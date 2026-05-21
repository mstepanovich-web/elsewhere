# Room-Access / Invite Model

Status: Adopted. This document defines how a person who is not currently in
a room gets into it — covering invite policy, the invite mechanism,
unregistered-invitee resolution, registration, and cross-household join.

It builds on the Room / Session / Group Model.

## Background — why this is one mechanism

"Who can invite someone to a room," "how an invite is enforced," "how an
unregistered person gets into the app," and "how someone from another
household joins" look like four separate features. They are one: they are
all the single question of how a person not currently in a room gets into
it legitimately.

They are therefore designed as one mechanism, on top of one schema entity —
the invites table — rather than as four features that would drift apart.

## The problem with today's invites

Today a session "invite" is not a real invite: it is a shared URL
containing the room code, plus a hint broadcast. There is no invite record
and no check at join time. Anyone with the link is in. The manager-only
"gating" in games is only the invite button being hidden — the link itself,
once shared, works for anyone.

This breaks three things the new model needs: an invite policy would have
nothing to enforce it; an unregistered person has no path in (anonymous
users cannot read a room directly — see "Resolution" below); and
cross-household join has no model.

## The invite record

The mechanism is built on the existing (currently dormant) invites table.
The table's shape is sound for this model — it is keyed on room_code
(room-stable, not session-disposable), and its invitee link is optional
(designed for ad-hoc / unregistered invitees).

An invite is a real row containing: a token (the bearer secret in the
invite URL), the room_code it grants access to, the app, who created
it, an optional link to a saved contact, an expiry (7-day default), and a
used-at marker.

One required change to the table: the column currently named session_type
is renamed to app — it holds the app name and is simply misnamed.

The URL shared with an invitee carries the token, not a raw room code. The
token is the credential to enter the room; the room code stops being the
de facto entry credential.

## Invite policy — who can invite

Each room carries an invite policy, a manager-controlled setting with two
values: manager-only, or anyone-in-the-room.

- Default is manager-only; the manager may relax it.
- Only the manager can change the policy; within an "anyone" policy, any
  member may invite.
- A saved room may carry its own preferred default.

The policy has real enforcement: creating an invites row (minting a
token) is gated on the policy. Because the token is what grants entry and a
token only exists if someone permitted to mint it did so, the policy is
enforceable — not merely a hidden button.

## Decision: invite role is inferred per-app, not stored

An accepted invite seats the invitee into the room. The role they land in —
active participant, or audience-mode watcher — is inferred per-app, not
stored on the invite.

- A karaoke invite lands the invitee in audience mode (present, watching;
  they queue up to sing when ready — which matches how karaoke's queue
  already works).
- A games invite lands the invitee as an active participant.

The invite does not carry a role-hint column. The per-app default is the
correct answer in each case, and storing it would add a field that is
almost always set to the obvious value.

## Decision: invites are single-use

An invite token grants exactly one seat. The invites table is single-use
shaped (a single used-at marker), and this is kept as-is.

A token granting one seat is the safer posture — a leaked link admits one
stranger, not many — and each invite is an accountable, individual grant.

This is a conscious trade-off: it makes "share one link with a whole group"
clunky (the manager mints one token per invitee). If multi-use invite links
later become a genuine product need, the table would need reshaping; that
is explicitly out of scope here.

## Resolution — the Edge Function

Anonymous (unauthenticated) users cannot read a room or session directly:
the row-level security on those tables denies it outright. This is the
intended design.

Therefore an unregistered invitee opening an invite link cannot reach the
room on their own. Token resolution goes through a Supabase Edge Function
that uses elevated credentials to: validate the token (exists, not expired,
not used) and resolve it to the room, the app, and what the invitee is
permitted to see.

The Edge Function is mandatory — it is the only bridge across the
"anonymous cannot read anything" boundary. Without it there is no
unregistered-invitee path. It is also new infrastructure: the first
Supabase Edge Function in the project.

## The conversion path — invite into a registered, seated participant

The invitee flow:

1. A registered user (manager or member, per the room's invite policy)
   creates the invite. The inviter supplies the invitee's name and a phone
   number or email — these are mandatory.
2. The invitee receives the link and opens it. The Edge Function resolves
   the token; the invitee sees the app working at baseline tier. They are
   not yet authenticated.
3. To participate (join the queue, play), the invitee registers. They may
   set their own display name for how they wish to be called.
4. The display name flows back into the inviting user's contact for that
   invitee.
5. Once registered, the invitee is seated into the room as a participant
   (role inferred per-app), and the invite's used-at marker is stamped.

If a person attempts to register with an email or phone number that already
belongs to an Elsewhere account, this is not a new registration — it is
recognized as that existing account, and the magic link signs them in
rather than creating a duplicate. (Sign-up and sign-in are the same
magic-link flow, differing only in whether a new account is created.)

Cross-household join is the same path: a user from another household, or no
household, with a valid token is simply an invitee. The mechanism does not
depend on the invitee having a household.

## Invite and magic-link: how they merge

A registered Elsewhere user is created by clicking a magic link. It is
tempting to make the invite link itself a magic link, so that accepting an
invite also registers the user. This is NOT done.

The reason: a magic link is a login credential. Making the invite link a
magic link means generating login credentials on behalf of other people and
sending them through email or SMS. Anyone the link is forwarded to — or
anyone with access to that inbox — clicking it would be authenticated as
that account. This is an account-takeover vector built into ordinary
forwarding behavior. It also conflicts with single-use invites, and it
produces accounts from stray clicks.

Instead, invite-acceptance and authentication are kept as two steps,
stitched so tightly they feel like one:

- The invite link carries an invite token — a reference, not a credential.
  Clicking it authenticates no one.
- When the invitee chooses to participate, they trigger their OWN
  magic-link sign-up (or sign-in, if they already have an account). The
  credential is generated by their action, for their own address.
- The invite token rides along through that flow (carried in the
  magic-link redirect). After the invitee authenticates — their own action
  — they land back in the room, seated, with the token consumed.

The felt experience is: open invite, see the app, one tap to enter your
contact detail, click your own link, you are in. But no credential is ever
generated on someone else's behalf.

This design also makes the already-registered invitee case fall out for
free: the same token-carrying flow runs, and the auth sub-step is simply
sign-in instead of sign-up.

## Email and SMS

The invitee may be invited by email or by SMS, at the inviter's choice
(name + phone-or-email are mandatory fields). The token-not-credential
design is channel-agnostic — the same mechanism works for both.

SMS carries operational considerations email does not:

- SMS authentication has a per-message cost (it routes through a telephony
  provider); email magic links are effectively free.
- Phone numbers are a flakier identifier than email — they are recycled,
  changed more often, and easier to mistype. A mistyped number fails more
  silently than a bad email address.
- A person may be invited by email on one occasion and by phone on another;
  care is needed not to create two separate accounts for the same person.

One point in SMS's favour: an SMS one-time passcode is a code the user
types back, not a link to click. This sidesteps the cross-device problem
email has (where the magic link may open on a different device than the one
the invitee started on).

## Implementation note — a cross-device caveat

In the email flow, the invitee leaves the app (to their inbox) and returns
via the magic link. The invite token must survive that round-trip,
including the case where the magic link opens on a different device than
the one the invitee started on. The token therefore belongs in the
magic-link redirect URL, not only in browser memory. This is a known case
to handle deliberately.

## Summary

- Access to a room is one mechanism, built on the invites table:
  policy + token + resolution + conversion.
- Invite policy is a manager-controlled per-room setting (manager-only by
  default), enforced because minting a token is policy-gated.
- Invite role is inferred per-app; invites are single-use.
- Anonymous users cannot read rooms directly; a Supabase Edge Function
  (new infrastructure, mandatory) resolves invite tokens.
- The invite link carries a token, never a login credential; the invitee
  triggers their own magic link, and the token rides through it. This
  avoids sending credentials on others' behalf.
- Registering with an existing email/phone is a sign-in, not a duplicate
  account.
- Email and SMS are both supported; SMS adds per-message cost and
  identifier-flakiness considerations.
