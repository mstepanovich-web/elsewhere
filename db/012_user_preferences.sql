-- ============================================================================
-- Elsewhere — User preferences storage
-- Migration: 012
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Session 5 Part 2c.1. Per-user-per-TV preferences as a generic key-value
-- store. First consumer is 2c.2's proximity banner ("Don't show me again"
-- preference); designed to accommodate future preferences without schema
-- churn (notification opt-outs, UI variant choices, etc.).
--
-- Tables created:
--   • user_preferences  — (user_id, tv_device_id?, preference_key, jsonb value)
--
-- RPCs (both SECURITY DEFINER):
--   • rpc_get_user_preference(p_tv_device_id, p_preference_key) → jsonb
--   • rpc_set_user_preference(p_tv_device_id, p_preference_key, p_preference_value) → user_preferences
--
-- tv_device_id NULLable: NULL = user-global preference (not yet used in
-- 2c.x; reserved for future preferences that aren't TV-scoped). The
-- (user_id, tv_device_id, preference_key) tuple is uniquely indexed with
-- NULLS NOT DISTINCT (Postgres 15+) so a single user can have at most one
-- value per (TV, key) pair, including the user-global pair where TV is NULL.
--
-- No seed values. When rpc_get_user_preference returns NULL (no row),
-- application code applies its own default — for the proximity case, that
-- means "banner fires." See SESSION-5-PART-2-BREAKDOWN.md § 2c.1.
--
-- RLS: users read/write their own rows only. RPCs are SECURITY DEFINER
-- (the explicit auth.uid() filter is the security boundary); RLS policies
-- on the table provide defense-in-depth for any direct table access.
--
-- Idempotency: CREATE OR REPLACE FUNCTION + CREATE TABLE IF NOT EXISTS +
-- DROP POLICY IF EXISTS / CREATE POLICY. Safe to re-run.
-- ============================================================================


-- ─── 1. Tables ────────────────────────────────────────────────────────────
create table if not exists public.user_preferences (
  id               uuid        primary key default gen_random_uuid(),
  user_id          uuid        not null references auth.users(id) on delete cascade,
  tv_device_id     uuid        references public.tv_devices(id) on delete cascade,
  preference_key   text        not null,
  preference_value jsonb       not null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

comment on table public.user_preferences is
  'Per-user, per-TV (or user-global if tv_device_id is NULL) key-value '
  'preferences. JSONB values; preference_key is a stable string (e.g., '
  '''proximity_prompt_dismissed''). updated_at is RPC-maintained — direct '
  'UPDATEs that bypass rpc_set_user_preference will not bump it. Add a '
  'trigger if a non-RPC write path is introduced later.';


-- ─── 2. Indexes ───────────────────────────────────────────────────────────
-- NULLS NOT DISTINCT (Postgres 15+) makes a NULL tv_device_id collide with
-- another NULL tv_device_id for the same (user, key). Without this, every
-- user-global preference row would be considered unique, breaking upsert.
create unique index if not exists user_preferences_unique_key
  on public.user_preferences (user_id, tv_device_id, preference_key)
  nulls not distinct;

create index if not exists user_preferences_user_idx
  on public.user_preferences (user_id);


-- ─── 3. RLS ───────────────────────────────────────────────────────────────
alter table public.user_preferences enable row level security;

drop policy if exists user_preferences_read_own on public.user_preferences;
create policy user_preferences_read_own on public.user_preferences
  for select using (user_id = auth.uid());

drop policy if exists user_preferences_write_own on public.user_preferences;
create policy user_preferences_write_own on public.user_preferences
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());


-- ─── 4. rpc_get_user_preference ───────────────────────────────────────────
-- Returns the JSONB preference_value, or NULL if no row exists for this
-- (user, tv_device_id, preference_key) triple. Caller cannot distinguish
-- "no row" from "row with explicit JSONB null"; both surface as NULL.
-- Future preferences that need to distinguish should use a different RPC
-- shape (e.g., return the full row).
create or replace function public.rpc_get_user_preference(
  p_tv_device_id   uuid,
  p_preference_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_value   jsonb;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  select preference_value
    into v_value
    from public.user_preferences
   where user_id        = v_user_id
     and tv_device_id  is not distinct from p_tv_device_id
     and preference_key = p_preference_key;

  return v_value;
end;
$$;

grant execute on function public.rpc_get_user_preference(uuid, text) to authenticated;

comment on function public.rpc_get_user_preference(uuid, text) is
  'Reads the caller''s preference for (tv_device_id, preference_key). '
  'Returns the JSONB value or NULL when no row exists. Caller cannot '
  'distinguish ''no row'' from ''row with explicit null''. tv_device_id '
  'NULL = user-global preference.';


-- ─── 5. rpc_set_user_preference ───────────────────────────────────────────
-- Upsert into user_preferences. Matches existing rows via the unique index
-- (user_id, tv_device_id, preference_key) NULLS NOT DISTINCT. Updates
-- preference_value and bumps updated_at on conflict.
create or replace function public.rpc_set_user_preference(
  p_tv_device_id     uuid,
  p_preference_key   text,
  p_preference_value jsonb
)
returns public.user_preferences
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_row     public.user_preferences;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  insert into public.user_preferences
    (user_id, tv_device_id, preference_key, preference_value)
  values
    (v_user_id, p_tv_device_id, p_preference_key, p_preference_value)
  on conflict (user_id, tv_device_id, preference_key)
  do update set
    preference_value = excluded.preference_value,
    updated_at       = now()
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.rpc_set_user_preference(uuid, text, jsonb) to authenticated;

comment on function public.rpc_set_user_preference(uuid, text, jsonb) is
  'Upserts the caller''s preference for (tv_device_id, preference_key). '
  'Bumps updated_at on conflict. Returns the row. tv_device_id NULL = '
  'user-global preference.';


-- ─── Verification ─────────────────────────────────────────────────────────
select 'migration 012 loaded' as status;
