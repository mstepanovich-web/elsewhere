# Session 5 Part 3 — Games audit

**Created:** 2026-04-30
**Purpose:** Ground-truth audit of `games/` codebase before Part 3 implementation. Documents what exists today, what works end-to-end, what's dead code, and what gaps affect Part 3 planning. The prescriptive scope for Part 3 lives in `docs/GAMES-CONTROL-MODEL.md`; this audit is the descriptive baseline that doc references.
**Investigation pass:** 2026-04-30 (Claude Code investigation session, conducted alongside chat-Claude planning)
**Companion doc:** `docs/GAMES-CONTROL-MODEL.md` — prescriptive Part 3 scope.

---

## TL;DR

Three findings that matter for Part 3:

1. **Engine modules in `games/engine/` are dead code.** All game logic lives inline in `games/player.html`. The 745 lines in `last-card.js` / `trivia.js` / `sync.js` are imported nowhere. The directory should be deleted as part of Part 3 cleanup. CLAUDE.md needs a corresponding correction (currently describes the engine modules as if they're functional code).

2. **All three games actually work end-to-end.** Trivia, Last Card, and Euchre play through complete games with real implementations. No game gets dropped from Part 3 due to incompleteness.

3. **Cross-game shell is genuinely shared.** The lobby, manager-bar, Agora message protocol, and game-state broadcast pattern are shared infrastructure across all three games. Part 3a's "common foundation" framing is right-sized: plumbing replacement on a single shared shell, not three separate per-game integrations.

## Per-game functional verdict

| Game | Verdict | Notes |
|---|---|---|
| Trivia | Complete and functional | Manager-driven question/reveal/next loop. Caveat: depends on Anthropic API call from manager's phone with no auth header — fragile to API changes. Uses `claude-sonnet-4-20250514` (older model). |
| Last Card | Complete and functional | Plays end-to-end. Single-round only — no built-in "deal next round" auto-flow. PHASE1-NOTES references "end-game state leakage — investigated, deferred pending repro" — possibly relevant. |
| Euchre | Complete and functional | Most state-rich. Multi-hand play, full scoring, dealer rotation, going-alone, partner sit-outs, march bonuses, euchred penalties. Surprisingly polished. |

## Existing manager controls

All wired to UI buttons; no orphans, no stubs.

| Function | Game scope | Reachable | Works |
|---|---|---|---|
| `managerStart()` | All — dispatches per-game | ✓ | ✓ |
| `managerReveal()` | Trivia only | ✓ | ✓ |
| `managerNext()` | Trivia only | ✓ | ✓ |
| `managerSkip()` | Last Card only (forces draw) | ✓ | ✓ |
| `managerEndGame()` | All | ✓ | ✓ |
| `managerEnd()` | All | ✓ | ✓ (but **mislabeled** — see below) |
| `managerAskPlayAgain()` | All | ✓ | Likely works |
| `managerStartFromGameOver()` | All — dispatches per-game | ✓ | ✓ |
| `managerNextRound()` | Last Card only | Conditional | Likely works |

**`managerEnd()` mislabeling:** the button text is "End Session" but the function only ends the current game and returns to lobby. It does NOT end the Session 5 session. Part 3 corrects this: existing button becomes "End Game" or "Switch Game"; a new "End Session" button gets added that actually calls `rpc_session_end`.

## Cross-game shared infrastructure

Confirmed shared across Trivia, Last Card, Euchre:

- One join flow (`doJoin`, `games/player.html` lines 945-1032)
- One lobby implementation (`renderRoster`, `recomputeQueue`, `lobbyPlayers[]` state)
- One Agora message protocol (`player-join`, `player-join-ack`, `game-start`, `game-state`, `game-over`, `game-restart`, `switch-game`)
- One state-broadcast pattern (`broadcastState()` line 3036 — manager-only sends `game-state` to all)
- One game-over screen (`showGameOver()` line 2154)
- One game-restart pattern (`managerStartFromGameOver` line 2202)
- One play-again flow (`ask-play-again` / `play-again-response`)
- One manager-bar UI (header strip with mgr-* buttons, per-game show/hide)
- One TV-pairing protocol (Session 4.8 `player_id` stable identity, `hasTVs` aggregation)
- One camera/video tile rendering for non-TV-mode players

The per-game branches are entirely game-specific state machines and rendering. Shell is genuinely shared.

## Existing Agora message protocol

**Lobby/identity:**
- `player-join` (player → all) — announces self
- `player-join-ack` (any → joiner) — confirms receipt
- `tv-display-added` — TV announces to player_id-owning player
- `invite-sent` — manager broadcasts pending-invite name list
- `camera-on` / `camera-off` — video tile state
- `limit-changed` — manager adjusts player capacity
- `ping` — keepalive at 20s interval
- `manager-player-status` (manager → all) — broadcasts manager-as-player toggle state. **Investigation pending:** handler not found in either file via re-verification grep; possibly vestigial. See "Open follow-ups" below.

**Game lifecycle:**
- `game-selected` (manager → all) — pre-start game choice
- `game-start` (manager → all) — initial game state
- `game-state` (manager → all) — full state broadcast on every change
- `game-over` (manager → all) — scores + transition
- `game-restart` — return to lobby
- `switch-game` — manager exits current game; back to game selection
- `request-state` (player → manager) — late-joiner / reconnect state request
- `ask-play-again` (manager → all) — post-game restart prompt
- `play-again-response` (player → manager) — yes/no response to ask-play-again

**Per-game gameplay (envelope: `player-action`):**
- `player-action` (player → manager) — non-manager sends a game move; manager applies it to authoritative state, then broadcasts updated `game-state`. Carries `action` sub-field with per-game payload:
  - **Last Card:** `'play'` (with card + chosenSuit), `'draw'`, `'pass'`, `'declare-last-card'`
  - **Euchre:** `'eu-bid-pass'`, `'eu-order-up'`, `'eu-call-suit'`, `'eu-dealer-discard'`, `'eu-play'`
- `trivia-answer-received` (player → manager) — Trivia answer submission. Older message that predates the `player-action` envelope.

**Per-game game logic flows through the `player-action` envelope's `action` sub-field; the `game-state` broadcast is downstream of that.** An earlier draft of this audit claimed Last Card and Euchre had no game-specific messages — that was incorrect. Both games rely heavily on `player-action`, just embedded inside one envelope rather than as top-level message types.

**Chunked sender** is required for Euchre full state (4 hands × 5 cards + trump + tricks won + scores + dealer + maker can exceed 1KB during play). `compressState()` and `euCompressState()` minimize payload by sending opponent hand cards as counts not card lists.

## Pre-Session-5 issues confirmed present in code

| Issue | Location | Severity | Resolves in |
|---|---|---|---|
| `?mgr=1` URL param | `games/player.html` lines 925-942, 981-983 | Real but contained — multiple-managers possible if multiple deep-link arrivals | Part 3a (manager identity from `control_role`) |
| `lobbyPlayers[]` broadcast-ephemeral state | `games/player.html` line 825+ | Real, occasional UX papercut — manager refresh loses lobby state on that phone | Part 3a (lobby from `session_participants` query) |
| Direct-launch UX (no room code) | `games/player.html` lines 945-947 | Low — empty join screen, disabled button, no help text | Out of scope for Part 3 (mostly testing path) |
| Last Card end-game state leakage | Suspected at `gameState` lifecycle around `managerEndGame()` | Unknown without repro | Out of scope for Part 3 (pre-existing, separate investigation) |

## What "common foundation" actually means

Part 3a operates on a single set of shared shell code. Concrete replacements:

| Today | After Part 3a |
|---|---|
| `?mgr=1` URL param + `join-mgr-check` checkbox | `currentMyRow.control_role === 'manager'` |
| `isManager` boolean | Derived from `currentMyRow.control_role` |
| `lobbyPlayers[]` array (memory + Agora-broadcast) | `currentParticipants[]` from `rpc_session_get_participants` |
| `players{}` map on TV side | Same — TV mirror of `session_participants` |
| `player-join` / `player-join-ack` Agora messages | Realtime `participant_role_changed` events |
| `request-state` Agora message | `refreshSessionState()` query on visibility change |
| `screen-watching` blocking late-joiners | Per-game admission flow (per `docs/GAMES-CONTROL-MODEL.md` § 3) |
| "End Session" button label that ends current game | "End Game" button + new "End Session" button calling `rpc_session_end` |

## What stays unchanged in Part 3

- Per-game state machines (Trivia phase enum, Last Card play logic, Euchre bid/play/score)
- Per-game rendering (`renderLastCard`, `renderTrivia`, `renderEuchre`)
- Manager-as-Agora-authority pattern — manager applies moves, broadcasts `game-state`. No silent-host transport mechanism needed (unlike Karaoke 2e.3.2 §1).
- Existing manager controls per game (Reveal, Next, Skip, etc.) — stay the same, just permission-gated through `control_role` instead of `isManager` boolean.
- Trivia Anthropic API call (separate concern, fragile but unchanged in Part 3).

## Open follow-ups (not Part 3 blockers)

- **Last Card:** "End hand" semantics (score the partial hand vs clear without scoring) — confirm during 3c implementation.
- **Euchre:** partnership assignment on mid-game replacement — options inventoried in `docs/GAMES-CONTROL-MODEL.md` § 3.3, decision deferred to 3d implementation.
- **Euchre:** Force Trump Call manager button — candidate for 3d, may defer to polish.
- **Trivia:** Anthropic API auth fragility — separate concern, not Part 3 scope.
- **Trivia:** Old model name `claude-sonnet-4-20250514` — opportunistic update later, not Part 3 scope.
- **`sync.js`** chunked-message reassembly bug (`_handleChunk` splits on `:` but tries `meta.split(',')` on a string with no commas) — dead code anyway, but worth noting if `games/engine/` ever gets revived.
- **`manager-player-status` Agora message vestigiality** — sent by `toggleManagerAsPlayer` (`games/player.html` line 1537) but no handler found in either `games/player.html` or `games/tv.html` via re-verification grep. May be vestigial. Confirm during 3a implementation; if so, retire alongside the other lobby-state Agora messages.

## Conclusion

Part 3 scope is well-bounded. All three games are functional, the shared shell exists and is genuinely shared, and the architectural decisions are largely pre-made. The Games Control Model (`docs/GAMES-CONTROL-MODEL.md`) prescribes what Part 3 builds; this audit grounds it in what's actually there.

Implementation can begin with 3a once both docs are reviewed and shipped.
