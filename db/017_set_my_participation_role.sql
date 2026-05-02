-- ============================================================================
-- Elsewhere — Self-only participation role flip
-- Migration: 017
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- First commit of three implementing the active/audience UX cluster per
-- docs/GAMES-CONTROL-MODEL.md § 2.4.3 (amended 2026-05-02). Single
-- SECURITY DEFINER RPC that lets a participant flip their own
-- participation_role between 'active' and 'audience' without going
-- through the manager-cross-user path (rpc_session_update_participant).
--
-- See docs/GAMES-CONTROL-MODEL.md § 2.4.3 for the UX scope.
--
-- RPCs in this migration:
--   • rpc_session_set_my_participation_role(p_session_id, p_role)
--                                            → session_participants
--
-- Key behaviors:
--
-- rpc_session_set_my_participation_role:
--   Self-only flip between 'active' and 'audience'. Caller is identified
--   via auth.uid(); only the caller's own row is updated.
--
--   Authorization: caller must be authenticated. Cross-user role changes
--   are not supported here — use rpc_session_update_participant (manager-
--   cross-user) for those.
--
--   Validation: p_role must be 'active' or 'audience'. The 'queued' value
--   is deliberately not allowed via this RPC; queue transitions go through
--   rpc_session_update_queue_position / rpc_session_promote_self_from_queue.
--   control_role changes go through manager-only paths in db/010 / db/011.
--
--   No-op idempotency: if the caller's row already has participation_role
--   = p_role, returns the existing row unchanged. Safe under realtime
--   races where multiple clients converge on the same flip.
--
--   Capacity behavior: the existing capacity trigger (db/006 / db/009)
--   fires on the underlying UPDATE and raises 55000 if an audience →
--   active flip would exceed the per-game cap. The caller catches that
--   and surfaces the "Room is full — remove a player first." toast per
--   § 2.4.3.
--
--   Bumps sessions.last_activity_at on success.
--
-- Realtime publishing is caller-side per existing pattern (RPCs do NOT
-- publish realtime events). Caller publishes participant_role_changed
-- after RPC success per shell/realtime.js doctrine.
--
-- Error codes (consistent with db/006, db/009, db/010, db/011, db/013, db/016):
--   42501 — authentication / authorization failures
--   02000 — not found / state invalid
--   22023 — invalid parameter value (p_role not in active|audience)
--   55000 — propagated from capacity trigger on audience → active flip
--
-- Idempotency: CREATE OR REPLACE FUNCTION. Safe to re-run.
-- ============================================================================


-- ─── 1. rpc_session_set_my_participation_role ──────────────────────────────
-- Self-only flip between 'active' and 'audience'. Caller identified via
-- auth.uid(). Validates role enum, no-op idempotency on already-in-target,
-- propagates capacity errors. Bumps session activity.
create or replace function public.rpc_session_set_my_participation_role(
  p_session_id uuid,
  p_role       text
)
returns public.session_participants
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_row     public.session_participants;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- Validate role enum.
  if p_role not in ('active', 'audience') then
    raise exception 'invalid role: must be active or audience, got %', p_role
      using errcode = '22023';
  end if;

  -- Find caller's row in this session. Order by joined_at desc to pick the
  -- most recent in the unlikely case of multiple rows for the same user_id.
  select * into v_row
    from public.session_participants
   where session_id = p_session_id
     and user_id    = v_user_id
     and left_at   is null
   order by joined_at desc
   limit 1;

  if v_row.id is null then
    raise exception 'caller is not a participant in session %', p_session_id
      using errcode = '02000';
  end if;

  -- No-op idempotency: already in target state.
  if v_row.participation_role = p_role then
    return v_row;
  end if;

  -- Update. The existing capacity trigger (db/006 / db/009) fires here and
  -- raises 55000 if an audience → active flip would exceed the per-game cap.
  -- That's caught by the caller and surfaced as the "Room is full — remove
  -- a player first." toast per docs/GAMES-CONTROL-MODEL.md § 2.4.3.
  update public.session_participants
     set participation_role = p_role
   where id = v_row.id
  returning * into v_row;

  -- Bump session activity.
  update public.sessions set last_activity_at = now() where id = p_session_id;

  return v_row;
end;
$$;

grant execute on function public.rpc_session_set_my_participation_role(uuid, text) to authenticated;

comment on function public.rpc_session_set_my_participation_role(uuid, text) is
  'Self-only participation_role flip between active and audience. '
  'Caller updates only their own session_participants row via auth.uid(). '
  'Validates role enum (active|audience) and propagates capacity errors '
  '(55000) from existing capacity trigger when audience→active would '
  'exceed per-game cap. Realtime publish is caller-side per '
  'shell/realtime.js doctrine — caller publishes participant_role_changed '
  'after success.';


-- ─── Verification ─────────────────────────────────────────────────────────
select 'migration 017 loaded' as status;
