-- ============================================================================
-- Elsewhere — Session-start manager-role branched-default fix
-- Migration: 018
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Hardware verification of v2.104 (commit 754d0a8) on 2026-05-02 surfaced
-- that the games manager landed as participation_role='audience' despite
-- the caller-side override in games/player.html doJoin. Root cause:
-- rpc_session_start (db/009:108-114) hardcodes the initial manager's
-- participation_role as 'audience' regardless of app, bypassing the
-- caller-side join logic entirely. v2.104 only fixed the non-manager
-- fresh-join path (rpc_session_join in doJoin).
--
-- Per docs/GAMES-CONTROL-MODEL.md § 2.4.4 (amended 2026-05-02 in commit
-- 410ccc1), lobby-state self-join for games defaults to 'active' — the
-- manager creating a games session is committing to play, not spectate.
--
-- Per docs/KARAOKE-CONTROL-MODEL.md § 1 vocabulary trap, the karaoke
-- manager landing as schema-state 'audience' is correct and must NOT
-- change: for HHU surfaces, schema-state 'audience' = "Available Singer
-- (not queued)". The karaoke manager is an Available Singer who hasn't
-- queued yet — exactly what 'audience' means there.
--
-- Fix: branch the manager's initial participation_role on p_app at the
-- INSERT site. CREATE OR REPLACE FUNCTION on rpc_session_start with the
-- same signature; only the INSERT body and comment block change.
--
-- Functions in this migration:
--   • rpc_session_start(p_tv_device_id, p_app, p_admission_mode, p_capacity,
--                       p_ask_proximity, p_turn_completion, p_room_code)
--                       → sessions
--
-- Key behavior change vs db/009:
--
-- rpc_session_start (manager INSERT):
--   Branches manager's participation_role on p_app:
--     - 'games'   → 'active'   (per GAMES-CONTROL-MODEL.md § 2.4.4)
--     - all other → 'audience' (preserves karaoke schema-state semantics
--                               and is the safe default for any future
--                               app until that app's control model spec
--                               is amended)
--
--   No other behavior changes. Same signature, same authorization checks,
--   same one-active-session-per-TV enforcement, same return type.
--
-- Idempotency: CREATE OR REPLACE FUNCTION. Safe to re-run. Replaces the
-- function shipped in db/009 in-place; db/009 stays in repo as historical
-- record (migrations are append-only history, not edited-in-place).
-- ============================================================================


-- ─── 1. rpc_session_start ─────────────────────────────────────────────────
-- Creates a new session on the given TV with the caller as initial manager.
-- The caller must be a household member of the TV's household. Only one
-- active session per TV is allowed — call rpc_session_end on an existing
-- session first (or use Part 1b.2's reclaim RPCs if the current manager
-- has gone inactive).
--
-- SECURITY DEFINER because direct INSERT on sessions / session_participants
-- is blocked by RLS (no write policies). The function performs the
-- authorization check explicitly via is_tv_household_member().
create or replace function public.rpc_session_start(
  p_tv_device_id    uuid,
  p_app             text,
  p_admission_mode  text,
  p_capacity        int,
  p_ask_proximity   boolean,
  p_turn_completion text,
  p_room_code       text default null
)
returns public.sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_session public.sessions;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if not public.is_tv_household_member(p_tv_device_id) then
    raise exception 'not a member of this TV''s household' using errcode = '42501';
  end if;

  -- Enforce "one active session per TV" with a clear error message.
  -- The sessions_one_active_per_tv unique partial index is a belt-and-
  -- suspenders fallback for concurrent inserts.
  if exists (
    select 1 from public.sessions
     where tv_device_id = p_tv_device_id and ended_at is null
  ) then
    raise exception 'an active session already exists on this TV'
      using errcode = '23505';
  end if;

  insert into public.sessions (
    tv_device_id, app, manager_user_id,
    admission_mode, capacity, ask_proximity, turn_completion, room_code
  )
  values (
    p_tv_device_id, p_app, v_user_id,
    p_admission_mode, p_capacity, p_ask_proximity, p_turn_completion, p_room_code
  )
  returning * into v_session;

  -- Initial manager's participant row. participation_role branches on p_app:
  --   'games'   → 'active'   per docs/GAMES-CONTROL-MODEL.md § 2.4.4 —
  --                          lobby-state self-join defaults to 'active'.
  --                          The manager creating a games session is
  --                          committing to play.
  --   karaoke   → 'audience' per docs/KARAOKE-CONTROL-MODEL.md § 1 —
  --                          schema-state 'audience' on HHU surfaces means
  --                          "Available Singer (not queued)". The karaoke
  --                          manager hasn't queued a song yet, so this is
  --                          the correct initial state.
  --   anything  → 'audience' as a safe default until that app's control
  --   else                   model spec defines its lobby-state semantics.
  insert into public.session_participants (
    session_id, user_id, control_role, participation_role
  )
  values (
    v_session.id, v_user_id, 'manager',
    case when p_app = 'games' then 'active' else 'audience' end
  );

  return v_session;
end;
$$;

grant execute on function public.rpc_session_start(uuid, text, text, int, boolean, text, text) to authenticated;

comment on function public.rpc_session_start(uuid, text, text, int, boolean, text, text) is
  'Creates a new session on the given TV with the caller as initial manager. '
  'Caller must be a household member of the TV''s household. Raises if an '
  'active session already exists for this TV. Snapshots manifest values '
  '(admission_mode, capacity, ask_proximity, turn_completion) onto the '
  'sessions row. Inserts a session_participants row for the caller with '
  'control_role=''manager'' and participation_role branched on p_app: '
  '''active'' for games (per GAMES-CONTROL-MODEL § 2.4.4); ''audience'' '
  'for karaoke and other apps (per KARAOKE-CONTROL-MODEL § 1 schema-state '
  'semantics where ''audience'' on HHU surfaces means Available Singer).';


-- ─── Verification ─────────────────────────────────────────────────────────
select 'migration 018 loaded' as status;
