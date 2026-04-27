-- db/014_push_subscriptions.sql
-- Push notification token storage for Session 5 Part 2e.0.
--
-- Table: push_subscriptions
--   One row per (device_token, apns_environment) pair. Rows are durable across
--   sessions and across role changes; they represent "this device wants pushes
--   for this user." Tokens are per-device, not per-session.
--
-- Identity:
--   - device_token alone is NOT the unique key. A single iPhone can register
--     against both sandbox (development build) and production (App Store /
--     TestFlight build) APNs hosts and receive different tokens for each. The
--     unique constraint is the (device_token, apns_environment) tuple to allow
--     both rows to coexist during eventual TestFlight rollout.
--
-- Lifecycle:
--   - Insert / update via rpc_register_push_token (UPSERT semantics).
--   - Delete via rpc_unregister_push_token (user revokes permission, signs out).
--   - Cascade delete on auth.users removal.
--
-- Send-side:
--   - The send-push-notification Edge Function uses the service_role key and
--     bypasses RLS to read tokens for the targeted user(s).
--
-- Spec source: docs/SESSION-5-PART-2E-AUDIT.md (locked decisions appendix).

create table public.push_subscriptions (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references auth.users(id) on delete cascade,
  device_token      text not null,
  platform          text not null check (platform in ('ios', 'android')),
  apns_environment  text not null check (apns_environment in ('sandbox', 'production')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (device_token, apns_environment)
);

create index push_subscriptions_user_id_idx on public.push_subscriptions(user_id);

alter table public.push_subscriptions enable row level security;

-- Users can read their own rows. (Edge Function uses service_role; bypasses RLS.)
create policy "users read own push subscriptions"
  on public.push_subscriptions
  for select
  using (auth.uid() = user_id);

-- Users can insert rows for themselves only.
create policy "users insert own push subscriptions"
  on public.push_subscriptions
  for insert
  with check (auth.uid() = user_id);

-- Users can update their own rows. (Used when same device, different user.)
create policy "users update own push subscriptions"
  on public.push_subscriptions
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Users can delete their own rows.
create policy "users delete own push subscriptions"
  on public.push_subscriptions
  for delete
  using (auth.uid() = user_id);

-- ── RPCs ─────────────────────────────────────────────────────────────────────

-- Register or refresh a push token.
--
-- Behavior:
--   - If (device_token, apns_environment) already exists: UPDATE the row to
--     point at the current authenticated user (in case the device changed
--     hands) and bump updated_at.
--   - Otherwise: INSERT a new row owned by the current authenticated user.
--   - Always uses auth.uid(); never accepts a user_id parameter (defensive
--     against impersonation).
--
-- Security:
--   - SECURITY INVOKER: runs as the calling user, respects RLS.
--   - 42501 if not authenticated.
--   - 22023 if platform or apns_environment fails check constraint.
create or replace function public.rpc_register_push_token(
  p_device_token text,
  p_platform text,
  p_apns_environment text
)
returns uuid
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid;
  v_id uuid;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  insert into public.push_subscriptions (user_id, device_token, platform, apns_environment)
  values (v_user_id, p_device_token, p_platform, p_apns_environment)
  on conflict (device_token, apns_environment) do update
    set user_id    = excluded.user_id,
        platform   = excluded.platform,
        updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.rpc_register_push_token(text, text, text) to authenticated;

-- Unregister a push token.
--
-- Deletes the row matching device_token + apns_environment, but only if it
-- belongs to the calling user. Silent no-op if no matching row exists.
--
-- Security:
--   - SECURITY INVOKER: runs as the calling user, respects RLS.
--   - 42501 if not authenticated.
create or replace function public.rpc_unregister_push_token(
  p_device_token text,
  p_apns_environment text
)
returns void
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  delete from public.push_subscriptions
  where device_token = p_device_token
    and apns_environment = p_apns_environment
    and user_id = v_user_id;
end;
$$;

grant execute on function public.rpc_unregister_push_token(text, text) to authenticated;
