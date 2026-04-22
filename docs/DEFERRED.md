# Elsewhere — Deferred Items Backlog

**Purpose:** Single canonical place for every item that's been deferred across sessions. Append-only. One file so nothing gets lost in session catalogs, commit messages, or PHASE1-NOTES subsections.

---

## Rules for using this file

**At the start of every session:**
Claude (or the human) reviews DEFERRED.md for items relevant to the session's scope. Surfaces them to the human before planning so they can be considered (promoted to the session, kept deferred, or re-scoped).

**At the end of every session:**
Any item deferred during the session gets appended to DEFERRED.md with the full entry format below — **before** the final commit. Partial context is worse than no context; write enough that future-Claude can pick it up without archaeology.

**When an item is picked up and completed:**
Mark it `**Status:** Completed in Session X.Y` in place. Do not delete — completed items are useful history.

---

## Entry format

```markdown
## Deferred: [short, concrete title]
**Deferred in:** Session X.Y
**Deferred on:** YYYY-MM-DD
**Priority:** High / Medium / Low — one-line rationale
**Area:** [Shell / Karaoke / Games / Schema / iOS / etc.]
**Status:** Deferred

### Context
What was being worked on when this came up. Why it was deferred.

### What's deferred
Specifically what work is being punted. Scope boundary.

### Options when picking up
Approaches, tradeoffs, gotchas. Enough that future-you isn't starting from zero.

### When to pick this up
Trigger conditions — "before X," "when Y arrives," "post-Phase-1," etc.

### Related
Links to other DEFERRED entries, PHASE1-NOTES sections, session plans.
```

---

## Active deferred items

---

### Deferred: Phone back-to-Elsewhere navigation + coordinated TV teardown

**Deferred in:** Session 4.10.2 testing (post-commit 7b81f70)
**Deferred on:** 2026-04-22
**Priority:** High — blocks real usage; once user is in an app, no clean way back
**Area:** Platform UX — session lifecycle
**Status:** Deferred (design partially clear; ties into multi-user model)

#### Context

Session 4.10.2's phone-as-remote loop ships the forward path: phone taps Karaoke → phone navigates to singer.html + TV navigates to stage.html. But the reverse path is missing. Once the user is on singer.html, there's no persistent "back to Elsewhere" affordance. Karaoke has its own "home" button but it goes somewhere else (within-karaoke navigation, not out-of-app). Even if the phone could navigate back to Elsewhere home, the TV would stay on stage.html — user would need to manually refresh the TV.

Current user experience: tap Karaoke on phone → stuck in karaoke until app is killed and relaunched. Not shippable as-is for real customers.

#### What's deferred

Two coordinated pieces:

**(1) Phone-side back-to-Elsewhere navigation.**
Every in-app page (`karaoke/singer.html`, `games/player.html`, future wellness pages, etc.) needs a visible "back to Elsewhere" affordance — probably a consistent top-left or top-right UI element. Tapping it should navigate the phone to the Elsewhere shell home (or directly to the TV remote-control screen, given Decision 5's n=1 skip).

**(2) TV-side coordinated teardown.**
When the phone leaves the app, the TV should return to tv2.html's apps grid. Implementation likely mirrors `launch_app`: a new realtime event (e.g., `end_session`) published by the phone on `tv_device:<device_key>`. TV listens, on receive navigates back to tv2.html.

Important design question: in a multi-user session (future), one phone leaving shouldn't kill the session for others. The natural answer is: phone-back only affects that user; the session manager can formally "end session" which navigates the TV. For Phase 1 (single-user), simplest rule is: phone-back = TV-back. Matches current mental model that phone-tapper controls the TV.

#### Options when picking up

Land as part of Session 5's multi-user work (`session_participants` + session manager role make the "who can end the session" question answerable). Or ship a Phase-1 simpler version earlier: phone-back unconditionally triggers TV-back, revisit when multi-user lands.

Phase-1 simpler version is ~1-2 hours of work:
- Add "back to Elsewhere" button to `singer.html`, `player.html`, and any other in-app pages (check what exists)
- New realtime event publish from phone on nav
- Extend tv2.html's realtime listener (already has `launch_app` handler from Part C) to handle `end_session` → navigate back to tv2.html

#### When to pick this up

High priority for real customer usability. Either:
- Ship Phase-1 simpler version as its own small session (4.10.3?) before Session 5
- Or bundle with Session 5's session-manager work

Don't defer past real customer testing.

#### Related

- DEFERRED "Multi-phone session coordination + session manager role" — ties into "who can end the session" question
- DEFERRED "Per-app role manifest" — each app declares its exit UX?
- commit `7b81f70` — Session 4.10.2's forward navigation (reverse is this entry)

---

### Deferred: Multi-phone session coordination + session manager role

**Deferred in:** Session 4.10.2 design discussion (post-Parts A+B+C testing)
**Deferred on:** 2026-04-22
**Priority:** High — platform foundation for all multi-user flows
**Area:** Platform architecture — session model
**Status:** Deferred (design decided; no implementation until Session 5+)

#### Context

Today, `tv_devices` rows track TV identity but not TV *state*. The platform has no concept of "what session is currently running on this TV." This gap is what causes multi-phone race conditions (failure modes identified during Session 4.10.2 testing: phone A taps Karaoke, phone B taps Games seconds later, TV races/hijacks/strands users).

#### What's deferred

Introduce a session concept. Each TV hosts at most one active session at a time. Session = `{tv_device, app, room_code, manager_user_id, started_at, last_activity_at}`. One user is the session manager; the role is transferable by the current manager. When any phone taps an app tile, the platform checks the TV's current session state and branches:

1. TV idle → phone launches fresh and becomes manager
2. TV on same app the phone tapped → phone joins as non-manager via app's role rules (see per-app role manifest DEFERRED entry)
3. TV on different app → blocked with "Karaoke is playing — interrupt or back?" prompt, with household admin override (admins can always hijack)

#### Options when picking up

Land with Session 5's `session_participants` schema. Likely a new `sessions` table (one row per active session, unique per `tv_device`) plus extensions to `tv_devices` for quick-read current state. Design alongside per-app role manifest — they're tightly coupled.

#### When to pick this up

Session 5, Part 1 (alongside `session_participants` + role manifest). Blocks all multi-user app flows.

#### Related

- Per-app role manifest (DEFERRED below) — defines how non-manager roles work; this entry defines the manager role and session identity
- Session manager inactivity + household-admin override (DEFERRED below) — the governance edge cases
- `docs/SESSION-4.10.2-PLAN.md` Decision 7 — original "multi-TV, multi-phone, who triggered" question that punted to Session 5
- Session 5 plan (doesn't exist yet — create when starting)

---

### Deferred: Proximity self-declaration ("are you at home?")

**Deferred in:** Session 4.10.2 design discussion (post-Parts A+B+C testing)
**Deferred on:** 2026-04-22
**Priority:** High — blocks multi-user flows; required for honest manager/singer role assignment
**Area:** Platform UX — session-state gating
**Status:** Deferred (design decided; implement with Session 5 multi-user work)

#### Context

Household membership grants TV access conceptually, but physical presence matters too. Husband at his office with Elsewhere app open shouldn't be able to act as karaoke manager for the Living Room TV that his wife is using at home. No way for the platform to detect location reliably from phone-side alone (wifi hints are not trustworthy gates; purely client-side geolocation doesn't prove proximity to a specific TV).

#### What's deferred

A trust-based self-declaration flow. On first interaction with a TV per session (and after reasonable inactivity periods or wifi-change hints), the platform asks: "Are you at home?" User answers yes or no. "Yes" unlocks manager-eligibility, singer-eligibility, active-player-eligibility. "No" keeps audience access and account/household management but blocks control roles.

Wifi-network hint (same public IP as previous "yes" answer) can skip the question — but the hint is an optimization, not a gate. Trust-based means the platform doesn't try to enforce truthfulness; if a family member lies to gain TV control, that's a household matter, not a product matter. Cross-household / non-member guest flows (scan TV QR to confirm presence) are a separate, later concern.

#### Options when picking up

Ship as part of Session 5's manager/session work. UX should be contextual: if TV is idle, ask on any TV-control attempt; if TV has active session, ask when user enters the session viewer. One concrete flow: open app → see "Living Room is playing Karaoke" → tap → "Are you in the room?" → Yes/No → appropriate participant mode.

Design note for testing: developer needs a "remember for the day" or "always at home" override so testing doesn't hit this prompt on every interaction. Capture at implementation.

#### When to pick this up

Session 5, alongside session manager concept and role manifest.

#### Related

- Multi-phone session coordination (DEFERRED above) — parent concern
- Per-app role manifest (DEFERRED) — "at home" is one of the role-entry requirements apps can declare
- Launch-conflict / multi-phone coordination (not yet filed — migrate from `docs/SESSION-4.10.2-PLAN.md` Decision 7 at 4.10.2's session-end ritual)

---

### Deferred: Session manager inactivity + household-admin override

**Deferred in:** Session 4.10.2 design discussion (post-Parts A+B+C testing)
**Deferred on:** 2026-04-22
**Priority:** High — governance edge case; required for livable multi-user UX
**Area:** Platform UX — session lifecycle
**Status:** Deferred (design partially decided; finalize during Session 5 implementation)

#### Context

When a TV session has a manager, non-managers can't launch new apps or take control. This is correct Phase-1 behavior to prevent hijack. But: what if the manager goes inactive? Kid is mid-karaoke, closes phone to take a call, wife wants to start games, can't — because kid is still formally the manager, even though they've walked away.

#### What's deferred

Two governance mechanisms.

**(1) Inactivity-based reclaim.** If the manager's phone hasn't registered activity (any session interaction: singer queue, tile-tap, app-foreground event, etc.) for a threshold duration, the session becomes "orphaned" and any household member can claim manager role. Phase-1 recommendation: 10 minutes. Worth revisiting after real usage.

**(2) Household-admin override.** Household admins (the existing 4.10 role) can always force-reclaim manager role, regardless of session state or inactivity. This is the "I'm the head of this household, I yank the remote back" escape hatch. Critical for family dynamics; without it, the platform creates governance problems it shouldn't solve.

Open questions for implementation:
- Inactivity threshold tunable per-app? (Karaoke might want 15 min; games might want 30.)
- Force-reclaim UX: silent or does manager get notified?
- If manager's phone regains activity after a reclaim, what happens? (Probably: they become a regular non-manager participant; their role was already transferred.)

#### Options when picking up

Design heartbeat + inactivity tracking alongside `session_participants`. Simplest implementation: session row stores `last_activity_at`; phone pings on interaction; any phone can query "is this session orphaned?" (`last_activity_at < now - 10min`); if yes, any household member can call `rpc_claim_manager`. Household admin override: separate `rpc_force_claim_manager` that bypasses orphan check but requires admin role.

#### When to pick this up

Session 5, tied to session manager concept.

#### Related

- Multi-phone session coordination (DEFERRED above) — parent concept
- 4.10 admin roles (`rpc_approve_household_member`, `rpc_designate_admin`) — household-admin override leverages existing admin designation
- DEFERRED "Scan-approval flow" — different admin flow but overlapping concept

---

### Deferred: Per-app role manifest for multi-user sessions

**Deferred in:** Session 4.10.2 design discussion (post-Parts A+B+C testing)
**Deferred on:** 2026-04-22
**Priority:** High — required for any multi-user app behavior
**Area:** Platform architecture — cross-cutting (affects platform + every app)
**Status:** Deferred (design only; no implementation until Session 5+)

#### Context

Part E testing of Session 4.10 exposed that the platform has no concept of "who controls a TV session." Parts A+B+C of Session 4.10.2 shipped phone-as-remote UX but still assume single-user usage. Real households are multi-user by default — husband, wife, kids each with a phone, all household members, all eligible to interact with the same TV.

Session 4.10.2 design discussion worked out the multi-user model: one TV hosts at most one active session, one user is the session manager, manager can transfer the role, non-managers interact with the session through app-specific roles (singer, player, audience, etc.).

The specific roles are per-app, not platform-uniform. Karaoke has "singer" (one at a time, request-based). Games has "player" (rules vary per game) and "manager" (one). Wellness has "participant" and "audience." New apps will invent new roles. The platform shouldn't hardcode knowledge of singers or games or breathing exercises.

#### What's deferred

Design and implement a declarative per-app role manifest. Each app (karaoke, games, wellness, future apps) declares:

- What roles exist in the app (singer, player, audience, etc.)
- How each role is entered (open join / request-to-manager / restricted / manager-only)
- What each role requires (household membership / TV-device presence / "at home" confirmation / open to anyone)
- Capacity rules (one singer at a time, N players max, unlimited audience, etc.)
- Default role for a user tapping the app tile when the session is active (usually "request singer" or "join audience" — app-specific)

The platform reads these manifests and:
- Routes a phone tap on an active TV session to the right flow (request vs join vs blocked)
- Enforces capacity and permission rules uniformly
- Surfaces "who's in what role" on the phone's TV-state display

App-internal UX (karaoke's singer queue with song search, games' lobby vs active-game join flow) lives in each app's HTML file, not in the manifest. Manifest only declares structure; apps implement their own role-specific UIs.

#### Options when picking up

- **Land with Session 5's session_participants schema.** The manifest + session_participants are natural partners: manifest declares roles, session_participants tracks who holds each role. Design together.
- **Could land earlier** as a standalone design exercise if Session 5 gets pushed. But implementation requires session_participants, so design-only doesn't unblock anything.

Don't try to design the manifest schema now. Too many unknowns until we're building the first real multi-user flow (likely karaoke singer queue). Design when concrete.

#### When to pick this up

At the start of Session 5, as part of session_participants schema design. Should be Part 1 of Session 5's scope: "design the role manifest + session_participants together, then build karaoke's multi-user flow as the first user of both."

#### Related

- Session 5 plan (doesn't exist yet — create docs/SESSION-5-PLAN.md when starting that session, with this entry as a required input)
- Launch-conflict / multi-phone coordination (not yet filed as a DEFERRED entry — see docs/SESSION-4.10.2-PLAN.md Decision 7 and "Deferred items likely to emerge". Migrate to DEFERRED.md at 4.10.2's session-end ritual.)
- docs/SESSION-4.10.2-PLAN.md — original plan, pre-dates this insight

---

### Deferred: Phone-as-remote — persistent app launcher on phone, display-only grid on TV
**Deferred in:** Session 4.10 (Part E Flow 1)
**Deferred on:** 2026-04-21
**Priority:** High — blocks real product usability before customer acquisition. Two problems: post-claim phone dead-end, and no way to resume TV control after relaunching the phone app.
**Area:** Shell / tv2.html / cross-device UX / phone-side TV list
**Status:** Deferred

#### Context
Session 4.10 Part E Flow 1 surfaced that post-claim, the phone drops the user at a dead-end "head to the TV" success screen while the TV shows an interactive "Choose an app" grid — mental model inverted. Phone is always in hand; TV is out of reach.

A second gap: relaunching the phone app lands the user on the generic home screen with no entry point back to controlling the TVs they're a member of. To resume TV control they'd have to re-scan a QR — except the TV is on the apps grid with no QR showing.

#### What's deferred
Three coupled pieces:

1. **Phone home-screen becomes "Your TVs"** when user has one or more `tv_devices` in their households. Queries `tv_devices` (RLS-filtered), shows a tile per TV with household name + `tv_display_name` + `last_seen_at` indicator. Tapping a TV enters "remote control" mode.

2. **Remote-control screen on phone** shows the 3 apps (Karaoke / Games / Wellness) as tiles. Tapping a tile:
   - Generates a room code (or delegates to TV)
   - Publishes a `launch_app` broadcast on the `tv_device:<device_key>` channel with `{app, room}`
   - TV's tv2.html subscribes to `launch_app` in addition to `session_handoff`, navigates to the product page when received

3. **TV's apps grid becomes display-only.** Still shows 3 tiles for visual parity, but subtitle text reads "Use your phone to select an app" and click handlers are removed (or replaced with a gentle tooltip).

Post-claim success screen on phone transitions directly into #2 for the TV just claimed, so first-launch is seamless.

#### Options when picking up
- **Minimal version:** no new DB tables. Phone queries `tv_devices` + `households` on launch (already works under RLS). Remote-control mode uses the `tv_device:<device_key>` realtime channel (already subscribed by TV post-4.10). Broadcast payloads just get a new event name (`launch_app`) alongside `session_handoff`. Fits in one session.
- **Bigger version:** introduces "active session" as a proper DB concept (Session 5 `session_participants` territory). Minimal version slots cleanly into this later — same broadcast shape survives.

#### When to pick this up
Session 4.10.2 or Session 4.11, before any real customer acquisition. Blocks core product usability.

#### Related
- `docs/PART-E-VERIFICATION.md` Flow 1 — where post-claim gap surfaced
- Session 5 `session_participants` — bigger refactor this foreshadows
- Session 4.10 Plan — current design missed both gaps
- `tv_device:<device_key>` realtime channel — re-used for `launch_app`

---

### Deferred: TV sign-in screen copy implies wrong direction of action
**Deferred in:** Session 4.10 (Part E Flow 2)
**Deferred on:** 2026-04-21
**Priority:** Medium — confuses onboarding but doesn't block
**Area:** Shell / `screen-tv-signin` copy
**Status:** Deferred

#### Context
Session 4.10 Part E Flow 2 verification surfaced that the phone's signin screen reads "Sign in on TV" as its title, implying the user should go do something on the TV. In reality, the phone is doing the auth work and the TV just reflects the result. Copy gets the active agent wrong.

User quote from the Part E run: *"the phone says 'Sign in on TV' but there is nothing to sign in on at the TV — this is confusing."*

#### What's deferred
Update `screen-tv-signin` copy in index.html:
- **Title** becomes "Signing in to `<household name>`" once the status resolves, or "Signing you in…" while status is pending (replaces "Sign in on TV")
- **Sub-text before status** reframes as "Authenticating with your household" (replaces "Connecting…")
- **Sub-text on success** becomes "Done. Your TV is ready." (replaces "Head to the TV to continue")

The "Head to the TV" message is technically accurate for the pre-phone-as-remote design but loses relevance once the phone becomes the primary launcher — this copy pass should be revisited again when phone-as-remote lands.

#### Options when picking up
- **Land together with the phone-as-remote milestone (4.10.2)** — that's already a cross-cutting copy pass on signin + claim flows; fold this in naturally.
- **Standalone 5-minute patch** — if phone-as-remote slips, fix this in any smaller session as a one-file index.html copy edit. No schema, no realtime changes, just string swaps.

#### When to pick this up
Whenever `screen-tv-signin` copy is next touched, OR at the start of 4.10.2, whichever comes first. Don't defer past customer acquisition.

#### Related
- DEFERRED.md → "Phone-as-remote — persistent app launcher on phone" — same family of issue, larger scope
- `docs/PART-E-VERIFICATION.md` Flow 2 — where this surfaced
- `index.html` → `screen-tv-signin` markup — location of the copy to update

---

### Deferred: Phone-based household pre-invites (SMS verification)
**Deferred in:** Session 4.10 (planning)
**Deferred on:** 2026-04-21
**Priority:** High — **fast-follow**, target Session 4.10.1 (between 4.10 and 4.11)
**Area:** Schema / Shell / Supabase auth
**Status:** Deferred

#### Context
Session 4.10 introduces `pending_household_invites` with columns for both `email` and `phone`. At implementation time, only email-based pre-invites are wired up. The phone column exists in the schema but is not yet usable.

Reason for deferral: phone-based matching requires the user to have a verified phone number on their Supabase account. Supabase supports this via SMS OTP auth, but enabling it requires Twilio integration, per-message cost, and new phone-number sign-up/verification UX. Too much to bundle into 4.10.

#### What's deferred
1. Enabling SMS OTP auth in Supabase (Twilio configuration + cost decisions)
2. Phone-number capture + verification flow on first sign-up (or as an add-on to existing accounts)
3. Wiring phone-match into `rpc_request_household_access` so a user with a verified phone matching a `pending_household_invites.phone` row gets auto-admitted
4. Admin UI for phone-based pre-invites (add to the household-invite UI being built in 4.11)

#### Options when picking up
- **Twilio via Supabase's built-in SMS provider integration** — standard path, per-message cost ($0.0075-ish per SMS in US)
- **Alternative SMS provider** (MessageBird, Vonage) — Supabase supports custom SMS templates; might save money at volume
- **Defer further and skip SMS entirely** — only use phone as a non-verified hint. Not recommended; defeats the auto-admission security story

#### When to pick this up
Target: Session 4.10.1 (new micro-session slot between 4.10 and 4.11). Should land before 4.11 (admin management UI) so admins can add phone pre-invites from day one of that UI, not retrofit later.

Escalation trigger: if 4.10.1 slips and 4.11 starts without it, note explicitly in 4.11 plan that phone UI is stubbed.

#### Related
- SESSION-4.10-PLAN.md → Data model → Table 4 (`pending_household_invites`)
- **Action required:** When Session 4.10's Part F adds the Session Catalog row to PHASE1-NOTES.md, also add a Session 4.10.1 row marked 🔜 with this scope. That reserves the slot and makes the planned work visible in the catalog alongside the deferred entry here.

---

### Deferred: claim.html App Store URL placeholder
**Deferred in:** Session 4.10 (Part B)
**Deferred on:** 2026-04-21
**Priority:** High — blocks real user onboarding for anyone without the app installed
**Area:** claim.html / onboarding
**Status:** Deferred

#### Context
Session 4.10 Part B ships `claim.html` as the intermediate landing page between the TV's QR code and the iOS app's `elsewhere://tv-claim` deep link. When the app isn't installed on the scanning phone, claim.html's 1.5s timeout reveals a "Get Elsewhere on the App Store" button. At implementation time, no App Store listing exists yet, so the button's `href` is a placeholder (`#` with "coming soon" copy).

#### What's deferred
Replace the placeholder `href` in `claim.html` with the real App Store URL once the listing goes live. Approximately a single-line change.

#### Options when picking up
1. Open `claim.html`, locate the App Store button, swap the `href`. Update the button label / surrounding copy if needed (e.g. drop "coming soon" wording).
2. If the listing also publishes a Smart App Banner meta tag, add it to `<head>` so Safari surfaces the native install prompt before users even tap the button.

#### When to pick this up
When the Elsewhere iOS App Store listing exists. Must land before any real user-acquisition campaign — the "scan → install → claim" path is broken for non-users without a real App Store URL. Until the listing is up, only users who already have the app via TestFlight or ad-hoc build can complete the flow.

#### Related
- SESSION-4.10-PLAN.md → Scope → claim.html intermediate landing
- Part B commit — claim.html first landed with placeholder

---

### Deferred: tv2.html render race — concurrent renderCurrentState calls
**Deferred in:** Session 4.10 (Part C)
**Deferred on:** 2026-04-21
**Priority:** Low — correctness is fine; only cosmetic flicker possible
**Area:** TV / tv2.html
**Status:** Deferred

#### Context
Session 4.10 Part C's `tv2.html` kicks off an async `renderCurrentState()` at boot (step 5 of the boot sequence). If a realtime `session_handoff` arrives before that initial render completes, the handoff handler also calls `renderCurrentState()` — two concurrent invocations. Both query `rpc_tv_is_registered` independently and both transition screens via `goTo(id)`.

Final state resolves correctly (both see the same DB row; both decide to show apps). But the ordering is non-deterministic: the user may briefly see the claim or sign-in screen flash before apps settles in. Correctness ✓, aesthetics ✗.

#### What's deferred
Serializing `renderCurrentState()` so only one invocation ever transitions the UI at a time. Two implementation options:
1. **Render-epoch counter** — module-level counter; each call bumps it and captures its epoch at entry; at the `goTo(id)` site, only transition if the captured epoch still matches the current global. Stale renders no-op.
2. **Rendering lock** — module-level in-flight Promise; a second call awaits the first before executing. Simpler but serializes cost.

Either pattern works; epoch counter is the cheaper fix.

#### Options when picking up
- Add `let renderEpoch = 0;` at module top
- At entry: `const myEpoch = ++renderEpoch;`
- Before `goTo(id)`: `if (myEpoch !== renderEpoch) return;`
- That's the whole patch, probably 3-4 lines

Alternative: accept the flicker as negligible and close this without implementing.

#### When to pick this up
Post-Session-5 polish pass. Flicker would need to actually annoy someone to justify the fix. If no complaints by end of Phase 1, deprioritize further.

#### Related
- SESSION-4.10-PLAN.md → Session handoff section
- tv2.html boot sequence `renderCurrentState()` + `handleSessionHandoff()` at the module-level script

---

### Deferred: Part E Flows 3 + 4 — guest access + pre-invited member verification
**Deferred in:** Session 4.10 (Part E)
**Deferred on:** 2026-04-21
**Priority:** Medium — before customer acquisition
**Area:** Verification / QA / Shell
**Status:** Deferred

#### Context
Session 4.10 Part E ran end-to-end verification of the new auth flow (TV claim, returning sign-in with session handoff, stage.html admin gear under production auth). Two of the five planned flows require a second Supabase account to exercise, which wasn't available during the Part E run. Flows 1, 2, and 5 were executed and signed off — see `docs/PART-E-VERIFICATION.md`.

#### What's deferred

**Flow 3 — Guest access (scan TV as non-member, no pre-invite):**

Requirements: A second Supabase account (user 2) that is NOT a member of user 1's household, and NOT present in `pending_household_invites` for that household.

Steps:
1. User 1 (admin): complete Flow 1 to claim a TV into household A. TV shows apps grid.
2. Clear laptop browser session (per Flow 2 Step 1 snippet) so TV shows the sign-in QR for household A.
3. User 2 signs in on phone.
4. User 2 scans the TV's sign-in QR with iPhone camera.
5. Expected RPC path: on the phone's handling of `elsewhere:tv-signin`, the shell calls `rpc_request_household_access` (or the signin equivalent) with user 2's auth. It sees user 2 is not a member and has no pending invite.
6. Expected outcome: either
   (a) user 2 gets an "access denied — ask an admin to invite you" screen, OR
   (b) user 2 proceeds as a **guest** — ephemeral session on that TV without a `household_members` row.
7. The intended Phase 1 behavior per SESSION-4.10-PLAN.md's Roles table is option (b) for now (guest mode), but the UX is untested.

**⚠ Structural question to resolve when picking this up:** the scan-approval flow for non-members is itself separately deferred (see "Scan-approval flow (request-to-join household in real time)" entry below, target Session 4.11). Depending on what lands in 4.11, Flow 3 may need to be rewritten against the new admin-approval surface instead of guest-mode.

**Flow 4 — Pre-invited member (auto-admit on first scan):**

Requirements: A second Supabase account (user 2) + an admin pre-invite.

Steps:
1. User 1 (admin) adds a `pending_household_invites` row for user 2's email. When the household management UI ships (4.11), do this via the UI. Until then, direct SQL works:
   ```sql
   insert into pending_household_invites (household_id, email, invited_by)
   values ('<household-a-id>', '<user-2-email>', '<user-1-id>');
   ```
2. User 2 signs in on phone.
3. User 1's TV is in sign-in state (Flow 2 Step 1 state).
4. User 2 scans the sign-in QR.
5. Expected RPC path: `rpc_request_household_access` matches the `pending_household_invites.email` against user 2's auth email. Auto-admits: inserts `household_members` row with `joined_via = 'pre_invite'`, deletes the pending invite row.
6. Expected outcome: user 2 lands on apps grid for household A as a full member (not guest). Handoff delivers session to the TV via realtime channel.
7. Verify in DB: `select * from household_members where user_id = '<user-2-id>'` returns a row with the correct household_id and `joined_via = 'pre_invite'`.

#### Options when picking up
- **Create a throwaway test Supabase account** — simplest path. Gmail + "test" alias works.
- **Use a real household member's phone** — more realistic but depends on social setup.
- **Resolve the Flow 3 structural question first** — check whether the Session 4.11 scan-approval flow has landed. If yes, rewrite Flow 3 against that new UX. If no, test the Phase 1 guest-mode path as originally specified.

Before running, also verify the shell-side UX: does index.html have a screen that gracefully handles both "you're not a member, here's how to request access" AND "pre-invite found, auto-admitted"? If absent, that's a scope gap to surface before running these flows.

#### When to pick this up
Before any real customer-acquisition campaign. These flows are critical-path for multi-member households — the primary value prop is "multiple people use the same TV." Until Flow 3 + Flow 4 are verified end-to-end, onboarding a second user into an existing household is unverified territory.

Latest acceptable slip point: end of Session 4.11 (admin UI), because 4.11's scope depends on these flows working structurally.

#### Related
- SESSION-4.10-PLAN.md → Roles table (`guest`, `pre_invite` joined_via values)
- docs/PART-E-VERIFICATION.md → Flows 1, 2, 5 (completed)
- DEFERRED.md → "Scan-approval flow (request-to-join household in real time)" — structural dependency for Flow 3
- DEFERRED.md → "Phone-based household pre-invites (SMS verification)" — when this lands, Flow 4 gains a phone variant worth adding to the checklist

---

### Deferred: Audit inline-script TDZ risk in other pages
**Deferred in:** Session 4.10 (Part E verification)
**Deferred on:** 2026-04-21
**Priority:** Low — no known live bugs, but the pattern that broke tv2.html likely exists elsewhere
**Area:** Inline `<script>` blocks across pages
**Status:** Deferred

#### Context
During Session 4.10 Part E verification, tv2.html threw `Uncaught ReferenceError: Cannot access '_logs' before initialization` on boot. Root cause: an async IIFE at the top of the inline script called `tvLog()` on its first line. `tvLog` was a function declaration (hoisted), but the `const _logs = []` array it mutated was declared further down in a "Log" section and hit the temporal dead zone (TDZ) when accessed from the boot path.

Fixed by hoisting `const _logs = []` to module-top state alongside `DEVICE_KEY_STORAGE` etc., with an inline comment at the new position explaining why it must stay hoisted.

#### What's deferred
An audit of the other large inline-script files in the repo for the same shape of bug:
- `index.html` — shell inline script, calls helpers during boot
- `karaoke/stage.html` — ~5k lines, many IIFEs and boot-time calls
- `karaoke/singer.html`, `karaoke/audience.html`
- `games/tv.html`, `games/player.html`

Look for: a hoisted `function` invoked (directly or via an IIFE chain) before the module body executes the `const`/`let` it references. No clean regex catches this — manual boot-sequence review per file is the practical approach.

#### Options when picking up
- **Per-file boot-order review** — read each file's top-of-script, trace which helpers are called before which `const`/`let` declarations execute. Hoist any affected state declaration with a `// Hoisted because …` comment (mirroring tv2.html's pattern).
- **Move each IIFE boot block to the bottom of its script** — structural change, higher churn, not recommended.

Don't silently convert `const`/`let` to `var` to sidestep TDZ — loses scope safety, and the real fix (hoist the state declaration) is cheaper.

#### When to pick this up
Opportunistically. When next touching any of the listed files for other reasons, spend 2 minutes on a boot-order sanity check. A full proactive audit isn't warranted — the specific shape (TDZ from inside an IIFE-called helper) is rare, and every listed page has been exercised end-to-end.

#### Related
- `tv2.html` — `_logs` hoisted with explanatory comment (the reference implementation)
- Session 4.10 Part E verification pass — where the bug surfaced

---

### Deferred: Home-screen flash before auto-route on app launch

**Deferred in:** Session 4.10.2 testing (post-commit 56e6e3d)
**Deferred on:** 2026-04-22
**Priority:** Low — cosmetic, not functional
**Area:** Shell UX — auth/routing timing
**Status:** Deferred

#### Context

On app launch, the default `screen-home` is visible while auth state hydrates and `loadUserTvs()` query runs. For n=1 users who auto-route to screen-tv-remote (per Decision 5), there's a visible flash of the home tile-grid before the remote screen replaces it. Observed at ~100-500ms on fast networks; likely longer on slow networks.

Flow causing the flash:
1. DOM loads with `screen-home` marked active (default markup state)
2. Home tile-grid renders
3. Shell JS initializes, `window.sb` created, auth state hydrates
4. `renderAuthState(user)` fires
5. `resumePendingTvFlow()` returns false
6. `enterYourTvsFlow()` fires, `loadUserTvs()` async query runs
7. Result comes back (n=1), `enterTvRemoteScreen()` navigates away
8. User sees remote screen

The flash is the visible gap between steps 2 and 7.

#### What's deferred

Eliminate or mask the flash. Two viable approaches:

1. **Loading screen default.** Make a minimal spinner/blank screen the default active screen on boot. `enterYourTvsFlow` replaces it with the correct destination. Requires adding a new screen and updating default markup state.
2. **Home with loading overlay.** Keep `screen-home` active by default but render a dimming overlay + spinner until auth+query complete. Less disruptive to existing shell structure.

Both are ~15-30 min of shell work.

#### Options when picking up

Opportunistic — land during any future session that touches shell initialization or auth routing. Session 5's multi-user work will likely touch `renderAuthState`; good candidate to bundle this fix.

#### When to pick this up

Low priority. No user-blocking behavior. Pick up when polish work cycle permits or bundled with adjacent shell changes.

#### Related

- `enterYourTvsFlow` / `renderAuthState` hook in `index.html`
- `shell/auth.js` initialization
- DEFERRED "Phone-as-remote" (parent — this flash is polish on the flow that entry establishes)

---

### Deferred: Scan-approval flow (request-to-join household in real time)
**Deferred in:** Session 4.10 (planning)
**Deferred on:** 2026-04-21
**Priority:** Medium — target Session 4.11 (admin management UI)
**Area:** Shell / Schema / Admin UX
**Status:** Deferred

#### Context
When a user scans a household TV without a pre-invite, Session 4.10 treats them as a **guest** — they can launch apps on that TV but don't become a household member. The "request to join + admin approves in real time" flow (where scanning triggers an admin notification → admin taps approve in shell → scanner becomes a full member) is deferred.

#### What's deferred
- Admin-side notification when a non-member scans a household TV
- Admin-side UI to review scan requests and approve/deny
- Client-side "your request is pending" state (if we want scanners to know they've been noticed)
- The `rpc_approve_household_member` RPC **is built in 4.10** (plumbing in place) but not called by any UI until 4.11

Workarounds in 4.10:
- Admin pre-invites the user by email **before** they arrive → auto-admit on scan
- Admin uses 4.11's management UI **after** the guest's visit to retroactively add them as a member

Neither workaround breaks the flow — guests can still use TVs for apps; they just aren't persistent members until 4.11 lands.

#### Options when picking up
Build alongside 4.11's household management UI:
- Admin sees a "Scan Requests" section with pending guests
- Approve button creates the `household_members` row via `rpc_approve_household_member` (already exists from 4.10)
- Optionally: decline button (records in some decline log, prevents repeat prompts)
- Real-time notification delivery: use same Supabase realtime pattern as TV session handoff, or poll-on-focus

#### When to pick this up
Session 4.11. This is listed in that session's scope alongside the broader household admin management UI.

#### Related
- SESSION-4.10-PLAN.md → RPCs → `rpc_approve_household_member` (built, not exercised)
- SESSION-4.10-PLAN.md → Roles → "scan_approved" joined_via enum value

---

### Deferred: "Pending Invitations" inbox UI in iOS shell
**Deferred in:** Session 4.10 (planning)
**Deferred on:** 2026-04-21
**Priority:** Low — polish, not blocking
**Area:** Shell / iOS app
**Status:** Deferred

#### Context
Session 4.10's `pending_household_invites` table supports a nice UX where a user who's been pre-invited to a household sees "You have 3 pending invitations" in their shell, with a list they can tap to accept/decline. This would add an RLS policy letting users read invite rows where `lower(email) = auth.jwt() email claim`.

#### What's deferred
- The UI (an "Invitations" tile or badge in the shell)
- The RLS policy allowing invitees to read their own pending invites (requires joining against `auth.users` email or reading from JWT — works but has performance and testing overhead)

Session 4.10 ships without this: pre-invited users learn about the invite out-of-band (admin tells them verbally or via text). When they physically arrive at the household TV and scan, auto-admission happens. The only user-facing friction is "you need to be at the household to activate your membership."

#### Options when picking up
- Straightforward RLS policy + shell screen — probably a 1-2 hour session as a standalone polish task
- Could also extend to "session invitations" when Session 5 ships, so there's one unified inbox

#### When to pick this up
After Session 5 ships. Combine with session invitations for a unified "Invitations" surface — avoids building two separate inboxes.

#### Related
- SESSION-4.10-PLAN.md → Data model → Table 4 (`pending_household_invites`)
- Session 5 (future) — session participant invitations

---

### Deferred: Deferred-deep-link post-install experience
**Deferred in:** Session 4.10 (planning)
**Deferred on:** 2026-04-21
**Priority:** Medium — improves onboarding, not blocking
**Area:** Shell / iOS app / QR flow
**Status:** Deferred

#### Context
Session 4.10 introduces TV-claim-via-QR: TV shows a QR code, user scans with phone, opens the Elsewhere app, authenticates, and claims the TV into their household. Works great if the user already has the app installed.

#### What's deferred
The "scan → app not installed → install → app opens with `device_key` preserved → claim completes automatically without the user needing to return to the TV and re-scan" experience. This is the "deferred deep link" pattern.

Session 4.10 ships **Option 2**: QR encodes an https:// URL (not `elsewhere://` directly). That URL is a tiny web page that tries the `elsewhere://tv-claim?device_key=X` deep link. If the app is installed, the deep link opens it. If not, the web page redirects the user to the App Store. User installs, then must return to the TV and re-scan to claim.

#### Options when picking up
- **Branch.io** — paid tier, turnkey deferred deep link service
- **Firebase Dynamic Links successor** — Firebase announced sunset in 2025; check for official Google replacement
- **Custom** — backend endpoint stores `{install_nonce → device_key}` pairs. Install page copies nonce to clipboard or embeds in app bundle metadata. App on first launch checks backend, resolves nonce, resumes claim

#### When to pick this up
Before real customer-acquisition campaigns. First-time onboarding UX matters most when prospective users don't already know Elsewhere. In Phase 1 (friends-and-family), Option 2's "scan twice" flow is acceptable because the first scan is usually the household admin (who can be told to install first via any channel).

#### Related
- SESSION-4.10-PLAN.md "Scope" section
- PHASE1-NOTES.md → "Phase 1 invite distribution (manual)" architecture decision (aligned philosophy: Phase 1 tolerates manual onboarding seams)

---

## Migrated from PHASE1-NOTES.md

The entries below were moved from PHASE1-NOTES.md on 2026-04-21. They are captured here in summary form; the full original text lives in PHASE1-NOTES.md git history (commit `9296a50` or earlier). Future fill-outs should flesh these into the full entry format above when someone picks one up.

### Deferred — Karaoke
- [ ] ~~Create `venues.json` metadata file with product tags when wellness needs it~~ — shipped in Session 4.9 Part A
- [ ] DeepAR `background_segmentation` jsdelivr 404 — karaoke/stage.html falls back to MediaPipe, low priority
- [ ] ~143 text-tone hardcoded colors deferred from Session 1 color audit — rebrand-safe enough for now
- [ ] Extract ambient venue effects into shell/venue-effects.js when wellness work begins
- [ ] Move karaoke performance effects (DeepAR filters, confetti) formally under karaoke/effects/
- [ ] Laptop/TV production auth path for karaoke/stage.html (Session 4.10+) — **being addressed by 4.10**
- [ ] Tune back_yaw / back_pitch for remaining venues via admin dialog (most NULL today)
- [ ] Bug: karaoke/stage.html line ~3085 has `if(viewMode==='singer')` — dead branch, no functional impact
- [x] ~~tv2.html camera init: currently requests camera permission during setup. Per architectural decision, should lazy-init only when entering a camera-requiring product~~ — **Resolved in Session 4.10 Part C.** tv2.html rewritten to a boot-only launcher (claim / signin / apps grid). No camera preview, no DeepAR init, no Agora watchers. Camera permission is now first requested by the product page the user launches (karaoke/stage.html, games/tv.html), which is the correct lazy-init surface per the original architectural decision.

### Deferred — Games
- [ ] Lobby state fragility — broadcast-ephemeral lobbyPlayers[] diagnosis; session 5 structural fix via session_participants
- [ ] Last Card end-game state leakage — investigated, deferred pending repro
- [ ] Direct-launch UX — when user opens games/player.html with no room code
- [ ] Player tile avatar unification — currently inconsistent across tile types
- [ ] v2.93.2 testing TBD — carried forward

### Deferred — UX Refinements
- [ ] Top-nav relocation — current top-right cluster too dense
- [ ] Modal dismissal pattern — standardize vs. backdrop-click behavior
- [ ] Copy button feedback — confirm visual affordance on Copy actions
- [ ] Room-code de-emphasis — post-invite-flow, room codes become less prominent
- [ ] Searchable contacts — current contact list is scroll-only
- [ ] Profile photo capture — avatar currently initials-only

### Pre-Session 5 Blockers
- [ ] **Games deep-link auto-manager bug** — `games/player.html` lines 928-929: `mgrCheck.checked = true` fires unconditionally on every `elsewhere://games?...` deep-link arrival, making every invitee a manager of the room they join. Breaks single-manager assumption across games code. **Scope: games only.** Does NOT affect Session 4.10 (different deep-link URLs, different handler). Fix options: (a) gate on `?role=manager` URL param, or (b) remove auto-check and trust URL `?mgr=1` exclusively. Structurally resolved by Session 5 when `session_participants` replaces ad-hoc manager flag. Logged: Session 4.8 (v2.98, commit `e3aaa05`). Still live as of v2.99.
- [ ] Lobby state fragility (also listed in Games) — gets structurally resolved by session_participants schema

### Phase 2 Deferred
- [ ] Auth enhancements beyond magic-link / password / QR
- [ ] Invite-flow extensions post-Session-5
- [ ] TV/device rendering optimizations
- [ ] Contacts + groups polish beyond current CRUD

---

## Completed items

*(Move entries here when they're addressed. Keep the full original entry — just update **Status** to `Completed in Session X.Y` and add a one-line completion note.)*

None yet.
