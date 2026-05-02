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
| 015_promotion_push_trigger.sql | ❓ Verify | (Session 5 Part 2e.2?) | (TBD) | Application history unclear (per Mike, 2026-05-02). Production push trigger appears functional (queued→active fires push successfully end-to-end at v2.110), implying APPLIED — but no explicit confirmation in shipping logs. Confirm by querying `pg_trigger` for the trigger name in db/015's body before next migration ships, then update this row. |
| 016_remove_participant.sql | ✅ | 2026-05-02 | Mike | Applied manually via Supabase SQL Editor during 3a.2 hardware verification. Committed to repo at `05d2cae` earlier in Session 5 Part 3a planning; prod application slipped — caught when item 5 of the 3a.2 verification gate failed with 404 on the missing `rpc_session_remove_participant`. This file's existence was triggered by that gap. |
| 017_set_my_participation_role.sql | ✅ | 2026-05-02 | Mike | Applied manually via Supabase SQL Editor 2026-05-02 immediately after migration commit `8c83b35` landed. Verified via `SELECT proname, pg_get_function_arguments(oid) FROM pg_proc WHERE proname = 'rpc_session_set_my_participation_role'` returning the function with args `(p_session_id uuid, p_role text)`. |

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
