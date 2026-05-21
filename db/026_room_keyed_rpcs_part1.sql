-- ============================================================================
-- Elsewhere — Phase 1 RPC migration, batch 1 of 3: room-keyed re-points
-- Migration: 026
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Repairs 10 of the 14 session-keyed RPCs that db/025 left broken at
-- runtime (their bodies filter session_participants by session_id, the
-- column db/025 dropped). After this migration, those 10 RPCs work
-- against the new room-keyed schema. Built against
-- docs/PHASE-1-BUILD-SPEC.md §D as amended by commit fcc42f6.
--
-- Three-migration grouping:
--   db/026 (THIS FILE) — 8 mechanical + rpc_session_end +
--                        rpc_session_set_admission_mode.
--   db/027            — rpc_session_start split + new rpc_room_create.
--   db/028            — rpc_session_leave + rpc_session_reclaim_manager +
--                        rpc_session_admin_reclaim.
--
-- The 10 RPCs in this file:
--   Mechanical re-points (8):
--     1. rpc_session_join                      (latest: db/009)
--     2. rpc_session_update_participant        (latest: db/022)
--     3. rpc_session_update_queue_position     (latest: db/011)
--     4. rpc_session_remove_participant        (latest: db/016)
--     5. rpc_session_set_my_participation_role (latest: db/017)
--     6. rpc_session_get_participants          (latest: db/023; DROP+CREATE)
--     7. rpc_session_heartbeat                 (latest: db/024)
--     8. rpc_karaoke_song_ended                (latest: db/013;
--                                                FOR UPDATE locks the
--                                                current session under
--                                                the room per §D)
--   Low-risk semantic (2):
--     9. rpc_session_end                       — participant sweep STOPS;
--                                                auth reroutes through
--                                                rooms.controller_user_id
--                                                (forced by db/025's
--                                                drop of
--                                                sessions.manager_user_id).
--    10. rpc_session_set_admission_mode        — stays session-scoped;
--                                                only manager-auth check
--                                                changes (to
--                                                rooms.controller_user_id
--                                                via sessions.room_id).
--
-- §D Cross-cutting decisions applied:
--   Activity-timestamp target — every RPC that bumps activity MUST bump
--   rooms.last_activity_at (required for the reclaim 10-min inactivity
--   gate) and SHOULD bump sessions.last_activity_at on the room's
--   active session (no-op if none). Applies to RPCs 1, 2, 3, 4, 5, 8, 9,
--   10. RPC 6 (get_participants) and RPC 7 (heartbeat) are read-only /
--   non-bumping per §D — heartbeat updates session_participants
--   .last_seen_at but not room/session activity (the 20s heartbeat would
--   defeat the reclaim gate).
--
-- Out of scope (DO NOT write here): rpc_session_start, rpc_room_create,
-- rpc_session_leave, rpc_session_reclaim_manager,
-- rpc_session_admin_reclaim — those land in db/027 and db/028.
-- fire_promotion_push + trigger recreation tracked in §D for a later
-- migration pending the iOS-app audit on payload shape.
--
-- Compat-wrapper note (OQ4): RPCs 6 and 8 previously called
-- is_session_participant / is_session_tv_household_member (compat
-- wrappers in db/025 step 12). The new bodies call the room-keyed
-- helpers (is_room_participant / is_room_tv_household_member) DIRECTLY,
-- not the compat wrappers. The compat wrappers remain defined per OQ4
-- and will be dropped in a Phase-1.1 cleanup after a grep-confirmed
-- zero-caller check.
--
-- Migration-window edge case (deliberate, bounded): between this
-- migration (db/026) and db/028, rooms.controller_user_id has no
-- transfer-writer. db/027 introduces rpc_room_create as the only
-- writer; the reclaim and leave RPCs that would otherwise transfer
-- controller_user_id are not rewritten until db/028. As a consequence,
-- between db/026 and db/028 only the original convener of a room can
-- end a session in that room (rpc_session_end and
-- rpc_session_set_admission_mode both authorize against
-- rooms.controller_user_id, which is fixed at room creation during
-- this window). This is acceptable per the "session and participant
-- data is ephemeral and pre-launch" cutover framing — the window is
-- short, no real users are exposed to it, and the behavior fully
-- resolves once db/028 lands.
--
-- Idempotency: CREATE OR REPLACE FUNCTION for 9 of 10; DROP+CREATE for
-- rpc_session_get_participants. Safe to re-run.
--
-- Transaction wrapping: BEGIN / COMMIT envelope. If any RPC's CREATE
-- fails, the entire migration rolls back.
-- ============================================================================


begin;


-- ─── 1. rpc_session_join (M1) ────────────────────────────────────────────
create or replace function public.rpc_session_join(
  p_room_id            uuid,
  p_participation_role text default 'audience'
)
returns public.session_participants
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id      uuid := auth.uid();
  v_room         public.rooms;
  v_new_position int;
  v_row          public.session_participants;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then
    raise exception 'room not found: %', p_room_id using errcode = '02000';
  end if;

  if v_room.ended_at is not null then
    raise exception 'room has ended' using errcode = '02000';
  end if;

  if not public.is_room_tv_household_member(p_room_id) then
    raise exception 'not a member of this room''s TV household'
      using errcode = '42501';
  end if;

  if exists (
    select 1 from public.session_participants
     where room_id  = p_room_id
       and user_id  = v_user_id
       and left_at is null
  ) then
    raise exception 'already an active participant in this room; use rpc_session_update_participant to change roles'
      using errcode = '23505';
  end if;

  -- Queue position only for queued role. Gaps from departed queuers
  -- are not filled (unchanged from db/009's mechanic + its rationale).
  if p_participation_role = 'queued' then
    select coalesce(max(queue_position), 0) + 1
      into v_new_position
      from public.session_participants
     where room_id        = p_room_id
       and left_at       is null
       and queue_position is not null;
  end if;

  insert into public.session_participants (
    room_id, user_id, control_role, participation_role, queue_position
  )
  values (
    p_room_id, v_user_id, 'none', p_participation_role, v_new_position
  )
  returning * into v_row;

  update public.rooms set last_activity_at = now() where id = p_room_id;
  update public.sessions set last_activity_at = now()
   where room_id = p_room_id and ended_at is null;

  return v_row;
end;
$$;

grant execute on function public.rpc_session_join(uuid, text) to authenticated;

comment on function public.rpc_session_join(uuid, text) is
  'Adds caller as a participant in the given room with '
  'control_role=''none''. Caller must be a household member of the '
  'room''s TV''s household. Raises if room ended, caller already active, '
  'or role fails the table check. Assigns next FIFO queue_position when '
  'role=''queued''. Bumps rooms.last_activity_at and the room''s active '
  'sessions.last_activity_at (if any).';


-- ─── 2. rpc_session_update_participant (M2) ──────────────────────────────
create or replace function public.rpc_session_update_participant(
  p_room_id            uuid,
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
  v_room               public.rooms;
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

  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then
    raise exception 'room not found: %', p_room_id using errcode = '02000';
  end if;

  if v_room.ended_at is not null then
    raise exception 'room has ended' using errcode = '02000';
  end if;

  -- Current session under the room (may be null between sessions).
  select * into v_session
    from public.sessions
   where room_id = p_room_id
     and ended_at is null;

  select * into v_caller
    from public.session_participants
   where room_id = p_room_id
     and user_id = v_user_id
     and left_at is null;

  if v_caller.id is null then
    raise exception 'not an active participant in room %', p_room_id
      using errcode = '42501';
  end if;

  select * into v_target
    from public.session_participants
   where room_id = p_room_id
     and user_id = p_user_id
     and left_at is null;

  if v_target.id is null then
    raise exception 'target user % is not an active participant in room %',
                    p_user_id, p_room_id
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

    -- Capacity check: applies to any transition into 'active' when an
    -- active session with non-null capacity exists.
    if p_participation_role = 'active'
       and v_session.id is not null
       and v_session.capacity is not null then
      select count(*) into v_active_count
        from public.session_participants
       where room_id            = p_room_id
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

  -- ── Compute queue_position (unchanged from db/022) ──────────────────
  if p_participation_role is null then
    v_new_queue_position := v_target.queue_position;
  elsif p_participation_role = 'queued' and v_target.queue_position is null then
    select coalesce(max(queue_position), 0) + 1
      into v_new_queue_position
      from public.session_participants
     where room_id        = p_room_id
       and left_at       is null
       and queue_position is not null;
  elsif p_participation_role = 'queued' then
    v_new_queue_position := v_target.queue_position;
  else
    v_new_queue_position := null;
  end if;

  -- ── Compute wanting_since (unchanged from db/022) ───────────────────
  if p_participation_role is null then
    v_new_wanting_since := v_target.wanting_since;
  elsif p_participation_role = 'queued' and v_target.participation_role <> 'queued' then
    v_new_wanting_since := now();
  elsif p_participation_role = 'queued' then
    v_new_wanting_since := v_target.wanting_since;
  else
    v_new_wanting_since := null;
  end if;

  update public.session_participants
     set control_role       = coalesce(p_control_role, control_role),
         participation_role = coalesce(p_participation_role, participation_role),
         pre_selections     = coalesce(p_pre_selections, pre_selections),
         queue_position     = v_new_queue_position,
         wanting_since      = v_new_wanting_since
   where id = v_target.id
  returning * into v_row;

  update public.rooms set last_activity_at = now() where id = p_room_id;
  update public.sessions set last_activity_at = now()
   where room_id = p_room_id and ended_at is null;

  return v_row;
end;
$$;

grant execute on function public.rpc_session_update_participant(uuid, uuid, text, text, jsonb) to authenticated;

comment on function public.rpc_session_update_participant(uuid, uuid, text, text, jsonb) is
  'Updates control_role / participation_role / pre_selections on a '
  'target participant in the room. Null args = no change. Field-level '
  'auth unchanged from db/022. Capacity check (55000) when transitioning '
  'into ''active'' with a non-null session capacity. queue_position and '
  'wanting_since semantics preserved identically from db/022. Bumps '
  'rooms.last_activity_at and the room''s active sessions.last_activity_at.';


-- ─── 3. rpc_session_update_queue_position (M3) ───────────────────────────
create or replace function public.rpc_session_update_queue_position(
  p_room_id      uuid,
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
  v_room    public.rooms;
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

  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then
    raise exception 'room not found: %', p_room_id using errcode = '02000';
  end if;

  if v_room.ended_at is not null then
    raise exception 'room has ended' using errcode = '02000';
  end if;

  select * into v_caller
    from public.session_participants
   where room_id = p_room_id
     and user_id = v_user_id
     and left_at is null;

  if v_caller.id is null then
    raise exception 'not an active participant in room %', p_room_id
      using errcode = '42501';
  end if;

  if v_caller.control_role not in ('manager', 'host') then
    raise exception 'only manager or host can reorder the queue'
      using errcode = '42501';
  end if;

  select * into v_target
    from public.session_participants
   where room_id            = p_room_id
     and user_id            = p_user_id
     and left_at            is null
     and participation_role = 'queued';

  if v_target.id is null then
    raise exception 'target user % is not currently queued in room %',
                    p_user_id, p_room_id
      using errcode = '02000';
  end if;

  update public.session_participants
     set queue_position = p_new_position
   where id = v_target.id
  returning * into v_row;

  update public.rooms set last_activity_at = now() where id = p_room_id;
  update public.sessions set last_activity_at = now()
   where room_id = p_room_id and ended_at is null;

  return v_row;
end;
$$;

grant execute on function public.rpc_session_update_queue_position(uuid, uuid, int) to authenticated;

comment on function public.rpc_session_update_queue_position(uuid, uuid, int) is
  'Manager or host sets a queued participant''s queue_position in the '
  'given room. Accepts duplicates / gaps (ties resolved by ordering '
  'query). Target must be ''queued''. p_new_position >= 1. Bumps '
  'rooms.last_activity_at and the room''s active sessions.last_activity_at.';


-- ─── 4. rpc_session_remove_participant (M4) ──────────────────────────────
create or replace function public.rpc_session_remove_participant(
  p_room_id uuid,
  p_user_id uuid
)
returns public.session_participants
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_caller  public.session_participants;
  v_target  public.session_participants;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if p_user_id = v_user_id then
    raise exception 'cannot remove self via rpc_session_remove_participant; use rpc_session_leave instead'
      using errcode = '22023';
  end if;

  select * into v_caller
    from public.session_participants
   where room_id      = p_room_id
     and user_id      = v_user_id
     and left_at     is null
     and control_role = 'manager';

  if v_caller.id is null then
    raise exception 'not authorized: only the active room manager can remove participants'
      using errcode = '42501';
  end if;

  select * into v_target
    from public.session_participants
   where room_id = p_room_id
     and user_id = p_user_id
   order by joined_at desc
   limit 1;

  if v_target.id is null then
    raise exception 'target user is not a participant in room %', p_room_id
      using errcode = '02000';
  end if;

  if v_target.left_at is not null then
    return v_target;
  end if;

  update public.session_participants
     set left_at = now()
   where id = v_target.id
  returning * into v_target;

  update public.rooms set last_activity_at = now() where id = p_room_id;
  update public.sessions set last_activity_at = now()
   where room_id = p_room_id and ended_at is null;

  return v_target;
end;
$$;

grant execute on function public.rpc_session_remove_participant(uuid, uuid) to authenticated;

comment on function public.rpc_session_remove_participant(uuid, uuid) is
  'Manager-only soft-remove of another participant in the given room. '
  'Sets left_at = now(). Self-removal disallowed; use rpc_session_leave. '
  'Idempotent on already-left targets. Realtime publish is caller-side.';


-- ─── 5. rpc_session_set_my_participation_role (M5) ───────────────────────
create or replace function public.rpc_session_set_my_participation_role(
  p_room_id uuid,
  p_role    text
)
returns public.session_participants
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_row     public.session_participants;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if p_role not in ('active', 'audience') then
    raise exception 'invalid role: must be active or audience, got %', p_role
      using errcode = '22023';
  end if;

  select * into v_row
    from public.session_participants
   where room_id = p_room_id
     and user_id = v_user_id
     and left_at is null
   order by joined_at desc
   limit 1;

  if v_row.id is null then
    raise exception 'caller is not a participant in room %', p_room_id
      using errcode = '02000';
  end if;

  if v_row.participation_role = p_role then
    return v_row;
  end if;

  update public.session_participants
     set participation_role = p_role
   where id = v_row.id
  returning * into v_row;

  update public.rooms set last_activity_at = now() where id = p_room_id;
  update public.sessions set last_activity_at = now()
   where room_id = p_room_id and ended_at is null;

  return v_row;
end;
$$;

grant execute on function public.rpc_session_set_my_participation_role(uuid, text) to authenticated;

comment on function public.rpc_session_set_my_participation_role(uuid, text) is
  'Self-only flip between ''active'' and ''audience'' in the given room. '
  'No-op idempotent if already in target state. ''queued'' not allowed; '
  'use rpc_session_update_queue_position. Bumps activity on transition '
  '(skipped on no-op).';


-- ─── 6. rpc_session_get_participants (M6) ────────────────────────────────
drop function if exists public.rpc_session_get_participants(uuid);

create function public.rpc_session_get_participants(
  p_room_id uuid
)
returns table (
  user_id            uuid,
  control_role       text,
  participation_role text,
  queue_position     int,
  wanting_since      timestamptz,
  pre_selections     jsonb,
  joined_at          timestamptz,
  display_name       text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if not (
    public.is_room_participant(p_room_id)
    or public.is_room_tv_household_member(p_room_id)
  ) then
    raise exception 'not authorized for room %', p_room_id
      using errcode = '42501';
  end if;

  return query
    select sp.user_id,
           sp.control_role,
           sp.participation_role,
           sp.queue_position,
           sp.wanting_since,
           sp.pre_selections,
           sp.joined_at,
           p.full_name as display_name
      from public.session_participants sp
      left join public.profiles p on p.id = sp.user_id
     where sp.room_id  = p_room_id
       and sp.left_at is null
     order by
       case sp.participation_role
         when 'active'   then 0
         when 'queued'   then 1
         else                 2
       end,
       sp.queue_position nulls last,
       sp.joined_at;
end;
$$;

grant execute on function public.rpc_session_get_participants(uuid) to authenticated;

comment on function public.rpc_session_get_participants(uuid) is
  'Returns active room participants with display_name from profiles. '
  'Read-only. Auth: room participant OR household member of the room''s '
  'TV (calls is_room_* helpers directly, not the OQ4 compat wrappers).';


-- ─── 7. rpc_session_heartbeat (M7) ───────────────────────────────────────
create or replace function public.rpc_session_heartbeat(p_room_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_pruned  int;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if not public.is_room_participant(p_room_id) then
    raise exception 'not a participant in room %', p_room_id
      using errcode = '42501';
  end if;

  update public.session_participants
     set last_seen_at = now()
   where room_id  = p_room_id
     and user_id  = v_user_id
     and left_at is null;

  update public.session_participants
     set left_at = now()
   where room_id     = p_room_id
     and left_at    is null
     and last_seen_at < now() - interval '60 seconds'
     and user_id    <> v_user_id;
  get diagnostics v_pruned = row_count;

  return v_pruned;
end;
$$;

grant execute on function public.rpc_session_heartbeat(uuid) to authenticated;

comment on function public.rpc_session_heartbeat(uuid) is
  'Bumps caller''s session_participants.last_seen_at and prunes stale '
  'peers in the same room (last_seen_at < now() - 60s). Returns prune '
  'count. Does NOT bump rooms.last_activity_at — the 20s heartbeat '
  'cadence would defeat the reclaim inactivity gate.';


-- ─── 8. rpc_karaoke_song_ended (M8) ──────────────────────────────────────
create or replace function public.rpc_karaoke_song_ended(
  p_room_id uuid
)
returns public.sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id     uuid := auth.uid();
  v_session     public.sessions;
  v_active      public.session_participants;
  v_queue_head  public.session_participants;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if not (
    public.is_room_participant(p_room_id)
    or public.is_room_tv_household_member(p_room_id)
  ) then
    raise exception 'not authorized for room %', p_room_id
      using errcode = '42501';
  end if;

  -- FOR UPDATE on the current session under the room (per §D pinned
  -- decision). Song-end is session-scoped; locking the session is the
  -- correct serialization granularity.
  select * into v_session
    from public.sessions
   where room_id   = p_room_id
     and ended_at is null
   for update;

  if v_session.id is null then
    raise exception 'no active session for room %', p_room_id
      using errcode = '02000';
  end if;

  select * into v_active
    from public.session_participants
   where room_id            = p_room_id
     and left_at            is null
     and participation_role = 'active'
   limit 1;

  select * into v_queue_head
    from public.session_participants
   where room_id            = p_room_id
     and left_at            is null
     and participation_role = 'queued'
   order by queue_position asc nulls last, joined_at asc
   limit 1;

  if v_active.id is not null then
    update public.session_participants
       set participation_role = 'audience',
           queue_position     = null
     where id = v_active.id;
  end if;

  if v_queue_head.id is not null then
    update public.session_participants
       set participation_role = 'active',
           queue_position     = null
     where id = v_queue_head.id;
  end if;

  update public.rooms set last_activity_at = now() where id = p_room_id;
  update public.sessions set last_activity_at = now() where id = v_session.id;

  select * into v_session from public.sessions where id = v_session.id;

  return v_session;
end;
$$;

grant execute on function public.rpc_karaoke_song_ended(uuid) to authenticated;

comment on function public.rpc_karaoke_song_ended(uuid) is
  'Demotes the current active singer to audience and promotes queue '
  'head to active, in the given room. Idempotent under all edge cases. '
  'FOR UPDATE locks the current session under the room (per §D). Auth: '
  'room participant OR household member of the room''s TV (calls '
  'is_room_* helpers directly).';


-- ─── 9. rpc_session_end (S2 — participant sweep STOPS) ───────────────────
-- Two behavioral changes from db/009:
--   • Participant sweep STOPS — ending a session no longer ends room
--     membership (room ending is a Phase-5 concern).
--   • Auth re-routes through rooms.controller_user_id — forced by
--     db/025's drop of sessions.manager_user_id. Set of allowed callers
--     is unchanged in steady state. See "Migration-window edge case" in
--     the header for the bounded transient between db/026 and db/028.
create or replace function public.rpc_session_end(p_session_id uuid)
returns public.sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_session public.sessions;
  v_room    public.rooms;
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

  select * into v_room from public.rooms where id = v_session.room_id;
  if v_room.id is null then
    raise exception 'session''s room not found: %', v_session.room_id
      using errcode = '02000';
  end if;

  if v_room.controller_user_id <> v_user_id then
    raise exception 'only the current room controller can end the session'
      using errcode = '42501';
  end if;

  update public.sessions
     set ended_at         = now(),
         last_activity_at = now()
   where id = p_session_id
  returning * into v_session;

  update public.rooms set last_activity_at = now() where id = v_session.room_id;

  return v_session;
end;
$$;

grant execute on function public.rpc_session_end(uuid) to authenticated;

comment on function public.rpc_session_end(uuid) is
  'Ends a specific session. Only the current room controller '
  '(rooms.controller_user_id) may call. Sets ended_at and '
  'last_activity_at on the session. Does NOT touch session_participants '
  '— participants belong to the room and persist across session ends '
  '(room ending is a Phase-5 concern). Bumps rooms.last_activity_at.';


-- ─── 10. rpc_session_set_admission_mode (S6 — auth re-routes) ────────────
create or replace function public.rpc_session_set_admission_mode(
  p_session_id      uuid,
  p_admission_mode  text,
  p_capacity        int
)
returns public.sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_session public.sessions;
  v_room    public.rooms;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if p_admission_mode is not null
     and p_admission_mode not in ('open', 'gated') then
    raise exception 'invalid admission_mode: % (must be NULL, ''open'', or ''gated'')',
                    p_admission_mode
      using errcode = '22023';
  end if;

  select * into v_session
    from public.sessions
   where id = p_session_id;

  if v_session.id is null then
    raise exception 'session not found: %', p_session_id
      using errcode = '02000';
  end if;

  if v_session.ended_at is not null then
    raise exception 'session has ended' using errcode = '02000';
  end if;

  -- Auth re-routes through sessions.room_id → rooms.controller_user_id
  -- (replacing the previous session_participants.control_role check).
  select * into v_room from public.rooms where id = v_session.room_id;
  if v_room.id is null then
    raise exception 'session''s room not found: %', v_session.room_id
      using errcode = '02000';
  end if;

  if v_room.controller_user_id <> v_user_id then
    raise exception 'not authorized: only the active room controller can set admission_mode'
      using errcode = '42501';
  end if;

  update public.sessions
     set admission_mode   = p_admission_mode,
         capacity         = p_capacity,
         last_activity_at = now()
   where id = p_session_id
  returning * into v_session;

  update public.rooms set last_activity_at = now() where id = v_session.room_id;

  return v_session;
end;
$$;

grant execute on function public.rpc_session_set_admission_mode(uuid, text, int) to authenticated;

comment on function public.rpc_session_set_admission_mode(uuid, text, int) is
  'Mid-session stamp of sessions.admission_mode and sessions.capacity. '
  'Stays session-scoped (p_session_id). Validates p_admission_mode '
  'against (NULL | ''open'' | ''gated''). Authorization: caller must be '
  'rooms.controller_user_id via sessions.room_id. Bumps activity on '
  'both rows.';


commit;


-- ─── Verification ─────────────────────────────────────────────────────────
select 'migration 026 loaded' as status;

-- ============================================================================
-- POST-MIGRATION VERIFICATION
-- Run against prod via Supabase SQL Editor after applying.
--
-- 1. All 10 RPCs exist with expected parameter NAMES.
--    SELECT proname, proargnames
--      FROM pg_proc
--     WHERE proname IN (
--             'rpc_session_join',
--             'rpc_session_update_participant',
--             'rpc_session_update_queue_position',
--             'rpc_session_remove_participant',
--             'rpc_session_set_my_participation_role',
--             'rpc_session_get_participants',
--             'rpc_session_heartbeat',
--             'rpc_karaoke_song_ended',
--             'rpc_session_end',
--             'rpc_session_set_admission_mode'
--           )
--     ORDER BY proname;
--    Expect 10 rows. proargnames for the 8 mechanical RPCs starts with
--    {p_room_id, ...}; rpc_session_end has {p_session_id};
--    rpc_session_set_admission_mode has {p_session_id, p_admission_mode,
--    p_capacity}.
--
-- 2. rpc_session_end no longer touches session_participants.
--    SELECT pg_get_functiondef(oid)
--      FROM pg_proc WHERE proname = 'rpc_session_end';
--    Expect: body has UPDATE public.sessions and UPDATE public.rooms
--    but NO UPDATE public.session_participants.
--
-- 3. rpc_session_set_admission_mode auth uses rooms.controller_user_id.
--    SELECT pg_get_functiondef(oid)
--      FROM pg_proc WHERE proname = 'rpc_session_set_admission_mode';
--    Expect: body references rooms.controller_user_id and does NOT
--    filter session_participants by control_role='manager'.
--
-- 4. rpc_karaoke_song_ended FOR UPDATE on current session under room.
--    SELECT pg_get_functiondef(oid)
--      FROM pg_proc WHERE proname = 'rpc_karaoke_song_ended';
--    Expect: body contains FROM public.sessions WHERE room_id = p_room_id
--    AND ended_at IS NULL ... FOR UPDATE.
--
-- 5. The 2 read-only RPCs do NOT bump rooms.last_activity_at.
--    SELECT proname,
--           pg_get_functiondef(oid) LIKE '%update public.rooms%' as touches_rooms
--      FROM pg_proc
--     WHERE proname IN ('rpc_session_get_participants', 'rpc_session_heartbeat')
--     ORDER BY proname;
--    Expect: touches_rooms = FALSE for both.
--
-- 6. GRANT EXECUTE to authenticated is present for every RPC.
--    SELECT p.proname,
--           has_function_privilege('authenticated', p.oid, 'EXECUTE') as authed
--      FROM pg_proc p
--     WHERE p.proname IN (
--             'rpc_session_join',
--             'rpc_session_update_participant',
--             'rpc_session_update_queue_position',
--             'rpc_session_remove_participant',
--             'rpc_session_set_my_participation_role',
--             'rpc_session_get_participants',
--             'rpc_session_heartbeat',
--             'rpc_karaoke_song_ended',
--             'rpc_session_end',
--             'rpc_session_set_admission_mode'
--           )
--     ORDER BY p.proname;
--    Expect: authed = TRUE for all 10 rows.
-- ============================================================================
