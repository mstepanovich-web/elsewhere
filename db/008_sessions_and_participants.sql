-- ============================================================================
-- Elsewhere — Universal session + participants + queue model
-- Migration: 008
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Session 5 Part 1a. Adds the universal session + participants schema that
-- replaces ad-hoc per-app coordination (room codes, Agora-broadcast lobbies,
-- ?mgr=1 URL params, etc.). All apps — karaoke, games, future wellness —
-- share this schema.
--
-- See docs/SESSION-5-PLAN.md commit 2b40313 for the full architectural plan.
--
-- Tables created:
--   • sessions              — one row per active session on a given TV
--   • session_participants  — one row per user per session
--
-- Session-level manifest snapshot columns (admission_mode, capacity,
-- ask_proximity, turn_completion) are copied from the app's role manifest at
-- rpc_session_start time. Subsequent manifest changes don't affect live
-- sessions — each session carries its own configuration.
--
-- Helper functions (SECURITY DEFINER for RLS-safety):
--   • is_session_participant(session_id uuid)         → bool
--   • is_tv_household_member(tv_device_id uuid)       → bool
--   • is_session_tv_household_member(session_id uuid) → bool
--   • is_session_tv_household_admin(session_id uuid)  → bool
--
-- RPCs are a separate concern and land in Part 1b (migration 009). This
-- migration is schema + RLS only; direct INSERT/UPDATE/DELETE are blocked
-- (RLS enabled, no write policies). All mutations will flow through
-- SECURITY DEFINER RPCs.
--
-- Idempotency: CREATE ... IF NOT EXISTS, DROP POLICY IF EXISTS + CREATE,
-- CREATE OR REPLACE FUNCTION. Safe to re-run.
-- ============================================================================


-- ─── 1. Tables ────────────────────────────────────────────────────────────

-- sessions
create table if not exists public.sessions (
  id                uuid        primary key default gen_random_uuid(),
  tv_device_id      uuid        not null references public.tv_devices(id) on delete cascade,
  app               text        not null check (app in ('karaoke', 'games', 'wellness')),
  manager_user_id   uuid        not null references auth.users(id),
  started_at        timestamptz not null default now(),
  last_activity_at  timestamptz not null default now(),
  room_code         text,
  current_state     jsonb       not null default '{}'::jsonb,
  admission_mode    text        not null check (admission_mode in (
                                  'manager_approved_single',
                                  'manager_approved_batch',
                                  'wait_for_next',
                                  'self_join'
                                )),
  capacity          int,
  ask_proximity     boolean     not null default false,
  turn_completion   text        not null check (turn_completion in (
                                  'app_declared',
                                  'indefinite'
                                )) default 'indefinite',
  ended_at          timestamptz
);

-- At most one active session per TV. Enforces the "one session per TV" invariant.
create unique index if not exists sessions_one_active_per_tv
  on public.sessions(tv_device_id) where ended_at is null;

comment on table public.sessions is
  'One row per active session on a given TV. manager_user_id tracks the '
  'CURRENT manager (updated on transfer/reclaim), not the original — '
  'session_participants is the source of truth for per-user roles. '
  'admission_mode, capacity, ask_proximity, turn_completion are snapshotted '
  'from the app''s role manifest at rpc_session_start time so live sessions '
  'are immune to manifest changes. A turn_completion value of ''timed'' is '
  'reserved for a future session — not in the current check constraint.';


-- session_participants
create table if not exists public.session_participants (
  id                 uuid        primary key default gen_random_uuid(),
  session_id         uuid        not null references public.sessions(id) on delete cascade,
  user_id            uuid        not null references auth.users(id) on delete cascade,
  control_role       text        not null check (control_role in (
                                   'manager',
                                   'host',
                                   'none'
                                 )) default 'none',
  participation_role text        not null check (participation_role in (
                                   'active',
                                   'queued',
                                   'audience'
                                 )) default 'audience',
  pre_selections     jsonb       not null default '{}'::jsonb,
  queue_position     int,
  joined_at          timestamptz not null default now(),
  left_at            timestamptz
);

-- At most one active manager per session.
create unique index if not exists session_participants_one_manager
  on public.session_participants(session_id)
  where control_role = 'manager' and left_at is null;

-- At most one active row per (session, user). Prevents duplicate active
-- participation rows. A user who leaves and rejoins gets a new row with
-- joined_at = now(); the historical row retains its left_at timestamp.
create unique index if not exists session_participants_one_active_per_user
  on public.session_participants(session_id, user_id)
  where left_at is null;

-- For "list my active sessions" queries + is_session_participant helper lookups.
create index if not exists session_participants_user_idx
  on public.session_participants(user_id);

-- For FIFO queue ordering (participation_role='queued').
create index if not exists session_participants_queue_idx
  on public.session_participants(session_id, queue_position)
  where queue_position is not null and left_at is null;

comment on table public.session_participants is
  'One row per user per session. A user who leaves and rejoins gets a new '
  'row; the old row has left_at set. control_role and participation_role '
  'are orthogonal axes — see docs/SESSION-5-PLAN.md Architecture Decision 3. '
  'pre_selections is a generic jsonb column the platform stores without '
  'inspecting; each app defines its own schema (karaoke: song/venue/costume, '
  'games: per-game-type, wellness: TBD when app ships). Read access extends '
  'to all household members of the TV''s household, not just co-participants '
  '— household members can see who''s in any active session on their TVs.';


-- ─── 2. Helper functions (SECURITY DEFINER) ──────────────────────────────
-- Defined AFTER tables because `create function ... language sql` validates
-- the function body at creation time. All helpers return false (not raise)
-- when auth.uid() is null.
--
-- SECURITY DEFINER is load-bearing: the session_participants RLS policy
-- calls is_session_participant(session_id), whose internal query also reads
-- session_participants. Without DEFINER the inner query re-enters the same
-- policy, risking recursion. Matches the pattern db/006 established for
-- is_household_member / is_household_admin.

create or replace function public.is_session_participant(p_session_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1
      from public.session_participants
     where session_id = p_session_id
       and user_id    = auth.uid()
       and left_at   is null
  );
$$;

comment on function public.is_session_participant(uuid) is
  'True if the currently-authenticated user has an active (left_at is null) '
  'session_participants row for the given session. Returns false when the '
  'caller is not authenticated. SECURITY DEFINER to avoid recursion through '
  'session_participants RLS.';


create or replace function public.is_tv_household_member(p_tv_device_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1
      from public.tv_devices         td
      join public.household_members  hm on hm.household_id = td.household_id
     where td.id      = p_tv_device_id
       and hm.user_id = auth.uid()
  );
$$;

comment on function public.is_tv_household_member(uuid) is
  'True if the currently-authenticated user is a household member of the '
  'household owning the given TV device. Resolves tv_device → household → '
  'household_members in a single SECURITY DEFINER query to bypass RLS on '
  'the intermediate tables.';


create or replace function public.is_session_tv_household_member(p_session_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1
      from public.sessions           s
      join public.tv_devices         td on td.id = s.tv_device_id
      join public.household_members  hm on hm.household_id = td.household_id
     where s.id       = p_session_id
       and hm.user_id = auth.uid()
  );
$$;

comment on function public.is_session_tv_household_member(uuid) is
  'True if the currently-authenticated user is a household member of the '
  'household owning the TV behind the given session. Resolves session → '
  'tv_device → household → household_members in a SECURITY DEFINER query. '
  'Sibling to is_session_tv_household_admin without the role=''admin'' filter.';


create or replace function public.is_session_tv_household_admin(p_session_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1
      from public.sessions           s
      join public.tv_devices         td on td.id = s.tv_device_id
      join public.household_members  hm on hm.household_id = td.household_id
     where s.id       = p_session_id
       and hm.user_id = auth.uid()
       and hm.role    = 'admin'
  );
$$;

comment on function public.is_session_tv_household_admin(uuid) is
  'True if the currently-authenticated user is a household admin of the '
  'household owning the TV behind the given session. Resolves session → '
  'tv_device → household → household_members in a SECURITY DEFINER query. '
  'Not referenced by RLS policies in this migration — retained for Part 1b '
  'RPCs (rpc_session_admin_reclaim and related) that need the admin check.';


-- ─── 3. Enable RLS ────────────────────────────────────────────────────────
alter table public.sessions             enable row level security;
alter table public.session_participants enable row level security;


-- ─── 4. Policies: sessions ────────────────────────────────────────────────
-- SELECT: session participants OR household members of the TV's household.
--
-- No INSERT/UPDATE/DELETE policies. With RLS enabled and no matching write
-- policy, those operations are denied for all non-owners. All mutations go
-- through SECURITY DEFINER RPCs in Part 1b.
drop policy if exists "sessions: participants and household members read"
  on public.sessions;

create policy "sessions: participants and household members read"
  on public.sessions
  for select
  using (
    public.is_session_participant(id)
    or public.is_tv_household_member(tv_device_id)
  );


-- ─── 5. Policies: session_participants ────────────────────────────────────
-- SELECT: co-participants (in the same session) OR household members of
-- the TV's household. Aligns with the sessions SELECT policy — if a
-- household member can see "a session exists on this TV," they can also
-- see who's in it. The asymmetric alternative (session exists visible,
-- participant list hidden) would be unintuitive without meaningful privacy
-- benefit; household members already have physical access to the TV.
--
-- No write policies. Mutations go through RPCs in Part 1b.
drop policy if exists "session_participants: co-participants and household members read"
  on public.session_participants;

create policy "session_participants: co-participants and household members read"
  on public.session_participants
  for select
  using (
    public.is_session_participant(session_id)
    or public.is_session_tv_household_member(session_id)
  );


-- ─── Verification ─────────────────────────────────────────────────────────
select 'migration 008 loaded' as status;
