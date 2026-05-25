# Immersive TV — Design Model

Status: DRAFT for review. This is the design model for the Elsewhere
Immersive TV: the device a household logs in AS, which embeds the
experience and is the participatory substrate.

This document covers the COMPLETE model. It is explicitly tiered:

- **Tier 1** — the minimum that gates Phase 3 (karaoke onto the new
  model). Built first, via the Stage 3 build spec.
- **Tier 2** — the rest of the model. Real, intended, and described
  here in full — but not gating Phase 3. Built later. Each Tier 2 item
  also carries a short pointer entry in `docs/DEFERRED.md` routing back
  to this document.

It is grounded in two read-only investigations (referred to as Q2 and
Stage 2) whose findings are cited inline. Where the design proposes
something not yet verified, it is marked **[OPEN]**.

This document does not itself modify any adopted doc. Adopted-doc
reconciliations it implies are listed in §10.

---

## 1. What the Immersive TV is

The Immersive TV is an **access point**: a device a household member
logs in *as*. It runs the stage / shared big-screen experience, it
embeds present users into the venue, and it is the participatory
substrate for an immersive session.

There is no dedicated Elsewhere TV hardware yet. The laptop is, and
has been since the project began, "the TV." The model is therefore
designed for the eventual hardware endpoint, and the laptop is treated
as the interim device that loads the same surface. Nothing in the
laptop case is a special path — it loads the same generic TV URL the
dedicated hardware will.

## 2. Two capabilities of one surface — Immersive vs Casting

There is ONE TV surface and ONE generic TV URL. "Immersive" and
"Casting" are not two products and not two URLs — they are two
behaviors of the same surface, and the distinguishing axis is
**control**.

- **Immersive TV** — the QR code is on the TV itself. Scanning the
  Immersive TV's on-screen QR makes the scanner the **driver** of the
  TV experience and the session — but only as first-in / when there is
  no active session (see §6). The Immersive TV is claimed, has a
  household, embeds present users.

- **Casting** — QR codes live throughout the phone apps. Any user
  scans one and the session is shown on a screen. Casting **confers no
  control**: whoever controlled the session still does. A caster
  watches. Casting TVs mirror whatever the driver is doing.

Both are the same TV surface; Casting is that surface with embedding
and driver-control not in play. The household / member model attaches
to **claiming**, not to immersive-ness — an unclaimed TV simply has no
household and no roster, whether or not it could embed.

Consequence: an Immersive TV session owner always controls the TV
experience. A casting user controls the session only if they already
own it — never by the act of casting.

## 3. The immersive user

An **immersive user** is a derived runtime role, not an account tier.
There is no account-level entitlement. (Verified — Q1 / Stage 2: no
premium/tier/subscription column exists on any user table.)

An immersive user is derived from exactly two facts:

1. The user is connected to an Elsewhere TV device whose
   `tv_devices.can_embed` is true (the device has the camera +
   compositing capability to embed participants).
2. The user has declared presence — they are physically in front of
   that device.

Both true → immersive user. Either false → not. The terminology
"premium user" is superseded by "immersive user" throughout
(see §10 — repo-wide rename).

### Participation is always via the app

Being an immersive user does NOT change how a user participates.
Everyone — immersive or not — participates through the iOS or HTML
app: song selection, mic, cards, answers, etc. The immersive user is
*additionally* embedded into the Immersive TV experience.

Being an immersive user confers **no control privilege**. An immersive
user invited into a session they do not own can never take control by
virtue of being immersive; control follows the normal room-authority
hierarchy.

### Immersive gating

A session MAY gate specific capabilities to immersive users — e.g. a
karaoke session that allows only immersive users to sing, or a manager
who can see which queue members are immersive and skip/remove
non-immersive ones. Gating is a per-session configuration, layered on
top of normal participation. **[OPEN]** — gating granularity
(per-capability vs whole-session) is not yet decided; flagged for a
later design pass, not gating Phase 3.

## 4. Presence — how it is declared

Presence is a per-session, volatile fact — distinct from the durable
binding/claim association (consistent with HOUSEHOLD-DEVICE-PRESENCE-
MODEL.md §8: "Binding proves a durable association ... it does not
prove the user is physically present right now").

Presence is declared one of two equivalent ways:

1. **By live QR scan.** The user scans the Immersive TV's on-screen QR
   code — to enter the app, or during an active session. Because the
   QR is displayed on that physical TV, scanning it is live evidence
   the user is in front of that device. The scan IS the presence
   declaration — no separate "are you home?" prompt. The scan is the
   one that initiated or occurred during the current session; it
   declares presence for that session only, not permanently.

2. **By the "are you home?" question.** If the user opens the app
   without a scan (e.g. just logs in from home), there is no live
   evidence, so presence is asked explicitly, as HOUSEHOLD-DEVICE-
   PRESENCE-MODEL.md §8 describes today.

Either way, presence is per-session and re-established each session.

**Multi-device:** if a user is a member of multiple TV devices and
logs in WITHOUT scanning, they are shown a list of their devices and
choose one BEFORE declaring presence. (Verified — Stage 2: this exists
today as `enterYourTvsFlow` in `index.html`; the n>=2 picker precedes
the proximity question.) The scan path needs no picker — the scan
names the device.

**TIER NOTE.** Presence-by-question + the multi-device picker EXIST
today (Tier 0 — already built). **Presence-by-scan does NOT exist**
(Stage 2: no code treats a scan as a presence declaration) — it is a
**Tier 2** build.

## 5. Setup — how a device becomes the Immersive TV

### 5.1 What already exists (verified — Stage 2)

The full claim round-trip exists end-to-end:

1. A device opens the TV surface (`tv2.html`) — generates a
   `device_key`, displays a claim QR.
2. A phone with the iOS Elsewhere app scans it.
3. The iOS app's deep-link handler fires `elsewhere://tv-claim`.
4. `index.html`'s claim screen calls `rpc_claim_tv_device` (new
   household) or `rpc_link_tv_to_existing_household` (existing).
5. The claiming device becomes a registered `tv_devices` row and
   transitions to the apps screen.

Verified facts that matter:

- The claim RPCs have **no iOS-specific assumption** — they are
  callable from an ordinary authenticated web session. The actual
  claim UI is already web code.
- The iOS dependency is **only the trigger** — the
  `elsewhere://tv-claim` deep link → `shell/auth.js` → a `CustomEvent`.
- `rpc_claim_tv_device` creates a household and makes the caller its
  admin, unconditionally (consistent with the "first claimant becomes
  HH admin" design).

### 5.2 The Tier 1 gap — the web-only claim trigger

The setup flow is therefore **not missing — it is iOS-app-gated.** The
only thing absent is a web path to the existing claim flow that does
not require the iOS app on a second device.

**TIER 1 — the Phase 3 gate.** Provide a web way for a logged-in
household member, on a laptop, to reach the existing claim flow and
make that laptop the household's Immersive TV — without the iOS app.
Because the RPCs and the claim screen already exist, this is a small
build: a web entry point that does what the deep-link trigger does.
**[OPEN]** — exact entry mechanism (a `/tv` route, a home-screen
action) to be settled in the Stage 3 build spec.

### 5.3 The setup flow (intended, complete)

1. A household member, on the device to become the TV, reaches the
   TV surface (Tier 1: via the web entry point; or, as today, the
   device shows a claim QR scanned by an iOS-app phone).
2. First claimant of a never-claimed TV → a household is created,
   that user becomes HH admin (verified — exists).
3. Subsequent household members are added by the admin via the
   existing email/phone household roster mechanism.
4. The device is now the household's Immersive TV.

## 6. Ownership, takeover, and release

These rules govern **the household's one active Immersive TV** — a
single household-scoped "which device is the TV right now" concept.
Underlying `tv_devices` rows are cheap and may be plural (Stage 2:
`device_key` is an unverified browser-local value, any browser can
mint one); the rules govern the active pointer, not the row count.

- **R1 — First claimant owns/drives.** The first household member to
  claim/scan the TV with no active session is its driver.
- **R2 — Second person joins as a player.** If another household
  member scans an Immersive TV that already has an active session,
  they join as a PLAYER and are shown that someone else is managing —
  they do NOT take over. (Stage 2: no scan-aware code path exists for
  this; the analogous behavior is covered today by `rpc_session_join`
  + `control_role` UI gating. A scan-aware path is a build item.)
- **R3 — HH admin takeover.** Only the household admin may take over
  an Immersive TV session in progress. (Stage 2: inactivity-reclaim
  RPCs are LIVE; ownership-seize is DOCUMENTED BUT UNIMPLEMENTED per
  ROOM-AUTHORITY-MODEL.md §"Seize authority" — its RPC does not exist.)
- **R4 — Idle release.** An Immersive TV registration is released
  ~10 minutes after there is no active session; the pointer frees and
  any household member may re-claim under R1.
- **R5 — Immersive status checked at entry.** Whether a user qualifies
  as immersive is evaluated at entry; later proximity flux does not
  tear down an in-progress TV session.

**TIER NOTE.** R1 exists (first claimant → founder admin). R2/R3 are
partially covered by existing session machinery but have no
scan-aware or ownership-seize implementation — **Tier 2**. R4 **does
not exist** — Stage 2: the 10-minute rule that exists gates ROOM
reclaim, not TV release; and `rpc_tv_heartbeat` fires only at boot,
so a periodic heartbeat must be built before any idle-release rule
can rely on it. R4 is **Tier 2** and itself has two parts (periodic
heartbeat + release rule).

## 7. The trust boundary — stated honestly

Device identity is **not verified.** (Stage 2: `device_key` has no
server-side format validation — any string is accepted;
`rpc_claim_tv_device` has no actor-authorization check — any
authenticated user holding a `device_key` can claim; the "128-bit
UUID secret" is doctrine in a code comment, not enforced; and a
weaker non-UUID fallback generation path exists.)

For the current stage — no active users — this is acceptable. The
model records it explicitly so it is not mistaken for a security
boundary.

The design's position: device *identity* stays unverified; *actor
authorization* should be enforced — only a member of household H may
become or drive H's Immersive TV. **[OPEN]** — whether to add an
actor-authorization check to the claim path, and whether to enforce
`device_key` format, are Tier 2 hardening decisions; flagged, not
gating Phase 3.

## 8. Showing a session on a TV you do not own

An immersive user invited into a session owned by someone else may
want it on their own Immersive TV. This is **display only — it confers
no control** (§2, §3).

- **Primary path — the "TV" button.** A one-tap action in the app
  sends the session to the user's own Immersive TV. The system already
  knows which TV is theirs. Build item.
- **Fallback — "enter room code" on the TV.** A low-prominence utility
  on the TV device (in a settings menu, not foregrounded) where a room
  code is typed to pull a session onto the screen. Consistent with
  ROOM-ACCESS-INVITE-MODEL.md's treatment of room codes as a real but
  deliberately low-prominence secondary entry path.
- **Casting** — the path for users with no TV of their own; the
  multi-device casting chain. Separate from the above.

**TIER NOTE.** The "TV" button and the scan-aware paths are **Tier 2**.

## 9. Guest immersive status lifecycle

A household guest (a user bound to a TV but not on its roster) who is
present is an immersive user — embeddable, gate-eligible — but a guest
is NOT eligible to own/claim the household's Immersive TV (that is
household-members-only).

Immersive status is **session-scoped**: it ends when the user leaves
the session or the session ends; regaining it requires a fresh scan.

**TIER NOTE — Tier 2, and note the dependency.** Stage 2: there is no
"immersive status" stored anywhere today — it is computed per-render,
not a discrete state. The session-scoped-expiry rule cannot be
enforced until a representation of the immersive grant is introduced.
This is a schema/model addition, not just logic — and it is the
prerequisite for the lifecycle rule. **Tier 2.**

## 10. Adopted-doc reconciliations this model implies

This design does not edit adopted docs; these are the changes it
implies, to be done as deliberate propose-pause edits:

1. **HOUSEHOLD-DEVICE-PRESENCE-MODEL.md §9** — already separately
   flagged: remove the nonexistent account-level premium flag; the
   capability is device + presence (this is "EDIT 1" from the doc-
   reconciliation task).
2. **Repo-wide rename** — "premium user" -> "immersive user" across
   docs (and, separately scoped, code). The four cross-reference sites
   identified in the doc-reconciliation task are corrected here.
3. **Immersive vs Casting** — HDPM §6 frames the TV QR as "display +
   binding" on one device. This model's Immersive/Casting distinction
   (a control distinction, §2) should be reconciled into HDPM so the
   two behaviors are named. NOTE: this model keeps them as ONE surface
   — it does not split them into two — so this is a clarification, not
   a structural change.
4. **Presence-by-scan** — HDPM §8 is question-only. §4 of this model
   adds scan-as-presence as a second equivalent path; HDPM §8 needs a
   corresponding update when presence-by-scan is built (Tier 2).

## 11. Tier summary

**Tier 0 — already built (verified Stage 2):** one generic TV URL +
per-device token; the full claim round-trip (iOS-app-triggered);
claim creates household + HH admin; multi-device picker before the
presence question; presence-by-question; `launch_app` subscription.

**Tier 1 — one of three Phase 3 gates, build next (Stage 3 build
spec):** the web-only claim trigger — a web path for a logged-in
household member to make a laptop the household's Immersive TV without
the iOS app. Small build; the RPCs and claim screen already exist.

Tier 1 is necessary but NOT sufficient to unblock Phase 3. See §13.

**Tier 2 — real, intended, NOT gating Phase 3 (deferred; each gets a
`DEFERRED.md` pointer entry routing here):**
- Presence-by-scan (§4) — and the HDPM §8 update.
- Periodic TV heartbeat + ~10-min idle TV release, R4 (§6).
- Scan-aware second-person / takeover paths, R2/R3 (§6).
- Ownership-seize RPC (§6 R3) — RAM §"Seize authority" already
  documents it as unimplemented.
- The "TV" button + low-prominence "enter room code" utility (§8).
- A stored representation of immersive status + its session-scoped
  lifecycle (§9) — schema/model addition.
- Trust-boundary hardening: actor-authorization on claim,
  `device_key` format enforcement (§7).
- Casting — display-without-binding — described in adopted docs,
  entirely unbuilt (Stage 2).
- Immersive gating granularity (§3) — open design question.

## 12. Next stages (Immersive TV workstream)

- **Stage 3** — build spec for **Tier 1 only** (the web claim
  trigger). Written and reviewed before code.
- **Stage 4** — build Tier 1, propose-pause-apply.
- Tier 2 items are sequenced separately, against this document.

Completing Stages 3-4 clears ONE of Phase 3's three gates. It does not
on its own unblock Phase 3 — see §13.

## 13. The three Phase 3 gates

Phase 3 (karaoke onto the new model, per UNIFIED-APP-PLAN.md §5) is
gated on THREE things, all of which must clear. Tier 1 of this model
is only the first.

1. **Immersive TV — Tier 1 (web claim trigger).** This document,
   §5.2 / §11. A device must be able to become the household's
   Immersive TV without the iOS app, or there is no stage for Phase 3
   karaoke to be tested against. Stage 3 build spec covers this.

2. **Item 6 — tile-tap must stop creating a session.** Tile-tap
   currently creates a session, contradicting ROOM-SESSION-MODEL.md
   ("tile-tap is navigation, not session creation"). Session creation
   must move to a deliberate per-app in-app action. The karaoke fix
   lands in Phase 3; the games fix lands in Phase 4.

3. **Item 5 — karaoke needs an explicit session-creation action.**
   The karaoke-specific form of the item-6 fix: tile-tap is navigation
   only; the user lands on a single "karaoke info" screen; clicking
   through that screen is the deliberate action that creates the
   karaoke session. No lobby screen (unlike games, which has a
   game-selection step; karaoke does not).

Items 5 and 6 are one piece of work seen from two ends — item 5 is
item 6's karaoke-specific fix. They are NOT backlog / DEFERRED.md
items; they are Phase 3 (and, for item 6's games half, Phase 4)
scope. They require their own focused investigation and build spec,
separate from this document's Tier 1 spec, though the two interlock
at the karaoke-entry seam (karaoke's "Start Session" action and the
Immersive TV that runs the karaoke stage are related).

Phase 3 is unblocked only when all three gates are cleared.
