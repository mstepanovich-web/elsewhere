# Session 5 Part 3a Closing Log

**Created:** 2026-04-30
**Scope:** Closing log for Session 5 Part 3a (Games foundation). Captures shipped state, deferred items, hardware verification status across 3a.1 (plumbing) and 3a.2 (manager controls). Names "Part 3" in the filename to match the Part 2 closing log convention; in practice this log covers Part 3a only — 3b/3c/3d will get their own closing material when they ship.

## Sub-part status

| Sub-part | Status | Reference |
|---|---|---|
| 3a prereq | ✓ Shipped | `db/016_remove_participant.sql` at commit `05d2cae` |
| 3a.1 plumbing | ✓ Shipped + HW-verified on iPhone Safari | commit `ea89c48` at v2.100 |
| 3a.2 manager controls | ✓ Shipped, HW-verification PENDING | commit `8bff27b` at v2.101 |
| ROADMAP sync | ✓ Shipped | commit `6e33bf7` |
| 3b Trivia | Pending | per GAMES-CONTROL-MODEL.md § 4.1 |
| 3c Last Card | Pending | per GAMES-CONTROL-MODEL.md § 4.1 |
| 3d Euchre | Pending | per GAMES-CONTROL-MODEL.md § 4.1 |

## What 3a.1 delivered (plumbing pass)

- **Manager identity from `session_participants.control_role`.** Retired the pre-3a `?mgr=1` URL param and `mgrCheck` join-screen checkbox. ~30 `isManager` use sites swapped to `currentMyRow?.control_role === 'manager'` (function-local derive where multi-use, inline elsewhere).
- **`agora-identity-bind` protocol.** Ephemeral Agora message that announces `(uid → user_id, player_id)` at join time. Receivers populate `uidToUserId{}` (camera-tile attachment) and `playerIdToUserId{}` (tv-display-added owner translation). Includes `wasNew` echo guard against ping-pong between two peers.
- **Camera state split.** `cameraState{}` keyed by Agora uid (transient, rotates on reconnect) is now distinct from `currentParticipants[]` (durable session-level state from `rpc_session_get_participants`). Renderers join the two via uidToUserId reverse-lookup.
- **Realtime sub on `tv_device:<device_key>`.** Handles `participant_role_changed` (with L1 removed-row auto-navigate), `queue_updated`, `session_ended` (handleBackToElsewhere). Mirrors karaoke/singer.html `startSingerRealtimeSub` (line 2080).
- **`refreshSessionState()` cold-path.** Looks up session by `room_code`, calls `rpc_session_get_participants`, populates `currentSession` / `currentParticipants` / `currentMyRow`, subscribes to realtime. Mirrors singer.html line 2268.
- **`rpc_session_join` wiring.** Inside doJoin, with 23505 idempotency for page-refresh / shell-already-joined cases.
- **`games/engine/` DELETED.** 520 lines (last-card.js + trivia.js + sync.js) that were never imported anywhere — confirmed via Phase 1 audit grep. CLAUDE.md updated to reflect inline implementations only.
- **γ-1 lobbyPlayers transitional synthesis.** Bridge so 3a.1 didn't have to retire all per-game read sites (managerStartLastCard, managerStartTrivia, managerStartEuchre, etc.) in the same commit. Synthesis re-derives `lobbyPlayers[]` from `currentParticipants` + `cameraState` + `uidToUserId` + `tvDisplaysByUserId` on every refreshSessionState call. Marked TRANSITIONAL with retirement scheduled for 3a.2.

## What 3a.2 delivered (manager controls)

- **End Session button row split.** Pre-3a's mislabeled "End Session" button (which actually returned to lobby) renamed to "Switch Game" via `managerSwitchGame()`. New "End Session" button wired to `managerEndSession()` async function — `await rpc_session_end` with 42501/02000 error-code branching → `await window.publishSessionEnded` inside try/catch → `handleBackToElsewhere`. Pattern mirrors `index.html` lines 3025-3070 (cross-app switch flow).
- **Manager-as-player toggle wired to DB.** `toggleManagerAsPlayer` rewritten async: calls `rpc_session_update_participant` on the manager's own row to flip `participation_role` between `'active'` and `'audience'`. Capacity-fail UX (errcode 55000) shows toast `"Room is full — remove a player first."` and reverts the checkbox to `currentMyRow`'s authoritative state. Followed by `publishParticipantRoleChanged` + `refreshSessionState` (BUG-13 self:false).
- **Remove Player UI.** Per-row Remove button on each non-self participant in `renderRoster` (manager only). `handleRemovePlayer` wraps `rpc_session_remove_participant` (db/016 prereq from `05d2cae`) with confirm prompt + caller-side publish + self-refresh. Mirrors singer.html `handleQueueRemoveTap` (line 2852).
- **`renderRoster` fully rewritten.** Reads `currentParticipants` directly. Camera state via `findUidForUser` reverse-lookup against `cameraState`. Queue rendering noop'd (admission_mode queueing defers to 3b/3c/3d).
- **In-game render swap.** `renderOthersStrip` (Last Card) and Euchre per-player tile render swapped from `lobbyPlayers.find(by name)` to `currentParticipants.find(by display_name)` + `uidToUserId` reverse against `cameraState`. Per-game start functions (`managerStartLastCard`, `managerStartTrivia` question gen, `managerStartEuchre`) now derive `playerNames` from `currentParticipants` where `participation_role === 'active'`.
- **Retirements (verified via static grep, all counts now 0).** `lobbyPlayers[]` declaration + all read sites; `managerIsPlayer` boolean + all read sites; `syncLobbyPlayersFromState` γ-1 synthesis function (replaced by 6-line `findUidForUser` helper); `manager-player-status` Agora message send (no handler ever existed in either games/player.html or games/tv.html — vestigial since at least 3a.1, retired implicitly with toggle rewrite); all 3a.1 TRANSITIONAL comment blocks (12 distinct blocks rewritten or deleted). Play-again filter sites at lines 1427 / 2551 / 2561 from 3a.1 DELETED entirely per locked decision — non-yes-responders accepted in the post-game lobby; manager uses the new per-row Remove button to clear stragglers.

## Hardware verification status

**3a.1 — verified on iPhone Safari (signed-in flow):**
- agora-identity-bind protocol fires correctly (uid binding propagates between phones)
- 23505 idempotency catches page-refresh / shell-already-joined cases without double-insert
- refreshSessionState populates currentSession / currentParticipants / currentMyRow correctly
- Realtime sub subscribes to `tv_device:<device_key>` and reacts to participant_role_changed
- Manager bar visibility derives from `currentMyRow.control_role === 'manager'` (not URL param or checkbox)

**3a.2 — NOT YET verified on hardware.**

## Verification gate before 3b begins

The 3a.2 commit (`8bff27b`) is unverified on real devices. Before 3b (Trivia integration) starts, the following must be confirmed end-to-end against `mstepanovich-web.github.io/elsewhere/games/player.html`:

1. **Manager bar UI.** Manager bar shows ▶ Start (per-game), End Game (per-round), Switch Game, and End Session. Pre-3a's mislabeled End Session (the lobby-return one) is now Switch Game.
2. **End Session full flow.** Manager taps End Session → confirm prompt → both phones (manager + non-manager) navigate to Elsewhere shell within 1-2s. TV (games/tv.html) navigates to tv2.html (session_ended realtime broadcast fires). Verify with logs that `publishSessionEnded` ran with `reason: 'user_ended'`.
3. **Manager-as-player toggle.** Uncheck "I'm playing in this game" → DB updates participation_role to `'audience'` → other phone's roster reflects change within 1-2s. Re-check → flips back to `'active'`. Persists across page refresh.
4. **Capacity-fail toast.** With session at capacity (6 active players), manager tries to flip themselves from audience to active → toast `"Room is full — remove a player first."` appears, checkbox snaps back to unchecked.
5. **Remove Player UI.** Manager sees per-row Remove button on each other participant (not on self). Tap → confirm prompt → target's phone navigates to Elsewhere shell within 1-2s, target's row disappears from roster on remaining phones.
6. **Pre-3a UX preserved.** Last Card / Trivia / Euchre still start correctly with active-only player list. Camera tiles still attach. Play-again flow still works (with caveat: non-yes-responders now stay in lobby — manager uses Remove to clear, per locked decision).

If any verification step fails, fix forward in a follow-up commit; do NOT begin 3b until 3a.2 is verified green.

## Capacitor app caveat

The iOS Capacitor wrapper at `~/Projects/elsewhere-app/` bundles its own copy of the web files via `cap sync` from `~/Projects/elsewhere-app/www/`. That bundle is currently **stale at v2.99** (pre-3a.1). Per CLAUDE.md doctrine ("iOS bundle drift mid-session is acceptable"), `npx cap sync ios` is deferred until end-of-session hardware verification confirms 3a.2 feature correctness. Mobile Safari against GitHub Pages is the verification target — covers all of 3a.2's UX since none of it touches Capacitor plugins, push, or fullscreen.

When 3a.2 verifies green, run the standard sync chain: `~/sync-app.sh` → `npx cap sync ios` → Xcode rebuild + install.

## Closeout TODOs from 3a.1 — status

| TODO | Status |
|---|---|
| (1) Amend Control Model § 4.1 to remove "Sit out / Rejoin queue UI" line | ✓ Done in 3a.2 (D1 amendment, commit `8bff27b`) |
| (2) Retire `request-state` Agora message when last per-game late-joiner UX ships in 3d | Carried forward — retires in 3d, not 3a.2 |
| (3) Play-again filter sites at lines 1427 / 2551 / 2561 from 3a.1 — `lobbyPlayers` retirement requires deletion or rewrite | ✓ Done in 3a.2 — sites DELETED entirely; non-yes-responders linger in post-game lobby per locked decision (Q1); manager uses Remove Player UI to clear stragglers. |
| (4) Delete TRANSITIONAL comment blocks introduced in 3a.1 when γ-1 synthesis retires | ✓ Done in 3a.2 — 12 distinct blocks rewritten or deleted; verification grep `TRANSITIONAL` (case-insensitive) = 0 |

## What's deferred to next session

- Hardware verification of 3a.2 on iPhone Safari (gate before 3b — see "Verification gate" above).
- Begin 3b — Trivia integration per `docs/GAMES-CONTROL-MODEL.md` § 4.1: `self_join` admission, late-joiner choice screen (Active vs Audience), manager controls (Reveal/Next/Skip) routed through `control_role` check.
- iOS Capacitor sync after 3a.2 verifies green.

## Doctrine updates this session

No new doctrine. The γ-1 transitional synthesis pattern proved useful for splitting plumbing-vs-UX commits in a single feature, but the user noted it shouldn't generalize without specific motivation — sample size of one. If the pattern recurs in 3b/3c/3d (e.g., bridging per-game state machines vs admission UX), revisit; otherwise file under "tactic, not doctrine."

## Next session entry point

> Hardware verify 3a.2 on iPhone Safari first (gate per "Verification gate" above). If green, plan 3b per `docs/GAMES-CONTROL-MODEL.md` § 4.1 (Trivia integration). If red, fix forward before 3b.
