# Session 5 Part 3c Closing Log

**Created:** 2026-05-19
**Scope:** `admission_model_v2` §10 work-packages W7-W10, shipped across 2026-05-18 → 2026-05-19. 18 commits, 16 version stamps (`games/player.html` v2.121 → v2.137; `games/tv.html` → v2.101), 1 DB migration (`db/024`) applied to prod.

`admission_model_v2` (canonical design: `docs/ADMISSION-MODEL-V2.md`) restructured games admission into a two-mode model (open / gated), a three-role model (active / queued / audience), and `screen-game-room` as the single shared pre-game surface. Its §10 enumerates the implementation as ten work-packages, W1-W10. Per §9.6, this **supersedes** the older `docs/GAMES-CONTROL-MODEL.md` §4.1 per-game "3b / 3c / 3d" breakdown — games integration is now cross-cutting work-packages, not per-game tracks.

This log is **Part 3c** in the Session 5 Part 3 progression: 3a shipped the session/participants plumbing + manager controls; 3b shipped Trivia productionization + Phase 2 (`docs/SESSION-5-PART-3B-CLOSING-LOG.md`); 3c is the `admission_model_v2` implementation. It covers **W7-W10 only** — see "Pre-existing gaps" for W1-W6.

## Pre-existing gaps

W1-W6 (schema migration, per-game manifest + admission stamping, dispatcher refactor, game-room updates, score-screen Play Again, Manager Select Players surface) shipped before this session and were **never given a closing log**. They are referenced only in `docs/ADMISSION-MODEL-V2.md` §10 and inline in their own commit bodies — the W7 commit cites W6 as `cef155c` v2.121, which fixes the lower bound. Reconstruct from `git log` + §10 if forensic detail is ever needed; this log does not attempt it.

## Sub-part status

| Work-package | Status | Commits | Version arc |
|---|---|---|---|
| W7 — `managerNextRound` refactor | ✓ Shipped (resolved to a deletion) | `68e8ee9` | v2.122 |
| W8 — Pause + Leave UI | ✓ Shipped; **scope expanded** vs §10 | `b6898ea` → `2432d86` (9 commits) | v2.123 → v2.131 |
| W9 — implicit-leave detection | ✓ Shipped; **heartbeat-only** vs §10 | `02cdc08`, `a1273df`, `5c1f97f`, `6b12290` | db/024 + v2.132 → v2.133 |
| W10 — issue fixes + polish + W5 sweep | ✓ Shipped; **≠ §10 "W10 Cleanup"** | `014c738` → `a7dd71a` (4 commits) | v2.134 → v2.137 (+ tv v2.101) |

## What W7 delivered

**`68e8ee9` (v2.122) — `managerNextRound` deletion.** §10 framed W7 as a refactor of `managerNextRound` (drop the `s.players` freeze, re-read active participants per round, integrate with the W6 Select Players output). In practice the function was vestigial: the Last Card "Next Round →" path (`#mgr-next` rewired in the round-end render) was a leftover from an earlier multi-hand Last Card design that never shipped user-visible, and W6 (`cef155c` v2.121) had already replaced the post-game flow with End Game → Game Over → single Play Again. So W7 resolved to a **deletion**, not a refactor — removed the round-end manager-button rewire and the `managerNextRound` function; preserved the dual-purpose `#mgr-next` button + `managerNext()` dispatcher (still used by Trivia) and the Last Card winner toast/banner. The W7 commit also explicitly deferred the W5 dead-code sweep to W10 — the first written marker of that deferral.

## What W8 delivered

§10 scoped W8 as a single work-package — "Pause + Leave UI on game surfaces." It shipped as **9 commits** (`b6898ea` → `2432d86`); the Pause + Leave core is only part of what landed.

- **`b6898ea` W8a (v2.123)** — per-game action row scaffold (Pause / Leave / Cam / Add TV), retiring the vestigial Last Card `MODE: TV ON / NO TV` toggle. Pause/Leave were stubs at this point.
- **`4bec4e4` W8a-fix (v2.124)** — regression repair: W8a's deletion of `setupLastCardLayout()` collapsed the Last Card deck strip + others strip to hidden. Restored the `.visible` assignment in `startLastCard()`.
- **`2146047` W8b (v2.125)** — real Leave wiring. `no_impact` games (Trivia, Last Card) soft-leave to the `audience` role (leaver stays in the session); `terminates_game` (Euchre) hard-leaves via `rpc_session_leave` + a `game-over` broadcast with `reason: 'user_left'`. Added `pruneAbsentPlayersFromGameState()`.
- **`3808b49` W8c-1 (v2.126)** — three hardware-surfaced bug fixes (Trivia End Game button, "[name] left" toast, "N playing" count chip) + Your Turn relocation into `#lc-top-strip`.
- **`7ba885e` W8c-2 (v2.127)** — Trivia routing refactor: aligned Trivia's manager flow (info → game-room → Setup → Start Game) with Last Card / Euchre.
- **`c5a8c15` W8c-3 (v2.128)** — manager + player bar **singleton refactor**. The architectural keystone of W8: replaced the per-game action rows (built ad-hoc across W8a / c-1 / c-2) with two app-level singleton bars driven by `applyManagerBarContext()`. Not in §10's W8 text — done because the per-game fragmentation made every new affordance expensive.
- **`d324922` W8c-3-fix (v2.129)** — six polish fixes (redundant Game Room camera toggle removal, Trivia Setup back-nav, contrast calibration, Trivia Skip retirement).
- **`6fa8827` W8c-3-fix2 (v2.130)** — regression repair: `#screen-lastcard`'s historical `position:fixed; inset:0` overlaid the new singleton bars, ghosting them non-interactive. Dropped `position:fixed`.
- **`2432d86` W8c-4 (v2.131)** — Pause behavior, the §10 W8 core: Last Card `pause_skips_turn` (paused players skipped in `advance()`), Euchre `pause_freezes_game` (`.game-paused-modal` overlay + handler gating), Trivia `pause_not_applicable`.

**Deviation note.** W8 as scoped (§10) was Pause + Leave buttons; W8 as shipped also delivered the Trivia routing refactor and the singleton-bar architecture rework — both genuine improvements, both well beyond the §10 W8 bullet. Two of the nine commits (W8a-fix, W8c-3-fix2) were hardware-test regression repairs.

## What W9 delivered

W9 implemented implicit-leave detection — cleaning up participants who close their tab or lose network and would otherwise linger forever in `session_participants`, breaking player counts and turn rotation.

- **`02cdc08` db/024** — schema + RPC. `session_participants.last_seen_at timestamptz` + a partial index; `rpc_session_heartbeat(p_session_id)` bumps the caller's `last_seen_at` and prunes peers stale >60s (sets `left_at`), returning the prune count. Deliberate RPC-only design (no trigger) since the table is RPC-mutated only; the 60s threshold tolerates two missed 20s beats + grace.
- **`a1273df`** — db/024 verified on prod (project `gbrnuxyzrlzbybvcvyzm`); `db/MIGRATIONS_APPLIED.md` flipped to ✅. Static schema checks + a manual back-date prune smoke test + the 42501 auth-gate rejection all passed.
- **`5c1f97f` W9 (v2.132)** — client wiring. Bundled the heartbeat RPC into the existing 20s Agora keepalive tick (zero new timer). On prune count > 0, fires `publishParticipantRoleChanged` so peers refresh.
- **`6b12290` W9-fix (v2.133)** — self-refresh after prune. W9 published to peers but not to the originating manager (BUG-13: Realtime doesn't echo to the sender), leaving the manager's own roster stale. Added `refreshSessionState()` + `pruneAbsentPlayersFromGameState()` in the prune block.

**Deviation note.** §10 W9 scoped `beforeunload` / `pagehide` handlers (or `navigator.sendBeacon`) *and* heartbeat infrastructure. W9 shipped **heartbeat + server-side prune only** — the explicit-unload handlers were not done. The heartbeat approach is more robust against what `beforeunload` misses (crash, network loss, OS process kill). The known weak spot — Mobile Safari / Capacitor WKWebView suspending background JS, making a backgrounded user a ghost for up to 60s — is filed as DEFERRED ("Capacitor iOS app-lifecycle hooks for the heartbeat").

## What W10 delivered

W10 as shipped is **not** §10's literal "W10 — Cleanup." §10 W10 specified four post-implementation cleanup tasks (`index.html` `APP_MANIFEST` shrink, `GAMES-CONTROL-MODEL.md` §9 supersession edits, `SESSION-5-CLOSEOUT-PLAN.md` restructure, `DEFERRED.md` mark-obsolete sweep). What shipped under the "W10" label was a batch of issue fixes + UX polish + the W5 dead-code sweep:

- **`014c738` W10/issue-1 (v2.134)** — manager roster auto-updates when a new player joins (the manager wasn't re-rendering on joiner arrival).
- **`302c33d` W10/issue-2 (v2.135)** — Last Card top-strip "current card" rendered black; root cause a CSS class-name prefix mismatch (`.lc-card-sm` CSS expected bare color names, the JS emitted `color-`-prefixed classes). Fixed; wild cards now tint to the chosen active color.
- **`651976d` W10/last-card-polish (v2.136)** — bundled: double-tap a playable card to play it (additive fast path alongside tap-to-select); and un-mirror opponent avatar initials (a `scaleX(-1)` counter-flip on the text span — also fixes Euchre's opponent strip).
- **`a7dd71a` W10/cleanup (v2.137 / tv v2.101)** — the W5 dead-code sweep deferred since W7: removed 6 dead Play Again functions, 3 dead Agora receivers, 3 dead `#screen-gameover` HTML blocks, orphaned CSS, plus a dead `game-restart` receiver in `games/tv.html`. Also appended 12 DEFERRED entries and added a `.gitignore` editor-swap-file block.

**Deviation note.** The four §10-defined W10 cleanup tasks remain undone — filed as a new DEFERRED entry ("admission_model_v2 §10 W10 cleanup tasks") in this doc commit. The `a7dd71a` commit message states "admission_model_v2 §10 work fully shipped: W1-W9 + W10"; measured against §10's literal W10 text, that overclaims. The W5 dead-code sweep was real cleanup, and `a7dd71a` *added* 12 DEFERRED entries — but §10 W10's "mark obsolete entries Resolved / Superseded" plus the `APP_MANIFEST` and doc-supersession tasks did not happen. This log records the accurate picture.

## Resolved investigations

Several read-only pre-flight investigations ran this session ahead of the W10 commits — each fed directly into a ship, so they are recorded here rather than as standalone no-action items:

- **W5 dead-code scope investigation** — traced the six W5 Play Again functions, confirmed all dead via a cascade (force-hidden HTML blocks → unreachable buttons → unsent messages → dead receivers), and found `.play-again-toggle` / `.play-again-indicator` CSS as additional dead-but-retained orphans. Fed `a7dd71a`.
- **`DEFERRED.md` format review** — confirmed the per-entry format and append point ahead of the 12-entry consolidation.
- **Last Card issue-2 / issue-3 / issue-5 pre-flights** (top-strip card color, double-tap to play, mirrored opponent initials) — each concluded with a concrete fix shape; results are in the W10 commits above.

## Hardware verification status

Most W7-W10 commits are **operationally verified through hardware use** across the 2026-05-18 → 2026-05-19 sessions, even where individual commit bodies say "static review only" — that phrase reflects the per-commit gate at commit time, before the verification round. Explicit per-commit verification gates remain in the commit bodies as the formal record. Specifically:

- **W8c-4** — hardware verified (explicit in commit body).
- **db/024** — verified on prod (`a1273df`; static schema checks + manual prune smoke test + 42501 auth-gate check).
- **W9 client heartbeat** — firing verified live (multiple successful 200s observed in the Network panel).
- **W9-fix** — hardware-verified during session continuity.
- **W10/issue-1** — all three checks passed.
- **W10/issue-2** — colors confirmed (blue-card screenshot).
- **W10/last-card-polish** — 5 of 6 checks green; the 6th (opponent camera video black-screen) is a real failure, deferred and filed (DEFERRED #12 in `a7dd71a`).
- **W10/cleanup** — pure dead-code removal; the one outstanding check is a Game Over regression pass (low risk — the knock-on cleanup explicitly handled the dead-block null-ref hazard in `showGameOver`).
- **W7, W8a-W8c-3-fix2** — operationally verified through usage across the two sessions, even where formal per-commit gates were not individually green-flagged in commit bodies.

**Outstanding:** the W10/cleanup Game Over regression check; the opponent camera-video black-screen failure (filed in `docs/DEFERRED.md`).

## Capacitor app caveat

The iOS Capacitor bundle (`~/Projects/elsewhere-app/`) is **stale at v2.99** (pre-3a.1) and was not synced this session — per project doctrine, iOS bundle drift mid-session is acceptable; sync is deferred until the next Capacitor-relevant work. None of W7-W10 touches Capacitor plugins, push, or fullscreen; Mobile Safari against GitHub Pages is the verification target. A future `npx cap sync ios` will pick up the full W7-W10 web-bundle delta (v2.99 → v2.137) in one jump.

## What's deferred to next session

- **13 DEFERRED.md entries new since this Part 3c work:** the 12 filed in `a7dd71a` (Cam button on/off state, manager-leave role-transfer, `screen-watching` orphan dead code, `#mgr-start` dead UI, `.visible`-pattern cleanup, Trivia Reveal double-score, `screen-lobby` rename, iOS heartbeat app-lifecycle hooks, Agora peer lifecycle vs prune, realtime silent-disconnect detection, participant-sync → `postgres_changes` migration, opponent camera black-screen) plus the new **"admission_model_v2 §10 W10 cleanup tasks"** entry filed in this doc commit.
- **W10/cleanup Game Over regression check** — outstanding hardware gate (low risk).
- **Opponent camera-video black-screen** — real W10/last-card-polish verification failure (DEFERRED).
- **Next major workstream** — unified-app / NHHU-as-first-class planning session (see "Next session entry point").

## Session process notes

Not coding doctrine — genuinely locked doctrine graduates to `CLAUDE.md` per `docs/SESSION-CLOSING-METHODOLOGY.md`. Recorded here as working-rhythm observations:

- **Commit granularity calibrated.** Small UX-polish items bundle into a single commit rather than one-commit-per-fix; `W10/last-card-polish` (double-tap + un-mirror initials — two unrelated small fixes in one commit) was the pivot point for that calibration.
- **Step-gated working rhythm confirmed as default.** Pre-flight investigation → report → user locks decisions → draft → chunked diff review → stage (with stat confirmation) → commit → push, each a discrete gated step, was used throughout W10 and is the confirmed default rhythm.

## Next session entry point

> Unified-app / NHHU-as-first-class planning session. The architecture question is how to serve non-household users (NHHU) as first-class users rather than via the frozen parallel `audience.html` codebase. Frame the planning around three axes: (1) HHU vs NHHU, (2) at home vs. not at home, (3) playing vs. watching.
>
> Reference: the four 2026-04-26 DEFERRED entries — "Audience.html freeze (no new features in Session 5)", "Migrate audience.html into unified app as parameterized NHHU view", "Audience browsing of venues/costumes for marketing", "Audience read-only queue display" — plus `docs/KARAOKE-CONTROL-MODEL.md` §5.5 for the existing architectural direction.
