# Games Control Model

**Created:** 2026-04-30
**Purpose:** Defines the role hierarchy, admission model, and per-game specs for games in Elsewhere. Specifies what each role can do, how late-joiners are handled per game, and how the manager intervenes when needed.
**Scope:** `games/tv.html` and `games/player.html`. Three games: Trivia, Last Card, Euchre. Pictionary is referenced in `docs/SESSION-5-PLAN.md` but is not implemented; out of scope for Session 5 Part 3.
**Anchored to:** `docs/PHONE-AND-TV-STATE-MODEL.md` (platform user model), `docs/SESSION-5-PLAN.md` (universal session + participants schema). HHU/HHM/NHHU and Modes A/B/C are defined in the state model and not redefined here.
**Companion doc:** `docs/SESSION-5-PART-3-AUDIT.md` captures ground-truth findings of what exists in `games/` today and informs this Control Model's scope.
**Referenced by:** `docs/SESSION-5-PART-2-BREAKDOWN.md` Part 3.

---

## 1. Roles

### Platform-level roles

Inherited from the state model: HHM (household admin), HHU (household member), NHHU (authenticated user not in the household). Games' `ask_proximity: false` (per SESSION-5-PLAN.md Decision 8) means proximity is not required to participate. Games are accessible to all authenticated users in the session, regardless of HHU/NHHU status.

### Session-level roles for games

A games session has these roles:

| Role | Definition |
|---|---|
| **Session Manager** | The user with session-level control authority. Always exactly one per session. Has manager-only buttons in games UI: Start, per-game controls (Reveal/Next/Skip), End Game, End Session, Remove Player. |
| **Active Player** | A user with `participation_role = 'active'` in the session. Can act in the game (submit answers in Trivia, play cards in Last Card, etc.). Multiple Active Players per session — unlike karaoke's singular Active Singer. |
| **Queued Player** | A user with `participation_role = 'queued'`. Waiting to become Active when capacity opens. Per-game admission rules determine when promotion happens. Queued users see a "you're #N in line" position display on their phone. |
| **Audience** | A user with `participation_role = 'audience'`. In the session but not currently playing. Two paths in: (a) NHHU or other users who deep-link in without intent to play, or who join after capacity is reached and choose not to queue; (b) Queued users who explicitly sideline themselves to avoid auto-promotion. Audience users see a "you're in the session but not playing" screen with options to (re)join the queue when applicable. Audience users can scan the TV's QR code to view the games TV experience on their phone for spectator viewing — same QR-code-to-phone-display feature available to all games users. |

### "Sidelining" — explicit opt-out from auto-promotion

Some queued users may not want to auto-promote when capacity opens — they want to chat, grab snacks, watch over someone's shoulder, or otherwise be in the session without being pulled into a round. They can sideline themselves: tap a "Sit out" button on their queued-user phone screen. This transitions them from `participation_role = 'queued'` to `'audience'`. They lose queue position. Tapping "Rejoin queue" on the audience screen re-queues them at the end of the line.

Rationale for losing position: simpler model (no separate sideline flag in schema), aligns with real-world fairness ("if you stepped away, you start over when you come back"), and matches the karaoke pattern where `'audience'` means "in session, not currently engaged."

### Roles map to schema

| Games UI role | `control_role` | `participation_role` |
|---|---|---|
| Session Manager | `manager` | `active` |
| Active Player | `none` | `active` |
| Queued Player | `none` | `queued` |
| Audience | `none` | `audience` |

Two layers of role identity:

- **Manager-vs-not** is computed from `control_role`. The current games code uses an `isManager` boolean derived from URL param `?mgr=1` and a manual checkbox. Part 3 retires both — manager identity comes from `session_participants.control_role === 'manager'`.

- **Active-vs-queued-vs-audience** is computed from `participation_role`. The current games code uses an inline `lobbyPlayers[]` array with `status: 'active' | 'queue'`. Part 3 retires this — participation comes from `session_participants.participation_role`.

### Session Manager hierarchy

Per `docs/KARAOKE-CONTROL-MODEL.md` § 1: HHM in session → HHM is Manager; HHM not in session → originator is Manager; auto-pass on departure to next session-join order.

Games doesn't have karaoke's Available Singer concept — there's just Manager + everyone else.

### One Session Manager per session, ever

The current games code allows multiple managers (the `?mgr=1` + auto-checkbox bug filed in PHASE1-NOTES). Part 3 enforces single-manager via `session_participants.control_role` unique constraints. Multiple deep-link arrivals can no longer create competing managers.

---

## 2. Cross-game patterns

These patterns apply across all three games. Per-game specifics are in § 3.

### 2.1 Session lifecycle

Games follow the same Session 5 lifecycle as Karaoke:

- **Start:** Manager taps Games tile in Elsewhere shell → `rpc_session_start({app: 'games', tv_device_id})` creates the session row → `publishLaunchApp` broadcasts to TV → `games/tv.html` mounts and queries the session.
- **Join:** Player scans QR or follows deep link → `games/player.html` mounts → `rpc_session_join` adds them to `session_participants`.
- **End Session:** Manager taps "End Session" → `rpc_session_end` → all phones navigate to Elsewhere home, TV navigates to apps grid.
- **End Game (without ending Session):** Manager taps "End Game" → game state ends, players return to lobby. Session stays alive, manager can pick another game.

The current games code conflates "End Game" and "End Session" — the existing "End Session" button only ends the current game, not the Session 5 session. Part 3 corrects this: "End Game" ends the current game (return to lobby), "End Session" ends everything (per `rpc_session_end`).

### 2.2 Lobby model

**Today:** Lobby state lives in an in-memory `lobbyPlayers[]` array on each phone, broadcast over Agora `player-join` / `player-join-ack` messages. Fragile — if the manager refreshes their browser, lobby state is lost on that device until peers re-broadcast.

**Part 3:** Lobby state is a query against `session_participants`. Each phone calls `rpc_session_get_participants` on mount and on every `participant_role_changed` realtime event. State is durable across reloads, manager refreshes don't lose anything, late joiners get a clean view of who's in.

**No more `player-join` / `player-join-ack` Agora messages.** Replaced by realtime `participant_role_changed` events on `tv_device:<device_key>`.

### 2.3 Manager identity

**Today:** `isManager` boolean from URL `?mgr=1` or join-screen checkbox. Multiple managers possible.

**Part 3:** Manager identity from `currentMyRow.control_role === 'manager'`. Single manager enforced by schema unique constraint. The `?mgr=1` URL param and join-mgr-check checkbox are both retired.

When the manager refreshes or rejoins, they're re-identified as manager from the DB — not from URL state.

### 2.4 Manager controls

The current games code has these manager-only buttons (per audit findings):

- **All games:** Start, End Game, End Session
- **Trivia only:** Reveal Answer, Next Question, Skip Question
- **Last Card only:** Skip (force current player to draw)
- **Euchre:** None mid-hand (state auto-advances)

**Part 3 keeps existing manager controls.** No new override panels per game (unlike Karaoke 2e.3.2 §2 which built 6 new buttons). Existing buttons just route through `currentMyRow.control_role === 'manager'` instead of `isManager` boolean.

**One new cross-game manager control:** Remove Player.

### 2.5 Remove Player (cross-game)

The manager can remove any player from the session for moderation. Removed users see a "you've been removed from this session" screen on their phone with no rejoin path (they'd need to scan the QR fresh).

**Mechanism:** Manager taps Remove on a player's row in the lobby/queue display → confirm dialog → RPC removes the user's `session_participants` row → realtime broadcast → user's phone navigates away.

**Scope:** Phase 1 ships Remove only. Suspend (temporarily benched, can be un-benched) is deferred per the closeout discussion.

### 2.6 Manager override transport

The manager already directly sends Agora `game-state` messages (the existing manager-broadcasts-truth pattern). Manager controls (Reveal, Next, Skip, etc.) flow through this same channel.

**Part 3 doesn't change the transport.** No silent-host-style mechanism needed (unlike Karaoke 2e.3.2 §1). Games' existing manager-as-Agora-authority pattern is fine.

### 2.7 Late-joiner UX

**Today:** Late joiners are blocked into a `screen-watching` "watching the game in progress" screen. They can't play.

**Part 3:** Late-joiner experience is per-game (see § 3). General pattern:
- Phone joins via QR/deep-link → `rpc_session_join` → user becomes session participant
- Per-game admission_mode determines what role they get and when they can play
- Phone shows the appropriate role's screen (queued, audience, or active depending on admission)

### 2.8 Capacity overflow

Per game, capacity limits exist (Last Card 8, Euchre 4, Trivia unlimited). When capacity is reached and someone joins, behavior is per-game:

- **Trivia:** unlimited capacity, no overflow, users join as Active immediately.
- **Last Card:** auto-FIFO from queue up to capacity at round-end. If queue exceeds remaining capacity, manager picker UI surfaces. Sidelined users are skipped.
- **Euchre:** all admissions are manager-approved (`manager_approved_batch`). Manager sees queue + selects who joins next hand.

### 2.9 Audience role + TV-experience-via-QR

Audience users (NHHU watchers, sidelined queued users, users who join post-capacity and decline to queue) see a minimal "you're in the session but not playing" screen with:

- A button to (re)join the queue (when applicable per game)
- A QR code that, when scanned by another device, displays the games TV experience for spectator viewing

The QR-code-to-phone-TV-experience feature is existing infrastructure available to all games users; Part 3 just exposes the affordance prominently on the audience screen.

### 2.10 What's retired in Part 3

Pre-Session-5 patterns being removed entirely:

- `?mgr=1` URL parameter (`games/player.html` line 925-942 + 981-983)
- `join-mgr-check` checkbox on join screen
- `isManager` boolean (replaced by `control_role` lookup)
- `lobbyPlayers[]` array (replaced by `currentParticipants[]` from RPC)
- `players{}` map on TV side (replaced by same RPC + realtime sub)
- `player-join` / `player-join-ack` Agora messages (replaced by realtime)
- `request-state` Agora message for late-joiners (replaced by `refreshSessionState` query)
- `screen-watching` blocking late-joiners (replaced by per-game admission flow)
- Misleading "End Session" button label that only ends current game

### 2.11 What's deleted in Part 3 cleanup

`games/engine/` directory: 745 lines of dead code. The modules (`last-card.js`, `trivia.js`, `sync.js`) are imported nowhere; all game logic lives inline in `player.html`. Deleted as part of 3a. CLAUDE.md updated correspondingly.

---

## 3. Per-game specs

Each game gets: existing state machine summary, role manifest (admission_mode + capacity), late-joiner UX, manager controls, and what changes in Part 3.

### 3.1 Trivia

**State machine (existing, unchanged in Part 3):**

`waiting` → `question` → `reveal` → `question` → ... → `game-end`

Manager generates questions (Anthropic API call from manager's phone), starts the game, and drives Reveal/Next transitions explicitly. Game ends after all questions answered. Highest score wins.

**Role manifest:**

| Field | Value |
|---|---|
| `admission_mode` | `self_join` |
| `capacity` | `null` (unlimited) |
| `ask_proximity` | `false` |

**Late-joiner UX:**

Trivia has unlimited capacity, so there's no queue. Late joiners get one of two paths:

- **Default:** Join as `participation_role = 'active'` immediately. They're in for the next question. Already-asked questions: their score for those is 0 (they weren't here).
- **Opt-out:** Land on a "join as audience instead" choice screen. Tap audience → `participation_role = 'audience'`, no scoring, can scan QR for spectator view.

The choice screen is offered because Trivia rounds can run long (10-20 questions) and a late arrival might prefer to watch the rest from their friend's perspective rather than play catch-up with no chance to win.

**Manager controls (existing, gated through `control_role` in Part 3):**

- Generate Questions (calls Anthropic API)
- Start Game
- Reveal Answer (after question time elapses)
- Next Question (advance to next)
- Skip Question (rare; bad question generated)
- End Game (return to lobby)
- End Session (end everything)
- Remove Player (new in Part 3)

**Trivia-specific Agora messages:**

- `trivia-answer-received` (player → manager) — answer submission. Retained — this is gameplay traffic, not lobby state.

**What changes in Part 3 for Trivia:**

- `?mgr=1` retired → manager from `control_role`
- `lobbyPlayers[]` retired → lobby from `session_participants`
- Late-joiner blocking via `screen-watching` retired → admission_mode determines flow
- Choice screen on late-join (Active vs Audience) is new UI
- Remove Player button is new

**Trivia notes:**

- The Anthropic API call from the manager's phone has no auth header (per CLAUDE.md). This is fragile to API changes but unchanged in Part 3 — separate concern, not blocking.
- The `claude-sonnet-4-20250514` model name is older than current Sonnet 4.6. Worth opportunistic update; not Part 3 scope.

### 3.2 Last Card

**State machine (existing, unchanged in Part 3):**

`playing` → `round-end`

Single-round only currently. No automatic "deal next round" flow — manager taps End Game to score, or manager taps Play Again (next deal) flow. Round ends when first player empties hand. Scoring: points = sum of opponents' remaining card values.

**Role manifest:**

| Field | Value |
|---|---|
| `admission_mode` | `wait_for_next` |
| `capacity` | 8 (max), 2 (min), 6 (default) |
| `ask_proximity` | `false` |

**Late-joiner UX:**

Late joiners during an active round get `participation_role = 'queued'` and see "you're #N in line" on their phone. At round-end, queued users are auto-promoted FIFO up to capacity.

**Capacity overflow at round-end:**

When the round ends, the system computes:
- Returning active players (those still in session who finished the round)
- Queued users (FIFO order, sidelined excluded)
- Available slots = `capacity - returning_active`

Two scenarios:

- **Queue ≤ available slots:** All queued users auto-promote. Round 2 starts with returning + queued, all as Active.
- **Queue > available slots:** Auto-FIFO promotes the first N queued users (where N = available slots). Manager sees a picker UI: "Auto-admitted: A, B, C. Still waiting: D, E. Override?" Manager can tap a still-waiting user to swap them in (bumping a different auto-admitted user back to queue head). When manager taps Start Next Round, picks lock and round 2 begins.

**Sidelined users are excluded from auto-promotion.** When a queued user taps "Sit out," they transition to Audience and lose queue position. They can rejoin queue at any point — they go to the end.

**Manager controls (existing + new in Part 3):**

- Start Game
- Skip (force current player to draw — existing)
- End Hand (force-end current round, score it — new in Part 3)
- End Game (return to lobby)
- End Session
- Remove Player (new)
- Capacity overflow picker (new, only surfaces when queue > available slots at round-end)

**What changes in Part 3 for Last Card:**

- All Section 2 retirements (manager identity, lobby state, late-joiner blocking)
- Late-joiners get queued instead of blocked
- Sit out / Rejoin queue UI on queued/audience phones
- Capacity overflow picker on manager phone at round-end
- End Hand button new (in addition to End Game)
- Remove Player button is new

**Last Card open question (deferred to implementation):**

The "End Hand" semantics: does it score the partial hand, or does it just clear without scoring (force re-deal)? The audit didn't surface a clear answer from existing code. Lean: score it (matches pattern of natural round-end), but confirmable during 3c implementation.

### 3.3 Euchre

**State machine (existing, unchanged in Part 3):**

`bid1` → `bid2` → `play` → `hand-end` → `bid1` (next hand) → ... → `game-end`

Multi-hand play with dealer rotation, trump calling, going-alone, partner sit-outs, scoring at 10 points wins. Most state-rich of the three games.

**Role manifest:**

| Field | Value |
|---|---|
| `admission_mode` | `manager_approved_batch` |
| `capacity` | 4 (exactly) |
| `ask_proximity` | `false` |

**Late-joiner UX:**

Euchre is partnership-based (2 vs 2). Late entry is structurally awkward — you can't just slot a 5th person in. Late joiners get queued + sidelined as needed.

**Capacity at hand-end:**

When a hand ends, the system checks if the active 4 are still in session. If anyone left, the manager sees a picker:

- **Queue with admit options:** "Player X left. Who fills the seat? [List of queued users with Admit buttons]"
- **All 4 still here:** No picker, next hand starts normally.

If multiple players left in one hand (rare), manager admits multiple from queue.

**Partnership question (deferred to implementation):**

When a player is replaced mid-game, partnership assignment is ambiguous. Options:

- **(i)** New player joins the original team of the player they replaced
- **(ii)** Manager picks partnerships from scratch each hand
- **(iii)** Reshuffle randomly when anyone is replaced

Implementation-time decision in 3d.

**Manager controls (existing + new in Part 3):**

- Start Game
- End Hand (force-end current hand, score it — new)
- End Game (return to lobby)
- End Session
- Remove Player (new)
- Force Trump Call (rare; trump-call phase stuck due to AFK dealer — new, possibly deferred)
- Hand-end picker (new, only surfaces when seat needs filling)

**What changes in Part 3 for Euchre:**

- All Section 2 retirements
- Late-joiner queueing per `manager_approved_batch`
- Sit out / Rejoin queue UI on queued/audience phones
- Hand-end seat-filling picker on manager phone (when needed)
- End Hand button new
- Remove Player button is new
- Force Trump Call button (lean toward shipping, but flag as candidate-for-defer if it bloats 3d)

**Euchre open questions (deferred to implementation):**

- Partnership assignment on mid-game replacement (per above)
- Whether Force Trump Call ships in 3d or post-3d polish
- "Force go-alone" decision — probably not needed; trump caller has full control of going-alone choice naturally

### 3.4 Pictionary (out of scope)

Listed in `docs/SESSION-5-PLAN.md` Part 3 with `admission_mode: 'manager_approved_single'` for artist + `self_join` for guessers. Not implemented in current `games/`. Out of scope for Session 5 Part 3. Future implementation work; the role manifest in SESSION-5-PLAN.md is the spec source when it lands.

---

## 4. Implementation mapping

### 4.1 Part 3 sub-decomposition

Part 3 ships across 4 sub-parts, foundation-first:

| Sub-part | Scope | Effort |
|---|---|---|
| **3a — Common foundation** | Replace `?mgr=1` + `lobbyPlayers[]` + `isManager` with `session_participants` lookups across the shared games shell. Add `rpc_session_start` on TV mount, `rpc_session_join` on player mount. Wire realtime sub on `tv_device:<device_key>`. Delete `games/engine/`. Update CLAUDE.md to reflect that engine modules don't exist. Add Remove Player button to manager-bar (cross-game). Add Sit out / Rejoin queue UI for queued/audience users. Wire QR-code-to-phone-TV-experience affordance on Audience screen. Rename "End Session" button to "End Game" and add a separate proper End Session button. No per-game logic changes. | ~3-5 hr, 1-2 commits |
| **3b — Trivia integration** | Validate foundation against simplest game first. `self_join` admission. Late-joiner choice screen (Active vs Audience). Manager controls (Reveal, Next, Skip) routed through `control_role` check. | ~2 hr, 1 commit |
| **3c — Last Card integration** | `wait_for_next` admission. Late-joiner queued state with position display. Sidelined users excluded from auto-promotion. Capacity overflow picker on manager phone at round-end. End Hand button (in addition to End Game). | ~3-4 hr, 1-2 commits |
| **3d — Euchre integration** | `manager_approved_batch` admission. Hand-end seat-filling picker. End Hand button. Force Trump Call button (or deferred). Partnership assignment on replacement (decision deferred to implementation). | ~3-4 hr, 1-2 commits |

**Total estimate: 11-15 hours, 5-7 commits across 4-5 sessions.**

### 4.2 Files touched per sub-part

| Sub-part | Files |
|---|---|
| 3a | `games/tv.html`, `games/player.html`, delete `games/engine/`, `CLAUDE.md` (correction) |
| 3b | `games/player.html` (Trivia logic + late-joiner choice screen) |
| 3c | `games/player.html`, `games/tv.html` (Last Card logic + overflow picker UI) |
| 3d | `games/player.html`, `games/tv.html` (Euchre logic + seat-filling picker UI) |

No new schema migrations. Part 3 reuses existing `sessions` and `session_participants` from Part 1.

No new RPCs. Part 3 reuses existing `rpc_session_start`, `rpc_session_join`, `rpc_session_get_participants`, `rpc_session_update_participant`, `rpc_session_end`. The participation_role transitions (queued → active on auto-promote, queued → audience on sit-out) all flow through `rpc_session_update_participant`.

### 4.3 Entry criteria per sub-part

- **3a:** Part 2 complete (✓), Audit doc shipped, this Control Model shipped.
- **3b:** 3a shipped + verified on real device.
- **3c:** 3b shipped + verified.
- **3d:** 3c shipped + verified.

Sequential, not parallel. Each sub-part validates the foundation before the next adds complexity.

### 4.4 Verification per sub-part

Each sub-part needs both static and on-device verification before moving to the next. Static verification: grep + diff review. On-device verification: real iPhone Capacitor app + at least one other phone (laptop browser is acceptable for second device in early sub-parts; real second iPhone needed for late-joiner flows).

For 3c and 3d, capacity-overflow scenarios need 9+ users for Last Card and 5+ for Euchre. Realistic test approach: run test sessions with multiple browser tabs as proxies for additional users when a real test session isn't available.

### 4.5 Deferred from Part 3 (post-Part-3 backlog)

These are explicit non-goals that get filed to DEFERRED.md when Part 3 wraps:

- **Suspend player (vs Remove)** — temporarily benched users. Phase 1 ships Remove only.
- **Pictionary implementation** — not in current games; future scope.
- **Euchre Force Trump Call** — may ship in 3d or defer to polish.
- **Last Card "end-game state leakage"** repro — pre-existing PHASE1-NOTES bug; not introduced or fixed by Part 3.
- **Trivia Anthropic API auth fragility** — separate concern from Part 3 scope.
- **Trivia old model name** (`claude-sonnet-4-20250514`) — opportunistic update later.
- **Engine module reintroduction** — if shared game logic ever needs extraction, it'll be greenfield, not the current dead modules.

### 4.6 Doc updates alongside Part 3

When Part 3 ships, the following docs need synchronized updates:

- **CLAUDE.md** — remove the misleading "engine modules" framing. Replace with corrected description that all games run inline in `player.html` and `tv.html`.
- **docs/SESSION-5-PLAN.md** — update Part 3 entry to reflect actual scope shipped (which games, deferred items).
- **docs/ROADMAP.md** — mark Part 3 complete; advance "Next up" to Part 4 (proximity self-declaration UX, ~0-1 hr) or Part 5 (multi-user verification doc).
- **docs/DEFERRED.md** — file Part 3 deferred items per § 4.5.
- **docs/SESSION-5-PART-3-CLOSING-LOG.md** — closing log per the Part 2 pattern.

### 4.7 What this doc covers vs the audit doc

This Control Model is **prescriptive**: defines what Part 3 builds, what roles exist, how late-joiners flow per game, what manager controls do.

The companion `docs/SESSION-5-PART-3-AUDIT.md` is **descriptive**: documents what exists in `games/` today (state machines, message protocols, manager controls inventory, the dead-engine-modules finding). It's the ground-truth baseline that informs this Control Model's scope.

When implementation hits an architectural question this doc doesn't answer, check the audit first to see if the answer is in existing code.
