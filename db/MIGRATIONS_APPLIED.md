# Migrations Applied to Production

This file tracks which `db/*.sql` migrations have been applied to the production Supabase database (project `gbrnuxyzrlzbybvcvyzm`). Update this file whenever a migration is run against prod.

**Doctrine (per CLAUDE.md):** A migration committed to the repo but not applied to prod is NOT shipped — only the actual prod application counts. Update this table when applying a migration; flag `❓ Verify` if applied state is unknown.

| Migration | Applied | Date Applied | Applied By | Notes |
|---|---|---|---|---|
| 001_user_management_schema.sql | ✅ | (pre-Session-5) | Mike | Foundational auth + profiles schema. Production sign-in works → applied. |
| 002_contacts_avatars.sql | ✅ | (pre-Session-5) | Mike | Avatar uploads via Supabase Storage verified on hardware (recent contacts work, commits `b267e41` + `5e44d5e`). |
| 003_admin_and_venue_settings.sql | ✅ | (pre-Session-5) | Mike | Venue admin functions used in karaoke/stage.html admin dialog. |
| 004_rename_is_admin_to_is_platform_admin.sql | ✅ | (pre-Session-5) | Mike | Column rename; downstream code references `is_platform_admin` and works. |
| 005_front_back_venue_tuning.sql | ✅ | (pre-Session-5) | Mike | Venue tuning fields (back_yaw, back_pitch) used by karaoke stage admin dialog. |
| 006_household_and_tv_devices.sql | ✅ | (Session 4.10) | Mike | Household + TV claim flow shipped in Session 4.10; production works end-to-end. |
| 007_anon_tv_is_registered.sql | ✅ | (Session 4.10) | Mike | TV registration check used at boot; claim flow works. |
| 008_sessions_and_participants.sql | ✅ | (Session 5 Part 1a) | Mike | Sessions schema verified on hardware in 3a.1 + 3a.2 (manager identity derives from session_participants.control_role). |
| 009_session_lifecycle_rpcs.sql | ✅ | (Session 5 Part 1b.1) | Mike | rpc_session_start/join/leave/end all verified on hardware in 3a.1 + 3a.2. |
| 010_manager_mechanics_rpcs.sql | ✅ | (Session 5 Part 1b.2) | Mike | Auto-promote + reclaim_manager RPCs. Karaoke Part 2e session lifecycle relies on db/010's updated rpc_session_leave; 2e shipped end-to-end. |
| 011_role_and_queue_mutation_rpcs.sql | ✅ | (Session 5 Part 1b.3) | Mike | rpc_session_update_participant verified on hardware in 3a.2 manager-as-player toggle. |
| 012_user_preferences.sql | ✅ | (Session 5 Part 2c.1) | Mike | Proximity banner persistence (2c.2) ships against this; 2c shipped at commits `daa8718`, `0a3a9ea`, `e4a348e`, `5617689`. |
| 013_karaoke_session_helpers.sql | ✅ | (Session 5 Part 2d.0) | Mike | Explicitly recorded as shipped in `docs/SESSION-5-PART-2-CLOSING-LOG.md` row 2d.0. |
| 014_push_subscriptions.sql | ✅ | (Session 5 Part 2e.0) | Mike | Push notification infrastructure verified end-to-end on iPhone per `docs/CONTEXT.md` history. |
| 015_promotion_push_trigger.sql | ✅ | (Session 5 Part 2e.2; verified 2026-05-03) | Mike | Verified applied to prod 2026-05-03 via `SELECT tgname FROM pg_trigger WHERE tgname = 'trg_fire_promotion_push'` (returned 1 row) and `SELECT proname FROM pg_proc WHERE proname = 'fire_promotion_push'` (returned 1 row). Both objects defined in db/015 are present. Original application history was unclear at the time of MIGRATIONS_APPLIED.md's creation; this verification closes that uncertainty. |
| 016_remove_participant.sql | ✅ | 2026-05-02 | Mike | Applied manually via Supabase SQL Editor during 3a.2 hardware verification. Committed to repo at `05d2cae` earlier in Session 5 Part 3a planning; prod application slipped — caught when item 5 of the 3a.2 verification gate failed with 404 on the missing `rpc_session_remove_participant`. This file's existence was triggered by that gap. |
| 017_set_my_participation_role.sql | ✅ | 2026-05-02 | Mike | Applied manually via Supabase SQL Editor 2026-05-02 immediately after migration commit `8c83b35` landed. Verified via `SELECT proname, pg_get_function_arguments(oid) FROM pg_proc WHERE proname = 'rpc_session_set_my_participation_role'` returning the function with args `(p_session_id uuid, p_role text)`. |
| 018_session_start_active_default.sql | ✅ | 2026-05-02 | Mike | Applied manually via Supabase SQL Editor 2026-05-02 alongside the v2.105 doJoin restructure (same commit). Verified via `SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = 'rpc_session_start';` returning the function with the new `case when p_app = 'games' then 'active' else 'audience' end` branched insert; comment also confirmed updated. Per `docs/GAMES-CONTROL-MODEL.md` § 2.4.4 for games branch; karaoke schema-state semantics preserved per `docs/KARAOKE-CONTROL-MODEL.md` § 1. |
| 019_trivia_premium_usage.sql | ✅ | 2026-05-04 | Mike | Applied manually via Supabase SQL Editor 2026-05-04 immediately after Phase 2 Commit A (`c4af15c`) landed. Verified via three queries: (1) `SELECT EXISTS (...) WHERE table_name = 'trivia_premium_usage'` returned `t`; (2) `SELECT tablename, rowsecurity FROM pg_tables WHERE tablename = 'trivia_premium_usage'` returned `t` (RLS enabled); (3) `SELECT COUNT(*) FROM pg_policies WHERE tablename = 'trivia_premium_usage'` returned `0` (no policies — service-role bypass is the only access path, browser denied entirely). Trivia Phase 2 generate-trivia Edge Function unblocked for deploy. |
| 020_admission_model_v2.sql | ✅ | 2026-05-15 | Mike | Applied manually via Supabase SQL Editor 2026-05-15 after migration commit `80a141b` landed. Implements W1 from `docs/ADMISSION-MODEL-V2.md` § 10. All 7 post-migration verification queries (per the file footer) passed: (1) `SELECT DISTINCT admission_mode FROM sessions` returned only NULL — old values transitioned out, W2 will re-stamp `'open'`/`'gated'` at game-start; (2) `SELECT DISTINCT participation_role FROM session_participants` returned `active`/`audience`/`queued` (enum preserved); (3) `SELECT COUNT(*) FROM session_participants WHERE participation_role = 'queued' AND wanting_since IS NULL` returned `0` (backfill applied); (4) `\d session_participants` confirmed `wanting_since timestamp with time zone` column added; (5) `\d sessions` confirmed `admission_mode` is nullable; (6) `\d sessions` confirmed new `sessions_admission_mode_check` CHECK constraint allows `NULL OR ('open','gated')`; (7) `\d session_participants` confirmed `queue_position` column + `session_participants_queue_idx` partial unique index both still present (karaoke dependencies untouched per § 2.7). W2-W10 client code changes pending. |
| 021_session_set_admission_mode.sql | ✅ | 2026-05-15 | Mike | Applied manually via Supabase SQL Editor 2026-05-15 after migration commit `103b507` landed. Implements W2 from `docs/ADMISSION-MODEL-V2.md` § 10. New manager-only SECURITY DEFINER RPC `rpc_session_set_admission_mode(p_session_id, p_admission_mode, p_capacity)` for stamping admission_mode + capacity onto the sessions row at game-start (and clearing on Switch Game). Verified via three queries: (1) `SELECT proname FROM pg_proc WHERE proname = 'rpc_session_set_admission_mode'` returned 1 row (function exists); (2) `SELECT proargnames FROM pg_proc WHERE proname = 'rpc_session_set_admission_mode'` returned `{p_session_id, p_admission_mode, p_capacity}` (signature matches spec); (3) `SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = 'rpc_session_set_admission_mode'` returned the full function body including `SECURITY DEFINER`, `SET search_path = public`, all three error paths (42501 non-manager, 02000 missing/ended session, 22023 invalid admission_mode value), and the UPDATE that bumps `last_activity_at`. Validates against `sessions_admission_mode_check` value set (NULL/'open'/'gated'). Called from `games/player.html`'s `managerStartTrivia` / `managerStartLastCard` / `managerStartEuchre` / `managerSwitchGame` (W2 client-side wiring shipped in commit `103b507` alongside the migration file). |
| 022_session_update_participant_wanting_since.sql | ⏳ Drafted, not yet applied | — | — | Part of W4 from `docs/ADMISSION-MODEL-V2.md` § 10. `CREATE OR REPLACE FUNCTION` on `rpc_session_update_participant` (originally db/011) to populate the `wanting_since` column added by db/020. Adds parallel handling to existing `queue_position` logic: set `wanting_since = now()` on transition INTO `'queued'` from a non-queued source; clear to `NULL` on transition OUT of `'queued'`; preserve on same-role calls. All other behavior (manager/host/self transition rules, capacity check, queue_position auto-assignment, pre_selections, control_role gates) preserved identically. Apply after review; verification queries in the migration file footer test all three transition paths (audience→queued sets wanting_since, queued→audience clears it, same-role preserves it). |
| 023_session_get_participants_wanting_since.sql | ⏳ Drafted, not yet applied | — | — | Part of W4 from `docs/ADMISSION-MODEL-V2.md` § 10. `DROP FUNCTION IF EXISTS` + `CREATE FUNCTION` on `rpc_session_get_participants` (originally db/013) to add `wanting_since` to the `RETURNS TABLE` column list and underlying SELECT. DROP+CREATE required because Postgres `CREATE OR REPLACE FUNCTION` cannot change the return-type signature (including RETURNS TABLE column list); wrapped in `BEGIN/COMMIT` so concurrent callers see an atomic swap. Server-side `ORDER BY` unchanged — karaoke continues to use `queue_position` ordering; games-side client code sorts the queued bucket by `wanting_since` in `renderRoster` (W4 3C work). Apply after review; verification queries confirm the column is surfaced in `RETURNS TABLE` and the function executes against a live session. |

## How to update

When applying a new migration to production:

1. Apply via Supabase SQL Editor (or `supabase db push` if/when CLI workflow lands).
2. Append a new row to the table above with `✅`, today's date (YYYY-MM-DD), the applier name, and any notes (e.g., commit hash where the file shipped to repo, or non-obvious context like "applied during incident response").
3. Commit the update alongside any session-log entry that claims the migration shipped. The two commits should not be temporally separated.

## How to verify a `❓ Verify` row

Run a check before relying on the migration's contents:

- **Functions:** `SELECT proname FROM pg_proc WHERE proname = 'rpc_xxx';` — empty result means not applied.
- **Tables/columns:** `\d+ table_name` in psql, or query `information_schema.columns WHERE table_name = 'xxx'`.
- **Triggers:** `SELECT tgname FROM pg_trigger WHERE tgname = 'xxx';`
- **Policies:** `SELECT polname FROM pg_policy WHERE polrelid = 'public.table_name'::regclass;`

If confirmed applied, update the row to `✅` with the verification date in Notes (e.g., "Verified live in pg_trigger 2026-05-15"). If confirmed missing, apply the migration and update the row.

## Why this exists

The Session 5 Part 3a.2 hardware verification on 2026-05-02 surfaced that `db/016_remove_participant.sql` had been committed to the repo at `05d2cae` and the closing log claimed it had shipped, but it had never actually been applied to production Supabase. The miss caused gate item 5 (Remove Player UI) to fail with a 404 on the missing RPC. Migration was applied manually mid-session.

This was the second instance of a migration committed-but-not-applied slipping through (the first was earlier in Session 5 but undocumented). Without tracking, a third slip is inevitable. This file is the cheapest viable mitigation; upgrade to a `pg_proc`-diff script or Supabase CLI workflow if checklist discipline doesn't hold.

See `docs/DEFERRED.md` "No tracking of which db/*.sql migrations have been applied to production" for the full bug entry.
