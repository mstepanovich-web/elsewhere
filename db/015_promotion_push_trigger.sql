-- ============================================================================
-- Elsewhere — Promotion push trigger
-- Migration: 015
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Session 5 Part 2e.2 §6b. When session_participants.participation_role
-- transitions queued → active, fire the send-push-notification Edge
-- Function for the user being promoted. pg_net.http_post is async (queued
-- by Postgres, sent off-loop) so the trigger does not block the writing
-- transaction.
--
-- The Edge Function is called with the project's service_role key in the
-- Authorization header. supabase/functions/send-push-notification/index.ts
-- (modified in this same shipping wave) accepts service-role-authed
-- requests as authoritative server-side calls and skips the JWT-user check
-- that 2e.0 added for direct user calls. It also synthesizes canonical
-- promotion title/body from `type: 'promotion'` so the trigger payload can
-- stay minimal (no notification copy in SQL).
--
-- Vault prerequisites (must be set before trigger fires; checked in-band
-- and warning-logged if missing):
--   select vault.create_secret('<edge fn url>', 'edge_fn_url');
--   select vault.create_secret('<service_role JWT>', 'service_role_key');
--
-- Scope of the WHEN clause:
--
--   (OLD.participation_role = 'queued' AND NEW.participation_role = 'active')
--
-- Tightened from "any → active" so that self-initiated audience → active
-- (the §3 Start Song path, where the user is already on the phone tapping
-- the CTA) does not push. Manager force-promote (2e.3 scope) currently
-- routes audience → active and would also be skipped; revisit when 2e.3
-- adds the manager queue-management UI.
-- ============================================================================

create extension if not exists pg_net;

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
  -- Read project URL and service role key from Vault.
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'edge_fn_url' limit 1;
  select decrypted_secret into v_service_role_key
    from vault.decrypted_secrets where name = 'service_role_key' limit 1;

  if v_url is null or v_service_role_key is null then
    raise warning 'fire_promotion_push: vault secrets missing, skipping';
    return NEW;
  end if;

  v_payload := jsonb_build_object(
    'user_id',    NEW.user_id,
    'type',       'promotion',
    'session_id', NEW.session_id
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

drop trigger if exists trg_fire_promotion_push on public.session_participants;

create trigger trg_fire_promotion_push
  after update of participation_role on public.session_participants
  for each row
  when (OLD.participation_role = 'queued'
        and NEW.participation_role = 'active')
  execute function public.fire_promotion_push();

comment on function public.fire_promotion_push is
  'Session 5 Part 2e.2 §6b: Fires send-push-notification Edge Function '
  'when a participant transitions queued → active. Reads URL + service '
  'role key from Supabase Vault.';


-- ─── Verification ─────────────────────────────────────────────────────────
select 'migration 015 loaded' as status;
