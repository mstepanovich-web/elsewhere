# Session 5 Part 3a.2 Hardware Verification Log

**Date:** 2026-05-02
**Pre-verification commit:** `8bff27b` (v2.101)
**Post-verification commits:**
  - `b5e1af2` (v2.102) — fix-forward for End Session realtime
  - `7dde17c` (v2.103) — fix-forward for doJoin propagation

## Summary

3a.2 hardware verification gate (6 items per `docs/SESSION-5-PART-3-CLOSING-LOG.md`) executed against iPhone Safari + laptop Chrome with two signed-in real Supabase auth users (Mike, Michael) sharing a household. Verification surfaced two fix-forward bugs that shipped during the session, plus a missing prod migration that was applied manually. Eight additional bugs or spec gaps were filed to `docs/DEFERRED.md`.

## Gate item results

| # | Item | Status | Notes |
|---|---|---|---|
| 1 | Manager bar UI | ✅ | All buttons gated correctly on `control_role === 'manager'`. Negative check on non-manager confirmed zero affordances visible. |
| 2 | End Session full flow | ✅ (post-v2.102) | Initially failed — non-manager stayed stuck on lobby. Diagnosed as BUG-10 redux (publishSessionEnded subscribe-handshake race). Fixed in commit `b5e1af2`. Re-verified green. |
| 3 | Manager-as-player toggle | ✅ | ON/OFF/ON cycle plus refresh persistence verified. `participant_role_changed` realtime confirmed working for non-manager subscribers. |
| 4 | Capacity-fail toast | 🟡 Verification gap | Cannot test functionally with only 2 real auth users; schema correctly prevents phantom-active duplicates via partial unique index. Functional code path verified by code review only. Defer until invite flow ships or unit-test infrastructure exists. |
| 5 | Remove Player UI | ✅ (post-db/016 + v2.103) | Initial test failed with 404 on `rpc_session_remove_participant`. `db/016_remove_participant.sql` had been committed at `05d2cae` but never applied to prod. Migration applied manually mid-session. Item retest passed. Re-verified again on v2.103 to confirm no regression from doJoin fix. |
| 6 | Pre-3a UX preserved | 🟡 Refactor verified, gameplay smoke blocked | Refactor itself is clean: `currentParticipants` exists and populated, `lobbyPlayers` undefined (legacy var fully removed), start-game gate reads `currentParticipants` correctly. Gameplay smoke test blocked by missing participant-side toggle (filed as bug "No participant-side I'm playing toggle") — couldn't get both Mike and Michael to active state without direct DB updates that don't fire realtime. Refactor verification is the actual 3a.2 acceptance criterion; gameplay smoke is downstream of unrelated feature gap. |

## Net assessment

3a.2 verified green on all four items where verification was achievable in the test environment. Items 4 and 6 are partial for documented environmental and feature-gap reasons — neither is a regression in the rewrite.

3a refactor itself confirmed clean:
- `?mgr=1` URL parameter retired
- `isManager` boolean replaced by `control_role` lookup
- `lobbyPlayers[]` array retired in favor of `currentParticipants[]`
- engine modules deleted
- Remove Player UI shipped end-to-end (post-migration apply)
- Manager-as-player toggle preserved and working
- All gate UI affordances correctly gated on `session_participants`

Ready to begin 3b (Trivia integration per `docs/GAMES-CONTROL-MODEL.md` § 4.1) once the active/audience UX cluster ships (bugs filed in DEFERRED.md).

## Bugs surfaced

11 bugs surfaced during this verification session:
- 3 resolved during the session (filed in DEFERRED.md "Completed items" with commit refs)
- 8 filed to DEFERRED.md as deferred entries

See `docs/DEFERRED.md` for full bug entries with priority, area, context, and pickup notes.

## Migrations applied

- `db/016_remove_participant.sql` applied manually 2026-05-02 via Supabase SQL Editor

## Operational note

Discovered second instance of a migration committed-but-not-applied slipping through. Filed as bug "No tracking of which db/*.sql migrations have been applied to production" in DEFERRED.md. Recommend prioritizing this fix before db/017 ships (active/audience cluster).
