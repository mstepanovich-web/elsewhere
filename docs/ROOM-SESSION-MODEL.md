# Room / Session / Group Model

Status: Adopted. This document defines the core entity model for the
unified-app workstream: what a room is, what a session is, how they relate,
and how groups (saved rooms) work on top of them.

It is the structural foundation that the Room Authority Model and the
Room-Access / Invite Model both build on.

## Background — the problem this solves

Today Elsewhere has one entity, `sessions`, which does two jobs at once: it
represents the running app instance (this game of Last Card, this karaoke
sitting) AND it represents the gathering of people (the manager and the
participant list).

Welding those two jobs into one row is why a gathering cannot survive an
app switch. A session's `app` is immutable — there is no code path that
changes it. So moving a gathering from Games to Karaoke cannot mean
"change this session's app"; it can only mean "end this session, start a
new one." And because the people are attached to the session, ending it
drops everyone.

The fix is to split the one entity into two: a durable container for the
gathering, and a disposable instance for the app.

## The three entities

### rooms (new)

A room is a durable gathering of people. It persists independent of which
app is currently running. A room holds:

- the manager (see Room Authority Model — manager authority is itself split
  into room control and room ownership)
- the participant list (via session_participants, re-anchored — see below)
- screen_ref — the screen the room is bound to. NULLABLE: it may point to
  a claimed household TV, or be null for a scanned/unclaimed screen, or be
  null for a room with no screen at all.
- room_code — the room's join code. Generated once when the room is
  created and stable for the room's life.
- lifecycle timestamps.

A room has at most one active session at a time.

### sessions (demoted)

A session is the disposable per-app instance running under a room. It is
single-app and its app value remains immutable. A session keeps:

- app (immutable), admission_mode, capacity, current_state, ask_proximity,
  turn_completion, started_at, ended_at
- room_id — pointing up to its room.

A session no longer holds the manager, the bound screen, or the room code —
those move up to the room.

### session_participants (re-anchored, not reshaped)

Participants re-anchor from the session to the room: the foreign key
changes from session_id to room_id. The row shape is otherwise frozen —
same columns, same control_role / participation_role values, same RPC
return signatures. The five indexes re-key from session-scoped to
room-scoped.

Freezing the row shape is deliberate: the control_role value is read in
~50 sites in the games player surface alone. Re-anchoring the foreign key
without changing the row shape means those reader sites do not change — the
data model moves underneath them.

The table name becomes a slight misnomer (participants now belong to a
room, not strictly a session). The name is NOT changed — renaming would
touch every RPC for no functional gain.

## How a person relates to the model

- A person is a member of a room (a participant row, left_at IS NULL).
- The room has a current session, or none (a room can exist between apps
  with no active session).
- The person experiences continuity at the room level. The session
  churning underneath them — ending, restarting as a different app — is
  invisible, because their membership was never attached to the session.

## The cross-app move

Moving a gathering from one app to another (e.g. Games to Karaoke):

1. The room manager initiates the move. (Authority for this is a room-level
   power — see Room Authority Model.)
2. The current session ends — ended_at is set. This is unavoidable: app
   is immutable, so a session cannot become a different app.
3. The room is NOT ended, and the room members are NOT touched. Ending a
   SESSION no longer sweeps participant left_at — that behavior moves to
   ending a ROOM only.
4. A new session is created under the same room_id, for the new app. It
   inherits the room's members by pointing at the same room — there is
   nothing to copy.
5. Surfaces re-navigate to the new app, but every participant re-attaches
   to the same room, with the same membership, the same manager.

The result: the app changes, the gathering does not.

Channel note: the Supabase realtime channel is keyed on the screen's
device key, not the session, so it persists across the move. The Agora
media channel embeds the app in its name and therefore necessarily
reconnects on an app switch — this is intrinsic and expected.

## Multi-room membership and the one-engagement rule

A user may be a member of many rooms simultaneously (a family room, a
friends room, a one-off room). Multi-room membership is unlimited.

A user may be actively ENGAGED in only one room at a time. "Engaged" means
actively participating in that room's current session — as opposed to
merely being a member of a room that is idle.

This is the one-engagement rule, and it is per-user-GLOBAL, not per-app: a
user is doing one thing at a time, period — not one karaoke thing and one
games thing concurrently.

"Engaged" is a derived state, not a stored field — a user is engaged in a
room if that room has an active session and the user is participating in
it.

When a user attempts to engage a second room while already engaged
elsewhere, they are prompted to confirm leaving the first ("Leave [room A]
to join [room B]?"). This reuses the cross-app-switch confirmation pattern.

## The TV QR code is a display mechanism, not a room-creation mechanism

A TV's QR code lets any user put an existing room/session onto that screen.
Scanning a TV's QR code to display a room creates nothing and confers no
authority — a room is owned and managed by whoever created it, which is
unrelated to the QR scan. Anyone may scan a TV to show a room on it.

(The same QR code is also used for binding a user to a TV device for
premium purposes — see the Household, Device & Presence Model. Binding is a
separate purpose from display; neither creates a room or confers room
authority.)

Because a scanned screen is bound to a room, and the room has a manager,
and the one-engagement rule governs joining, putting a room on a screen is
not an uncontrolled free-for-all: who may drive the screen (change venues,
start content) follows normal room-control authority.

## Groups — saved rooms

A group is a saved room: a reusable template consisting of a name and a
member list, plus room-level preferences. It is a distinct entity from a
live room.

The relationship is three layers:

- a group (saved room) is the template — inert, no live state
- a room is a live gathering — instantiated, either from a group or
  ad-hoc
- a session is what the room is currently doing.

"Temporary vs. saved" is not a flag on a room. A temporary room simply has
no saved-room record behind it and evaporates when done; a saved room is
one that has been deliberately saved as a group.

A live room spawned from a group may diverge from its template (a guest
joins mid-session). The group does NOT auto-update from the live room. When
a room spawned from a group has diverged, the manager is prompted to either
persist the changes to the group or keep the group unchanged. Ad-hoc rooms
have no template and no such prompt.

(Elsewhere already has a contacts-level groups concept for organizing
contacts. A saved room is a separate, lean entity — it may be populated
from a contact group, but it is not the same thing as a contact group.)

## Migration note

The introduction of the rooms entity is a clean-slate cutover. Existing
session and participant data is cleared as a migration pre-step; the schema
migrates against empty session tables. There is no backfill of historical
sessions into rooms. This is appropriate because session/participant data
is ephemeral by nature and pre-launch — nothing of value is lost — and it
removes the backfill and constraint-violation risk that a live-data
migration would carry.

## Summary

- rooms (new, durable) holds the gathering: manager, members, screen,
  room code.
- sessions (demoted, disposable) holds the per-app instance: app,
  admission settings, app state.
- session_participants re-anchors from session to room; row shape frozen.
- A room outlives its sessions; the cross-app move ends the session and
  keeps the room, so the gathering survives.
- Multi-room membership is unlimited; active engagement is one room at a
  time, globally.
- The TV QR code displays a room on a screen (or binds a user to a TV); it
  does not create rooms or confer authority.
- A group is a saved room — a template; temporary vs. saved is whether a
  saved-room record exists; groups do not auto-update from live rooms.
