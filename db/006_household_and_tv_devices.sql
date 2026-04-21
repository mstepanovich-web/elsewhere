-- ============================================================================
-- Elsewhere — Household + TV device registration
-- Migration: 006
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Introduces the foundational household and TV device model for Session 4.10.
-- Replaces the temporary ?dev=1 email+password bridge on karaoke/stage.html
-- with a proper production auth flow driven by a persistent household-
-- membership relationship.
--
-- Tables created:
--   • households                   — one row per physical home / venue
--   • tv_devices                   — TV browsers registered to a household
--   • household_members            — user ↔ household with role (admin | user)
--   • pending_household_invites    — admin-staged pre-invitations
--
-- Helper functions (SECURITY DEFINER for RLS-safety — see note below;
-- defined AFTER the tables because `create function ... language sql`
-- validates the body at creation time):
--   • is_household_member(uuid) → bool
--   • is_household_admin(uuid)  → bool
--
-- RPC functions:
--   • rpc_claim_tv_device               (DEFINER, in use in 4.10)
--   • rpc_link_tv_to_existing_household (INVOKER, in use in 4.10)
--   • rpc_request_household_access      (DEFINER, in use in 4.10)
--   • rpc_tv_heartbeat                  (DEFINER, in use in 4.10)
--   • rpc_approve_household_member      (INVOKER, plumbing — wired for 4.11)
--   • rpc_designate_admin               (INVOKER, plumbing — wired for 4.11)
--
-- Session 4.10 scope (see docs/SESSION-4.10-PLAN.md). Phone-based pre-invites
-- (via pending_household_invites.phone) are deferred to Session 4.10.1 — the
-- column exists but is not read by any RPC in this migration. Scan-approval
-- flow (rpc_approve_household_member + associated UI) is deferred to 4.11
-- but the RPC is shipped here as plumbing.
--
-- On SECURITY DEFINER for the helpers: the members-read policy on
-- household_members calls is_household_member(household_id), whose internal
-- query also reads from household_members. With SECURITY INVOKER the inner
-- query re-enters the same policy, risking recursion. SECURITY DEFINER makes
-- the helper's internal query bypass RLS on household_members. The helper
-- still explicitly filters by user_id = auth.uid(), so it cannot leak other
-- users' membership. Standard Supabase pattern.
--
-- Idempotency: every CREATE is wrapped with IF NOT EXISTS where supported;
-- policies use DROP IF EXISTS + CREATE; functions use CREATE OR REPLACE.
-- Safe to re-run.
-- ============================================================================


-- ─── 0. Extensions ────────────────────────────────────────────────────────
create extension if not exists citext;


-- ─── 1. Tables (in FK-dependency order) ──────────────────────────────────
-- Must come before the helper functions: `create function ... language sql`
-- validates the function body at creation time, so the helpers would fail
-- to compile if they reference tables that don't yet exist.

-- households
create table if not exists public.households (
  id          uuid        primary key default gen_random_uuid(),
  name        text,
  created_at  timestamptz not null default now(),
  created_by  uuid        not null references auth.users(id)
);

comment on table public.households is
  'One row per physical home or venue. Created_by is the founding user; '
  'they receive the first household_members row (role=admin, joined_via=''founder'') '
  'via rpc_claim_tv_device.';

-- tv_devices
create table if not exists public.tv_devices (
  id             uuid        primary key default gen_random_uuid(),
  household_id   uuid        not null references public.households(id) on delete cascade,
  device_key     text        not null unique,
  display_name   text,
  registered_at  timestamptz not null default now(),
  registered_by  uuid        not null references auth.users(id),
  last_seen_at   timestamptz not null default now()
);

create index if not exists tv_devices_household_idx
  on public.tv_devices(household_id);

comment on table public.tv_devices is
  'TV browsers registered to a household. device_key is a v4 UUID generated '
  'by the TV browser and stored in localStorage — it is the stable identity '
  'of the physical TV browser across refreshes. One TV per row; a household '
  'may have many TVs.';

-- household_members
create table if not exists public.household_members (
  household_id  uuid        not null references public.households(id) on delete cascade,
  user_id       uuid        not null references auth.users(id) on delete cascade,
  role          text        not null check (role in ('admin', 'user')),
  joined_at     timestamptz not null default now(),
  joined_via    text        not null check (joined_via in ('founder', 'pre_invite', 'scan_approved')),
  primary key (household_id, user_id)
);

create index if not exists household_members_user_idx
  on public.household_members(user_id);

comment on table public.household_members is
  'User membership in a household with a role. Founder admission (joined_via='
  '''founder'') is created by rpc_claim_tv_device. Pre-invite admission '
  '(joined_via=''pre_invite'') happens via rpc_request_household_access when '
  'the caller''s email matches a pending_household_invites row. Scan-approved '
  'admission (joined_via=''scan_approved'') is plumbing for Session 4.11 — '
  'the RPC is built but no UI calls it in 4.10.';

-- pending_household_invites
create table if not exists public.pending_household_invites (
  id            uuid        primary key default gen_random_uuid(),
  household_id  uuid        not null references public.households(id) on delete cascade,
  email         citext,
  phone         text,
  invited_by    uuid        not null references auth.users(id),
  invited_at    timestamptz not null default now(),
  consumed_at   timestamptz,
  consumed_by   uuid        references auth.users(id),
  check (email is not null or phone is not null)
);

-- Unique partial indexes: one active pre-invite per (household, email) and
-- per (household, phone). Consumed invites don't block new invites for the
-- same address (useful if someone unjoins and is re-invited).
create unique index if not exists pending_invites_email_per_household
  on public.pending_household_invites (household_id, email)
  where email is not null and consumed_at is null;

create unique index if not exists pending_invites_phone_per_household
  on public.pending_household_invites (household_id, phone)
  where phone is not null and consumed_at is null;

comment on table public.pending_household_invites is
  'Admin-staged pre-invitations. When a user signs up with a matching email '
  '(or verified phone — deferred to 4.10.1) and scans the household TV, '
  'rpc_request_household_access auto-admits them and marks the invite consumed. '
  'Phone column is reserved but NOT read by any RPC in migration 006 — SMS '
  'OTP integration is a Session 4.10.1 follow-up.';


-- ─── 2. Helper functions (SECURITY DEFINER) ──────────────────────────────
-- Defined AFTER tables because `create function ... language sql` validates
-- the function body at creation time. Both helpers return false cleanly
-- when auth.uid() is null (signed-out caller). Short-circuit via AND
-- ensures the inner EXISTS isn't evaluated in that case.

create or replace function public.is_household_member(hh_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1
      from public.household_members
     where household_id = hh_id
       and user_id      = auth.uid()
  );
$$;

comment on function public.is_household_member(uuid) is
  'True if the currently-authenticated user is a member of the given household. '
  'Returns false (not raise) when the caller is not authenticated. '
  'SECURITY DEFINER to avoid recursion through household_members RLS.';

create or replace function public.is_household_admin(hh_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1
      from public.household_members
     where household_id = hh_id
       and user_id      = auth.uid()
       and role         = 'admin'
  );
$$;

comment on function public.is_household_admin(uuid) is
  'True if the currently-authenticated user is an admin of the given household. '
  'Returns false (not raise) when the caller is not authenticated. '
  'SECURITY DEFINER to avoid recursion through household_members RLS.';


-- ─── 3. Enable RLS on all four tables ────────────────────────────────────
alter table public.households               enable row level security;
alter table public.tv_devices               enable row level security;
alter table public.household_members        enable row level security;
alter table public.pending_household_invites enable row level security;


-- ─── 4. Policies: households ──────────────────────────────────────────────
drop policy if exists "households: members read"         on public.households;
drop policy if exists "households: authed users insert"  on public.households;
drop policy if exists "households: admins update"        on public.households;
drop policy if exists "households: admins delete"        on public.households;

create policy "households: members read"
  on public.households
  for select
  using (public.is_household_member(id));

create policy "households: authed users insert"
  on public.households
  for insert
  with check (created_by = auth.uid());

create policy "households: admins update"
  on public.households
  for update
  using (public.is_household_admin(id))
  with check (public.is_household_admin(id));

create policy "households: admins delete"
  on public.households
  for delete
  using (public.is_household_admin(id));


-- ─── 5. Policies: tv_devices ──────────────────────────────────────────────
drop policy if exists "tv_devices: members read"  on public.tv_devices;
drop policy if exists "tv_devices: admins write"  on public.tv_devices;

create policy "tv_devices: members read"
  on public.tv_devices
  for select
  using (public.is_household_member(household_id));

create policy "tv_devices: admins write"
  on public.tv_devices
  for all
  using (public.is_household_admin(household_id))
  with check (public.is_household_admin(household_id));


-- ─── 6. Policies: household_members ───────────────────────────────────────
-- Members see each other (so the future household-management UI can list
-- them). Admins have full write authority. Founder and pre-invite insertions
-- happen via SECURITY DEFINER RPCs that bypass RLS, so no self-insert
-- policy is needed.
drop policy if exists "household_members: members read"  on public.household_members;
drop policy if exists "household_members: admins write"  on public.household_members;

create policy "household_members: members read"
  on public.household_members
  for select
  using (public.is_household_member(household_id));

create policy "household_members: admins write"
  on public.household_members
  for all
  using (public.is_household_admin(household_id))
  with check (public.is_household_admin(household_id));


-- ─── 7. Policies: pending_household_invites ──────────────────────────────
-- Admins-only. No invitee-read policy (they don't see their own pending
-- invites in 4.10 — a "Pending Invitations" inbox UI is deferred, see
-- docs/DEFERRED.md). Invitee matching happens inside the SECURITY DEFINER
-- rpc_request_household_access, which bypasses this policy.
drop policy if exists "pending_household_invites: admins all"
  on public.pending_household_invites;

create policy "pending_household_invites: admins all"
  on public.pending_household_invites
  for all
  using (public.is_household_admin(household_id))
  with check (public.is_household_admin(household_id));


-- ─── 8. RPC: rpc_claim_tv_device ─────────────────────────────────────────
-- First-time TV registration. Creates a new household with the caller as
-- the founding admin, then registers the TV. SECURITY DEFINER because the
-- household_members insert requires admin privileges that don't yet exist
-- (the caller is about to become admin in this transaction).
create or replace function public.rpc_claim_tv_device(
  p_device_key      text,
  p_household_name  text default null,
  p_tv_display_name text default null
)
returns public.tv_devices
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id   uuid := auth.uid();
  v_household public.households;
  v_tv_device public.tv_devices;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if exists (select 1 from public.tv_devices where device_key = p_device_key) then
    raise exception 'device_key already claimed: %', p_device_key using errcode = '23505';
  end if;

  insert into public.households (name, created_by)
  values (p_household_name, v_user_id)
  returning * into v_household;

  insert into public.household_members (household_id, user_id, role, joined_via)
  values (v_household.id, v_user_id, 'admin', 'founder');

  insert into public.tv_devices (household_id, device_key, registered_by, display_name)
  values (v_household.id, p_device_key, v_user_id, p_tv_display_name)
  returning * into v_tv_device;

  return v_tv_device;
end;
$$;

grant execute on function public.rpc_claim_tv_device(text, text, text) to authenticated;


-- ─── 9. RPC: rpc_link_tv_to_existing_household ────────────────────────────
-- Admin adds another TV to their existing household. SECURITY INVOKER —
-- caller's admin-ness is enforced by is_household_admin(), and the
-- tv_devices insert passes the existing "admins write" RLS policy.
create or replace function public.rpc_link_tv_to_existing_household(
  p_device_key   text,
  p_household_id uuid
)
returns public.tv_devices
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_tv_device public.tv_devices;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if not public.is_household_admin(p_household_id) then
    raise exception 'not an admin of household %', p_household_id using errcode = '42501';
  end if;

  if exists (select 1 from public.tv_devices where device_key = p_device_key) then
    raise exception 'device_key already claimed: %', p_device_key using errcode = '23505';
  end if;

  insert into public.tv_devices (household_id, device_key, registered_by)
  values (p_household_id, p_device_key, auth.uid())
  returning * into v_tv_device;

  return v_tv_device;
end;
$$;

grant execute on function public.rpc_link_tv_to_existing_household(text, uuid) to authenticated;


-- ─── 10. RPC: rpc_request_household_access ───────────────────────────────
-- Scanning user requests access to the household that owns the scanned TV.
-- Returns a jsonb object with a status string:
--   'already_member'  — caller is already a household member; nothing changed
--   'auto_admitted'   — email matched a pending_invite; membership created
--   'guest'           — no match; caller may still launch apps as a guest
-- SECURITY DEFINER because it reads pending_household_invites (admin-only)
-- and inserts into household_members (admin-only) on behalf of the caller.
create or replace function public.rpc_request_household_access(p_device_key text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id    uuid := auth.uid();
  v_user_email citext;
  v_tv         public.tv_devices;
  v_household  public.households;
  v_invite_id  uuid;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  select * into v_tv from public.tv_devices where device_key = p_device_key;
  if v_tv.id is null then
    raise exception 'tv_device not found for device_key=%', p_device_key using errcode = '02000';
  end if;

  select * into v_household from public.households where id = v_tv.household_id;

  -- Already a member? Return immediately, no changes.
  if exists (
    select 1 from public.household_members
     where household_id = v_household.id and user_id = v_user_id
  ) then
    return jsonb_build_object(
      'status',         'already_member',
      'household_id',   v_household.id,
      'household_name', v_household.name
    );
  end if;

  -- Look for an email-based pending invite. Phone is reserved for 4.10.1
  -- and is not checked here.
  select email::citext into v_user_email from auth.users where id = v_user_id;

  if v_user_email is not null then
    select id into v_invite_id
      from public.pending_household_invites
     where household_id = v_household.id
       and email        = v_user_email
       and consumed_at is null
     limit 1;

    if v_invite_id is not null then
      insert into public.household_members (household_id, user_id, role, joined_via)
      values (v_household.id, v_user_id, 'user', 'pre_invite');

      update public.pending_household_invites
         set consumed_at = now(),
             consumed_by = v_user_id
       where id = v_invite_id;

      return jsonb_build_object(
        'status',         'auto_admitted',
        'household_id',   v_household.id,
        'household_name', v_household.name
      );
    end if;
  end if;

  -- No membership, no matching invite — guest access.
  return jsonb_build_object(
    'status',         'guest',
    'household_id',   v_household.id,
    'household_name', v_household.name
  );
end;
$$;

grant execute on function public.rpc_request_household_access(text) to authenticated;


-- ─── 11. RPC: rpc_tv_heartbeat ────────────────────────────────────────────
-- Called by tv2.html on load (and periodically thereafter) to bump
-- tv_devices.last_seen_at. SECURITY DEFINER bypasses the "admins write"
-- RLS policy on tv_devices — every member of the household (not just
-- admins) should be able to mark "this TV is alive" when they're in front
-- of it. Explicit is_household_member check inside the function enforces
-- that the caller actually has household access; guests (no
-- household_members row) are rejected.
create or replace function public.rpc_tv_heartbeat(p_device_key text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tv public.tv_devices;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  select * into v_tv from public.tv_devices where device_key = p_device_key;
  if v_tv.id is null then
    raise exception 'tv_device not found for device_key=%', p_device_key using errcode = '02000';
  end if;

  if not public.is_household_member(v_tv.household_id) then
    raise exception 'not a member of this TV''s household' using errcode = '42501';
  end if;

  update public.tv_devices
     set last_seen_at = now()
   where device_key = p_device_key;
end;
$$;

grant execute on function public.rpc_tv_heartbeat(text) to authenticated;


-- ─── 12. RPC: rpc_approve_household_member (plumbing) ────────────────────
-- No UI calls this in 4.10 — wired for Session 4.11 scan-approval flow.
-- SECURITY INVOKER — caller's admin-ness is enforced both by
-- is_household_admin() and by the underlying "admins write" RLS policy on
-- household_members.
create or replace function public.rpc_approve_household_member(
  p_user_id      uuid,
  p_household_id uuid
)
returns public.household_members
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_row public.household_members;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if not public.is_household_admin(p_household_id) then
    raise exception 'not an admin of household %', p_household_id using errcode = '42501';
  end if;

  if exists (
    select 1 from public.household_members
     where household_id = p_household_id and user_id = p_user_id
  ) then
    raise exception 'user % is already a member of household %', p_user_id, p_household_id
      using errcode = '23505';
  end if;

  insert into public.household_members (household_id, user_id, role, joined_via)
  values (p_household_id, p_user_id, 'user', 'scan_approved')
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.rpc_approve_household_member(uuid, uuid) to authenticated;


-- ─── 13. RPC: rpc_designate_admin (plumbing) ─────────────────────────────
-- No UI calls this in 4.10 — wired for Session 4.11 admin management UI.
--
-- TODO(session-4.11): When demote / remove RPCs land (rpc_remove_member,
-- rpc_demote_admin, or whatever they end up being called), they MUST
-- enforce the "last admin cannot leave" constraint: a household's final
-- admin cannot be demoted to 'user' or removed from household_members.
-- Otherwise the household becomes unmanageable (no one can add TVs, invite
-- new members, or approve guests). Check before mutating:
--   count(*) from household_members where household_id = X and role='admin'
--   — if <= 1 and the target is that one admin, raise.
-- This constraint must also apply to household_members DELETE via RLS or
-- RPC, whichever form removal takes.
create or replace function public.rpc_designate_admin(
  p_user_id      uuid,
  p_household_id uuid
)
returns public.household_members
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_row public.household_members;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if not public.is_household_admin(p_household_id) then
    raise exception 'not an admin of household %', p_household_id using errcode = '42501';
  end if;

  update public.household_members
     set role = 'admin'
   where household_id = p_household_id and user_id = p_user_id
  returning * into v_row;

  if v_row.household_id is null then
    raise exception 'user % is not a member of household %', p_user_id, p_household_id
      using errcode = '02000';
  end if;

  return v_row;
end;
$$;

grant execute on function public.rpc_designate_admin(uuid, uuid) to authenticated;


-- ─── Verification ─────────────────────────────────────────────────────────
select 'migration 006 loaded' as status;
