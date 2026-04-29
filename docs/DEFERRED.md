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
- docs/PHONE-AND-TV-STATE-MODEL.md — defines the manager orphan timeout as one of three platform-level configurable timeouts. 10-min default is from this entry; the state model doc references it.

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

### Deferred: Audience back-to-Elsewhere navigation

**Deferred in:** Session 4.10.3 scope adjustment (pre-Part B)
**Deferred on:** 2026-04-22
**Priority:** Medium — not blocking; partial escape exists via karaoke in-app home button
**Area:** Platform UX — session lifecycle, role-dependent
**Status:** Completed in Session 5 Part 2c.3.2

#### Context

Session 4.10.3's Part B originally scoped a back-to-Elsewhere button onto both `karaoke/singer.html` AND `karaoke/audience.html`. During pre-implementation review, the audience.html case was pulled because its role semantics aren't specified yet:

- How audience members join the session (household member? guest? passive observer with no account?)
- Whether audience members have agency to leave the current app (is "back" even meaningful for a non-member?)
- What "home" means for them — if they're not a household member, landing on `screen-home` is a dead-end

These answers depend on Session 5's per-app role manifest work, which will formalize how apps declare their roles and what capabilities each role has. Shipping a back button with unclear semantics now risks either (a) giving non-members a confusing dead-end destination, or (b) locking in Phase-1 behavior that Session 5 has to walk back.

The audience path has the karaoke in-app "home" button as a partial escape — a user on audience.html can use within-karaoke navigation to leave the audience role — so this gap isn't totally blocking. Just unresolved.

#### What's deferred

Add a back-to-Elsewhere button to `karaoke/audience.html` once Session 5's role manifest clarifies:
- Who can reach audience.html (household members only, or guests/passive observers too)
- What destination makes sense for each role after tapping back
- Whether the TV teardown should fire (audience leaving ≠ session ending, if other singers/players remain)

Also extends to any future audience-equivalent pages (e.g., hypothetical games/spectator.html, wellness audience modes).

**Prerequisite:** audience.html currently lacks `viewport-fit=cover` in its viewport meta. Add it before the back button, or the button will render behind iOS status bar (singer.html hit this during 4.10.3 Part B; see commit `50a9f5c`).

#### Options when picking up

Bundle with Session 5's role manifest design + implementation. The role manifest will declare, per audience role:
- Who qualifies for entry (household membership? invite? open?)
- What "leaving the app" does (session teardown? just leave role?)
- What phone destination is appropriate on back-tap

Then the back button implementation becomes a mechanical application of those declared rules — no new design decisions at implementation time.

Alternative: ship a Phase-1 button now that unconditionally navigates phone to `../index.html` and publishes `exit_app` like singer.html does. This was the original Part B plan. Rejected during scope review because it hardcodes semantics that Session 5 may need to override.

#### When to pick this up

During Session 5, alongside the per-app role manifest implementation. Don't land standalone — the semantics can't be settled in isolation.

#### Related

- DEFERRED "Per-app role manifest for multi-user sessions" — design dependency
- DEFERRED "Multi-phone session coordination + session manager role" — audience is a non-manager role, relevant to session-ownership questions
- `docs/SESSION-4.10.3-PLAN.md` — Part B's scope-down decision documented inline
- commit `f43369a` — Part A of 4.10.3 (exit_app realtime wiring; audience.html already capable of calling publishExitApp if a button were added later)

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

### Deferred: Extract publishExitApp + related realtime helpers into shell/realtime.js

**Deferred in:** Session 4.10.3 session-end (per plan's "Deferred items likely to emerge")
**Deferred on:** 2026-04-22
**Priority:** Low — no functional impact; inline duplication is manageable through Phase 1
**Area:** Shell / infrastructure — realtime helpers
**Status:** Completed in Session 5 Part 1c (commit `9e10bf4`)

#### Context

Sessions 4.10, 4.10.2, and 4.10.3 incrementally added Supabase realtime event publishers and listeners across the phone and TV pages. Each is a ~30-line inline function that subscribes to the `tv_device:<device_key>` channel, sends a broadcast, and tears down the channel (or the listener mirror for receivers). The pattern is identical across every consumer.

**Publishers (phone/shell side):**
- `publishSessionHandoff` — `index.html`, added in Session 4.10 Part B (commit `b9b3ca1`)
- `publishLaunchApp` — `index.html`, added in Session 4.10.2 Parts A+B (commit `4a331d6`), refined in await fix (`7b81f70`)
- `publishExitApp` — inlined in three places:
  - `index.html`, added in Session 4.10.3 Part A (commit `f43369a`)
  - `karaoke/singer.html`, added in Session 4.10.3 Part B (commit `2c2d5fe`)
  - `games/player.html`, added in Session 4.10.3 Part C (commit `40e4f4b`)

**Listeners (TV side):**
- `handleSessionHandoff` — `tv2.html`, added in Session 4.10 Part C (commit `e2bc6bb`)
- `handleLaunchApp` — `tv2.html`, added in Session 4.10.2 Part C (commit `4372a20`)
- `handleExitApp` — inlined in two places:
  - `karaoke/stage.html`, added in Session 4.10.3 Part A (`f43369a`)
  - `games/tv.html`, added in Session 4.10.3 Part A (`f43369a`)

Each consumer has its own copy of the subscribe-send-unsubscribe-removeChannel ceremony (or the subscribe-listen-unsubscribe ceremony for receivers). This works fine at today's volume of 3 events × 5 consumers, but it's N² boilerplate that will explode when Session 5 adds `session_participants` events (e.g., `member_joined`, `member_left`, `session_ended`, `manager_transferred`, potentially more).

Also noted in the Session 4.10.3 plan's "Scope / On ship, also do" section and in "Deferred items likely to emerge."

#### What's deferred

Create `shell/realtime.js` that exports:

- A shared `publish(device_key, event, payload)` helper encapsulating the subscribe → send → unsubscribe → removeChannel pattern (5s subscribe timeout, error-throwing on channel errors, etc.)
- A shared `subscribe(device_key, handlers)` helper for listeners — `handlers` is `{[event]: callback}` map; returns a teardown function
- Named wrappers for each event (`publishExitApp`, `publishLaunchApp`, etc.) that just call the base helper with the event name

Consumers replace their inline ~30-line function with a ~3-line call. Estimated cumulative diff: ~200 lines removed, ~60 lines added (shell/realtime.js), net ~140-line reduction across the codebase.

#### Options when picking up

Bundle with Session 5's multi-user work — that's when the number of realtime events crosses the threshold where the duplication becomes painful. Extract all existing helpers (session_handoff, launch_app, exit_app) at the same time; Session 5 adds its new events using the helper from day one.

Alternative: extract sooner as a standalone polish commit if something else drives touching these pages (e.g., a bug fix across realtime behavior). Unlikely to be worth a dedicated session on its own.

#### When to pick this up

During Session 5, before any new realtime events get inlined. Adding `session_ended` / `member_joined` / etc. inline would compound the duplication and make the eventual extraction larger.

Don't defer past Session 5.

#### Related

- Session 4.10.3 plan ("Scope / On ship, also do" + "Deferred items likely to emerge") — source of this entry
- DEFERRED "Per-app role manifest for multi-user sessions" — Session 5 scope cluster
- DEFERRED "Multi-phone session coordination + session manager role" — adds new events that will drive extraction
- Commits enumerated above — consumers of the inline pattern today

---

### Deferred: Post-claim direct transition to remote-control screen (4.10.2 Part E)

**Deferred in:** Session 4.10.3 session-end (carried forward from 4.10.2 plan, Part E)
**Deferred on:** 2026-04-22
**Priority:** Low-medium — user-facing UX gap but not blocking
**Area:** Shell / post-claim flow
**Status:** Completed in Session 4.10.2 Part E (shipped 2026-04-22 as follow-up via 4.10.3 cycle, commit `b994df7`)

#### Context

Session 4.10.2's plan included Part E: after a user successfully claims a new TV via the phone claim flow, the phone should auto-route into `screen-tv-remote` for the newly-claimed TV (same pattern as 4.10.2 Decision 5's n=1 auto-route). This mirrors the "phone is the remote" model — immediately after claiming, the natural next action is to launch an app on the freshly-paired TV.

Current behavior: post-claim, the phone lands on a "head to your TV to finish" success state that's effectively a dead-end. Users must manually navigate back to home and then (for n=1) get auto-routed to the remote — an extra step for no benefit.

Part E did not ship during 4.10.2 — focus shifted to 4.10.3 follow-up work addressing issues surfaced during 4.10.2 testing.

#### What's deferred

After `rpc_claim_tv_device` resolves successfully in the index.html claim flow:
- Stash the claimed device_key via the existing `elsewhere.active_tv.device_key` sessionStorage bridge (added in Session 4.10.3 Part A)
- Navigate phone into `screen-tv-remote` for that TV (same code path as Decision 5's n=1 auto-route)
- Skip the current "head to your TV" success screen

Estimated scope: ~5-10 lines in index.html's claim success handler. Single commit, no coordinating changes needed.

#### Options when picking up

Pick up alongside any other index.html claim-flow work, or as a standalone micro-session. Low risk — pure phone-side navigation change, no realtime events involved, no new dependencies.

#### When to pick this up

Before real customer acquisition (first-time claim is the most visible onboarding moment). Not scheduled yet.

#### Related

- `docs/SESSION-4.10.2-PLAN.md` → Part E (original spec)
- 4.10.2 plan Architecture Decision 5 — n=1 auto-route pattern this mirrors
- Session 4.10.3 Part A (commit `f43369a`) — introduced the `elsewhere.active_tv.device_key` sessionStorage bridge this feature can reuse

---

### Deferred: Venues as cross-app service (games, wellness, future apps)

**Deferred in:** Session 5 planning discussion (2026-04-23)
**Deferred on:** 2026-04-23
**Priority:** Medium — enables games visual parity with karaoke; unlocks Phase 2 camera-insertion across all apps
**Area:** Shell / cross-app rendering
**Status:** Deferred

#### Context

Karaoke has a fully-built 360° venue system: equirectangular panorama sphere in Three.js, particle systems, floating video planes, spatial Web Audio with beat detection. Infrastructure is partially extracted (`shell/venue-settings.js` handles admin view-coordinates; `venues.json` is the metadata registry) but the rendering itself lives inside `karaoke/stage.html`.

During Session 5 planning, surfaced the idea: games already have blockade images for each game (Last Card, Trivia, Poker, etc.). These could become proper 360° venues. Games render on top of a venue panorama. Wellness when it ships would do the same.

Session 5 treats "venue" as an opaque identifier in `session_participants.pre_selections` — the schema supports cross-app venues already. What's missing is (a) the cross-app rendering module and (b) games/wellness integration.

#### What's deferred

Three-part work:

1. Extract 360° panorama rendering from `karaoke/stage.html` into `shell/venue-renderer.js` (or similar). Three.js setup, texture loading, transition UX. Keep karaoke's ambient effects separate (that's the DEFERRED "shell/venue-effects.js" entry from PHASE1-NOTES).

2. Games integration: each game's blockade image becomes a venue entry in `venues.json` with product tag 'games'. Session-wide venue selection (manager/host picks one venue for the whole game, not per-player). Games pages consume the shared renderer.

3. Phase 2 follow-up: DeepAR camera insertion for player/participant presence in games (same technique karaoke uses for singers).

#### Options when picking up

- Bundle with wellness app start (natural trigger — wellness needs venue system, games benefit). Pairs cleanly with the "shell/venue-effects.js" extraction already deferred.
- Ship standalone as a Session 6.x refactor if games venue support becomes a product priority before wellness.

Per-session vs session-wide venue: Karaoke is per-singer (each queue entry has its own pre-selected venue). Games should be session-wide (one venue for the whole game round). Wellness likely session-wide too.

#### When to pick this up

When either:
- Wellness app work begins (natural bundling), OR
- Games visual parity with karaoke becomes a product priority

Not urgent for Session 5. Don't bundle with Session 5 — the scope creep risk is real.

#### Related

- DEFERRED "Extract ambient venue effects into `shell/venue-effects.js`" (from PHASE1-NOTES migrated section) — same extraction family
- `shell/venue-settings.js` (existing admin dialog)
- `venues.json` (existing metadata with product tags)
- Session 4.9 Part A — shipped `venues.json` cross-app metadata
- Session 5 Part 2d — keeps venue logic inline in stage.html per current architecture; this entry is the follow-up extraction

---

## Venues integration (post-Session-5)

Cluster of items surfaced during Session 5 Part 2b scope review that resolve when venues-as-cross-app-service work begins (see "Venues as cross-app service (games, wellness, future apps)" entry above for the parent refactor). All six are architectural or design-clarification items, not bugs — they capture decisions deferred from Session 5 that affect games visual parity, proximity semantics, and participant lifecycle cleanup.

---

### Deferred: Games TV rendering matrix (post-venues integration)

**Deferred in:** Session 5 Part 2b scope refinement (2026-04-24)
**Deferred on:** 2026-04-24
**Priority:** High — architectural; needed before venues-as-cross-app work starts
**Area:** Games / Shell — TV rendering
**Status:** Deferred

#### Context

Karaoke's TV viewer (stage.html) renders singers composited into a 360° venue panorama. When venues integrate into games (post-Session-5), the rendering contract needs to be explicit about which players get inserted into the venue vs. rendered as name + avatar + video tile.

Core principle to preserve: the TV device is a *rendering capability*, not a visibility gate. Every TV viewer sees every player regardless of whether the viewer or the player has a TV device — what varies is *how* they're rendered.

#### What's deferred

Document and implement the rendering matrix:

- **TV viewer WITH TV device:** renders 360° venue + TV-device players inserted into venue background (camera composite like karaoke singers) + non-TV-device players as name + avatar + video stream (if on).
- **TV viewer WITHOUT TV device:** renders 360° venue + all players (both TV-device and non-TV-device) as name + avatar + video stream. No insertion.

Implications for the design work:

- Participant TV device availability is a *player capability* ("can I be inserted?"), separate from viewer TV device ("can I render insertion?"). Both need to be modeled.
- Preserves today's any-player-can-add-a-TV behavior for games.

#### Options when picking up

Bundle with the venues extraction work ("Venues as cross-app service (games, wellness, future apps)" parent entry). Natural place to make the rendering matrix explicit is inside `shell/venue-renderer.js` as it's being extracted — the two-axis (viewer capability × participant capability) branching lives there.

#### When to pick this up

Start of venues-as-cross-app-service work. Before writing any games-side venue integration code.

#### Related

- DEFERRED "Venues as cross-app service (games, wellness, future apps)" — parent refactor
- DEFERRED "Games `ask_proximity` revision (post-venues integration)" — sibling concern (participant capability modeling)
- `karaoke/stage.html` — today's reference implementation of TV-viewer-with-TV-device rendering

---

### Deferred: Games `ask_proximity` revision (post-venues integration)

**Deferred in:** Session 5 Part 2b scope refinement (2026-04-24)
**Deferred on:** 2026-04-24
**Priority:** High — architectural; targets revising SESSION-5-PLAN.md Decision 8
**Area:** Games / Shell — role manifest / proximity semantics
**Status:** Deferred

#### Context

SESSION-5-PLAN.md Decision 8 sets `games: ask_proximity: false`. Correct for Session 5's shipping scope (games without venue rendering) — proximity only matters when the TV needs to composite the user into the venue background.

When venues integrate into games, proximity becomes relevant, but not in the same way as karaoke. Games should keep non-proximity users as *full participants* — they still play, see the game, show up on TV as name + avatar + video — they just can't be inserted into the venue background.

#### What's deferred

Revise the games role manifest: `ask_proximity: false` → `ask_proximity: true` with *soft-gate* semantics. Unlike karaoke's hard gate (no proximity = audience role), the games soft gate:

- Prompts the proximity question
- "No" answer: user remains a player (not demoted to audience), but TV renders them as name + avatar + video tile instead of venue composite
- "Yes" answer: user is eligible for venue-background insertion (subject to TV-device capability check, see "Games TV rendering matrix" sibling entry)

This pattern (soft-gate-on-capability rather than hard-gate-on-participation) may indicate proximity semantics need a broader revision at that time — see "Proximity meaning refined" sibling entry.

#### Options when picking up

Land alongside the games venue integration work. The manifest field itself is cheap to change (schema already supports per-app flags). The behavioral branching in games/tv.html and games/player.html is the real work.

Consider whether the manifest field's boolean shape is expressive enough or needs to become a tri-state (`'hard'` / `'soft'` / `false`) — see "Proximity meaning refined" for the fuller discussion.

#### When to pick this up

Start of venues-as-cross-app-service work, before games venue integration lands.

#### Related

- SESSION-5-PLAN.md → Architecture Decision 8 (the `ask_proximity: false` setting this revises)
- DEFERRED "Proximity meaning refined (hard gate vs. soft gate)" — sibling concern; the broader semantic question
- DEFERRED "Games TV rendering matrix (post-venues integration)" — sibling concern; participant capability modeling

---

### Deferred: "Potential participant" as derived UI state

**Deferred in:** Session 5 Part 2b scope refinement (2026-04-24)
**Deferred on:** 2026-04-24
**Priority:** Medium — design clarification
**Area:** Shell / UX — phone UI branching
**Status:** Deferred

#### Context

During Session 5 Part 2b scope review, "potential participant" surfaced as a distinct UI state: a user who's at home (proximity = yes) with a TV device but hasn't joined a queue. Surface-level this feels like a fourth `participation_role` value.

It's not. The existing three roles (`active`, `queued`, `audience`) plus proximity + TV-device availability already encode this state via UI logic. Adding a schema value would duplicate what's already derivable.

#### What's deferred

Formalize the "potential participant" state as a *derived UI branching rule* in the phone UI (singer.html / audience.html / future games player.html):

- Logged in + proximity = yes + has TV device + role = `audience` → show "Queue Up to Sing" button (karaoke) or "Join as player" (games with venues)
- Logged in + (proximity = no OR no TV device) + role = `audience` → audience view only; no queue button

Implementation is a client-side conditional render, not a schema change.

#### Options when picking up

Apply when singer.html / audience.html get their Session 5 polish pass (post-Part 2f), or when venues integration starts — either surfaces the UI branching as a first-class concern.

#### When to pick this up

Either trigger suffices. Not urgent before real multi-user testing surfaces the UX need.

#### Related

- SESSION-5-PLAN.md → participation_role enum (three values: active / queued / audience)
- DEFERRED "Proximity meaning refined (hard gate vs. soft gate)" — proximity input to this branching rule
- DEFERRED "Games TV rendering matrix (post-venues integration)" — TV-device availability input

---

### Deferred: Proximity meaning refined (hard gate vs. soft gate)

**Deferred in:** Session 5 Part 2b scope refinement (2026-04-24)
**Deferred on:** 2026-04-24
**Priority:** Medium — design clarification; targets revising SESSION-5-PLAN.md Decision 8 flag approach
**Area:** Shell / Schema — role manifest proximity semantics
**Status:** Deferred

#### Context

Proximity answers one question: *"can this user be rendered by the TV's camera?"* Its *effect* varies by app, though, and the current binary `ask_proximity: true/false` flag on the role manifest doesn't capture that variation.

Per-app proximity semantics:

- **Karaoke:** hard gate. Proximity = no → user cannot sing. UX routes to audience via confirm dialog. Current Session 5 design.
- **Games (post-venues):** soft gate. Proximity = no → user still plays, just not inserted into venue background. No demote.
- **Wellness (when it lands):** hard gate (form tracking requires camera).

The current `ask_proximity: true/false` flag is binary. Post-venues-integration, the manifest may need a tri-state (`'hard'` / `'soft'` / `false`) or a different shape entirely.

#### What's deferred

Revise the role manifest's proximity field to express hard vs. soft gating. Options:

- Tri-state enum: `'hard'` / `'soft'` / `false` (or `null`)
- Separate flags: `ask_proximity: true/false` + `proximity_is_hard_gate: true/false`
- App-declared handler: each app registers a `handleProximityAnswer(role, answer)` function the shell invokes

Any of these work; the second option (separate flags) is probably the clearest read but adds two fields where one expressive one might suffice.

#### Options when picking up

Ship alongside "Games `ask_proximity` revision" — those two entries touch the same manifest surface and should land together. Don't split.

#### When to pick this up

When venues integration starts, or when the proximity prompt UX gets its second design pass — whichever comes first.

#### Related

- SESSION-5-PLAN.md → Architecture Decision 8 — current binary flag shape
- DEFERRED "Games `ask_proximity` revision (post-venues integration)" — sibling concern; same manifest surface
- DEFERRED "'Potential participant' as derived UI state" — consumer of refined proximity semantics
- docs/PHONE-AND-TV-STATE-MODEL.md — canonical state model. Proximity prompting is now at TV-connect; this entry's hard-gate-vs-soft-gate semantics define what apps do with the answer.

---

### Deferred: Participant cleanup mechanism (audience left_at / inactivity sweep)

**Deferred in:** Session 5 Part 2b scope refinement (2026-04-24)
**Deferred on:** 2026-04-24
**Priority:** Medium — becomes High once real multi-user usage accumulates ghost participants
**Area:** Schema / Shell — session_participants lifecycle
**Status:** Deferred

#### Context

In Session 5 Part 2, non-manager participant exits are largely implicit. Audience members who close the phone app leave their `session_participants` row with `left_at = null`. This accumulates "ghost audience" rows that the platform doesn't currently clean up.

Ghost-audience count is an accepted Phase 1 trade-off — a data-hygiene nuisance, not a correctness bug. Real multi-user usage will reveal whether ghost counts show up as usability problems (wrong audience counter on stage.html, confusing queue displays, etc.) or stay invisible.

#### What's deferred

Build a participant cleanup mechanism. Options, not yet decided:

- **Scheduled job** — periodic Supabase edge function or cron that sets `left_at = now()` for participants with stale `last_activity_at`.
- **Heartbeat + sweep** — each participant page pings to keep `last_activity_at` fresh; a separate sweep marks stale rows as left. More responsive than pure scheduled job but more plumbing.
- **`beforeunload` / `pagehide`** best-effort — first layer that catches most clean exits; pair with inactivity sweep as the backstop for ungraceful exits (tab crashes, phone force-quits, dead batteries).

Design depends on real usage data. The right threshold (5 min? 15? 60?) isn't decidable in advance.

#### Options when picking up

Start with inactivity-sweep-only (simplest; covers all ghost paths). Layer `beforeunload` on top if UX testing shows sweep alone is too slow. Heartbeat is probably overkill for Phase 1.

Implementation can piggyback on existing `sessions.last_activity_at` infrastructure — the RPCs already bump this on participant actions.

#### When to pick this up

Customer testing surfaces ghost-audience or ghost-queued counts as a usability problem, OR Session 5 Verification flows surface it. Not a Session 5 concern unless testing explicitly blocks on it.

#### Related

- SESSION-5-PART-2-BREAKDOWN.md § 2f — "Audience exit is implicit" scope note establishing this trade-off
- SESSION-5-PLAN.md → session_participants schema (`left_at` column, `last_activity_at` on sessions)
- DEFERRED "Session manager inactivity + household-admin override" — adjacent inactivity-tracking mechanism; share infrastructure
- docs/PHONE-AND-TV-STATE-MODEL.md — establishes the ghost-audience trade-off this entry solves. Cleanup mechanism picks up when phase 1 ghost-audience accumulation becomes a real usability issue.

---

### Deferred: `rpc_session_leave` manager auto-promote branch is dead code

**Deferred in:** Session 5 Part 2b scope refinement (2026-04-24)
**Deferred on:** 2026-04-24
**Priority:** Low — cleanup; no functional impact
**Area:** Schema — db/009 + db/010 cleanup
**Status:** Deferred

#### Context

`rpc_session_leave` is defined in two migrations: `db/009_session_lifecycle_rpcs.sql` ships the original (raises if the manager has other active participants), and `db/010_manager_mechanics_rpcs.sql` replaces it with the auto-promote-to-host-or-next-participant logic per SESSION-5-PLAN Decision 7. The live version in a fully-migrated database is db/010's. The auto-promote branch covers the case where the manager leaves the session and an eligible participant gets promoted before the leaving manager's row is finalized.

Under the revised Session 5 Part 2 UX (Back-to-Elsewhere is navigate-only; no user-facing action calls `rpc_session_leave` from the phone), no phone UI path exercises the auto-promote branch:

- Managers exit via `rpc_session_end` (explicit End Session button)
- Orphaned sessions are handled by `rpc_session_reclaim_manager` (any household member claims)
- Admin overrides use `rpc_session_admin_reclaim` (household admin only)

None of these call `rpc_session_leave`. The manager auto-promote branch is therefore defensive / unreachable in Session 5 Part 2 UI.

#### What's deferred

Cleanup decision:

- **Leave in place** (current disposition): costs nothing, preserves flexibility for future cleanup mechanisms (heartbeat sweep, background job) that might legitimately call `rpc_session_leave` on a manager row.
- **Strip the manager branch**: reduces `rpc_session_leave` to non-manager semantics only. Smaller surface, but rebuilds if the cleanup mechanism later needs the auto-promote path.

Current recommendation: leave alone unless the file is being touched for another reason.

#### Options when picking up

When next touching `db/010_manager_mechanics_rpcs.sql` (where the live auto-promote branch lives — db/009 has the original simpler version but db/010 supersedes it) for any reason, check whether the manager auto-promote branch has any caller. If still unused, strip it in a new migration and document the removal. If a caller has emerged (e.g. cleanup mechanism per sibling DEFERRED entry), keep it.

#### When to pick this up

Opportunistic — next time `db/010_manager_mechanics_rpcs.sql` (the file holding the auto-promote branch) or its sibling `db/009_session_lifecycle_rpcs.sql` is touched for any reason. OR scheduled cleanup pass after real usage data clarifies which branches are actually exercised.

#### Related

- `db/009_session_lifecycle_rpcs.sql` — original `rpc_session_leave` (raise-on-manager-with-others)
- `db/010_manager_mechanics_rpcs.sql` — current live `rpc_session_leave` with auto-promote branch; replaces db/009's version
- SESSION-5-PART-2-BREAKDOWN.md → "Non-manager exit semantics" section — documents why no phone UI calls this RPC
- DEFERRED "Participant cleanup mechanism (audience left_at / inactivity sweep)" — potential future caller if background cleanup lands

---

## State model implementation (post-Session-5)

Cluster of items surfaced during Session 5 Part 2 state model design (see [PHONE-AND-TV-STATE-MODEL.md](./PHONE-AND-TV-STATE-MODEL.md) — canonical state model, added 2026-04-24, commit `36353ca`). The state model defines behavior across phone and TV that implementation doesn't yet cover end-to-end. These four entries capture the post-Session-5 work items the state model implies.

---

### Deferred: Configurable platform timeouts

**Deferred in:** Session 5 Part 2 state model design (2026-04-24)
**Deferred on:** 2026-04-24
**Priority:** Low — current hardcoded values are fine for Phase 1; becomes Medium when ops needs runtime tuning without redeploys
**Area:** Schema / Shell — platform settings
**Status:** Deferred

#### Context

The Phone and TV state model (docs/PHONE-AND-TV-STATE-MODEL.md) defines three platform-level timeouts that govern session and device state cleanup:

- TV inactivity (State 2 → State 1 transition) — default 10 min
- Manager orphan threshold — default 10 min
- Phone proximity persistence — default 10 min

Today these are hardcoded constants. Tuning requires code changes + redeploy. Real operational usage will likely benefit from runtime configurability — letting an ops admin set different values for different deployments or experiment with thresholds.

#### What's deferred

Build a `platform_settings` DB table with rows for each configurable timeout. Read at runtime by relevant code paths (stage.html session-state checks, manager-orphan polls, proximity-persistence check). Default values stored as table seed data; admin overrides applied per-row.

Depends on a platform-admin role to scope who can edit (see sibling entry "Platform admin role + UI"). Platform settings are global, not household-scoped — a household admin shouldn't be able to extend their TV inactivity timeout to game the session-orphan rules.

#### Options when picking up

- Single `platform_settings` table with key-value pairs, schema validated by application code
- Multiple narrow tables per concern (timeouts, feature flags, etc.) — overkill for Phase 1
- Environment variables instead of DB — simpler but loses runtime tunability

Recommendation: single `platform_settings` table, schema-validated in application code, edited via platform admin UI.

#### When to pick this up

When ops feedback surfaces specific tuning needs, OR when post-Phase-1 work necessarily includes platform-level admin features.

#### Related

- docs/PHONE-AND-TV-STATE-MODEL.md — defines the three timeouts this entry would make configurable
- DEFERRED "Platform admin role + UI" — prerequisite role scoping
- DEFERRED "Session manager inactivity + household-admin override" — describes manager orphan timeout's current hardcoded behavior

---

### Deferred: Platform admin role + UI

**Deferred in:** Session 5 Part 2 state model design (2026-04-24)
**Deferred on:** 2026-04-24
**Priority:** Low — required for "Configurable platform timeouts" pickup; otherwise no production trigger
**Area:** Schema / Shell — auth + authorization
**Status:** Deferred

#### Context

Today's authorization model has household-admin (defined in db/006 Session 4.10 — admin within a single household, can manage TVs, members, household settings). There's no concept of platform-level admin authority that spans households.

Several deferred items require platform-level scoping:

- Configurable platform timeouts (sibling entry)
- Cross-household analytics / observability (future)
- Force-reset device claims (future operational tool)
- Platform feature flag rollouts (future)

A platform admin role distinct from household-admin lets a small operations team manage these without giving household-level users cross-household authority.

#### What's deferred

Define a `platform_admins` table (`user_id`, `granted_at`, `granted_by`, `active`) — simple list of platform-admin user IDs. Add a UI page (probably outside the regular Elsewhere phone app — e.g., a dedicated admin page at `mstepanovich-web.github.io/elsewhere/admin/` or similar) gated to those users. Initial scope of the UI: edit configurable timeouts (per sibling entry), maybe view session-stats dashboards.

#### Options when picking up

- Separate web UI (no Capacitor wrapper, just web page) — cleanest separation; doesn't bloat phone app
- Hidden routes inside main Elsewhere phone app — simpler but blurs concern boundaries
- Pure CLI / SQL access — minimal UI but doesn't scale to non-engineering ops

Recommendation: separate web UI, simple page rather than full SPA. Auth via the existing Supabase session.

#### When to pick this up

When the first platform-admin-only operational task surfaces (most likely: configurable platform timeouts, see sibling entry).

#### Related

- DEFERRED "Configurable platform timeouts" — first concrete use case for this role
- db/006 — `household_members.role` definition; `platform_admins` is a parallel but distinct role table

---

### Deferred: Guest flow design (under state model)

**Deferred in:** Session 5 Part 2 state model design (2026-04-24)
**Deferred on:** 2026-04-24
**Priority:** Medium — required before sessions can be initiated by non-household users
**Area:** Shell / Schema — auth + session participation
**Status:** Deferred

#### Context

The Phone and TV state model (docs/PHONE-AND-TV-STATE-MODEL.md) notes that a guest (non-household user) can scan the QR code on a TV in State 1 (at-rest), sign in or create an account, and bootstrap a session on that TV without becoming a household member. The state model defines this scenario at a high level but defers implementation specifics to a separate design pass.

Pre-state-model, guest flow was partially captured in "Part E Flows 3 + 4 — guest access + pre-invited member verification" and "Scan-approval flow" entries. Those entries predate the state model's unified post-login home and need to be reconciled with the new framing.

#### What's deferred

Decide and implement:

- Can a guest be a session manager? (State model says "probably yes" — they originated the session.)
- Can a host promote a guest to a participant role? (Probably yes.)
- Does the guest's `session_participants` row persist after the session ends? (Yes — they have an `auth.users` record; they just aren't a `household_members` row.)
- Does the guest see any household-themed UI on the phone post-login? (Mode C in state model: no household, no TV header, only non-TV-required app tiles active.)
- Does the household see "guests participated" in any history/log? (Future observability; out of scope for guest flow itself.)
- How does a guest "graduate" to household member? (Existing invitation flows from Session 4.10; not new mechanics.)

#### Options when picking up

Approach 1: Unify with Part E Flows 3+4 — one consolidated guest flow design that supersedes those entries. Cleanest final shape but requires reading the prior entries' detail.

Approach 2: Layered — Part E entries cover the auth + claim mechanics; this entry covers the state-model-specific UI behaviors (Mode C rendering, tile state matrix for guests, etc.). Less consolidation but smaller scope per pickup.

Recommendation: Approach 1 (unified) when this is scheduled. The state model's Mode C is the umbrella concept that deserves first-class treatment.

#### When to pick this up

When the first real guest-participation use case surfaces (typically: friend visits, scans the TV's QR, wants to play games or sing). Post-Session-5.

#### Related

- docs/PHONE-AND-TV-STATE-MODEL.md — defines Mode C (non-household-user) state and guest flow at a high level
- DEFERRED "Part E Flows 3 + 4 — guest access + pre-invited member verification" — predecessor entry; needs reconciling with state model
- DEFERRED "Scan-approval flow (request-to-join household in real time)" — adjacent flow for guest-becomes-member scenarios
- Session 4.10 plans — household membership mechanics

---

### Deferred: Multi-TV picker and selection persistence

**Deferred in:** Session 5 Part 2 state model design (2026-04-24)
**Deferred on:** 2026-04-24
**Priority:** Low — only relevant once a real multi-TV household exists; n=1 case is the dominant Phase 1 reality
**Area:** Shell / UX — phone home screen
**Status:** Deferred

#### Context

The Phone and TV state model (docs/PHONE-AND-TV-STATE-MODEL.md) specifies that users with more than one claimed TV (n>1) see an inline TV picker on the post-login home before the proximity prompt fires. The state model captures the high-level flow:

- Picker fires before proximity prompt
- Selection persists across app launches as long as user stays signed in
- Switching TVs via the badge menu's "Your TVs" returns to the picker; new selection resets proximity (since the question is "are you at home with *this* TV")

Today's index.html implements n=1 auto-skip. The picker UI for n>1 doesn't yet exist.

#### What's deferred

Build the picker UI: list TVs by display name + household name + last-seen timestamp; tap to select; visual indication of currently-selected TV. Persist selection in sessionStorage or per-user DB column.

Reset proximity when selection changes (per state model's explicit rule).

Multi-TV households are rare in Phase 1 — most users have one TV. Building this picker is low priority until real n>1 households surface usability issues with the current auto-routing.

#### Options when picking up

- Inline picker on post-login home as state model specifies — reads cleanly with the unified-home design
- Modal/drawer picker (alternative to inline) — more conventional but adds a navigation level
- Per-app last-used-TV memory — alternative persistence mechanism if simple TV-selected-once doesn't fit usage

Recommendation: inline picker per state model. No drill-in.

#### When to pick this up

When real multi-TV households emerge in usage. Probably post-Phase-1 unless sales/marketing surfaces specific multi-TV use cases (e.g., bar/restaurant deployments).

#### Related

- docs/PHONE-AND-TV-STATE-MODEL.md — defines multi-TV selection at a high level
- DEFERRED "Phone-as-remote — persistent app launcher on phone, display-only grid on TV" — predecessor concept; Session 4.10.2 implemented n=1 auto-skip from this design

---

### Deferred: Phone proximity persistence — 10-minute inactivity expiration

**Deferred in:** Session 5 Part 2c.x scoping (2026-04-24)
**Deferred on:** 2026-04-24
**Priority:** Low — sessionStorage-only persistence is sufficient for Phase 1; revisit when usage shows persistence is too sticky
**Area:** Shell — phone state management
**Status:** Deferred

#### Context

The Phone and TV state model (docs/PHONE-AND-TV-STATE-MODEL.md) defines a 10-minute phone-side inactivity expiration for the proximity answer — meaning if the user has been inactive on the phone for 10+ minutes, the next interaction re-prompts the proximity question.

2c.x (Session 5 Part 2c.1 / 2c.2 / 2c.3) ships proximity persistence using sessionStorage only. The answer survives until app force-close, phone restart, sign-out, or explicit TV switch. The 10-minute inactivity expiration is not implemented.

#### What's deferred

Add a timestamp to the sessionStorage proximity record. On read, check whether the timestamp is older than 10 minutes (configurable per the platform-timeouts entry). If older, treat as unanswered and re-prompt.

Could optionally migrate to localStorage with the timestamp check, persisting the answer across app close/reopen but still expiring on inactivity. That choice is a 2c.x-followup design decision.

#### Options when picking up

- **(a) sessionStorage with timestamp:** minimal change, answer expires after 10 min OR app close (whichever comes first)
- **(b) localStorage with timestamp:** answer survives app close, expires only on inactivity
- **(c) DB-backed with timestamp:** survives reinstalls; consistent with "Don't show me again" persistence model
- **(d) Configurable via platform_settings:** per "Configurable platform timeouts" entry; opt for a uniform timeouts model

Recommendation: (a) for simplest pickup. Promote to (c) if usage shows users want their answer to survive reinstalls or if the platform-timeouts work lands first.

#### When to pick this up

When real usage surfaces complaints about proximity persistence being "too sticky" — users walking away from the TV, returning later, and the app still treating them as at-home. Or when the broader platform-timeouts work picks up and this becomes a uniform implementation case.

#### Related

- docs/PHONE-AND-TV-STATE-MODEL.md — defines the 10-minute timeout that this entry defers
- DEFERRED "Configurable platform timeouts" — sibling entry; this proximity timeout is one of three platform-level timeouts
- SESSION-5-PART-2-BREAKDOWN.md § 2c.2 — implementation that ships sessionStorage-only persistence

---

## Karaoke control model (Session 5 Part 2d/2e/2f spec landing)

Seven items surfaced during the Karaoke Control Model spec work (commit `b7d4e70`) that bound or defer features touched by the spec. They cluster around (1) audience.html freeze and migration, (2) NHHU conversion strategy, (3) manager intervention features, and (4) the Manager Override transport mechanism architectural decision.

---

### Deferred: Manager picks song/venue/costume on behalf of Active Singer (Q-2B helper feature)

**Deferred in:** Session 5 Part 2 (Karaoke control model spec landing)
**Deferred on:** 2026-04-26
**Priority:** Low — workaround exists (manager takes stage themselves; nearby person uses elderly user's phone)
**Area:** Karaoke — manager UI / accessibility
**Status:** Deferred — post-Session-5

#### Context

When an Active Singer can't navigate their own phone (older relative, accessibility need, network issue), Session Manager could pick songs and configure venue/costume on their behalf. Adds non-trivial complexity to manager UI: needs a "current Active Singer" view with full session controls, permission system to apply manager's selection to Active Singer's slot, UI handoff. Documented in docs/KARAOKE-CONTROL-MODEL.md § 5.6.

---

### Deferred: Audience-to-NHHU conversion path

**Deferred in:** Session 5 Part 2 (Karaoke control model spec landing)
**Deferred on:** 2026-04-26
**Priority:** Medium — supports user acquisition strategy (Audience-to-NHHU model)
**Area:** Platform — onboarding / acquisition
**Status:** Phase 1 placeholder may ship in Session 5; full conversion funnel deferred post-Session-5

#### Context

NHHU audience users tap Back-to-Elsewhere from audience.html and land on a placeholder Elsewhere home with options to return to audience or explore Elsewhere. Phase 1 ships minimal placeholder. Full conversion funnel (sign-up flow, app downloads, game launchers) lands post-Session-5. Documented in docs/KARAOKE-CONTROL-MODEL.md § 5.4.

---

### Deferred: Audience.html freeze (no new features in Session 5)

**Deferred in:** Session 5 Part 2 (Karaoke control model spec landing)
**Deferred on:** 2026-04-26
**Priority:** N/A — constraint, not deliverable
**Area:** Platform architecture — audience surface
**Status:** Active constraint through Session 5; bug fixes only on audience.html

#### Context

Audience.html is frozen for Session 5. New audience-experience features (read-only queue, venue/costume browsing, NHHU sign-up) build into the unified HHU app post-Session-5, not into audience.html. Reason: avoid parallel UI codebases that compound complexity with each new feature. Documented in docs/KARAOKE-CONTROL-MODEL.md § 4.3 and § 5.5.

---

### Deferred: Migrate audience.html into unified app as parameterized NHHU view

**Deferred in:** Session 5 Part 2 (Karaoke control model spec landing)
**Deferred on:** 2026-04-26
**Priority:** Medium — architectural foundation for NHHU feature work
**Area:** Platform architecture — audience surface
**Status:** Deferred — triggered when NHHU-as-first-class-user feature work begins (games venues, wellness, etc.)

#### Context

Future state is unified app with parameterized NHHU view based on user context. NHHU users see same UI fabric as HHU users; conditional rendering hides TV-required features. Single source of truth for new features, consistent UX, conversion path built into app fabric. Documented in docs/KARAOKE-CONTROL-MODEL.md § 5.5.

---

### Deferred: Audience browsing of venues/costumes for marketing

**Deferred in:** Session 5 Part 2 (Karaoke control model spec landing)
**Deferred on:** 2026-04-26
**Priority:** Low — marketing enhancement
**Area:** Karaoke — audience experience / user acquisition
**Status:** Deferred to audience.html migration into unified app

#### Context

Audience users browsing venues and costumes (no apply, just visual preview) is high-value for marketing — shows what they're missing without their own TV device. Implementation requires audience.html UI changes. Audience.html is frozen for Session 5. Lands when audience surface migrates to unified app. Documented in docs/KARAOKE-CONTROL-MODEL.md § 3.1 footnote (rows 1.4 / 1.6).

---

### Deferred: Audience read-only queue display

**Deferred in:** Session 5 Part 2 (Karaoke control model spec landing)
**Deferred on:** 2026-04-26
**Priority:** Low — nice-to-have for audience experience
**Area:** Karaoke — audience experience
**Status:** Deferred to audience.html migration into unified app

#### Context

Audience users seeing the queue (read-only, who's up next) is valuable for engagement. Implementation requires audience.html UI changes; audience.html is frozen for Session 5. Lands when audience surface migrates to unified app. Documented in docs/KARAOKE-CONTROL-MODEL.md § 3.5 footnote (row 5.1).

---

### Deferred: Manager Override mechanism design (architectural decision)

**Deferred in:** Session 5 Part 2 (Karaoke control model spec landing)
**Deferred on:** 2026-04-26
**Priority:** High — blocking for 2e implementation of manager intervention features
**Area:** Karaoke — realtime architecture
**Status:** Deferred to 2e pre-implementation audit

#### Context

Session Manager mid-song commands (override Active Singer's mute/pause/restart/stop/view/zoom/pan/costume/comments) need a transport mechanism. Currently no implementation exists; all mid-song singer controls send via Agora data streams from Active Singer's phone only. Three options under consideration:

- Option A: Session Manager phone sends Supabase realtime command → Active Singer's phone listens and re-broadcasts as Agora to stage
- Option B: Session Manager phone gets direct stage-channel access; sends Agora commands directly
- Option C: New RPC layer for session-state mutations that publishes events stage.html consumes

Decision deferred to 2e implementation pass. Documented in docs/KARAOKE-CONTROL-MODEL.md § 2 (Manager Override mechanism) and § 5.7.

---

### Deferred: Remove Way 1 (pre-Session-5 stage.html entry path)

**Deferred in:** Session 5 Part 2d audit (2026-04-26)
**Deferred on:** 2026-04-26
**Priority:** Low — not blocking; legacy code preserved for testing/dev fallback
**Area:** Karaoke / stage.html / shell — code cleanup
**Status:** Deferred

#### Context

Stage.html supports two entry paths today:

- **Way 1 (pre-Session-5):** Direct navigation to `karaoke/stage.html?room=ABCD`. Stage shows QR with room code; singer's phone scans the QR and connects via Agora. No database session row involved.
- **Way 2 (Session 5):** User taps Karaoke from the Elsewhere home screen. Phone calls `rpc_session_start`, session row created, broadcast triggers TV navigation, stage.html loads and queries session by `tv_device_id`. Database session is canonical.

Way 1 is no longer used in real product flows. Users always go through home → TV → tap Karaoke. Way 1 exists in the code as legacy from before Session 5 and remains accessible for direct-URL testing/dev workflows.

In 2d.1's solo mode (no active session in DB), stage.html falls back to Way 1 behavior: `idle-panel` with QR shows, URL `?room=` is the room identifier, Agora handles all coordination. This preserves dev/test workflows.

#### What's deferred

Removal of Way 1 plumbing:

- URL `?room=` parsing on stage.html (lines 583-587 area)
- `idle-panel` showing the QR code with room-code-only identification (lines 339-350 area)
- Room-code generation fallback (`(()=>{ const c='ABCD…'; ... })()` at line 587)
- Agora room name derivation from `ROOM_CODE` (line 587)
- Singer.html's `screen-join` (entire screen for entering a room code)
- Singer.html's `doJoin()` function and the room-code input flow
- Any audience.html plumbing that depends on room-code-only identification

Plus an audit pass to verify nothing else depends on these references.

#### Options when picking up

Bundle with Session 5 wrap-up cleanup OR a dedicated post-Session-5 cleanup session. Each removal site needs review:

- Trace every reference to `ROOM_CODE`, `?room=` URL handling, `screen-join`, `doJoin`
- Verify no testing/dev workflow depends on direct-URL access
- Verify session-loading is the only path stage.html supports post-cleanup

Estimated scope: ~half-day of careful removal work.

#### When to pick this up

After Session 5 ships completely (2e and 2f shipped, multi-user flows verified end-to-end on hardware). At that point, confidence that nothing real depends on Way 1 is high.

Don't bundle with 2d.1 implementation — keeping legacy code in place during 2d.1 reduces blast radius.

#### Related

- `docs/SESSION-5-PART-2D-AUDIT.md` DECISION-AUDIT-5 — solo mode preserves Way 1 verbatim
- `docs/KARAOKE-FUNCTION-AUDIT.md` — full inventory of stage.html and singer.html that documents Way 1's surface

---

## Edge Function deploy `--no-verify-jwt` wrapper script

**Surfaced:** 2e.2 (2026-04-29).
**Severity:** Low — operational footgun.
**Affected:** `supabase/functions/send-push-notification`.

The `send-push-notification` Edge Function MUST be deployed with the
`--no-verify-jwt` flag because the Postgres trigger sends a non-JWT bearer
token (`PROMOTION_TRIGGER_SECRET`). Without the flag, Supabase's edge gateway
rejects the call with `UNAUTHORIZED_INVALID_JWT_FORMAT` before the function
code ever runs, breaking the push pipeline silently.

A vanilla `supabase functions deploy send-push-notification` will silently
re-enable JWT verification at the gateway, breaking the trigger. This has
already happened once in the 2e.2 verification phase.

**Proposed fix:** add `scripts/deploy-push-fn.sh` that wraps the deploy with
the correct flag. Document in CLAUDE.md (already noted in CLAUDE.md locked
doctrine; script is the actionable safety net).

```bash
#!/usr/bin/env bash
# scripts/deploy-push-fn.sh
set -euo pipefail
cd "$(dirname "$0")/.."
supabase functions deploy send-push-notification --no-verify-jwt
```

**Effort:** 5 minutes. Defer until next time the function is deployed.

---

## TV's app-launch realtime not reaching tv2.html

**Surfaced:** 2e.2 verification (2026-04-29).
**Severity:** Medium — blocks one path of TV-side testing.
**Affected:** `tv2.html` realtime listener; possibly `shell/realtime.js`.

During 2e.2 testing, tapping Karaoke from the household home on the phone
did NOT navigate the TV from `tv2.html` (idle launcher) to
`karaoke/stage.html`. The phone's downstream effects all worked correctly
(joined session, mic published, push token registered), suggesting the
phone's realtime publish fired. But the TV's listener didn't pick it up.

TV LOG showed `realtime: subscribed` and `state: authed + registered →
apps` (waiting at launcher) but no app-launch event received.

Possible causes (not yet investigated):
- Channel name mismatch between tv2.html subscriber and phone publisher
- §5's `roleAllowsStageSignals()` accidentally suppressing the launch signal
- tv2.html subscribed to a different topic than phone publishes to
- Less likely: phone never fires the publish (would have other observable
  failures, none of which occurred)

**Workaround:** during 2e.2, joined session via QR/code path (Way 1) — TV
stuck at launcher didn't block push testing.

**Investigate before:** 2e.3 testing of Manager Override (Workstream B),
which involves manager phone joining Agora as silent host. End-to-end
testing requires a working TV-stage. Time-box investigation to ~30 min in
2e.3; if not obvious, file as separate small commit and continue with
Way 1 testing.

**Effort:** 30 min – 2 hr depending on root cause.

---

## Pre-existing JS error at singer.html:645

**Surfaced:** 2e.2 Xcode console capture (2026-04-29).
**Severity:** Low — likely cosmetic, possibly fixed already by 2e.2's DOM
changes.
**Affected:** `karaoke/singer.html`.

Xcode console captured an error during the v2.99 (pre-2e.2) bundle's
startup:

```
TypeError: null is not an object (evaluating
'document.getElementById("stat-w").textContent=n')
```

at `singer.html:645:40`. The `stat-w` element didn't exist in the DOM at
the time the code ran. Pre-existing in v2.99-ish.

**Status uncertain:** did not reproduce in v2.110 during 2e.2 testing.
Possibly fixed by 2e.2's screen-home DOM changes. Possibly still latent
and just not reached by the test paths used.

**Investigate when:** next time touching singer.html. Quick grep for
`stat-w` + audit of the surrounding code at line 645. Either confirm fix
and remove note, or fix and remove note.

**Effort:** 15-30 min.

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
