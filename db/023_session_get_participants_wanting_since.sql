-- ============================================================================
-- Elsewhere — rpc_session_get_participants + wanting_since column
-- Migration: 023
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Implements part of work item W4 from docs/ADMISSION-MODEL-V2.md § 10.
-- Adds wanting_since to the function's RETURNS TABLE column list and to
-- the underlying SELECT so client code can surface the column on
-- currentParticipants rows.
--
-- WHY THIS IS A DROP + CREATE instead of CREATE OR REPLACE:
--   Postgres does not allow changing a function's return type (including
--   RETURNS TABLE column list) via CREATE OR REPLACE FUNCTION. Adding a
--   column to RETURNS TABLE is a return-type change and must be done via
--   DROP FUNCTION + CREATE FUNCTION. Wrapped in BEGIN/COMMIT so concurrent
--   callers see an atomic swap; no observable "function not found" window
--   from outside the transaction.
--
-- WHY THIS IS NEEDED:
--   db/020 added wanting_since to the session_participants table but the
--   RPC's RETURNS TABLE explicitly lists columns, so adding the column
--   to the table did not surface it to clients. Client code that reads
--   currentParticipants[i].wanting_since would get undefined without this.
--
-- BEHAVIOR PRESERVED — everything else stays identical to db/013's
-- definition:
--
--   • Auth gate via is_session_participant OR is_session_tv_household_member.
--   • Sort order: active(0) → queued(1) → audience(2), then
--     queue_position NULLS LAST, then joined_at.
--   • SECURITY DEFINER + search_path = public.
--   • Grant to authenticated.
--
-- NOTE: The server-side ORDER BY does NOT use wanting_since. Karaoke
-- continues to use queue_position ordering as before. Games-side client
-- code does its own client-side sort by wanting_since for the queued
-- bucket (per W4 renderRoster updates in 3C).
--
-- Idempotency: DROP FUNCTION IF EXISTS handles re-runs. Safe to re-run.
-- ============================================================================

begin;

-- Drop the old signature. Required because RETURNS TABLE column list is
-- part of the function's return type and CREATE OR REPLACE cannot change it.
drop function if exists public.rpc_session_get_participants(uuid);

-- Recreate with wanting_since added to RETURNS TABLE + SELECT.
create function public.rpc_session_get_participants(
  p_session_id uuid
)
returns table (
  user_id            uuid,
  control_role       text,
  participation_role text,
  queue_position     int,
  wanting_since      timestamptz,
  pre_selections     jsonb,
  joined_at          timestamptz,
  display_name       text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- Same auth gate as rpc_karaoke_song_ended — broad enough to include
  -- stage.html's TV-claimer auth context.
  if not (
    public.is_session_participant(p_session_id)
    or public.is_session_tv_household_member(p_session_id)
  ) then
    raise exception 'not authorized for session %', p_session_id
      using errcode = '42501';
  end if;

  -- Order: active first (0), then queued by queue_position (1), then
  -- audience by joined_at (2). NULLS LAST on queue_position handles
  -- malformed queue rows defensively. wanting_since intentionally NOT in
  -- ORDER BY — karaoke continues to use queue_position for queue ordering;
  -- games-side client code sorts the queued bucket by wanting_since
  -- separately in renderRoster.
  return query
    select sp.user_id,
           sp.control_role,
           sp.participation_role,
           sp.queue_position,
           sp.wanting_since,
           sp.pre_selections,
           sp.joined_at,
           p.full_name as display_name
      from public.session_participants sp
      left join public.profiles p on p.id = sp.user_id
     where sp.session_id = p_session_id
       and sp.left_at   is null
     order by
       case sp.participation_role
         when 'active'   then 0
         when 'queued'   then 1
         else                 2
       end,
       sp.queue_position nulls last,
       sp.joined_at;
end;
$$;

grant execute on function public.rpc_session_get_participants(uuid) to authenticated;

comment on function public.rpc_session_get_participants(uuid) is
  'Returns active session participants with display_name joined from profiles. '
  'SECURITY DEFINER bypasses owner-only profiles RLS so callers can render '
  'queue UI for users whose profile rows they do not own. Ordered for queue '
  'display: active, then queued (by queue_position), then audience (by joined_at). '
  'wanting_since column surfaced for client-side queue ordering in games '
  '(W4 — see docs/ADMISSION-MODEL-V2.md § 3.4); karaoke continues to use '
  'queue_position ordering server-side.';

commit;

-- ─── Verification ─────────────────────────────────────────────────────────
select 'migration 023 loaded' as status;

-- ============================================================================
-- POST-MIGRATION VERIFICATION
--
-- After applying, run these checks against prod via Supabase SQL editor:
--
-- -- Function exists with the new signature.
-- SELECT proname, prorettype::regtype FROM pg_proc
--  WHERE proname = 'rpc_session_get_participants';
-- --   Expect: 1 row.
--
-- -- New column visible in the function's RETURNS TABLE list.
-- SELECT pg_get_functiondef(oid)
--   FROM pg_proc
--  WHERE proname = 'rpc_session_get_participants';
-- --   Expect: RETURNS TABLE includes `wanting_since timestamptz` between
-- --           queue_position and pre_selections; SELECT clause includes
-- --           sp.wanting_since.
--
-- -- Smoke test: call against a real session, confirm wanting_since column
-- -- comes back in the result set.
-- SELECT user_id, participation_role, queue_position, wanting_since, joined_at
--   FROM rpc_session_get_participants('<session_id>'::uuid);
-- --   Expect: result includes wanting_since (NULL for non-queued rows,
-- --           timestamp for queued rows that have been flipped via the
-- --           updated rpc_session_update_participant from db/022).
-- ============================================================================
