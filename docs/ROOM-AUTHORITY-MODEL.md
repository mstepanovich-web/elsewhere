# Room Authority Model

Status: Adopted. Supersedes the single-role "manager" concept described in
earlier control-model docs (see "Relationship to existing docs" below).

This document defines who holds authority over a room, how that authority
is split, and what happens when the manager departs.

## Background

A "room" is a durable gathering of people — a manager and a set of
participants — that persists independent of which app it is currently
running. A "session" is the disposable per-app instance running under a
room. (The room/session model is defined separately; this document covers
only the authority model layered on top of it.)

Earlier docs treated "manager" as a single role. This document refines that:
manager authority is two distinct roles, because operational control of a
live gathering and personal ownership of a saved template are different
things and must transfer differently.

## The two roles

Manager authority is split into two roles that, for the original convener
of a room, are held by the same person — but which separate when authority
transfers.

### Room control

Operational authority over the live gathering:

- Drive the screen (change venues, start/stop content).
- Manage the queue.
- Switch apps and switch games within an app.
- Admit and remove participants.
- Set the room's invite policy.

Room control is fully transferable. A successor — whether assigned
explicitly or auto-promoted — receives room control in full.

### Room ownership

The binding between a room and the original convener's personal context:

- The convener's saved rooms / saved groups (their reusable templates).
- The right to save this room into, or update, the convener's own template
  library.

Room ownership is NOT transferable by succession. It remains with the
original convener. A successor who takes control does NOT gain ownership:
they can run the room, but they cannot modify the original convener's saved
groups, and if they choose to save the room they save it as their own new
saved room — never as an edit to someone else's library.

Because ownership never transfers, an original convener who leaves and
returns can reclaim room control cleanly: ownership was never in question,
so reclaiming is unambiguous.

## Manager departure

How a room responds to losing its manager has two triggers — explicit
departure (the manager deliberately leaves) or implicit loss (the manager
vanishes) — and one four-tier succession hierarchy applied to either.
The trigger affects whether the named-successor tier can match (only on
explicit departure is a name passed); the hierarchy itself is the same.

### Explicit departure

The manager has a "leave room" affordance. Choosing it prompts the manager
to either:

- Name a successor — a specific participant who receives room control IF
  no host is present (a present host always wins); or
- Leave without naming a successor; or
- End the room.

Naming a successor is one input to the hierarchy, not an override: if a
host is in the room, the host inherits regardless of who was named.
Leaving without naming a successor simply skips the named-successor tier.

### Implicit loss

If the manager's presence ends without an explicit departure — phone dies,
app closed, connection lost, walked away — the room cannot prompt anyone.
The existing participant heartbeat / prune mechanism detects the manager's
absence. The named-successor tier is skipped (no opportunity to pass a
name); the host, non-audience, and room-end tiers apply unchanged.

### The four-tier succession hierarchy

When the manager has departed, the next controller is chosen by the first
matching tier. A host is always preferred over any other candidate,
including a named successor — a host never competes with a name, and a
name never competes with a host.

**Tier 1 — A present host.** If a participant with the host role
(see "The host role" below) is currently in the room, the host becomes
controller. A present host ALWAYS inherits, on BOTH explicit and
implicit departure. If multiple hosts are present, pick among them by
the "longest continuously-present" measure used in tier 3.

**Tier 2 — Named successor (explicit departure only, no host present).**
If no host is present AND the leaving manager named a specific
participant when leaving AND that participant is eligible (currently in
the room, in active or queued participation mode, not the leaver), that
participant becomes controller. A named successor only matters when
there is no host to inherit by default.

**Tier 3 — Longest-present non-audience participant.** If no host is
present and no eligible named successor was passed, the room promotes
the longest continuously-present non-audience participant to room
control.

**Tier 4 — Room ends.** If no host, no eligible named successor, and no
non-audience participant is available — the room ends (see "Empty room"
below).

- "Continuously-present" means the candidate's current unbroken presence
  — a participant who left and rejoined is ranked by their current stint,
  not their first.
- "Non-audience" excludes participants in audience (watcher) mode, who
  have opted out of the player track; promoting a watcher to controller
  would promote someone who chose not to drive.
- Eligibility check on a named successor is defensive: the UI picker
  will only ever show eligible candidates, so an ineligible name should
  not occur — but the RPC checks anyway and silently falls through to
  tier 3 if the named user is no longer eligible. No prompt, no error.

### Empty room — no eligible successor

Tier 4 of the succession hierarchy: if no host is present, no eligible
named successor was passed, and no non-audience participant is available
to take control, the room ends.

A room containing only the departing manager, or only audience-mode
watchers, is empty for succession purposes: there is no one to hand
control to, so the room ends. Naming a successor who is not (or is no
longer) an eligible participant falls through to the lower tiers; if
those are empty too, the room ends.

Ending the room sweeps participants and ends any active session as part
of the transition (see PHASE-1-BUILD-SPEC.md §D's rpc_session_leave row
for the implementation contract — write order is sessions → participants
→ rooms.ended_at). Room ownership is preserved unchanged — the original
convener retains their saved-room binding even after the room ends.

## The host role

A host is a standing deputy. While the room runs, a host holds
manager-like authority over OTHER participants: a host can change other
participants' participation roles, reorder the queue, and edit other
participants' pre-selections. A host CANNOT assign the manager role
itself, and CANNOT alter the manager's own row. Multiple participants
may be hosts concurrently.

The host is also the standing designated successor: tier 1 of the
succession hierarchy promotes a present host over any other candidate,
including a named successor. This is the host role's secondary purpose
— a "designated heir" that wins automatically, no matter what the
leaving manager named at leave time.

**Dormancy.** The host role is currently dormant in the product. The
database schema (`control_role` enum value `'host'`) and the RPC
authorization gates exist, but no current UI surfaces or assigns the
role. It is intentionally retained, not vestigial: surfacing the host
role — both as a deputy and as a standing successor — is a future
feature. A reader who finds `'host'` in the schema or RPC bodies should
know it is held for this design, not for legacy reasons.

## The immersive-control layer

The "immersive-control layer" is the set of additional authority concepts
that apply when a room is bound to an embedding-capable screen. Two
new authority surfaces matter under this layer:

- **Expanded room-control operations.** Beyond the four-tier
  succession hierarchy already covered above, room control may
  transfer in two other ways: a controller may pass control to a
  successor without leaving the room, and an ownership-class user
  may seize control immediately. Both are documented below.
- **Device authority.** A peer authority category — not room control —
  keyed on ownership of the physical TV device the room is bound to.
  Device authority grants the power to evict whatever is currently
  using the household's screen; it does NOT grant room control. See
  HOUSEHOLD-DEVICE-PRESENCE-MODEL.md §7 for the device-authority
  side.

The layer is conditional. The activation predicate is documented in
"When the immersive-control layer is active" below.

### Control-transfer operations

Room control may transfer in three operations:

1. **Pass control without leaving.** The current controller hands
   control to a specific other participant while remaining in the
   room as a non-controller participant. Available to all users —
   not gated on ownership, admin status, or the layer being active.
   The acting user must be the current controller; the target must
   be an eligible participant (active room participant, not in
   audience-only mode).
2. **Ownership-seize.** An ownership-class user takes control of a
   LIVE room without waiting for any pre-existing controller to
   leave. Not gated on inactivity. See "Seize authority" below for
   the two predicates and the relationship to the existing
   inactivity-reclaim path.
3. **Succession on leave.** The current controller leaves the room
   and a successor is chosen by the four-tier hierarchy documented
   above in "Manager departure." This is the only path that ENDS the
   controller's room membership; pass-control and seize do not.

Each operation writes `rooms.controller_user_id` to the new
controller. Room ownership (`rooms.owner_user_id`) is never written by
any of these — it stays with the original convener.

### Seize authority

Seize is the immediate take-control operation, available to
ownership-class authority. It is a distinct operation from the
existing **inactivity-reclaim** path — the two are cousins, not
synonyms:

|  | Ownership-seize (NEW) | Inactivity-reclaim (existing) |
|---|---|---|
| Target room state | LIVE — controller is actively driving the room | STALE — controller has been idle ≥ 10 min |
| Gated on inactivity? | No — immediate | Yes — 10-min idle window required |
| Caller predicate | Ownership-class only (the two predicates below) | Any household member (member-reclaim) or HH admin (admin-reclaim) of the **displaying TV's** household |
| Implementing RPC | (not yet implemented — see "Implementation" below) | `rpc_session_reclaim_manager` / `rpc_session_admin_reclaim` |
| Intended use | Owner/admin asserts authority over a live room | Free a stalled room whose controller has walked away |

The two seize predicates (when the immersive-control layer is active —
see "When the immersive-control layer is active" below):

- **Convener-seize.** `auth.uid() = rooms.owner_user_id`. The original
  convener may seize their own room at any time the layer is active.
  Applies to any room the user owns, regardless of where the room is
  displayed.
- **Admin-seize.** The caller is an HH admin of the household that
  OWNS the room — i.e., `rooms.owner_user_id` is on that admin's
  household roster. **Note the narrowed predicate:** admin-seize
  keys on ROOM OWNERSHIP, not on the room being displayed on the
  household's device. An admin whose household OWNS a room may seize
  it even if it is currently being displayed on a foreign screen;
  conversely, an admin whose household OWNS the displaying TV
  CANNOT seize a foreign household's room just because it sits on
  their screen. The eviction power for that case is device
  authority (HDPM §7), not seize.

The host role (see "The host role" above) is NOT in scope for seize.
A host gets succession-priority — tier 1 of the four-tier hierarchy
— but cannot seize an actively-controlled room. The host's
authority is upgraded only when the current controller leaves; not
before.

**Engagement prompt on seize.** An HH admin who seizes a room while
already engaged in another room fires the normal one-engagement
"Leave [room A] to seize [room B]?" confirmation — seize is an
engagement transition like any other room-join. (See
ROOM-SESSION-MODEL.md § "Multi-room membership and the
one-engagement rule.")

A future enhancement — HH admins performing purely administrative
actions on a household-owned room (end it, remove a participant)
WITHOUT it counting as an engagement transition — is planned but
deferred. The current model treats every seize as an engagement
transition; the deferred enhancement would distinguish administrative
actions from take-control. Tracked in DEFERRED.md.

**Implementation.** Inactivity-reclaim's RPCs (db/010, re-pointed in
db/028) are live in prod. Ownership-seize has no RPC yet; the
model is written down so that when its RPC ships, the predicates
and engagement-prompt behavior are already defined. The
implementing-RPC work is tracked in DEFERRED.md, not under the
existing reclaim RPCs.

### Room vs. device authority — the three scenarios

The room/device authority split is the key new structural concept
of the immersive-control layer. Three scenarios make the split
concrete. In each case, "this household" is the household relative
to which an HH admin is making a claim of authority.

1. **Room owned by this household, displayed on this household's
   device.** The HH admin has BOTH authorities: admin-seize on the
   room (the room is owned by this household, so the admin-seize
   predicate `rooms.owner_user_id` is on this admin's roster) AND
   device authority on the screen (the TV device belongs to this
   household). The admin can take control of the room, or evict
   the room from the screen, or both. The operations are
   independent — seize transfers control without changing where
   the room is displayed; eviction changes display without changing
   who controls the room.
2. **Room owned by a foreign household, embedded on this
   household's device.** The HH admin has ONLY device authority.
   They can evict the foreign room from their screen — that's
   their physical property. They CANNOT seize the foreign room:
   the admin-seize predicate fails (`rooms.owner_user_id` belongs
   to a different household's roster). Eviction returns the
   screen to the local household's control; the foreign room
   continues to exist on the foreign household's terms,
   somewhere else (a different screen, or no screen).
3. **Room merely cast onto this household's screen (no binding).**
   The HH admin has ONLY device authority. There is no
   `screen_ref` to the household's device — the room is being
   displayed through a casting mechanism, not bound. The admin
   can revoke the cast (device authority); they cannot seize a
   room they don't own.

The throughline: device authority is "this is our physical screen,
and we decide what is on it." Room authority is "this is our
gathering, and we decide who controls it." They are separate
because the room and the screen are separable concepts.

### When the immersive-control layer is active

The immersive-control layer activates when a room is bound (via
`rooms.screen_ref`) to an **embedding-capable** device.

"Embedding-capable" is a CAPABILITY of the device, not a hardware
brand. The capability is: a camera, present and accessible to the
TV browser, plus the compositing pipeline to overlay participants
into the venue. A laptop with a USB webcam acting as a household
TV satisfies this exactly the same way the eventual Elsewhere
hardware unit will. The model does not enumerate brands; it
enumerates capabilities.

The current schema has no column that records this capability —
every `tv_devices` row is presently "some browser that claimed
itself to a household," with no discrimination between
embedding-capable hardware and a plain claimed screen. Adding an
embedding-capability column (e.g. `tv_devices.can_embed`),
tv2.html's self-report, and the claim-flow's recording is deferred
work; see DEFERRED.md. Until that column exists, the layer's
activation predicate is a logical concept the docs describe, not
yet a runtime-enforceable condition. The model is written down so
that when the schema catches up, the logic is in place.

When the layer is NOT active — a room bound to a non-embedding
device, or a screenless room — the four-tier succession
hierarchy above and the existing standard operations
(manager-departure, inactivity-reclaim, pass-control) are the
entirety of the authority model. The immersive-layer-only
operations (ownership-seize, immersive-filtered succession) and
device authority do not apply.

### Succession under the immersive layer — the degrade rule

When the immersive-control layer is active and the current controller
leaves the room, the four-tier succession hierarchy from "Manager
departure" above is applied — but with the candidate pool filtered
to **immersive-present** users only. "Immersive-present" means a user
who is presently embeddable on the displaying screen — i.e. bound
to the displaying TV with presence declared (HDPM §8), where the TV
is embed-capable (`tv_devices.can_embed = true`). There is no
account-level property in this predicate. (This matches "immersive
activates" in HOUSEHOLD-DEVICE-PRESENCE-MODEL.md §9.)

The four tiers (host → named successor → longest non-audience →
room-end) run against this filtered pool first, exactly as they do
in the non-immersive case — just with non-immersive-present
candidates excluded from consideration at every tier.

If no immersive-present candidate is found at any tier, the room does
NOT end immediately. The immersive filter degrades: succession falls
back to the plain four-tier hierarchy against all candidates
(immersive-present or not). Embedding goes dark — the room runs
without camera-composited presence on the screen — and the room
continues.

The room ends (tier 4 of the plain hierarchy) only if NO
non-audience candidate is available, immersive-present or not. The
immersive filter never causes the room to end prematurely; it is a
preference layer, not a stricter gate.

Rationale: the layer's purpose is to keep immersive embedding alive
when possible. Forcing the room to end the moment all
immersive-present candidates leave would punish the non-immersive
members for the immersive members' departure. Degrading to the plain
hierarchy preserves the room and downgrades only the embedding
capability — which is the right tradeoff: the room is the thing of
value, and the embedding is an enhancement.

### Known imperfection — presence vs. stored controller pointer

Presence (HDPM §8) is volatile and declared. Room control
(`rooms.controller_user_id`) is a stored pointer. The two can
drift: a controller who physically walks away from the
embedding-capable TV while their phone stays connected to
Supabase remains the controller-of-record even though they are no
longer present. The heartbeat / prune mechanism does not detect
physical departure — only the absence of network heartbeats.

This is an accepted imperfection. Three mitigations are in place:

- The existing inactivity-reclaim path: if the controller becomes
  inactive (no network heartbeat for ≥ 10 minutes), any household
  member of the displaying TV's household may reclaim via
  `rpc_session_reclaim_manager`.
- Ownership-seize: the room's owner, or an HH admin of the owning
  household, may seize at any time without waiting for the
  inactivity timer.
- Future presence-based detection (Bluetooth / ultrasonic
  proximity) is noted in HDPM §8 as a possible enhancement; if it
  lands, the controller's stored pointer could be re-evaluated
  against live presence.

The model does not solve the drift; it acknowledges the gap and
documents the routes around it.

## Summary

- Manager authority = room control (operational, fully transferable) +
  room ownership (personal, never transfers by succession).
- Manager departure has two triggers (explicit / implicit) and one
  four-tier succession hierarchy: (1) a present host, (2) named
  successor on explicit departure when no host is present, (3) longest
  continuously-present non-audience participant, (4) the room ends.
- A present host always wins — a named successor never competes with a
  host, and a host always inherits over any longer-present non-host.
- No promotable candidate at any tier → the room ends. Ending a room
  sweeps participants and any active session; room ownership is
  preserved.
- Room ownership stays with the original convener throughout; if they
  return, they reclaim control cleanly.
- The host role is currently dormant in the product — kept by design,
  not vestigial.
- **The immersive-control layer** activates when a room is bound to an
  embedding-capable device. It adds two new room-control transfer
  operations (pass-control-without-leaving; ownership-seize) and a
  immersive-filtered succession with a degrade rule (embedding goes
  dark; room continues). Ownership-seize is distinct from the
  existing inactivity-reclaim: seize is immediate and
  ownership-gated; reclaim requires the 10-min idle window and is
  household-gated.
- **Device authority** (see HOUSEHOLD-DEVICE-PRESENCE-MODEL.md §7) is
  a peer authority category — eviction power on the household's
  physical screen — distinct from room control. Evicting a room
  from your screen does NOT make you that room's controller.

## Relationship to existing docs

This document supersedes the single-role "manager" description in earlier
control-model docs. Docs that describe the older model should carry a
pointer to this one. The complete set of affected docs is to be identified
by repo search (see the task that accompanied this doc's creation) rather
than assumed.
