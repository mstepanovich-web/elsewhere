# Session 4.10.3 Verification — Phone back-to-Elsewhere + coordinated TV teardown

**Session status:** Parts A + B + C shipped; verified end-to-end on real hardware (iPhone + laptop TV browser) through commit `40e4f4b`.
**Drafted:** 2026-04-22
**Planning reference:** `docs/SESSION-4.10.3-PLAN.md`

---

## Commits shipped in Session 4.10.3

| SHA | Description |
|---|---|
| `f43369a` | **Part A** — `exit_app` realtime wiring: `publishExitApp` helper in index.html, sessionStorage device_key bridge, on-boot `exit_app` listener on `karaoke/stage.html` + `games/tv.html`. Scope expansion: added `shell/auth.js` to `games/tv.html`. |
| `2c2d5fe` | **Part B** — Back-to-Elsewhere pill button on `karaoke/singer.html` (top-right), inline `publishExitApp` + `handleBackToElsewhere`. Scope expansion: added `shell/auth.js` to `singer.html`. |
| `50a9f5c` | **Post-Part-B fix** — Added `viewport-fit=cover` to singer.html's viewport meta tag. Back button was rendering behind iOS status bar because `env(safe-area-inset-top)` was returning 0. |
| `40e4f4b` | **Part C** — Fixed `games/player.html` "Back to Home" link. Extracted inline onclick into `handleBackToElsewhere`; corrected pre-existing hardcoded URL bug (was pointing at tv2.html on GitHub Pages, now relative `../index.html`); wired `publishExitApp`. No scope expansion — shell/auth.js + viewport-fit=cover were already present. |

---

## Verification status at a glance

| # | Flow | Status |
|---|------|--------|
| 1 | Karaoke back (singer) | ✓ **Passed** — confirmed on hardware |
| 2 | Karaoke back (audience) | ⏸ **Deferred** — see DEFERRED "Audience back-to-Elsewhere navigation" |
| 3 | Games back (player → TV apps grid) | ✓ **Passed** — confirmed on hardware |
| 4 | Realtime failure posture (no wifi on phone) | ⏸ **Not tested** — documented Phase-1 behavior |
| 5 | Karaoke regression (stage.html subscription added) | ◐ **Partial** — smoke-verified via Flow 1; explicit checks below |
| 6 | Games regression (games/tv.html subscription added) | ◐ **Partial** — smoke-verified via Flow 3; explicit checks below |
| 7 | Shell-load smoke test (cumulative Part A + B) | ◐ **Partial** — implicit pass via Flows 1, 3, 5, 6; explicit checks below |

**Legend:**
- ✓ Passed — explicitly run and confirmed
- ◐ Partial — smoke-covered by other flows; specific checks still useful
- ⏸ Deferred / Not tested — intentional or unrun

---

## Flow 1 — Karaoke back (singer)

**Status:** ✓ Passed

**Prereq:** User is authed on phone; TV is claimed + on apps grid; phone is on `screen-tv-remote` for that TV.

**Steps:**

```
[x] 1. On phone, tap Karaoke tile on screen-tv-remote
[x] 2. Observe TV navigates to karaoke/stage.html
[x] 3. Observe phone navigates to karaoke/singer.html?code=XXXXXX
[x] 4. Top-right "← Elsewhere" pill button visible on phone
[x] 5. Tap "← Elsewhere"
[x] 6. Observe phone returns to Elsewhere shell (screen-tv-remote for n=1)
[x] 7. Observe TV returns to tv2.html apps grid within ~1-2s
```

**Actual:** After post-Part-B viewport-fit=cover fix (`50a9f5c`), button renders correctly (not behind status bar). End-to-end loop works: phone publishes `exit_app` on `tv_device:<device_key>` channel, TV's `handleExitApp` listener fires, TV unsubscribes cleanly and navigates to `../tv2.html`. Phone navigates to `../index.html` which auto-routes back to the TV remote screen.

---

## Flow 2 — Karaoke back (audience)

**Status:** ⏸ Deferred — NOT tested.

**Context:** Audience role semantics (who can reach audience.html, what "back" means for non-members, whether TV teardown should fire when one of multiple audience members leaves) aren't specified yet. Filed as DEFERRED entry "Audience back-to-Elsewhere navigation" pending Session 5's per-app role manifest work.

**Prerequisite noted in DEFERRED:** `karaoke/audience.html` also lacks `viewport-fit=cover`; must be added before any button is placed top-right (singer.html hit this same bug, see `50a9f5c`).

---

## Flow 3 — Games back (player → TV apps grid)

**Status:** ✓ Passed

**Prereq:** User is authed on phone; TV is claimed + on apps grid; phone is on `screen-tv-remote` for that TV.

**Steps:**

```
[x] 1. On phone, tap Games tile on screen-tv-remote
[x] 2. Observe TV navigates to games/tv.html
[x] 3. Observe phone navigates to games/player.html?room=XXXXXX&mgr=1
[x] 4. Enter the lobby screen (may need to pass through join flow first)
[x] 5. Observe "⌂ Back to Home" link visible at bottom of lobby
[x] 6. Tap "⌂ Back to Home"
[x] 7. Observe phone returns to Elsewhere shell (screen-tv-remote for n=1)
[x] 8. Observe TV returns to tv2.html apps grid within ~1-2s
```

**Actual:** Part C's handler extraction + URL fix + `publishExitApp` wiring works as designed. Same `exit_app` broadcast → TV teardown flow as Flow 1.

**Pre-existing bug also fixed incidentally (confirmed):** before this session, tapping "Back to Home" navigated the phone to `https://mstepanovich-web.github.io/elsewhere/tv2.html` via hardcoded URL — broken in the iOS Capacitor wrapper. Now correctly uses relative `../index.html`.

---

## Flow 4 — Realtime failure posture (phone offline)

**Status:** ⏸ Not tested — documented Phase-1 behavior.

**Design posture (per plan Architecture Decision 7):** if realtime is unreachable when user taps back, the phone still navigates to Elsewhere (unconditional per post-`7b81f70` await pattern). TV stays on `stage.html` / `games/tv.html` until manually refreshed. Acceptable Phase-1 failure mode; same risk tier as `launch_app`'s own delivery failure. Heartbeat / auto-reconnect tracked in DEFERRED if customer testing surfaces real pain.

**If you run this flow later, steps:**

```
[ ] 1. Complete Flow 1 or Flow 3 up to the in-app page (singer.html or player.html)
[ ] 2. Disable wifi on phone (and disable cellular data if testing Capacitor wrapper; for browser, just disable network via devtools)
[ ] 3. Tap "← Elsewhere" / "⌂ Back to Home"
[ ] 4. Expected: phone navigates to Elsewhere shell within ~5-6s (after 5s subscribe timeout fires)
[ ] 5. Expected: console shows "[elsewhere] exit_app publish failed: ..." error
[ ] 6. Expected: TV stays on stage.html / games/tv.html
[ ] 7. Re-enable wifi, manually refresh TV, observe it returns to apps grid on reload
```

---

## Flow 5 — Karaoke regression (stage.html subscription)

**Status:** ◐ Partial — smoke-covered by Flow 1

**Context:** Part A added a new realtime subscription to `karaoke/stage.html` (for the `exit_app` listener). stage.html is ~5k lines with complex Agora + YouTube + DeepAR + lyrics + admin-gear code. The new subscription is new surface area. Flow 5 confirms nothing broke.

**What Flow 1 implicitly verified:**
- Venue background renders (Flow 1 would have caught a venue-load regression)
- Agora audio publishes from singer to stage (Flow 1 implicitly tested the singer → stage hookup)

**Explicit regression checks still worth running when convenient:**

```
[ ] YouTube karaoke video loads and plays on stage.html
[ ] Synced lyrics fetch from lrclib.net and display with the music
[ ] DeepAR face filters function (pick any one filter on singer, verify composited video appears on stage)
[ ] Admin gear icon visible on stage (when signed in as platform admin)
[ ] Admin "Set View Coordinates" dialog opens and saves correctly
[ ] Console shows no errors related to the new exit_app subscription
```

---

## Flow 6 — Games regression (games/tv.html subscription)

**Status:** ◐ Partial — smoke-covered by Flow 3

**Context:** Part A added a new realtime subscription to `games/tv.html` (exit_app listener) AND added `shell/auth.js` (new script dependency). Flow 6 confirms nothing broke.

**What Flow 3 implicitly verified:**
- Lobby renders on games/tv.html after Games tile launch
- Phone joins lobby successfully (means Agora hookup works)

**Explicit regression checks still worth running when convenient:**

```
[ ] Start a game of Last Card — game launches cleanly
[ ] Play a few rounds — game state syncs phone ↔ TV correctly
[ ] Manager bar on phone visible when ?mgr=1; buttons work (Start, Reveal, Next, etc.)
[ ] END SESSION button works as game-scoped (returns user to lobby, does NOT trigger exit_app or TV teardown)
[ ] Start a game of Trivia; similar sync checks
[ ] Console shows no errors related to the new shell/auth.js load or exit_app subscription
```

---

## Flow 7 — Shell-load smoke test (cumulative Part A + B)

**Status:** ◐ Partial — implicit pass via Flows 1, 3, 5, 6

**Context:** During 4.10.3, `shell/auth.js` was added to two pages that didn't previously load it:
- `games/tv.html` — added in Part A (`f43369a`)
- `karaoke/singer.html` — added in Part B (`2c2d5fe`)

`games/player.html` already had shell before this session; Part C didn't change that.

**What Flows 1–3 implicitly verified:**
- Pages load without crashing (we successfully completed the forward + back flows through them)
- `window.sb` is available (publishExitApp and handleExitApp both use it and worked)

**Explicit checks still worth running when convenient:**

For each of `games/tv.html` and `karaoke/singer.html`:

```
[ ] Open the page in a fresh browser session (DevTools open)
[ ] Console shows no uncaught errors during load
[ ] Existing app functionality intact (see Flows 5 and 6)
[ ] No unexpected auth prompts, magic-link flows, or redirects fire on page load
[ ] Console check: `typeof window.sb === 'object'` returns true post-load
[ ] Console check: `typeof window.elsewhere === 'object'` returns true post-load
```

---

## Issues found (if any)

- **singer.html status-bar overlap** — Part B's new back button initially rendered behind the iOS status bar on notched iPhones because singer.html's viewport meta was missing `viewport-fit=cover`. Fixed in `50a9f5c`. Incidentally corrected three other pre-existing latent bugs (LOG button, voice cancel button, screen-header padding) that used `max(N, env(safe-area-inset-top))` but weren't receiving the env value. All now sit at their intended positions.
- **games/player.html "Back to Home" URL** — pre-existing bug discovered during Part C: link was navigating phones to `tv2.html` via hardcoded GitHub Pages URL. Fixed incidentally as part of the Part C handler extraction.

## Follow-ups from this session

- File `karaoke/audience.html` back button in Session 5 per DEFERRED "Audience back-to-Elsewhere navigation" (prerequisite: add `viewport-fit=cover` to audience.html first).
- Extract `publishExitApp` + related realtime helpers into `shell/realtime.js` when Session 5 adds more events — see plan's "Deferred items likely to emerge."
- Consider a universal top-right back button on games/player.html if mid-game escape (currently requires END SESSION → lobby → Back to Home) proves a real UX pain point.
