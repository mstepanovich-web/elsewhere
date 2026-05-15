-- ============================================================================
-- Elsewhere — Manager-only admission_mode stamping
-- Migration: 021
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Implements work item W2 from docs/ADMISSION-MODEL-V2.md § 10. Single
-- SECURITY DEFINER RPC that lets the session manager stamp
-- admission_mode + capacity onto the sessions row at game-start time
-- (and clear them on Switch Game).
--
-- See docs/ADMISSION-MODEL-V2.md § 2.3 + § 6 for the model. Admission
-- mode is now a per-game property, not a per-app property — Games
-- sessions set it on manager-taps-Start-Game, NOT at session-create.
-- This RPC is the schema-side endpoint for that stamping.
--
-- Expected callers (all in games/player.html):
--   • managerStartTrivia      → stamp ('open',  null)        for Trivia
--   • managerStartLastCard    → stamp ('gated', playerLimit) for Last Card
--   • managerStartEuchre      → stamp ('gated', 4)           for Euchre
--   • managerSwitchGame       → stamp (null,    null)        on switch
--
-- RPCs in this migration:
--   • rpc_session_set_admission_mode(p_session_id, p_admission_mode, p_capacity)
--                                    → session_participants  (returns the updated
--                                                              sessions row for
--                                                              caller convenience)
--
-- Key behaviors:
--
-- rpc_session_set_admission_mode:
--   Manager-only mid-session stamping of sessions.admission_mode and
--   sessions.capacity. Allowed values for p_admission_mode: NULL,
--   'open', or 'gated' — matches the CHECK constraint added by
--   db/020 (sessions_admission_mode_check). Capacity is NULL (no
--   limit) or a positive integer; the column itself is `int` with
--   no constraint beyond the existing capacity trigger.
--
--   Authorization: caller must be the active manager of the session
--   (session_participants.control_role = 'manager', left_at IS NULL,
--   for the caller's row in this session). Hosts cannot stamp
--   admission_mode in Phase 1 (matches the conservative pattern of
--   other manager-only-cross-row RPCs; revisit if real demand
--   surfaces).
--
--   Bumps sessions.last_activity_at on success, matching the pattern
--   of other manager-action RPCs.
--
-- Error codes (consistent with db/009, db/011, db/016, db/017):
--   42501 — authentication / authorization failures (not the manager)
--   02000 — not found / state invalid (session ended or missing)
--   22023 — invalid parameter value (admission_mode not in valid set)
--
-- Idempotency: CREATE OR REPLACE FUNCTION. Re-stamping with the same
-- values is a no-op write (UPDATE with no row changes); the function
-- still returns the updated row and bumps last_activity_at.
-- ============================================================================

begin;

-- ─── 1. rpc_session_set_admission_mode ──────────────────────────────────────
-- Manager-only mid-session stamp of admission_mode + capacity onto the
-- sessions row. Returns the updated row.
create or replace function public.rpc_session_set_admission_mode(
  p_session_id      uuid,
  p_admission_mode  text,
  p_capacity        int
)
returns public.sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_caller  public.session_participants;
  v_session public.sessions;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- Validate p_admission_mode against the same set the
  -- sessions_admission_mode_check CHECK constraint allows.
  if p_admission_mode is not null
     and p_admission_mode not in ('open', 'gated') then
    raise exception 'invalid admission_mode: % (must be NULL, ''open'', or ''gated'')',
                    p_admission_mode
      using errcode = '22023';
  end if;

  -- Look up the session. Must exist and not be ended.
  select * into v_session
    from public.sessions
   where id = p_session_id;

  if v_session.id is null then
    raise exception 'session not found: %', p_session_id
      using errcode = '02000';
  end if;

  if v_session.ended_at is not null then
    raise exception 'session has ended' using errcode = '02000';
  end if;

  -- Authorization: caller must be the active manager of this session.
  select * into v_caller
    from public.session_participants
   where session_id   = p_session_id
     and user_id      = v_user_id
     and left_at     is null
     and control_role = 'manager';

  if v_caller.id is null then
    raise exception 'not authorized: only the active session manager can set admission_mode'
      using errcode = '42501';
  end if;

  -- Apply the stamp. Bumps last_activity_at in the same UPDATE.
  update public.sessions
     set admission_mode   = p_admission_mode,
         capacity         = p_capacity,
         last_activity_at = now()
   where id = p_session_id
  returning * into v_session;

  return v_session;
end;
$$;

grant execute on function public.rpc_session_set_admission_mode(uuid, text, int) to authenticated;

comment on function public.rpc_session_set_admission_mode(uuid, text, int) is
  'Manager-only mid-session stamp of sessions.admission_mode and '
  'sessions.capacity. Validates p_admission_mode against the same set the '
  'sessions_admission_mode_check CHECK allows (NULL | ''open'' | ''gated''). '
  'Authorization: caller must be the active session manager '
  '(control_role=''manager'', left_at IS NULL). Bumps sessions.last_activity_at '
  'on success. Called from games/player.html''s managerStart{Trivia,LastCard,Euchre} '
  'and managerSwitchGame per docs/ADMISSION-MODEL-V2.md § 2.3 + § 6.';

commit;

-- ─── Verification ─────────────────────────────────────────────────────────
select 'migration 021 loaded' as status;

-- ============================================================================
-- POST-MIGRATION VERIFICATION
--
-- After applying, run these checks against prod via Supabase SQL editor:
--
-- -- Function exists.
-- SELECT proname FROM pg_proc WHERE proname = 'rpc_session_set_admission_mode';
-- --   Expect: 1 row.
--
-- -- Parameter names + modes match the spec.
-- SELECT proargnames, proargmodes FROM pg_proc
--  WHERE proname = 'rpc_session_set_admission_mode';
-- --   Expect: proargnames = {p_session_id, p_admission_mode, p_capacity};
-- --           proargmodes NULL (all IN params; Postgres represents this
-- --           as NULL when all are IN, since IN is the default).
--
-- -- Function is grantable to authenticated.
-- SELECT pg_get_functiondef(oid)
--   FROM pg_proc WHERE proname = 'rpc_session_set_admission_mode';
-- --   Expect: SECURITY DEFINER + GRANT to authenticated.
--
-- -- Smoke test (replace <test-session-uuid> with a real session you manage):
-- SELECT * FROM rpc_session_set_admission_mode(
--   '<test-session-uuid>'::uuid,
--   'gated',
--   6
-- );
-- -- Then confirm the row updated:
-- SELECT admission_mode, capacity, last_activity_at
--   FROM sessions
--  WHERE id = '<test-session-uuid>'::uuid;
-- --   Expect: admission_mode = 'gated', capacity = 6, last_activity_at recent.
--
-- -- Confirm validation rejects invalid values:
-- SELECT rpc_session_set_admission_mode(
--   '<test-session-uuid>'::uuid,
--   'self_join',  -- old value, no longer valid
--   null
-- );
-- --   Expect: ERROR 22023 invalid admission_mode: self_join (...)
--
-- -- Confirm authorization rejects non-managers:
-- -- (Run as a non-manager session participant via Supabase auth context.)
-- SELECT rpc_session_set_admission_mode(
--   '<test-session-uuid>'::uuid, 'gated', 6
-- );
-- --   Expect: ERROR 42501 not authorized: only the active session manager (...)
-- ============================================================================
