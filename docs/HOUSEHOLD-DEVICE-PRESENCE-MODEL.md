# Household, Device & Presence Model

Status: Adopted. This document is the complete model for users, households,
TV devices, presence, and the premium tier. It supersedes
PHONE-AND-TV-STATE-MODEL.md.

It is a companion to ROOM-SESSION-MODEL.md, ROOM-AUTHORITY-MODEL.md, and
ROOM-ACCESS-INVITE-MODEL.md, and is referenced by UNIFIED-APP-PLAN.md.

## 1. The reframe

The superseded model treated an at-home household user as the primary user,
with everyone else as a constrained case. This model inverts that: the
primary user is any registered Elsewhere user, with no TV device required.
Households and TV devices are not a participation gate — they are the
substrate for one optional premium capability.

## 2. User categories

There is one kind of Elsewhere account: a registered user. "HHU," "NHHU,"
and "guest" are not separate account types — they describe a user's
relationship to a household or TV, and that relationship is derived, not
stamped.

- A registered user is anyone with an Elsewhere account (created via
  magic-link sign-up). Every registered user is a full, primary user of
  every app at baseline tier.
- A household member (HHU) is a registered user who is on a given
  household's member roster.
- A non-household user (NHHU) is a registered user not on the household in
  question's roster. NHHU is not a lesser account — it is simply "not a
  member of this household." A user is an HHU of their own household and an
  NHHU relative to every other household.
- A guest is a user who has bound to a household's TV (see section 5) but
  is not on that household's roster.

HHU / NHHU / guest are all relative to a specific household. The same
person is an HHU of their own household and a guest or NHHU elsewhere.
Their account does not change; only the relationship does.

## 3. Households

A household is a group of users, with an admin, that owns one or more
claimed TV devices.

- The household admin maintains the household's member roster (by email /
  phone). The existing household-invite mechanism (pending invites matched
  on email) is how a person is added.
- Household membership is the entitlement axis for household-account
  spending and household management — see section 10. It is NOT the gate for
  premium embedding — see section 9.
- A household is created when a user claims their first TV device. A
  newly-registered user has no household by default — being registered and
  being in a household are independent.

## 4. TV devices

A TV device is a screen claimed to a household. Claiming a TV is what
creates the household (for the first TV) or adds to it.

In the new model the TV device's role is re-scoped: it is no longer
required to use any app. It is the substrate for the premium tier — the
camera-equipped screen a premium user is composited into.

A TV device also displays a join/QR affordance (see sections 5 and 6).

## 5. Binding

Binding associates a registered user with a TV device.

- Binding is established by a one-time scan of the TV's QR code.
- Binding is free: anyone — including a user who is not on the household's
  roster — may scan and bind.
- Binding alone confers nothing. It is only an association. It does not
  grant household membership and does not grant the ability to spend the
  household's funds.

A user who is bound to a TV but not on the household's roster is a guest of
that household.

HHU-vs-guest status is derived live from the household roster, not frozen
at the moment of binding: if the admin adds a bound guest to the roster
later, that user becomes an HHU automatically, with no re-scan. If the
admin removes them, they revert to guest.

## 6. The TV QR code — display, binding, and authority

The TV's QR / join code serves two distinct purposes, and neither is room
creation or room authority:

- Display — anyone may scan the code to put an existing room/session onto
  that TV screen. Scanning to display creates nothing and confers no
  authority. A room is owned and managed by whoever created it (see
  ROOM-SESSION-MODEL.md); the QR scan is unrelated to room ownership.
- Binding — a registered user scans the code once to bind to the TV device
  (section 5).

The TV exposes its code persistently — full-screen when idle, and as a
compact affordance while an app is running — so binding and display are
available at any time, not only at idle.

## 7. Device authority

Device authority is the power to evict whatever is currently using a
household's physical screen.

Predicate: the caller is an HH admin of the household that OWNS the
TV device — i.e., `tv_devices.household_id` is on that admin's
household roster.

Device authority grants exactly one thing — eviction. The "what is
using the screen" can be three things:

- a room locally owned and displayed on the household's TV;
- a foreign household's room embedded on the household's TV (the
  foreign room continues to exist; only its embedding on this
  screen ends);
- a non-room cast (a phone or browser mirroring content via a
  casting mechanism, with no `rooms.screen_ref`).

Device authority is explicitly NOT room control. Evicting a room
from your household's screen does NOT make you the controller of
the evicted room. The room continues to exist (in scenarios 1 and 2
above) under whatever authority owned it before; only its presence
on your physical screen ends. Whoever was controlling the room
remains in control; they will simply be controlling it somewhere
else (a different screen, or no screen).

Three concrete scenarios that demonstrate the room/device split
are documented in ROOM-AUTHORITY-MODEL.md § "Room vs. device
authority — the three scenarios."

Device authority is a peer concept to room authority. Together
they make up the premium-control layer described in
ROOM-AUTHORITY-MODEL.md § "The premium-control layer." See that
section for the layer's activation predicate, the ownership-seize
operation (room-side), and the premium succession degrade rule.

## 8. Presence — "are you home?"

Premium is co-presence with a camera-equipped screen. Binding proves a
durable association with a TV; it does not prove the user is physically
present right now. Presence is a separate, volatile fact.

Presence is not detected. It is declared:

- On login, a user who is bound to a TV is asked whether they are home
  (present at that TV).
- The answer is remembered for that app session and re-asked on the next
  login.

Presence is self-declared and trusted. A user could falsely claim presence,
but the only thing a false claim unlocks is a cosmetic compositing feature
of no value to the liar — so defending against the lie is unnecessary for
this capability. (If presence ever gated something with real stakes, this
would be revisited.)

Automatic presence detection — e.g. Bluetooth or ultrasonic proximity
between phone and TV — would remove the need to ask. It is noted as a
possible future enhancement, not part of this model.

## 9. The premium tier

Baseline tier is every registered user's full access to every app, with no
TV device required. (See UNIFIED-APP-PLAN.md section 2.)

Premium is one capability: being camera-composited into the venue, with
costume overlays. It is identical across all apps.

Premium embedding follows the USER, not the user's relationship to a
particular household. Premium activates when both of the following are
true:

1. The user has premium (a property of their own account).
2. They are present at a TV device — i.e. bound to it (section 5) and
   presence declared (section 8).

Whose TV it is does not matter. Any premium user, present at any TV — their
own household's, a friend's, anywhere — is embedded. Premium embedding is
household-permissionless: a household does not gate who may be embedded on
its TV. (The household's control is over the room and over the screen
binding — see ROOM-AUTHORITY-MODEL.md and ROOM-SESSION-MODEL.md — not over
who embeds.)

Premium is therefore defined by a physical situation — a premium user,
present at a camera-equipped screen — not by household membership.

The same embedding-capable-device predicate that gates premium
embedding (this section) also gates the room-side premium-control
layer — see ROOM-AUTHORITY-MODEL.md § "When the premium-control
layer is active" for the layer's room-side operations
(ownership-seize, premium-filtered succession) and device authority.

## 10. Purchasing — the two-wallet rule

Two wallets exist:

- The household / TV account — funds belonging to the household.
- Each user's own account — funds belonging to that user, which travel
  with them to any household or TV.

The rules:

- An HHU may charge purchases (e.g. premium paid services) to their
  household account, or to their own.
- A guest — a user bound to a TV but not on that household's roster — may
  purchase, but only from their own account, never the household's. A
  guest's location does not change their access to their own funds; it only
  means the visited household's wallet is unavailable to them.

The HHU / guest distinction governs ONLY this wallet rule and household
management. It does NOT gate premium embedding (see section 9). A guest who
has premium and is present is embedded exactly like an HHU.

The broader payments / premium-paid-services model — how paid services are
priced, delivered, and managed — is not designed. The two-wallet rule above
is the one decided constraint within an otherwise undesigned area.

## 11. Relationship to existing docs

This document supersedes PHONE-AND-TV-STATE-MODEL.md in full. That document
should carry a supersession pointer to this one. Any HHU / NHHU / proximity
content in the superseded doc that is not reflected here was either
intentionally replaced by this model or is no longer applicable; if a
future reader finds superseded-doc content that seems to have been dropped
rather than deliberately replaced, it should be raised against this model
rather than assumed still valid.
