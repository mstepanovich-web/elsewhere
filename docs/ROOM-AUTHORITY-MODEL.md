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

## Relationship to existing docs

This document supersedes the single-role "manager" description in earlier
control-model docs. Docs that describe the older model should carry a
pointer to this one. The complete set of affected docs is to be identified
by repo search (see the task that accompanied this doc's creation) rather
than assumed.
