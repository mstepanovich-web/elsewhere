# Session 5 Part 2e Pre-Implementation Audit

**Created:** 2026-04-26
**Purpose:** Pre-implementation audit for Session 5 Part 2e (karaoke/singer.html role-aware UI). Surfaces architectural blockers, framings, and decisions before implementation begins.
**Pattern:** Mirrors `docs/SESSION-5-PART-2D-AUDIT.md` — durable artifact, 5 investigation areas, decisions explicitly framed.
**Spec sources:** `docs/KARAOKE-CONTROL-MODEL.md` § 4.1 + § 5.2, `docs/SESSION-5-PART-2-BREAKDOWN.md` § 2e, `docs/SESSION-5-PART-2D-AUDIT.md` (predecessor).
**Investigation HEAD:** `3961418` (2d.1 complete + 1.9 fix).

---

## TL;DR

2e ships role-aware UI on `karaoke/singer.html` so each phone reflects its session role (Active Singer / Available Singer queued / Available Singer not queued / Session Manager). Touches singer.html primarily; possibly singer.html for Session Manager queue management (Decision 5). 1862 lines today, expecting +500-800 lines total across the phase split.

**Three hard blockers must be resolved at session start:**
1. **Singer.html doesn't call `rpc_session_join`** — in legacy Way 1 (direct URL), no `session_participants` row exists. Role-aware UI has nothing to read. Resolution: defensive fallback to legacy behavior (mirrors 2d.1's solo mode pattern).
2. **Push notification scope** — iOS native push via Capacitor `@capacitor/push-notifications` + APNs is viable; singer.html IS bundled in iOS app shell (`~/Projects/elsewhere-app/www/karaoke/`). Decision: ship push as 2e.0 prerequisite phase (~6-8 hr, recommended), OR defer + foreground fallbacks for all platforms.
3. **Manager Override transport mechanism** — Karaoke Control Model § 2 lists Options A/B/C without choosing one. Without this choice, manager queue management can't be wired end-to-end. Must lock at session start.

**Recommended phase split:** 2e.1 (read-only role-aware UI for non-managers, ~3-4 hr) → 2e.2 (write actions for self, ~2-3 hr) → 2e.3 (Session Manager queue management UI + Override mechanism, ~3-4 hr). Push notifications deferred to a later phase regardless of decision.

---

## Area 1 — Singer.html screen state machine

### `showScreen()` definition (lines 581-594)

```js
function showScreen(id){
  document.querySelectorAll('.screen').forEach(s=>s.classList.remove('active'));
  document.getElementById(id).classList.add('active');
  if(id==='screen-mic') populateMicList();
  if(id==='screen-search'){
    if(!lastSearchResults.length){
      document.getElementById('srch-recent-section').style.display='block';
      document.getElementById('srch-result-list').style.display='none';
      renderRecent();
    }
    setTimeout(()=>{ const inp=document.getElementById('srch-in'); if(inp&&!inp.value) inp.focus(); },100);
  }
}
```

No state machine guards beyond per-screen init hooks for `screen-mic` (populate device list) and `screen-search` (focus input). Any screen transition is allowed.

### Screens (DOM ID, line, role)

| Screen ID | Line | Trigger | Exit | Role-dependent today |
|---|---|---|---|---|
| `screen-join` | 194 | Initial state (URL has no `?code=`) OR initial state with code that hasn't auto-joined yet | `doJoin()` success → `screen-home` | No |
| `screen-home` | 212 | After Agora `join` succeeds, after song ends, after costume edit, manual `← Home` | Tap action card (Search / Costume / Mic / etc.) | No |
| `screen-search` | 318 | Tap Search action card | Tap a result → `screen-confirm`; back → `screen-home` | No |
| `screen-voice` | 352 | Voice search start | Result handler → `screen-search` | No |
| `screen-confirm` | 363 | Search-result selection | Start → `screen-countdown`; back → `screen-search` | No |
| `screen-countdown` | 383 | Confirm song | Auto-advance → `screen-performing` | No |
| `screen-mic` | 392 | Tap mic-config gear | Back → `screen-home` | No |
| `screen-performing` | 443 | Countdown complete | `song-ended` / `session-ended` Agora msg → `screen-home` | No |
| `screen-costume` | 512 | Tap Costume action card | Selection → `screen-home` | No |
| `screen-postsong` | 530 | (defined but unused in code today; placeholder div, `display:none`) | — | No |

### Initial screen on load

Driven by URL parser at lines 597-607 (auto-join IIFE):
```js
const c = (p.get('code')||'').toUpperCase().replace(/[^A-Z0-9]/g,'');
if(c.length>=4){
  document.getElementById('join-in').value=c;
  // ... 600ms later, doJoin()
}
else document.getElementById('join-in').focus();
```

If URL has `?code=ABCD` (≥4 chars), auto-fills join input + auto-calls `doJoin()` after 600ms. Otherwise focuses the manual entry field. Default visible screen is `screen-join` (HTML `class="screen active"` on line 194).

### Implications for 2e

- **No screens are role-aware today.** All ten screens render identically regardless of `participation_role`. 2e adds conditional UI within `screen-home` (the action hub) and adds new transient surfaces (Take Stage prompt).
- **Screen transitions are unguarded** — any caller can `showScreen()` to anywhere. 2e role-aware UI lives within screens, not as transition guards.
- **`doJoin()` (lines 610-648) joins via Agora room code only.** No DB session lookup, no `rpc_session_join`, no participant row creation. This is **HARD BLOCKER #1** below.

---

## Area 2 — Existing Agora message handlers

### `handleStageMsg(msg)` (lines 688-692)

```js
function handleStageMsg(msg){
  if(msg.type==='song-ended'){ muteMic(); showScreen('screen-home'); }
  if(msg.type==='session-ended'){ muteMic(); showScreen('screen-home'); }
  if(msg.type==='progress'){ document.getElementById('perf-prog-fill').style.width=(msg.pct||0)+'%'; }
}
```

Three handled types only: `song-ended` (since pre-Session-5), `session-ended` (added in 2d.1 section 1.8 today), `progress` (lyric/song progress bar update).

Reached via `agoraClient.on('stream-message', ...)` at line 621 — single Agora listener for all data-channel messages.

### Stage.html sender inventory

`sendMsg()` callsites in `karaoke/stage.html` (verified at HEAD `3961418`):

| msg.type | Stage line | Singer handles? | Audience handles? | Notes |
|---|---|---|---|---|
| `cheer-bounce` | 3358, 3359 | No | (yes) | Singer ignores; audience UI feedback |
| `restart-song` | 3452 | No | (yes) | Audience-only animation cue |
| `pause` | 3459, 3897 | No | (yes) | Audience YT pause |
| `resume` | 3471 | No | (yes) | Audience YT resume |
| `video-chat-available` | 3495 | No | (yes) | Audience-only |
| `video-chat-ended` | 3500 | No | (yes) | Audience-only |
| `song-announce` | 3760 | No | (yes) | Audience-only banner |
| `play-start` | 3778, 3885 | No | (yes) | Audience-only YT load |
| `countdown-start` | 3871 | No | (yes) | Audience-only countdown UI |
| `lyric` | 3918 | No | (yes) | Audience-only lyric overlay |
| `progress` | 3921 | **Yes** | (yes) | Both handle — singer for own perf bar, audience for sync |
| `end` | 3939 | No | (yes) | Audience-only YT stop + applause |
| `song-ended` | 3940 | **Yes** | No | Singer-only — return to home + mute |
| `tv-search`, `tv-search-clear` | 4257, 4268 | No | (yes) | Audience-only search overlay |
| `tv-song-card`, `tv-song-card-clear` | 4280, 4285 | No | (yes) | Audience-only |
| `session-ended` | 5693 | **Yes** | No | New in 2d.1 — singer-only graceful teardown |

**Routing pattern:** stage.html broadcasts to all Agora subscribers; receiver-side filtering by `msg.type`. Singer cares about three; audience cares about most others. **No bug** — singer's silence on the rest is deliberate.

### What 2e likely adds

- A new sender type from singer (Session Manager) for queue management (e.g., `mgr-promote-next`, `mgr-skip-current`) — see Manager Override mechanism in Area 5.
- Possibly a `take-stage-prompt` from stage.html, OR singer self-derives the prompt from realtime `participant_role_changed` events. Decision 1 below.

### Singer's other event listeners

Beyond `handleStageMsg`, singer.html has:
- `agoraClient.on('user-joined', ...)` at line 628 — adds audience member tile
- `agoraClient.on('user-left', ...)` at line 629 — removes audience member tile
- `setInterval` at line 630 — updates audience watch count

**No Supabase realtime subscriptions** on singer.html today. Confirmed by grep (only `Capacitor` and `applyAuthState` references found via `subscribe`). 2e adds the first.

---

## Area 3 — Singer auth + session context

### URL parsing (lines 597-607)

```js
const p=new URLSearchParams(window.location.search);
const c=(p.get('code')||'').toUpperCase().replace(/[^A-Z0-9]/g,'');
if(c.length>=4){ /* auto-join */ }
```

Singer expects `?code=` URL param. The room code is the **Agora channel identifier** (`elsewhere_<CODE>`), not the session UUID.

### Today's RPC usage

```bash
grep 'sb\.rpc\|sb\.from' karaoke/singer.html
# (matches only the 2c.3.2 sessionStorage device_key reads — NO RPC calls, NO sb.from queries)
```

**Singer.html does NOT call any Supabase RPCs today.** It joins via Agora only. There's no path to verify the singer is actually a session participant.

### `rpc_session_join` callers (existing, NOT in singer.html)

- `index.html:2919` — `handleSameAppRejoin()` calls `rpc_session_join({session_id, p_participation_role: 'audience'})` for the 2c.3.1 same-app rejoin path
- `index.html:3083` — same pattern in the 23505-already-active-session R4 fallback during `handleTvRemoteTileTap`

### How a singer ends up in `session_participants` today

| Path | Creates participant row? |
|---|---|
| User taps Karaoke from Elsewhere home (Way 2, **production**) | **Yes** — Manager via `rpc_session_start` (manager + audience role); other household members via `rpc_session_join('audience')` in R4 fallback |
| User scans QR + types code in `screen-join` (Way 1, **legacy**) | **No** — Agora-only, never touches DB |
| Manager who started session navigates singer.html via deep link | **Yes** — Manager already inserted by `rpc_session_start` |
| Direct URL `karaoke/singer.html?code=ABCD` (dev/legacy) | **No** — same as Way 1 |

**Way 2 paths are reliable in production.** Way 1 paths are the gap.

### Failure mode inventory

| Scenario | Today's behavior |
|---|---|
| Network drops during `screen-performing` | Agora reconnect handled by SDK; no app-level reconnect logic |
| Session ends mid-song from manager's "End Session" | 2d.1 added `sendMsg({type:'session-ended'})` from stage; singer mutes mic + goes home |
| Manager kicks singer (intended) | **No mechanism today** — `rpc_session_update_participant` requires manager auth context, but no UI on stage or singer |
| Phone backgrounded during long song | Agora may suspend; no app-level handling |
| Phone screen locks | Performance continues server-side; singer's UI stays on `screen-performing` until unlocked |

### Implications for 2e

- **Add `rpc_session_join` call in singer.html's `doJoin()` success path** — ensures every singer has a participant row, including Way 1 paths if the user is signed in.
- **Add Supabase realtime subscription on singer.html** — currently absent; needs the same pattern stage.html uses (`startStageRealtimeSub` etc.).
- **Defensive fallback for unauthed/no-participant case** — mirror 2d.1's solo mode pattern. Singer falls back to legacy single-singer UX with no role-aware features.

---

## Area 4 — Push notification feasibility

**Reframed per user correction:** push assessment must be oriented around the existing **Capacitor iOS app shell**, not browser Web Push. Singer.html IS bundled in the iOS app's `www/` directory (verified at `~/Projects/elsewhere-app/www/karaoke/`). iOS users access singer.html *through the app*, not through Safari. Native APNs via Capacitor plugin is the relevant path.

### iOS Capacitor app inventory

Project: `~/Projects/elsewhere-app/`
- **Capacitor version:** 8.3.1
- **`capacitor.config.json`:** `{ "appId": "my.elsewhere", "appName": "Elsewhere", "webDir": "www" }` — minimal config, no plugin sections
- **Installed plugins:** `@capacitor/app`, `@capacitor/browser`, `@capacitor/cli`, `@capacitor/core`, `@capacitor/ios`. **`@capacitor/push-notifications` NOT installed.**
- **`www/` payload contents:** `claim.html, docs/, elsewhere-theme.css, games/, index.html, karaoke/, shell/, tv2.html, venues.json, wellness/`. **Singer.html IS bundled** (under `www/karaoke/singer.html`).
- **Android shell:** **None.** No `android/` directory, no Android-related Capacitor config. Android users are web-only.

### iOS native push state

`~/Projects/elsewhere-app/ios/App/App/Info.plist`:
- ✗ No `aps-environment` entitlement — push capability NOT enabled
- ✗ No `UIBackgroundModes` array — no `remote-notification` mode
- ✓ `CFBundleURLSchemes` includes `elsewhere://` (deep linking working)
- ✓ Camera + microphone usage descriptions present
- ✗ **No `.entitlements` file at all** — push capability would need creating

`~/Projects/elsewhere-app/ios/App/App/AppDelegate.swift`:
- Zero push-related code. No `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`, no UNUserNotificationCenter setup, no push registration calls.

### Backend push infrastructure

| Search | Found |
|---|---|
| `apns_tokens`, `device_tokens`, `push_tokens` table in `db/*.sql` | None |
| Supabase Edge Functions (`/supabase/functions/`) | No directory exists |
| Push-related RPCs | None |

**Zero backend push infrastructure.** No token storage, no edge function, no APNs sender.

### What pushing via Capacitor + APNs requires

| Component | Status | Effort |
|---|---|---|
| `npm install @capacitor/push-notifications` in elsewhere-app | Missing | ~5 min |
| `npx cap sync ios` after install | Missing | ~5 min |
| iOS Capabilities → enable "Push Notifications" + "Background Modes → Remote notifications" | Missing | ~10 min in Xcode |
| `.entitlements` file with `aps-environment` (auto-created by Xcode capabilities toggle) | Missing | (above) |
| `AppDelegate.swift` updates: register for remote notifications, handle `deviceToken`, forward to JS via Capacitor | Missing | ~30 min |
| Apple Developer account: create APNs Auth Key (.p8 file) | Likely already exists since app ships | ~30 min if first time |
| Supabase migration: new `push_subscriptions` table `(user_id, device_token, platform, created_at, last_seen_at)` | Missing | ~30 min |
| Supabase Edge Function: `send-push-notification(user_id, payload)` — looks up token, calls APNs HTTP/2 | Missing | ~2-3 hr |
| Trigger: edge function called when `participant_role_changed` event has `participation_role='active'` for a target user. Call from singer.html OR from a DB trigger. | Missing | ~30 min |
| Singer.html: on init, request permission via `PushNotifications.requestPermissions()`, register, store token via RPC | Missing | ~30 min |
| Singer.html: handle `pushNotificationActionPerformed` event (user tapped notification → navigate to Take Stage prompt) | Missing | ~30 min |
| **Total iOS push integration** | — | **~6-8 hours** |

Plus: end-to-end testing on a real device (~1-2 hr). **Apple Developer account already used to ship the iOS app**, so the .p8 key and team setup are likely present (need user confirmation).

### Foreground fallbacks (still needed for Android web users)

Even with iOS push, Android users on browser need foreground fallbacks since there's no Android shell:

1. **Vibration API** (`navigator.vibrate(pattern)`) — works on Android Chrome without permission
2. **Audio cue** — play notification chime via inline audio
3. **Page Visibility API** — detect when user re-foregrounds, re-fire prompt with audio + vibration
4. **Full-screen Take Stage modal** — appears immediately if foregrounded; persists across visibility changes

### Recommendation

**Two viable paths — both are reasonable choices:**

**Path A — Ship push in 2e Phase 1 alongside the role-aware UI work** (~+6-8 hr to 2e total scope, primarily iOS):
- iOS users (the dominant platform per the iOS app being the only native shell) get push notifications when promoted
- Android web users get foreground fallback only (acceptable Phase-1 limitation)
- Aligned with broader native-shell strategy
- Pushes infrastructure cost forward; once built, future features benefit

**Path B — Defer push to post-2e** (~0 hr added to 2e):
- 2e ships sooner with foreground fallbacks for everyone
- iOS users have the same UX as Android web users in this phase (no platform parity penalty)
- Push deferred as DEFERRED.md entry; revisit when an additional motivator appears
- Decision can be revisited any time without rework

**Recommendation: Path A (ship in 2e Phase 1).** Reasoning:
- iOS native push via Capacitor is significantly more tractable than browser Web Push (which my prior assessment was incorrectly oriented toward)
- Singers commonly leave their phone face-down or screen-locked between songs; backgrounded promotion is a real-world case worth solving for the dominant platform
- The 6-8 hr cost is amortized — push infrastructure unlocks future use cases (manager helper notifications, queue-position-changed pings, etc.)
- The Android-web gap is acceptable — foreground fallback covers most Android users (singers near the TV)
- Could be delivered as 2e.0 (push infrastructure) before 2e.1, similar to how 2d.0 preceded 2d.1

**If user prefers Path B:** Phase 1 fallback for backgrounded phones — detect `document.visibilityState === 'hidden'` when `participation_role` transitions to `active`. Store a "you were promoted" flag in `sessionStorage`. On `visibilitychange` → visible, show full-screen Take Stage prompt with audio cue + vibration burst.

---

## Area 5 — Manager override mechanism

This area covers two distinct concerns:
1. **Location** — where the manager's queue management UI lives (decision 5)
2. **Mechanism** — the Karaoke Control Model's Options A/B/C (control message transport)

### Manager-detection logic today

`grep 'manager\b\|currentSession.manager_user_id' karaoke/singer.html`:
```
(no matches)
```

**Singer.html has zero manager detection today.** No conditional UI based on `control_role === 'manager'`. The same UX shows to every singer regardless of role.

### `rpc_session_update_participant` capabilities (db/011)

Reviewed at HEAD `3961418`. Manager (`control_role IN ('manager','host')`) can mutate cross-user:
- `participation_role` — `audience ↔ queued`, `audience ↔ active`, `queued ↔ active` (any direction)
- `control_role` — promote/demote others to `host`/`none` (cannot assign `'manager'` directly)
- `pre_selections` — manager OR target-is-caller

Plus `rpc_session_update_queue_position(session_id, user_id, new_position)` — manager-only reorder.

**All needed mutations are supported by existing RPCs.** No schema additions required for manager queue management.

### Stage.html queue panel — extension feasibility

Reviewed at section 1.5 (commit `e481086`):

```js
// renderSessionUI() at stage.html lines 5459+
list.innerHTML = sorted.map(p => {
  // ... avatar + name + position + song + venue
  return `<div class="qp-row${isActive ? ' active' : ''}">...</div>`;
}).join('');
```

The queue panel rows are pure HTML strings with no per-row click handlers today. Adding click handlers would require event delegation on `#qp-list`, then dispatching by `data-user-id` attribute. **Mechanically feasible**, but:
- Stage.html is a TV display — typically no remote control, no mouse, no touch input on the TV
- TVs are usually viewed by the room; per-row interactions don't fit the form factor
- The Karaoke Control Model § 4.2 explicitly says the queue panel is "Visible to everyone with stage.html access (not gated by role)" — it's a glance affordance, not an admin surface

**Stage.html-side queue management is mechanically feasible but ergonomically wrong.** Recommend not pursuing.

### Three location options

| Option | Manager UI lives | Pros | Cons |
|---|---|---|---|
| **A — Stage.html only** | TV display, per-row click handlers + admin gear | Single rendering location; no duplicated UI logic | TV doesn't have native input (no mouse/keyboard); reduces utility to "tap-to-act" via remote which we don't have |
| **B — Singer.html (manager-only view)** | Manager's phone, conditional rendering when `control_role === 'manager'` | Phone is always in the manager's hand; unifies all manager actions in one place | Adds significant UI complexity to singer.html; manager and singer roles share screen-home with mode-conditional rendering |
| **C — Hybrid** | Stage.html shows queue glance; singer.html has the action affordances | Read everywhere, write only on phone (matches Karaoke Control Model § 4.2 intent) | Adds a third rendering target (singer.html-as-manager); slight duplication |

**Recommendation: Option B (singer.html, manager-only view).** Reasoning:
- Phone is the natural input device (touch, always-on)
- Stage.html's queue panel already shows the read-only list; manager can glance at TV while acting on phone
- Adds singer.html role-aware rendering for managers, which is the broader 2e scope anyway

### Override mechanism — Karaoke Control Model Options A/B/C

Verbatim from `KARAOKE-CONTROL-MODEL.md` § 2 line 215-218:

> - **Option A:** Session Manager's phone sends a Supabase realtime command that the Active Singer's phone listens for and re-broadcasts as Agora to stage.
> - **Option B:** Session Manager's phone gets direct stage-channel access and sends Agora commands directly.
> - **Option C:** New RPC layer for session-state mutations that publishes events stage.html consumes.

| Option | Implementation |
|---|---|
| **A — Manager → Active Singer relay** | Manager's phone publishes Supabase realtime → Active singer's phone subscribes → singer's phone calls existing `sendToStage()` → stage receives via Agora as if singer pressed it. **Cons:** Requires active singer to be online + responsive; if singer's phone is paused/lost, manager commands fail silently. |
| **B — Manager → Agora directly** | Manager's phone joins the Agora karaoke room as a `host` (mirroring singer's join), then calls `sendToStage()` directly. **Pros:** Matches the existing Agora-first pattern; no new realtime topology. **Cons:** Multiple "host" Agora clients per room; need to prevent manager's mic from being broadcast. Mic-mute on join + role discipline solves it. |
| **C — Manager → RPC → stage** | Manager's phone calls a new RPC like `rpc_session_command(p_session_id, p_command, p_payload)` which mutates server state and publishes a realtime event. Stage subscribes to that event. **Pros:** Clean architectural layering; auditable command log. **Cons:** Most schema work; requires a new RPC + event family; adds latency vs Agora direct. |

**Recommendation: Option B with mic-mute discipline.** Reasoning:
- All existing mid-song controls already flow through Agora `sendToStage` from the active singer's phone
- Manager can join Agora as a silent observer (`setClientRole('audience')` initially, upgrading to `'host'` only when sending commands), eliminating mic broadcast risk
- Zero new infrastructure — reuses the existing data channel
- Latency-equivalent to current active-singer commands

**Caveats with Option B:**
- The existing "one host" assumption in Agora becomes "two hosts" — need to verify Agora live-mode supports this (it does; multiple hosts is normal)
- Manager needs an UID to be distinguishable from singer — use the user's auth UID or a deterministic prefix
- If manager closes their browser mid-command, the message is in-flight only via Agora — same failure mode as singer commands today

---

## Hard Blockers

### B1 — Singer.html doesn't call `rpc_session_join`

**Severity:** Functional blocker for 2e role-aware UI. Resolvable via small addition.

**Symptom:** Currently, `doJoin()` (singer.html line 610) joins via Agora only. No `session_participants` row is created from this path. Way 1 (legacy ?code= URL) and direct-nav paths leave the user without a DB participant row, so role-aware UI in 2e has no role to read.

**Impact areas:**
- Take Stage prompt — needs to listen for own `participation_role` change → audience.
- Queue position display — needs row in DB to display.
- Mode-conditional UI — needs `control_role` and `participation_role` to switch on.

**Resolution:** Add `rpc_session_join({session_id, participation_role: 'audience'})` call after Agora join in `doJoin()`. Need to look up `session_id` from `room_code` first. Sequence:
1. Agora join (existing)
2. If signed in: query `sessions` by `room_code` (or have `tv_device_id` in sessionStorage from Way 2 path) → get `session_id`
3. Call `rpc_session_join` with `'audience'` role
4. Defensive: if not signed in OR query fails OR RPC fails → fall back to legacy single-singer behavior (no role-aware UI)

**Effort:** ~30-60 minutes in 2e.1.

---

### B2 — Push notification scope decision

**Severity:** Scope decision — affects 2e total time and platform parity.

**Symptom:** Karaoke Control Model § 5.2 lists "Push notification: 'You are up — click here to take the stage' when phone backgrounded during promotion" as a 2e work item. Singer.html IS bundled in the iOS Capacitor app (`~/Projects/elsewhere-app/www/karaoke/`), so iOS native push via `@capacitor/push-notifications` + APNs is a viable path. Android shell does not exist; Android users would be web-only (foreground fallback). Backend infrastructure is zero (no plugin installed, no entitlement, no DB tokens, no edge function).

**Two viable resolutions** — neither is a hard block, both are valid choices:

1. **Ship push in 2e (recommended)** — adds ~6-8 hr to 2e. Sub-phase 2e.0 builds Capacitor push plugin + iOS entitlements + AppDelegate + DB push_subscriptions table + Supabase edge function. Singer.html integrates in 2e.1+. iOS users get push; Android users get foreground fallback.
2. **Defer push to post-2e** — 2e ships sooner with foreground fallbacks for all platforms. Push infrastructure as a DEFERRED.md entry; revisit as a separate phase.

See Area 4 for full feasibility breakdown and recommendation.

---

### B3 — Manager Override transport mechanism (Options A/B/C) undecided

**Severity:** Implementation blocker for Session Manager queue management.

**Symptom:** Karaoke Control Model § 2 lines 214-218 list Options A/B/C without choosing one. Manager queue management UI in 2e needs a transport mechanism to send commands; without choice, can't be wired.

**Resolution:** Lock the option choice during session start. See Area 5 for analysis. Recommendation: **Option B (Manager phone joins Agora as host with mic-mute discipline)**.

**Effort impact by option:**
- A (relay through active singer): ~3-4 hr (requires new realtime channel + relay logic on singer)
- B (direct Agora): ~2-3 hr (extends existing pattern)
- C (RPC + event): ~4-5 hr (new RPC, schema migration, event family)

---

## Caveats

### C1 — Way 1 vs Way 2 path divergence

Way 1 (legacy `?code=` URL navigation) doesn't go through `index.html`'s session orchestration. Way 2 (Karaoke tile from Elsewhere home) does. After B1's resolution, both paths converge — but the Way 1 user might be unsigned in or not a household member, so `rpc_session_join` can fail.

**Mitigation:** defensive fallback to legacy single-singer UX when join fails. No-op for the 2e role-aware features. This mirrors 2d.1's solo mode pattern (DECISION-AUDIT-5).

### C2 — Singer-side realtime subscription is new ground

Today only stage.html subscribes to Supabase realtime (added in 2d.1 section 1.3a). 2e adds singer.html as the second subscriber, on the same `tv_device:<device_key>` topic. Multiplexing handles routing.

**Mitigation:** mirror stage.html's `startStageRealtimeSub` / `stopStageRealtimeSub` pattern. Same idempotent start, explicit stop, 5s timeout, three-state subscribe-status check.

### C3 — Backgrounded phone behavior — depends on push decision

If push is deferred (recommended): singer's phone backgrounded → promotion event fires → page handler doesn't run. When user foregrounds, page must detect missed promotion via state check + show recovery UI.

**Mitigation:** Page Visibility API + `sessionStorage`-backed missed-promotion flag. Refresh session state on `visibilitychange` → visible. If `currentActiveSinger` is now self, show Take Stage prompt with audio + vibration.

### C4 — Multiple hosts on Agora (Option B for Manager Override)

Agora live-mode supports multiple hosts per room. Manager joining as host (in addition to active singer) is supported. Need to confirm UID disambiguation and ensure manager doesn't accidentally publish their mic.

**Mitigation:** manager joins with `setClientRole('audience')` initially; only upgrades to `'host'` when sending data-channel commands; manually mute mic at all times. Or use Agora's `RTM` (real-time messaging) layer that's separate from the audio bus — but RTM isn't currently in use in this codebase, so it'd be new infrastructure.

### C5 — Stage.html sends `mic-connected` from singer (line 639)

The existing `sendToStage({type:'mic-connected', roomCode})` happens once after Agora join + mic publish. Stage.html's `handleStageMsg` at line 3375 hides idle-panel on receive. **2e must not break this** when adding new singer-side message types.

### C6 — No Take Stage prompt UX precedent

Existing transient surfaces (showToast 3500ms, idle-panel pulse 8s) are too fleeting. 2e introduces a new surface category — modal-like, requires user action, can't auto-dismiss. Decision 1 below frames the options.

---

## Six Decisions to Lock at Session Start

### Decision 1 — Take Stage prompt UX

**Question:** When a queued singer is promoted to active, what does the prompt look like?

| Option | Description | Implications |
|---|---|---|
| **A — Full-screen modal** | Page-blocking overlay with avatar + name + "You are up — Tap to confirm". No auto-advance. | Can't be ignored. Strong affordance. Requires explicit dismiss. Singer must be looking at phone. |
| **B — Top banner + audio cue** | In-page banner above current screen + audio chime + vibration. Auto-dismisses if user taps anywhere. | Less intrusive. May be missed if user is mid-action elsewhere. Audio + haptic catch attention. |
| **C — Auto-advance after N seconds** | Show prompt; if no tap within 30s, auto-confirm and proceed. Safety net for distracted singers. | Risk: false-positive auto-confirm when user is unaware. Mitigated if combined with audio. |

**Recommendation: A (full-screen modal)** with audio cue on appear + vibration burst. Tap-to-confirm only. No auto-advance. Spec § 2 says "tap-to-confirm, no countdown" — matches recommendation.

**Backgrounded phone:** prompt persists; on `visibilitychange` → visible, prompt re-fires audio + vibration.

---

### Decision 2 — Queue position display

**Question:** How is queue position shown to a queued (Available Singer) user?

| Option | Description | Implications |
|---|---|---|
| **A — Always visible on screen-home** | "You're #3 in line" banner permanently showing while queued. | Always informative; takes screen real estate. |
| **B — Only on dedicated tile/section** | Compact tile in screen-home grid that shows position. Dismissible/hideable. | Cleaner home; requires user attention to surface. |
| **C — Number-only vs avatar list** | Either "#3" (just the number) or full list "Alice, then Bob, then YOU" with avatars. | Number is compact; avatar list is rich but takes more space. |

**Recommendation: A + number-only.** Always visible at top of screen-home, "You're #3 of 5 in line." Avatar list is overkill for phone screens; queue panel on stage.html already shows the full list for those who want it.

---

### Decision 3 — Singer-side realtime channel scope

**Question:** What realtime channel does singer.html subscribe to?

| Option | Channel | Implications |
|---|---|---|
| **A — Same as stage** | `tv_device:<device_key>` | Uses existing topic. Singer needs `device_key` from `sessionStorage.elsewhere.active_tv.device_key` (set during 2c.3.2 flow). |
| **B — Per-session topic** | `session:<session_id>` (new pattern) | Explicit session scoping. Future-proofs for multi-TV-per-household scenarios. New channel topic. |
| **C — Hybrid** | Same as stage now, switch to per-session if/when multi-TV becomes a real concern. | Defers infrastructure work. Matches 2d.1 pattern. |

**Recommendation: A (same as stage).** Reuses topic that already multiplexes well. `session_id` is in `currentSession.id` after participant query. Singer subscribes to same `tv_device:<device_key>` topic — already-published events (`participant_role_changed`, `queue_updated`, `session_ended`) reach both stage and singer.

**Caveat:** singer needs `device_key` from sessionStorage (set during Way 2 flow). Way 1 path won't have it; defensive fallback to no-realtime + cold-path-only refresh.

---

### Decision 4 — Push notification scope

**Question:** Does 2e ship push notifications? (Reframed per Capacitor context — iOS native push is the relevant path, not browser Web Push.)

| Option | Scope | Implications |
|---|---|---|
| **A — Ship in 2e (recommended)** | Add as 2e.0 prerequisite phase: install `@capacitor/push-notifications`, enable iOS Capabilities (push + remote-notification background mode), wire AppDelegate, new `push_subscriptions` DB table, Supabase Edge Function for APNs sender. Then integrate in 2e.1+. | iOS users get push (the dominant platform — only native shell). Android web users get foreground fallback only (acceptable). +6-8 hr to 2e. Apple Developer setup likely already done since app ships. |
| **B — Defer to post-2e** | Foreground fallbacks for all platforms (audio + vibration + Page Visibility API). Push as DEFERRED entry; revisit as separate phase. | 2e ships sooner, ~0 hr added. Singers with backgrounded phones miss promotion until refocus. Both iOS and Android share the same UX (no platform-parity penalty). Decision can be revisited any time. |

**Recommendation: A (ship in 2e as Phase 0 prerequisite).** Reasoning:
- iOS native push via Capacitor is significantly more tractable than browser Web Push (my initial assessment was incorrectly oriented toward iOS Safari)
- Singers commonly leave phones face-down between songs — backgrounded promotion is a real-world case worth solving on the dominant platform
- Infrastructure cost amortizes — manager helper pushes, queue-position-changed pings, and other future notifications all benefit
- Android-web foreground-only is acceptable Phase-1 (singers near the TV anyway)
- 6-8 hr fits comfortably alongside the 2e.1-2.3 work; consistent with how 2d.0 preceded 2d.1

**Either choice is reasonable.** Path B is also defensible if the goal is to ship 2e fast and de-risk push as a separate concern.

---

### Decision 5 — Manager override location

**Question:** Where does Session Manager queue management UI live?

| Option | Location | Implications |
|---|---|---|
| **A — Stage.html (TV-side)** | Per-row click handlers on queue panel + new admin overlay | TV usually has no input device; ergonomically wrong |
| **B — Singer.html (phone-side, manager-only view)** | Conditional rendering when `control_role === 'manager'` | Phone is in hand; matches the 2e scope of role-aware UI |
| **C — Hybrid** | Read everywhere (stage panel), write only on phone | Slight UI duplication but matches Karaoke Control Model § 4.2 intent |

**Recommendation: B (singer.html, manager-only view).** See Area 5 for rationale. Stage.html stays pure read-only display; all manager actions on phone.

---

### Decision 6 — Backgrounded phone handling

**Question:** What happens if singer's phone is locked/backgrounded when promoted?

| Option | Approach | Implications |
|---|---|---|
| **A — Show prompt immediately on foreground** | Detect via Page Visibility API; on visibilitychange → visible, re-fire Take Stage prompt with audio + vibration | Catches user when they re-engage |
| **B — Show "you missed your turn" recovery** | If too much time elapsed, show different UI ("Sorry, you were skipped — manager continues") | Handles long-backgrounded case; manager would have likely already skipped |
| **C — Combination** | Both A and B with a threshold (e.g., 30s elapsed = recovery; <30s = standard prompt) | Most robust; slight complexity | 

**Recommendation: A (show prompt on foreground).** The threshold approach (C) requires a server-side concept of "still-eligible-active" that we don't have. The simpler model: if user foregrounds and their `participation_role` is still `active`, show prompt. If it's now `audience` (manager skipped them), no prompt — they see normal home with note. Re-querying on foreground via `refreshSessionState` already produces the right state; just attach prompt logic to that.

**Depends on Decision 4** (if push is deferred — recommended — then this is the only path; if push ships, push provides the foreground signal).

---

## Recommended Phase Split

### 2e.0 — Push notification infrastructure (optional, ~6-8 hr, only if Path A on Decision 4)

**Scope:** Capacitor plugin install + iOS entitlements + AppDelegate wiring + DB push_subscriptions table + Supabase Edge Function for APNs sender. Independent of singer.html UI work; ships before 2e.1.

- `npm install @capacitor/push-notifications` in `~/Projects/elsewhere-app`, `npx cap sync ios`
- Xcode: enable "Push Notifications" capability + "Background Modes → Remote notifications"
- AppDelegate.swift: register, handle deviceToken, forward via Capacitor bridge
- DB migration: `db/014_push_subscriptions.sql` (new table, RLS, RPCs `rpc_register_push_token`, `rpc_unregister_push_token`)
- Supabase Edge Function: `send-push-notification` calling APNs HTTP/2
- Apple Developer: confirm .p8 key exists (app already ships); store APNs key in Supabase secrets

Skip this phase if Decision 4 = Path B (defer).

### 2e.1 — Read-only role-aware UI (~3-4 hr, 5-6 sections)

**Scope:** Singer.html establishes session context, queries own role, conditionally renders screen-home content based on role. No write actions yet.

- Add `rpc_session_join` to `doJoin()` (resolves B1)
- Add module state: `currentSession`, `currentParticipants`, `currentMyRow`, `currentMyControlRole`, `currentMyParticipationRole`, etc.
- Add `refreshSessionState` mirroring stage.html's pattern
- Add Supabase realtime subscription on `tv_device:<device_key>` (resolves Decision 3 with Option A)
- Wire `participant_role_changed` + `queue_updated` + `session_ended` event handlers
- Conditionally render screen-home tiles based on `participation_role` (active / queued / audience)
- Display queue position (resolves Decision 2)

### 2e.2 — Self write actions (~2-3 hr, 4-5 sections)

**Scope:** User can take actions on their own row.

- "Add to Queue" / "Update My Song" UX
- Queue editing: change song, change venue, change costume, remove self from queue
- Take Stage prompt on `participation_role` → active transition (resolves Decision 1)
- Foregrounded vs backgrounded handling via Page Visibility API (resolves Decision 6)
- Audio cue + vibration on prompt
- Self-action RPCs: `rpc_session_update_participant` for own row

### 2e.3 — Session Manager queue management + Override (~3-4 hr, 5-6 sections)

**Scope:** Manager-only UI + cross-user RPCs.

- Conditional manager-view UI (resolves Decision 5 with Option B)
- Queue management actions: reorder, force-promote, skip current, take over
- RPCs: `rpc_session_update_participant` (cross-user), `rpc_session_update_queue_position`
- Manager Override mechanism (resolves B3 with Option B — Agora-direct)
- Manager joins Agora as host with mic-mute discipline; sends mid-song commands

### Total estimated effort: ~8-11 hours across three phases

---

## Estimated Effort

**Conservative ranges** (assuming hardware testing between phases, similar pace to 2d.1's 8-section ship):

| Phase | Sections | Hours | Notes |
|---|---|---|---|
| 2e.1 | 5-6 | 3-4 | Read-only foundation; least risky; B1 resolution + Decision 3 |
| 2e.2 | 4-5 | 2-3 | Self actions; Decision 1 + 6 testing-heavy |
| 2e.3 | 5-6 | 3-4 | Manager UI + Override mechanism (Decision 5 + B3); largest variance |
| **Total** | **14-17** | **8-11 hr** | Plus ~30 min audit / decision-locking at session start |

**Uncertainties:**
- Push notification decision (B2 / Decision 4): if Path A chosen, add 2e.0 prerequisite phase ~6-8 hr (Capacitor plugin + iOS entitlements + AppDelegate + DB table + Supabase Edge Function for APNs). Apple Developer .p8 key likely exists since app ships — confirm with user.
- Manager Override mechanism (B3): if Option C chosen, +1-2 hr for new RPC migration. Option B (recommended) is +0 hr.
- Agora multi-host edge cases (C4): if blocking for Option B, fall back to Option A or C — adds 2-3 hr.
- Way 1 / no-auth fallback testing: ~1 hr extra QA across phases.

**Comparable shipped scope:** 2d.1 was 8 sections in ~5-6 hours of focused work (per Phase 2 estimate). 2e is larger and more varied; conservative estimate accounts for the variance.

---

## Locked Decisions (locked 2026-04-26 end of session)

The 6 decisions framed in this audit have been resolved. Implementation
in next session proceeds against these locks:

1. **Take Stage prompt UX:** Option A — Full-screen modal, tap-to-confirm,
   audio cue + vibration burst on appear. No auto-advance. On
   visibilitychange → visible after backgrounded promotion, re-fire audio +
   vibration.

2. **Queue position display:** Option A — Always visible at top of
   screen-home for queued users. Number-only ("#3 of 5"), no avatar list.

3. **Singer-side realtime channel scope:** Option A — Same
   `tv_device:<device_key>` topic as stage.html. Way 1 paths fall back to
   no-realtime + cold-path-only refresh.

4. **Push notification scope:** Option A — Ship as 2e.0 prerequisite phase.
   Capacitor `@capacitor/push-notifications` + iOS entitlements + AppDelegate
   + DB push_subscriptions table + Supabase Edge Function for APNs sender.
   iOS users get push via APNs; Android web users get foreground fallback.

5. **Manager override location:** Option B — Singer.html manager-only view.
   Stage.html queue panel stays read-only.

6. **Backgrounded phone handling:** Option A — Page Visibility API +
   sessionStorage missed-promotion flag. Re-query on foreground; render
   based on current truth.

## Hard Blocker Resolutions

- **B1:** Resolved in 2e.1 via `rpc_session_join` in `doJoin()` with
  defensive fallback to legacy single-singer behavior.
- **B2:** Resolved via Decision 4 = Path A. Push ships as 2e.0.
- **B3:** Resolved as Manager Override Option B — Manager phone joins
  Agora as host with mic-mute discipline.

## Phase Plan

```
2e.0 — Push notification infrastructure  (~6-8 hr)
2e.1 — Read-only role-aware UI            (~3-4 hr, 5-6 sections)
2e.2 — Self write actions                 (~2-3 hr, 4-5 sections)
2e.3 — Manager queue management + Override (~3-4 hr, 5-6 sections)

Total: 14-19 hours across 3-5 sessions
```

## Apple Developer Account Confirmed

- Apple Developer Program: **active** (renews April 9, 2027)
- Enrollment: Individual
- **Team ID: ZK6356AG69**
- APNs Auth Key (.p8): **generated and downloaded by user** (locally stored,
  not in repo). Key ID will be supplied by user at start of 2e.0.
- App Bundle ID: `my.elsewhere`
- iOS shell location: `~/Projects/elsewhere-app/`

## 2e.0 Tomorrow — Pre-Flight Checklist

Before code work starts, the implementing session should confirm:
- [ ] User has the .p8 file accessible
- [ ] User has the Key ID (10-char alphanumeric from key generation page)
- [ ] User has the Team ID (`ZK6356AG69`)
- [ ] User can open `~/Projects/elsewhere-app` in Xcode
- [ ] User has `npm` available in elsewhere-app project

Once confirmed, 2e.0 starts with:
1. `npm install @capacitor/push-notifications` in elsewhere-app
2. Xcode capabilities: enable Push + Remote Notifications background mode
3. AppDelegate.swift: register, handle deviceToken, forward via Capacitor bridge
4. DB migration db/014_push_subscriptions.sql
5. Supabase Edge Function send-push-notification (APNs HTTP/2)
6. Singer.html token registration + push handler

---

## Footer

Audit conducted via Claude Code investigation across 5 areas: singer.html screen state machine, Agora message handlers, singer auth + session context, push notification feasibility, manager override mechanism. 6 decisions framed for session-start lock-in. 3 hard blockers, 6 caveats identified.

Convention: doc commits use `Co-Authored-By: Claude <noreply@anthropic.com>` trailer.
