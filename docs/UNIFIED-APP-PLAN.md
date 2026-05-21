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
  and the premium tier

Read this document first for the whole picture; the companions for detail.

## 1. The reframe

The existing Elsewhere docs treat an at-home household user (HHU) as the
primary user, and a non-household user (NHHU) as the constrained case.

This workstream inverts that. The primary user is any registered Elsewhere
user, with no TV device required. Every app must work for that user as a
primary participant — never relegated to a separate "audience" surface. A
TV device becomes a premium capability layer on top of a complete
experience, not a gate to it.

In some situations NHHUs, or HHUs who are not at home, get a deprecated
experience compared to a premium user present at a TV — but not a wholly
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

### Premium tier — a premium user, present at a camera-equipped screen

- Everything baseline, plus the camera-composite capability: being
  composited into the venue, and costume overlays.
- Premium is exactly this one capability. It is identical across all apps.

Premium is defined by a physical situation — a premium user present at a
camera-equipped screen — not by user class or household membership. The
full model for households, TV devices, binding, presence, and premium
activation is in HOUSEHOLD-DEVICE-PRESENCE-MODEL.md.

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

1. Premium-A is the workstream's premium tier — premium = a premium user
   present at a camera-equipped screen, which the architecture already
   supports. Premium-B (remote self-insertion via a phone camera) is
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

For karaoke and games, the experience across baseline/premium x player/
watcher.

Two framing points:
- "Watcher" is a mode any user opts into, not a lesser tier.
- Premium is camera-composite while performing — so a "premium watcher" has
  the entitlement but nothing to act on; it collapses into baseline
  watcher. The real matrix is three live cells per app, not four.

### Karaoke — how users are placed

When a user enters karaoke, they are placed by their premium/presence
status (see HOUSEHOLD-DEVICE-PRESENCE-MODEL.md):

- A premium user who is present at the TV is placed as a potential singer.
  In the manager's view they are shown distinctly, so the manager can see
  these users can be embedded into the venue.
- A non-premium user, or a premium user not present, is placed in audience
  mode by default — they cannot be embedded, so they are not put in the
  singer track automatically.

An audience-mode user may still ask to join the singing queue. The first
time such a user does so, the manager is prompted with a one-time
session-level choice: allow non-premium / not-present users to join the
queue — yes or no. If yes, such users may queue for the rest of that
session; the manager retains the existing skip and remove controls. If no,
they remain audience-only.

### Karaoke — the premium-restricted session

The karaoke manager may restrict singing to premium-present users for a
session. In a restricted session:

- Only premium-present users may be in the singing queue.
- Audience-mode users (non-premium, or premium-not-present) cannot join the
  queue at all — the one-time queue-approval prompt above does not apply;
  the restriction overrides it.
- Audience-mode users retain full access to the rest of the app: they can
  search for songs, and search and view venues and costumes. They are shown
  a message that singing is restricted to premium users, with a path to
  obtain a TV device.

So karaoke has two manager-controlled modes: unrestricted (audience users
may be allowed into the queue at the manager's one-time discretion) and
restricted (singing is premium-present only).

### Karaoke — the quadrants

- Baseline player — a non-premium or not-present user who has been allowed
  into the queue: drives a screen, picks and changes venues, searches
  songs, queues, sings. Not composited into the venue.
- Premium player — a premium-present user: as baseline, plus composited
  into the venue and costume overlays. Every control is identical to
  baseline; premium adds visual presence only.
- Baseline watcher — a user in audience mode: sees and hears the room's
  karaoke, is a room member, not in the queue. Same app, reversible mode.
  This is what replaces the old audience.html.
- Premium watcher — no distinct experience; dormant entitlement, equals
  baseline watcher until the user switches to playing.

### Games

- Baseline player — full games for any user; closest to games today, which
  is already TV-independent.
- Premium player — forward-looking: camera-insertion + costumes for games
  depends on venues being introduced into games, a separate future
  workstream. Empty until then by absence of the venue substrate.
- Baseline watcher — a user in the games room who has opted to watch.
- Premium watcher — empty (no venues yet, and watching anyway).

### What the breakdown shows

- "Premium watcher" is not a real quadrant in either app.
- Premium is a thin, consistent layer — the same one capability in both
  apps, on the player track only.
- Karaoke's cells are describable now; games' premium column is
  forward-looking. Karaoke is a refactor target; games' premium tier is a
  later feature.

## 5. Implementation sequencing

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
  app. Can overlap Phase 1.
- Phase 3 — karaoke onto the new model. Scanned-screen sessions; baseline
  players driving venues and the queue with no TV device; audience.html
  dissolved into baseline watcher mode. Depends on Phases 1 and 2.
- Phase 4 — games onto the new model. Conformance, not rebuild: re-anchor
  to the room/session split, adopt the unclaimed-screen path, unify
  cross-app-switch behavior. Depends on Phase 1; independent of Phase 3.
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
  model. It does not get its premium tier in this workstream.
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

## 7. Premium-B — deferred, with no-foreclose notes

Premium-B (a remote user composited into a venue via their own phone
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
