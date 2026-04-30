-- ============================================================================
-- Elsewhere — Manager-only participant removal
-- Migration: 016
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Session 5 Part 3a prereq. Single SECURITY DEFINER RPC for manager
-- moderation: a manager can soft-remove another active participant
-- from their session. Removed user's row gets left_at = now(); they
-- no longer appear in session participant queries; their phone
-- navigates away on receiving the realtime broadcast (caller-side
-- per shell/realtime.js doctrine).
--
-- See docs/GAMES-CONTROL-MODEL.md § 2.5 for the UX scope.
--
-- RPCs in this migration:
--   • rpc_session_remove_participant(p_session_id, p_user_id)
--                                    → session_participants
--
-- Key behaviors:
--
-- rpc_session_remove_participant:
--   Manager-only cross-user soft-delete. Sets left_at = now() on the
--   target's row. Returns the updated row.
--
--   Authorization: caller must be the active manager of the session
--   (control_role='manager', left_at IS NULL).
--
--   Self-removal not allowed via this RPC. Managers leaving must use
--   rpc_session_leave (which has auto-promote logic per db/010).
--   Non-managers leaving also use rpc_session_leave with their own row.
--
--   No-op idempotency: if target is already left (left_at IS NOT NULL),
--   returns the existing row unchanged. Safe under realtime races where
--   multiple clients converge on the same removal.
--
--   Bumps sessions.last_activity_at on success.
--
-- Realtime publishing is caller-side per existing pattern (RPCs do NOT
-- publish realtime events). Caller publishes participant_role_changed
-- after RPC success per shell/realtime.js doctrine.
--
-- Error codes (consistent with db/006, db/009, db/010, db/011, db/013):
--   42501 — authentication / authorization failures
--   02000 — not found / state invalid
--   22023 — invalid parameter value (target = self)
--
-- Idempotency: CREATE OR REPLACE FUNCTION. Safe to re-run.
-- ============================================================================


-- ─── 1. rpc_session_remove_participant ──────────────────────────────────────
-- Manager-only soft-delete of another active participant. Sets target's
-- left_at = now() on their session_participants row. Returns the updated
-- target row (or the unchanged row if target was already left).
create or replace function public.rpc_session_remove_participant(
  p_session_id uuid,
  p_user_id    uuid
)
returns public.session_participants
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_caller  public.session_participants;
  v_target  public.session_participants;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- Self-removal disallowed: managers should use rpc_session_leave
  -- (auto-promote logic in db/010); non-managers should also use
  -- rpc_session_leave for their own row.
  if p_user_id = v_user_id then
    raise exception 'cannot remove self via rpc_session_remove_participant; use rpc_session_leave instead'
      using errcode = '22023';
  end if;

  -- Authorization: caller must be the active manager of this session.
  -- Hosts CANNOT remove participants in Phase 1 (matches the conservative
  -- pattern of other manager-only-cross-user RPCs; revisit if real demand
  -- surfaces).
  select * into v_caller
    from public.session_participants
   where session_id   = p_session_id
     and user_id      = v_user_id
     and left_at     is null
     and control_role = 'manager';

  if v_caller.id is null then
    raise exception 'not authorized: only the active session manager can remove participants'
      using errcode = '42501';
  end if;

  -- Find target row. If already left, return unchanged (no-op idempotency).
  -- Order by joined_at desc to pick the most recent row in the unlikely
  -- case of multiple rows for the same user_id (shouldn't happen given
  -- the schema, but defensive).
  select * into v_target
    from public.session_participants
   where session_id = p_session_id
     and user_id    = p_user_id
   order by joined_at desc
   limit 1;

  if v_target.id is null then
    raise exception 'target user is not a participant in session %', p_session_id
      using errcode = '02000';
  end if;

  if v_target.left_at is not null then
    -- Already removed; return as-is for idempotency.
    return v_target;
  end if;

  -- Soft-delete the target's row.
  update public.session_participants
     set left_at = now()
   where id = v_target.id
  returning * into v_target;

  -- Bump session activity.
  update public.sessions set last_activity_at = now() where id = p_session_id;

  return v_target;
end;
$$;

grant execute on function public.rpc_session_remove_participant(uuid, uuid) to authenticated;

comment on function public.rpc_session_remove_participant(uuid, uuid) is
  'Manager-only soft-removal of another active participant. Sets left_at = now() '
  'on target''s row. Self-removal disallowed; use rpc_session_leave instead. '
  'Idempotent: no-op if target is already left. Realtime publish is caller-side per '
  'shell/realtime.js doctrine — caller publishes participant_role_changed after success.';


-- ─── Verification ─────────────────────────────────────────────────────────
select 'migration 016 loaded' as status;
