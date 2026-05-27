# Unified-App / NHHU-Primary Plan

Status: Adopted (planning complete). This is the umbrella document for the
unified-app workstream. It carries the capability model, the locked
decisions, the per-app experience breakdown, the implementation sequencing,
and the open items.

Companion documents (the detailed models):
- ROOM-SESSION-MODEL.md — the room / session / group entity model
- ROOM-AUTHORITY-MODEL.md — the manager authority model
- ROOM-ACCESS-INVITE-MODEL.md — the room-access / invite model
- HOUSEHOLD-DEVICE-PRESENCE-MODEL.md — households, TV devices, presence,
  and the immersive capability

Read this document first for the whole picture; the companions for detail.

## 1. The reframe

The existing Elsewhere docs treat an at-home household user (HHU) as the
primary user, and a non-household user (NHHU) as the constrained case.

This workstream inverts that. The primary user is any registered Elsewhere
user, with no TV device required. Every app must work for that user as a
primary participant — never relegated to a separate "audience" surface. A
TV device becomes an immersive capability layer on top of a complete
experience, not a gate to it.

In some situations NHHUs, or HHUs who are not at home, get a deprecated
experience compared to an immersive user present at a TV — but not a wholly
different one.

Scope: this workstream refactors KARAOKE and GAMES. Wellness and Worlds are
greenfield — they do not exist as runtime surfaces yet and will be built
against the finished model afterward. When wellness is built, its baseline
experience is venue navigation on a screen, consistent with the capability
model — explicitly NOT the camera-gated wellness model described in the
superseded PHONE-AND-TV-STATE-MODEL.md.

## 2. The capability model

### Baseline tier — every registered user, no TV device required

- Full access to every app as a primary participant.
- Can drive a screen — paired or scanned (see below) — to navigate venues,
  start content, manage the experience.
- Sees and uses all the app's core controls.

### Immersive tier — a user present at an embed-capable screen

- Everything baseline, plus the camera-composite capability: being
  composited into the venue, and costume overlays.
- Immersive is exactly this one capability. It is identical across all apps.

Immersive is defined by a physical situation — a user is connected to a TV
device whose `tv_devices.can_embed` is true AND has declared presence at
that device. It is derived, not stored — there is no account-level
entitlement. Whose TV it is doesn't matter; household membership doesn't
gate it. The full model for households, TV devices, binding, presence, and
immersive activation is in HOUSEHOLD-DEVICE-PRESENCE-MODEL.md.

### Two ways a screen is driven

- Paired screen — a TV device claimed to a household.
- Scanned screen — any screen, driven by any user who scans its QR code, no
  household pairing required.

A "TV experience" no longer implies a claimed TV device.

### "Audience" is a mode, not a class

In the new model, "audience" is not a class of user and not a separate
surface. It is an opt-in, reversible mode (participation_role = audience)
that any user may choose — watching rather than playing — and leave. The
separate audience.html surface is dissolved; its function becomes
baseline-tier watcher mode within the main app.

## 3. Locked decisions

1. Immersive-A is the workstream's immersive capability — a user present
   at the TV with embed-capable hardware, which the architecture already
   supports. Immersive-B (remote self-insertion via a phone camera) is
   deferred as a separate future feature. See section 7.

2. A net-new rooms table is committed. The session entity splits into a
   durable rooms container and a disposable per-app sessions instance.
   (Detail: ROOM-SESSION-MODEL.md.)

3. The one-engagement rule is per-user-global: a user may be a member of
   many rooms but actively engaged in only one at a time.

4. Manager / TV-owner authority split: a household admin controls the
   screen — they may evict a room from their own TV, setting screen_ref to
   null — but they do not gain manager authority over the gathering.

5. Saved rooms do not auto-update from live rooms. When a room spawned from
   a saved room diverges, the manager is prompted to persist the change or
   keep the template unchanged.

6. Manager authority splits into room control (operational, fully
   transferable) and room ownership (personal, never transfers by
   succession). (Detail: ROOM-AUTHORITY-MODEL.md.)

Two further design decisions, in the access model:
- Invite role is inferred per-app, not stored on the invite.
- Invites are single-use.
(Detail: ROOM-ACCESS-INVITE-MODEL.md.)

## 4. Per-app experience — the four-quadrant breakdown

For karaoke and games, the experience across baseline/immersive x player/
watcher.

Two framing points:
- "Watcher" is a mode any user opts into, not a lesser tier.
- Immersive is camera-composite while performing — so an "immersive watcher"
  has the capability but nothing to act on; it collapses into baseline
  watcher. The real matrix is three live cells per app, not four.

### Karaoke — how users are placed

When a user enters karaoke, they are placed by their immersive/presence
state (see HOUSEHOLD-DEVICE-PRESENCE-MODEL.md):

- A user bound to an embed-capable TV with presence declared is placed as
  a potential singer. In the manager's view they are shown distinctly, so
  the manager can see these users can be embedded into the venue.
- A user not bound to an embed-capable TV (or bound but not present) is
  placed in audience mode by default — they cannot be embedded, so they
  are not put in the singer track automatically.

An audience-mode user may still ask to join the singing queue. The first
time such a user does so, the manager is prompted with a one-time
session-level choice: allow non-immersive / not-present users to join the
queue — yes or no. If yes, such users may queue for the rest of that
session; the manager retains the existing skip and remove controls. If no,
they remain audience-only.

### Karaoke — the immersive-restricted session

The karaoke manager may restrict singing to immersive-present users for a
session. In a restricted session:

- Only immersive-present users may be in the singing queue.
- Audience-mode users (non-immersive, or immersive-not-present) cannot join
  the queue at all — the one-time queue-approval prompt above does not
  apply; the restriction overrides it.
- Audience-mode users retain full access to the rest of the app: they can
  search for songs, and search and view venues and costumes. They are shown
  a message that singing is restricted to immersive users, with a path to
  obtain a TV device.

So karaoke has two manager-controlled modes: unrestricted (audience users
may be allowed into the queue at the manager's one-time discretion) and
restricted (singing is immersive-present only).

### Karaoke — the quadrants

- Baseline player — a non-immersive or not-present user who has been
  allowed into the queue: drives a screen, picks and changes venues,
  searches songs, queues, sings. Not composited into the venue.
- Immersive player — an immersive-present user: as baseline, plus
  composited into the venue and costume overlays. Every control is
  identical to baseline; immersive adds visual presence only.
- Baseline watcher — a user in audience mode: sees and hears the room's
  karaoke, is a room member, not in the queue. Same app, reversible mode.
  This is what replaces the old audience.html.
- Immersive watcher — no distinct experience; dormant capability, equals
  baseline watcher until the user switches to playing.

### Games

- Baseline player — full games for any user; closest to games today, which
  is already TV-independent.
- Immersive player — forward-looking: camera-insertion + costumes for games
  depends on venues being introduced into games, a separate future
  workstream. Empty until then by absence of the venue substrate.
- Baseline watcher — a user in the games room who has opted to watch.
- Immersive watcher — empty (no venues yet, and watching anyway).

### What the breakdown shows

- "Immersive watcher" is not a real quadrant in either app.
- Immersive is a thin, consistent layer — the same one capability in both
  apps, on the player track only.
- Karaoke's cells are describable now; games' immersive column is
  forward-looking. Karaoke is a refactor target; games' immersive tier is a
  later feature.

## 5. Implementation sequencing

**Numbering note.** "Phase N" in this document refers exclusively to this migration sequencing — the dependency-ordered phases listed below. The repo contains unrelated "Phase N" references that are not phases of this plan: Session 5 Part 3b's session-internal "Trivia Phase 2" (the 2026-05-04 premium AI-questions track) and product-roadmap items such as Elsewhere Kids and social-publish. Do not cross-reference numbering schemes.

Order is dependency-firm; sizing is directional.

- Phase 0 — investigation. Complete.
- Phase 1 — the room/session foundation. Create rooms; demote sessions;
  re-anchor session_participants to room_id; migrate the room-aware RPCs;
  rework the shell's "active session for this TV" state model to "room and
  its current session." screen_ref nullable lands here. Clean-slate
  migration (see section 6). The keystone — everything downstream depends
  on it.
- Phase 2 — venue extraction. Pull venue rendering out of the karaoke
  stage into a shared shell renderer; make the venue registry cross-app.
  Prerequisite for "navigate venues" being a baseline experience in any
  app. Can overlap Phase 1. **Closed 2026-05-24:** as-built design in
  `docs/PHASE-2-BUILD-SPEC.md` (revision 3 at close), which broadened
  Phase 2 from a literal panorama-extraction into a complete cross-app
  venue abstraction; see that spec's §1 for the supersession of the
  original three-part DEFERRED breakdown ("Venues as cross-app service").
  The abstraction ships dormant — no live consumer until Phase 3.
- Phase 3 — karaoke onto the new model. Scanned-screen sessions; baseline
  players driving venues and the queue with no TV device; audience.html
  dissolved into baseline watcher mode. Depends on Phases 1 and 2.
  Phase 3 also includes karaoke's deliberate in-app session-creation
  action: tile-tap becomes navigation only, and a new in-app "karaoke
  info" screen's click-through is the action that creates the session
  — per ROOM-SESSION-MODEL.md § "Tile-tap is navigation, not session
  creation," which the current shell code contradicts. The shell-side
  change (removing session creation from tile-tap) is gated per-app:
  karaoke converts here in Phase 3; games converts in Phase 4. **Plan B
  amendment (2026-05-26):** Phase 3 also folds in the **venue translation**
  (procedural `AMBIENT_PROFILES` + `addVenueEffects3D` in
  `karaoke/stage.html` → data-driven `venue_anchors` + reusable shell
  renderer impls) AND the **Part-1 admin UI** (`admin-venues.html`,
  manage the existing 26 venues) as the authoring/preview tool that
  mitigates the translation risk. Authoritative sequencing:
  `docs/VENUE-ADMIN-UI-DIRECTION.md` (Plan B, reverses the earlier
  wrap-as-legacy framing) + `docs/VENUE-ADMIN-UI-A1-BUILD-SPEC.md` §7
  (the A1–A8 staging — audio first, then particle, then spotlight,
  then `AMBIENT_PROFILES` retirement; followed by Block B's karaoke
  reader-path rewire). Part 2 of the admin UI (create brand-new venues
  with asset-generation pipelines) remains post-Phase-5 per Decision 2
  of VENUE-ADMIN-UI-DIRECTION.md §3.
- Phase 4 — games onto the new model. Conformance, not rebuild: re-anchor
  to the room/session split, adopt the unclaimed-screen path, unify
  cross-app-switch behavior, and games gains its own deliberate in-app
  session-creation action (the games-side counterpart to karaoke's
  Phase 3 change), completing the per-app removal of session creation
  from tile-tap. Depends on Phase 1; independent of Phase 3.
- Phase 5 — rooms / groups / cross-app movement. The user-facing room
  layer: multi-room, groups-as-saved-rooms, the cross-app move, manager/
  screen authority. Depends on Phase 1 and on Phases 3-4 existing.
- Then — wellness and worlds, built greenfield against the finished model.

The room-access / invite layer is not a single phase — its pieces land at
their dependency points: the invite schema and Edge Function after Phase 1;
invite policy with Phase 5; the registration / conversion path after
Phases 3-4.

### Refactoring load

- Karaoke is a heavy transformation — the app the workstream exists to
  change. It touches Phases 1, 2, 3, and 5.
- Games is a moderate conformance pass — already close to the target
  model. It does not get its immersive tier in this workstream.
- Both share the Phase-1 schema migration. The frozen participant row
  shape keeps the ~50 control_role reader sites stable, so the churn is
  concentrated in schema and RPCs, not client read sites.

## 6. Phase-1 execution worklist

The Phase-1 migration is a CLEAN-SLATE cutover: existing session and
participant data is cleared as a migration pre-step; the schema migrates
against empty session tables. No backfill, no historical-data preservation.
This removes the backfill and constraint-violation risk a live-data
migration would carry. It is appropriate because session/participant data
is ephemeral and pre-launch — nothing of value is lost.

The migration (db/025, following the established ALTER + backfill
idempotent migration pattern, though backfill is now a no-op): clear the
session tables; drop the dead rpc_session_promote_self_from_queue (retired
since admission-model v2); create rooms; add room_id to sessions and
session_participants; create the room-scoped indexes.

RPC worklist — roughly 14 distinct RPCs (after accounting for
create-or-replace supersession), in two groups:

- Mechanical (~8) — re-point the filter column from session_id to room_id;
  no logic change. Includes join, get_participants, remove_participant,
  heartbeat, set_my_participation_role, update_queue_position,
  update_participant, karaoke_song_ended.
- Semantic (~6) — logic changes at the room/session boundary. Includes
  rpc_session_start (the largest — must split room-resolution from
  session-creation, since a durable room is not recreated on every app
  entry), rpc_session_end (its participant-sweep stops — participants
  belong to the room now), rpc_session_leave (succession logic — see
  below), the two reclaim-manager RPCs, and set_admission_mode (cleanest —
  stays session-scoped).

RLS — keep session-keyed helpers as compatibility wrappers; add room-keyed
siblings (is_room_participant, is_room_tv_household_member,
is_room_tv_household_admin). Update the sessions and session_participants
SELECT policies.

Shell — roughly 13 sites in the shell's active-session state cluster
re-point from "session for the bound TV" to "room and its current session."
The cross-app-switch authority check moves to reading the room's manager,
which is the correct level for it. The shell UI also gains a
low-prominence room-code-entry affordance (a place to type a code and
join — see ROOM-ACCESS-INVITE-MODEL.md "Room code as a secondary entry
path"), included in Phase 1 so it does not get lost in later phases.

Confirmed fact — current_state has zero writers anywhere in the codebase;
it is dormant scaffolding and carries no data. The room/session refactor
need not migrate it.

Manager-role amendment — the execution-scope investigation was run before
the manager control/ownership split was decided. As a result: rooms needs
both a controller reference and an owner reference (not a single
manager_user_id); and rpc_session_leave plus the two reclaim RPCs must
distinguish control-transfer from ownership, which never auto-transfers.

Known implementation-vs-doctrine gap — the current rpc_session_leave
selects a successor by join order (joined_at). The adopted succession rule
is "longest continuously-present non-audience participant" (see
ROOM-AUTHORITY-MODEL.md). The Phase-1 rpc_session_leave rewrite must change
this selection logic, not merely re-point its filter column.

## 7. Immersive-B — deferred, with no-foreclose notes

Immersive-B (a remote user composited into a venue via their own phone
camera) is deferred. Investigation found B splits in two:
- B-narrow (one remote singer) is close to a routing change — the karaoke
  composite pipeline already accepts an arbitrary video element, and the
  remote stream already arrives at the stage. Karaoke only ever has one
  singer, so B-narrow is the whole karaoke remote-self-insertion story.
- B-wide (N concurrent remote composites) is genuinely new architecture.

To keep B-narrow cheap to build later, the refactor should: keep the
composite pipeline's input decoupling intact (do not re-couple it to a
local camera); preserve the "this stream is the active performer"
distinction; resolve the feasibility unknowns opportunistically; and write
the extracted venue renderer's input contract source-agnostic.

### Technical starting points for B-narrow

B-narrow is deferred to be picked up later, likely by someone without this
investigation's context. These concrete findings let that work start from
the answer rather than re-investigating:

- The karaoke composite pipeline is already decoupled from its own camera
  (the DeepAR disableDefaultCamera flag) — it is fed a video element. This
  decoupling is the load-bearing asset; it must not be undone.
- The pipeline's input is set through a single coupling point
  (setVideoElement) — swapping the input is, mechanically, a change at one
  site.
- The remote singer's video already arrives at the stage as an Agora
  videoTrack (today routed to a side video tile, not the composite). The
  raw material for B-narrow is already present.
- Three unknowns remain, resolvable only by DeepAR documentation or a
  hands-on spike: (a) whether the SDK accepts a runtime input swap;
  (b) whether it accepts the Agora-produced video element; (c) whether
  camera publish behaves correctly on the karaoke build of the Agora SDK.

## 8. Open items

- The screen-by-screen four-quadrant breakdown verified against current
  surfaces — not yet produced; wanted at the start of Phase 3.

- A Phase-1 execution-scope investigation should be re-run once the target
  schema (rooms + invite-table changes + the manager controller/owner
  split) is fully fixed, as the final check before db/025 is written.

- CLAUDE.md is stale regarding tv2.html — it describes Agora watchers, but
  tv2.html now uses Supabase realtime broadcast (no Agora). A repo
  correction, not a model change: CLAUDE.md should be updated.

- Email and SMS invites can produce duplicate accounts. If a person
  registers with an existing email or phone, that is correctly handled as a
  sign-in (see ROOM-ACCESS-INVITE-MODEL.md). But a person registering with
  a DIFFERENT identifier than a prior account (email one time, phone
  another) creates a second account — the system cannot tell it is the same
  person. An account-merge capability is an undesigned future need.

- The broader payments / premium-paid-services model is undesigned. The
  two-wallet rule (HOUSEHOLD-DEVICE-PRESENCE-MODEL.md section 9) is the one
  decided constraint within it.

- Automatic presence detection (Bluetooth / ultrasonic) is a possible
  future enhancement that would remove the "are you home?" prompt
  (HOUSEHOLD-DEVICE-PRESENCE-MODEL.md section 7).

- Multi-use invite links are out of scope; the invite table is single-use
  shaped. Revisit only if multi-use becomes a genuine need.

- PHONE-AND-TV-STATE-MODEL.md is superseded by
  HOUSEHOLD-DEVICE-PRESENCE-MODEL.md. If a future reader finds content in
  the superseded doc that appears dropped rather than deliberately
  replaced, it should be raised against the new model.

- Room codes are a secondary, low-prominence entry path; invites are
  primary. Both must be visible in the shell UI, but the room-code-entry
  affordance is visually subordinated. See ROOM-ACCESS-INVITE-MODEL.md
  "Room code as a secondary entry path" for the model, and §6's shell
  paragraph for the Phase-1 implementation hook.

## 9. Status

Planning is complete. The locked decisions, the four companion models, and
this plan constitute the workstream design. The next action is execution,
beginning with the Phase-1 migration.

## 10. Shell tile state — per-user per-app

The shell home screen renders an app tile for each app (karaoke, games,
wellness, future). Each tile may carry a state signal — a badge — that
reflects the signed-in user's relationship to that app. This section
specifies the badge vocabulary, the data sources behind each signal, the
precedence between signals when multiple apply, and what is buildable in
which phase.

This section SUPERSEDES the tile-state material in
`docs/PHONE-AND-TV-STATE-MODEL.md` ("Three rendering modes" through "Tile
state matrix"). That doc was written before the room/session model and
keys tile state to the bound TV; this spec keys tile state to the user.
PTSM retains its TV-side and home-screen-shell material — only the tile-
state subsection is superseded.

**Scope.** This section specifies the VISIBLE BADGE STATE only — what
appears on each tile. Tap behavior is governed by
`docs/ROOM-SESSION-MODEL.md` ("Tile-tap is navigation, not session
creation") and is not re-specified here.

### 10.1 The shift: bound-TV-keyed → per-user per-app

The current implementation (`index.html:2310-2353`, the `renderHomeTiles`
+ `applyHomeTileState` pair landed in Session 5 Part 2c.3.1 and reshaped
to the nested `{session, room}` cache in §F Part 2) renders one signal
per tile: *"does the bound TV have a session in this app?"* When yes:
the tile gets the `.active-session` class, label = `"Active Session"`,
sub = the app's default label.

This is correct for the pre-room-model world where a user had at most
one session, attached to one TV. Under the room/session model
(`docs/ROOM-SESSION-MODEL.md`), a user has unlimited multi-room
membership across apps and a single global engagement at a time — and
the tile can express more than just the bound-TV state. The badge
becomes per-user per-app.

The mechanism stays: `renderHomeTiles()` orchestrator,
`applyHomeTileState(tile, app, mode, active)` per-tile applier,
`TILE_DEFAULT_COPY` for the default labels. What changes is the input
domain — `active` (a single bound-TV cache) widens to include the
user's cross-app participant rows.

### 10.2 Signal vocabulary

Four signals are recognized. They are listed in order of urgency from
most-to-least; precedence ties resolve in §10.3.

#### Signal C — Turn imminent

**Meaning.** The signed-in user is queued in an active session in this
app and their turn is approaching (the queued→active promotion the push-
notification path already triggers via `db/029`'s `fire_promotion_push`).

**Badge.** A high-visibility marker on the tile — e.g. a small "Up next"
pill, or a pulse on the tile. Exact visual is design work; the spec
requires that this signal is unambiguously the most-prominent of the four
when it fires.

**Data source.** `session_participants` row where `user_id = me AND
participation_role = 'queued' AND left_at IS NULL`, JOIN-ed via `room_id`
to `rooms` where `app = X` and the room's current session has `ended_at
IS NULL`. The queue-position field (or the push-trigger event) can further
gate "imminent" vs. "queued but distant" if desired.

**Phase-buildable.** ⚠️ Phase 3 (karaoke) at earliest — the queue concept
is karaoke-first in the current product. Games' queue model is different
(participation toggles, not a karaoke-style ordered queue) and may not
need this signal. Wellness has no queue concept defined. The data is on
hand — the `db/029` trigger payload already carries `room_id` — so the
missing piece is the shell-side reader.

#### Signal B — Engaged

**Meaning.** The signed-in user is currently participating in a session
in this app. Per the one-engagement rule, this signal fires for AT MOST
ONE app tile globally — a user is "engaged" in one room at a time, period.

**Badge.** Tile label reads e.g. `"You're in a session"` (or similar);
the tile carries a distinct class (e.g. `.engaged`). Visually distinct
from Signal A (bound-TV session) and Signal D (other-room session) —
the user should be able to tell at a glance "this is what I'm doing
right now."

**Data source.** `session_participants` row where `user_id = me AND
left_at IS NULL`, JOIN-ed via `room_id` to `rooms` where `app = X` and
JOIN-ed via the room's current session ID to `sessions` where `ended_at
IS NULL`. The room/session model defines engagement as
*(member of room) AND (room has active session)*; the query reads both
predicates.

**One-engagement-rule respect.** The query may return rows for >1 app in
edge cases (the rule is UX-enforced, not DB-enforced — see ROOM-SESSION-
MODEL.md §108-119). If that happens, the badge picks the most-recently-
joined row (by `session_participants.joined_at desc LIMIT 1`) and surfaces
Signal B on that single app's tile only. Other apps fall through to
lower-precedence signals. This is graceful degradation, not silent — the
in-app prompt (the one-engagement transition prompt) handles correction.

**Phase-buildable.** ⚠️ Phase 3 at earliest — needs the cross-app
participants query in the shell. Until then, Signal A (bound-TV session)
covers the engaged case for the bound-TV scenario, which is the common
case.

#### Signal A — Bound-TV session

**Meaning.** The bound TV is running a session in this app. The signed-in
user may or may not be a participant — this signal is about the TV, not
the user. It exists for backward compatibility with the pre-room-model
behavior and remains the primary signal for the common Mode A case
(at-home user looking at their own TV's home screen).

**Badge.** Today's behavior — `.active-session` class, label = `"Active
Session"`, sub = the app's default label (per `TILE_DEFAULT_COPY`).
Visually distinct from Signal B (engagement) — Signal A says "there's a
session here," Signal B says "you're in it."

**Data source.** Already implemented. `getActiveSession()` returns
`{session, room}` for the bound TV (the `_activeSessionForBoundTv`
nested cache from §F Part 2); the predicate is `active.session?.app ===
app` per `applyHomeTileState`'s line at `index.html:2336`.

**Phase-buildable.** ✅ Already shipped (Phase 1, §F). No new data
source needed.

#### Signal D — Other-room session

**Meaning.** The signed-in user is a member of one or more rooms in this
app that have active sessions, EXCEPT the bound TV's session (which is
covered by Signal A). This is the multi-room awareness signal — "you
have a karaoke room going at your friend's house while you're standing
in your own living room."

**Badge.** Low-prominence indicator — e.g. a small dot or count on the
tile (`•` or `2`). Strictly less prominent than Signal A. Tapping
behavior (which room is targeted by the in-app navigation) is governed
by `docs/ROOM-ACCESS-INVITE-MODEL.md` and the in-app room list, not by
this signal.

**Data source.** `rooms` where `app = X AND ended_at IS NULL`, JOIN-ed
via `session_participants` where `user_id = me AND left_at IS NULL`,
EXCLUDING any room whose ID equals `active.room?.id` (the bound TV's
room, if any).

**Phase-buildable.** ⚠️ Phase 5 (rooms / groups / cross-app movement)
at earliest — multi-room concept lands in Phase 5 per §5. Until then,
this signal is absent and tiles fall through to Signal A or default.

### 10.3 Signal precedence

When multiple signals apply to the same tile, the highest-priority signal
controls the visible badge. Lower-priority signals may render as
secondary visual elements (e.g. a count dot alongside a Signal-B label),
but their primary signal is suppressed.

Precedence order (highest first):

1. **Signal C — Turn imminent.** Actionable urgency overrides everything.
2. **Signal B — Engaged.** Fires on at most one tile globally (one-
   engagement rule). When B fires on a tile, A and D are suppressed on
   that same tile.
3. **Signal A — Bound-TV session.** The pre-room-model default. Fires
   when the bound TV has a session in this app and Signal B has not
   fired for the same app.
4. **Signal D — Other-room session.** Fires when none of A/B/C apply
   for this tile but rooms outside the bound TV have active sessions
   in this app.
5. **Default.** No signal. Tile shows the `TILE_DEFAULT_COPY` label and
   sub.

Mode A/B/C from PTSM (now superseded for tile state, retained for header
and proximity-banner concerns) still influences `.greyed` state on
TV-required apps: Mode B karaoke tile greys when no Signal A/B/C/D
applies. The FLAG-3 precedence rule from today's `applyHomeTileState`
holds: any active signal overrides `.greyed` because the tile is
tappable in that state regardless of proximity.

### 10.4 Buildability per phase

| Signal | Phase | Status | What unlocks it |
|---|---|---|---|
| A — Bound-TV session | 1 | ✅ Shipped | `getActiveSession()` reads the nested cache from §F Part 2. |
| B — Engaged | 3+ | ⚠️ Not built | Cross-app `session_participants` query in the shell. |
| C — Turn imminent | 3+ | ⚠️ Not built | Shell reader of the queued state; karaoke-first. Push-trigger payload already carries `room_id` (db/029). |
| D — Other-room session | 5 | ⚠️ Not built | Multi-room concept lands in Phase 5; cross-app `rooms` query. |

The recommended build order matches §5's phase sequencing — A is in
place, B and C land with Phase 3 (karaoke onto the new model) where the
shell gains its first reason to read cross-app participant state, and D
lands with Phase 5 when multi-room becomes a first-class concept.

### 10.5 Wellness

Wellness has no sessions, rooms, queues, or participants today —
`docs/UNIFIED-APP-PLAN.md` §5 lists wellness as built greenfield "after"
the model is finished. The wellness tile renders the default copy
("Coming soon") and no signal fires until the wellness app introduces
sessions and rooms. The spec scales naturally: when wellness gets rooms,
the same signal vocabulary applies.

### 10.6 Tap behavior — out of scope

Tap behavior on a tile is NOT specified by this section. Per
`docs/ROOM-SESSION-MODEL.md` § "Tile-tap is navigation, not session
creation", tile-tap is navigation into the app; session and room
creation are deliberate in-app actions. The shell tile is the door; the
in-app create action is the threshold. Per-signal tap dispatch (rejoin
vs. join-as-audience vs. start-fresh vs. confirm-cross-app-switch)
remains the implementation's concern, governed by the room/session model
and the dispatchers already in `index.html` (`handleHomeTileTap`,
`handleSameAppRejoin`, `handleTvRemoteTileTap`, `handleCrossAppSwitch`).

### 10.7 Relationship to other models

- `docs/PHONE-AND-TV-STATE-MODEL.md` — superseded for the tile-state
  matrix; retained for TV-side state and the home-screen shell
  structural material (header, badge menu, proximity banner).
- `docs/ROOM-SESSION-MODEL.md` — source of the multi-room membership
  rule and the one-engagement rule that Signal B respects.
- `docs/ROOM-AUTHORITY-MODEL.md` — irrelevant to badge state; controller
  / owner authority is in-app and not surfaced on the shell tile.
- `docs/HOUSEHOLD-DEVICE-PRESENCE-MODEL.md` — provides the
  "household membership" and "at-home" predicates Mode A/B/C derive
  from; tile state inherits Mode-driven `.greyed` behavior on
  TV-required apps when no signal fires.
- `docs/ROOM-ACCESS-INVITE-MODEL.md` — invites and room-code-entry are
  separate shell surfaces from the app-tile grid; an invite badge or
  pending-invitations tile (see DEFERRED.md "Pending Invitations
  inbox UI") would be its own indicator, not Signal A/B/C/D.

### 10.8 The implementation hook

The function to modify is `applyHomeTileState(tile, app, mode, active)`
at `index.html:2332`. Its current signature accepts `active` (the
bound-TV cache). The Phase-3 evolution extends it to accept the user's
cross-app participant state — either as an additional argument or by
making the function read a new shell-side cache populated by a
`refreshUserAppState()` orchestrator. The Phase-1 default-state path
(restore `TILE_DEFAULT_COPY`, set `.greyed` per Mode B karaoke rule)
is preserved unchanged.

The `TILE_DEFAULT_COPY` constant gains a wellness entry when the
wellness tile is added; no schema change is implied by this spec
beyond what Phase 3+ already needs.
