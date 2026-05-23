-- ============================================================================
-- Elsewhere — Promotion push trigger recreation (room-keyed)
-- Migration: 029
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Recreates the fire_promotion_push() function and trg_fire_promotion_push
-- trigger, both dropped by db/025 step 4 because the original db/015
-- implementation referenced NEW.session_id — a column db/025 removed
-- from session_participants when it re-anchored the table to room_id.
--
-- The recreated function reads NEW.room_id instead. The trigger's WHEN
-- clause (OLD.participation_role = 'queued' AND NEW.participation_role
-- = 'active') is unchanged from db/015 — only the payload field that
-- identifies the gathering changes.
--
-- ─── Payload change vs. db/015 ───────────────────────────────────────────
-- db/015 payload (pre-rooms-anchor):
--   { user_id, type: 'promotion', session_id: NEW.session_id }
-- db/029 payload (post-rooms-anchor):
--   { user_id, type: 'promotion', room_id:    NEW.room_id }
--
-- session_id is dropped from the payload entirely. The 2026-05-23 iOS
-- audit confirmed the Capacitor app's two PushNotifications listeners
-- (karaoke/singer.html lines ~2094, ~2098) read NOTHING from
-- notif.data — neither session_id, nor room_id, nor any other field.
-- So payload field-name choice is moot for the app today; room_id is
-- chosen for future-proofing per ROOM-SESSION-MODEL.md (rooms outlive
-- sessions; eventual tap-routing work will navigate to a ROOM, not a
-- session). See DEFERRED.md "turn-notification iOS feature depends on
-- fire_promotion_push trigger recreation" for the full audit findings.
--
-- ─── Downstream coupling ─────────────────────────────────────────────────
-- The send-push-notification Edge Function
-- (supabase/functions/send-push-notification/index.ts line 244)
-- hard-codes session_id when synthesizing the APNs data object. That
-- line must be updated to read body.room_id in lockstep with this
-- migration; otherwise the deployed Edge Function produces
-- session_id: undefined in the APNs payload (harmless today since the
-- iOS app reads nothing from data, but stale-named for future
-- tap-routing work). Edge Function update + redeploy ships with this
-- migration in the same operator session:
--   supabase functions deploy send-push-notification --no-verify-jwt
--
-- The --no-verify-jwt flag is MANDATORY per CLAUDE.md doctrine — the
-- trigger sends a non-JWT shared-secret in the Authorization header,
-- and Supabase's edge gateway rejects it before reaching function
-- code if JWT verification is on.
--
-- ─── Vault prerequisites ─────────────────────────────────────────────────
-- The Vault secrets db/015 provisioned are still in prod (the secret
-- entries survived db/025's function/trigger DROPs — Vault is
-- separate from pg_catalog). They are reused as-is:
--   - 'edge_fn_url'      — the send-push-notification function URL
--   - 'service_role_key' — see naming note below
-- If either is missing for some reason (e.g., a future project reset),
-- the function raises a WARNING and returns NEW without firing — the
-- writing transaction is never blocked.
--
-- ─── IMPORTANT: 'service_role_key' Vault name is INTENTIONALLY KEPT ──────
-- The Vault entry named 'service_role_key' does NOT contain
-- Supabase's auto-provisioned SUPABASE_SERVICE_ROLE_KEY. It contains
-- a custom PROMOTION_TRIGGER_SECRET — a shared secret that the
-- send-push-notification Edge Function validates against (see
-- supabase/functions/send-push-notification/index.ts lines 205–214
-- for the §6b shared-secret auth branch).
--
-- The Vault name 'service_role_key' is retained from db/015 — it is a
-- legacy name from when the value WAS the auto-provisioned service
-- role key. Supabase later migrated to sb_secret_... keys; the
-- Edge Function switched to a custom secret, and the Vault entry's
-- VALUE changed, but the Vault entry's NAME was kept to avoid
-- breaking the deployed trigger. Renaming the Vault entry (or the
-- name this function reads) would break auth — both the deployed
-- Edge Function and the provisioned Vault entry depend on this
-- exact string.
--
-- Do not "fix" this misleading name. The trade-off was deliberate.
--
-- ─── Idempotency / transaction wrapping ──────────────────────────────────
-- DROP TRIGGER IF EXISTS + DROP FUNCTION IF EXISTS before the CREATEs
-- (per the c657c9f DROP-FUNCTION-IF-EXISTS discipline). begin;/commit;
-- envelope; if any statement fails, the whole migration rolls back.
-- Safe to re-run.
--
-- ─── Verification footer: see after COMMIT ──────────────────────────────
-- ============================================================================


begin;


create extension if not exists pg_net;


-- DROP first for idempotency. Both objects were already dropped by
-- db/025 step 4, so on the first apply these DROPs are no-ops; they
-- guard against re-runs and any future state where the objects might
-- partially exist.
drop trigger if exists trg_fire_promotion_push on public.session_participants;
drop function if exists public.fire_promotion_push();


create or replace function public.fire_promotion_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url              text;
  v_service_role_key text;
  v_payload          jsonb;
begin
  -- Read project URL and the trigger's shared-secret token from Vault.
  --
  -- The Vault name 'service_role_key' is KEPT FROM db/015 INTENTIONALLY.
  -- The entry no longer holds Supabase's auto-provisioned service role
  -- key — it now holds a custom PROMOTION_TRIGGER_SECRET that the
  -- send-push-notification Edge Function validates against (see
  -- supabase/functions/send-push-notification/index.ts §6b auth
  -- branch). The Vault NAME was preserved to avoid breaking the
  -- deployed Edge Function and the provisioned Vault entry, both of
  -- which depend on this exact string. Do not rename to something
  -- more accurate — it would break auth. See migration header for
  -- the full history.
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'edge_fn_url' limit 1;
  select decrypted_secret into v_service_role_key
    from vault.decrypted_secrets where name = 'service_role_key' limit 1;

  if v_url is null or v_service_role_key is null then
    raise warning 'fire_promotion_push: vault secrets missing, skipping';
    return NEW;
  end if;

  -- Payload change vs. db/015: session_id → room_id. The 2026-05-23 iOS
  -- audit confirmed the Capacitor app's notification listeners read
  -- nothing from notif.data, so this field-name change is functionally
  -- moot today; room_id is chosen for future-proofing per
  -- ROOM-SESSION-MODEL.md (rooms outlive sessions; eventual
  -- tap-routing work will navigate to a ROOM, not a session).
  v_payload := jsonb_build_object(
    'user_id', NEW.user_id,
    'type',    'promotion',
    'room_id', NEW.room_id
  );

  -- pg_net.http_post returns immediately; the request is queued.
  perform net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_service_role_key,
      'Content-Type',  'application/json'
    ),
    body    := v_payload
  );

  return NEW;
end;
$$;


create trigger trg_fire_promotion_push
  after update of participation_role on public.session_participants
  for each row
  when (OLD.participation_role = 'queued'
        and NEW.participation_role = 'active')
  execute function public.fire_promotion_push();


comment on function public.fire_promotion_push is
  'Recreated 2026 (db/029) post-db/025 room-anchoring. Fires '
  'send-push-notification Edge Function when a session_participants '
  'row transitions queued → active. Payload: { user_id, type: '
  '''promotion'', room_id }. Reads URL + shared-secret token from '
  'Supabase Vault (names: edge_fn_url, service_role_key — see '
  'migration header for why the second name is intentionally '
  'misleading).';


commit;


-- ─── Verification ─────────────────────────────────────────────────────────
select 'migration 029 loaded' as status;

-- ============================================================================
-- POST-MIGRATION VERIFICATION
-- Run against prod via Supabase SQL Editor after applying.
--
-- 1. The function exists and is owned by postgres / has SECURITY DEFINER.
--    SELECT proname,
--           pg_get_function_result(oid)            AS returns,
--           prosecdef                              AS security_definer,
--           pg_get_function_arguments(oid)         AS args
--      FROM pg_proc
--     WHERE proname = 'fire_promotion_push'
--       AND pronamespace = 'public'::regnamespace;
--    Expect: 1 row. returns = 'trigger'. security_definer = true. args = ''.
--
-- 2. The function body references NEW.room_id (not NEW.session_id) and
--    builds the room-keyed payload.
--    SELECT pg_get_functiondef(oid)
--      FROM pg_proc
--     WHERE proname = 'fire_promotion_push'
--       AND pronamespace = 'public'::regnamespace;
--    Expect: body contains 'NEW.room_id' and 'room_id', NEW.room_id'
--    (jsonb_build_object call). Should NOT contain 'NEW.session_id'
--    or 'session_id'.
--
-- 3. The trigger exists on session_participants and is enabled.
--    SELECT tgname,
--           tgenabled,
--           tgtype,
--           pg_get_triggerdef(oid) AS def
--      FROM pg_trigger
--     WHERE tgname = 'trg_fire_promotion_push';
--    Expect: 1 row. tgenabled = 'O' (enabled, "Origin" — fires for
--    user-initiated UPDATEs, the normal case). def contains
--    'AFTER UPDATE OF participation_role' and the queued→active WHEN
--    clause.
--
-- 4. Confirm the trigger is on the correct table.
--    SELECT t.tgname,
--           c.relname AS table_name
--      FROM pg_trigger t
--      JOIN pg_class c ON c.oid = t.tgrelid
--     WHERE t.tgname = 'trg_fire_promotion_push';
--    Expect: table_name = 'session_participants'.
--
-- 5. Vault secrets are present (required for the function to actually
--    fire; missing secrets degrade gracefully to a WARNING per the
--    function body's guard clause).
--    SELECT name FROM vault.decrypted_secrets
--     WHERE name IN ('edge_fn_url', 'service_role_key')
--     ORDER BY name;
--    Expect: 2 rows — both names present. (Values are not printed by
--    this query.)
--
-- 6. End-to-end smoke test (only after the Edge Function update at
--    line 244 is also deployed — see migration header).
--    From an authenticated user's session, trigger a queued → active
--    transition on session_participants (e.g., manager promotes the
--    queued user via the karaoke UI, or a manual UPDATE via SQL
--    Editor with sufficient privileges). On a real device with a
--    registered push_subscriptions row for that user, the iOS device
--    should show the "You're up! / Tap to take the stage" alert.
-- ============================================================================
