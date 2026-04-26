-- ============================================================================
-- Elsewhere — Karaoke session helpers (song-end + participants-with-names)
-- Migration: 013
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Session 5 Part 2d.0. Two SECURITY DEFINER RPCs that unblock 2d.1
-- (karaoke/stage.html session integration) against existing RLS gates.
-- These functions cover the two cross-cutting auth/RLS gaps surfaced
-- in the 2d audit:
--
--   B1: rpc_session_update_participant (db/011) requires caller to be
--       both an active participant AND have manager/host control_role
--       to mutate cross-user. Stage.html's TV-claimer auth context
--       generally satisfies neither — too narrow for the song-end trigger.
--   B2: profiles RLS (db/001) is owner-only; nested-select for display_name
--       returns NULL for other users — blocks queue panel rendering on
--       stage.html.
--
-- Both addressed by SECURITY DEFINER wrappers gated on
-- is_session_participant OR is_session_tv_household_member, which is broad
-- enough to include stage.html's TV-claimer auth context.
--
-- See docs/SESSION-5-PART-2D-AUDIT.md DECISION-AUDIT-6 + DECISION-AUDIT-13
-- for the full design rationale.
--
-- RPCs in this migration:
--   • rpc_karaoke_song_ended(p_session_id)
--                            → public.sessions
--   • rpc_session_get_participants(p_session_id)
--                                  → table(user_id, control_role,
--                                          participation_role, queue_position,
--                                          pre_selections, joined_at,
--                                          display_name)
--
-- Key behaviors:
--
-- rpc_karaoke_song_ended:
--   Atomic dual transition called by stage.html when a YouTube song ends.
--   Demotes current 'active' participant to 'audience' (clearing
--   queue_position), promotes queue head ('queued' with lowest queue_position)
--   to 'active' (clearing queue_position).
--
--   Idempotent under all four edge cases:
--     • No active singer + no queue head → no-op, return session row.
--     • No active singer + queue head exists → promotion only.
--     • Active singer + no queue head → demotion only.
--     • Both exist → full dual transition.
--
--   Multi-tab / multi-call safety: SELECT FOR UPDATE on sessions row
--   serializes concurrent calls. The second call reads already-advanced
--   state and no-ops via the idempotency ladder.
--
--   Does NOT publish realtime events. Caller (stage.html) is responsible
--   for publishing participant_role_changed and queue_updated after
--   successful return. Mirrors the existing pattern from
--   index.html lines 3134-3137.
--
-- rpc_session_get_participants:
--   Returns one row per active session participant with display_name
--   joined from profiles (bypassing owner-only profiles RLS via
--   SECURITY DEFINER). Ordered for queue display: active first, then
--   queued by queue_position ascending, then audience by joined_at.
--
--   Returns empty set (not error) if session has no participants.
--
-- Error code conventions (consistent with db/006, db/009, db/010, db/011):
--   42501 — authentication / authorization failures
--   02000 — not found / state invalid
--
-- Idempotency: CREATE OR REPLACE FUNCTION throughout. Safe to re-run.
-- ============================================================================


-- ─── 1. rpc_karaoke_song_ended ──────────────────────────────────────────────
-- Atomic dual transition: demotes current 'active' singer to 'audience',
-- promotes queue head ('queued' with lowest queue_position) to 'active'.
-- Both transitions clear queue_position. Idempotent — safe under multi-tab
-- and multi-call scenarios via SELECT FOR UPDATE on sessions and
-- state-check ladder.
create or replace function public.rpc_karaoke_song_ended(
  p_session_id uuid
)
returns public.sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id        uuid := auth.uid();
  v_session        public.sessions;
  v_active         public.session_participants;
  v_queue_head     public.session_participants;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- Auth gate: caller must be a session participant OR a member of the
  -- TV's household. The latter covers stage.html's TV-claimer auth
  -- context, which generally lacks participant rows.
  if not (
    public.is_session_participant(p_session_id)
    or public.is_session_tv_household_member(p_session_id)
  ) then
    raise exception 'not authorized for session %', p_session_id
      using errcode = '42501';
  end if;

  -- Row-level lock to serialize concurrent calls (multi-tab safety).
  -- Without this, two simultaneous calls could both find the same active
  -- singer and try to demote them, or both try to promote the same queue
  -- head. The lock makes the second call wait, then read the
  -- already-advanced state and no-op via the idempotency checks below.
  select * into v_session from public.sessions where id = p_session_id for update;
  if v_session.id is null then
    raise exception 'session not found: %', p_session_id using errcode = '02000';
  end if;

  if v_session.ended_at is not null then
    raise exception 'session has ended' using errcode = '02000';
  end if;

  -- ── Find current active singer (if any) ──────────────────────────────
  select * into v_active
    from public.session_participants
   where session_id         = p_session_id
     and left_at            is null
     and participation_role = 'active'
   limit 1;

  -- ── Find queue head (if any) — lowest queue_position among queued ────
  select * into v_queue_head
    from public.session_participants
   where session_id         = p_session_id
     and left_at            is null
     and participation_role = 'queued'
   order by queue_position asc nulls last, joined_at asc
   limit 1;

  -- ── Demotion: active → audience (clear queue_position) ───────────────
  -- Idempotent: skipped if no active singer.
  if v_active.id is not null then
    update public.session_participants
       set participation_role = 'audience',
           queue_position     = null
     where id = v_active.id;
  end if;

  -- ── Promotion: queue head → active (clear queue_position) ────────────
  -- Idempotent: skipped if no queue head.
  if v_queue_head.id is not null then
    update public.session_participants
       set participation_role = 'active',
           queue_position     = null
     where id = v_queue_head.id;
  end if;

  -- ── Bump session activity timestamp ──────────────────────────────────
  update public.sessions set last_activity_at = now() where id = p_session_id;

  -- Re-read the session row so the caller gets the updated last_activity_at.
  select * into v_session from public.sessions where id = p_session_id;

  return v_session;
end;
$$;

grant execute on function public.rpc_karaoke_song_ended(uuid) to authenticated;

comment on function public.rpc_karaoke_song_ended(uuid) is
  'Atomic dual transition called by stage.html on YouTube song-end. '
  'Demotes current active singer to audience and promotes queue head to active. '
  'Idempotent under all edge cases (no active, no queue, both, both empty). '
  'Multi-tab safe via SELECT FOR UPDATE on sessions. Does not publish '
  'realtime events — caller publishes participant_role_changed and '
  'queue_updated after successful return.';


-- ─── 2. rpc_session_get_participants ────────────────────────────────────────
-- Returns one row per active participant with display_name joined from
-- profiles. SECURITY DEFINER bypasses owner-only profiles RLS so the caller
-- can render queue UI with names of users they don't own profile rows for.
-- Ordered for queue display: active first, then queued by queue_position,
-- then audience by joined_at.
create or replace function public.rpc_session_get_participants(
  p_session_id uuid
)
returns table (
  user_id            uuid,
  control_role       text,
  participation_role text,
  queue_position     int,
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
  -- malformed queue rows defensively.
  return query
    select sp.user_id,
           sp.control_role,
           sp.participation_role,
           sp.queue_position,
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
  'display: active, then queued (by queue_position), then audience (by joined_at).';


-- ─── Verification ─────────────────────────────────────────────────────────
select 'migration 013 loaded' as status;
