# Items 5 & 6 — Build Spec: Session Creation Becomes a Deliberate In-App Action

Status: BUILD-READY for review. This is a build spec — it defines WHAT
to build and the constraints, for a Claude Code implementation done
propose-pause. It does not itself contain code.

Grounded in two read-only investigations (cited inline as
"investigation" — the items 5/6 trace — and "code-read" — the
follow-up open-questions trace). All open questions from the original
draft are now RESOLVED — see §11. Where a build-time confirmation is
still required (a code fact to verify during implementation, not a
decision), it is marked **[BUILD-CONFIRM]**.

## 1. The problem

`ROOM-SESSION-MODEL.md` § "Tile-tap is navigation, not session creation"
is explicit: tapping an app tile must NOT create a room or session or
make the tapper a manager. The code contradicts this — `handleHomeTileTap`
→ `handleTvRemoteTileTap` calls `rpc_room_create` + `rpc_session_start`
on the tile tap (investigation Q1: the two creation lines are
`index.html:3199` and `:3215`; this is the ONLY session-creation path
for either app).

Two linked items:

- **Item 6** — tile-tap must stop creating sessions. Creation moves to a
  deliberate per-app in-app action.
- **Item 5** — karaoke's specific form of that action: tile-tap is
  navigation only; the user lands on a single "karaoke info" screen;
  clicking through that screen is the deliberate action that creates the
  karaoke session. No lobby (karaoke has no game-selection step).

These are two ends of one change — item 5 is item 6's karaoke-specific
fix. The games-side fix is also required (see §6) and lands in Phase 4.

## 2. Scope and phase placement

Per the Option-A decision: items 5/6 are explicit **Phase 3** scope
(`UNIFIED-APP-PLAN.md §5`). This spec REQUIRES an accompanying §5
amendment (see §9) — §5's current Phase 3 text does not mention
session-creation UX, and item 6's shell half has no phase home as
written.

- **Item 5 (karaoke info screen)** — Phase 3.
- **Item 6, karaoke half (tile-tap stops creating the karaoke session)**
  — Phase 3, coupled to item 5; they ship together.
- **Item 6, games half (tile-tap stops creating the games session +
  games' deliberate creation action)** — Phase 4. Specced in outline
  here (§6) so the shell change is coherent, but BUILT in Phase 4.

This spec's BUILDABLE scope is the **Phase 3 / karaoke** half plus the
**shell change** that both apps share. The games-side in-app creation
action is Phase 4 and is only outlined.

## 3. The core mechanical problem — the room_code anchor

(Investigation Q3 — the load-bearing finding.)

Today `rpc_room_create` generates the `room_code` and tile-tap injects
it into the navigation URL (`singer.html?code=…`, `player.html?room=…`,
and the TV's `stage.html?room=…`). Every downstream surface anchors on
that URL code: `singer.html`'s auto-join, `player.html`'s prefilled
join field, the TV's stage navigation.

If session creation is simply removed from tile-tap, the navigation URL
has no code and every entry path loses its anchor. Therefore item 6 is
NOT "delete the creation block." It is: **move session creation to the
in-app click-through, and re-thread how the room_code reaches the
surfaces** — because after the change, the room_code does not exist
until the in-app action fires.

This is the spec's central constraint. Every requirement below serves it.

## 4. What tile-tap becomes (the shell change — shared by both apps)

`handleTvRemoteTileTap` (`index.html`, ~3161–3338) currently: validates
device context → creates room → creates session → publishes
`session_started` + `launch_app` → navigates with the generated
room_code.

**After the change, tile-tap (Mode A, no active session) must:**

R4.1 — Validate the bound-TV device context (`device_key`,
`tv_device_id`) exactly as today.

R4.2 — NOT call `rpc_room_create` or `rpc_session_start`. NOT publish
`session_started` or `launch_app`. (The `rpc_session_start` /
`rpc_room_create` call sites move out of this function entirely.)

R4.3 — Stash, in `sessionStorage`, the `device_key` the in-app creation
action will need (already stashed today as `elsewhere.active_tv.device_key`
— no change). `tv_device_id` is NOT stashed and NOT to be added to the
stash: the in-app click-through RESOLVES `tv_device_id` from `device_key`
via the `from('tv_devices').select('id').eq('device_key', …).maybeSingle()`
pattern `stage.html` already uses (stage.html ~line 5387). [OPEN A
RESOLVED — resolve, not stash: matches the existing stage.html precedent,
keeps a single source of truth (the live `tv_devices` row, no staleness
window), needs no shell change. The ~50–300ms resolve cost is negligible
against a deliberate user tap.]

R4.4 — Navigate to the per-app surface WITHOUT a `room_code` (because
none exists yet): karaoke → `karaoke/singer.html` (no `?code=`).

**Unchanged paths — must NOT regress:**

- `handleSameAppRejoin` — does not create a session today (only
  `rpc_session_join`); it must continue to work for rejoining an
  existing session, navigating with the existing room_code.
- `handleCrossAppSwitch` — currently ends the old session
  (`rpc_session_end`), publishes `session_ended`, then tail-calls
  `handleTvRemoteTileTap`. After the change, the tail no longer creates
  a session. [OPEN B RESOLVED — code-read traced the function:]
  - The function has no per-app branching after `rpc_session_end`; it
    blindly tail-calls `handleTvRemoteTileTap(newApp)`. Under per-app
    gating (§6) the asymmetry is automatic: switching TO games (old
    path) still creates + navigates directly; switching TO karaoke (new
    path) navigates to `singer.html`'s info screen, and the user taps
    "Start Karaoke" to create.
  - This produces a DOUBLE-CONFIRM when switching to karaoke: the
    cross-app-switch confirm ("End X to start karaoke?"), then the
    info-screen "Start Karaoke" tap. This is INTENDED, not a regression
    — the two answer different questions ("abandon this session?" vs.
    the deliberate creation action). Making cross-app-switch bypass the
    info screen would re-introduce non-deliberate session creation,
    which Item 6 exists to eliminate. The build must not "fix" this.
  - Required: the room is NOT ended by `rpc_session_end` (post-db/025,
    only the session row gets `ended_at`; the room persists). So the
    karaoke info-screen click-through must REUSE the persisted/cached
    room rather than always calling `rpc_room_create` — it inherits the
    existing "reuse cached room or `rpc_room_create` new" pattern at
    `index.html` ~3186–3207. See §7.
  - **[BUILD-CONFIRM]** — verify cross-app-switch's tail behaves
    correctly under per-app gating: karaoke target → info screen; games
    target → old create path.
- Mode B / Mode C paths (silent no-op for karaoke Mode B; direct-nav for
  Mode C) — unchanged; they never created a session.

## 5. The karaoke info screen (Item 5)

R5.1 — A new screen state inside `karaoke/singer.html` — e.g.
`screen-karaoke-info`. It is a NEW SCREEN IN AN EXISTING SURFACE, not a
new file. (Investigation Q2: this mirrors how games has multiple screens
in `games/player.html`.)

R5.2 — `singer.html` loaded WITHOUT `?code=` defaults to
`screen-karaoke-info` — not to the existing `screen-join`. (Today an
un-coded load shows `screen-join` with the room-code input focused.)

R5.3 — `singer.html` loaded WITH `?code=` continues through the existing
join path (the auto-join IIFE → `doJoin` → `rpc_session_join`). The info
screen is the CREATION path; the `?code=` path is the JOIN/rejoin path.
The two must not interfere.

R5.4 — `screen-karaoke-info` content: a minimal, welcoming threshold
screen — brief informational copy about the karaoke experience and how
it works (the phone is the controller/mic, the TV is the stage) — plus
a single primary call-to-action labelled **"Start Karaoke"**. [OPEN D
RESOLVED — "Start Karaoke": plain human language, avoids the system
jargon of "session" and the slight overpromise of "Start Singing".]
No game selection, no lobby, no options — karaoke has one experience
and one button. Final copy is Phase 3 build detail. The screen has two
renderings — a TV-bound state (active CTA) and a no-TV-bound state
(§5.7).

R5.5 — The click-through on that CTA is the deliberate session-creation
action. It must:
  a. Resolve the creation inputs (see §7).
  b. Resolve or reuse the room: if a persisted/cached room for this
     screen already exists (e.g. after a cross-app switch — see §4
     `handleCrossAppSwitch`), REUSE it; otherwise call `rpc_room_create`.
     This is the existing "reuse cached room or `rpc_room_create` new"
     pattern at `index.html` ~3186–3207, relocated. Then call
     `rpc_session_start` — same parameters as tile-tap uses today
     (investigation Q3 confirmed all are available here: `p_app='karaoke'`,
     `p_ask_proximity=true`, `p_admission_mode`/`p_capacity` null,
     `p_turn_completion='app_declared'` — from `APP_MANIFEST.karaoke`).
  c. Publish `session_started` and `launch_app` — these MOVE here from
     tile-tap (investigation Q4: `publishLaunchApp` is sequenced with
     `rpc_session_start` and moves with it). `launch_app` carries the
     newly-generated `room_code` so the TV navigates to
     `karaoke/stage.html?room=<room_code>`.
  d. Transition `singer.html` internally to the active singer UI (the
     same UI state the post-`doJoin` flow reaches today).

R5.6 — Pre-click-through, `screen-karaoke-info` is a benign UI state:
no Agora connection, no session lookup, no role-aware rendering. Those
begin only after the click-through.

R5.7 — Mode C (no bound TV — no `device_key`/`tv_device_id`): the
click-through cannot create a session — there is no `tv_device_id` to
pass as the room's `screen_ref`. [OPEN E RESOLVED — code-read confirmed
a Mode C user has no `tv_device_id` from any source.] The Mode C
rendering of `screen-karaoke-info`: informational copy about karaoke,
plus a path to get a TV — a sign-in CTA if the user is unsigned, or
guidance to bind/claim a TV if signed-in-but-no-TV. It does NOT show an
active "Start Karaoke" CTA, because there is nothing to bind a session
to. This is consistent with today — Mode C never created a session.
(The fuller "scanned-screen sessions / baseline players with no TV
device" path from UNIFIED-APP-PLAN §5 Phase 3 is the eventual answer
for screenless karaoke, but it is separate Phase 3 work, not Item 5's
scope.)

## 6. The games half (Item 6, games) — OUTLINE ONLY, Phase 4

Built in Phase 4, not by this spec. Outlined so the shell change (§4) is
coherent for both apps.

(Investigation Q2: games has in-app screens — `screen-lobby` →
`screen-game-info` → `screen-game-room` — but they start a game ROUND
inside an already-created session; games has NO in-app session-creation
action. So games has the same item-6 problem as karaoke.)

O6.1 — Games needs a deliberate in-app session-creation action, the
games equivalent of the karaoke info-screen click-through. Where in
games' existing screen flow it sits is a Phase 4 design question.

O6.2 — The shell change in §4 applies to games identically: tile-tap
navigates to `games/player.html` with no `room_code`; games' in-app
action creates the session.

O6.3 — DECISION (OPEN C RESOLVED): **per-app gating.** The §4 shell
change is gated on `app`. Karaoke's tile-tap session-creation is removed
in Phase 3 (the karaoke info screen takes over). Games RETAINS tile-tap
session-creation until Phase 4 (when O6.1 ships games' own in-app
creation action). This means there is no window in which games is unable
to create a session — games stays on its current working path until its
Phase 4 conversion. No throwaway interim games creation action is built.
Rejected alternative: all-apps shell change in Phase 3 + a minimal
interim games action — rejected because it builds throwaway code and
forces both apps to convert in lockstep, contradicting UNIFIED-APP-PLAN
§5's separate Phase 3 (karaoke) / Phase 4 (games) sequencing.
**[BUILD-CONFIRM]** — confirm `handleTvRemoteTileTap` can gate the
session-creation block on `app` cleanly (the function already takes
`app` as a parameter and branches on it in its navigation tail, so this
is expected to be straightforward; verify during build).

## 7. Creation inputs at the click-through

(Investigation Q3.) `rpc_room_create({ p_screen_ref })` +
`rpc_session_start({ p_room_id, p_app, p_admission_mode, p_capacity,
p_ask_proximity, p_turn_completion })`.

- `p_app`, `p_admission_mode`, `p_capacity`, `p_ask_proximity`,
  `p_turn_completion` — constant for karaoke (the `APP_MANIFEST.karaoke`
  values); available trivially at the info screen.
- `auth.uid()` — required by `rpc_session_start`; available (Mode A
  precondition is a signed-in user).
- `p_screen_ref` = `tv_device_id` — NOT directly available in
  `singer.html`; RESOLVED from `device_key` at the click-through via the
  `from('tv_devices').select('id').eq('device_key', …).maybeSingle()`
  pattern `stage.html` uses (~line 5387). Per §4 R4.3 / OPEN A.
- `device_key` — needed for the resolve above and for `publishLaunchApp`;
  read from `sessionStorage` (`elsewhere.active_tv.device_key`, already
  stashed today).

## 8. Constraints and non-regressions

- The four `APP_MANIFEST.karaoke` parameter values must be identical to
  what tile-tap uses today — the session created by the info screen must
  be indistinguishable from the session tile-tap creates today.
- `rpc_room_create` / `rpc_session_start` themselves are NOT modified —
  this is a client-side relocation of WHERE they are called, not an RPC
  change. No db migration.
- The 23505 race handler currently in `handleTvRemoteTileTap`
  (investigation Q1 step 4; code-read A3) MOVES with the creation logic
  to the karaoke info-screen click-through. [OPEN F RESOLVED.] The
  handler is structurally wrapped around `rpc_session_start`, so it
  follows that RPC wherever it lives. Its branches all stay relevant and
  translate without semantic change: same-app (karaoke) race → rejoin
  the existing karaoke session and transition to the active singer UI;
  different-app race → alert and stay on the info screen; race-rare
  fall-through → generic error. Note: the race's mechanical window
  (`rpc_room_create`/room-reuse → `rpc_session_start`) is unchanged, but
  user-visible exposure is wider — a user can sit on the info screen for
  minutes before clicking, lengthening the gap between intent and the
  RPCs. The handler is therefore more important, not less, at the new
  call site. Without it, a losing-the-race user gets a raw Postgres
  duplicate-key error instead of a clean rejoin.
- The stale-SELECT degradation on `singer.html`/`stage.html` is a
  SEPARATE tracked DEFERRED item — not introduced or fixed by this spec.
- `publishLaunchApp` will have multiple callers post-Phase-3 (this
  click-through, and later the Immersive TV Tier 2 "TV button") —
  investigation Q4. Not a constraint on this spec, but the implementation
  should not assume a single caller.
- Phase 2 (db/032, `venue-settings.js`, `venue-registry.js`) is
  untouched — confirmed by the investigation.

## 9. Required accompanying doc edits

This spec REQUIRES, as part of the same workstream:

D9.1 — `UNIFIED-APP-PLAN.md §5` amendment (the Option-A decision): add
session-creation UX as explicit Phase 3 scope. [OPEN G RESOLVED — the
amendment is ADDITIVE; existing Phase 3 / Phase 4 text stays verbatim.]

Add, as a sub-bullet under §5's Phase 3 entry:

> Phase 3 also includes karaoke's deliberate in-app session-creation
> action: tile-tap becomes navigation only, and a new in-app "karaoke
> info" screen's click-through is the action that creates the session —
> per ROOM-SESSION-MODEL.md § "Tile-tap is navigation, not session
> creation," which the current shell code contradicts. The shell-side
> change (removing session creation from tile-tap) is gated per-app:
> karaoke converts here in Phase 3; games converts in Phase 4.

Add, as a clause to §5's Phase 4 entry:

> ...and games gains its own deliberate in-app session-creation action
> (the games-side counterpart to karaoke's Phase 3 change), completing
> the per-app removal of session creation from tile-tap.

The amendment is delivered as a propose-pause Claude Code doc edit:
Claude Code first prints §5 verbatim (to confirm the exact bullet style
and best insertion point), then proposes the diff. The doctrine source
cited (ROOM-SESSION-MODEL.md) frames this honestly — §5 was incomplete
(it never allocated an implementation slot for that adopted rule), not
wrong.

D9.2 — The `IMMERSIVE-TV-DESIGN-MODEL.md` §13 "three Phase 3 gates"
already names items 5/6 — once §5 is amended, §13's framing and §5 agree.
No edit needed beyond confirming consistency.

## 10. Interlock with Immersive TV Tier 1

(Investigation Q4 — confirmed clean.) Items 5/6 change WHICH code path
publishes `launch_app`; Immersive TV Tier 1 changes WHO can become a TV.
They share the `tv_device:<device_key>` channel as substrate but operate
at different layers and are compatible. The migration of
`publishLaunchApp`'s caller (shell → in-app click-through) is invariant
to whether the TV was claimed via iOS (Tier 0) or web (Tier 1).

No coordination constraint beyond: both the Tier 1 spec and this spec
touch entry/navigation; whichever builds second should re-verify the
other's surface still behaves. This is a review note, not a blocker.

## 11. Resolved decisions (was: open questions)

All open questions from the original draft are resolved. Record:

- **OPEN A** (§4 R4.3) — `tv_device_id` is RESOLVED from `device_key` at
  the click-through, not stashed. Matches the stage.html precedent.
- **OPEN B** (§4) — cross-app-switch keeps its structure; under the new
  model its tail no longer creates a session, so a switch to karaoke
  lands on the info screen (a deliberate second action — intended, not
  a regression). Room is reused, not re-created.
- **OPEN C** (§6 O6.3) — per-app gating: karaoke converts in Phase 3,
  games retains tile-tap creation until Phase 4. No interim broken
  state, no throwaway code.
- **OPEN D** (§5 R5.4) — CTA label "Start Karaoke"; minimal threshold
  screen.
- **OPEN E** (§5 R5.7) — Mode C `screen-karaoke-info` shows info copy +
  a path to get a TV, no active "Start Karaoke" CTA.
- **OPEN F** (§8) — the 23505 race handler moves to the click-through
  with `rpc_session_start`.
- **OPEN G** (§9 D9.1) — the §5 amendment is additive; wording fixed in
  D9.1.

Remaining **[BUILD-CONFIRM]** items (code facts to verify DURING
implementation, not decisions):
- §4 / §6 — confirm `handleTvRemoteTileTap` gates the creation block
  per-app cleanly.
- §4 — confirm cross-app-switch's tail behaves correctly under per-app
  gating (karaoke target → info screen; games target → old path).

## 12. Build sequence (proposed)

1. §5 amendment (D9.1) — propose-pause doc edit. (All design opens are
   resolved per §11; the only remaining items are [BUILD-CONFIRM] code
   facts, verified inline during the build below.)
2. Build the shell change (§4) — per-app-gated so karaoke converts now,
   games stays on the old path until Phase 4. Verify the two
   [BUILD-CONFIRM] items here.
3. Build the karaoke info screen (§5) in `singer.html`.
4. Verify: karaoke entry end-to-end (tile-tap → info screen →
   click-through → session created → singer UI + TV stage), rejoin path,
   cross-app-switch (incl. the intended double-confirm), Mode B/C.
5. Games half (§6) — Phase 4, separate.
