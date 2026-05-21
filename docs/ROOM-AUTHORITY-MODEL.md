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

How a room responds to losing its manager depends on whether the departure
was explicit or implicit.

### Explicit departure

The manager has a "leave room" affordance. Choosing it prompts the manager
to either:

- Assign a successor — a named participant who receives room control; or
- End the room.

The manager, being present and deliberate, makes the succession decision
themselves. This is the preferred path because the person with the most
context chooses the successor.

### Implicit loss

If the manager's presence ends without an explicit departure — phone dies,
app closed, connection lost, walked away — the room cannot prompt anyone.
The existing participant heartbeat / prune mechanism detects the manager's
absence. When it does, it triggers auto-promotion of a successor.

### Succession rule (auto-promotion)

When a successor must be chosen automatically, the room promotes the
**longest continuously-present non-audience participant** to room control.

- "Continuously-present" means the candidate's current unbroken presence —
  a participant who left and rejoined is ranked by their current stint, not
  their first.
- "Non-audience" excludes participants in audience (watcher) mode, who have
  opted out of the player track; promoting a watcher to controller would
  promote someone who chose not to drive.

### Empty room — no eligible successor

If, on either an explicit or an implicit departure, there is no eligible
successor — no non-audience participant available to take control — the
room ends.

"Empty" for this purpose means no participant eligible to become
controller. A room containing only audience-mode watchers and no other
participants is, for succession purposes, empty: there is no one to hand
control to, so the room ends.

This is a single rule covering both triggers: manager departs (explicitly
or implicitly) → look for an eligible successor → if none exists, end the
room.

## Summary

- Manager authority = room control (operational, fully transferable) +
  room ownership (personal, never transfers by succession).
- Explicit departure → manager assigns a successor or ends the room.
- Implicit loss → auto-promote the longest continuously-present
  non-audience participant to room control.
- No eligible successor, either trigger → the room ends.
- Room ownership stays with the original convener throughout; if they
  return, they reclaim control cleanly.

## Relationship to existing docs

This document supersedes the single-role "manager" description in earlier
control-model docs. Docs that describe the older model should carry a
pointer to this one. The complete set of affected docs is to be identified
by repo search (see the task that accompanied this doc's creation) rather
than assumed.
