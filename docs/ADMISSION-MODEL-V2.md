# Admission Model v2 — canonical design

**Created:** 2026-05-15
**Status:** Locked design. Supersedes parts of `docs/GAMES-CONTROL-MODEL.md`
(see § 9 for the supersession map). Implementation deferred to a separate
plan doc once this design is approved.
**Scope:** Games only. Karaoke is decoupled (see § 2.4).

---

## 1. Why this exists

A diagnostic pass on 2026-05-15 surfaced that the existing admission_mode
framework is structurally broken and that several adjacent product gaps
have been latent in the model:

- `admission_mode` is stamped per-app at session-create time
  (`index.html:3100-3103`), keyed by `app` not by game. Every Games
  session is stamped `self_join` regardless of which game inside Games
  the user actually plays. Last Card 3c code (HEAD = `c58923e`) is
  shipped but unreachable in production because the schema says
  `self_join` while the dispatcher's wait_for_next branch is the only
  Last Card path. Trivia 3b works in production by accident — its
  spec'd admission_mode happens to match the shell stamp.
- Karaoke selects `admission_mode` from the sessions row but never
  reads it. The karaoke flow is hardcoded in `karaoke/singer.html`
  with `rpc_karaoke_song_ended` for the active↔queue rotation. The
  schema value `manager_approved_single` is documentation only.
- The four admission_mode values (`self_join`, `wait_for_next`,
  `manager_approved_single`, `manager_approved_batch`) do not cleanly
  describe the behavior space. They mix "who lets people in"
  (self vs manager) with "how players rotate" (batch vs single vs
  none) with "what happens at capacity" (overflow modal vs queue
  vs none).
- No spectator view of live game state exists for any game. Audience
  users land on `screen-game-room` (Trivia + Last Card) or get
  dragged onto the active screen with broken render (Euchre,
  dispatcher stubbed). The "QR-code spectator view" in
  `docs/GAMES-CONTROL-MODEL.md` § 2.9 is mentioned but not built.
- No self-leave RPC, no tab-close cleanup. The only `left_at` setter
  is the manager's Remove Player action. Tab-close = silent ghost
  in the roster forever.
- `managerNextRound` (`games/player.html:3232`) freezes `s.players`
  at game-start and never re-reads. Queued users are invisible to
  round-transition logic. Section C of Last Card 3c as planned
  (auto-promote + manager picker) would not function correctly
  without first refactoring this function.

The simplification adopted: **two admission modes (open, gated),
three explicit role states (active, queued, audience), per-game
manifest stamped at game-start, Games-only scope.** Karaoke is
explicitly carved out and remains on its current hardcoded flow;
unifying it into this framework is future work.

The model also introduces Leave and Pause as first-class user
actions, addresses implicit-exit cleanup, and collapses the
admission-mode-specific late-joiner surfaces into a single
`screen-game-room`-centric flow.

---

## 2. The two-mode model

Games sessions run in one of two admission modes. The mode determines
how new participants enter the active set and how between-round
transitions resolve.

### 2.1 open

Anyone in the session can join as active immediately. Late-joiners
flow into the active state on join. Users may toggle themselves to
audience at any time; they may toggle back to queued or active
freely (subject to whether the game is mid-round).

No manager approval is required at any point. No capacity limit.
Trivia is the only `open` game today.

### 2.2 gated

The manager controls who plays. Late-joiners default to queued in
the game-room. The active set changes only between rounds, via the
manager-driven Select Players flow (see § 5).

Capacity applies. Last Card and Euchre are `gated`.

### 2.3 Where admission_mode lives

`admission_mode` is a per-game property, not a per-app property. It
is stamped onto the `sessions` row at game-start time — when the
manager taps Start Game on `screen-game-info` — and cleared on
Switch Game.

- Definition: per-game constant in a new `GAME_MANIFEST` object in
  `games/player.html` (see § 6 for values).
- Persistence: written to `sessions.admission_mode` via a new
  manager-only RPC `rpc_session_set_admission_mode(p_session_id,
  p_admission_mode, p_capacity)`. Capacity travels with the mode
  because the two are jointly determined per game.
- Lifecycle: set on game-start; cleared on Switch Game (back to the
  game picker); re-set on next game's Start Game.

### 2.4 What `APP_MANIFEST` in `index.html` becomes

Today (`index.html:3100-3103`) `APP_MANIFEST` stamps four manifest
values per app onto the sessions row at `rpc_session_start` time.
Under this model, `admission_mode` and `capacity` move per-game, so
the shell manifest is reduced to:

| Field | Karaoke | Games |
|---|---|---|
| `ask_proximity` | `true` | `false` |
| `turn_completion` | `app_declared` | `app_declared` |

`admission_mode` and `capacity` are not stamped at session-create
time. For Games sessions they are set per-game at game-start. For
karaoke sessions they remain unset at the schema level and karaoke
continues to ignore them.

### 2.5 What `sessions.admission_mode` is during the lobby window

Between session creation and game-start, `admission_mode` has no
defined value. Implementation may model this as either:

- **Nullable column** — relax the existing NOT NULL constraint and
  the CHECK constraint to accept NULL.
- **Placeholder value** — extend the CHECK list to include a new
  value such as `'lobby'` or `'pending'`, and use it as the
  pre-game-start default.

Either approach works; the design does not mandate one. The
implementation plan picks one (see OQ1, § 11). The CHECK constraint
update is required either way.

The dispatcher fallback at `games/player.html:2202` (today
`const mode = currentSession?.admission_mode || 'self_join'`) is a
known bug under any choice — it silently routes lobby-state audience
users to the Trivia choice screen. Implementation work item W3 fixes
this by gating the entire admission-mode switch on `gameInProgress`,
not on the value of `admission_mode`.

### 2.6 Karaoke explicitly out of scope

Karaoke does not read `admission_mode` anywhere. Its admission flow
is hardcoded in `karaoke/singer.html` and `karaoke/stage.html`,
backed by `rpc_karaoke_song_ended` (`db/013`). The schema value
`manager_approved_single` is documentation only.

This design does not touch karaoke. The model parameters (open/gated,
active/queued/audience) are not applied to karaoke surfaces. The
karaoke spec at `docs/KARAOKE-CONTROL-MODEL.md` remains the
authoritative reference for karaoke admission.

Future work may unify karaoke into a generalized framework that
accommodates its per-entry pre-selections, take-stage confirmation,
Stop ≠ End Turn semantics, idle-state venue tour, and song-end
rotation. That generalization is out of scope here and would be a
separate spec.

---

## 3. The three-role model

The `participation_role` enum preserves three existing values —
**active**, **queued**, **audience** — and refines their semantics
to match the two-mode admission model. No rename of enum values is
required; the W1 migration adds `wanting_since` and drops
`queue_position`, but the enum stays as-is.

### 3.1 active

The user is in the current round. Receives game-state broadcasts.
Has a hand / question view / bidding UI as appropriate. Their name
appears in `s.players` (the game-state players list).

### 3.2 queued

The user wants to play but is not in the current round. This is
the default for late-joiners in gated games who haven't expressed
a preference, and for previous-round players who keep Play Again
checked on the score screen (see § 5.1). For open games,
late-joiners default directly to active; queued is used only in
gated games as the canonical "between rounds, in line for the
next one" state.

### 3.3 audience

The user is opted into audience-only status — wants to watch, not
play. Sticky: once in audience, they stay across game-end
transitions unless they explicitly toggle into queued (or active
in `open` games).

Watchers see `screen-game-room` with the active-round audience copy
(see § 4). They do not see live game state. The QR-code spectator
path remains the separate product story per `docs/GAMES-CONTROL-MODEL.md`
§ 2.9.

### 3.4 Queue ordering for queued users

A new column `session_participants.wanting_since` (timestamp) records
the moment a user entered the queued state. The queued list is
ordered by `wanting_since` ascending — oldest first at the top.

Concrete example: a user who joined the session 30 minutes ago
without playing a round yet outranks a user who just finished Round 1 and
opted in to Round 2 via Play Again.

Manager has full discretion in the Select Players flow (§ 5.2);
ordering is a hint, not a hard rule. A manager may skip the
top-of-list user if they have a reason (the user just stepped away,
the manager wants to balance team composition, etc.).

### 3.5 How queued's semantics change

Before this design, `'queued'` was a Last Card-specific state
tracked via `session_participants.queue_position` and pinned to
`screen-lastcard-queue`. The dispatcher auto-promoted queued users
via Section C's planned (unshipped) flow.

Under this design, `'queued'` is the canonical "wants to play,
waiting for next round" state for all gated games. The
queue-vs-audience distinction in the previous model collapses:
queued users and audience users share `screen-game-room` as their
non-playing surface; the only difference between them is intent
(queued = wants to play, audience = wants to watch) and ordering
(queued ordered by `wanting_since`, audience unordered).

`queue_position` is no longer used; ordering is by `wanting_since`
instead. The column is dropped in W1.

### 3.6 Schema migration required

A new migration (file `db/0XX_role_model_v2.sql`, number determined
at implementation time) is required to:

- Add `wanting_since timestamp with time zone` column on
  `session_participants`, nullable.
- Drop `queue_position` column.
- Drop the partial unique index that referenced `queue_position`
  (defined in `db/008:127-128`).
- Update the `sessions.admission_mode` CHECK constraint and NOT
  NULL constraint per § 2.5: relax to allow NULL, restrict
  values to `'open'`, `'gated'` (transition any existing rows
  with old values).

The migration also requires coordinated updates to every RPC that
references the `sessions.admission_mode` value as a string
literal — the four old values (`'self_join'`, `'wait_for_next'`,
`'manager_approved_single'`, `'manager_approved_batch'`) collapse
to the two new values (`'open'`, `'gated'`). The specific RPC
surfaced by the diagnostic is `rpc_session_self_promote_from_queue`
in `db/011:378`; others may surface during migration drafting.

---

## 4. Game-room is the single shared surface

`screen-game-room` hosts all three role populations during all
session states. The dedicated late-joiner surfaces introduced in
Trivia 3b and Last Card 3c are retired.

### 4.1 The three sections of `screen-game-room`

- **Active (lobby state only):** Users in the active state during
  the lobby window — before the round starts. Once the round starts,
  active users navigate to the per-game active screen
  (`screen-trivia` / `screen-lastcard` / `screen-euchre`) and are
  not on `screen-game-room` anymore.
- **Queued:** Ordered list by `wanting_since` ascending. Visible
  to all users in the session (including the user themselves if
  they're queued). The manager's Select Players view (§ 5.2)
  presents this list with checkboxes; non-managers see it
  read-only.
- **Audience:** Separate section, no specific ordering. Visible to
  all users. Watchers stay here through the entire session unless
  they explicitly transition.

### 4.2 Retired screens

The following surfaces are deleted under this model. Their DOM is
removed from `games/player.html`, their CSS entries are removed
from the `<style>` block, and their referenced handler functions
are deleted or replaced:

- `screen-lastcard-queue` (added in Last Card 3c Section A, commit
  `6bec79c`) — superseded by the queued section of game-room.
- `screen-trivia-late-choice` (added in Trivia 3b Section A, commit
  `c8317da`) — superseded by default queued-on-join + the explicit
  participation toggle on game-room.
- `screen-watching` (legacy, present since before Session 5) — kept
  only until Euchre 3d work retires its cold-join dependency, then
  deleted alongside that work.

### 4.3 Active-round behavior for queued and audience

When a round is in progress (`gameInProgress = true`), queued and
audience users on `screen-game-room` see a static "Round in progress"
header at the top of the screen plus the three sections (with
themselves listed in queued or audience). They do not see live
game state — no questions, no cards, no bidding. The active-round
view is reserved for users in the active state.

Spectator-of-live-state remains a separate product story; per
`docs/GAMES-CONTROL-MODEL.md` § 2.9, the intended path is a QR
code on the game-room that, when scanned by another device,
launches a spectator surface displaying the games TV experience.
That spectator surface is not specified here.

### 4.4 Game-end behavior on game-room

When a round ends and the game-over event broadcasts, all users
return to `screen-game-room` (or `screen-gameover` if the
implementation chooses a separate end-of-round screen; see § 5.1).
Active users from the just-ended round have their role flipped per
§ 5.1; queued and audience users see their role unchanged.

For `gated` games, the manager-only Select Players affordance
surfaces here (or on `screen-gameover`; see OQ4, § 11).

---

## 5. Game-end flow (gated games only)

This section defines the between-rounds flow for `gated` games. Open
games (Trivia) do not use this flow — late-joiners and previous-round
players in Trivia can self-toggle into active or audience freely.

### 5.1 Score screen

On round-end, all users land on the score screen (`screen-gameover`,
or equivalent). The score screen shows final scores for the
just-ended round plus a per-user Play Again checkbox.

**Play Again checkbox semantics:**

- Defaulted ON for previous-round players (those who finished in
  the active state).
- Not shown for watchers — watchers are not candidates for the
  next round; their role is sticky.
- Queued users (who weren't in the just-ended round) see the
  checkbox in their default-on state. Their wanting_since is
  unchanged.

**State transitions on Play Again interaction:**

When a previous-round player keeps Play Again checked:
- Role flips from `active` to `queued`.
- `wanting_since` set to `now()`.
- They join the queue at the bottom (latest wanting_since).

When a previous-round player unchecks Play Again:
- Role flips from `active` to `audience`.
- `wanting_since` is null (watchers don't have one).

The timing of the role flip — at score-screen close, at game-end
broadcast, at checkbox interaction — is OQ2, § 11. The doc does
not mandate the timing; implementation chooses.

### 5.2 Manager Select Players surface

Manager-only affordance on `screen-game-room` after the round ends.
The recommended placement is `screen-game-room` (so the manager
sees the queued list in context with the audience list and the
just-ended scores); `screen-gameover` is the alternative. OQ4
captures the choice.

**Entry point:** Button labeled "Select Players for Next [game]"
where [game] is the human-readable game name. Visible to the
manager only. Appears once the round has ended and Play Again
responses are settled.

**Surface layout when tapped:**

The queued list renders with checkboxes, ordered by `wanting_since`
ascending (oldest first). For Last Card, the playerLimit (capacity)
is shown alongside as context.

**Affordances:**

- **Per-user checkbox:** Toggle a queued user into the next-round
  selection set. Checking is up to capacity; once capacity is
  reached, additional checkboxes are disabled with a "Capacity
  reached" hint.
- **Select All:** Selects all queued users up to capacity. If the
  queued count exceeds capacity, Select All still selects all and
  surfaces a capacity-adjustment prompt: "Capacity is X — increase
  to Y to include everyone?" The manager can confirm (capacity
  bumps to the new value, applies to this game's session row, and
  the selection set includes all queued users) or trim selection
  manually back down to current capacity. The capacity-adjustment
  prompt UX (modal, inline, auto-adjust) is OQ5.
- **Start Next Round:** Applies the selection. Fires
  `rpc_session_update_participant` per selected user (or a batch
  RPC; OQ8) to flip their role from `queued` to `active`.
  Unselected queued users stay queued (see § 5.3). Broadcast
  `game-start` (or per-game equivalent) follows; selected users
  navigate to the per-game active screen.
- **Cancel:** Returns to game-room with no role changes.

### 5.3 What happens to unselected queued users

They stay queued. Their `wanting_since` is unchanged — they do not
get re-stamped just because a round happened. They remain at the
top of the queued list (assuming they were among the oldest) for
the next round-end's Select Players flow.

This is what "they move up in the order" means in practice — they
were already near the top of the list by virtue of being older
queued entries, and they stay there. They do not regress in the
queue because they weren't picked.

### 5.4 No auto-promote

Unlike the superseded Section C of Last Card 3c, there is no
auto-promote at round-end. The manager always taps Select Players
to make the selection explicit. The reasoning:

- Manager intent is the source of truth in `gated` games. The
  Select Players surface gives manager control without forcing
  them through a multi-step picker only when capacity overflows.
- Always-on Select Players removes the conditional UX (overflow
  modal vs auto-promote) and replaces it with a single consistent
  flow.
- Capacity adjustment is folded into the same surface, so the
  manager handles overflow inline rather than as an exceptional
  case.

---

## 6. Per-game manifest

A new `GAME_MANIFEST` object in `games/player.html` (location and
exact shape determined at implementation time, but conceptually
keyed by game id) defines per-game properties:

### 6.1 Trivia

| Field | Value |
|---|---|
| `admission_mode` | `'open'` |
| `capacity` | `null` (unlimited) |
| `leave_impact` | `'no_impact'` |
| `pause_behavior` | `'pause_not_applicable'` |

### 6.2 Last Card

| Field | Value |
|---|---|
| `admission_mode` | `'gated'` |
| `capacity` | `6` (default; 2-8 range, manager-tunable on `screen-game-info`) |
| `leave_impact` | `'no_impact'` |
| `pause_behavior` | `'pause_skips_turn'` |

### 6.3 Euchre

| Field | Value |
|---|---|
| `admission_mode` | `'gated'` |
| `capacity` | `4` (fixed) |
| `leave_impact` | `'terminates_game'` |
| `pause_behavior` | `'pause_freezes_game'` |

### 6.4 `leave_impact` values

| Value | Semantics |
|---|---|
| `'no_impact'` | Notify other players ("[name] left"); game continues without the user. Their `active` row flips per § 7.2. |
| `'terminates_game'` | Notify other players; game ends for everyone. Broadcast `game-over` with reason `'user_left'`. The user's row flips per § 7.2. |

### 6.5 `pause_behavior` values

| Value | Semantics |
|---|---|
| `'pause_skips_turn'` | Paused user's turn auto-skips when it would be theirs; they resume on their next natural turn after unpausing. Others continue uninterrupted. |
| `'pause_freezes_game'` | Entire game freezes; manager may unpause; if paused user doesn't resume and won't unpause, manager must End Game. |
| `'pause_not_applicable'` | No pause action available for this game; the Pause button is not surfaced. |

### 6.6 Future extensibility

The manifest shape is intentionally narrow. Additional fields may
be added per future game requirements (e.g., a hypothetical
`turn_timer` field if a future game has shot-clock semantics). The
schema does not encode the manifest; it is a client-side constant
that informs runtime behavior and is stamped onto `sessions` at
game-start as needed.

---

## 7. New first-class user actions

This model introduces three new actions on game surfaces. Each
surfaces conditionally based on the per-game manifest.

### 7.1 Pause (active game surfaces)

A button on `screen-lastcard` / `screen-euchre` / `screen-trivia`,
visible to active users only. The button is hidden entirely when
the game's `pause_behavior` is `'pause_not_applicable'` (Trivia
today).

**Behavior branches on `pause_behavior`:**

`'pause_skips_turn'` (Last Card):
- The paused user's row in `session_participants` gets a paused
  flag (or equivalent; schema choice deferred to implementation).
- Other players' UIs show "[name] is paused" indicator next to
  their avatar.
- When the turn would be the paused user's, the round logic
  auto-advances past them (similar to existing Skip action,
  scoped to the paused user).
- The paused user remains in `active` role; their turn resumes
  naturally on their next turn after they unpause.
- Unpause: tap the same button (now labeled Unpause / Resume).

`'pause_freezes_game'` (Euchre):
- A whole-game overlay appears for all users: "Game paused —
  waiting for [name]."
- All play is frozen; no turn advances; no cards play.
- Manager may also tap Unpause to override.
- If the paused user does not resume and won't unpause, the
  manager must End Game (no auto-recovery).

`'pause_not_applicable'` (Trivia):
- Pause button is not rendered on `screen-trivia`. The action is
  absent from the user's vocabulary for this game.

### 7.2 Leave (active game surfaces)

A button on `screen-lastcard` / `screen-euchre` / `screen-trivia`,
visible to all active users. The button is always available
regardless of `leave_impact`.

**On tap, a confirmation dialog appears with copy branched on
`leave_impact`:**

`'no_impact'` (Trivia, Last Card):
> "Leave the game? Others will continue."

`'terminates_game'` (Euchre):
> "Leave the game? This will end the game for everyone."

**On confirm:**

Update the user's row. Schema choice (deferred to implementation,
see OQ in § 11 covered by W9): either set `left_at = now()` (audit
trail preserved) or flip `participation_role` to `'audience'`. The
doc notes a preference for `left_at = now()` because it preserves
the audit trail and matches the existing Remove Player semantics
in `db/016`. Either way, the user is no longer active.

**For `'terminates_game'` games:**

Broadcast `game-over` with `reason: 'user_left'` and the leaver's
name. All remaining users see a game-over screen with a special
treatment indicating the termination reason (specific UX is OQ7,
§ 11) instead of the normal score-then-Play-Again flow.

### 7.3 Implicit leave detection

Tab close and network disconnect should be treated equivalent to
explicit Leave for the game's `leave_impact` value.

**Mechanism (high-level only; implementation specifics deferred):**

- `beforeunload` and `pagehide` handlers on game surfaces (and
  ideally `screen-game-room` as well) fire a best-effort
  `rpc_session_leave` call before the page unloads. These handlers
  must be synchronous-friendly; the standard pattern is
  `navigator.sendBeacon` to a Supabase endpoint or an in-flight
  RPC that's tolerated to fire-and-forget.
- Heartbeat-based cleanup as backstop for ungraceful exits where
  `beforeunload`/`pagehide` did not fire (browser crash, force-quit,
  network drop). Implementation: a periodic ping from each client
  updating their row's `last_heartbeat_at` (new column); a
  server-side cleanup job (cron or trigger) acts on stale rows where
  `last_heartbeat_at < now() - threshold` by applying the same
  mechanism as explicit Leave per § 7.2 (preferred: `left_at = now()`).

The specific heartbeat cadence, cleanup interval, and
implementation mechanism (Edge Function, pg_cron, trigger-based)
are OQ3, § 11.

Relevant prior art: `docs/DEFERRED.md` entries on participant
cleanup and on inactivity-based manager reclaim describe earlier
thinking around heartbeat infrastructure for related concerns.

---

## 8. Manager affordances summary

### 8.1 Existing manager affordances (preserved)

These remain unchanged under the new model:

- **Remove Player** — per-row button in roster, manager-only.
  Calls `rpc_session_remove_participant`. Sets target's `left_at`.
  (No change.)
- **End Session** — whole-session end. Calls `rpc_session_end`.
  Marks `sessions.ended_at`. All clients navigate away.
- **Switch Game** — broadcasts the `switch-game` Agora event,
  client-side state change. Under the new model, also fires the
  new `rpc_session_set_admission_mode` to clear admission_mode
  (or set to lobby placeholder per § 2.5).
- **Start Game** — per-game Start button on `screen-game-info`.
  Under the new model, also fires `rpc_session_set_admission_mode`
  with the per-game manifest's admission_mode and capacity.
- **Next Round / Play Again** — per-game next-round button. For
  `gated` games, the manager affordance changes: instead of "Next
  Round →" auto-using the previous players, the flow goes through
  Select Players (§ 5.2).
- **Manager-as-player toggle** — own row only. Visible on
  `screen-game-room`. Updates via `rpc_session_update_participant`
  with self-target.

### 8.2 New manager affordances

- **Select Players for Next [game]** — gated games only, between
  rounds. See § 5.2.
- **Pause / Unpause game** — gated games with
  `pause_behavior = 'pause_freezes_game'` only (Euchre).
  Manager-side override of the user-pause from § 7.1.
- **Capacity adjustment prompt** — surfaces from within Select
  Players when Select All exceeds capacity (§ 5.2).

### 8.3 Manager affordances NOT introduced

This design does not introduce a generic "move user from
audience/audience to queued/active" affordance. Manager
intervention on other users' role state remains scoped to:
Remove Player (force-remove) and Select Players (gated games,
between rounds only). The manager does not have a "force-promote"
or "force-demote" affordance outside those two surfaces.

---

## 9. What this design supersedes

This section maps the design against the existing
`docs/GAMES-CONTROL-MODEL.md` and identifies what's obsolete,
updated, or unchanged. The corresponding edits to that doc happen
in a follow-up commit after this design is approved.

### 9.1 § 2.4 (active/audience cluster)

**Update.** The active/audience binary is expanded to a clearer
three-role model using existing schema values: active (in the
current round), queued (wants to play, waiting), audience
(explicitly watching only). The previous design's vocabulary
trap (where 'audience' meant both schema-state and surface-label)
is resolved by treating queued as the canonical "waiting to
play" state for gated games, separate from audience. Default
role on join differs by admission mode: open games default
late-joiners to `active` immediately (no manager step); gated
games default late-joiners to `queued` in the game-room.
Audience members in both modes are users who explicitly toggle
into watching.

### 9.2 § 2.8 (admission modes and capacity)

**Update.** The four admission modes (`self_join`, `wait_for_next`,
`manager_approved_single`, `manager_approved_batch`) collapse to
two (`open`, `gated`). Karaoke is documented as
hardcoded-not-using-this-framework rather than as a
`manager_approved_single` consumer.

The capacity section is updated to reflect that capacity travels
with admission_mode at game-start time, not at session-create
time. Per-game capacity values are documented in this design's § 6.

### 9.3 § 3.1 (Trivia spec)

**Update.** `admission_mode: 'self_join'` → `admission_mode: 'open'`.

The late-joiner choice screen (Trivia 3b Section A) is removed.
Late-joiners default to active on join; users may toggle into
audience via the existing participation toggle on `screen-game-room`.

The dispatcher's Trivia-specific branch (Trivia 3b Section B)
collapses into the two-mode dispatcher. The Skip Question wiring
(Trivia 3b Section C) is unaffected — it's a manager control, not
admission logic.

### 9.4 § 3.2 (Last Card spec)

**Update.** `admission_mode: 'wait_for_next'` → `admission_mode: 'gated'`.

The queue surface (`screen-lastcard-queue`, Last Card 3c Section A)
is removed. Queued users live in the queued section of
`screen-game-room`, ordered by `wanting_since`.

Section C of Last Card 3c (auto-promote + manager picker UI) is
**superseded** by the Select Players for Next [game] flow
(§ 5.2). The implementation work for Section C as previously
scoped is replaced by the work item W6.

Last Card capacity remains manager-tunable on `screen-game-info`
with the same 2-8 range and 6 default.

### 9.5 § 3.3 (Euchre spec)

**Update.** `admission_mode: 'manager_approved_batch'` →
`admission_mode: 'gated'`. The Section 3.3 manager-approved-batch
flow is replaced by the same Select Players flow used for Last Card.
Euchre's capacity stays at 4 (fixed). `leave_impact: 'terminates_game'`
is introduced for Euchre per § 6.

Hand-end seat-filling picker UI (originally specified for Euchre 3d)
is superseded by the Select Players flow. Force Trump Call
(mentioned as possible 3d scope) is unaffected by this design and
remains a separate item.

### 9.6 § 4.1 (Part 3 implementation breakdown)

**Update.** The 3b/3c/3d work items are restructured. The shared
admission-mode-specific dispatcher logic collapses to one
two-mode dispatcher (W3); per-game work items focus on per-game
state machines, scoring, and Pause/Leave UI. The Select Players
flow (W6) is shared across Last Card and Euchre.

### 9.7 § 2.5 (Remove Player affordance)

**No change.** Remove Player stays as a manager affordance with the
same RPC and semantics.

### 9.8 § 2.9 (Audience role + TV-experience-via-QR)

**No change to the QR spectator path itself.** The audience role
semantics are preserved as they exist in the schema today. The QR
spectator view remains the intended path for live spectator
experience and is unaffected by this design.

### 9.9 Cross-references

This design references but does not modify:

- `docs/KARAOKE-CONTROL-MODEL.md` — karaoke decoupled per § 2.6.
- `docs/PHONE-AND-TV-STATE-MODEL.md` — device/TV state model
  unaffected.
- `docs/DEFERRED.md` — implementation work item W10 covers
  marking obsolete entries Resolved or Superseded.

---

## 10. Implementation scope (high-level only)

The work items below enumerate the scope inventory. They are not a
plan, not an ordering, not an estimate. Actual session planning,
ordering, dependencies, and estimates live in a separate plan doc
to be created when implementation begins.

### W1 — Schema migration

New migration `db/0XX_role_model_v2.sql` (number determined at
implementation time):

- Add `wanting_since timestamp with time zone` column on
  `session_participants`, nullable.
- Drop `queue_position` column.
- Drop the partial unique index that referenced `queue_position`
  (defined in `db/008:127-128`).
- Update the `sessions.admission_mode` CHECK constraint and NOT
  NULL constraint per § 2.5: relax to allow NULL, restrict values
  to `'open'`, `'gated'` (transition any existing rows with old
  values).
- Update referenced RPCs to use the two new admission_mode string
  literals: `rpc_session_self_promote_from_queue` in `db/011:378`
  is the specific RPC surfaced by diagnostics; others may surface
  during drafting.

No `participation_role` enum rename; the existing values
(`active`, `queued`, `audience`) are preserved.

### W2 — Per-game manifest + game-start admission stamping

In `games/player.html`:

- New `GAME_MANIFEST` object with per-game values per § 6.
- New manager-only RPC `rpc_session_set_admission_mode(p_session_id,
  p_admission_mode, p_capacity)` in a new migration file.
- `managerStartLastCard` / `managerStartTrivia` / `managerStartEuchre`
  call the new RPC before broadcasting `game-start` to stamp the
  per-game admission_mode and capacity onto `sessions`.
- `managerSwitchGame` calls the RPC to clear admission_mode (or
  set to lobby placeholder per § 2.5) on switch.

### W3 — Dispatcher refactor

In `games/player.html`:

- Replace the four-mode switch in `handleAudienceGameStateArrival`
  with a two-mode switch (open / gated).
- Fix the `|| 'self_join'` fallback bug at line 2202: gate the
  entire admission-mode switch on `gameInProgress` instead of
  silently defaulting to a game mode.
- Retire the dispatcher's queued-role early-return (queued role
  no longer exists).
- Retire `screen-trivia-late-choice` and `screen-lastcard-queue`
  DOM, CSS, and handler functions.
- Update `doJoin` cold-join routing: late-joiners always go to
  `screen-game-room` (no more per-admission-mode routing).

### W4 — Game-room updates

In `games/player.html`:

- Add queued and audience sections to `screen-game-room`'s
  roster rendering (`renderRoster` update).
- Order queued section by `wanting_since` ascending.
- Active-round audience copy at the top of game-room ("Round in
  progress" or equivalent) when `gameInProgress = true`.

### W5 — Score screen Play Again

In `games/player.html` (and possibly `games/tv.html` if TV mirrors
the score screen):

- Per-user Play Again checkbox on `screen-gameover` (or equivalent),
  defaulted ON for previous-round players.
- Role flip on Play Again interaction per § 5.1, with
  `wanting_since` update (timing per OQ2).
- Hide Play Again checkbox for watchers.

### W6 — Manager Select Players surface

In `games/player.html`:

- New "Select Players for Next [game]" button on `screen-game-room`
  (or `screen-gameover` per OQ4), manager-only, gated games only.
- Surface with queued list + checkboxes ordered by
  `wanting_since`.
- Select All affordance with capacity-adjustment prompt for
  overflow.
- Start Next Round applies role flips via per-row or batch RPC
  (OQ8), then broadcasts `game-start` or per-game equivalent.

### W7 — `managerNextRound` refactor

In `games/player.html`:

- Drop the `s.players` freeze pattern.
- Re-read `currentParticipants` filtered to `active` role at
  every round-start.
- Integrate with the Select Players output (W6) so the selected
  set becomes the new round's `s.players`.

### W8 — Pause + Leave UI on game surfaces

In `games/player.html`:

- Pause button on `screen-lastcard` / `screen-euchre`, visible
  to active users when the game's `pause_behavior` is not
  `'pause_not_applicable'`. Behavior branches per § 7.1.
- Leave button on `screen-lastcard` / `screen-euchre` /
  `screen-trivia`, visible to active users. Confirmation
  dialog with copy branched per `leave_impact` per § 7.2.
- For `'pause_skips_turn'`: integrate paused state with turn
  advancement (Last Card).
- For `'pause_freezes_game'`: whole-game overlay + freeze logic
  (Euchre).
- For `'terminates_game'` Leave: broadcast `game-over` with
  `reason: 'user_left'`.

### W9 — Implicit leave detection

Likely touches `games/player.html` plus a new server-side
mechanism (Edge Function, pg_cron, or trigger):

- `beforeunload` + `pagehide` handlers firing best-effort
  `rpc_session_leave` (new RPC) or `navigator.sendBeacon`.
- Heartbeat infrastructure: client-side periodic ping;
  server-side cleanup job. Specifics per OQ3.

### W10 — Cleanup

Across multiple files:

- `index.html`: shrink `APP_MANIFEST` per § 2.4 (drop
  `admission_mode` and `capacity`; keep `ask_proximity` and
  `turn_completion`).
- `docs/DEFERRED.md`: mark obsolete entries Resolved or
  Superseded. Items related to the old queued role,
  admission-mode-specific dispatcher branches, and old
  late-joiner surfaces likely all qualify.
- `docs/SESSION-5-CLOSEOUT-PLAN.md`: restructure items
  obsoleted by this design (Section C of Last Card 3c, the
  late-joiner surfaces of both 3b and 3c, the 3d as-scoped
  work). The restructure happens in a follow-up after this
  design is approved.
- `docs/GAMES-CONTROL-MODEL.md`: apply the supersession edits
  documented in § 9.

---

## 11. Open questions for implementation time

Captured here to prevent loss. The implementation planning
session resolves them; they are NOT answered in this design.

### OQ1 — `sessions.admission_mode` during lobby window

NULL with relaxed NOT NULL + CHECK constraint, or placeholder value
(e.g., `'lobby'`)? Schema choice, small impact, both work.

### OQ2 — `wanting_since` update timing

At game-end broadcast, at score-screen close, or at the user's
Play Again checkbox interaction? Each has slight ordering
differences for users who tap quickly vs slowly.

### OQ3 — Implicit leave heartbeat cadence + cleanup interval

How often does each client ping? How often does the cleanup job
run? What's the staleness threshold for flipping a row to a left
state? Standard infrastructure question with usability and DB-load
tradeoffs.

### OQ4 — Score screen vs game-room placement for Select Players

The Select Players button could live on `screen-gameover` (so the
manager sees scores then picks) or on `screen-game-room` (so the
manager sees the full session roster context). UX call.

### OQ5 — Capacity adjustment from Select All

When Select All exceeds capacity, is the prompt a modal, an
inline banner, or auto-adjustment with notification? UX call.

### OQ6 — Sticky audience status across sessions

If user A is audience in Session 1 and Session 1 ends, what's
their default status in Session 2 (a new session in the same
household)? Probably `queued` (fresh session, fresh defaults),
but worth confirming explicitly.

### OQ7 — `leave_impact='terminates_game'` UX during game-end

When a user leave triggers game-over with `reason: 'user_left'`,
does the remaining players' screen show "Game terminated by
[name] leaving" vs the normal score screen? UX call.

### OQ8 — Select Players batch role-update mechanism

Single RPC call with a list of user_ids and the target role
('active'), or per-row loop with the existing
`rpc_session_update_participant`? The loop pattern is simpler;
the batch RPC reduces realtime traffic (one publish vs N publishes).
Implementation choice.

### OQ9 — Gated games with capacity=1 future consideration

If karaoke ever unifies into this framework with `gated, capacity=1`,
does Select All make sense (selects the one user, trivially)? Or
does the Select Players UI need a special-case for capacity=1?
Future-consideration only; not relevant to Games today.

---

## 12. Relationship to existing in-flight work

This section documents how shipped and planned work intersects with
this design. The existing commits do not need to be reverted; W3 +
W6 retire the obsoleted code as part of the implementation pass.

### 12.1 Last Card 3c (currently HEAD = `c58923e`, v2.118)

| Commit | Section | Status under new model |
|---|---|---|
| `6bec79c` (v2.117) | A — `screen-lastcard-queue` + handlers | **Superseded.** The screen and its handlers are deleted under W3. The `joinLastCardAsQueued` / `joinLastCardAsAudience` / `rejoinLastCardQueue` / `renderLastCardQueuePosition` helpers are removed alongside. |
| `c58923e` (v2.118) | B — dispatcher wait_for_next branch + cold-join queue routing | **Superseded.** The wait_for_next branch is removed under W3 (two-mode dispatcher). The cold-join `wantsQueued` check in `doJoin` is removed; cold-joiners always go to `screen-game-room`. |
| _(unshipped)_ | C — auto-promote + manager picker at round-end | **Superseded by Select Players flow (§ 5.2).** Implementation work shifts to W6 + W7. |

The shipped Section A + B code stays in place until W3 + W6 retire
it. No immediate rollback.

### 12.2 Trivia 3b (currently HEAD ahead = `35daf82`, v2.116)

| Commit | Section | Status under new model |
|---|---|---|
| `c8317da` (v2.114) | A — `screen-trivia-late-choice` + handlers | **Superseded.** The screen and handlers are deleted under W3. |
| `4af4428` (v2.115) | B — `handleAudienceGameStateArrival` dispatcher + self_join branch | **Refactored.** The function survives but is rewritten to two-mode dispatch under W3. The self_join branch is removed. |
| `35daf82` (v2.116) | C — Skip Question wiring + `applyTriviaManagerButtonVisibility` | **Unaffected.** Skip Question is a manager control, not admission logic. Stays as-is. |

The Trivia 3b code mostly survives; the choice screen and its
dispatcher branch retire under W3.

### 12.3 Section 5 closeout plan (`docs/SESSION-5-CLOSEOUT-PLAN.md`)

| Item | Status under new model |
|---|---|
| Day 1 item 1 — v2.113 verification | Complete; unaffected. |
| Day 1 item 2 — iOS Capacitor sync | Complete; unaffected. |
| Day 1 item 3 — Trivia 3b proper | Partially obsoleted. Choice screen retires; Skip Question + dispatcher work survives (rephrased per § 9.3). |
| Day 2 — Last Card 3c | Substantially restructured. Section A + B shipped code retires under W3; Section C as scoped is replaced by W6 + W7. |
| Day 3 — Euchre 3d | Scope changes to use the new gated flow (§ 5.2). The originally-scoped manager-approved-batch admission work is replaced by the same Select Players flow Last Card uses. |
| Day 4 — Euchre 3d finish + Part 4 + prep Part 5 | Restructured; Euchre piece per above. Part 4 + Part 5 prep unaffected. |
| Day 5 — Part 5 verification + Session 5 close | Largely unchanged; verification flows may need updates to reflect new role names and surfaces. |

The closeout plan needs reframing after this design is approved.
That reframing happens in a follow-up commit, alongside or after
the GAMES-CONTROL-MODEL.md supersession edits.

### 12.4 What can ship in the meantime

Until W1-W10 are implemented, the existing shipped code (Trivia 3b
A/B/C, Last Card 3c A/B) continues to run with the known issues
documented in earlier diagnostics:

- Last Card 3c paths are unreachable in production due to the
  shell admission_mode stamping bug.
- Trivia 3b paths work in production by accident.
- Audience users have no live spectator view in any game.
- No self-leave, no tab-close cleanup.

These remain known issues; the new model resolves them collectively
once implemented. No partial implementation of this design is
intended — W1 (schema rename) in particular is a coordinated
single-deploy because it touches every consumer of the
`participation_role` enum.

---

## End of design

The next steps after this doc is approved:

1. Apply supersession edits to `docs/GAMES-CONTROL-MODEL.md` per § 9.
2. Restructure `docs/SESSION-5-CLOSEOUT-PLAN.md` per § 12.3.
3. Create a separate implementation plan doc that schedules W1-W10,
   resolves the open questions in § 11, and estimates effort. The
   plan doc is the entry point for actual implementation work.
