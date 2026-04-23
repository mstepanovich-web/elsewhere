-- ============================================================================
-- Elsewhere — Role and queue mutation RPCs
-- Migration: 011
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Session 5 Part 1b.3. Three RPCs covering participant role changes,
-- manager-driven queue reordering, and self-promotion from queue for
-- self_join admission mode. Completes the RPC surface for Session 5
-- (excluding session_started's manifest-lookup follow-ups, which are
-- app-layer not schema-layer).
--
-- See docs/SESSION-5-PLAN.md commit 2b40313 for the full architectural plan.
--
-- RPCs in this migration:
--   • rpc_session_update_participant(session_id, user_id, control_role?,
--                                    participation_role?, pre_selections?)
--                                    → session_participants
--   • rpc_session_update_queue_position(session_id, user_id, new_position)
--                                       → session_participants
--   • rpc_session_promote_self_from_queue(session_id)
--                                         → session_participants
--
-- Key behaviors:
--
-- rpc_session_update_participant:
--   Nullable optional args — null means "don't change that field."
--   Field-by-field authorization:
--     • control_role: only manager/host may change; target value cannot be
--       'manager' (use reclaim instead); cannot demote a current manager.
--     • participation_role: manager/host can transition any user; users
--       can self-transition audience↔queued and active→audience only.
--       Non-manager/non-host changing another user is denied.
--       Capacity check fires when transitioning target into 'active'.
--     • pre_selections: manager/host OR target-is-caller.
--
-- rpc_session_update_queue_position:
--   Manager/host can set an existing queued participant's queue_position
--   to any integer ≥ 1. Duplicates and gaps are accepted per plan's naive
--   ordering model; the ordering query handles ties.
--
-- rpc_session_promote_self_from_queue:
--   Queued user auto-promotes themselves to active when session is in
--   self_join admission_mode AND capacity permits. Uses SELECT FOR UPDATE
--   to serialize concurrent self-promotions under capacity limits.
--
-- Error code conventions (consistent with db/006, db/009, db/010):
--   42501 — authentication / authorization failures
--   02000 — not found / state invalid
--   55000 — prerequisite state not met (capacity, admission_mode)
--   22023 — invalid parameter value (queue_position < 1)
--
-- Idempotency: CREATE OR REPLACE FUNCTION throughout. Safe to re-run.
-- ============================================================================


-- ─── 1. rpc_session_update_participant ────────────────────────────────────
-- Updates any subset of control_role, participation_role, or pre_selections
-- on a target participant. Null arguments mean "don't change that field."
-- Field-level authorization rules apply — see file-top summary.
--
-- When transitioning INTO participation_role='queued' from a non-queued
-- state, assigns queue_position = max+1 across non-left queued rows (FIFO).
-- Transitioning OUT of 'queued' clears queue_position. Staying queued keeps
-- the existing position.
create or replace function public.rpc_session_update_participant(
  p_session_id         uuid,
  p_user_id            uuid,
  p_control_role       text  default null,
  p_participation_role text  default null,
  p_pre_selections     jsonb default null
)
returns public.session_participants
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id            uuid := auth.uid();
  v_session            public.sessions;
  v_caller             public.session_participants;
  v_target             public.session_participants;
  v_active_count       int;
  v_new_queue_position int;
  v_row                public.session_participants;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- Session validity.
  select * into v_session from public.sessions where id = p_session_id;
  if v_session.id is null then
    raise exception 'session not found: %', p_session_id using errcode = '02000';
  end if;

  if v_session.ended_at is not null then
    raise exception 'session has ended' using errcode = '02000';
  end if;

  -- Caller must have an active row.
  select * into v_caller
    from public.session_participants
   where session_id = p_session_id
     and user_id    = v_user_id
     and left_at   is null;

  if v_caller.id is null then
    raise exception 'not an active participant in session %', p_session_id
      using errcode = '42501';
  end if;

  -- Target must have an active row.
  select * into v_target
    from public.session_participants
   where session_id = p_session_id
     and user_id    = p_user_id
     and left_at   is null;

  if v_target.id is null then
    raise exception 'target user % is not an active participant in session %',
                    p_user_id, p_session_id
      using errcode = '02000';
  end if;

  -- ── Authorization: control_role changes ────────────────────────────
  if p_control_role is not null then
    if v_caller.control_role not in ('manager', 'host') then
      raise exception 'only manager or host can change control_role'
        using errcode = '42501';
    end if;

    if p_control_role = 'manager' then
      raise exception 'manager role cannot be assigned via this RPC; use reclaim or auto-promote via leave'
        using errcode = '42501';
    end if;

    if v_target.control_role = 'manager' then
      raise exception 'cannot change the manager''s control_role via this RPC; use rpc_session_leave or reclaim'
        using errcode = '42501';
    end if;
    -- At this point p_control_role in ('host', 'none') and
    -- target.control_role in ('host', 'none') — transition is allowed.
  end if;

  -- ── Authorization: participation_role changes ───────────────────────
  if p_participation_role is not null then
    if v_caller.control_role in ('manager', 'host') then
      -- Manager/host: any transition allowed. No further checks (beyond capacity below).
      null;
    elsif v_user_id = p_user_id then
      -- Self-transition rules:
      --   audience → queued:   ALLOW
      --   queued   → audience: ALLOW
      --   active   → audience: ALLOW (step off stage voluntarily)
      --   anything else:       DENY
      if not (
        (v_target.participation_role = 'audience' and p_participation_role = 'queued')
        or (v_target.participation_role = 'queued' and p_participation_role = 'audience')
        or (v_target.participation_role = 'active' and p_participation_role = 'audience')
      ) then
        raise exception 'not authorized to transition own participation_role from % to % (only manager or host can promote to active)',
                        v_target.participation_role, p_participation_role
          using errcode = '42501';
      end if;
    else
      -- Not manager/host AND target is another user — deny.
      raise exception 'only manager or host can change another user''s participation_role'
        using errcode = '42501';
    end if;

    -- Capacity check: applies to ANY transition into 'active' regardless of caller.
    -- Count current active participants excluding the target (if target is
    -- already active, they're not adding to the count; if target is not
    -- already active, the exclusion is a no-op).
    if p_participation_role = 'active' and v_session.capacity is not null then
      select count(*) into v_active_count
        from public.session_participants
       where session_id         = p_session_id
         and left_at            is null
         and participation_role = 'active'
         and user_id            <> p_user_id;

      if v_active_count >= v_session.capacity then
        raise exception 'session at capacity' using errcode = '55000';
      end if;
    end if;
  end if;

  -- ── Authorization: pre_selections changes ───────────────────────────
  if p_pre_selections is not null then
    if v_caller.control_role not in ('manager', 'host')
       and v_user_id <> p_user_id then
      raise exception 'only manager, host, or the target user may update pre_selections'
        using errcode = '42501';
    end if;
  end if;

  -- ── Compute queue_position ──────────────────────────────────────────
  -- Transitions that affect queue_position:
  --   • null p_participation_role          → no change
  --   • non-queued → queued                → assign max+1
  --   • queued → queued (no real change)   → keep existing position
  --   • any → non-queued                   → null
  if p_participation_role is null then
    v_new_queue_position := v_target.queue_position;
  elsif p_participation_role = 'queued' and v_target.queue_position is null then
    select coalesce(max(queue_position), 0) + 1
      into v_new_queue_position
      from public.session_participants
     where session_id     = p_session_id
       and left_at       is null
       and queue_position is not null;
  elsif p_participation_role = 'queued' then
    v_new_queue_position := v_target.queue_position;
  else
    v_new_queue_position := null;
  end if;

  -- ── Apply the update ────────────────────────────────────────────────
  -- COALESCE preserves existing value when the corresponding arg is null.
  update public.session_participants
     set control_role       = coalesce(p_control_role, control_role),
         participation_role = coalesce(p_participation_role, participation_role),
         pre_selections     = coalesce(p_pre_selections, pre_selections),
         queue_position     = v_new_queue_position
   where id = v_target.id
  returning * into v_row;

  update public.sessions set last_activity_at = now() where id = p_session_id;

  return v_row;
end;
$$;

grant execute on function public.rpc_session_update_participant(uuid, uuid, text, text, jsonb) to authenticated;

comment on function public.rpc_session_update_participant(uuid, uuid, text, text, jsonb) is
  'Updates any subset of control_role, participation_role, or pre_selections '
  'for a target participant. Null args mean "don''t change." Field-level '
  'authorization: control_role and cross-user participation_role require '
  'manager/host; self-transitions are audience↔queued + active→audience '
  'only; pre_selections require manager/host or target-is-caller. Capacity '
  'check (errcode 55000) applies when transitioning into ''active''. '
  'Assigning control_role=''manager'' is forbidden (use reclaim). Changing '
  'the current manager''s control_role is forbidden (use leave/reclaim). '
  'To clear pre_selections, callers must pass ''{}''::jsonb explicitly; '
  'passing SQL NULL leaves the existing value unchanged. All-null arg call '
  'succeeds as a no-op heartbeat (bumps sessions.last_activity_at).';


-- ─── 2. rpc_session_update_queue_position ─────────────────────────────────
-- Manager/host reorders the queue by setting a specific queued participant's
-- queue_position to a new integer (>= 1). Naive approach — accepts
-- duplicate and gapped positions; FIFO read query resolves ties. If gap
-- growth or collision handling becomes a real problem, the plan's Open
-- Question on queue position recalculation covers the follow-up refactor.
create or replace function public.rpc_session_update_queue_position(
  p_session_id   uuid,
  p_user_id      uuid,
  p_new_position int
)
returns public.session_participants
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_session public.sessions;
  v_caller  public.session_participants;
  v_target  public.session_participants;
  v_row     public.session_participants;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if p_new_position is null or p_new_position < 1 then
    raise exception 'queue_position must be >= 1' using errcode = '22023';
  end if;

  select * into v_session from public.sessions where id = p_session_id;
  if v_session.id is null then
    raise exception 'session not found: %', p_session_id using errcode = '02000';
  end if;

  if v_session.ended_at is not null then
    raise exception 'session has ended' using errcode = '02000';
  end if;

  -- Caller authorization.
  select * into v_caller
    from public.session_participants
   where session_id = p_session_id
     and user_id    = v_user_id
     and left_at   is null;

  if v_caller.id is null then
    raise exception 'not an active participant in session %', p_session_id
      using errcode = '42501';
  end if;

  if v_caller.control_role not in ('manager', 'host') then
    raise exception 'only manager or host can reorder the queue'
      using errcode = '42501';
  end if;

  -- Target must be queued.
  select * into v_target
    from public.session_participants
   where session_id         = p_session_id
     and user_id            = p_user_id
     and left_at            is null
     and participation_role = 'queued';

  if v_target.id is null then
    raise exception 'target user % is not currently queued in session %',
                    p_user_id, p_session_id
      using errcode = '02000';
  end if;

  update public.session_participants
     set queue_position = p_new_position
   where id = v_target.id
  returning * into v_row;

  update public.sessions set last_activity_at = now() where id = p_session_id;

  return v_row;
end;
$$;

grant execute on function public.rpc_session_update_queue_position(uuid, uuid, int) to authenticated;

comment on function public.rpc_session_update_queue_position(uuid, uuid, int) is
  'Manager or host sets an existing queued participant''s queue_position. '
  'Accepts duplicate and gapped positions (ties resolved by the ordering '
  'query''s secondary sort). Target must currently have participation_role='
  '''queued''. p_new_position must be >= 1.';


-- ─── 3. rpc_session_promote_self_from_queue ───────────────────────────────
-- Caller (who must be queued) promotes themselves from queue to active.
-- Only valid in self_join admission_mode. Uses SELECT ... FOR UPDATE on the
-- sessions row to serialize concurrent self-promotions — capacity checks
-- against a consistent snapshot without racing.
create or replace function public.rpc_session_promote_self_from_queue(
  p_session_id uuid
)
returns public.session_participants
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id      uuid := auth.uid();
  v_session      public.sessions;
  v_caller       public.session_participants;
  v_active_count int;
  v_row          public.session_participants;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- Row-level lock on sessions to serialize capacity checks across concurrent
  -- self-promotions. Other RPCs on unrelated sessions are unaffected.
  select * into v_session from public.sessions where id = p_session_id for update;

  if v_session.id is null then
    raise exception 'session not found: %', p_session_id using errcode = '02000';
  end if;

  if v_session.ended_at is not null then
    raise exception 'session has ended' using errcode = '02000';
  end if;

  if v_session.admission_mode <> 'self_join' then
    raise exception 'this RPC is only valid for self_join admission mode'
      using errcode = '42501';
  end if;

  -- Caller must currently be queued.
  select * into v_caller
    from public.session_participants
   where session_id = p_session_id
     and user_id    = v_user_id
     and left_at   is null;

  if v_caller.id is null then
    raise exception 'not an active participant in session %', p_session_id
      using errcode = '42501';
  end if;

  if v_caller.participation_role <> 'queued' then
    raise exception 'only queued participants can self-promote (current role: %)',
                    v_caller.participation_role
      using errcode = '42501';
  end if;

  -- Capacity check. Caller is transitioning from queued → active, so a
  -- successful promotion would add 1 to the active count.
  if v_session.capacity is not null then
    select count(*) into v_active_count
      from public.session_participants
     where session_id         = p_session_id
       and left_at            is null
       and participation_role = 'active';

    if v_active_count >= v_session.capacity then
      raise exception 'session at capacity' using errcode = '55000';
    end if;
  end if;

  -- Promote.
  update public.session_participants
     set participation_role = 'active',
         queue_position     = null
   where id = v_caller.id
  returning * into v_row;

  update public.sessions set last_activity_at = now() where id = p_session_id;

  return v_row;
end;
$$;

grant execute on function public.rpc_session_promote_self_from_queue(uuid) to authenticated;

comment on function public.rpc_session_promote_self_from_queue(uuid) is
  'Queued caller auto-promotes themselves to participation_role=''active''. '
  'Only valid when session.admission_mode=''self_join''. Serializes concurrent '
  'promotions via SELECT FOR UPDATE on the sessions row. Enforces capacity '
  '(errcode 55000 when session.capacity is not null and already at limit). '
  'Clears queue_position on success.';


-- ─── Verification ─────────────────────────────────────────────────────────
select 'migration 011 loaded' as status;
