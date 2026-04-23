-- ============================================================================
-- Elsewhere — Session lifecycle RPCs (core)
-- Migration: 009
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Session 5 Part 1b.1. Four SECURITY DEFINER RPCs that drive session start,
-- join, leave, and end. Operates on the schema from db/008.
--
-- See docs/SESSION-5-PLAN.md commit 2b40313 for the full architectural plan
-- and docs/SESSION-5-PLAN.md § Data model / RPCs for the target surface.
--
-- RPCs in this migration:
--   • rpc_session_start(tv_device_id, app, admission_mode, capacity,
--                       ask_proximity, turn_completion, room_code)
--                       → sessions
--   • rpc_session_join(session_id, participation_role='audience')
--                       → session_participants
--   • rpc_session_leave(session_id)
--                       → session_participants
--   • rpc_session_end(session_id)
--                       → sessions
--
-- NOT in this migration (shipped in Part 1b.2):
--   • rpc_session_transfer_manager
--   • rpc_session_reclaim_manager
--   • rpc_session_admin_reclaim
--   • rpc_session_update_participant
--   • rpc_session_update_queue_position
--   • rpc_session_promote_self_from_queue
--
-- Simplification vs. final plan (intentional, revisited in 1b.2):
-- rpc_session_leave raises an exception if the caller is the manager AND
-- other participants are still active. Final plan Decision 7 calls for
-- auto-promoting the manager role to the first host (or first non-audience
-- participant) when the manager leaves. That auto-promote logic lands in
-- 1b.2 alongside the transfer/reclaim RPCs. Until then, clients must call
-- rpc_session_transfer_manager (1b.2) or rpc_session_end (this file) to
-- clean up before a manager can leave.
--
-- Manifest values (admission_mode, capacity, ask_proximity, turn_completion)
-- are passed in by the caller at rpc_session_start and snapshotted onto the
-- sessions row. Subsequent manifest changes don't affect the live session —
-- see db/008's sessions table comment.
--
-- Idempotency: CREATE OR REPLACE FUNCTION throughout. Safe to re-run.
-- ============================================================================


-- ─── 1. rpc_session_start ─────────────────────────────────────────────────
-- Creates a new session on the given TV with the caller as initial manager.
-- The caller must be a household member of the TV's household. Only one
-- active session per TV is allowed — call rpc_session_end on an existing
-- session first (or use Part 1b.2's reclaim RPCs if the current manager
-- has gone inactive).
--
-- SECURITY DEFINER because direct INSERT on sessions / session_participants
-- is blocked by RLS (no write policies). The function performs the
-- authorization check explicitly via is_tv_household_member().
create or replace function public.rpc_session_start(
  p_tv_device_id    uuid,
  p_app             text,
  p_admission_mode  text,
  p_capacity        int,
  p_ask_proximity   boolean,
  p_turn_completion text,
  p_room_code       text default null
)
returns public.sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_session public.sessions;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if not public.is_tv_household_member(p_tv_device_id) then
    raise exception 'not a member of this TV''s household' using errcode = '42501';
  end if;

  -- Enforce "one active session per TV" with a clear error message.
  -- The sessions_one_active_per_tv unique partial index is a belt-and-
  -- suspenders fallback for concurrent inserts.
  if exists (
    select 1 from public.sessions
     where tv_device_id = p_tv_device_id and ended_at is null
  ) then
    raise exception 'an active session already exists on this TV'
      using errcode = '23505';
  end if;

  insert into public.sessions (
    tv_device_id, app, manager_user_id,
    admission_mode, capacity, ask_proximity, turn_completion, room_code
  )
  values (
    p_tv_device_id, p_app, v_user_id,
    p_admission_mode, p_capacity, p_ask_proximity, p_turn_completion, p_room_code
  )
  returning * into v_session;

  -- Initial manager's participant row. Manager's participation_role starts
  -- as 'audience' — they haven't committed to being an active participant
  -- yet. They can transition via rpc_session_update_participant (1b.2).
  insert into public.session_participants (
    session_id, user_id, control_role, participation_role
  )
  values (
    v_session.id, v_user_id, 'manager', 'audience'
  );

  return v_session;
end;
$$;

grant execute on function public.rpc_session_start(uuid, text, text, int, boolean, text, text) to authenticated;

comment on function public.rpc_session_start(uuid, text, text, int, boolean, text, text) is
  'Creates a new session on the given TV with the caller as initial manager. '
  'Caller must be a household member of the TV''s household. Raises if an '
  'active session already exists for this TV. Snapshots manifest values '
  '(admission_mode, capacity, ask_proximity, turn_completion) onto the '
  'sessions row. Inserts a session_participants row for the caller with '
  'control_role=''manager'' and participation_role=''audience''.';


-- ─── 2. rpc_session_join ──────────────────────────────────────────────────
-- Adds the caller as a participant in an existing session. Caller must be
-- a household member of the TV's household. If participation_role='queued',
-- the queue_position is assigned as max+1 across non-left queued rows.
--
-- To change roles after joining, use rpc_session_update_participant (1b.2).
-- This RPC raises if the caller already has an active row — not a silent
-- upsert — so callers can distinguish "joined now" from "was already in."
create or replace function public.rpc_session_join(
  p_session_id         uuid,
  p_participation_role text default 'audience'
)
returns public.session_participants
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id      uuid := auth.uid();
  v_session      public.sessions;
  v_new_position int;
  v_row          public.session_participants;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  select * into v_session from public.sessions where id = p_session_id;
  if v_session.id is null then
    raise exception 'session not found: %', p_session_id using errcode = '02000';
  end if;

  if v_session.ended_at is not null then
    raise exception 'session has ended' using errcode = '02000';
  end if;

  if not public.is_tv_household_member(v_session.tv_device_id) then
    raise exception 'not a member of this TV''s household' using errcode = '42501';
  end if;

  -- Reject re-join via this RPC. Role changes go through
  -- rpc_session_update_participant. The unique partial index
  -- session_participants_one_active_per_user is a fallback.
  if exists (
    select 1 from public.session_participants
     where session_id = p_session_id
       and user_id    = v_user_id
       and left_at   is null
  ) then
    raise exception 'already an active participant in this session; use rpc_session_update_participant to change roles'
      using errcode = '23505';
  end if;

  -- Queue position only for queued role. For active/audience, leave null.
  -- Computed across non-left queued rows; gaps from departed queuers are
  -- not filled (simpler; may revisit if gap growth becomes a real concern).
  if p_participation_role = 'queued' then
    select coalesce(max(queue_position), 0) + 1
      into v_new_position
      from public.session_participants
     where session_id     = p_session_id
       and left_at       is null
       and queue_position is not null;
  end if;

  insert into public.session_participants (
    session_id, user_id, control_role, participation_role, queue_position
  )
  values (
    p_session_id, v_user_id, 'none', p_participation_role, v_new_position
  )
  returning * into v_row;

  update public.sessions set last_activity_at = now() where id = p_session_id;

  return v_row;
end;
$$;

grant execute on function public.rpc_session_join(uuid, text) to authenticated;

comment on function public.rpc_session_join(uuid, text) is
  'Adds the caller as a participant in an existing session with control_role='
  '''none'' and the given participation_role (default ''audience''). Caller '
  'must be a household member of the TV''s household. Raises if session is '
  'ended, caller already has an active row, or participation_role fails the '
  'table check constraint. Assigns next FIFO queue_position when role=''queued''.';


-- ─── 3. rpc_session_leave ─────────────────────────────────────────────────
-- Sets left_at on the caller's active session_participants row. Manager
-- leaving logic (1b.1 simplification):
--   • Manager + other participants present → raise (must transfer or end)
--   • Manager alone                        → end session + mark all left
--   • Non-manager                          → mark left
--
-- Full plan Decision 7 auto-promote-on-manager-leave lands in 1b.2 and will
-- supersede the raise branch.
create or replace function public.rpc_session_leave(p_session_id uuid)
returns public.session_participants
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id     uuid := auth.uid();
  v_row         public.session_participants;
  v_other_count int;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- Find caller's active row. If none, nothing to leave.
  select * into v_row
    from public.session_participants
   where session_id = p_session_id
     and user_id    = v_user_id
     and left_at   is null;

  if v_row.id is null then
    raise exception 'not an active participant in session %', p_session_id
      using errcode = '02000';
  end if;

  if v_row.control_role = 'manager' then
    -- Count OTHER active participants in the session.
    select count(*) into v_other_count
      from public.session_participants
     where session_id = p_session_id
       and left_at   is null
       and user_id   <> v_user_id;

    if v_other_count > 0 then
      raise exception 'Manager cannot leave while other participants are active. Transfer manager role first or end the session.'
        using errcode = '42501';
    end if;

    -- Manager is alone: end the session. Mark all (this caller) left first
    -- so the "session ended ⇒ all participants left" invariant holds.
    update public.session_participants
       set left_at = now()
     where session_id = p_session_id
       and left_at   is null;

    update public.sessions
       set ended_at         = now(),
           last_activity_at = now()
     where id = p_session_id;

    -- Re-read caller's row to return its updated state.
    select * into v_row
      from public.session_participants
     where id = v_row.id;

    return v_row;
  end if;

  -- Non-manager: just set left_at on the caller's row.
  update public.session_participants
     set left_at = now()
   where id = v_row.id
  returning * into v_row;

  update public.sessions set last_activity_at = now() where id = p_session_id;

  return v_row;
end;
$$;

grant execute on function public.rpc_session_leave(uuid) to authenticated;

comment on function public.rpc_session_leave(uuid) is
  'Sets left_at on the caller''s active session_participants row. If the '
  'caller is the manager and other participants are active, raises (must '
  'transfer manager role or end session first). If the caller is the manager '
  'and alone, ends the session. Otherwise just marks the row left. Part '
  '1b.1 simplification: auto-promote logic (plan Decision 7) lands in 1b.2.';


-- ─── 4. rpc_session_end ───────────────────────────────────────────────────
-- Ends the session. Only the current manager may call. Sets ended_at on
-- the session and marks all still-active participants as left.
create or replace function public.rpc_session_end(p_session_id uuid)
returns public.sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_session public.sessions;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  select * into v_session from public.sessions where id = p_session_id;
  if v_session.id is null then
    raise exception 'session not found: %', p_session_id using errcode = '02000';
  end if;

  if v_session.ended_at is not null then
    raise exception 'session already ended' using errcode = '02000';
  end if;

  if v_session.manager_user_id <> v_user_id then
    raise exception 'only the current manager can end the session'
      using errcode = '42501';
  end if;

  -- Mark all still-active participants as left.
  update public.session_participants
     set left_at = now()
   where session_id = p_session_id
     and left_at   is null;

  -- End the session.
  update public.sessions
     set ended_at         = now(),
         last_activity_at = now()
   where id = p_session_id
  returning * into v_session;

  return v_session;
end;
$$;

grant execute on function public.rpc_session_end(uuid) to authenticated;

comment on function public.rpc_session_end(uuid) is
  'Ends the session. Only the current manager (sessions.manager_user_id) '
  'may call. Sets ended_at on the session and left_at on all still-active '
  'session_participants rows. Raises if the session is already ended or '
  'the caller is not the manager.';


-- ─── Verification ─────────────────────────────────────────────────────────
select 'migration 009 loaded' as status;
