-- ============================================================================
-- Elsewhere — User Management Schema (Phase 1)
-- Migration: 001
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Contents:
--   • profiles        — extends auth.users, one row per signed-in user
--   • contacts        — people the manager may invite
--   • groups          — named tags for organizing contacts
--   • contact_groups  — many-to-many between contacts and groups
--   • invites         — one row per invite issued
--   • helper functions: set_updated_at, handle_new_user
--
-- Assumes Supabase Auth (magic links) is already configured. Run the whole
-- file in order — it is idempotent where reasonable (IF NOT EXISTS / CREATE
-- OR REPLACE) but is designed to be run once on a fresh project.
-- ============================================================================


-- ─── Helper: shared updated_at trigger function ─────────────────────────────
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;


-- ════════════════════════════════════════════════════════════════════════════
-- 1. profiles
-- ════════════════════════════════════════════════════════════════════════════
create table if not exists public.profiles (
  id          uuid        primary key references auth.users(id) on delete cascade,
  full_name   text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
comment on table public.profiles is
  'Application-side profile for each authenticated user. One row per auth.users row. '
  'Populated automatically by the on_auth_user_created trigger when a new user signs up.';

alter table public.profiles enable row level security;

create policy "profiles: owner can select"
  on public.profiles
  for select
  using (id = auth.uid());

create policy "profiles: owner can update"
  on public.profiles
  for update
  using (id = auth.uid())
  with check (id = auth.uid());

-- No public INSERT policy — rows are created by handle_new_user() below,
-- which runs as SECURITY DEFINER and bypasses RLS.

create trigger set_updated_at_on_profiles
  before update on public.profiles
  for each row execute function public.set_updated_at();


-- ─── Trigger: auto-create a profile row when a new user signs up ────────────
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, new.raw_user_meta_data->>'full_name')
  on conflict (id) do nothing;
  return new;
end;
$$;
comment on function public.handle_new_user is
  'Creates a public.profiles row for each new auth.users row. Pulls full_name '
  'from the optional raw_user_meta_data.full_name field (null if not provided).';

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ════════════════════════════════════════════════════════════════════════════
-- 2. contacts
-- ════════════════════════════════════════════════════════════════════════════
create table if not exists public.contacts (
  id          uuid        primary key default gen_random_uuid(),
  account_id  uuid        not null references public.profiles(id) on delete cascade,
  full_name   text        not null,
  nickname    text,
  email       text,
  phone       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint contacts_email_or_phone_required
    check (email is not null or phone is not null)
);
comment on table public.contacts is
  'People a manager may invite to a session. Owned by a single profile via '
  'account_id. Requires at least one of email or phone so an invite can actually '
  'be delivered.';

create index if not exists contacts_account_id_idx
  on public.contacts(account_id);

alter table public.contacts enable row level security;

create policy "contacts: owner can select"
  on public.contacts
  for select
  using (account_id = auth.uid());

create policy "contacts: owner can insert"
  on public.contacts
  for insert
  with check (account_id = auth.uid());

create policy "contacts: owner can update"
  on public.contacts
  for update
  using (account_id = auth.uid())
  with check (account_id = auth.uid());

create policy "contacts: owner can delete"
  on public.contacts
  for delete
  using (account_id = auth.uid());

create trigger set_updated_at_on_contacts
  before update on public.contacts
  for each row execute function public.set_updated_at();


-- ════════════════════════════════════════════════════════════════════════════
-- 3. groups
-- ════════════════════════════════════════════════════════════════════════════
create table if not exists public.groups (
  id          uuid        primary key default gen_random_uuid(),
  account_id  uuid        not null references public.profiles(id) on delete cascade,
  name        text        not null,
  color       text        not null default '#888888',
  created_at  timestamptz not null default now(),
  constraint groups_unique_name_per_account unique (account_id, name)
);
comment on table public.groups is
  'Named tags used to organize contacts (e.g. "Family", "Book Club"). Names must '
  'be unique within a single account but can repeat across accounts.';

alter table public.groups enable row level security;

create policy "groups: owner can select"
  on public.groups
  for select
  using (account_id = auth.uid());

create policy "groups: owner can insert"
  on public.groups
  for insert
  with check (account_id = auth.uid());

create policy "groups: owner can update"
  on public.groups
  for update
  using (account_id = auth.uid())
  with check (account_id = auth.uid());

create policy "groups: owner can delete"
  on public.groups
  for delete
  using (account_id = auth.uid());


-- ════════════════════════════════════════════════════════════════════════════
-- 4. contact_groups (join table, many-to-many)
-- ════════════════════════════════════════════════════════════════════════════
create table if not exists public.contact_groups (
  contact_id  uuid not null references public.contacts(id) on delete cascade,
  group_id    uuid not null references public.groups(id)   on delete cascade,
  primary key (contact_id, group_id)
);
comment on table public.contact_groups is
  'Many-to-many: each row associates one contact with one group. Both sides must '
  'belong to the same account — enforced at the RLS layer so cross-account '
  'associations cannot be written.';

alter table public.contact_groups enable row level security;

-- Both the contact AND the group must belong to the authenticated user.
-- Checked on SELECT / INSERT / DELETE. (No UPDATE: the PK is the whole row.)

create policy "contact_groups: both sides owned — select"
  on public.contact_groups
  for select
  using (
    exists (
      select 1 from public.contacts c
      where c.id = contact_id and c.account_id = auth.uid()
    )
    and exists (
      select 1 from public.groups g
      where g.id = group_id and g.account_id = auth.uid()
    )
  );

create policy "contact_groups: both sides owned — insert"
  on public.contact_groups
  for insert
  with check (
    exists (
      select 1 from public.contacts c
      where c.id = contact_id and c.account_id = auth.uid()
    )
    and exists (
      select 1 from public.groups g
      where g.id = group_id and g.account_id = auth.uid()
    )
  );

create policy "contact_groups: both sides owned — delete"
  on public.contact_groups
  for delete
  using (
    exists (
      select 1 from public.contacts c
      where c.id = contact_id and c.account_id = auth.uid()
    )
    and exists (
      select 1 from public.groups g
      where g.id = group_id and g.account_id = auth.uid()
    )
  );


-- ════════════════════════════════════════════════════════════════════════════
-- 5. invites
-- ════════════════════════════════════════════════════════════════════════════
create table if not exists public.invites (
  id            uuid        primary key default gen_random_uuid(),
  account_id    uuid        not null references public.profiles(id) on delete cascade,
  contact_id    uuid        references public.contacts(id) on delete cascade,
  session_type  text        not null,
  room_code     text        not null,
  token         text        not null unique,
  sent_via      text,
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null default (now() + interval '7 days'),
  used_at       timestamptz
);
comment on table public.invites is
  'One row per invite issued. contact_id is nullable for ad-hoc "guest" invites '
  'that are not tied to a saved contact. session_type is free-form text today '
  '(karaoke / games / future types). Token resolution for unauthenticated '
  'invitees will go through a Supabase Edge Function — no public-read RLS policy '
  'here on purpose.';

-- Note: the UNIQUE constraint on token already creates a btree index, so
-- lookups by token are fast. No separate CREATE INDEX needed on token.
create index if not exists invites_account_id_idx
  on public.invites(account_id);

alter table public.invites enable row level security;

create policy "invites: owner can select"
  on public.invites
  for select
  using (account_id = auth.uid());

create policy "invites: owner can insert"
  on public.invites
  for insert
  with check (account_id = auth.uid());

create policy "invites: owner can update"
  on public.invites
  for update
  using (account_id = auth.uid())
  with check (account_id = auth.uid());

create policy "invites: owner can delete"
  on public.invites
  for delete
  using (account_id = auth.uid());


-- ─── Verification ───────────────────────────────────────────────────────────
select 'schema loaded' as status;
