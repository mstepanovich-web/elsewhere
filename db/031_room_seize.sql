-- ============================================================================
-- Elsewhere — rpc_room_seize: ownership-seize RPC
-- Migration: 031
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Implements the ownership-seize operation specified in
-- ROOM-AUTHORITY-MODEL.md § "Seize authority". This is the C5 work
-- item from the premium-control model documentation arc (tracked in
-- docs/DEFERRED.md as "ownership-seize implementing RPC").
--
-- Seize is the IMMEDIATE take-control operation, distinct from the
-- existing inactivity-reclaim path (rpc_session_reclaim_manager /
-- rpc_session_admin_reclaim, db/028 §§1 + 3). Cousins, not synonyms:
--
--                       │  Ownership-seize         │ Inactivity-reclaim
--   ────────────────────┼──────────────────────────┼──────────────────────
--   Target state        │  LIVE room               │ STALE room (≥10 min)
--   Inactivity gate?    │  NO                      │ YES
--   Caller predicate    │  Ownership-class only    │ HH member / HH admin
--                       │  (this RPC)              │ (of the DISPLAYING TV)
--
-- The two seize predicates:
--   • Convener-seize: auth.uid() = rooms.owner_user_id. The original
--     convener may seize their own room at any time the premium-
--     control layer is active.
--   • Admin-seize:    the caller is an HH admin of the household
--     that OWNS the room — i.e., rooms.owner_user_id is on that
--     admin's household roster. Keys on ROOM OWNERSHIP, NOT on the
--     room being displayed on the household's device.
--
-- ─── Premium-control-layer gate (auth gate b) ───────────────────────────
-- Seize is available only when the premium-control layer is active
-- for the room. Per ROOM-AUTHORITY-MODEL.md § "When the premium-
-- control layer is active", the layer activates iff the room is
-- bound to an embedding-capable device:
--   1. rooms.screen_ref IS NOT NULL (room has a screen at all), AND
--   2. tv_devices.can_embed = true for that screen.
--
-- These checks are split into two separate guards in the body (4a
-- and 4b) so the user-visible error distinguishes "no screen at all"
-- from "screen exists but not embedding-capable" — useful for
-- debugging and possible future UX surfacing.
--
-- Functional consequence in current prod: db/030 shipped the
-- can_embed column with NO writer (the self-report path is deferred,
-- blocked on the compositing pipeline not yet existing as code —
-- see DEFERRED.md). Every tv_devices row currently reads
-- can_embed = false, so guard 4b will reject every seize attempt in
-- prod until the self-report writer lands. This is by design — the
-- correct interim safety posture. The RPC's correctness is
-- independent of any row's current can_embed value.
--
-- ─── Admin-seize predicate inlined ──────────────────────────────────────
-- The "admin of the household that OWNS the room" predicate has no
-- pre-existing helper that expresses it directly:
--   • is_room_tv_household_admin (db/025) keys on the DISPLAYING
--     TV's household, not the room owner's. Wrong predicate.
--   • is_household_admin (db/006) takes a household_id argument;
--     there's no single "the room owner's household" because a user
--     can be a member of multiple households.
--
-- The model phrasing — "rooms.owner_user_id is on that admin's
-- household roster" — translates to a household_members self-join:
-- exists a household where the caller is an admin AND the room's
-- owner is a member. The self-join is inlined in the body below
-- (one caller, single-purpose; no abstraction needed).
--
-- The role-comparison shape (hm_admin.role = 'admin') mirrors
-- is_household_admin's exact predicate (db/006:172) which itself
-- checks the household_members.role text column against the literal
-- 'admin' value (CHECK constraint: role in ('admin', 'user')).
--
-- ─── Demote-then-promote mechanic ───────────────────────────────────────
-- Copied verbatim from db/028's reclaim RPCs (rpc_session_reclaim_manager
-- §1 + rpc_session_admin_reclaim §3). The only differences vs. those
-- RPCs are the auth gates above and the absence of the 10-min
-- inactivity check. The mechanic itself — demote current manager via
-- the partial-unique-index invariant, look up caller's row, insert-
-- or-update to promote, then write rooms.controller_user_id with the
-- activity-timestamp bump — is identical.
--
-- owner_user_id is NEVER touched. Only rpc_room_create (db/027) writes
-- that column; seize transfers room CONTROL only.
--
-- ─── Engagement-prompt is client-side ──────────────────────────────────
-- Per ROOM-AUTHORITY-MODEL.md § "Seize authority":
--
--   "An HH admin who seizes a room while already engaged in another
--    room fires the normal one-engagement 'Leave [room A] to seize
--    [room B]?' confirmation — seize is an engagement transition
--    like any other room-join."
--
-- The prompt fires on the phone BEFORE this RPC is called. The RPC
-- itself is a single atomic seize — nothing here asks for
-- confirmation; if the client wanted to bail at the prompt, it
-- would not call this RPC in the first place. The future
-- "administrative actions without engagement transition"
-- enhancement (separate DEFERRED entry) would change the CLIENT-
-- side UX, not this RPC. The RPC's contract is: every call that
-- passes the guards seizes; no per-call client confirmation
-- logic on the server.
--
-- ─── Idempotency / transaction wrapping ─────────────────────────────────
-- DROP FUNCTION IF EXISTS before CREATE (per the c657c9f DROP-FUNCTION-
-- IF-EXISTS discipline). begin;/commit; envelope. Safe to re-run.
--
-- ─── Verification footer: see after COMMIT ──────────────────────────────
-- ============================================================================


begin;


-- DROP first for idempotency (per the c657c9f discipline). First-time
-- apply is a no-op DROP; protects re-runs and partial-state recovery.
drop function if exists public.rpc_room_seize(uuid);


create function public.rpc_room_seize(p_room_id uuid)
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
  -- Guard 1: caller must be authenticated.
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- Guard 2: room must exist.
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then
    raise exception 'room not found: %', p_room_id using errcode = '02000';
  end if;

  -- Guard 3: room must not have ended.
  if v_room.ended_at is not null then
    raise exception 'room has ended' using errcode = '02000';
  end if;

  -- Guard 4a: premium-control layer requires the room be bound to a
  -- screen. Screenless rooms have no embedding capability to gate on
  -- and are therefore outside seize's scope.
  if v_room.screen_ref is null then
    raise exception 'room is not bound to a screen (premium-control layer inactive)'
      using errcode = '42501';
  end if;

  -- Guard 4b: the bound screen must be embedding-capable. Reads the
  -- can_embed column shipped via db/030. With the self-report writer
  -- still deferred, every row currently reads false in prod — every
  -- seize attempt rejects here until the writer lands. Correct
  -- interim safety; see migration header.
  if not exists (
    select 1
      from public.tv_devices
     where id        = v_room.screen_ref
       and can_embed = true
  ) then
    raise exception 'premium-control layer not active for this room''s screen'
      using errcode = '42501';
  end if;

  -- Guard 5: caller must satisfy convener-seize OR admin-seize.
  --   Convener-seize: caller IS the room's original convener
  --                   (auth.uid() = rooms.owner_user_id).
  --   Admin-seize:    caller is an admin of a household where the
  --                   room's owner is also a member.
  -- The admin-seize self-join mirrors is_household_admin's
  -- role-comparison shape (db/006:172) exactly: hm_admin.role =
  -- 'admin', matching the household_members.role CHECK constraint.
  if v_user_id <> v_room.owner_user_id
     and not exists (
       select 1
         from public.household_members hm_admin
         join public.household_members hm_owner
           on hm_admin.household_id = hm_owner.household_id
        where hm_admin.user_id = v_user_id
          and hm_admin.role    = 'admin'
          and hm_owner.user_id = v_room.owner_user_id
     )
  then
    raise exception 'only the room owner or an admin of the owner''s household may seize this room'
      using errcode = '42501';
  end if;

  -- Engagement-prompt note (per ROOM-AUTHORITY-MODEL.md § "Seize
  -- authority"): the one-engagement "Leave [room A] to seize
  -- [room B]?" confirmation is a CLIENT-SIDE concern. The prompt
  -- fires on the phone BEFORE this RPC is called; the RPC is a
  -- single atomic seize and does NOT ask for confirmation. If the
  -- user bails at the prompt, the client never calls this RPC.
  -- The future "administrative actions without engagement
  -- transition" enhancement (separate DEFERRED entry) would change
  -- the CLIENT-side UX, not this RPC.

  -- Demote-then-promote mechanic (copied verbatim from db/028's
  -- reclaim RPCs §§1 + 3). The only differences vs. those RPCs are
  -- the auth gates above and the absence of the 10-min inactivity
  -- check; the mechanic itself is identical.
  --
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


grant execute on function public.rpc_room_seize(uuid) to authenticated;


comment on function public.rpc_room_seize(uuid) is
  'Ownership-seize RPC per ROOM-AUTHORITY-MODEL.md § "Seize authority". '
  'Immediate take-control operation, distinct from the inactivity-'
  'reclaim path (rpc_session_reclaim_manager / rpc_session_admin_reclaim). '
  'Gated on three auth checks: (a) authenticated; (b) premium-control '
  'layer active for the room (rooms.screen_ref → tv_devices.can_embed '
  '= true); (c) convener-seize (auth.uid() = rooms.owner_user_id) OR '
  'admin-seize (caller is an admin of a household where the room owner '
  'is a member). Demote-then-promote mechanic copied verbatim from '
  'db/028''s reclaim RPCs; writes rooms.controller_user_id, bumps '
  'rooms.last_activity_at and the active session''s last_activity_at. '
  'rooms.owner_user_id is NEVER touched. Engagement-prompt is a '
  'client-side concern; this RPC is a single atomic seize.';


commit;


-- ─── Verification ─────────────────────────────────────────────────────────
select 'migration 031 loaded' as status;

-- ============================================================================
-- POST-MIGRATION VERIFICATION
-- Run against prod via Supabase SQL Editor after applying.
--
-- 1. The function exists with the expected signature and SECURITY
--    DEFINER attribute.
--    SELECT proname,
--           proargnames,
--           pg_get_function_arguments(oid)           AS args,
--           pg_get_function_result(oid)              AS returns,
--           prosecdef                                AS security_definer
--      FROM pg_proc
--     WHERE proname      = 'rpc_room_seize'
--       AND pronamespace = 'public'::regnamespace;
--    Expect: 1 row.
--      proname           = 'rpc_room_seize'
--      proargnames       = {p_room_id}
--      args              = 'p_room_id uuid'
--      returns           = 'rooms'
--      security_definer  = true
--
-- 2. The function body contains the three guards (premium-control
--    layer + convener-OR-admin), the demote query, and the controller
--    update.
--    SELECT pg_get_functiondef(oid)
--      FROM pg_proc
--     WHERE proname      = 'rpc_room_seize'
--       AND pronamespace = 'public'::regnamespace;
--    Expect the body to contain (manual inspection):
--      - 'tv_devices' and 'can_embed = true' (guard 4b)
--      - 'owner_user_id' (guard 5 — convener-seize half)
--      - 'household_members hm_admin' and 'hm_admin.role    = ''admin'''
--        (guard 5 — admin-seize half)
--      - 'control_role = ''none''' AND 'control_role = ''manager'''
--        (the demote-then-promote mechanic)
--      - 'update public.rooms' with 'controller_user_id = v_user_id'
--        and 'last_activity_at   = now()'
--      - Should NOT contain 'owner_user_id =' on any UPDATE/INSERT
--        statement against rooms (preservation guarantee).
--
-- 3. GRANT EXECUTE to authenticated.
--    SELECT has_function_privilege('authenticated',
--                                    p.oid,
--                                    'EXECUTE') AS authed
--      FROM pg_proc p
--     WHERE p.proname      = 'rpc_room_seize'
--       AND p.pronamespace = 'public'::regnamespace;
--    Expect: authed = true.
--
-- 4. owner_user_id sole-writer guarantee preserved (re-run the
--    sentinel check from db/027 + db/028, now including rpc_room_seize
--    in the exclusion list since it legitimately references the
--    column in a READ — the guard-5 convener check reads
--    v_room.owner_user_id but does not write it).
--    SELECT proname
--      FROM pg_proc
--     WHERE prokind        = 'f'
--       AND pronamespace   = 'public'::regnamespace
--       AND pg_get_functiondef(oid) ILIKE '%owner_user_id%'
--       AND proname NOT IN ('rpc_room_create',
--                           'rpc_session_leave',
--                           'rpc_session_reclaim_manager',
--                           'rpc_session_admin_reclaim',
--                           'rpc_room_seize')
--     ORDER BY proname;
--    Expect: 0 rows. rpc_room_create remains the sole WRITER of
--    owner_user_id (per the db/027 structural guarantee); the four
--    other functions in the exclusion list reference the column in
--    READ-only contexts (db/028 RPCs mention it in comments only;
--    rpc_session_leave reads it for the tier-1 named-successor
--    eligibility check; rpc_room_seize reads it for guard 5).
--
-- 5. Functional smoke test (manual, after a real device-claim with
--    can_embed = true exists in prod — currently no row qualifies
--    in prod because the self-report writer is deferred, so this
--    smoke test is deferred to whenever that writer lands).
--    Steps:
--      a. Set tv_devices.can_embed = true on a test device via
--         direct UPDATE (one-off, expected once the column writer
--         is no longer the only way to set the value).
--      b. Have user A create a room on that screen via
--         rpc_room_create — they're both controller and owner.
--      c. Have user B (where B is not the room's owner and is NOT
--         a member of A's household) attempt rpc_room_seize on the
--         room — expect 42501 'only the room owner or an admin of
--         the owner''s household may seize this room'.
--      d. Have user A attempt rpc_room_seize on the same room —
--         expect success (convener-seize). A is already the
--         controller; the call is effectively a no-op transfer but
--         updates last_activity_at.
--      e. Add a third user C as a 'user' (non-admin) of A's
--         household; attempt rpc_room_seize — expect 42501 (not
--         admin).
--      f. Promote C to 'admin' of A's household; attempt
--         rpc_room_seize — expect success (admin-seize).
-- ============================================================================
