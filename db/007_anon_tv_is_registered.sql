-- ============================================================================
-- Elsewhere — Anon-callable RPC for TV registration state
-- Migration: 007
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Supports Session 4.10 Part C (tv2.html rewrite). At boot, tv2.html has no
-- Supabase session yet — the browser needs to decide between rendering the
-- "claim this TV" QR (unregistered state) and the "sign in to this TV" QR
-- (registered but no current session). That decision requires reading
-- tv_devices, but the existing "tv_devices: members read" RLS policy from
-- db/006 blocks unauthed reads (is_household_member() returns false without
-- a session).
--
-- This migration adds an anon-callable SECURITY DEFINER RPC that returns a
-- minimal projection of the row — just enough to drive the boot-state
-- decision. Safe to expose to anon because:
--   • device_key is a 128-bit UUID; guessing one requires brute-forcing
--     v4 UUID space (~2^122 values)
--   • Output is bounded to { registered, household_id, household_name,
--     tv_display_name } — no member list, no admin info, no tokens
--   • Worst case an attacker holding a valid device_key learns the
--     household display name. That's strictly less information than they
--     could read by physically looking at the TV the QR is on.
--
-- Read-only; no side effects. Idempotent. Safe to re-run.
-- ============================================================================


-- ─── 1. rpc_tv_is_registered ─────────────────────────────────────────────
create or replace function public.rpc_tv_is_registered(p_device_key text)
returns jsonb
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_tv        public.tv_devices;
  v_household public.households;
begin
  if p_device_key is null or length(p_device_key) = 0 then
    return jsonb_build_object('registered', false);
  end if;

  select * into v_tv from public.tv_devices where device_key = p_device_key;

  if v_tv.id is null then
    return jsonb_build_object('registered', false);
  end if;

  select * into v_household from public.households where id = v_tv.household_id;

  return jsonb_build_object(
    'registered',      true,
    'household_id',    v_tv.household_id,
    'household_name',  v_household.name,
    'tv_display_name', v_tv.display_name
  );
end;
$$;

comment on function public.rpc_tv_is_registered(text) is
  'Anon-callable introspection for TV browsers. Returns {registered, '
  'household_id, household_name, tv_display_name} when a device_key is '
  'claimed, or {registered: false} otherwise. Used by tv2.html at boot '
  'to decide between claim and sign-in QR states without requiring an '
  'authenticated session.';


-- ─── 2. Grants ────────────────────────────────────────────────────────────
-- Anon grant is intentional — tv2.html has no session at boot. The function
-- body filters strictly by the caller-supplied device_key (an opaque secret
-- known only to whoever holds the TV), so leaking household_name on a
-- correct guess is the floor of exposure.
grant execute on function public.rpc_tv_is_registered(text) to anon, authenticated;


-- ─── Verification ────────────────────────────────────────────────────────
select 'migration 007 loaded' as status;
