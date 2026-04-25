# Phone and TV State Model

**Created:** 2026-04-24
**Supersedes:** SESSION-5-PLAN.md Decision 8 (per-app `ask_proximity` flag), Session 4.10.2's split between `screen-home` and `screen-tv-remote`
**Referenced by:** SESSION-5-PART-2-BREAKDOWN.md Part 2c onward; docs/KARAOKE-CONTROL-MODEL.md

This is the canonical reference for how the phone and TV behave across user contexts in Elsewhere. Future sessions point back to this document rather than re-deriving the model. When a code or plan decision contradicts this doc, this doc wins (or the doc gets updated explicitly with a supersession note).

---

## Why this doc exists

Session 5 Part 2 surfaced that the phone and TV had implicit, partly-contradictory state models:

- The phone had two post-login home screens (`screen-home` with large tiles, `screen-tv-remote` with small tiles) that were treated as distinct navigation targets but functionally overlapped. A back button on `screen-tv-remote` exposed the seam.
- The TV's `tv2.html` had implicit states (sign-in, apps grid, in-session) but transitions between them weren't explicitly modeled.
- Proximity prompting was specified per-app (`ask_proximity: true/false` on the role manifest) but the prompt naturally belongs at TV-connect time, not per app launch.
- Multiple timeout values (orphan threshold, inactivity, proximity persistence) lived as hardcoded constants with no path to operational tuning.

This document captures the unified model that resolves these contradictions.

---

## Core principles

1. **One post-login home screen on the phone.** Conditional rendering replaces multiple-screen navigation.
2. **Three explicit states for `tv2.html`.** Transitions between them are documented with triggers.
3. **Proximity is asked at TV-connect, not per-app.** Per-app interpretation handles hard-gate vs. soft-gate semantics.
4. **TV device is a rendering capability, not a visibility gate.** Every TV viewer sees every participant, regardless of TV device availability.
5. **Active sessions persist through navigation.** Back-to-Elsewhere doesn't end the session regardless of who taps it; the same UI surfaces apply for rejoin and not-home participation.
6. **Phase 1 tolerates manual-recovery seams.** Inactivity timeouts and explicit user actions handle state cleanup; no heartbeat or automatic detection layers.

---

## TV state model (`tv2.html`)

The TV has three explicit states. Every transition has a documented trigger.

### State 1 — At-rest

**Display:** QR code, "Sign in to this TV" prompt, household + TV name shown for confirmation, "Not your TV? Reset" link.

**When:** No authenticated user on this TV. Either the TV has never been used, or it returned here from inactivity.

**Outbound transitions:**
- → State 2 when a phone scans the QR code, completes auth handoff (`session_handoff` realtime event delivers tokens), TV runs `auth.setSession`, then `renderCurrentState` routes to State 2.

### State 2 — Connected, no active session

**Display:** Apps grid (`screen-apps` element). Tile per available app. Household name in header.

**When:** TV is authenticated. No row in `sessions` table where `tv_device_id = this TV` AND `ended_at IS NULL`.

**Outbound transitions:**
- → State 3 when a phone publishes `launch_app` for this TV (`rpc_session_start` succeeded on the phone, session row exists, then `launch_app` broadcast fires).
- → State 1 after TV-inactivity timeout expires (configurable, default 10 minutes — see Timeouts section).

### State 3 — In active session

**Display:** Navigated away from `tv2.html` to `karaoke/stage.html` or `games/tv.html` (or future apps' equivalent TV pages). `tv2.html` is no longer the active page.

**When:** A row exists in `sessions` for this TV with `ended_at IS NULL`.

**Outbound transitions:**
- → State 2 when `session_ended` fires (from explicit End Session button, cross-app switch in 2c, or other session-termination paths). The TV navigates back to `tv2.html`, which on load detects no active session and renders State 2.
- ↔ State 3 (different app) when a cross-app switch ends the current session and starts a new one in a different app. The TV transits through State 2 briefly during the switch.

### State diagram

```
                  TV-inactivity timeout
                  (default 10 min)
                          │
                          ▼
   ┌──────────────────────────────────┐
   │  State 1 — At-rest (QR code)     │
   │  No authenticated user           │
   └──────────────────┬───────────────┘
                      │
                      │ phone scans QR,
                      │ session_handoff
                      ▼
   ┌──────────────────────────────────┐
   │  State 2 — Connected, no session │
   │  Authenticated, apps grid shown  │
   └──────────┬─────────────▲─────────┘
              │             │
              │ launch_app  │ session_ended
              │ (phone)     │ (any source)
              ▼             │
   ┌──────────────────────────────────┐
   │  State 3 — In active session     │
   │  Navigated to stage.html or      │
   │  games/tv.html                   │
   └──────────────────────────────────┘
```

### Notes on the TV state model

- **State 1 displays QR code so household guests or new devices can bootstrap.** A user who isn't yet authed on the phone can scan the QR, sign in, and the auth tokens hand off to the TV. The TV moves from State 1 to State 2 as a side effect.
- **TV-inactivity timeout returns the TV to State 1 from either State 2 or State 3.** This is the "TV has been idle a while, return to bootstrap state" behavior. Default 10 minutes, configurable.
- **Active session in State 3 is independent of TV inactivity.** If a session is live and the TV is showing stage.html, the TV doesn't return to State 1 due to inactivity — the session is the activity. Only after the session ends and the TV returns to State 2 does the inactivity clock start.

---

## Phone post-login home screen

There is **one** post-login home screen on the phone. It replaces the prior `screen-home` / `screen-tv-remote` distinction. Tile content and labeling vary based on user context, but the screen itself is structurally one element with conditional rendering.

### What renders on the home screen

- Header showing the user's badge (avatar + name)
- App tiles in a single grid, all the same size
- TV name + household subheader IF user is connected to a TV (household member with at least one TV)
- No back button (it's the home — you don't back out of home; you sign out via the badge menu)

### Three rendering modes (conditional state, not separate screens)

The home screen renders differently based on user context, but the differences are CSS/content variations within a single DOM section:

#### Mode A — Household user, at home

- Connected to a TV (their TV is selected — n=1 skip if only one TV, picker resolved if more)
- Proximity declared "yes"
- TV name + household subheader visible
- All app tiles active (subject to active-session relabeling — see below)
- App-tile tap → triggers session start flow (Part 2b's `rpc_session_start` + publish + navigate)

#### Mode B — Household user, not at home

- Connected to a TV in some sense (they're a household member) but answered "no" to proximity
- TV name + household subheader visible (or hidden — design choice; default visible for context)
- TV-device-required apps (karaoke, future wellness): tile state depends on whether session exists
  - **No active session:** tile inactive/greyed (cannot start a session without TV device)
  - **Active session exists:** tile shows "Active Session" label, tap joins as audience
- Non-TV-device apps (games today): tile active, can launch normally
- App-tile tap → varies by tile state above

#### Mode C — Non-household user (NHHU)

NHHU users are first-class users of Elsewhere with one specific limitation: they cannot access TV-device-required features. They have full access to non-TV-device apps (e.g., games today) — same UI fabric, same tap behavior, same session lifecycle as household users for those apps. The distinction is "TV-device-required features only," not "audience-only across all of Elsewhere."

- Not a member of any household
- No TV header (no TV available)
- TV-device-required apps (karaoke, wellness): tile inactive/greyed (cannot start a session without TV device); audience-join via app-specific deep links (e.g., audience.html) remains available where the app supports it
- Non-TV-device apps (games today): tile active, can launch normally — same behavior as Mode A/B for these apps
- App-tile tap (non-TV-required apps) → launches without any TV-side launch broadcast

### Active session relabeling

When any active session exists for a TV the user has access to, the corresponding app tile is visually marked. Same UI for all user roles that need it:

- **Manager who navigated back to Elsewhere home via Back-to-Elsewhere:** tile shows "Active Session" — tap rejoins as manager
- **Household user, at home, mid-session:** tile shows "Active Session" — tap rejoins in their existing role (or joins if not yet a participant)
- **Household user, not at home:** tile shows "Active Session" — tap joins as audience (karaoke) or player (games)

Tile UI is identical across these cases. Tap behavior dispatches based on user role + proximity at runtime.

### Cross-app switching

If a session is active and the user taps a *different* app's tile, a confirm dialog asks: "End current [app] session to start [other app]?" → on confirm: `rpc_session_end` on current session, then `rpc_session_start` for new app, navigate.

### Tile state matrix

| User context | App requires TV device | Active session exists | Tile state | Tap behavior |
|---|---|---|---|---|
| Household + at home | Yes (karaoke) | No | Active | Start new session |
| Household + at home | Yes | Yes (this app) | Active, "Rejoin" or "Active Session" | Rejoin in current role |
| Household + at home | Yes | Yes (different app) | Active | Confirm cross-app switch |
| Household + at home | No (games) | No | Active | Start new session |
| Household + at home | No | Yes (this app) | Active, "Rejoin" or "Active Session" | Rejoin |
| Household + at home | No | Yes (different app) | Active | Confirm cross-app switch |
| Household + not at home | Yes | No | Inactive (greyed) | No-op or tooltip |
| Household + not at home | Yes | Yes (this app) | Active, "Active Session" | Join as audience |
| Household + not at home | No | No | Active | Start new session |
| Household + not at home | No | Yes (this app) | Active, "Active Session" | Join as player |
| Non-household user (NHHU) | Yes | No | Inactive (greyed) | No-op or tooltip |
| Non-household user (NHHU) | Yes | Yes (this app) | Inactive (greyed)¹ | No-op (audience-join routed via app-specific deep link, e.g., audience.html) |
| Non-household user (NHHU) | No | No | Active | Start new session |
| Non-household user (NHHU) | No | Yes (this app) | Active, "Active Session" | Join as player |

¹ NHHU audience access for TV-required apps is via app-specific deep link (e.g., audience.html) today. Tile-based audience-join from the post-login home lands when audience.html migrates into the unified app — see "Architectural direction" section below.

---

## Proximity model

### When the banner fires

**On post-login home render**, an inline banner appears at the top of the home when ALL of the following are true:

1. User is a household member with at least one TV claimed (Mode A/B candidate)
2. User landed on the post-login home directly (not via a deep-link to audience.html, player.html, or another in-app destination)
3. User has not previously selected "Don't show me again" for the currently-selected TV (per-TV persistence — see Banner UI subsection)
4. User has not yet answered the proximity question for this TV-connection-session

The banner does NOT fire when:
- User has no household (Mode C — never)
- User deep-linked into an audience or player invite flow (skips home entirely)
- User previously chose "Don't show me again" for this TV (default applies; no banner)
- User already answered the question for this TV-connection-session

For multi-TV households (n>1): the TV picker resolves first, then the banner fires for the selected TV. The "Don't show me again" preference is per-TV, not global — a user can opt out for one TV but still be prompted for another.

### Banner UI

The proximity banner is an inline element rendered at the top of the post-login home when the firing conditions above are met. It does not block the rest of the home — tiles render below it — but it is visually prominent.

The banner shows three actions:

- **"Yes, I'm at home"** → user proceeds in Mode A; answer stored in sessionStorage for the current TV-connection-session
- **"No, I'm not"** → confirm dialog: "You'll join as audience for sessions that need a TV. Continue?" → on confirm, user proceeds in Mode B; on cancel, banner remains visible
- **"Don't show me again"** → answer locked to "yes" by default; preference stored in DB (per-user-per-TV); banner does not fire on future post-login-home renders for this TV. User can revisit this choice via the new "Proximity Settings" menu item (see below).

### Default proximity for first-time interaction

If the user has not yet answered and has not selected "Don't show me again," the home renders in **Mode A by default** while the banner is visible. The user is treated as at-home until they explicitly answer otherwise. This minimizes friction for the dominant case (household members at home most of the time) while still surfacing the question.

### "Proximity Settings" menu item

A new menu item under the user's badge menu, alongside Contacts / Groups / Manage Household / Your TVs / Sign Out. Drilling in shows:

- Current proximity for current TV: at-home / not-at-home toggle
- "Always ask me on next session" — re-enables the banner (clears the "Don't show me again" preference)
- For users with multiple claimed TVs (n>1): per-TV settings

Back from this drill-in returns to the post-login home. Settings changes apply immediately.

### Per-app interpretation of the answer

Proximity is one answer from the user, but apps interpret it differently:

- **Karaoke (and similar TV-device-required apps): hard gate.** "No" means the user cannot sing — only audience. Tile state in Mode B reflects this (greyed when no session, "Active Session" when session exists for audience-join).
- **Games (post-venues integration): soft gate.** "No" doesn't demote the user — they still play. The "no" answer affects only TV-side rendering (they don't get inserted into the venue background; show as name + avatar + video tile instead). For Session 5's pre-venues games, proximity doesn't matter — games doesn't require TV device today.
- **Wellness (when it ships): hard gate.** Same pattern as karaoke.

### Persistence

Two layers of persistence:

**Per-TV-connection-session (sessionStorage):**
- The user's answer to the proximity prompt for the currently-active TV-connection
- Cleared on app force-close, phone restart, explicit TV switch (multi-TV scenario), or sign-out
- 10-minute inactivity expiration is **deferred** for Phase 1 (see DEFERRED.md "Phone proximity persistence — 10-minute inactivity expiration"). 2c.x ships sessionStorage-only.

**Per-user-per-TV (DB):**
- The "Don't show me again" preference, stored in a new `user_preferences` table (or equivalent — per 2c.1 design)
- Persists across app reinstalls, new devices, and sign-out → sign-in cycles
- Editable via the "Proximity Settings" menu item

### Recovery

If the user answered incorrectly (said "no" but actually is at home, or vice versa), recovery is via:

- **Banner answer change:** if the banner is still visible, tap a different option
- **Menu navigation:** drill into "Proximity Settings" via the badge menu, change the answer
- **Natural disengagement:** force-close the app → re-prompted on next launch (assuming "Don't show me again" not selected)

---

## Phone navigation model

### Pre-login

- **Pre-login home:** Sign-in/Create button + guest tiles (room code entry). No back button. Tile-tap to guest entry navigates to room-code prompt.
- **Sign-in screen:** Email input + magic link send. Back button → pre-login home.
- **Check-your-email screen:** Confirmation message. Back button → pre-login home.

### Post-login

- **Post-login home (single screen):** Conditional rendering per Mode A/B/C above. No back button.
- **Badge menu drill-ins (Contacts, Groups, Manage Household, Your TVs):** Back button → post-login home. The home re-renders in whatever mode matches current state.
- **In-app pages (singer.html, player.html, audience.html):** Back-to-Elsewhere visible for all audience users. Destination differs by user type — household members land on the post-login home; NHHU lands on a placeholder Elsewhere home (audience-to-NHHU conversion path). See "Back-to-Elsewhere navigation" section for details.

### "Your TVs" menu item

Under the new model, "Your TVs" is informational/management, not a navigation path to a separate home variant:

- **n=1:** Tap shows confirmation/info ("Connected to: Living Room"). No-op for TV selection. May offer "Disconnect" or "Manage" actions.
- **n>1:** Tap shows TV picker → selecting a different TV updates the home's TV context → home re-renders with new TV info.

The current code's `screen-tv-remote` (small-tile screen with back button) is **deprecated under this model**. Its responsibilities (TV name display, app tiles for the TV, app-tile tap handler) move into the unified post-login home.

---

## Back-to-Elsewhere navigation

Per Session 5 Part 2 design: **Back-to-Elsewhere is navigate-only**. Tapping the button navigates the user from a participant page (singer.html, player.html, audience.html) to an Elsewhere home. The session continues running on the TV regardless of who navigates back; the button does not end the session.

### Visibility rule

**All audience users see Back-to-Elsewhere.** What changes by user type is the destination:

- **Household member with TV access (Modes A/B):** lands on their normal post-login home (Mode A or B). Active session is reflected via "Active Session" tile relabeling per the home unification section.
- **Non-household user (Mode C, NHHU):** lands on a placeholder Elsewhere home offering "go back to where you were" + "explore Elsewhere" options. This is the audience-to-NHHU conversion path.

See `docs/KARAOKE-CONTROL-MODEL.md` § 4.4 for the full Back-to-Elsewhere visibility evolution and per-user-type behavior on tap.

This revises an earlier draft of the state model that scoped Back-to-Elsewhere to household members only ("Mode C does not see the button; they are app-scoped to the link target"). The earlier framing prevented NHHU audience users from ever returning to an Elsewhere context, which closed off the audience-to-NHHU conversion path. The new rule decouples visibility (universal) from destination (per-user-type).

An even earlier draft restricted Back-to-Elsewhere to managers only — the assumption being it was a manager-authority concept ("I'm running this, I can step away"). In practice, cross-app switching is gated by RPC-level authority (`rpc_session_end` is manager-only), so a non-manager who navigates back and accidentally taps a different app's tile will see the cross-app-switch RPC fail safely. UI-level navigation restriction was protecting against a non-issue.

### Behavior when a household member navigates back

1. Phone navigates from the participant page to the post-login home
2. The home renders with the active session's app tile showing "Active Session" (per Mode A/B logic in the home unification section)
3. Tapping that tile rejoins the user in their existing role (manager rejoin if manager; singer/player/audience rejoin otherwise)
4. Tapping a different app's tile triggers the cross-app switch confirm dialog. On confirm:
   - If user is the manager: `rpc_session_end` succeeds, session ends, new session starts in the new app
   - If user is not the manager: `rpc_session_end` fails (RPC-level rejection). User sees an error; session continues; user remains on the home
5. The TV is unaffected by the navigation. It stays on stage.html (or games/tv.html) because the session is still active. The TV's `exit_app` handler (Part 2b) checks session state and stays put when the session is live.

### Behavior when an NHHU navigates back

1. Phone navigates from the participant page (typically `audience.html` today) to the placeholder Elsewhere home
2. Placeholder offers "go back to where you were" (returns to the participant page) and "explore Elsewhere" / sign-up options
3. The TV is unaffected by the navigation; the session continues
4. Full conversion-funnel UX (sign-up flow, app downloads, game launchers) is post-Session-5 — see DEFERRED "Audience-to-NHHU conversion path"

### Notes on hosts

In edge cases, a manager may promote a non-household-member (deep-link audience user) to the host role. Such a host sees Back-to-Elsewhere like any other audience user under the new visibility rule, but tapping it routes them to the placeholder Elsewhere home, not the household home. The household-home boundary is preserved by destination routing, not by hiding the button.

---

## Active session participation

### Roles

Two independent role axes:

- **Control role:** `manager` (one per session, originator), `host` (zero or more, manager-equivalent within app), `none` (default)
- **Participation role:** `active` (currently performing/playing), `queued` (waiting), `audience` (present but not performing)

These axes are independent. A manager can be `control_role=manager, participation_role=audience` (running the session but not currently singing). A regular user can be `control_role=none, participation_role=active` (singing, no authority).

### How users enter sessions

- **Manager:** originates by tapping an app tile (Part 2b's `rpc_session_start`). Created with `control_role=manager`.
- **Singer (karaoke) / player (games), at home:** tap an app tile during an active session → `rpc_session_join` with appropriate participation role.
- **Audience:** several paths. Karaoke audience navigates explicitly to `audience.html` (today). Not-home household users join active sessions via the post-login home's "Active Session" tile, also as audience.

### How users exit sessions

Per the Session 5 design we locked earlier:

- **Active singer finishes song:** role transition `active → queued` or `active → audience` via `rpc_session_update_participant`. Not a leave.
- **Queued singer drops out:** role transition `queued → audience` via same RPC.
- **Audience closes app or navigates away:** implicit. No RPC fires. Their `session_participants` row remains with `left_at = null` (ghost-audience, accepted as Phase 1 trade-off).
- **Manager ends session:** explicit "End Session" button → `rpc_session_end` → session over for everyone.
- **Manager goes inactive 10+ min:** orphan threshold → another household member can reclaim via `rpc_session_reclaim_manager`, becoming new manager.
- **Household admin force-reclaim:** `rpc_session_admin_reclaim` regardless of activity.
- **Host or non-manager participant exiting the app entirely:** no UI for this in current scope. Would require manager to end session or admin reclaim.

`rpc_session_leave` is retained in the database for future use (background cleanup, future explicit-leave flows) but is not called from any user-facing UI in current scope.

---

## TV device as rendering capability

The TV device (the camera + display setup that lets users be composited into a venue background) is a **rendering capability**, not a visibility gate. Stated explicitly:

- Every TV viewer sees every participant in a session.
- TV viewers WITH a TV device see participants composited into the venue background (camera-tracked, like karaoke singers today).
- TV viewers WITHOUT a TV device see those same participants as name + avatar + video stream (no composition).

This applies to all apps that use venues. Karaoke today uses TV device; games will use it post-venues integration. The DEFERRED entry "Games TV rendering matrix (post-venues integration)" captures the full table.

---

## Timeouts

Three timeout values govern state cleanup. All should be configurable via a future platform admin UI; current Phase 1 defaults are hardcoded constants.

| Timeout | Default | What it does |
|---|---|---|
| TV inactivity | 10 min | TV returns from State 2 (apps grid) to State 1 (QR code) when no activity. Does not fire from State 3 (active session). |
| Manager orphan | 10 min | Active session becomes orphan-reclaimable when manager has been inactive this long. Triggers eligibility for `rpc_session_reclaim_manager`. |
| Phone proximity persistence | 10 min | Proximity answer expires after this much phone-side inactivity, requiring re-prompt on next interaction. |

These three are conceptually independent but happen to share the same default. Operational tuning may diverge them.

**Configurable via:**
- Currently: hardcoded in code
- Future: `platform_settings` DB table, with platform-admin UI for editing
- Depends on: a platform-admin role (separate from household-admin) — does not exist yet

These items will be captured in DEFERRED.md when the platform admin role and configurable-timeout work are scheduled (post-Session-5).

---

## Guest flow

Defined here for completeness; implementation deferred.

A guest (non-household user) can scan the QR code on a TV in State 1, sign in or create an account on their phone, and bootstrap a session on that TV without becoming a household member. Open questions for implementation:

- Can a guest be a manager? (Probably yes — they originated the session.)
- Can a host promote a guest to a participant role? (Probably yes.)
- When the session ends, does the guest's identity persist? (Yes — they have an `auth.users` record; they just aren't a `household_members` row.)
- Does the guest appear in the household's "remembered" list afterward? (No — that's what household membership means.)

These resolve in the guest flow's own design pass. Guest flow design will be revisited as a separate item once the state model is in place; capture-to-DEFERRED expected when that work is scheduled.

---

## Multi-TV selection

For users with more than one claimed TV (n>1):

- Post-login home renders an inline picker BEFORE the proximity prompt fires
- User selects a TV → home re-renders with that TV's context, then proximity prompt fires
- User can switch TVs via the badge menu's "Your TVs" → returns to picker → selecting a new TV resets proximity (the question is "are you at home with *this* TV")

Persistence note: TV selection persists across app launches as long as the user remains signed in. Re-selecting only happens when the user explicitly changes TVs.

---

## Architectural direction: unified app with parameterized NHHU view

Future state is a unified Elsewhere app with a parameterized NHHU view based on user context. NHHU users see the same UI fabric as HHU users; conditional rendering hides TV-required features and routes appropriately. Audience.html is frozen for Session 5 (bug fixes only). Audience-experience features build into the unified app post-Session-5. Triggered when NHHU-as-first-class-user feature work begins (games venues, wellness, etc.).

See `docs/KARAOKE-CONTROL-MODEL.md` § 5.5 and the "Karaoke control model" cluster of DEFERRED entries (audience.html freeze, audience.html migration into unified app, audience-to-NHHU conversion path, audience read-only queue, audience venue/costume browsing).

---

## What this document does NOT cover

The following are intentionally out of scope for this state model. They have their own design documents or DEFERRED entries:

- Specific app-internal flows (queue management within karaoke, game lobby mechanics, etc.) — see app-specific plan docs
- Backend RPC implementations — see `db/008` through `db/011` migrations
- Realtime event emission contract — see `shell/realtime.js` header
- Authentication flow specifics — see Session 4.10 series plans
- Household management (claim, invite, member roles) — see Session 4.10 plans

---

## Relationship to existing plans

**SESSION-5-PLAN.md Decision 8** (per-app `ask_proximity` flag): superseded. The flag is no longer the model; proximity prompts at TV-connect with per-app interpretation of the answer.

**SESSION-5-PART-2-BREAKDOWN.md Part 2c** (apps grid session-awareness): scope expands to include unification of the post-login home screen. May need to split into 2c.1 (structural unification) and 2c.2 (active session relabeling + rejoin).

**SESSION-5-PART-2-BREAKDOWN.md Part 4** (proximity self-declaration UX): substantially absorbed into 2c. Part 4 may collapse or become a polish/edge-case session.

**Session 4.10.2 / 4.10.3 conventions** (sessionStorage bridge for `device_key`, single realtime channel, await-before-navigate): preserved unchanged. The state model layers on top of these without altering the underlying mechanics.

---

## Updating this document

When a future session changes any element of this model, update this document in the same commit as the code/plan change. Don't let drift accumulate. The doc is canonical only as long as it's kept current.
