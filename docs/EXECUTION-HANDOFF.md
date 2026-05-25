# Elsewhere — Execution Handoff Brief

**Purpose:** This document, together with the five unified-app planning
docs, is the kickoff for any new chat continuing the unified-app
execution work. Read this FIRST, then the planning docs.

**Last updated:** 2026-05-23 (immersive-control + regular-user model documentation pass complete — see ROOM-AUTHORITY-MODEL.md / HOUSEHOLD-DEVICE-PRESENCE-MODEL.md / ROOM-SESSION-MODEL.md; §4 now points at §F shell-rework IMPLEMENTATION — the §F pre-write investigation already ran this session and is recorded inline)

---

## 1. The three environments — read this before anything else

Work on this project happens across THREE environments. They are NOT
interchangeable. Most handoff failures come from forgetting this.

- **The planning chat** (a regular claude.ai chat — likely the one
  reading this now). Has the project context. Writes tasks, reviews
  results, makes decisions. **CANNOT read or edit the repo.** It only
  sees what is pasted into it.
- **Claude Code** (a terminal tool running in the repo). CAN read every
  file, run git, edit code. It executes tasks. It does not drive the
  project — it does what each task says.
- **The human.** Carries tasks from the planning chat to Claude Code, and
  carries Claude Code's results back to the planning chat.

**The working loop, every time:** planning chat writes a task → human
pastes it into Claude Code → Claude Code does the repo work and reports →
human pastes the result back to the planning chat → planning chat reviews
it with the human. Pushes are deliberate gates the human approves.

**The rule that prevents the most common failure:** any task that needs
to READ or EDIT the repo MUST go to Claude Code. Never write a
"check against the actual repo" or "edit file X" task for the planning
chat — the planning chat physically cannot do it and will get stuck
asking for files. If you are the planning chat and you are about to write
a task, the first question is always: WHO RECEIVES THIS — Claude Code, or
the human directly? Write accordingly.

The five planning docs are committed in the repo, so Claude Code can read
them itself. They do not need to be pasted into Claude Code.

## 2. Where the project is

The unified-app / NHHU-primary refactor. Goal: every registered user is a
first-class user of every app at a baseline tier with no TV device
required; an embed-capable TV device adds an immersive capability layer.
This refactors KARAOKE and GAMES; Wellness and Worlds are greenfield.

**Documentation phase: COMPLETE.** Five planning docs written, reviewed,
committed. Every superseded doc carries a supersession pointer. CONTEXT.md
(the general kickoff doc), INFRA.md, and CLAUDE.md were all revised to
match. No doc contains a known-false statement.

**Phase-1 execution-scope investigation: COMPLETE.** Its adopted output is
`docs/PHASE-1-BUILD-SPEC.md` (initial commit `caf647e`, amended by
`fcc42f6` for three cross-cutting pinned decisions + an S6 current-state
correction). The six open questions surfaced in §H are now closed.

**Phase-1 RPC migration: COMPLETE.** All four database migrations
are applied to prod and recorded in `db/MIGRATIONS_APPLIED.md`. The
room-keyed RPC surface (the 14 RPCs plus new `rpc_room_create`) is
the canonical implementation in prod as of 2026-05-22.

- **db/025** (schema cutover — rooms entity + session/participant
  re-anchor): committed `dddbeb6`, applied 2026-05-21.
- **db/026** (RPC batch 1 — 8 mechanical re-points + rpc_session_end
  + rpc_session_set_admission_mode): committed `9e3926e`, applied
  2026-05-22.
- **db/027** (RPC batch 2 — rpc_session_start split + new
  rpc_room_create per OQ2 (a)): committed `2465ff5`, applied
  2026-05-22.
- **db/028** (RPC batch 3 — rpc_session_leave with four-tier
  host-first succession + new `p_successor_user_id` parameter, plus
  rpc_session_reclaim_manager and rpc_session_admin_reclaim):
  committed `95dcf70`, applied 2026-05-22.
- **Forward-correction commit `c657c9f`** added `DROP FUNCTION IF
  EXISTS` statements ahead of each CREATE on the 11 renamed/re-typed
  functions across db/026/027/028. The originals used `CREATE OR
  REPLACE FUNCTION` for parameter renames and return-type changes,
  which Postgres rejects with `42P13`; without `c657c9f`, none of
  the three RPC migrations could apply. The fix landed mid-apply
  and the three migrations then applied cleanly.

Verified-live structural guarantees from the post-migration checks:
`rpc_room_create` is the sole writer of `rooms.owner_user_id`
(immutable post-creation per OQ2 (a)); `rpc_session_leave`'s tier-4
branch is the first and only writer of `rooms.ended_at` in the
system.

**Phase-1 post-work: COMPLETE.** Three additional database migrations
and the §F shell session-state cluster rework shipped 2026-05-22 →
2026-05-23 to close Phase-1's downstream gaps:

- **db/029** (`fire_promotion_push` trigger recreation with
  room-keyed payload, replacing the trigger dropped by db/025):
  committed `b0f8a47`, applied 2026-05-23. Push notification
  DELIVERY restored end-to-end.
- **db/030** (`tv_devices.can_embed` column — schema half of the
  immersive-control-layer activation predicate; self-report writer
  deferred per DEFERRED.md): committed `2ca15a8`, applied
  2026-05-23.
- **db/031** (new `rpc_room_seize` ownership-seize RPC per
  ROOM-AUTHORITY-MODEL.md "Seize authority"; functionally usable
  in prod only after the can_embed self-report writer lands):
  committed `b654f91`, applied 2026-05-23.
- **§F shell session-state cluster rework**: the ~13-site
  client-side migration enumerated in `docs/PHASE-1-BUILD-SPEC.md`
  §F. Nested `{ session, room }` cache reshape (`d790703`) + RPC
  call-site re-points (`c270800`) + version bump v2.138
  (`58b36c3`). The shell now reads the room-keyed RPC surface.
- **Phase-1.1 cleanup, iOS notification-payload audit, C2
  shell-half realtime publisher payload rename, UNIFIED-APP-PLAN
  §10 tile-badge spec**: all shipped 2026-05-23; see §4 for
  per-item commits and detail.

Phase 1 is closed. iOS bundle is current through `bf45b2c` (this
session's close).

The current immediate next step is named in §4.

## 3. The five planning docs — the design

All in docs/. Read all five after this brief:
- `UNIFIED-APP-PLAN.md` — umbrella: capability model, the six locked
  decisions, four-quadrant per-app breakdown, phase sequencing, open
  items (§8).
- `ROOM-SESSION-MODEL.md` — entity model: durable `rooms` + disposable
  per-app `sessions`; `session_participants` re-anchored to `room_id`.
- `ROOM-AUTHORITY-MODEL.md` — manager authority splits into room control
  (transferable) and room ownership (never transfers by succession);
  succession picks the longest continuously-present non-audience
  participant.
- `ROOM-ACCESS-INVITE-MODEL.md` — token-based invites on the dormant
  `invites` table; new Edge Function to resolve tokens.
- `HOUSEHOLD-DEVICE-PRESENCE-MODEL.md` — households, binding, presence,
  immersive-embedding rule. Supersedes PHONE-AND-TV-STATE-MODEL.md.

## 4. The immediate next step

**Phase-1 close is complete.** Everything §4 previously named as upcoming has shipped this session. Specifically:

**§F shell session-state cluster rework — complete.** The ~13-site client-side migration enumerated in `docs/PHASE-1-BUILD-SPEC.md` §F shipped across three commits: Part 2 nested-cache reshape (`d790703`), Part 1 RPC call-site re-point (`c270800`), version bump to v2.138 (`58b36c3`). The shell now reads the nested `{ session, room }` cache populated from db/025-028's room-keyed RPCs. All four shell call sites for `rpc_session_start`, `rpc_session_leave`, `rpc_session_reclaim_manager`, and `rpc_session_admin_reclaim` are on the new room-keyed signatures.

**Phase-1 post-work 8-item sequence — complete:**

1. **iOS bundle sync** — `~/sync-app.sh` + `npx cap sync ios` run this session; bundle captures through commit `bf45b2c`. See "Bundle hygiene" below.
2. **Phase-1.1 dead-code cleanup** — `generateRoomCode()` removed from `index.html` (commit `daeff0b`). The `is_session_*` compat-wrapper drop was deferred (DEFERRED.md entry retained — pending zero-caller grep confirmation).
3. **iOS notification-payload audit** — confirmed the iOS app reads nothing from `notif.data` today; field-name choice is moot for the app, `room_id` chosen for future-proofing. Recorded in DEFERRED.md (commit `5eb8258`).
4. **C3 — `fire_promotion_push` trigger recreation.** db/029 written and applied to prod 2026-05-23 (commits `b0f8a47` migration, `89a629e` bookkeeping). Push DELIVERY restored; tap-routing remains unbuilt (separate active DEFERRED entry).
5. **C1 — `tv_devices.can_embed` column (schema half).** db/030 written and applied to prod 2026-05-23 (commits `2ca15a8` migration, `fd553ac` bookkeeping). C1 re-scoped to self-report-path-only; that half remains active.
6. **C5 — `rpc_room_seize` ownership-seize RPC.** db/031 written and applied to prod 2026-05-23 (commits `b654f91` migration, `cbd2783` bookkeeping). RPC SHIPPED and correct; refuses every seize attempt in prod until a `tv_devices.can_embed = true` row exists (i.e., until C1's self-report half lands).
7. **C2 shell-half — realtime publisher payload rename.** The 4 shell publisher call sites in `index.html` renamed (`session_id` → `room_id`; `manager_user_id` → `controller_user_id` at the one `publishSessionStarted` caller); `shell/realtime.js` doc-comments updated to match (commit `a5ed589`). The 18 surface call sites ride Phase 3/4 surface migration (separate active DEFERRED entry).
8. **Tile-badge spec — UNIFIED-APP-PLAN §10.** Per-user per-app shell tile-state spec written, with signal vocabulary (4 signals), data sources, precedence, and phase-buildability table. `docs/PHONE-AND-TV-STATE-MODEL.md`'s tile-state section marked superseded (commit `bf45b2c`).

**Push + prod state.** 10 commits pushed this session; `origin/main` at `bf45b2c`. db/029, db/030, db/031 all applied to prod via Supabase SQL Editor and recorded in `db/MIGRATIONS_APPLIED.md`.

**Bundle hygiene.** iOS bundle is current through `bf45b2c` as of this session's close. `~/sync-app.sh` + `npx cap sync ios` was re-run this session after the 10-commit push; the sync output confirmed `index.html` and `shell/realtime.js` (the C2 shell-half rename in `a5ed589`) copied into `ios/App/App/public/`. The only outstanding iOS step is an Xcode rebuild + install on the test device before any iOS-side verification of the C2 rename — that's the normal deferred-rebuild step, not a missing sync. No functional regression expected from C2 (zero subscriber dependence on the renamed fields).

**The immediate next step is Phase 2 per `docs/UNIFIED-APP-PLAN.md` §5: venue extraction.** Pull venue rendering out of the karaoke stage into a shared shell renderer; make the venue registry cross-app. The three-part work breakdown already exists in `docs/DEFERRED.md` entry "Venues as cross-app service (games, wellness, future apps)" (filed 2026-04-23; cross-referenced by `docs/ROADMAP.md`):

1. Extract 360° panorama rendering from `karaoke/stage.html` into `shell/venue-renderer.js` (or similar). Three.js setup, texture loading, transition UX. Keep karaoke's ambient effects separate (that's a separate DEFERRED "shell/venue-effects.js" entry from PHASE1-NOTES).
2. Games integration: each game's blockade image becomes a venue entry in `venues.json` with product tag `'games'`. Session-wide venue selection (manager/host picks one venue for the whole game). Games pages consume the shared renderer.
3. Phase-2 follow-up (per the DEFERRED entry): DeepAR camera insertion for player/participant presence in games — the same technique karaoke uses for singers.

Trigger per the DEFERRED entry: either wellness app start, OR games visual parity priority. The entry's "When to pick this up" note suggests bundling with wellness; standalone is also clean if games visual parity becomes urgent first. Phase 2 "can overlap Phase 1" per §5; with Phase 1 complete, Phase 2 starts unblocked.

**Still-active downstream items — tracked in `docs/DEFERRED.md`, NOT blocking Phase 2:**

- **C1 self-report half** — `tv_devices.can_embed` schema is in place; the writer (camera + compositing-pipeline detection in `tv2.html` + claim flow + claim-RPC update) is not built. Until it lands, every row reads `can_embed = false` and C5's ownership-seize RPC refuses every attempt. Blocked on the compositing pipeline not yet existing as code.
- **C2 surface-side completion** — 18 publisher call sites in `karaoke/singer.html` (×7), `karaoke/stage.html` (×2), and `games/player.html` (×9) still send pre-rename `session_id`. Rides Phase 3/4 surface migration. Pair with the schema-stale-SELECT cleanup below.
- **Schema-stale `sessions` SELECTs on the four pre-Phase-3 surfaces** — 7 sites across singer/stage/player/games-tv reference columns (`manager_user_id`, `room_code`, `tv_device_id`) that db/025 dropped. Would 400 against prod if exercised; not surfaced as a live regression because the surface flows haven't been exercised since db/025 applied 2026-05-21. Must land before any user-facing test of those flows.
- **C4 — HH-admin administrative actions without engagement transition** — future enhancement; current uniform-engagement behavior is correct for the primary use case.

Other open items recorded in `docs/DEFERRED.md` (latent realtime contract drift, dead `publishManagerChanged`, unbuilt push-tap-routing, the `is_session_*` compat-wrapper drop, the low-prominence room-code-entry UI affordance, etc.) are individually tracked there. None blocks Phase 2.

**§2 also refreshed this commit.** Per §6's "update section 2 and section 4 at end of each execution session" instruction, §2's stale db-migration enumeration (which previously stopped at db/028) is brought current to db/031 in this same commit, and §2's now-obsolete "next step is the §F rework" line is rewritten to point at §4 generically. Both §2 and §4 reflect this session's close.

## 5. Review discipline

Propose-then-review. Claude Code proposes diffs or specs; the human and
planning chat review before anything is committed. Commits and pushes are
separate gates. Migration code is never written before its build spec is
reviewed.

## 6. Maintaining this brief

Update section 2 and section 4 at the end of each execution session, so
this brief is always a current snapshot of where the project is and what
the next step is — the same way CONTEXT.md is maintained.
