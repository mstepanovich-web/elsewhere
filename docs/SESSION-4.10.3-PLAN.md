# SESSION 4.10.3 PLAN — Phone back-to-Elsewhere + coordinated TV teardown

**Status:** Design complete, implementation not started
**Drafted:** 2026-04-22
**Depends on:** Session 4.10.2 through commit `7b81f70` (phone-as-remote forward loop shipped)
**Unblocks:** Real customer usability — completes the session lifecycle loop that 4.10.2 opened

---

## Goal

Add the reverse of Session 4.10.2's forward path. A user in `karaoke/singer.html` or `games/player.html` can tap a "back to Elsewhere" affordance, which navigates their phone to Elsewhere's shell AND publishes a realtime event that sends the TV back to `tv2.html`'s apps grid. Closes the stuck-in-app dead-end identified in 4.10.2 testing. (audience.html deferred pending role-semantics work in Session 5.)

---

## Scope

### In scope

- **Phone-side `publishExitApp` helper** — inline in each consumer page (`index.html`, `karaoke/singer.html`, `games/player.html`). Mirrors `publishLaunchApp`'s subscribe/send/unsubscribe pattern.
- **`exit_app` realtime event** on the existing `tv_device:<device_key>` channel — new event, channel unchanged.
- **TV-side `handleExitApp`** in `karaoke/stage.html` and `games/tv.html` — each page gains a realtime subscription on load (NEW surface area for these pages), a listener for `exit_app`, and clean teardown before navigation.
- **Back-to-Elsewhere button** on `karaoke/singer.html` and `games/player.html`. Same visual style across both.
- **Verification doc** — `docs/SESSION-4.10.3-VERIFICATION.md` patterned on `PART-E-VERIFICATION.md`. Includes explicit regression checks for existing karaoke/games functionality (venue rendering, Agora, game state) given the new realtime subscription on stage.html and games/tv.html.

### Out of scope (referenced in DEFERRED, not this session)

- **Multi-user session semantics** — "session manager ends for everyone" vs "non-manager leaves" distinction. Phase 1 is single-user; phone-back = TV-back. Session 5 will layer role-aware semantics on top without changing this event's name or channel. Ref: DEFERRED "Multi-phone session coordination".
- **"Are you at home?" proximity check** — Phase 1 doesn't gate back-navigation on proximity. Session 5 will revisit. Ref: DEFERRED "Proximity self-declaration".
- **Wellness app support** — wellness pages don't exist yet. When they ship, add the same button.
- **Heartbeat / auto-reconnect for TV realtime channel** — if the TV loses realtime connectivity during a karaoke/games session, the `exit_app` broadcast will miss and the TV will be stuck on `stage.html` / `games/tv.html` until manual refresh. Same risk tier as `launch_app`'s own failure posture. Acceptable for Phase 1.
- **Extracting `publishExitApp` into a shared helper module** — inline duplication is the Phase-1 pick. Extraction deferred (see "Deferred items likely to emerge" below).

### On ship, also do

File a Low-priority DEFERRED entry: *"Extract `publishExitApp` + related realtime helpers into `shell/realtime.js` when Session 5 adds more events."* Preserves the "extract later" decision point for when repeated patterns justify the abstraction.

---

## Architecture decisions

### 1. Event name: `exit_app`

Chosen over `end_session`, `leave_session`, `dismiss_app`, `phone_exit`.

Rationale:
- **Mirrors `launch_app`'s naming pattern** — symmetric action verbs on the same channel. `launch_app` starts, `exit_app` ends.
- **Action-oriented, not semantically loaded.** In Phase 1, phone exiting = session ending (only one user). In Session 5 multi-user, `exit_app` can stay as "this phone is done"; richer semantics (e.g., `session_ended` for manager-initiated teardown, `member_left` for non-manager departures) can layer on top with new event names.
- Avoids `end_session` because that implies broader "session is over for everyone" semantics that don't fit Session 5's manager/member distinction.

### 2. Event payload: `{ reason: 'user-exit' }`

Phase 1 TV handler ignores `reason` and unconditionally dismisses. The field is reserved for Session 5 extensions:
- `'user-exit'` — this phone is done (Phase 1 default)
- `'session-ended'` — manager explicitly ended (Session 5)
- `'manager-kicked'` — admin override (Session 5+)

Including a structured payload now avoids a breaking-change migration later.

### 3. Phone navigation target

`location.href = '../index.html'` — relative up from `karaoke/singer.html`, `games/player.html`, and any future same-depth pages.

On landing at `index.html`, the existing `renderAuthState(user)` → `resumePendingTvFlow()` → `enterYourTvsFlow()` chain runs. Per 4.10.2 Decision 5 (n=1 skip):
- n=0 household TVs → stays on `screen-home` (signed-out or no-membership)
- n=1 → auto-routes to `screen-tv-remote` for that TV
- n≥2 → auto-routes to `screen-your-tvs` picker

No new navigation logic. The back-tap returns to Elsewhere's shell; the shell decides where the user lands.

### 4. TV navigation target + subscription teardown

`location.href = '../tv2.html'` — relative up from `karaoke/stage.html` or `games/tv.html`.

**Cleanup before navigation is required.** The TV-side handler must:
1. `await channel.unsubscribe()`
2. `window.sb.removeChannel(channel)`
3. Then `location.href = '../tv2.html'`

Mirrors `publishSessionHandoff`'s teardown in 4.10 Part B. Prevents realtime socket leaks across navigations.

On landing at `tv2.html`, its existing boot logic runs: device_key lookup → `rpc_tv_is_registered` → session check → lands on apps grid (registered + authed). No new logic needed on the tv2.html side.

### 5. Button placement and style

**Placement:** Fixed position top-left of the viewport. Inset 12px from both edges. `z-index` above app chrome but below modals.

**Style:**
- Text: `← Elsewhere`
- Font: inherited from theme (`var(--font-ui)`)
- Size: `var(--text-sm)`
- Color: `var(--color-text-dim)` so it's present but not dominant
- Padding: 10px 14px (tap target ≥44px tall with text)
- Background: subtle `rgba(0,0,0,0.35)` for legibility over busy backgrounds (karaoke venue panoramas especially)
- Border radius: `var(--radius-pill)` — reads as a chip, not a full button

Same class definition inline on all three phone pages. Each page already links `elsewhere-theme.css`, so theme vars resolve.

### 6. On publish failure: log and navigate anyway

Same pattern as `publishLaunchApp` in 4.10.2's final fix. Wrap `publishExitApp` in try/catch, `console.error` on failure, navigate unconditionally. User is never stranded in an app even if realtime is down.

TV-side consequence if publish fails: TV stays on `stage.html` / `games/tv.html` until manually refreshed. Known acceptable Phase-1 failure mode.

### 7. TV realtime connection loss — explicit posture

**Question:** What happens if the TV loses its realtime subscription mid-session (network blip, backgrounded tab, Supabase flake) and the phone then taps back?

**Answer:** `exit_app` broadcast misses. TV stays on `stage.html` / `games/tv.html`. User must manually refresh the TV to return to apps grid.

**Decision:** Acceptable for Phase 1. Same risk tier as `launch_app`'s own delivery failure. Adding heartbeat + auto-reconnect on TV pages is out of scope — it's a broader resilience concern that would need to apply to the whole realtime layer (session_handoff, launch_app, exit_app) consistently. Cross-reference: tracked implicitly under the general "Phase 1 tolerates manual recovery seams" philosophy established in Session 4.10's planning.

If the manual-refresh recovery turns out to be a real pain point during customer testing, file as DEFERRED with a follow-up scope.

---

## Data model

**No schema changes.** `exit_app` is a new event on the existing `tv_device:<device_key>` realtime channel. Same RLS posture as `launch_app`.

If any DB work surfaces during implementation, stop and revisit scope — this session stays at UX + realtime wiring.

---

## Parts breakdown

Each part is a standalone commit. Review pause point between each.

### Part A — `exit_app` realtime wiring (phone publish + TV listeners)

**Phone side (`index.html`):** add `publishExitApp(device_key, reason = 'user-exit')` near `publishLaunchApp`. Mirror the subscribe → send → unsubscribe → removeChannel pattern from `publishLaunchApp` (post-`7b81f70`). Event name: `'exit_app'`. Payload: `{ reason }`.

**TV side — NEW subscription surface on two pages:**

- `karaoke/stage.html`:
  - On boot: read `localStorage['elsewhere.tv.device_key']`. If absent, no-op (stage.html is reachable directly without a registered TV for dev/testing; don't hard-fail).
  - Subscribe to `tv_device:<device_key>` via `window.sb.channel(...).on('broadcast', { event: 'exit_app' }, handleExitApp).subscribe(...)`.
  - On `handleExitApp` receive: `await channel.unsubscribe(); window.sb.removeChannel(channel); location.href = '../tv2.html';`
- `games/tv.html`: same pattern, same teardown, same target.

**Files touched in Part A:** `index.html`, `karaoke/stage.html`, `games/tv.html`. tv2.html does NOT need changes — it's the destination, not a listener.

**Failure-mode check:** verified in Architecture Decision 7. Loss of realtime between forward navigation and phone-tap-back results in a stuck TV; documented and accepted.

### Part B — Back-to-Elsewhere button on karaoke singer page

Covers `karaoke/singer.html` only. `karaoke/audience.html` intentionally deferred — its role semantics (how audience joins, whether they have agency to leave, what "home" means for a non-household member) aren't specified yet; depends on Session 5's per-app role manifest work. Filed as separate DEFERRED entry.

- Add inline `<style>` for `.back-to-elsewhere` class on each page (style block duplicated — acceptable per no-build-step convention)
- Add `<button onclick="handleBackToElsewhere()">← Elsewhere</button>` top-left on each page
- Inline `publishExitApp` helper in each page's script block
- Inline `handleBackToElsewhere()` wrapper: reads device_key from localStorage or pre-launch query param state (see note below), calls `publishExitApp`, then `location.href = '../index.html'`

**Device_key on phone side:** the phone doesn't have `elsewhere.tv.device_key` in its own localStorage — that key is the TV's identity, stored TV-side. The phone knows which TV it's controlling via the `screen-tv-remote` context during launch. After navigation to singer/player, that context is gone. Solutions:
- **(a)** Pass device_key via URL query string during launch (e.g., `karaoke/singer.html?code=X&tv=<device_key>`)
- **(b)** Stash device_key in sessionStorage before the launch `location.href`, consume it in the in-app page
- **(c)** Phone-side re-queries `tv_devices` on in-app page load to find the user's TV

**Pick: (b) sessionStorage bridge.** Matches the pre-existing pattern for TV deep-link flows (`PENDING_TV_CLAIM_KEY`, `PENDING_TV_SIGNIN_KEY` in index.html). Key name: `'elsewhere.active_tv.device_key'`. Set by `handleTvRemoteTileTap` in index.html before navigating; read by the in-app page's back handler; cleared by the back handler after publish.

This requires a **small index.html adjustment in Part A** (or Part B — flag during execution): set the sessionStorage key inside `handleTvRemoteTileTap` just before `location.href`. Minor, one line.

**Files touched in Part B:** `karaoke/singer.html`. (`index.html` sessionStorage bridge was folded into Part A, commit `f43369a`.)

### Part C — Back-to-Elsewhere button on `games/player.html`

Same pattern as Part B: inline style block, inline button, inline `publishExitApp`, inline `handleBackToElsewhere`. Reads the same `elsewhere.active_tv.device_key` sessionStorage key set by index.html.

**Files touched in Part C:** `games/player.html`.

### Part D — Verification

Create `docs/SESSION-4.10.3-VERIFICATION.md` patterned on `PART-E-VERIFICATION.md`. Flows:

1. **Karaoke back (singer):** launch Karaoke → phone on singer.html + TV on stage.html → tap "← Elsewhere" → phone returns to screen-tv-remote (or picker, depending on n) + TV returns to apps grid within ~1-2s.
2. ~~**Karaoke back (audience):**~~ Deferred — see DEFERRED "Audience back-to-Elsewhere navigation" entry. Audience role semantics need clarification in Session 5's per-app role manifest work before this flow can be tested meaningfully.
3. **Games back:** launch Games → phone on player.html + TV on games/tv.html → tap "← Elsewhere" → same expected behavior as Flow 1.
4. **Realtime failure posture check:** disable wifi on phone before tapping back → phone still navigates to Elsewhere; TV stays on stage.html/games/tv.html (documented failure mode; user manually refreshes TV).
5. **Regression: karaoke functionality intact after subscription added to stage.html.** Verify:
   - Venue background renders
   - Agora connection establishes (singer audio publishes to stage)
   - YouTube karaoke loads + plays
   - Lyrics fetch + display
   - DeepAR filters (if exercised) still function
   - Admin gear + Set View Coordinates dialog (Session 4.9 feature) still work
6. **Regression: games functionality intact after subscription added to games/tv.html.** Verify:
   - Lobby renders; phone shows as joined
   - Game starts cleanly (Last Card or Trivia)
   - Game state syncs between phone and TV
   - Manager bar on phone works as expected

Skip flows requiring a second account (still gated on Part E Flows 3+4 DEFERRED).

**Files touched in Part D:** new `docs/SESSION-4.10.3-VERIFICATION.md`.

---

## Verification approach

Same pattern as `PART-E-VERIFICATION.md`: paste-and-tick checklist, Mike runs after each implementation session, results filled in place.

The regression flows (Flow 5 + Flow 6) are load-bearing — they guard against the new realtime subscription breaking something in the complex stage.html or games/tv.html pages. If regressions surface, pause before shipping Part D and redesign Part A's subscription lifecycle (e.g., lazy-subscribe, gate on specific page states).

---

## Deferred items likely to emerge

Pre-log these so we catch them during session-end ritual:

- **Extract `publishExitApp` + related realtime helpers into `shell/realtime.js` when Session 5 adds more events.** Low priority — inline duplication across 3 consumer pages (index, singer, player) is manageable today. When Session 5 adds richer events (session_ended, member_left, etc.), the repeated subscribe-send-unsubscribe boilerplate will justify extraction. File at session-end per Additional Requirement 2.
- **Heartbeat / auto-reconnect for TV realtime** — see Architecture Decision 7. File only if customer testing shows the manual-refresh recovery is a real pain point.

---

## Open questions for implementation

None — all major design questions resolved during planning review:
- Q1 (audience.html inclusion): **No — deferred pending Session 5 role-semantics work.** See DEFERRED "Audience back-to-Elsewhere navigation".
- Q2 (TV-side scope expansion): **Yes, accepted; regression checks in Part D.**

If new questions surface during Part-level execution, update this file rather than punting.

---

## Related existing architecture

- **Two-device model for TV:** unchanged. Phone remains controller. 4.10.3 adds the "controller exits" reverse path.
- **Session handoff via realtime channel:** `exit_app` is the third event on `tv_device:<device_key>` (after `session_handoff` from 4.10 Part B and `launch_app` from 4.10.2 Part C). Reuse, don't fork channels.
- **Phone is the remote; TV is the display:** unchanged. Back-to-Elsewhere strengthens this model — phone controls forward AND reverse transitions.
- **No build step, minimal abstraction:** inline `publishExitApp` in each consumer page. Consistent with existing repo conventions. Extraction deferred to Session 5+.
- **SessionStorage bridge for cross-page context:** existing pattern (`PENDING_TV_CLAIM_KEY`, `PENDING_TV_SIGNIN_KEY`). `elsewhere.active_tv.device_key` is a natural third instance of the same pattern.
