-- ============================================================================
-- Elsewhere — Phase 1 room/session schema migration
-- Migration: 025
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Introduces the durable `rooms` entity, demotes `sessions` to a per-app
-- instance under a room, and re-anchors `session_participants` from
-- session_id to room_id. Built against docs/PHASE-1-BUILD-SPEC.md as
-- amended by commit c54d09e (the 11-step §C plan that includes the
-- fire_promotion_push trigger drop per §A's MISSED row).
--
-- SCHEMA-ONLY. The 14 room-keyed RPCs and the new rpc_room_create are
-- db/026 onward, out of scope here. The only RPC-/trigger-related
-- statements in this migration are two DROPs (no function bodies are
-- written or rewritten):
--   1. rpc_session_promote_self_from_queue — dead since admission-model
--      v2; zero live callers per build spec §A.
--   2. trg_fire_promotion_push + fire_promotion_push() — the function
--      body reads NEW.session_id, which this migration drops. Recreation
--      with room_id awareness is tracked in build spec §D as a separate
--      worklist item for db/026 onward. The recreation is deferred
--      pending a decision on payload shape (room_id, session_id, or
--      both) that requires auditing the out-of-repo iOS app's use of
--      data.session_id from the APNs payload. Until the recreation
--      lands, the queued→active promotion push does NOT fire —
--      backgrounded iOS users do not receive the "you're up" push;
--      foreground UI is unaffected (the realtime broadcast still
--      drives it). The deferred recreation is deliberate and tracked.
--
-- Resolved open questions folded in (per docs/EXECUTION-HANDOFF.md §4):
--   • OQ1: rooms.room_code carries a partial UNIQUE index — unique on
--     (room_code) where ended_at is null. Active room codes are
--     unambiguously resolvable; historical (ended) rooms may reuse codes.
--   • OQ2: option (a) — rpc_session_start session-creation-only and the
--     new rpc_room_create ship in db/026 onward, NOT in this migration.
--   • OQ3: sessions.current_state is KEPT (dormant scaffolding; zero
--     writers confirmed in build spec §A). NOT in the column-drop list
--     in section 8 below.
--   • OQ4: the is_session_* compat wrappers ARE included here and kept
--     through Phase 1. A Phase-1.1 cleanup will drop them after an
--     explicit grep-confirmed zero-caller check.
--
-- Operational ordering notes: the build spec §C lists 11 logical steps.
-- This migration adds three implementation-detail operations the spec
-- abstracts away — pre-emptive drops of the OLD SELECT policies on
-- sessions / session_participants (section 5) and the OLD is_session_*
-- helpers (section 6) — which must run before the column drops they
-- depend on. The build spec's policy "update" (step 9) lands as fresh
-- CREATE POLICY statements (sections 11 and 12), because the old
-- policies were dropped earlier. The rooms SELECT policy promised by
-- build spec §C step 5 lands in section 11 rather than alongside the
-- table itself (section 7), since it references room-keyed helpers that
-- only exist after section 10.
--
-- Cutover model: existing session and session_participants data is
-- cleared as a migration pre-step (build spec §C step 2). Data is
-- ephemeral and pre-launch — nothing of value is lost — and the new
-- NOT NULL constraint on room_id becomes safe.
--
-- RLS recursion mechanism: the new is_room_* helpers (section 10) and
-- the compat is_session_* wrappers (section 13) all use SECURITY DEFINER
-- and inherit the pattern established by db/006 and db/008. The
-- canonical explanation is in db/006's header comment (lines 38-46):
-- the helper runs as the function owner (the migration-runner role,
-- postgres / supabase_admin in Supabase, which has RLS bypass via
-- superuser / BYPASSRLS), so the helper's internal query against the
-- participating tables bypasses RLS and cannot recurse into the
-- policies that call it. The helpers still explicitly filter by
-- user_id = auth.uid() so they cannot leak other users' data. The
-- function-level comments below abbreviate this rationale to match the
-- existing db/008 convention; consult db/006 for the full explanation.
--
-- Idempotency: CREATE ... IF NOT EXISTS, DROP ... IF EXISTS,
-- CREATE OR REPLACE FUNCTION, ADD COLUMN IF NOT EXISTS, DROP COLUMN
-- IF EXISTS, DROP POLICY IF EXISTS preceding each CREATE POLICY. Safe
-- to re-run.
--
-- Verification queries: see the footer (section 14), aligned with
-- build spec §C step 11's 8 queries plus three additional post-hoc
-- sanity checks for compat wrappers, room-keyed policies, and the
-- 4+1 index outcome.
-- ============================================================================


-- ─── 2. Clear ephemeral session state (build spec §C step 2) ──────────────
-- Order matters: participants first (FK to sessions), sessions second.
-- The db/015 promotion-push trigger is participation_role-transition
-- gated; a mass DELETE does not fire it. (The trigger is dropped
-- explicitly in section 4 below regardless.)
delete from public.session_participants;
delete from public.sessions;


-- ─── 3. Drop the dead RPC (build spec §C step 3) ──────────────────────────
-- rpc_session_promote_self_from_queue was superseded by admission-model
-- v2 (db/020 onward). Zero live callers per build spec §A. The 14
-- room-keyed RPCs in db/026 onward do NOT include a successor.
drop function if exists public.rpc_session_promote_self_from_queue(uuid);


-- ─── 4. Drop fire_promotion_push trigger + function (build spec §C step 4)
-- Addressing §A's MISSED row. The function body (db/015) reads
-- NEW.session_id, which section 9 below removes from session_participants.
-- Because plpgsql function bodies are not eagerly validated against the
-- schema, a function left referencing the dropped column would silently
-- survive the column drop and fail at the first matching UPDATE.
--
-- Recreation with room_id awareness is intentionally deferred to db/026
-- onward — tracked in build spec §D's "Additional tracked work"
-- subsection with the payload-shape sub-question (room_id, session_id,
-- or both) pending an iOS-app audit. Until the recreation lands,
-- queued→active promotion push notifications do NOT fire.
drop trigger if exists trg_fire_promotion_push on public.session_participants;
drop function if exists public.fire_promotion_push();


-- ─── 5. Drop the OLD SELECT policies on sessions + session_participants ──
-- Implementation detail (not an explicit build spec §C step). The OLD
-- policies (defined in db/008) reference sessions.tv_device_id and
-- session_participants.session_id, both dropped in sections 8 and 9.
-- Postgres would otherwise refuse the column drop. The new room-keyed
-- policies are created fresh in sections 11 and 12.
drop policy if exists "sessions: participants and household members read"
  on public.sessions;

drop policy if exists "session_participants: co-participants and household members read"
  on public.session_participants;


-- ─── 6. Drop the OLD is_session_* helpers ────────────────────────────────
-- Implementation detail. The OLD helper bodies (db/008) are `language sql`
-- (eagerly validated) and query session_participants WHERE session_id =
-- ... and sessions.tv_device_id. Postgres would block the column drops
-- without dropping these first. Compat wrappers with the same signatures
-- are recreated in section 13, delegating through sessions.room_id to
-- the new room-keyed helpers from section 10.
drop function if exists public.is_session_participant(uuid);
drop function if exists public.is_session_tv_household_member(uuid);
drop function if exists public.is_session_tv_household_admin(uuid);


-- ─── 7. Create rooms table + indexes; enable RLS (build spec §B + §C step 5)
-- SELECT policy lands in section 11 after is_room_* helpers exist
-- (section 10).
create table if not exists public.rooms (
  id                  uuid        primary key default gen_random_uuid(),
  room_code           text        not null,
  controller_user_id  uuid        not null references auth.users(id),
  owner_user_id       uuid        not null references auth.users(id),
  screen_ref          uuid                 references public.tv_devices(id) on delete set null,
  created_at          timestamptz not null default now(),
  last_activity_at    timestamptz not null default now(),
  ended_at            timestamptz
);

comment on table public.rooms is
  'A durable gathering of people, independent of which app is currently '
  'running. controller_user_id is the current room controller (operational '
  'authority, fully transferable). owner_user_id is the original convener '
  '(personal authority, never transfers by succession; only rpc_room_create '
  'in db/026 onward writes this column). screen_ref is the screen the room '
  'is bound to; NULL for scanned/unclaimed or screenless rooms. See '
  'docs/ROOM-SESSION-MODEL.md and docs/ROOM-AUTHORITY-MODEL.md.';

-- OQ1: partial UNIQUE index on room_code among non-ended rooms. Active
-- room codes are unambiguously resolvable; historical (ended) rooms may
-- reuse codes.
create unique index if not exists rooms_one_active_per_code
  on public.rooms(room_code)
  where ended_at is null;

-- One active room per physical screen (when bound). Mirrors the
-- (now-dropped) sessions_one_active_per_tv partial-unique idiom from db/008.
create unique index if not exists rooms_one_active_per_screen
  on public.rooms(screen_ref)
  where screen_ref is not null and ended_at is null;

alter table public.rooms enable row level security;


-- ─── 8. Demote sessions: add room_id, drop moved columns (§C step 6) ─────
-- Drop the existing partial-unique index first; it depends on
-- tv_device_id which is dropped below. (Postgres would CASCADE-drop it,
-- but explicit is clearer.)
drop index if exists public.sessions_one_active_per_tv;

-- Add room_id nullable first (so IF NOT EXISTS is meaningful on re-run),
-- then set NOT NULL. The NOT NULL is safe because section 2 emptied the
-- table.
alter table public.sessions
  add column if not exists room_id uuid references public.rooms(id) on delete cascade;

alter table public.sessions
  alter column room_id set not null;

-- OQ3: sessions.current_state is NOT in the drop list — it stays as
-- dormant scaffolding (zero writers confirmed in build spec §A).
alter table public.sessions
  drop column if exists tv_device_id,
  drop column if exists manager_user_id,
  drop column if exists room_code;

-- New invariant: at most one active session per room.
create unique index if not exists sessions_one_active_per_room
  on public.sessions(room_id)
  where ended_at is null;


-- ─── 9. Re-anchor session_participants: session_id → room_id (§C step 7)
-- Per build spec §E3, FOUR of the five existing session_participants
-- indexes re-key from session_id to room_id. The fifth —
-- session_participants_user_idx, on (user_id) — is NOT re-keyed; it stays
-- as-is because it is user-scoped, not session-scoped, and the
-- "list my active rooms" query needs it.
drop index if exists public.session_participants_one_manager;
drop index if exists public.session_participants_one_active_per_user;
drop index if exists public.session_participants_queue_idx;
drop index if exists public.session_participants_heartbeat_idx;

alter table public.session_participants
  add column if not exists room_id uuid references public.rooms(id) on delete cascade;

alter table public.session_participants
  alter column room_id set not null;

alter table public.session_participants
  drop column if exists session_id;

-- Recreate the four indexes as room-scoped. Predicates and column
-- structure are unchanged from db/008 + db/024; only the leading
-- column swaps from session_id to room_id.
create unique index if not exists session_participants_one_manager
  on public.session_participants(room_id)
  where control_role = 'manager' and left_at is null;

create unique index if not exists session_participants_one_active_per_user
  on public.session_participants(room_id, user_id)
  where left_at is null;

create index if not exists session_participants_queue_idx
  on public.session_participants(room_id, queue_position)
  where queue_position is not null and left_at is null;

create index if not exists session_participants_heartbeat_idx
  on public.session_participants(room_id, last_seen_at)
  where left_at is null;


-- ─── 10. Create room-keyed RLS helpers (build spec §C step 8) ────────────
-- SECURITY DEFINER, matching the pattern db/008 established for the
-- session-keyed siblings and db/006 documented canonically in its
-- header. Created AFTER session_participants.room_id and rooms.id both
-- exist (sections 7 and 9), so the `language sql` bodies validate
-- against the present schema.

create or replace function public.is_room_participant(p_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1
      from public.session_participants
     where room_id  = p_room_id
       and user_id  = auth.uid()
       and left_at is null
  );
$$;

comment on function public.is_room_participant(uuid) is
  'True if the currently-authenticated user has an active (left_at is '
  'null) session_participants row for the given room. Returns false when '
  'the caller is not authenticated. SECURITY DEFINER to avoid recursion '
  'through session_participants RLS — see db/006 header for the canonical '
  'mechanism explanation. The room-keyed sibling of the (now compat-'
  'wrapped) is_session_participant.';


create or replace function public.is_room_tv_household_member(p_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1
      from public.rooms             r
      join public.tv_devices        td on td.id = r.screen_ref
      join public.household_members hm on hm.household_id = td.household_id
     where r.id          = p_room_id
       and r.screen_ref is not null
       and hm.user_id   = auth.uid()
  );
$$;

comment on function public.is_room_tv_household_member(uuid) is
  'True if the given room has a screen (screen_ref is not null) AND the '
  'currently-authenticated user is a member of that screen''s household. '
  'Returns false for screenless rooms (screen_ref is null) — household-'
  'gated auth does not apply to those. SECURITY DEFINER per the pattern '
  'documented in db/006''s header. The room-keyed sibling of the (now '
  'compat-wrapped) is_session_tv_household_member.';


create or replace function public.is_room_tv_household_admin(p_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1
      from public.rooms             r
      join public.tv_devices        td on td.id = r.screen_ref
      join public.household_members hm on hm.household_id = td.household_id
     where r.id          = p_room_id
       and r.screen_ref is not null
       and hm.user_id   = auth.uid()
       and hm.role      = 'admin'
  );
$$;

comment on function public.is_room_tv_household_admin(uuid) is
  'True if the given room has a screen AND the currently-authenticated '
  'user is an admin of that screen''s household (household_members.role '
  '= ''admin''). Returns false for screenless rooms. Sibling to '
  'is_room_tv_household_member with the admin-role filter; the room-keyed '
  'sibling of is_session_tv_household_admin.';


-- ─── 11. SELECT policy: rooms (build spec §C step 5 — policy portion) ───
-- Deferred from section 7 until the helpers it references existed.
-- Room participants OR household members of the room's TV (when bound)
-- may read. No INSERT/UPDATE/DELETE policies — mutations flow through
-- the SECURITY DEFINER RPCs in db/026 onward.
drop policy if exists "rooms: participants and household members read"
  on public.rooms;

create policy "rooms: participants and household members read"
  on public.rooms
  for select
  using (
    public.is_room_participant(id)
    or public.is_room_tv_household_member(id)
  );


-- ─── 12. SELECT policies: sessions + session_participants (§C step 9) ───
-- "Update SELECT policies" from the build spec; lands as fresh CREATE
-- POLICY because the originals were dropped in section 5. The new
-- bodies key on room_id and delegate to the room-keyed helpers from
-- section 10.
drop policy if exists "sessions: participants and household members read"
  on public.sessions;

create policy "sessions: participants and household members read"
  on public.sessions
  for select
  using (
    public.is_room_participant(room_id)
    or public.is_room_tv_household_member(room_id)
  );

drop policy if exists "session_participants: co-participants and household members read"
  on public.session_participants;

create policy "session_participants: co-participants and household members read"
  on public.session_participants
  for select
  using (
    public.is_room_participant(room_id)
    or public.is_room_tv_household_member(room_id)
  );


-- ─── 13. Compatibility wrappers for is_session_* (build spec §C step 10) ─
-- OQ4 keeps these through Phase 1. They retain the original
-- (p_session_id uuid) signatures — so any unmigrated plpgsql RPC body
-- that still calls them keeps working — but the new bodies delegate to
-- the room-keyed helpers via sessions.room_id. A Phase-1.1 cleanup will
-- drop these wrappers after an explicit grep-confirmed zero-caller check.

create or replace function public.is_session_participant(p_session_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_room_participant(
    (select room_id from public.sessions where id = p_session_id)
  );
$$;

comment on function public.is_session_participant(uuid) is
  'Phase-1 compatibility wrapper (db/025). Resolves session_id → room_id '
  'via the sessions table and delegates to is_room_participant. To be '
  'dropped in a Phase-1.1 cleanup with a grep-confirmed zero-caller check.';


create or replace function public.is_session_tv_household_member(p_session_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_room_tv_household_member(
    (select room_id from public.sessions where id = p_session_id)
  );
$$;

comment on function public.is_session_tv_household_member(uuid) is
  'Phase-1 compatibility wrapper (db/025). Resolves session_id → room_id '
  'via the sessions table and delegates to is_room_tv_household_member. '
  'To be dropped in a Phase-1.1 cleanup with a grep-confirmed zero-caller '
  'check.';


create or replace function public.is_session_tv_household_admin(p_session_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_room_tv_household_admin(
    (select room_id from public.sessions where id = p_session_id)
  );
$$;

comment on function public.is_session_tv_household_admin(uuid) is
  'Phase-1 compatibility wrapper (db/025). Resolves session_id → room_id '
  'via the sessions table and delegates to is_room_tv_household_admin. '
  'To be dropped in a Phase-1.1 cleanup with a grep-confirmed zero-caller '
  'check.';


-- ─── 14. Verification queries (build spec §C step 11) ────────────────────
-- Run via Supabase SQL Editor after applying. Queries 1-8 align with
-- build spec §C step 11's expected outcomes (queries 7-8 added in the
-- c54d09e amendment for the trigger drop). Queries 9-11 are post-hoc
-- sanity checks for the spots where this migration could quietly land
-- wrong: OQ4 compat wrappers present, all three SELECT policies
-- room_id-keyed, and the 4+1 session_participants index outcome.
--
--   -- 1. SELECT count(*) FROM public.rooms;
--   --    expect 0
--   --
--   -- 2. \d public.sessions
--   --    expect: room_id present (NOT NULL, FK -> rooms);
--   --            tv_device_id, manager_user_id, room_code absent;
--   --            current_state still present (OQ3).
--   --
--   -- 3. \d public.session_participants
--   --    expect: room_id present (NOT NULL, FK -> rooms);
--   --            session_id absent; all other columns unchanged from
--   --            db/024 baseline (id, user_id, control_role,
--   --            participation_role, pre_selections, queue_position,
--   --            joined_at, left_at, wanting_since, last_seen_at).
--   --
--   -- 4. SELECT indexname FROM pg_indexes
--   --     WHERE tablename = 'rooms' ORDER BY indexname;
--   --    expect: rooms_one_active_per_code, rooms_one_active_per_screen,
--   --            rooms_pkey.
--   --
--   -- 5. SELECT proname FROM pg_proc
--   --     WHERE proname LIKE 'is_room%' ORDER BY proname;
--   --    expect 3 rows: is_room_participant,
--   --                   is_room_tv_household_admin,
--   --                   is_room_tv_household_member.
--   --
--   -- 6. SELECT 1 FROM pg_proc
--   --     WHERE proname = 'rpc_session_promote_self_from_queue';
--   --    expect 0 rows (dropped).
--   --
--   -- 7. SELECT 1 FROM pg_proc
--   --     WHERE proname = 'fire_promotion_push';
--   --    expect 0 rows (dropped; recreation tracked in build spec §D
--   --    for db/026 onward).
--   --
--   -- 8. SELECT 1 FROM pg_trigger
--   --     WHERE tgname = 'trg_fire_promotion_push';
--   --    expect 0 rows (dropped).
--   --
--   -- 9. SELECT proname FROM pg_proc
--   --     WHERE proname LIKE 'is_session_%' ORDER BY proname;
--   --    expect 3 rows: is_session_participant,
--   --                   is_session_tv_household_admin,
--   --                   is_session_tv_household_member (all compat
--   --                   wrappers; OQ4).
--   --
--   -- 10. SELECT tablename, polname FROM pg_policies
--   --      WHERE tablename IN ('rooms','sessions','session_participants')
--   --      ORDER BY tablename, polname;
--   --     expect 3 SELECT policies, all referencing room_id or rooms.id
--   --     (verify by inspecting the qual / definition; no remaining
--   --     references to session_id, tv_device_id, manager_user_id, or
--   --     room_code).
--   --
--   -- 11. SELECT indexname FROM pg_indexes
--   --      WHERE tablename = 'session_participants' ORDER BY indexname;
--   --     expect 6 entries: session_participants_pkey,
--   --       session_participants_heartbeat_idx,
--   --       session_participants_one_active_per_user,
--   --       session_participants_one_manager,
--   --       session_participants_queue_idx,
--   --       session_participants_user_idx (this last one unchanged from
--   --       db/008; user-scoped, not re-keyed).

select 'migration 025 loaded' as status;
