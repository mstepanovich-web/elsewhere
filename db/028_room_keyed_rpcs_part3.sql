-- ============================================================================
-- Elsewhere — Phase 1 RPC migration, batch 3 of 3: leave + reclaim RPCs
-- Migration: 028
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Three RPCs land here (the last three of the 14-RPC Phase-1 worklist):
--
--   • rpc_session_leave (REWRITE)            — re-pointed to room-keyed,
--                                                with the four-tier
--                                                succession hierarchy and
--                                                a new optional
--                                                p_successor_user_id
--                                                parameter for the named-
--                                                successor tier. Includes
--                                                the empty-room full
--                                                room-end branch.
--
--   • rpc_session_reclaim_manager (REWRITE)  — re-pointed; writes
--                                                rooms.controller_user_id;
--                                                10-min inactivity gate
--                                                preserved.
--
--   • rpc_session_admin_reclaim (REWRITE)    — re-pointed; writes
--                                                rooms.controller_user_id;
--                                                household-admin gate
--                                                preserved (no inactivity
--                                                check).
--
-- Built against docs/PHASE-1-BUILD-SPEC.md §D as amended through commit
-- fcc42f6, the ROOM-AUTHORITY-MODEL.md correction landing in the SAME
-- commit as this migration (host-first succession order), and the
-- db/028 pre-write investigation conducted prior to drafting.
--
-- Three-migration grouping (db/026 / db/027 / db/028):
--   db/026 (shipped)      — 8 mechanical + rpc_session_end +
--                           rpc_session_set_admission_mode.
--   db/027 (shipped)      — rpc_session_start split + new rpc_room_create.
--   db/028 (THIS FILE)    — rpc_session_leave + rpc_session_reclaim_manager
--                           + rpc_session_admin_reclaim. End of Phase-1
--                           RPC migration arc.
--
-- ─── Succession order (host-first; corrected from ROOM-AUTHORITY-MODEL.md) ─
-- ROOM-AUTHORITY-MODEL.md (as corrected in the same commit as this
-- migration) defines a four-tier hierarchy in this exact order:
--
--   Tier 1 — Present host wins, always. If any active host
--            (control_role = 'host', left_at IS NULL, not the leaver)
--            is in the room, the longest continuously-present host
--            takes control. Applies to BOTH explicit and implicit
--            manager departure. A host always wins — a named successor
--            never competes with a host.
--
--   Tier 2 — Named successor (explicit departure only). If no host is
--            present AND the leaver passed a non-null p_successor_user_id
--            AND that user is eligible (left_at IS NULL,
--            participation_role IN ('active','queued'), not the leaver),
--            they take control.
--
--   Tier 3 — Longest continuously-present non-audience participant. If
--            no host and no eligible named successor, promote the
--            non-audience participant (participation_role IN
--            ('active','queued'), left_at IS NULL, not the leaver) with
--            the earliest joined_at.
--
--   Tier 4 — Full room-end. If none of the above match, end the room
--            (see below).
--
-- Eligibility for named successor (tier 2): silent fall-through if the
-- name is ineligible. No error, no prompt. The UI picker is expected
-- to only ever show eligible players, so an ineligible name should not
-- occur — but the RPC checks defensively, and on miss falls through to
-- tier 3 (host has already been excluded by ordering). This matches
-- ROOM-AUTHORITY-MODEL.md's empty-room paragraph: "Naming a successor
-- who is not (or is no longer) an eligible participant falls through
-- to the lower tiers."
--
-- "Continuously-present" via joined_at: the row-creation contract from
-- db/008:114-116 — "A user who leaves and rejoins gets a new row with
-- joined_at = now(); the historical row retains its left_at timestamp."
-- ORDER BY joined_at ASC LIMIT 1 on left_at-IS-NULL rows picks the
-- candidate with the earliest current unbroken stint, which is the
-- definition of longest continuously-present.
--
-- ─── Full room-end (tier 4) — write order ────────────────────────────────
-- The no-successor branch ends the ROOM (not just the session). This is
-- the FIRST and ONLY writer of rooms.ended_at in the entire system, the
-- structural counterpart to rpc_room_create's sole-writer guarantee on
-- rooms.owner_user_id (db/027). The write order is fixed and matters:
--
--   1. End the active session if any: sessions.ended_at = now(),
--      sessions.last_activity_at = now() WHERE room_id = p_room_id AND
--      ended_at IS NULL.
--   2. Sweep participants: session_participants.left_at = now() WHERE
--      room_id = p_room_id AND left_at IS NULL.
--   3. LAST: rooms.controller_user_id = NULL, rooms.ended_at = now(),
--      rooms.last_activity_at = now().
--
-- Rationale for the order: contents (sessions, participants) are cleaned
-- up BEFORE the room is stamped ended, so no reader ever observes an
-- ended room with live contents. A reader filtering rooms by
-- ended_at IS NULL never sees the partially-cleaned-up state; readers
-- of sessions and session_participants under a still-active room see the
-- normal session-end / leave path. Future room-end paths (a "close
-- room" UI affordance, Phase-5 scope) should reuse this exact order.
--
-- Why controller_user_id is nulled at tier 4: the leaver's
-- session_participants row is swept (left_at = now()) in step 2, so the
-- room has no live manager row in session_participants. Leaving
-- controller_user_id pointing at the (now-departed) leaver would
-- disagree with the swept participant rows: a reader joining
-- rooms.controller_user_id back to session_participants would find no
-- active row. NULL is the consistent post-end value. owner_user_id is
-- emphatically NOT nulled — ownership is preserved at room-end (see
-- preservation guarantee below).
--
-- The room-end branch is unguarded by an explicit "no participants
-- left" check — it is reached only when tiers 1-3 all failed to find a
-- promotee, which by construction means the room has no eligible
-- controller and the only remaining live state belongs to the leaver
-- and audience-mode watchers. Marking those rows left and ending the
-- room is the correct response: audience-mode watchers have opted out
-- of the player track and there is no controller to drive the room
-- further. ROOM-AUTHORITY-MODEL.md's "Empty room" paragraph is the
-- canonical statement.
--
-- ─── Owner-user-id preservation guarantee ────────────────────────────────
-- None of the three RPCs in this file write to rooms.owner_user_id.
-- Per the structural guarantee from PHASE-1-BUILD-SPEC.md OQ2 (a) and
-- db/027's file header, rpc_room_create is the SOLE writer of
-- owner_user_id; ownership is set once at room creation and never
-- transferred by any other RPC. rpc_session_leave (including its full
-- room-end branch — ending a room does NOT change its owner) and both
-- reclaim RPCs transfer room CONTROL only via rooms.controller_user_id.
-- Even when rpc_session_leave ends the room and nulls
-- controller_user_id, rooms.owner_user_id is preserved — the original
-- convener retains the binding to their saved-room template library
-- (ROOM-AUTHORITY-MODEL.md § "Room ownership").
--
-- ─── Reclaim mechanics preserved verbatim from db/010 ────────────────────
-- Both reclaim RPCs preserve the demote-then-promote mechanic on
-- session_participants.control_role (drives off the unique partial
-- index session_participants_one_manager, re-keyed to room_id by
-- db/025). The mirror behavior is unchanged:
--
--   1. UPDATE session_participants SET control_role = 'none' WHERE
--      room_id = p_room_id AND control_role = 'manager' AND
--      left_at IS NULL.
--   2. If caller has an active row under the room, UPDATE its
--      control_role = 'manager'. Otherwise INSERT a new row with
--      control_role = 'manager', participation_role = 'audience'
--      (the reclaiming caller may not be a participant yet — e.g., a
--      household admin who never joined).
--   3. UPDATE rooms SET controller_user_id = caller, last_activity_at
--      = now() WHERE id = p_room_id.
--
-- Driving demote off the partial-unique-index invariant rather than
-- rooms.controller_user_id preserves the resilience-to-desync property
-- from db/010 — if controller_user_id ever diverges from the manager
-- session_participants row, the reclaim still clears the slot
-- correctly. (Should never happen post-Phase-1, but the property is
-- free to keep and pays for itself if a future migration desyncs.)
--
-- ─── Auth gates preserved ────────────────────────────────────────────────
-- rpc_session_reclaim_manager: caller must be a household member of
-- the room's TV (is_room_tv_household_member). 10-min inactivity gate
-- preserved: rooms.last_activity_at < now() - interval '10 minutes',
-- raise SQLSTATE 55000 (object_not_in_prerequisite_state) when the
-- room is still active. The inactivity-gate timestamp source is
-- rooms.last_activity_at, which is the §D pinned activity-target —
-- this is exactly the timestamp every activity-bumping RPC updates.
--
-- rpc_session_admin_reclaim: caller must be a household admin of the
-- room's TV (is_room_tv_household_admin). No inactivity check — admin
-- can force-reclaim an actively-managed room.
--
-- rpc_session_leave: caller must be authenticated and currently an
-- active room participant; the function looks up their row and raises
-- SQLSTATE 02000 if not found.
--
-- ─── §D Cross-cutting decisions applied ──────────────────────────────────
-- Activity-timestamp target: every CONTROLLER state-changing path in
-- this file bumps rooms.last_activity_at. rpc_session_leave bumps it
-- on the promote branch (tier 1/2/3); the tier-4 room-end branch
-- replaces the bump with rooms.ended_at + last_activity_at on the
-- rooms row. Both reclaim RPCs bump rooms.last_activity_at as part of
-- the rooms UPDATE.
--
-- Non-controller leave does NOT bump rooms.last_activity_at — a
-- non-controller participant departing is not controller activity, and
-- the reclaim 10-min inactivity gate reads rooms.last_activity_at.
-- Bumping it on a non-controller leave would reset the reclaim timer
-- on someone else's behalf, which is wrong. The non-controller leave
-- DOES bump sessions.last_activity_at (matches db/010 behavior — the
-- session is still active and the row change is real session activity).
--
-- Sessions.last_activity_at is bumped wherever a current session
-- exists, per the "recommended" §D rule.
--
-- ─── Idempotency / transaction wrapping ──────────────────────────────────
-- CREATE OR REPLACE FUNCTION for all three. BEGIN/COMMIT envelope.
-- If any CREATE fails, the migration rolls back. Safe to re-run.
--
-- ─── Signature changes vs. db/010 (callers must update) ──────────────────
--   • rpc_session_leave: signature changes from (p_session_id uuid) to
--     (p_room_id uuid, p_successor_user_id uuid DEFAULT NULL). Callers
--     passing p_session_id break — they must pass the room_id. Shell-
--     side migration to this new signature is tracked in DEFERRED.md
--     alongside the rpc_session_start signature breakage from db/027.
--   • rpc_session_reclaim_manager: signature changes from
--     (p_session_id uuid) to (p_room_id uuid). Returns rooms instead
--     of sessions.
--   • rpc_session_admin_reclaim: signature changes from
--     (p_session_id uuid) to (p_room_id uuid). Returns rooms instead
--     of sessions.
--
-- ─── Verification footer: see after COMMIT ──────────────────────────────
-- ============================================================================


begin;


-- ─── 1. rpc_session_leave (REWRITE — four-tier succession + room-end) ────
-- Caller leaves the room. If caller is the room's current controller,
-- runs the four-tier succession hierarchy from ROOM-AUTHORITY-MODEL.md
-- (host-first; named successor; longest non-audience; full room-end).
-- Non-controller leave is the simple set-left_at on the caller's row.
--
-- p_successor_user_id is optional (default null). Used only by tier 2
-- (named successor), reached only when no active host is present —
-- per the corrected succession order, host always beats named.
-- Silently falls through to tier 3 if the named user is ineligible
-- (left_at IS NOT NULL, audience-mode, or is the leaver themselves).
create or replace function public.rpc_session_leave(
  p_room_id            uuid,
  p_successor_user_id  uuid default null
)
returns public.session_participants
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id    uuid := auth.uid();
  v_room       public.rooms;
  v_row        public.session_participants;
  v_promotable public.session_participants;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- Room must exist and be live.
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then
    raise exception 'room not found: %', p_room_id using errcode = '02000';
  end if;

  if v_room.ended_at is not null then
    raise exception 'room has ended' using errcode = '02000';
  end if;

  -- Find caller's active room participant row. If none, nothing to leave.
  select * into v_row
    from public.session_participants
   where room_id  = p_room_id
     and user_id  = v_user_id
     and left_at is null;

  if v_row.id is null then
    raise exception 'not an active participant in room %', p_room_id
      using errcode = '02000';
  end if;

  -- ─── Non-controller leave ──────────────────────────────────────────
  -- The room's controller is identified by rooms.controller_user_id
  -- (the canonical source post-db/025). If the leaver is not the
  -- controller, just set left_at on their row.
  --
  -- Does NOT bump rooms.last_activity_at — non-controller departure is
  -- not controller activity and must not reset the reclaim timer (the
  -- 10-min inactivity gate in rpc_session_reclaim_manager reads
  -- rooms.last_activity_at). Sessions.last_activity_at IS bumped (the
  -- session is still active and a participant row change is real
  -- session-level activity; matches db/010 behavior).
  if v_room.controller_user_id <> v_user_id then
    update public.session_participants
       set left_at = now()
     where id = v_row.id
    returning * into v_row;

    update public.sessions
       set last_activity_at = now()
     where room_id = p_room_id
       and ended_at is null;

    return v_row;
  end if;

  -- ─── Controller leave: four-tier succession ────────────────────────
  -- The order is FIXED and host-wins-always: tier 1 host > tier 2
  -- named > tier 3 longest non-audience > tier 4 room-end. The
  -- p_successor_user_id parameter, if non-null, is consulted ONLY at
  -- tier 2 — never competes with a present host.

  -- Tier 1 — Present host (longest continuously-present host).
  select * into v_promotable
    from public.session_participants
   where room_id      = p_room_id
     and left_at     is null
     and control_role = 'host'
     and user_id     <> v_user_id
   order by joined_at asc
   limit 1;

  -- Tier 2 — Named successor (only when no host was found).
  -- Eligibility check inline; silent fall-through if ineligible. The
  -- (room_id, user_id, left_at IS NULL) match is single-row in practice
  -- via the partial-unique invariant on session_participants, but the
  -- explicit `limit 1` makes the single-row intent of this SELECT INTO
  -- self-evident (matches tiers 1 and 3).
  if v_promotable.id is null and p_successor_user_id is not null then
    select * into v_promotable
      from public.session_participants
     where room_id            = p_room_id
       and user_id            = p_successor_user_id
       and left_at           is null
       and participation_role in ('active', 'queued')
       and user_id           <> v_user_id
     limit 1;
  end if;

  -- Tier 3 — Longest continuously-present non-audience participant.
  if v_promotable.id is null then
    select * into v_promotable
      from public.session_participants
     where room_id            = p_room_id
       and left_at           is null
       and participation_role in ('active', 'queued')
       and user_id           <> v_user_id
     order by joined_at asc
     limit 1;
  end if;

  if v_promotable.id is not null then
    -- Promote. Order matters: clear the leaver's manager slot before
    -- promoting the successor, to avoid momentarily violating the
    -- session_participants_one_manager partial-unique index (re-keyed
    -- to room_id by db/025).
    update public.session_participants
       set left_at      = now(),
           control_role = 'none'
     where id = v_row.id
    returning * into v_row;

    update public.session_participants
       set control_role = 'manager'
     where id = v_promotable.id;

    -- Transfer room control. owner_user_id is NOT touched — this RPC
    -- transfers CONTROL only (ROOM-AUTHORITY-MODEL.md § "Room
    -- ownership" — ownership never transfers by succession).
    update public.rooms
       set controller_user_id = v_promotable.user_id,
           last_activity_at   = now()
     where id = p_room_id;

    -- Bump active session's last_activity_at if any.
    update public.sessions
       set last_activity_at = now()
     where room_id = p_room_id
       and ended_at is null;

    return v_row;
  end if;

  -- ─── Tier 4: full room-end ─────────────────────────────────────────
  -- No promotable found at any tier. End the room. Write order is
  -- fixed and matters (see file header for rationale): sessions
  -- first, participants next, rooms.ended_at LAST.

  -- 1. End the active session, if any.
  update public.sessions
     set ended_at         = now(),
         last_activity_at = now()
   where room_id   = p_room_id
     and ended_at is null;

  -- 2. Sweep all active participants (including the leaver).
  update public.session_participants
     set left_at = now()
   where room_id  = p_room_id
     and left_at is null;

  -- 3. LAST: stamp the room ended and clear the controller pointer.
  -- controller_user_id is nulled — the leaver's participant row was
  -- just swept in step 2, so the ended room has no live manager row,
  -- and rooms.controller_user_id pointing at the (now-departed) leaver
  -- would disagree with that. NULL is the consistent post-end value.
  -- owner_user_id is NOT touched (the convener retains their saved-
  -- room binding even after the room ends — ownership is preserved).
  update public.rooms
     set controller_user_id = null,
         ended_at           = now(),
         last_activity_at   = now()
   where id = p_room_id;

  -- Re-read caller's row to return its swept state.
  select * into v_row
    from public.session_participants
   where id = v_row.id;

  return v_row;
end;
$$;

grant execute on function public.rpc_session_leave(uuid, uuid) to authenticated;

comment on function public.rpc_session_leave(uuid, uuid) is
  'Caller leaves the room. If caller is the current controller, runs '
  'the four-tier succession from ROOM-AUTHORITY-MODEL.md (host-first): '
  '(1) longest continuously-present host; (2) named successor via '
  'p_successor_user_id when no host; (3) longest non-audience '
  'participant; (4) full room-end. Tier 2 silently falls through to '
  'tier 3 when the named user is ineligible. Tier 4 is the FIRST and '
  'ONLY writer of rooms.ended_at; write order is sessions → '
  'participants → rooms.ended_at; tier-4 also nulls '
  'rooms.controller_user_id (consistent with the swept participant '
  'rows). NEVER touches rooms.owner_user_id — transfers room CONTROL '
  'only; ownership is preserved even at room-end. Non-controller leave '
  'just sets left_at on the caller''s row and bumps '
  'sessions.last_activity_at (does NOT bump rooms.last_activity_at — '
  'that would reset the reclaim 10-min inactivity gate on behalf of '
  'someone who is not the controller). Signature changed from db/010: '
  '(p_session_id) → (p_room_id, p_successor_user_id).';


-- ─── 2. rpc_session_reclaim_manager (REWRITE — room-keyed) ───────────────
-- Any household member of the room's TV may reclaim a room whose
-- controller has been inactive for ≥ 10 minutes. Same demote-then-
-- promote mechanic on session_participants.control_role as db/010,
-- but now writes rooms.controller_user_id (not the dropped
-- sessions.manager_user_id) and reads rooms.last_activity_at for the
-- inactivity gate (the §D pinned activity-target timestamp).
--
-- NEVER touches rooms.owner_user_id — control transfer only.
create or replace function public.rpc_session_reclaim_manager(p_room_id uuid)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id    uuid := auth.uid();
  v_room       public.rooms;
  v_caller_row public.session_participants;
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

  -- Inactivity check: reclaim allowed when
  -- rooms.last_activity_at < now() - interval '10 minutes'.
  -- Raise when >= that threshold (still "within 10 min").
  if v_room.last_activity_at >= now() - interval '10 minutes' then
    raise exception 'room is still active (last activity %); only orphaned rooms can be reclaimed',
                    v_room.last_activity_at
      using errcode = '55000';
  end if;

  -- Demote current manager via the unique-partial-index invariant
  -- (control_role='manager' + left_at is null → at most one row per
  -- room). Resilient to denormalization desync vs.
  -- rooms.controller_user_id.
  update public.session_participants
     set control_role = 'none'
   where room_id      = p_room_id
     and control_role = 'manager'
     and left_at     is null;

  -- Look up caller's active row, if any.
  select * into v_caller_row
    from public.session_participants
   where room_id = p_room_id
     and user_id = v_user_id
     and left_at is null;

  if v_caller_row.id is null then
    -- Caller not yet a participant. Insert as manager-audience.
    insert into public.session_participants (
      room_id, user_id, control_role, participation_role
    )
    values (
      p_room_id, v_user_id, 'manager', 'audience'
    );
  else
    update public.session_participants
       set control_role = 'manager'
     where id = v_caller_row.id;
  end if;

  -- Transfer room control. owner_user_id NOT touched.
  update public.rooms
     set controller_user_id = v_user_id,
         last_activity_at   = now()
   where id = p_room_id
  returning * into v_room;

  -- Bump active session's last_activity_at if any.
  update public.sessions
     set last_activity_at = now()
   where room_id = p_room_id
     and ended_at is null;

  return v_room;
end;
$$;

grant execute on function public.rpc_session_reclaim_manager(uuid) to authenticated;

comment on function public.rpc_session_reclaim_manager(uuid) is
  'Any household member of the room''s TV reclaims an orphaned room '
  '(rooms.last_activity_at >= now() - 10 min raises errcode 55000). '
  'Demotes current manager via the session_participants_one_manager '
  'partial-unique index; promotes caller (insert as manager-audience '
  'if not yet participant). Updates rooms.controller_user_id and '
  'rooms.last_activity_at; NEVER touches rooms.owner_user_id. '
  'Signature changed from db/010: (p_session_id) → (p_room_id); '
  'returns rooms instead of sessions.';


-- ─── 3. rpc_session_admin_reclaim (REWRITE — room-keyed) ─────────────────
-- Household admin of the room's TV force-reclaims a room. Same demote-
-- then-promote mechanics as rpc_session_reclaim_manager but no
-- inactivity check — admin can reclaim an actively-managed room. The
-- "head of household yanks the remote" escape hatch.
--
-- NEVER touches rooms.owner_user_id — control transfer only.
create or replace function public.rpc_session_admin_reclaim(p_room_id uuid)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id    uuid := auth.uid();
  v_room       public.rooms;
  v_caller_row public.session_participants;
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

  if not public.is_room_tv_household_admin(p_room_id) then
    raise exception 'not a household admin of this room''s TV household'
      using errcode = '42501';
  end if;

  -- Demote current manager (no-op if none active — see note in
  -- rpc_session_reclaim_manager).
  update public.session_participants
     set control_role = 'none'
   where room_id      = p_room_id
     and control_role = 'manager'
     and left_at     is null;

  -- Look up caller's active row, if any.
  select * into v_caller_row
    from public.session_participants
   where room_id = p_room_id
     and user_id = v_user_id
     and left_at is null;

  if v_caller_row.id is null then
    insert into public.session_participants (
      room_id, user_id, control_role, participation_role
    )
    values (
      p_room_id, v_user_id, 'manager', 'audience'
    );
  else
    update public.session_participants
       set control_role = 'manager'
     where id = v_caller_row.id;
  end if;

  -- Transfer room control. owner_user_id NOT touched.
  update public.rooms
     set controller_user_id = v_user_id,
         last_activity_at   = now()
   where id = p_room_id
  returning * into v_room;

  -- Bump active session's last_activity_at if any.
  update public.sessions
     set last_activity_at = now()
   where room_id = p_room_id
     and ended_at is null;

  return v_room;
end;
$$;

grant execute on function public.rpc_session_admin_reclaim(uuid) to authenticated;

comment on function public.rpc_session_admin_reclaim(uuid) is
  'Household admin of the room''s TV force-reclaims a room regardless '
  'of inactivity. Same demote-then-promote mechanics as '
  'rpc_session_reclaim_manager without the inactivity check. "Head of '
  'household yanks the remote" escape hatch. Updates '
  'rooms.controller_user_id; NEVER touches rooms.owner_user_id. '
  'Signature changed from db/010: (p_session_id) → (p_room_id); '
  'returns rooms instead of sessions.';


commit;


-- ─── Verification ─────────────────────────────────────────────────────────
select 'migration 028 loaded' as status;

-- ============================================================================
-- POST-MIGRATION VERIFICATION
-- Run against prod via Supabase SQL Editor after applying.
--
-- 1. All three RPCs exist with expected parameter NAMES and return types.
--    SELECT proname, proargnames, pg_get_function_result(oid) AS returns
--      FROM pg_proc
--     WHERE proname IN ('rpc_session_leave', 'rpc_session_reclaim_manager',
--                       'rpc_session_admin_reclaim')
--     ORDER BY proname;
--    Expect 3 rows. proargnames:
--      rpc_session_leave           = {p_room_id, p_successor_user_id}
--      rpc_session_reclaim_manager = {p_room_id}
--      rpc_session_admin_reclaim   = {p_room_id}
--    returns:
--      rpc_session_leave           = session_participants
--      rpc_session_reclaim_manager = rooms
--      rpc_session_admin_reclaim   = rooms
--
-- 2. rpc_session_leave is the SOLE writer of rooms.ended_at.
--    SELECT proname
--      FROM pg_proc
--     WHERE pg_get_functiondef(oid) ~* 'rooms[[:space:]]+set[[:space:]]+ended_at'
--        OR pg_get_functiondef(oid) ~* 'rooms\.ended_at[[:space:]]*='
--        OR pg_get_functiondef(oid) ~* 'ended_at[[:space:]]*=[[:space:]]*now\(\)[^;]*public\.rooms'
--     ORDER BY proname;
--    Expect: exactly 1 row, rpc_session_leave (its tier-4 branch
--    contains `controller_user_id = null, ended_at = now()`). If any
--    other function appears, the sole-writer guarantee on
--    rooms.ended_at is violated.
--
-- 3. None of the three RPCs write rooms.owner_user_id (preservation
--    guarantee — rpc_room_create remains the sole writer from db/027).
--    SELECT proname
--      FROM pg_proc
--     WHERE proname IN ('rpc_session_leave', 'rpc_session_reclaim_manager',
--                       'rpc_session_admin_reclaim')
--       AND pg_get_functiondef(oid) ILIKE '%owner_user_id%';
--    Expect: 0 rows. Re-run the db/027 sole-writer check too —
--    rpc_room_create must remain the sole writer overall.
--
-- 4. Both reclaim RPCs preserve the demote-then-promote control_role
--    mirror.
--    SELECT proname,
--           pg_get_functiondef(oid) ILIKE '%control_role = ''none''%' AS demotes,
--           pg_get_functiondef(oid) ILIKE '%control_role = ''manager''%' AS promotes
--      FROM pg_proc
--     WHERE proname IN ('rpc_session_reclaim_manager', 'rpc_session_admin_reclaim');
--    Expect: demotes = TRUE and promotes = TRUE for both rows.
--
-- 5. The 10-min inactivity gate on rpc_session_reclaim_manager reads
--    rooms.last_activity_at (the §D pinned activity-target).
--    SELECT pg_get_functiondef(oid)
--      FROM pg_proc WHERE proname = 'rpc_session_reclaim_manager';
--    Expect: body contains v_room.last_activity_at >= now() - interval
--    '10 minutes' and errcode '55000'.
--
-- 6. rpc_session_leave's four-tier succession SQL contains all three
--    candidate-selection queries.
--    SELECT pg_get_functiondef(oid)
--      FROM pg_proc WHERE proname = 'rpc_session_leave';
--    Expect: body contains (a) a SELECT with control_role = 'host' and
--    LIMIT 1 (tier 1); (b) a SELECT with user_id = p_successor_user_id
--    and participation_role IN ('active', 'queued') and LIMIT 1
--    (tier 2); (c) a SELECT with participation_role IN ('active',
--    'queued') and no control_role filter and ORDER BY joined_at asc
--    and LIMIT 1 (tier 3); (d) UPDATE public.rooms SET
--    controller_user_id = NULL, ended_at = now() (tier 4).
--
-- 7. rpc_session_leave's tier-4 write order is sessions → participants
--    → rooms.ended_at, and the rooms UPDATE nulls controller_user_id.
--    Manual inspection: pg_get_functiondef(oid) for rpc_session_leave,
--    locate the no-promotable branch, confirm three UPDATEs in this
--    order: UPDATE public.sessions ... ended_at; UPDATE public.
--    session_participants ... left_at; UPDATE public.rooms ...
--    controller_user_id = null, ended_at = now().
--
-- 8. rpc_session_leave's non-controller leave path does NOT bump
--    rooms.last_activity_at.
--    SELECT pg_get_functiondef(oid)
--      FROM pg_proc WHERE proname = 'rpc_session_leave';
--    Manual inspection: in the `controller_user_id <> v_user_id`
--    branch (the non-controller leave path), confirm there is NO
--    `update public.rooms` statement. The `update public.sessions`
--    activity bump IS present.
--
-- 9. GRANT EXECUTE to authenticated is present for all three RPCs.
--    SELECT p.proname,
--           has_function_privilege('authenticated', p.oid, 'EXECUTE') as authed
--      FROM pg_proc p
--     WHERE p.proname IN ('rpc_session_leave', 'rpc_session_reclaim_manager',
--                         'rpc_session_admin_reclaim')
--     ORDER BY p.proname;
--    Expect: authed = TRUE for all 3 rows.
-- ============================================================================
