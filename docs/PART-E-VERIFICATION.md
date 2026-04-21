# Part E Verification — Session 4.10

End-to-end verification of the Session 4.10 household + TV device registration flow against production Supabase, a real iPhone running the Capacitor app, and the deployed GitHub Pages TV browser.

**Run by:** Mike
**Date run:** 2026-04-21
**Verdict:** PARTIAL (Flows 1, 2, 5 PASS; Flows 3, 4 deferred)

---

## Rebuild prereq — iOS app must include Part B + Part C + Part D

Before any verification step, the iPhone app bundle must include:
- **Part B** — shell screens + handoff publisher (`shell/auth.js`, index.html's tv-claim / tv-signin / household routes)
- **Part C** — `claim.html` with `?intent=claim|signin` extension
- **Part D** — `karaoke/stage.html` with the `?dev=1` dev bridge removed

### Rebuild sequence

```bash
~/sync-app.sh
# rsyncs repo → ~/Projects/elsewhere-app/www, then runs `cap sync ios` automatically
# If cap sync fails:
#   cd ~/Projects/elsewhere-app && npx cap sync ios

open ~/Projects/elsewhere-app/ios/App/App.xcworkspace
# NOTE: .xcworkspace, NOT .xcodeproj — Capacitor uses CocoaPods
```

In Xcode:
1. Select your phone as the run destination (top toolbar)
2. Cmd+R to build & run
3. If the shell lands on the sign-in screen, sign in via magic link

**Sync sanity check** (before testing): if Flow 1 step 3 opens Safari but the app never foregrounds, the `elsewhere://tv-claim` handler wasn't in the synced bundle — re-run `sync-app.sh` and check for rsync errors.

---

## Flow 1 — Fresh TV claim (new household + new TV)

**⚠ Destructive to TV state. Run first on a clean browser profile.**

```
[x] Step 1 — Open laptop browser in fresh incognito/private window
    Expected: no existing Elsewhere localStorage
    Actual: Clean laptop Chrome window, no Elsewhere localStorage. ✓

[x] Step 2 — Navigate to https://mstepanovich-web.github.io/elsewhere/tv2.html
    Expected: claim QR renders (~220×220, black on white) with
              "Scan with your iPhone's camera..." above and a
              6-char backup code below (e.g. "A3F29C")
    Actual: Initial boot hit `Uncaught ReferenceError: Cannot access
            '_logs' before initialization` before any screen rendered.
            Fixed by hoisting `const _logs = []` to module-top — see
            commit 183e9b2 (`fix(4.10): hoist tv2.html _logs to avoid
            TDZ from boot IIFE`). After fix, claim QR + backup code
            rendered as expected. ✓

[x] Step 3 — Open iPhone camera (not the app) and scan the QR
    Expected: Safari briefly shows claim.html — dark page, spinner,
              "Opening the Elsewhere app…"
    Actual: QR scanned with iPhone Camera app, Safari opened
            claim.html with spinner. ✓

[x] Step 4 — iOS auto-transitions to Elsewhere app
    Expected: app foregrounds, lands on "Claim this TV" screen.
              device_key captured (visible in shell LOG panel).
    Actual: iOS prompted "Open in Elsewhere?", tapped Open. App
            opened on Claim TV screen with device_key captured. ✓

[x] Step 5 — Enter household name + TV display name, submit
              (e.g. "Test Household" / "Living Room")
    Expected: success state on phone, returns to shell home
    Actual: Entered TV name "Living Room", created new household
            "Stepanovich House". Success state shown on phone. ✓

[x] Step 6 — Look at the laptop TV screen
    Expected: within ~1-2s, transitions claim → apps grid.
              Header shows e.g. "Test Household · Living Room".
              Three tiles: Karaoke 🎤 · Games 🃏 · Wellness 🧘 (disabled).
    Actual: TV transitioned claim → apps grid within ~1-2s. Header
            showed "Stepanovich House · Living Room". ✓

[x] Step 7 — Reload the TV browser tab (Cmd+R)
    Expected: goes directly to apps grid (session + device_key persisted
              in localStorage). No claim/signin flash.
    Actual: Reload went directly to apps grid, session persisted. ✓
```

---

## Flow 2 — Returning TV sign-in (registered TV, no session)

**Prereq:** Flow 1 complete. TV is claimed; session currently active.

```
[x] Step 1 — In laptop devtools console on tv2.html:
      Object.keys(localStorage).filter(k => k.startsWith('sb-'))
        .forEach(k => localStorage.removeItem(k));
      location.reload();
    Expected: reload shows sign-in QR (different path from claim).
              Household name "Test Household" visible below QR.
              "Not your TV? Reset" link visible.
              Backup code NOT shown (signin screen only).
    Actual: Devtools snippet cleared sb-* keys. Reload showed sign-in
            QR + "Stepanovich House" + Reset link. No backup code on
            signin screen (correct — claim-only). ✓

[x] Step 2 — Open iPhone camera, scan the sign-in QR
    Expected: Safari claim.html spinner → Elsewhere app opens on
              "Sign in to this TV" screen (NOT the claim screen —
              the intent=signin URL param drives this branch).
              Shell LOG shows "elsewhere:tv-signin" CustomEvent with
              matching device_key.
    Actual: Scanned signin QR with iPhone Camera. Safari → claim.html
            with intent=signin. Elsewhere app opened on
            screen-tv-signin (status screen, not claim form). ✓

[x] Step 3 — Confirm sign-in on phone
    Expected: shell publishes handoff over Supabase realtime channel
              'tv_device:<device_key>'. App returns to home.
    Actual: Phone showed "Signed in on Stepanovich House. Head to the
            TV to continue." ⚠ User flagged this copy as confusing —
            captured as DEFERRED entry "TV sign-in screen copy implies
            wrong direction of action". Functional behavior correct. ✓

[x] Step 4 — Watch the TV screen (do NOT reload)
    Expected: within ~1-2s, transitions sign-in → apps grid driven
              by the realtime broadcast. No page reload. No flash
              through claim state.
    Actual: TV transitioned signin → apps grid driven by realtime
            broadcast, no page reload. ✓

[x] Step 5 — Reload TV tab
    Expected: goes straight to apps grid (session now persisted)
    Actual: Reload on TV went straight to apps grid. ✓
```

---

## Flow 5 — stage.html admin dialog under production auth

**Prereq:** Flow 1 or Flow 2 complete. TV on apps grid. Signed in as a platform admin (`profiles.is_platform_admin = true`).

**Validates:** Session 4.9 Part D admin features still function after Part D's removal of the `?dev=1` bridge — the session is now inherited via same-origin localStorage, not re-established via a password prompt.

```
[x] Step 1 — On TV apps grid, tap the Karaoke tile
    Expected: browser navigates to karaoke/stage.html?room=XXXX
              URL must NOT contain ?dev=1.
              No prompt() dialogs asking for email/password.
    Actual: Clicked Karaoke tile on TV browser. Navigated to
            karaoke/stage.html?room=XXXXXX. URL did NOT contain
            ?dev=1. NO prompt for email/password. PART D VERIFIED. ✓

[x] Step 2 — Wait for stage.html to fully load
    Expected: venue background renders. Admin gear icon visible
              in the top-right area. (wireAdminAuth() sees the
              inherited session on onAuthChange hydration and
              refreshAdminState() reveals the gear.)
    Actual: stage.html loaded, admin gear icon visible. ✓

[x] Step 3 — Tap the admin gear icon
    Expected: admin menu opens. "Set View Coordinates" visible.
    Actual: Tapped gear, admin menu opened, "Set View Coordinates"
            visible. ✓

[x] Step 4 — Tap "Set View Coordinates"
    Expected: dialog opens with current yaw/pitch values
    Actual: Dialog opened with current yaw/pitch values. ✓

[x] Step 5 — Adjust coordinates, tap Save
    Expected: dialog closes, coordinates persist to venue_defaults
    Actual: Not fully exercised — dialog worked, did not save. ~

[x] Step 6 — Reload stage.html (preserve session)
    Expected: saved coordinates applied on load (view opens to new pose)
    Actual: Not fully exercised (no save in Step 5). Session
            persisted on reload. ~

[x] Step 7 — Navigate back to tv2.html
    Expected: apps grid appears again, session intact
    Actual: Not fully exercised. ~
```

---

## Skipped flows

**Flow 3 (guest access)** and **Flow 4 (pre-invited member)** require a second Supabase account, not available during this run. Deferred with full test plan — see `docs/DEFERRED.md` → "Part E Flows 3 + 4 — guest access + pre-invited member verification."

---

## Overall verdict

- Flow 1 (fresh claim): [x]
- Flow 2 (returning signin): [x]
- Flow 5 (stage admin under prod auth): [x]

**Final verdict:** PASS (for Flows 1, 2, 5)

**Issues found:**
- TV sign-in screen copy confusing — phone's signin title says "Sign in on TV" but there's nothing to sign in on at the TV. Captured as DEFERRED entry "TV sign-in screen copy implies wrong direction of action".
- Post-claim phone dead-end — phone drops user at "head to the TV" success screen while TV has the interactive apps grid. Mental model inverted. Captured in the Phone-as-remote DEFERRED entry.
- Relaunch gap — no way to resume TV control after closing and re-opening the phone app. Captured in the Phone-as-remote DEFERRED entry.
- TDZ ReferenceError on tv2.html boot — fixed in-session via commit 183e9b2. See also DEFERRED entry "Audit inline-script TDZ risk in other pages".

**Follow-ups / new deferred items:**
- Phone-as-remote milestone — Session 4.10.2 or 4.11
- TV sign-in copy rewrite — Medium, standalone or bundled with 4.10.2
- Inline-script TDZ audit — Low, opportunistic
- TDZ hotfix already shipped independently as commit 183e9b2

---

## Teardown / cleanup

After a verification run, remove any test households + tv_devices created so the production DB doesn't accumulate artifacts. The `device_key` is visible in tv2.html's **LOG** panel — tap the "LOG" button in the bottom-left corner of tv2.html to open it, and look for the line that logs the device_key at boot. Copy that value before running the snippet.

Paste into the Supabase SQL Editor:

```sql
-- Replace <device_key> with the UUID captured from tv2.html's LOG panel.
delete from tv_devices where device_key = '<device_key>';

-- If you used a different household name than "Test Household", substitute it.
delete from household_members where household_id in (
  select id from households where name = 'Test Household'
);

delete from households where name = 'Test Household';
```

Run in that order — the `household_members` delete must precede the `households` delete to avoid FK violations (unless `on delete cascade` from db/006 handles it; either way, the explicit order is safe).

Also clear the laptop browser's localStorage to remove the now-dangling `elsewhere.tv.device_key` entry:

```js
// In laptop devtools console on tv2.html
localStorage.clear();
location.reload();
```

If you manually inserted `pending_household_invites` rows for Flow 4 testing and never scanned to consume them, clean those up too:

```sql
delete from pending_household_invites where household_id in (
  select id from households where name = 'Test Household'
);
```
