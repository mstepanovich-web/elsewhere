# Session 5 Part 2 Breakdown

**Status:** Parts 2a, 2b, 2c (all sub-parts) complete. Part 2d next, then 2e–2f pending.
**Created:** 2026-04-23
**Parent plan:** `docs/SESSION-5-PLAN.md` (commit `2b40313`)
**Canonical state model:** [docs/PHONE-AND-TV-STATE-MODEL.md](./PHONE-AND-TV-STATE-MODEL.md) (added 2026-04-24, commit `36353ca`). Parts 2c onward operate against the model defined there. Where this breakdown's older language conflicts with the state model, the state model wins.
**Spec source for 2d/2e/2f:** [docs/KARAOKE-CONTROL-MODEL.md](./KARAOKE-CONTROL-MODEL.md) (added 2026-04-26, commit `b7d4e70`). 2d, 2e, and 2f scope is canonical against this doc.

## Context for the next session

Session 5 breaks into 5 parts. Part 1 (schema + RPCs + `shell/realtime.js` extraction) is complete and applied. Part 2 is Karaoke integration — 6 sub-parts from event publishers to audience.html wiring. Part 2a shipped the realtime event publishers. Parts 2b–2f need to land before Session 5 Part 3 (Games) can start.

## Sub-part breakdown

### 2a — Event publishers in shell/realtime.js ✓ COMPLETE (`d1b4edd`)

- 5 new publishers: `publishSessionStarted`, `publishManagerChanged`, `publishParticipantRoleChanged`, `publishQueueUpdated`, `publishSessionEnded`
- Object-payload signatures (deviation from existing 3 publishers)
- Private `broadcast()` helper collapses duplication
- Full event emission matrix in file header documents which RPC fires which event
- NO consumer wiring yet — that's 2b+

### 2b — Session lifecycle wiring ✓ SHIPPED (`601d125`)

**Scope:**

- `index.html` `handleTvRemoteTileTap`: await `rpc_session_start` before `publishLaunchApp`; emit `session_started` after RPC succeeds. On RPC failure, surface error and do NOT navigate.
- `tv2.html`: subscribe to `session_ended` on the existing `tv_device:<device_key>` channel; navigate to apps grid on receive.
- `karaoke/stage.html` + `games/tv.html`: on `exit_app`, SELECT active session for this `tv_device_id`; stay on current screen if session still active, navigate as before if not. Under Session 5, phone navigating back to Elsewhere home does NOT end the session, so the TV must ignore `exit_app` when a session is still live.

**What's NOT in 2b (deliberate):**

- `karaoke/singer.html` / `games/player.html` `handleBackToElsewhere` get NO wiring changes. The manager-only Back-to-Elsewhere button becomes navigate-only: no `rpc_session_leave` call, no SELECT follow-up, no `publishSessionEnded`, no `publishExitApp`. The phone navigates away; the TV sees the implicit `exit_app` fire (from page unload) and ignores it because the session is still active. Session stays alive with the manager still as manager.
- Session termination paths are unchanged from Part 1: explicit End Session button (`rpc_session_end`), inactivity orphan timeout (`rpc_session_reclaim_manager`), admin force-reclaim (`rpc_session_admin_reclaim`), and cross-app switch confirmation (Part 2c).

**Locked decisions:**

- Back-to-Elsewhere = navigate only. Supersedes earlier breakdown language about `rpc_session_leave` + SELECT follow-up on Back tap. That design was rejected in favor of "navigate but stay in session" — matches the plan doc's "Back to Elsewhere behavior" cross-cutting decision.
- Back-to-Elsewhere visibility is universal on participant pages — all audience users see the button (per Karaoke Control Model § 4.4). Destination differs by user type: HHU → post-login home; NHHU → placeholder Elsewhere home. (2b shipped with manager-only visibility; 2c.3.2 expanded to household members; control model expanded to all audience users.)
- "Potential participant" is a derived UI state from `(control_role, participation_role, has_tv_device, proximity)`, NOT a new schema value.
- Sessions always created on app-tile tap in Session 5; "no session" fallback in stage/tv.html is for dev/direct-nav only.
- Object-payload signatures for Session 5 publishers (Part 2a convention).
- Await-before-navigate (commit `7b81f70`).

**Entry criteria:** 2a complete ✓
**Exit criteria:** DB session rows created at app-tile tap; TV stays on stage when manager navigates back to Elsewhere home; TV navigates to apps grid on `session_ended` (fired by End Session or cross-app switch in 2c). Reclaim paths (`rpc_session_reclaim_manager`, `rpc_session_admin_reclaim`) fire `manager_changed`, not `session_ended` — the session continues through reclaim.
**Files touched:** `index.html`, `tv2.html`, `karaoke/stage.html`, `games/tv.html`. (No longer touches `karaoke/singer.html` or `games/player.html`.)
**Rough commit count:** 1

### 2c — Apps grid session-awareness + post-login home unification + proximity banner ✓ SHIPPED

**Scope:**

Per [docs/PHONE-AND-TV-STATE-MODEL.md](./PHONE-AND-TV-STATE-MODEL.md), the post-login home screen on the phone unifies into a single conditional-rendering element with a proximity banner and active-session relabeling. Part 2c splits into three sub-parts to keep each commit reviewable:

**2c.1 — User preferences storage:** ✓ SHIPPED (commit `daa8718`)
- New DB table `user_preferences` (or equivalent column on `auth.users` / `household_members`) for per-user-per-TV preferences
- Initial preference: `proximity_prompt_dismissed` (boolean, default false) — captures the "Don't show me again" choice
- Designed to accommodate future preferences without schema churn (e.g., per-app notification opt-outs, UI variant choices)
- RLS: users can only read/write their own preferences
- Migration in `db/012` (or next available number)
- Helper functions in `shell/` (e.g., `getUserPreference(tv_device_id, key)`, `setUserPreference(tv_device_id, key, value)`)

**2c.2 — Post-login home unification + proximity banner:** ✓ SHIPPED (commit `0a3a9ea`)
- Merge `screen-home` and `screen-tv-remote` into a single DOM section
- Remove the back button from the unified post-login home (it was a symptom of the split design)
- Implement Mode A / Mode B / Mode C rendering per the state model's tile state matrix
- Add the inline proximity banner per the state model's "Banner UI" subsection (three actions: Yes / No / Don't show me again)
- Banner firing rule per the state model's 4-condition AND (household member + post-login home landing + not previously dismissed for this TV + not yet answered this session)
- Default mode = A while banner is visible (default-yes per state model)
- "No" answer triggers confirm dialog before applying Mode B
- "Don't show me again" calls 2c.1's preference helper; banner suppressed on subsequent visits
- New "Proximity Settings" menu item drilling into a settings page (toggle proximity, re-enable banner)
- For n>1: auto-pick most-recent-last_seen_at TV (stub; full picker UI per DEFERRED "Multi-TV picker and selection persistence")
- Update `handleTvRemoteTileTap` to read TV context from the unified home rather than `screen-tv-remote.dataset.tvDeviceId` (small adjustment to Part 2b's wiring)
- "Your TVs" menu item becomes informational/picker rather than a navigation drill-in
- Tap behavior dispatches based on (user role, proximity, active sessions)

**Delivered in 2c.2 (stats: +728 / −86 on index.html, 7 sections applied via section-by-section review):**
- DOM unification: `screen-home` absorbed `screen-tv-remote`; back button removed; TV header + proximity banner + 3-mode tile rendering
- Banner 4-condition firing rule + three action handlers (Yes / No-with-confirm / Don't-ask-again)
- Proximity Settings drill-in via badge menu; visible only in Mode A/B
- R4 23505 catch: same-app rejoin via best-effort `rpc_session_join('audience')`; cross-app surfaced with user-facing copy ("A {app} session is already active…")
- `enterTvRemoteScreen` → `enterHomeForTv` renamed; all 4 callers updated (post-claim, enterYourTvsFlow, openYourTvsFromMenu, renderTvTile)
- `clearHomeTvBinding` helper wired into `renderAuthState`'s signed-out branch
- `.app-tile*` CSS block deleted; new `.proximity-banner*`, `.seg-btn*`, `.tile.greyed`, `.home-tv-switch`, `.proximity-settings-*` styles added

**Decisions baked in:**
- DECISION-A: `fetchProximityDismissed` — first attempt per (user, TV) per session; no retry. If the first fetch errors, banner stays visible until manual dismiss.
- DECISION-B: Mode B greyed-karaoke tap = silent no-op. Banner and Proximity Settings provide recovery; no inline tooltip or alert.
- Confirm dialog for "No" uses native `confirm()` with browser-default [OK]/[Cancel]. Locked copy specified [Continue]/[Cancel] — mismatch acknowledged; custom modal deferred as 2c.x polish (tracked inline).

**On-device watch items (non-blocking; fix in 2c.x if real friction):**
- WATCH-1: Banner background visual weight (gold-ghost + gold-faint border) against tile grid. If competes for the eye, drop to transparent + border-only.
- WATCH-2: Tertiary "Don't ask again" styling (text-faint + underline) is a new pattern with no codebase precedent. If it reads as out-of-place, drop the underline.
- WATCH-3: Three vertical stacked buttons may read as parallel choices rather than primary/alternate/escape-hatch hierarchy. If off, restructure to Yes/No row + tertiary below.

**Known acceptable carryover (not a 2c.x item):**
- `.tv-remote-header`, `.tv-remote-household` CSS class names are reused on the unified home. Names are slightly anachronistic post-unification but pure aesthetic — no functional payoff to renaming. Leave as-is.

**2c.3 — Active session relabeling + rejoin:** ✓ SHIPPED

Sub-split into 2c.3.1 and 2c.3.2 per pre-implementation audit.

**2c.3.1 — Phone home active-session rendering + tap dispatch + realtime subscription:** ✓ SHIPPED (commit `e4a348e`)
- Query active sessions on home render: `SELECT id, app, room_code, manager_user_id FROM sessions WHERE tv_device_id = <selected TV> AND ended_at IS NULL`
- Relabel matching app tiles with "Active Session" primary label + app name as sub (DECISION-1; state model uses "Active Session" as umbrella)
- Tap behavior on active-session tile: `rpc_session_join('audience')` with 23505 "already participant" swallow + 02000 "session ended" race catch, then navigate. Manager/existing-participant role preserved (23505 path).
- Cross-app switch: confirm dialog → `rpc_session_end` + `publishSessionEnded` → delegate to `handleTvRemoteTileTap` for start. Non-manager pre-check surfaces locked alert without confirm.
- Subscribe to `session_started` / `session_ended` on `tv_device:<device_key>`; both trigger `refreshActiveSession` (re-query per DECISION-6)

**Delivered in 2c.3.1 (stats: +455 / −33 on index.html, 6 sections applied via section-by-section review):**
- Active-session module state + `getActiveSession` accessor + `refreshActiveSession` query
- `renderHomeTiles` extended with `TILE_DEFAULT_COPY` + `applyHomeTileState` helper (Mode B / active-session precedence per FLAG-3)
- `handleHomeTileTap` dispatch extended for active-session: same-app rejoin + cross-app switch
- `handleSameAppRejoin` (`rpc_session_join` + 23505/02000 handling, FLAG-A games `&mgr=1` dropped)
- `handleCrossAppSwitch` (manager pre-check + native confirm + `rpc_session_end` + delegate to `handleTvRemoteTileTap`)
- Realtime subscription on home: `tv_device:<key>` channel, idempotent restart, silent failure
- 2c.2 R4 path FLAG-A fix: dropped `&mgr=1` from games rejoin URL (consistency with primary path)
- CSS: `.tile.active-session` (gold-ghost + gold-faint) + `.tile.greyed.active-session` defensive precedence rule

**Decisions baked in:**
- DECISION-1: tile copy = "Active Session" primary label + app name as sub. Single umbrella label; dispatch handles role-aware behavior. Role-specific copy deferred to 2c.x if friction.
- DECISION-2: cross-app confirm = native `confirm()` with "End current [App] session to start [App]?" [OK]/[Cancel]. Consistent with 2c.2's "No" confirm.
- DECISION-3: non-manager cross-app = locked alert "Only the current manager can switch apps. Ask them to end the [App] session first." Pre-check avoids confirm-then-alert UX.
- DECISION-6: session_ended payload re-query (option i). Stable payload contract; handlers call `refreshActiveSession` instead of parsing event.
- FLAG-A: games rejoin URL drops `&mgr=1` (both primary path and R4 fallback). Broader games-manager-detection remains under DEFERRED "Games deep-link auto-manager bug".
- FLAG-3: `.active-session` takes precedence over `.greyed` in `applyHomeTileState` (JS-driven); `.tile.greyed.active-session` CSS rule provides defensive backup.

**On-device watch items (non-blocking; fix in 2c.x if real friction):**
- Active-session state flash on `enterHomeForTv` (~200-500ms while `refreshActiveSession` resolves). R4 catches race-clicks during the flash. If visually disruptive, add sessionStorage hydration of last-known active-session state in 2c.x.
- Cross-app switch native `confirm()` shows [OK]/[Cancel] vs. locked [Continue]/[Cancel] — same papercut as 2c.2's "No" confirm. Custom modal still deferred to 2c.x.

**2c.3.2 — Back-to-Elsewhere visibility across play-pages:** ✓ SHIPPED (commit `5617689`)
- Implement `isLikelyHouseholdMember()` heuristic: authenticated + `sessionStorage.elsewhere.active_tv.device_key` present (DECISION-4 from 2c.3 planning audit). Helper name flags it as a heuristic, not RPC-verified, so future swap stays surgical.
- `karaoke/singer.html`: gate the existing `.back-to-elsewhere` button visibility on `isLikelyHouseholdMember()`.
- `games/player.html`: gate the existing `.home-link` button visibility on `isLikelyHouseholdMember()`.
- `karaoke/audience.html`: add new Back-to-Elsewhere button (markup + style + `handleBackToElsewhere` handler), styled to match singer.html's `.back-to-elsewhere` pill style (DECISION-5 from 2c.3 planning audit). Visibility gated on `isLikelyHouseholdMember()`. Closes DEFERRED "Audience back-to-Elsewhere navigation".
- State model basis: household members (Mode A/B) see the button; non-household (Mode C, deep-link only) do not.

**Delivered in 2c.3.2 (stats: +155 / −6 across 5 files, 4 sections applied via section-by-section review):**
- `shell/auth.js`: `window.elsewhere.isLikelyHouseholdMember()` heuristic (auth + sessionStorage `active_tv.device_key` check)
- `karaoke/singer.html`: existing `.back-to-elsewhere` button gated on `isLikelyHouseholdMember()`; two-tier wire pattern (onAuthChange + elsewhere:sb-ready fallback)
- `games/player.html`: existing `.home-link` gated on same helper; independent subscriber to onAuthChange (parallel to existing applyAuthState wiring)
- `karaoke/audience.html`: net-new shell module imports (auth.js + realtime.js) + `.back-to-elsewhere` button (markup + CSS duplicated from singer.html + `handleBackToElsewhere` handler + visibility wiring)
- `docs/DEFERRED.md`: "Audience back-to-Elsewhere navigation" marked Completed in Session 5 Part 2c.3.2
- Cross-file function naming: `applyBackToElsewhereVisibility` + `wireBackToElsewhereVisibility` reused identically across all three pages (grep affordance for future maintenance).

**Decisions baked in:**
- DECISION-4: `isLikelyHouseholdMember` = simple heuristic (authenticated + `sessionStorage.elsewhere.active_tv.device_key` present). "Likely" naming flags the heuristic; future RPC-verified swap can replace method body without changing call sites.
- DECISION-5: audience.html Back button styled to match singer.html's `.back-to-elsewhere` pill (top-right, `position:fixed`). Karaoke peer consistency.
- Helper placement: `window.elsewhere` namespace in `shell/auth.js` (Option C from Section 1 audit). Single update site for future RPC-verified swap.
- Visibility init pattern: start hidden in HTML (`style="display:none;"`), reveal in JS via `onAuthChange`. Avoids flash for non-household deep-link users.

**On-device watch items (non-blocking; fix in 2c.x if real friction):**
- audience.html Back-to-Elsewhere pill may visually collide with topbar right-side content (both top-right; z-index resolved but vertical overlap possible). Reposition or integrate into topbar if conflict surfaces.

**Files touched:** `shell/auth.js`, `karaoke/singer.html`, `games/player.html`, `karaoke/audience.html`, `docs/DEFERRED.md`.
**Commit count:** 1 (code) + 1 (this docs update).

**Locked decisions:**
- Single post-login home screen — no separate `screen-tv-remote`
- All tiles same size; mode-conditional rendering varies tile state, not layout
- Proximity at TV-connect, not per app launch
- Tap behavior dispatches by user context at runtime; same UI for manager-rejoin and not-home-audience-join
- Banner is inline (not modal); default mode is A while banner visible
- Back-to-Elsewhere visibility is universal (all audience users see the button); destination differs by user type per Karaoke Control Model § 4.4 (revised from 2c.3.2's household-member rule, which itself revised from 2b's manager-only)

**Entry criteria:** 2b complete ✓ (commit `601d125`)
**Exit criteria:** Single post-login home renders correctly across Modes A/B/C; proximity banner fires per the firing rule; "Don't show me again" persists; Proximity Settings menu item works; active sessions relabel matching tiles; rejoin works for all three contexts; cross-app switch prompts and works (and fails safely for non-managers); live updates via realtime subscriptions; Back-to-Elsewhere visible for household members on participant pages
**Files touched:** `index.html`, `karaoke/singer.html`, `karaoke/audience.html`, `games/player.html`, new migration `db/012`, possibly `shell/preferences.js` (new helper module)
**Rough commit count:** 3 (2c.1 + 2c.2 + 2c.3 split is the expected case)

### 2d.0 — Karaoke session helper RPCs (db/013) [PENDING — prerequisite for 2d.1]

**Scope:** New SECURITY DEFINER RPCs that unblock 2d.1 against existing RLS gates. Single migration commit + SQL editor verification.

- `rpc_karaoke_song_ended(p_session_id uuid)` — atomic dual transition (current active singer → audience, queue head → active). Idempotent: handles missing-active or missing-queue-head gracefully. Returns updated session row.
- `rpc_session_get_participants(p_session_id uuid)` — returns participant rows joined with `profiles.full_name` as `display_name`. Bypasses owner-only profiles RLS via SECURITY DEFINER.

**Auth gate (both RPCs):** `is_session_participant(session_id) OR is_tv_household_member(tv_device_id)`. Broad enough to include stage.html's TV-claimer auth context.

**Why these RPCs are needed:**

- `rpc_session_update_participant` (db/011) requires the caller to be both an active participant AND have manager/host control_role to mutate cross-user. Stage.html's TV-claimer auth context generally satisfies neither condition — auth gate too narrow for the song-end RPC trigger.
- `profiles` RLS (db/001) is owner-only; nested-select for `display_name` returns NULL for other users — blocks queue panel rendering.

Both addressed by the new SECURITY DEFINER wrappers with broader auth.

**Locked decisions:**
- RPC publishing is caller-side per existing pattern (RPCs do NOT publish realtime events; stage.html publishes after RPC success per `docs/SESSION-5-PART-2D-AUDIT.md` DECISION-AUDIT-7 B5)
- Idempotency in `rpc_karaoke_song_ended` protects multi-tab and reload race scenarios

**Entry criteria:** None (Part 1 schema already in place)
**Exit criteria:** Migration applied to Supabase; both RPCs callable from SQL editor with correct auth-gate enforcement; `rpc_karaoke_song_ended` correctly handles all four edge cases (no active, no queue, both, both empty)
**Files touched:** `db/013_karaoke_session_helpers.sql` (new)
**Rough commit count:** 1
**Spec source:** `docs/SESSION-5-PART-2D-AUDIT.md` DECISION-AUDIT-6 + DECISION-AUDIT-13

### 2d — karaoke/stage.html session integration [PENDING — split into 2d.0 + 2d.1; 2d.2 collapsed]

Per `docs/SESSION-5-PART-2D-AUDIT.md` DECISION-AUDIT-2, 2d.2 collapsed into 2d.1. Manager override UI moved off stage.html per Karaoke Control Model § 4.2; remaining 2d.2 scope (pre_selections loading on promotion, session_ended navigation) absorbed into 2d.1's event-driven scope.

2d.0 (above) ships first as a prerequisite migration. Then 2d.1.

**2d.1 — Session-aware stage (~6-8 sections, ~3-4 hours) [PENDING — entry criteria: 2d.0 complete]:**

"Read-only" in 2d.1 means **no user-input mutators** (no buttons that change session state). Event-driven mutations responding to internal events (YouTube video ended) and received realtime events ARE in scope.

Scope:
- Session load on stage.html mount (query by tv_device_id, URL fallback)
- Graceful fallback to pre-Session-5 solo mode if no session (silent + log; dev/legacy only)
- Queue panel (new bottom-right button + slide-out matching Comments pattern; content per Karaoke Control Model § 4.2)
- Realtime subscription to `participant_role_changed`, `queue_updated`, `session_ended` (independent channel instance, mirrors `index.html`'s 2c.3.1 pattern)
- Active-singer highlight + "Up Next" card during inter-song transitions
- Idle-state behavior: 60s social window → 360° venue tour with "Select and start a song" overlay
- Pre_selections loading on queue→active transition (new active singer's selections become initial stage state)
- Song-end RPC trigger via `rpc_karaoke_song_ended` from db/013, with `_currentSongInstanceId` double-fire guard
- `session_ended` graceful teardown: `doEnd()` → `stopStageRealtimeSub()` → navigate to tv2.html
- Migration-window grace: Agora `session-ended` message to singer.html before teardown (the only 2d.1 change to singer.html; ~10 LOC)
- Room code override from `sessions.room_code` when session loaded; URL fallback in solo mode

**Locked decisions:**
- Manager override UI (venue/costume mid-song, end song) lives on phone, NOT stage.html (per Karaoke Control Model § 4.2)
- Stage.html is read-only for **user inputs**; event-driven mutations (RPC calls in response to internal events) ARE in scope
- "Up Next" card auto-shows on song-end (transient surface, distinct from user-toggled queue panel)
- Queue panel stays user-driven (no auto-show, no auto-hide)
- Idle states coexist: existing `idle-panel` (QR + room code) for no-session; new 60s + 360° tour for in-session no-active-singer
- Way 1 (legacy QR + room code path) preserved verbatim in solo mode; removal deferred post-Session-5

**Entry criteria:** 2d.0 complete (db/013 applied)
**Exit criteria:** Stage renders session state and queue per spec; song-end triggers role transitions via RPC; pre_selections load on promotion; session_ended causes graceful teardown + navigate; idle state behaviors fire correctly
**Files touched:** `karaoke/stage.html` (primary); `karaoke/singer.html` (~10 LOC for migration-window grace)
**Rough commit count:** 6-8 sections, each as separate commit
**Spec source:** `docs/SESSION-5-PART-2D-AUDIT.md` (full implementation contract); `docs/KARAOKE-CONTROL-MODEL.md` § 4.2 + § 5.1

### 2e — karaoke/singer.html role-aware [PENDING — re-scoped per Karaoke Control Model § 5.2]

The largest remaining sub-part. Singer.html becomes role-aware per Karaoke Control Model § 4.1: tile rendering, controls visibility, and authority all branch on the user's session role (Active Singer / Available Singer queued / Available Singer not queued / Session Manager + role overlay).

**Scope:**
- Role detection on mount: query session state, determine current role across both axes (control + participation)
- Conditional rendering of screen-home tiles based on role and queue membership state
- "Take Stage" prompt when promoted to Active Singer (tap-to-confirm, removable, no countdown — per § 2)
- Push notification ("You are up — click here to take the stage") when phone backgrounded during promotion
- Available Singer queue position display
- "Add to Queue" / "Update My Song" UX based on queue membership
- Queue editing: Inactive Singer edits own entry (song / venue / costume / comments-toggle / remove)
- Phone-side venue preview for non-active singers (currently TV-only)
- Phone-side costume preview images for non-active singers
- Session Manager queue management UI (reorder, remove, force-promote, skip current/next, take over)
- Remove redundant "Leave" button from screen-home (Back-to-Elsewhere replaces it)
- Restart, Pause, Stop, End-Song semantics per § 2 (Stop ≠ End Turn)
- Manager override mechanism implementation — choose Option A/B/C in pre-implementation audit (see DEFERRED "Manager Override mechanism design")

**Deferred from 2e (per Q-2B):**
- Manager picks song/venue/costume/mic on behalf of Active Singer (helper-for-elderly-relative scenario) — captured in DEFERRED.

**Locked decisions:**
- Audience-role users on singer.html redirect to audience.html (not inline read-only state)
- Pre-selections UI (song + venue + costume) all ship in Part 2 (existing UIs adapt; not net-new)
- Active Singer is state-derived from `participation_role='active'` per § 2
- Stop ≠ End Turn (Stop pauses; End Turn transitions to audience)

**Entry criteria:** 2b + 2d complete (singer needs session-aware stage)
**Exit criteria:** All four roles render correctly on screen-home; "Take Stage" prompt fires on promotion; push notification works when backgrounded; manager queue management UI works; mid-song manager override works (transport mechanism per audit decision)
**Files touched:** `karaoke/singer.html` (primary); possibly new push-notification helper module
**Rough commit count:** 3-5 (large sub-part, multiple section commits expected)
**Spec source:** docs/KARAOKE-CONTROL-MODEL.md § 4.1 (singer.html UI surfaces) + § 5.2 (work item list)

### 2f — karaoke/audience.html session integration [PENDING — significantly reduced per Karaoke Control Model § 5.3]

**Scope reduced under audience.html freeze decision** (Karaoke Control Model § 4.3 + § 5.5). Audience.html receives no new features in Session 5; new audience-experience features build into the unified app post-Session-5. Original 2f scope (read-only spectator with `rpc_session_join('audience')`, queue display) was largely landed in 2c.3.2's audience.html Back-to-Elsewhere wiring. What remains:

**Scope:**
- Verify audience.html still functions correctly with new session lifecycle (regression test: arrival via deep link, session_ended navigation, realtime resilience)
- Update Back-to-Elsewhere visibility rule from "HHU only" to "all audience users" (small change to `isLikelyHouseholdMember()` gating in audience.html — removes the household-membership filter on the existing pill, lands the universal-visibility rule from Karaoke Control Model § 4.4)
- Bug fixes only beyond this

2f may not need a dedicated implementation pass. Could land as part of 2e's verification work or as a small standalone commit.

**Deferred from 2f (per audience.html freeze):**
- Audience read-only queue display (waits for unified-app migration — DEFERRED)
- Audience venue/costume browsing for marketing (waits for unified-app migration — DEFERRED)
- Audience-to-NHHU conversion path full funnel (Phase 1 placeholder may ship; full conversion post-Session-5 — DEFERRED)

**Locked decisions:**
- Audience.html is frozen for Session 5 (bug fixes only; no new features)
- Back-to-Elsewhere now visible for all audience users (decoupled visibility from destination — household lands on home, NHHU lands on placeholder)

**Entry criteria:** 2b complete (independent of 2d/2e)
**Exit criteria:** audience.html regression-clean; Back-to-Elsewhere visibility rule update lands without breaking the existing pill behavior
**Files touched:** `karaoke/audience.html`
**Rough commit count:** 0-1 (may collapse into 2e verification)
**Spec source:** docs/KARAOKE-CONTROL-MODEL.md § 4.3 (audience.html freeze) + § 4.4 (Back-to-Elsewhere visibility) + § 5.3 (sub-part scope)

## Dependency graph

```
2a ✓
  └─> 2b (lifecycle plumbing)
        ├─> 2c (apps grid relabel) — independent
        ├─> 2d (stage.html) — independent
        │     └─> 2e (singer.html) — depends on 2d
        └─> 2f (audience.html) — independent
```

Sequential order: 2a → 2b → 2c → 2d → 2e → 2f.

## Cross-cutting design decisions (apply to all sub-parts)

### Event emission contract

Documented in `shell/realtime.js` header (Part 2a). Quick reference:

- `rpc_session_start` → `session_started`
- `rpc_session_end` → `session_ended` (reason: `'user_ended'`)
- `rpc_session_leave` manager-alone/no-promotee → `session_ended` (reason: `'manager_left'`)
- `rpc_session_leave` auto-promote → `manager_changed` (`'auto_promote'`) + `participant_role_changed` for leaver
- `rpc_session_leave` non-manager → `participant_role_changed`
- `rpc_session_reclaim_manager` → `manager_changed` (`'reclaim'`)
- `rpc_session_admin_reclaim` → `manager_changed` (`'admin'`)
- `rpc_session_join` → `participant_role_changed`
- `rpc_session_update_participant` (role change) → `participant_role_changed`
- `rpc_session_update_participant` (pre_selections only) → `queue_updated`
- `rpc_session_update_queue_position` → `queue_updated`
- `rpc_session_promote_self_from_queue` → `participant_role_changed`

**`queue_updated` fires only for pure queue metadata changes** (reorder, pre-selection). Role transitions fire `participant_role_changed`. Consumers interested in queue state subscribe to BOTH.

### Session always created on app-tile tap

Under Session 5, tapping any app tile creates a session via `rpc_session_start`. "No active session" should not happen in production. `stage.html` / `singer.html` / `audience.html` fallback to pre-Session-5 behavior is for dev/direct-nav only; not a real production state.

### Back to Elsewhere behavior

Per Session 5 design: Back to Elsewhere = navigate but stay in session. The phone navigates to apps grid; the TV stays on the current session. The session ending is orthogonal — see "Non-manager exit semantics" and the termination paths listed below.

No user-facing "Leave session" button. Exits happen via:
- Explicit end session (manager only)
- Going inactive (10-min threshold) → orphan reclaim by another household member, or admin force-reclaim

### Back-to-Elsewhere button visibility

All audience users see the Back-to-Elsewhere button on participant pages. Destination differs by user type — household members land on the post-login home; NHHU lands on a placeholder Elsewhere home (audience-to-NHHU conversion path). Canonical treatment lives in `docs/PHONE-AND-TV-STATE-MODEL.md` § "Back-to-Elsewhere navigation" and `docs/KARAOKE-CONTROL-MODEL.md` § 4.4.

### Non-manager exit semantics

No non-manager participant calls `rpc_session_leave` via a user-facing action in Session 5 Part 2. Exit mechanics by role:

- **Active singer finishes song:** role transition (`active` → `audience` or `queued`) via `rpc_session_update_participant`. Not a leave.
- **Queued singer drops out:** role transition (`queued` → `audience`) via `rpc_session_update_participant` (Part 2e). Not a leave.
- **Audience closes app:** no RPC. Implicit; row persists. Ghost audience accepted as Phase 1 trade-off (Part 2f).
- **Host / participant wanting to exit the app entirely:** no UI for this in Session 5. Would require manager to end session or admin reclaim.

`rpc_session_leave` itself is retained in the DB for future use (background cleanup, heartbeat-based stale-participant sweep) but is not called from any Session 5 Part 2 UI.

### Manager/host authority semantics

- Manager: one per session; transferable only via auto-promote or reclaim (no explicit transfer RPC)
- Host: assigned by manager; session-scoped; manager-equivalent powers except cannot assign other hosts or end session outright
- Both can always override the active participant (change venue/costume mid-song, end song, kick active participant)

### Error codes established

Continuing db/006 conventions plus Session 5 additions:
- `42501`: auth/authorization failures
- `23505`: unique constraint violations
- `02000`: not found / state invalid
- `55000`: prerequisite state not met (capacity, admission_mode, orphan threshold) — first use in Part 1b.2
- `22023`: invalid parameter value — first use in Part 1b.3

## What NOT to relitigate tomorrow

These decisions are locked. Don't revisit unless a concrete problem surfaces in implementation:

- No `rpc_session_transfer_manager` (auto-promote + admin-reclaim cover real needs)
- Pre-selections via generic JSONB column, not per-field columns
- Proximity as per-app flag (`ask_proximity`), not per-role
- Proximity "No" → confirm dialog → audience role
- 10-min orphan threshold flat across apps (not per-app tunable in Phase 1)
- Object-payload signatures for Session 5 publishers
- Back-to-Elsewhere is navigate-only, no `rpc_session_leave` call (supersedes earlier "SELECT follow-up on Back tap" design)
- Back-to-Elsewhere visibility is universal (all audience users see the button); destination differs by user type — settled per Karaoke Control Model § 4.4
- "Potential participant" is derived UI state, not a schema value
- Non-manager exits use role transitions or implicit accumulation, never `rpc_session_leave` in Session 5 Part 2

## Applied migrations

All Part 1 migrations in `db/` are applied in Supabase:
- `db/008_sessions_and_participants.sql`
- `db/009_session_lifecycle_rpcs.sql`
- `db/010_manager_mechanics_rpcs.sql`
- `db/011_role_and_queue_mutation_rpcs.sql`
- `db/012_user_preferences.sql` (Part 2c.1)

**Pending:** `db/013_karaoke_session_helpers.sql` ships in 2d.0 before 2d.1 implementation begins.
