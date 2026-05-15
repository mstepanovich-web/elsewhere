-- ============================================================================
-- Elsewhere — rpc_session_update_participant + wanting_since handling
-- Migration: 022
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Implements part of work item W4 from docs/ADMISSION-MODEL-V2.md § 10.
-- CREATE OR REPLACE on rpc_session_update_participant (originally defined
-- in db/011) to start populating the wanting_since column added by db/020.
--
-- BEHAVIORAL CHANGE — wanting_since handling:
--
--   • Transition INTO participation_role='queued' from a non-queued source
--     → SET wanting_since = now() in the same UPDATE.
--   • Transition OUT of participation_role='queued' to any other role
--     → SET wanting_since = NULL.
--   • Staying at 'queued' (no role change, or queued → queued)
--     → keep existing wanting_since unchanged.
--   • p_participation_role IS NULL (no role change requested)
--     → keep existing wanting_since unchanged.
--
-- This mirrors the existing queue_position handling pattern in the
-- function (db/011:198-217). The two columns are now updated together
-- inside the same UPDATE statement.
--
-- BEHAVIOR PRESERVED — everything else stays identical to db/011's
-- definition:
--
--   • Manager/host can transition any user; users can self-transition
--     audience↔queued and active→audience only.
--   • Capacity check fires on transition into 'active' (errcode 55000).
--   • queue_position auto-assignment on transition to 'queued' (max+1).
--   • queue_position cleared on transition away from 'queued'.
--   • pre_selections + control_role rules unchanged.
--   • Bumps sessions.last_activity_at on success.
--
-- Idempotency: CREATE OR REPLACE FUNCTION. Safe to re-run.
--
-- See db/011 for the original definition and the full behavioral spec.
-- See db/020 for the wanting_since column addition.
-- See docs/ADMISSION-MODEL-V2.md § 3.4 for the wanting_since semantics
-- (queued ordering by wanting_since ASC).
-- ============================================================================

begin;

-- ─── 1. rpc_session_update_participant (with wanting_since handling) ───────
-- See db/011 for the original. This version adds wanting_since column
-- write semantics matching the queue_position pattern (lines 198-217 + 225
-- of db/011).
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
  v_new_wanting_since  timestamptz;
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
  end if;

  -- ── Authorization: participation_role changes ───────────────────────
  if p_participation_role is not null then
    if v_caller.control_role in ('manager', 'host') then
      null;
    elsif v_user_id = p_user_id then
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
      raise exception 'only manager or host can change another user''s participation_role'
        using errcode = '42501';
    end if;

    -- Capacity check: applies to ANY transition into 'active' regardless of caller.
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

  -- ── Compute queue_position (unchanged from db/011) ──────────────────
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

  -- ── Compute wanting_since (NEW in db/022) ───────────────────────────
  -- Parallel to queue_position semantics:
  --   • null p_participation_role            → no change
  --   • non-queued → queued                  → set now()
  --   • queued → queued (no real change)     → keep existing wanting_since
  --   • any → non-queued                     → null
  if p_participation_role is null then
    v_new_wanting_since := v_target.wanting_since;
  elsif p_participation_role = 'queued' and v_target.participation_role <> 'queued' then
    v_new_wanting_since := now();
  elsif p_participation_role = 'queued' then
    v_new_wanting_since := v_target.wanting_since;
  else
    v_new_wanting_since := null;
  end if;

  -- ── Apply the update ────────────────────────────────────────────────
  update public.session_participants
     set control_role       = coalesce(p_control_role, control_role),
         participation_role = coalesce(p_participation_role, participation_role),
         pre_selections     = coalesce(p_pre_selections, pre_selections),
         queue_position     = v_new_queue_position,
         wanting_since      = v_new_wanting_since
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
  'queue_position auto-set on transition to ''queued'' (max+1), cleared on '
  'transition away. wanting_since (db/020) set to now() on transition to '
  '''queued'' from non-queued source, cleared on transition away, preserved '
  'when staying queued (db/022 W4 addition). All-null arg call succeeds as '
  'a no-op heartbeat (bumps sessions.last_activity_at).';

commit;

-- ─── Verification ─────────────────────────────────────────────────────────
select 'migration 022 loaded' as status;

-- ============================================================================
-- POST-MIGRATION VERIFICATION
--
-- After applying, run these checks against prod via Supabase SQL editor:
--
-- -- Function definition shows the new wanting_since write paths.
-- SELECT pg_get_functiondef(oid)
--   FROM pg_proc
--  WHERE proname = 'rpc_session_update_participant';
-- --   Expect: function body includes both `v_new_queue_position` and
-- --           `v_new_wanting_since` declarations + computes + the UPDATE
-- --           writes both columns.
--
-- -- Smoke test: insert a test queued participant transition + confirm
-- -- wanting_since is set. Replace <session_id> + <user_id> with real IDs
-- -- for a session you manage with a participant in 'audience' role.
-- SELECT * FROM rpc_session_update_participant(
--   '<session_id>'::uuid,
--   '<user_id>'::uuid,
--   p_participation_role := 'queued'
-- );
-- SELECT participation_role, queue_position, wanting_since
--   FROM session_participants
--  WHERE session_id = '<session_id>'::uuid AND user_id = '<user_id>'::uuid;
-- --   Expect: participation_role='queued', queue_position >= 1,
-- --           wanting_since within the last few seconds (now()).
--
-- -- Flip back to audience, confirm wanting_since cleared.
-- SELECT * FROM rpc_session_update_participant(
--   '<session_id>'::uuid,
--   '<user_id>'::uuid,
--   p_participation_role := 'audience'
-- );
-- SELECT participation_role, queue_position, wanting_since
--   FROM session_participants
--  WHERE session_id = '<session_id>'::uuid AND user_id = '<user_id>'::uuid;
-- --   Expect: participation_role='audience', queue_position=NULL,
-- --           wanting_since=NULL.
--
-- -- Confirm staying queued preserves wanting_since.
-- -- (Run two queued transitions back-to-back; second should be a no-op on
-- -- both queue_position and wanting_since since the role didn't change.)
-- SELECT * FROM rpc_session_update_participant(
--   '<session_id>'::uuid,
--   '<user_id>'::uuid,
--   p_participation_role := 'queued'
-- );
-- -- Note the wanting_since value, wait 2 seconds, then:
-- SELECT * FROM rpc_session_update_participant(
--   '<session_id>'::uuid,
--   '<user_id>'::uuid,
--   p_pre_selections := '{}'::jsonb  -- any no-op-on-role call
-- );
-- SELECT wanting_since FROM session_participants
--  WHERE session_id = '<session_id>'::uuid AND user_id = '<user_id>'::uuid;
-- --   Expect: same wanting_since timestamp as the first call (preserved).
-- ============================================================================
