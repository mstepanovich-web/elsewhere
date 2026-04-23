-- ============================================================================
-- Elsewhere — Manager mechanics RPCs
-- Migration: 010
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Session 5 Part 1b.2. Three RPCs: two new reclaim functions, plus an
-- updated rpc_session_leave that adds auto-promote-on-manager-leave logic
-- per plan Decision 7. Operates on the schema from db/008 and replaces
-- the rpc_session_leave shipped in db/009.
--
-- See docs/SESSION-5-PLAN.md commit 2b40313 for the full architectural plan.
--
-- RPCs in this migration:
--   • rpc_session_reclaim_manager(session_id) → sessions
--       Any household member can reclaim an orphaned session
--       (last_activity_at >= now() - 10 min raises as "still active").
--   • rpc_session_admin_reclaim(session_id) → sessions
--       Household admin can force-reclaim any time; no inactivity check.
--   • rpc_session_leave(session_id) → session_participants  [REPLACES db/009]
--       Manager-with-others-active no longer raises. Auto-promotes the
--       first eligible user to manager per plan Decision 7:
--         1. First active host (by joined_at asc), OR
--         2. First active non-audience participant (active/queued), OR
--         3. If none eligible: session ends (mark all left, set ended_at).
--       Audience-only participants are NOT promoted — audience has declared
--       they're not participating; promoting would violate that stated intent.
--
-- NOT in this migration (shipped in Part 1b.3 or later):
--   • rpc_session_update_participant
--   • rpc_session_update_queue_position
--   • rpc_session_promote_self_from_queue
--
-- Revised scope vs. original plan (locked in Part 1b.2):
-- Original plan Decision 7 included rpc_session_transfer_manager (explicit
-- user-facing manager transfer). Removed from scope: manager transfer
-- happens automatically via auto-promote-on-leave. Not user-facing.
-- Simplifies the surface area and eliminates one UI concept.
--
-- Error code additions:
--   • 55000 (object_not_in_prerequisite_state) — used by
--     rpc_session_reclaim_manager when the session is still active
--     (inactivity threshold not met). New to this codebase; semantically
--     correct per PostgreSQL standard.
--
-- Idempotency: CREATE OR REPLACE FUNCTION throughout (including the
-- rpc_session_leave replacement of db/009's version). Safe to re-run.
-- ============================================================================


-- ─── 1. rpc_session_reclaim_manager ───────────────────────────────────────
-- Any household member of the TV's household may reclaim a session whose
-- manager has been inactive for >= 10 minutes. Demotes the current manager
-- (control_role → 'none', row NOT marked left — they may still return as
-- a participant), promotes the caller, and updates sessions.manager_user_id.
--
-- If the caller is already an active participant in the session, their row
-- is updated in place (control_role → 'manager'; participation_role
-- unchanged). If they are NOT already a participant, a new row is inserted
-- with participation_role='audience'.
--
-- Self-reclaim by the current manager is a no-op semantically but still
-- runs the demote-then-promote cycle and bumps last_activity_at — useful
-- as a heartbeat if the RPC is occasionally invoked that way.
--
-- SECURITY DEFINER — direct writes on sessions / session_participants are
-- blocked by RLS. Authorization is enforced explicitly via
-- is_tv_household_member().
create or replace function public.rpc_session_reclaim_manager(p_session_id uuid)
returns public.sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id    uuid := auth.uid();
  v_session    public.sessions;
  v_caller_row public.session_participants;
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

  -- Inactivity check: spec says reclaim allowed when
  -- last_activity_at < now() - interval '10 minutes'.
  -- So raise when last_activity_at >= that threshold (still "within 10 min").
  if v_session.last_activity_at >= now() - interval '10 minutes' then
    raise exception 'session is still active (last activity %); only orphaned sessions can be reclaimed',
                    v_session.last_activity_at
      using errcode = '55000';
  end if;

  -- Demote current manager. Drive off the unique-partial-index invariant
  -- (control_role='manager' + left_at is null → at most one row) rather
  -- than sessions.manager_user_id, so this is resilient to denormalization
  -- desync. No-op if the session has no active manager row (e.g., prior
  -- bug left things inconsistent — we'll still proceed and fix it here).
  update public.session_participants
     set control_role = 'none'
   where session_id    = p_session_id
     and control_role  = 'manager'
     and left_at      is null;

  -- Look up caller's active row, if any.
  select * into v_caller_row
    from public.session_participants
   where session_id = p_session_id
     and user_id    = v_user_id
     and left_at   is null;

  if v_caller_row.id is null then
    -- Caller not yet a participant. Insert as manager-audience.
    insert into public.session_participants (
      session_id, user_id, control_role, participation_role
    )
    values (
      p_session_id, v_user_id, 'manager', 'audience'
    );
  else
    -- Caller already participant — promote to manager; keep their
    -- participation_role unchanged.
    update public.session_participants
       set control_role = 'manager'
     where id = v_caller_row.id;
  end if;

  update public.sessions
     set manager_user_id   = v_user_id,
         last_activity_at  = now()
   where id = p_session_id
  returning * into v_session;

  return v_session;
end;
$$;

grant execute on function public.rpc_session_reclaim_manager(uuid) to authenticated;

comment on function public.rpc_session_reclaim_manager(uuid) is
  'Any household member of the TV''s household reclaims an orphaned session '
  '(last_activity_at >= now() - 10 min raises). Demotes current manager to '
  'control_role=''none'' without marking their row left, then promotes the '
  'caller. If caller is not yet a participant, inserts a new row with '
  'participation_role=''audience''. Updates sessions.manager_user_id and '
  'last_activity_at. Errcode 55000 (object_not_in_prerequisite_state) when '
  'inactivity threshold not met.';


-- ─── 2. rpc_session_admin_reclaim ─────────────────────────────────────────
-- Household admin of the TV's household force-reclaims a session. Same
-- demote-then-promote mechanics as rpc_session_reclaim_manager but without
-- the inactivity check — admin can reclaim an actively-managed session.
-- The "head of household yanks the remote" escape hatch.
--
-- Uses is_session_tv_household_admin() from db/008 (defined but unused by
-- migration 008's RLS policies — retained for this RPC per its comment).
create or replace function public.rpc_session_admin_reclaim(p_session_id uuid)
returns public.sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id    uuid := auth.uid();
  v_session    public.sessions;
  v_caller_row public.session_participants;
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

  if not public.is_session_tv_household_admin(p_session_id) then
    raise exception 'not a household admin of this TV''s household'
      using errcode = '42501';
  end if;

  -- Demote current manager (no-op if none active — see note in
  -- rpc_session_reclaim_manager).
  update public.session_participants
     set control_role = 'none'
   where session_id    = p_session_id
     and control_role  = 'manager'
     and left_at      is null;

  -- Look up caller's active row, if any.
  select * into v_caller_row
    from public.session_participants
   where session_id = p_session_id
     and user_id    = v_user_id
     and left_at   is null;

  if v_caller_row.id is null then
    insert into public.session_participants (
      session_id, user_id, control_role, participation_role
    )
    values (
      p_session_id, v_user_id, 'manager', 'audience'
    );
  else
    update public.session_participants
       set control_role = 'manager'
     where id = v_caller_row.id;
  end if;

  update public.sessions
     set manager_user_id   = v_user_id,
         last_activity_at  = now()
   where id = p_session_id
  returning * into v_session;

  return v_session;
end;
$$;

grant execute on function public.rpc_session_admin_reclaim(uuid) to authenticated;

comment on function public.rpc_session_admin_reclaim(uuid) is
  'Household admin of the TV''s household force-reclaims a session regardless '
  'of inactivity. Same demote-then-promote mechanics as '
  'rpc_session_reclaim_manager without the inactivity check. "Head of '
  'household yanks the remote" escape hatch.';


-- ─── 3. rpc_session_leave (UPDATED — auto-promote on manager leave) ───────
-- Replaces the db/009 version. The previous "manager cannot leave while
-- others active" raise is replaced with plan Decision 7's auto-promote
-- logic:
--   • Try to find a host (control_role='host', left_at is null), oldest
--     by joined_at, to promote.
--   • Fall back to first active/queued participant, oldest by joined_at.
--     Audience-only participants are not eligible — they've declared
--     they're not participating; promoting them violates stated intent.
--   • If no eligible promotee, the session ends (mark all remaining
--     participants left, set sessions.ended_at).
--
-- "Manager alone" and "only audience remain" collapse into the same
-- "no promotable found" branch — both end the session.
--
-- Order of operations in the promote branch matters: the leaving manager's
-- row must have left_at set BEFORE the promotable user's control_role is
-- changed to 'manager'. Otherwise the unique partial index
-- session_participants_one_manager (control_role='manager' where
-- left_at is null) is momentarily violated.
create or replace function public.rpc_session_leave(p_session_id uuid)
returns public.session_participants
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id    uuid := auth.uid();
  v_row        public.session_participants;
  v_promotable public.session_participants;
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
    -- First preference: oldest active host (excluding the leaving manager
    -- defensively; host control_role shouldn't match 'manager' but guards
    -- against any invariant desync).
    select * into v_promotable
      from public.session_participants
     where session_id   = p_session_id
       and left_at     is null
       and control_role = 'host'
       and user_id     <> v_user_id
     order by joined_at asc
     limit 1;

    -- Fallback: oldest active non-audience participant. Exclude the
    -- leaving manager — if their participation_role is 'active' or
    -- 'queued', this query would otherwise match them.
    if v_promotable.id is null then
      select * into v_promotable
        from public.session_participants
       where session_id         = p_session_id
         and left_at            is null
         and participation_role in ('active', 'queued')
         and user_id            <> v_user_id
       order by joined_at asc
       limit 1;
    end if;

    if v_promotable.id is not null then
      -- Auto-promote. Mark the leaving manager's row left FIRST to clear
      -- the unique-partial-index slot for control_role='manager'.
      update public.session_participants
         set left_at = now()
       where id = v_row.id
      returning * into v_row;

      update public.session_participants
         set control_role = 'manager'
       where id = v_promotable.id;

      update public.sessions
         set manager_user_id   = v_promotable.user_id,
             last_activity_at  = now()
       where id = p_session_id;

      return v_row;
    end if;

    -- No eligible promotee (manager alone OR only audience remain).
    -- End the session. Mark all active rows left (including the caller's).
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

-- GRANT already exists from db/009; CREATE OR REPLACE FUNCTION preserves
-- privileges, so no need to re-grant. Explicit regrant included defensively.
grant execute on function public.rpc_session_leave(uuid) to authenticated;

comment on function public.rpc_session_leave(uuid) is
  'Sets left_at on the caller''s active session_participants row. If caller '
  'is the manager, auto-promotes per plan Decision 7: first active host by '
  'joined_at, then first active non-audience participant. Audience-only '
  'participants are not eligible. If no eligible promotee, the session ends. '
  'Non-manager leave just marks the row left. Replaces db/009 version '
  '(which raised when manager had other active participants).';


-- ─── Verification ─────────────────────────────────────────────────────────
select 'migration 010 loaded' as status;
