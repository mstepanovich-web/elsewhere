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
