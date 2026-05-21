-- ============================================================================
-- Elsewhere — Phase 1 RPC migration, batch 2 of 3: room creation + session start
-- Migration: 027
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Two RPCs land here:
--
--   • rpc_room_create (NEW)        — creates a rooms row and seats the
--                                     convener as the room's initial
--                                     manager-audience participant.
--
--   • rpc_session_start (REWRITE)  — session-creation-only under an
--                                     existing room. The OQ2 split from
--                                     PHASE-1-BUILD-SPEC.md §D: rooms
--                                     are durable, sessions are
--                                     disposable; creating a room and
--                                     starting a session are now two
--                                     separate operations.
--
-- Built against docs/PHASE-1-BUILD-SPEC.md §D as amended by commit
-- fcc42f6, and the convener-seating + cross-app-move decisions confirmed
-- in the db/027 pre-write investigation (this session, prior turn).
--
-- Three-migration grouping (db/026 / db/027 / db/028):
--   db/026 (shipped)      — 8 mechanical + rpc_session_end +
--                           rpc_session_set_admission_mode.
--   db/027 (THIS FILE)    — rpc_session_start split + new rpc_room_create.
--   db/028 (next)         — rpc_session_leave + rpc_session_reclaim_manager
--                           + rpc_session_admin_reclaim.
--
-- ─── Convener-seating decision (reviewed and confirmed) ──────────────────
-- In the old model (db/018), rpc_session_start INSERTed the manager's
-- session_participants row inline with the sessions INSERT. That cannot
-- carry forward: the room/session split means participants belong to
-- the ROOM, and ROOM-SESSION-MODEL.md's cross-app-move spec
-- ("nothing to copy") forbids re-INSERTing on each session start.
--
-- The seating split: rpc_room_create seats the convener as a
-- session_participants row with control_role='manager' and
-- participation_role='audience'. rpc_session_start does NOT
-- re-insert. The "branched per-app participation_role default" from
-- db/018 is preserved as an UPDATE on the controller's existing row
-- at every session-start, not as an INSERT.
--
-- ─── Cross-app-move scope decision (reviewed and confirmed) ──────────────
-- The branched default applies on every rpc_session_start call (fresh-
-- room first session AND cross-app moves), but ONLY to the controller's
-- row. All other room participants keep their existing participation_role
-- across a session start. Reasoning:
--
--   • In db/018, the only row created on session start was the
--     manager's — so the branched default was already manager-scoped.
--     Controller-only in the new model reproduces that exact scope.
--   • Force-applying to all participants would silently promote
--     audience-mode users to 'active' on a cross-app move, violating
--     the audience-as-mode opt-out doctrine in UNIFIED-APP-PLAN.md.
--   • ROOM-SESSION-MODEL.md §"The cross-app move" steps 3-5 say room
--     members are not touched on the move (membership and manager are
--     preserved). Touching only the controller's row (who is by
--     construction the caller of rpc_session_start) is consistent with
--     "the same manager" — the controller chose the new app, the
--     controller gets the new app's default. Other participants are
--     left to their existing roles.
--
-- ─── Queued-convener edge case (reviewed and confirmed — documented) ────
-- The branched-default UPDATE in rpc_session_start clears the
-- controller's queue_position and wanting_since unconditionally. The
-- intent is to handle a specific edge case cleanly:
--
--   A karaoke room has the controller in participation_role='queued'
--   (waiting in the singer queue). The controller initiates a
--   cross-app move to games. The session ends; a new games session
--   starts. The branched-default UPDATE flips the controller's row
--   to participation_role='active' (games default) AND clears
--   queue_position and wanting_since.
--
-- The controller loses their place in the (now-defunct) karaoke
-- queue. This is INTENDED: the karaoke session has ended, the queue
-- it indexed no longer exists, and the queue_position/wanting_since
-- fields are no longer meaningful on this row. The same clear
-- happens unconditionally on every session-start (harmless no-op
-- when the controller wasn't queued), so a future reader sees the
-- UPDATE as "the controller's queue fields are reset on every
-- session start" rather than as a special-case branch.
--
-- ─── Room_code format ────────────────────────────────────────────────────
-- 6 characters, drawn uniformly at random from a 31-character alphabet:
--   uppercase A-Z (23 letters; I, L, O excluded as visually ambiguous)
--   digits     0-9 (8 digits; 0, 1 excluded as visually ambiguous)
--
-- Alphabet (verbatim): ABCDEFGHJKMNPQRSTUVWXYZ23456789
-- That is: A B C D E F G H J K M N P Q R S T U V W X Y Z 2 3 4 5 6 7 8 9.
-- Excluded: I L O (letters) and 0 1 (digits).
--
-- Collision space at any moment: 31^6 ≈ 887 million distinct codes.
-- With the partial UNIQUE index rooms_one_active_per_code restricting
-- uniqueness to non-ended rooms only, real collision probability is
-- negligible even at tens of thousands of concurrent rooms.
--
-- ─── Collision-retry pattern (per §D pinned decision) ────────────────────
-- rpc_room_create generates a candidate room_code, attempts the INSERT,
-- catches SQLSTATE 23505 (unique_violation) on the partial UNIQUE
-- rooms_one_active_per_code, and retries with a fresh code. Bounded to
-- 5 attempts. If all 5 attempts collide (vanishingly unlikely with a
-- 887M-code space), raise a clear error rather than looping unbounded.
--
-- The retry loop scope: ONLY the rooms INSERT is in the catch — the
-- subsequent session_participants INSERT (the convener seat) is not
-- subject to collision and runs after the rooms row is committed within
-- the function. If the function as a whole rolls back (e.g., the
-- session_participants INSERT fails for some reason), the rooms row
-- created in the same transaction also rolls back. Atomic.
--
-- ─── Owner-user-id sole-writer guarantee ─────────────────────────────────
-- rpc_room_create is THE ONLY RPC in the entire system that writes to
-- rooms.owner_user_id. It writes it at room creation and never again.
-- No other RPC anywhere — not the reclaim RPCs, not the leave RPC, not
-- anything in db/028 or beyond — ever touches owner_user_id. This is
-- the structural guarantee from PHASE-1-BUILD-SPEC.md OQ2 option (a):
-- ownership is set once at room creation and is immutable thereafter.
-- The comment is repeated on rpc_room_create's body below for
-- prominence; if a future migration adds an owner_user_id writer, the
-- guarantee breaks and ROOM-AUTHORITY-MODEL.md's ownership-never-
-- transfers contract is violated.
--
-- ─── §D Cross-cutting decisions applied ──────────────────────────────────
-- Activity-timestamp target — both RPCs bump rooms.last_activity_at
-- (required for the reclaim 10-min inactivity gate). rpc_room_create
-- gets the bump for free via the rooms.last_activity_at column default
-- (now()) on INSERT; no explicit bump needed. rpc_session_start bumps
-- rooms.last_activity_at explicitly and relies on the
-- sessions.last_activity_at column default for the new sessions row.
--
-- ─── Auth model ──────────────────────────────────────────────────────────
-- rpc_room_create: caller must be authenticated. If p_screen_ref is
-- non-null, caller must additionally be a household member of that TV
-- device's household (is_tv_household_member). Screenless rooms
-- (p_screen_ref IS NULL) require only authentication — invite-based
-- access for non-household users lands in a later phase.
--
-- rpc_session_start: caller must be authenticated AND must be the
-- current room controller (rooms.controller_user_id = auth.uid()).
-- This is unchanged in spirit from db/018's manager-only session
-- creation, just resolved through the new canonical source.
--
-- ─── Idempotency / transaction wrapping ──────────────────────────────────
-- CREATE OR REPLACE FUNCTION for both. BEGIN/COMMIT envelope. If
-- either CREATE fails, the migration rolls back. Safe to re-run.
--
-- ─── Verification footer: see after COMMIT ──────────────────────────────
-- ============================================================================


begin;


-- ─── 1. rpc_room_create (NEW) ────────────────────────────────────────────
-- Creates a new room and seats the convener as control_role='manager',
-- participation_role='audience'. Generates a fresh room_code (6 chars,
-- 31-char alphabet; see header) with collision-retry bounded to 5
-- attempts. The ONLY RPC that writes rooms.owner_user_id — set once at
-- creation, immutable thereafter (see header for the structural
-- guarantee).
create or replace function public.rpc_room_create(
  p_screen_ref uuid default null
)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id    uuid := auth.uid();
  v_alphabet   text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';  -- 31 chars (see header)
  v_alpha_len  int  := length(v_alphabet);
  v_code       text;
  v_attempt    int := 0;
  v_room       public.rooms;
  v_i          int;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- Auth gate for bound rooms: if a screen is named, the caller must
  -- be a household member of that TV device's household. Screenless
  -- rooms (p_screen_ref IS NULL) require only authentication; the
  -- invite-based path for non-household access lands in a later phase.
  if p_screen_ref is not null then
    if not public.is_tv_household_member(p_screen_ref) then
      raise exception 'not a member of the screen''s TV household'
        using errcode = '42501';
    end if;
  end if;

  -- room_code generation with bounded collision-retry. The candidate is
  -- generated by sampling 6 indices uniformly from the 31-char alphabet
  -- (see header for the alphabet). On SQLSTATE 23505 from the partial
  -- UNIQUE index rooms_one_active_per_code, retry with a fresh code.
  -- After 5 failed attempts, raise — the 31^6 ≈ 887M-code space makes
  -- 5 collisions in a row vanishingly unlikely; an exhausted retry
  -- loop indicates something is very wrong (e.g., random() returning
  -- a constant), not a real saturation of room codes.
  loop
    v_attempt := v_attempt + 1;

    v_code := '';
    for v_i in 1..6 loop
      v_code := v_code
              || substr(v_alphabet,
                        1 + floor(random() * v_alpha_len)::int,
                        1);
    end loop;

    begin
      insert into public.rooms (
        room_code,
        controller_user_id,
        owner_user_id,            -- SOLE WRITER: this RPC, this line,
                                  -- this migration. owner_user_id is
                                  -- never written by any other RPC.
                                  -- See header for the structural
                                  -- guarantee.
        screen_ref
      )
      values (
        v_code,
        v_user_id,
        v_user_id,                -- convener is both controller and
                                  -- owner at room creation
        p_screen_ref
      )
      returning * into v_room;

      exit;  -- success
    exception
      when unique_violation then
        if v_attempt >= 5 then
          raise exception 'failed to generate a unique room_code after 5 attempts (rooms_one_active_per_code collisions)'
            using errcode = '23505';
        end if;
        -- otherwise loop and try a fresh code
    end;
  end loop;

  -- Seat the convener as the room's initial manager. This is the new-
  -- model replacement for db/018's inline-with-session-INSERT manager
  -- seat. participation_role='audience' is the neutral default at room
  -- creation — no app/session yet. rpc_session_start applies the
  -- branched per-app default to this row on session start; see
  -- rpc_session_start below.
  insert into public.session_participants (
    room_id, user_id, control_role, participation_role
  )
  values (
    v_room.id, v_user_id, 'manager', 'audience'
  );

  -- rooms.last_activity_at is set by the column default (now()) on the
  -- INSERT above; no explicit bump needed.

  return v_room;
end;
$$;

grant execute on function public.rpc_room_create(uuid) to authenticated;

comment on function public.rpc_room_create(uuid) is
  'Creates a new room and seats the caller as the initial manager-'
  'audience participant. Generates a 6-char room_code from a 31-char '
  'alphabet (uppercase A-Z and digits 2-9, excluding visually-ambiguous '
  'I L O 0 1). Collision-retry bounded to 5 attempts on the partial '
  'UNIQUE rooms_one_active_per_code. p_screen_ref optional: if non-null, '
  'caller must be a household member of that screen''s household; if '
  'null, the room is screenless. THE ONLY RPC that writes '
  'rooms.owner_user_id — set once at creation, never written by any '
  'other RPC (structural guarantee per PHASE-1-BUILD-SPEC.md OQ2).';


-- ─── 2. rpc_session_start (REWRITE — OQ2 split) ──────────────────────────
-- Session-creation-only. Caller must be the room's current controller
-- (rooms.controller_user_id = auth.uid()). Does NOT create rooms (use
-- rpc_room_create), does NOT insert session_participants rows (the
-- room's members already exist; rpc_room_create seated the controller).
--
-- The "branched participation_role default" from db/018 lands here as
-- an UPDATE on the controller's existing session_participants row:
-- p_app='games' → participation_role='active'; else → 'audience'. The
-- UPDATE also unconditionally clears the controller's queue_position
-- and wanting_since on every session-start. The unconditional clear is
-- harmless when the controller wasn't queued (no-op); when the
-- controller WAS queued (e.g. waiting in the karaoke singer queue at
-- the moment of a cross-app move), it intentionally drops their queue
-- place — the karaoke session has ended, the queue it indexed no
-- longer exists, and queue_position / wanting_since are no longer
-- meaningful on this row. See the queued-convener edge-case note in
-- the file header.
--
-- The UPDATE affects ONLY the controller's row (matched on
-- room_id, user_id = auth.uid()). All other room participants keep
-- their existing participation_role, queue_position, and wanting_since
-- across a session-start, consistent with ROOM-SESSION-MODEL.md's
-- cross-app-move "nothing to copy" / "same membership" framing.
create or replace function public.rpc_session_start(
  p_room_id         uuid,
  p_app             text,
  p_admission_mode  text,
  p_capacity        int,
  p_ask_proximity   boolean,
  p_turn_completion text
)
returns public.sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_room    public.rooms;
  v_session public.sessions;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- Room validity and controller auth.
  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null then
    raise exception 'room not found: %', p_room_id using errcode = '02000';
  end if;

  if v_room.ended_at is not null then
    raise exception 'room has ended' using errcode = '02000';
  end if;

  if v_room.controller_user_id <> v_user_id then
    raise exception 'only the current room controller can start a session'
      using errcode = '42501';
  end if;

  -- Enforce "one active session per room" with a clear error message.
  -- The sessions_one_active_per_room partial unique index (db/025) is a
  -- belt-and-suspenders fallback for concurrent inserts.
  if exists (
    select 1 from public.sessions
     where room_id = p_room_id and ended_at is null
  ) then
    raise exception 'an active session already exists in this room'
      using errcode = '23505';
  end if;

  -- Create the session row. CHECK constraints on app, admission_mode,
  -- and turn_completion enforce value-set validation.
  insert into public.sessions (
    room_id, app, admission_mode, capacity, ask_proximity, turn_completion
  )
  values (
    p_room_id, p_app, p_admission_mode, p_capacity, p_ask_proximity, p_turn_completion
  )
  returning * into v_session;

  -- Apply the branched per-app participation_role default to the
  -- controller's existing session_participants row. The UPDATE clears
  -- the controller's queue_position and wanting_since on every session-
  -- start; see the queued-convener edge-case note in the file header
  -- for why the unconditional clear is correct.
  --
  -- p_app branching:
  --   'games'   → 'active'   per docs/GAMES-CONTROL-MODEL.md § 2.4.4
  --                          (lobby-state self-join defaults to 'active';
  --                          the controller initiating a games session
  --                          is committing to play).
  --   karaoke   → 'audience' per docs/KARAOKE-CONTROL-MODEL.md § 1
  --                          (schema-state 'audience' on HHU surfaces
  --                          means "Available Singer (not queued)"; the
  --                          karaoke controller hasn't queued a song
  --                          yet, so this is the correct initial state).
  --   anything  → 'audience' as a safe default until that app's control
  --   else                   model spec defines lobby-state semantics.
  --
  -- The UPDATE is row-scoped to the controller (room_id + user_id +
  -- left_at IS NULL match). If the controller's row does not exist
  -- (which should not happen — rpc_room_create seated them and only the
  -- removal path could un-seat — but defensively), the UPDATE matches
  -- zero rows and the function continues. No error; the controller can
  -- be re-seated via rpc_session_join if needed.
  update public.session_participants
     set participation_role = case
                                when p_app = 'games' then 'active'
                                else                      'audience'
                              end,
         queue_position     = null,
         wanting_since      = null
   where room_id  = p_room_id
     and user_id  = v_user_id
     and left_at is null;

  -- Activity bump on the room. The sessions.last_activity_at column
  -- default (now()) on the INSERT above already provides the session-
  -- level bump.
  update public.rooms set last_activity_at = now() where id = p_room_id;

  return v_session;
end;
$$;

grant execute on function public.rpc_session_start(uuid, text, text, int, boolean, text) to authenticated;

comment on function public.rpc_session_start(uuid, text, text, int, boolean, text) is
  'Creates a new session under an existing room. Caller must be the '
  'current room controller (rooms.controller_user_id). Does NOT create '
  'the room (use rpc_room_create); does NOT insert session_participants '
  'rows. Applies the branched participation_role default '
  '(games→''active'', else→''audience'') to the controller''s '
  'existing session_participants row via an UPDATE, and clears the '
  'controller''s queue_position and wanting_since unconditionally on '
  'every session-start (harmless when not queued; drops the karaoke '
  'queue place on a cross-app move from karaoke-queued — intended, '
  'see file header). Other room participants are unaffected. Bumps '
  'rooms.last_activity_at; sessions.last_activity_at is set by the '
  'column default on INSERT.';


commit;


-- ─── Verification ─────────────────────────────────────────────────────────
select 'migration 027 loaded' as status;

-- ============================================================================
-- POST-MIGRATION VERIFICATION
-- Run against prod via Supabase SQL Editor after applying.
--
-- 1. Both RPCs exist with expected parameter NAMES.
--    SELECT proname, proargnames
--      FROM pg_proc
--     WHERE proname IN ('rpc_room_create', 'rpc_session_start')
--     ORDER BY proname;
--    Expect 2 rows. proargnames for rpc_room_create = {p_screen_ref};
--    proargnames for rpc_session_start = {p_room_id, p_app,
--    p_admission_mode, p_capacity, p_ask_proximity, p_turn_completion}.
--    Note rpc_session_start has 6 args (down from 7 in db/018; p_room_code
--    and p_tv_device_id are gone, p_room_id is added).
--
-- 2. rpc_room_create writes owner_user_id (the sole writer in the system).
--    SELECT pg_get_functiondef(oid)
--      FROM pg_proc WHERE proname = 'rpc_room_create';
--    Expect: body INSERTs into public.rooms with controller_user_id AND
--    owner_user_id columns, both set to v_user_id. The body should also
--    INSERT into public.session_participants with control_role='manager'
--    and participation_role='audience' for the convener.
--
-- 3. rpc_session_start UPDATEs the controller's participation_role per
--    the branched default and does NOT insert into session_participants.
--    SELECT pg_get_functiondef(oid)
--      FROM pg_proc WHERE proname = 'rpc_session_start';
--    Expect: body contains UPDATE public.session_participants SET
--    participation_role = case when p_app = 'games' ... and clears
--    queue_position + wanting_since. Expect: body does NOT contain any
--    INSERT INTO public.session_participants.
--
-- 4. Both RPCs bump rooms.last_activity_at (rpc_room_create via the
--    INSERT default; rpc_session_start via an explicit UPDATE).
--    For rpc_room_create: confirm via the rooms table column default —
--    SELECT column_default FROM information_schema.columns
--      WHERE table_name='rooms' AND column_name='last_activity_at';
--    Expect: 'now()'.
--    For rpc_session_start: confirm via pg_get_functiondef shows
--    `update public.rooms set last_activity_at = now()`.
--
-- 5. Sole-writer guarantee on rooms.owner_user_id — no other function
--    in the schema writes to it.
--    SELECT proname
--      FROM pg_proc
--     WHERE pg_get_functiondef(oid) ILIKE '%owner_user_id%'
--       AND proname NOT IN ('rpc_room_create')
--     ORDER BY proname;
--    Expect: 0 rows after db/027 lands. If any rows appear, an offending
--    writer exists and the structural guarantee is violated.
--
-- 6. GRANT EXECUTE to authenticated is present for both RPCs.
--    SELECT p.proname,
--           has_function_privilege('authenticated', p.oid, 'EXECUTE') as authed
--      FROM pg_proc p
--     WHERE p.proname IN ('rpc_room_create', 'rpc_session_start')
--     ORDER BY p.proname;
--    Expect: authed = TRUE for both rows.
-- ============================================================================
