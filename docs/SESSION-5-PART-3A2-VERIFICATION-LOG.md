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

---

## Addendum — Active/audience UX cluster work (2026-05-02)

After 3a.2 closeout, the active/audience UX cluster started shipping per the bugs filed above. Two of three commits landed in the same session, with hardware verification of the second commit incomplete.

| # | Commit | Description |
|---|---|---|
| Spec | `410ccc1` | `GAMES-CONTROL-MODEL.md` § 2.4 cluster (§ 2.4.1–§ 2.4.6 NEW) + § 1 audience definition extended for lobby-state opt-out path. Three coupled DEFERRED entries (default role, participant toggle, manager visibility) unblocked. |
| Migrations tracker | `97f1e83` | `db/MIGRATIONS_APPLIED.md` checklist + CLAUDE.md doctrine ("a migration committed to repo is NOT shipped until applied to prod"). 16 existing migrations enumerated; db/015 ❓ Verify pending. |
| 1 (cluster) | `8c83b35` | `db/017_set_my_participation_role.sql` migration (self-only RPC for participant active↔audience flip). |
| 1a (apply gate) | `b1a8e4a` | db/017 applied to prod via Supabase SQL Editor; `MIGRATIONS_APPLIED.md` row 017 flipped from `❌ Pending` to `✅`. Verified via `pg_proc` query. |
| 2 (cluster) | `754d0a8` (v2.104) | `doJoin` defaults new participants to `'active'` not `'audience'` per § 2.4.4. Caller-side fix only — RPC default in db/009 unchanged to avoid karaoke-side effects. |
| 3 (cluster) | (pending) | Participant "I'm playing in this game" toggle UI (per § 2.4.3, calls `rpc_session_set_my_participation_role`) + lobby roster sectioning into PLAYING (N) / WATCHING (M) headers (per § 2.4.5). Single commit, version bump v2.104 → v2.105. |

### v2.104 hardware verification — INCOMPLETE

Verification of the default-role fix hit a snag: Michael's `session_participants` rows from earlier `'audience'`-default joins persisted across test runs and appear to interfere with fresh `doJoin` re-testing. The exact failure mode wasn't fully diagnosed within the session — possible causes:

- Stale rows confusing `currentParticipants` derivation (manager's roster shows ghost active participant from a prior test run).
- `rpc_session_join` 23505 (already-a-participant) catch path bypassing the new `'active'` default and reusing the prior `'audience'` row state — meaning the v2.104 caller-side override doesn't actually take effect on a returning user without a fresh row.
- Realtime sub state from a prior test bleeding into the new test (channel reuse, stale subscription handlers).

The third possibility is least likely (page reload tears down sub state). The second is most plausible — and if confirmed, it indicates v2.104 alone may not be sufficient; the 23505 catch path may need its own remediation (e.g., update the existing row's `participation_role` to `'active'` on re-join when the prior row's role was `'audience'`).

### Remediation steps for next-session verification

To re-establish a clean test environment for v2.104 verification:

**Option A (cleanest):** SQL Editor cleanup before testing.
```sql
-- Mark all prior session_participants rows for the test user as left.
UPDATE session_participants
SET left_at = now()
WHERE user_id = '<michael-user-id>'
  AND left_at IS NULL;
```
Then end the active session via the End Session button (or `UPDATE sessions SET ended_at = now() WHERE id = '<session-id>';`), then start a fresh session.

**Option B:** Use a third test account that has zero rows in `session_participants` for the target session. Simplest if available.

**Option C (if 23505 path is the cause):** Investigate the 23505 catch in `games/player.html` `doJoin`. If a returning user with a previously-`'audience'` row hits the catch and never re-runs the role assignment, the v2.104 caller-side override is functionally a no-op for them. Fix-forward would update the existing row's role to `'active'` on the catch path — but only if the test environment confirms this is the failure mode.

### Expected behavior once test environment is clean

1. Mike (manager) creates session via Games tile.
2. Michael (non-manager) joins via room code on v2.104.
3. DB query confirms: Michael's row has `participation_role = 'active'` and `left_at IS NULL`.
4. Mike's iPhone roster shows Michael as a normal active participant (flat roster until Commit 3 ships the section split).
5. Mike's console shows `participant_role_changed` realtime broadcast received.

If verification is green, proceed with Commit 3 of the cluster. If red (e.g., 23505 catch path is the failure mode), fix-forward before Commit 3.

### Cluster status snapshot (end of 2026-05-02 session)

- Spec: ✅ shipped, applied to docs.
- Migration: ✅ shipped, applied to prod.
- Commit 2 (default-role): ✅ shipped, hardware verification pending.
- Commit 3 (toggle UI + roster split): ⏳ pending v2.104 verification.
