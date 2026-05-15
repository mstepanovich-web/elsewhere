-- ============================================================================
-- Elsewhere — Admission Model v2 schema migration (W1)
-- Migration: 020
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Implements work item W1 from docs/ADMISSION-MODEL-V2.md § 10. Additive
-- schema changes only: adds a wanting_since column on session_participants
-- and relaxes the sessions.admission_mode constraint to support the new
-- two-mode model (open/gated) plus the lobby-window NULL state.
--
-- DESIGN NOTES — what this migration does NOT change:
--
--   • participation_role enum values themselves — preserved as 'active',
--     'audience', 'queued' (per docs/ADMISSION-MODEL-V2.md § 3 + § 2.7).
--   • queue_position column on session_participants — retained for
--     karaoke's continued use (rpc_karaoke_song_ended,
--     rpc_karaoke_get_participants both depend on it; see
--     docs/ADMISSION-MODEL-V2.md § 2.7). Games code under W3-W10
--     stops reading or writing it.
--   • session_participants_queue_idx (partial unique index on
--     queue_position) — retained alongside the column.
--   • All karaoke-specific RPCs (rpc_karaoke_*) — untouched.
--   • All Games-side RPCs that reference participation_role values —
--     untouched in this migration. Per-game admission_mode stamping
--     and RPC updates land in W2.
--
-- BACKFILL: wanting_since is backfilled to joined_at for existing
-- 'queued' rows. This gives queued users a reasonable timestamp so the
-- new ordering (wanting_since ASC) doesn't sort them randomly after
-- W3-W10 client code starts reading it.
--
-- ADMISSION_MODE TRANSITION: existing sessions with old admission_mode
-- values ('self_join', 'wait_for_next', 'manager_approved_single',
-- 'manager_approved_batch') are set to NULL before the new CHECK
-- constraint is added. The new constraint allows NULL + 'open' + 'gated'
-- only. W2 will populate admission_mode per-game at game-start.
--
-- IDEMPOTENCY: the new CHECK constraint is named explicitly
-- (sessions_admission_mode_check). DROP CONSTRAINT IF EXISTS handles the
-- case where the existing inline constraint was auto-named with the same
-- name by Postgres convention. If the actual auto-name differs in prod
-- (rare but possible), the DROP will be a no-op and the ADD CONSTRAINT
-- will fail with "constraint already exists" — verify constraint name
-- in prod before applying if uncertain via:
--   SELECT conname FROM pg_constraint
--    WHERE conrelid = 'public.sessions'::regclass
--      AND contype = 'c';
--
-- TRANSACTIONAL: the whole migration is wrapped in BEGIN/COMMIT so a
-- failure at any step rolls back the entire change.
-- ============================================================================

begin;

-- ────────────────────────────────────────────────────────────────────────
-- 1. Drop the existing inline CHECK constraint on sessions.admission_mode.
--    Postgres auto-names column-level inline constraints as
--    <table>_<column>_check; in this case sessions_admission_mode_check.
--    IF EXISTS is defensive in case the actual auto-name differs in prod.
--    Done FIRST so the subsequent UPDATE to NULL (step 3) isn't blocked
--    by the old constraint set.
-- ────────────────────────────────────────────────────────────────────────
alter table public.sessions
  drop constraint if exists sessions_admission_mode_check;

-- ────────────────────────────────────────────────────────────────────────
-- 2. Relax the NOT NULL constraint on sessions.admission_mode. The new
--    model has a lobby window (between session creation and game-start)
--    during which admission_mode is undefined; NULL represents that
--    state. Done BEFORE the UPDATE to NULL (step 3) so the column
--    declaration accepts NULL writes.
-- ────────────────────────────────────────────────────────────────────────
alter table public.sessions
  alter column admission_mode drop not null;

-- ────────────────────────────────────────────────────────────────────────
-- 3. Transition existing sessions.admission_mode values out of the old
--    enum set. Old values that map to none of {open, gated} go to NULL;
--    W2 will re-stamp admission_mode per-game on game-start. Runs AFTER
--    both the CHECK (step 1) and NOT NULL (step 2) are relaxed so the
--    UPDATE succeeds; runs BEFORE the new CHECK is added (step 4) so the
--    new constraint doesn't reject any rows on creation.
-- ────────────────────────────────────────────────────────────────────────
update public.sessions
   set admission_mode = null
 where admission_mode not in ('open', 'gated');

-- ────────────────────────────────────────────────────────────────────────
-- 4. Add the new CHECK constraint allowing NULL + 'open' + 'gated' only.
--    Named explicitly so future migrations can DROP it by name without
--    relying on Postgres's auto-naming convention.
-- ────────────────────────────────────────────────────────────────────────
alter table public.sessions
  add constraint sessions_admission_mode_check
  check (admission_mode is null or admission_mode in ('open', 'gated'));

-- ────────────────────────────────────────────────────────────────────────
-- 5. Add wanting_since column on session_participants. Nullable, no
--    default — the column is populated at the moment a participant
--    transitions to participation_role='queued' (by W3-W10 client code
--    via rpc_session_update_participant). Pre-existing 'queued' rows are
--    backfilled in step 6 below.
-- ────────────────────────────────────────────────────────────────────────
alter table public.session_participants
  add column wanting_since timestamp with time zone;

-- ────────────────────────────────────────────────────────────────────────
-- 6. Backfill wanting_since for pre-existing 'queued' rows using
--    joined_at as the best-available approximation. Without this
--    backfill, queued users would sort unpredictably after W3-W10
--    starts reading wanting_since for queue ordering.
-- ────────────────────────────────────────────────────────────────────────
update public.session_participants
   set wanting_since = joined_at
 where participation_role = 'queued'
   and wanting_since is null;

commit;

-- ============================================================================
-- POST-MIGRATION VERIFICATION
--
-- After applying, run these checks against prod via Supabase SQL editor:
--
-- -- Expect: NULL only, until W2 starts stamping 'open'/'gated' at game-start.
-- SELECT DISTINCT admission_mode FROM sessions;
--
-- -- Expect: active, audience, queued (unchanged from before).
-- SELECT DISTINCT participation_role FROM session_participants;
--
-- -- Expect: 0 (backfill applied to all pre-existing queued rows).
-- SELECT COUNT(*) FROM session_participants
--  WHERE participation_role = 'queued' AND wanting_since IS NULL;
--
-- -- Verify wanting_since column present on session_participants.
-- \d session_participants
--
-- -- Verify admission_mode is nullable + new CHECK in place.
-- \d sessions
-- -- Look for: "admission_mode | text |  |" (no NOT NULL)
-- -- Look for: Check constraint "sessions_admission_mode_check" CHECK
-- --          (admission_mode IS NULL OR admission_mode = ANY (ARRAY[
-- --           'open'::text, 'gated'::text]))
--
-- -- Confirm karaoke-critical artifacts are untouched.
-- -- Expect: queue_position column still present, partial unique index
-- -- session_participants_queue_idx still present.
-- \d session_participants
-- ============================================================================
