# Session 5 Part 2 Closing Log

**Created:** 2026-04-30
**Scope:** Closing log for Session 5 Part 2 (Karaoke integration). Captures shipped state, deferred items, open backlog, and verification status across 2a-2f sub-parts.

## Sub-part status

| Sub-part | Status | Reference |
|---|---|---|
| 2a | ✓ Shipped | commit `d1b4edd` |
| 2b | ✓ Shipped | commit `601d125` |
| 2c.1 | ✓ Shipped | commit `daa8718` |
| 2c.2 | ✓ Shipped | commit `0a3a9ea` |
| 2c.3.1 | ✓ Shipped | commit `e4a348e` |
| 2c.3.2 | ✓ Shipped | commit `5617689` |
| 2d.0 | ✓ Shipped | `db/013` migration |
| 2d.1 | ✓ Shipped | (multiple commits) |
| 2e.0 | ✓ Shipped | push notification infrastructure |
| 2e.1 | ✓ Shipped | read-only role-aware UI |
| 2e.2 | ✓ Shipped | self write actions; v2.110 |
| 2e.3.1 | ✓ Shipped | manager queue UI; v2.111-v2.116 |
| 2e.3.2 §1 | ✓ Shipped | Agora silent-host foundation; v2.117 |
| 2e.3.2 §2 | ✓ Shipped | Manager Override commands; v2.120 (commit `af1e468`) |
| 2f | Deferred | No-op under audience.html no-investment rule |

## Bugs surfaced and shipped during 2e.3.1 / 2e.3.2

| Bug | Description | Status |
|---|---|---|
| BUG-10 | Realtime publish subscribe-handshake race on Capacitor iOS | Fixed v2.118 (commit `1b870d3`) |
| BUG-13 | Manager actions don't refresh originating device UI (Realtime self:false) | Fixed v2.119 (commit `ad97ea5`) |
| BUG-3 | LOG button visually overlaps screen-manage-queue back button | Fixed v2.119 |
| BUG-7 | Toast messages truncate at viewport edge | Fixed v2.119 |
| BUG-5 | Web sign-up redirect regression | Fixed (commit `ce36fe5`) |

## Open bugs (not blocking, deferred to next session or backlog)

- **BUG-4:** Sign-in shows "Signups not allowed for otp" for unregistered email. UX papercut on auth path.
- **BUG-6:** singer.html silently degrades to legacy mode for non-HHU users. Should redirect to audience.html.
- **BUG-8:** Laptop singer.html shows wrong role state.
- **BUG-12:** Proximity prompt unresponsive on iPhone.
- **BUG-14:** "You can sing — pick a song" banner copy on screen-home reads as "you're singing now" to fresh users in Available Singer state.

## Known limitations (accepted, deferred to consolidation work)

- NHHU pill gap on audience.html — see DEFERRED.md entry "NHHU pill gap on audience.html (known limitation under no-investment rule)".

## What's deferred to next session

- Multi-device hardware verification of 2e.3 (manager queue + Manager Override commands) with TV running stage.html.
- Triage and address open bugs above.
- Begin Session 5 Part 3 (Games) — apply session_participants + realtime patterns to `games/tv.html` + `games/player.html`.

## Doctrine updates this session

- audience.html freeze tightened from "bug fixes only" to "regression fixes only" (no investment, defer all features and fixes other than restoring functionality that broke). Updated in `docs/KARAOKE-CONTROL-MODEL.md` § 4.3 + § 5.5, `docs/SESSION-5-PART-2-BREAKDOWN.md` § 2f, `docs/DEFERRED.md`, and `CLAUDE.md` doctrine section.

## Verification status

**Static-verified on iPhone:**
- 2e.3.1 manager queue UI (full reorder/promote/skip flow)
- 2e.3.2 §2 all 6 manager override buttons fire correct payloads

**NOT YET verified end-to-end with TV:**
- Stage.html receives and acts on §2 override commands (pause/resume/restart/end-song/clear-costume/comments-toggle)
- Multi-device propagation (laptop singer + iPhone manager + TV)

Folds into next-session hardware verification pass.
