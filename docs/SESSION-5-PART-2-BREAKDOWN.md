# Session 5 Part 2 Breakdown

**Status:** Part 2a complete (commit `d1b4edd`). Parts 2b–2f pending.
**Created:** 2026-04-23
**Parent plan:** `docs/SESSION-5-PLAN.md` (commit `2b40313`)
**Canonical state model:** [docs/PHONE-AND-TV-STATE-MODEL.md](./PHONE-AND-TV-STATE-MODEL.md) (added 2026-04-24, commit `36353ca`). Parts 2c onward operate against the model defined there. Where this breakdown's older language conflicts with the state model, the state model wins.

## Context for the next session

Session 5 breaks into 5 parts. Part 1 (schema + RPCs + `shell/realtime.js` extraction) is complete and applied. Part 2 is Karaoke integration — 6 sub-parts from event publishers to audience.html wiring. Part 2a shipped the realtime event publishers. Parts 2b–2f need to land before Session 5 Part 3 (Games) can start.

## Sub-part breakdown

### 2a — Event publishers in shell/realtime.js ✓ COMPLETE (`d1b4edd`)

- 5 new publishers: `publishSessionStarted`, `publishManagerChanged`, `publishParticipantRoleChanged`, `publishQueueUpdated`, `publishSessionEnded`
- Object-payload signatures (deviation from existing 3 publishers)
- Private `broadcast()` helper collapses duplication
- Full event emission matrix in file header documents which RPC fires which event
- NO consumer wiring yet — that's 2b+

### 2b — Session lifecycle wiring [PENDING — NEXT]

**Scope:**

- `index.html` `handleTvRemoteTileTap`: await `rpc_session_start` before `publishLaunchApp`; emit `session_started` after RPC succeeds. On RPC failure, surface error and do NOT navigate.
- `tv2.html`: subscribe to `session_ended` on the existing `tv_device:<device_key>` channel; navigate to apps grid on receive.
- `karaoke/stage.html` + `games/tv.html`: on `exit_app`, SELECT active session for this `tv_device_id`; stay on current screen if session still active, navigate as before if not. Under Session 5, phone navigating back to Elsewhere home does NOT end the session, so the TV must ignore `exit_app` when a session is still live.

**What's NOT in 2b (deliberate):**

- `karaoke/singer.html` / `games/player.html` `handleBackToElsewhere` get NO wiring changes. The manager-only Back-to-Elsewhere button becomes navigate-only: no `rpc_session_leave` call, no SELECT follow-up, no `publishSessionEnded`, no `publishExitApp`. The phone navigates away; the TV sees the implicit `exit_app` fire (from page unload) and ignores it because the session is still active. Session stays alive with the manager still as manager.
- Session termination paths are unchanged from Part 1: explicit End Session button (`rpc_session_end`), inactivity orphan timeout (`rpc_session_reclaim_manager`), admin force-reclaim (`rpc_session_admin_reclaim`), and cross-app switch confirmation (Part 2c).

**Locked decisions:**

- Back-to-Elsewhere = navigate only. Supersedes earlier breakdown language about `rpc_session_leave` + SELECT follow-up on Back tap. That design was rejected in favor of "navigate but stay in session" — matches the plan doc's "Back to Elsewhere behavior" cross-cutting decision.
- Only managers see the Back-to-Elsewhere button. Hosts and participants are app-scoped and cannot navigate to Elsewhere home from inside an app.
- "Potential participant" is a derived UI state from `(control_role, participation_role, has_tv_device, proximity)`, NOT a new schema value.
- Sessions always created on app-tile tap in Session 5; "no session" fallback in stage/tv.html is for dev/direct-nav only.
- Object-payload signatures for Session 5 publishers (Part 2a convention).
- Await-before-navigate (commit `7b81f70`).

**Entry criteria:** 2a complete ✓
**Exit criteria:** DB session rows created at app-tile tap; TV stays on stage when manager navigates back to Elsewhere home; TV navigates to apps grid on `session_ended` (fired by End Session or cross-app switch in 2c). Reclaim paths (`rpc_session_reclaim_manager`, `rpc_session_admin_reclaim`) fire `manager_changed`, not `session_ended` — the session continues through reclaim.
**Files touched:** `index.html`, `tv2.html`, `karaoke/stage.html`, `games/tv.html`. (No longer touches `karaoke/singer.html` or `games/player.html`.)
**Rough commit count:** 1

### 2c — Apps grid session-awareness + post-login home unification [PENDING]

**Scope:**

Per [docs/PHONE-AND-TV-STATE-MODEL.md](./PHONE-AND-TV-STATE-MODEL.md), the post-login home screen on the phone unifies into a single conditional-rendering element. Part 2c implements that unification along with active-session relabeling. Likely splits into 2c.1 (structural) and 2c.2 (relabeling + rejoin) — implementation-time call.

**2c.1 — Structural unification of post-login home screen:**
- Merge `screen-home` and `screen-tv-remote` into a single DOM section
- Remove the back button from the unified post-login home (it was a symptom of the split design)
- Add the proximity prompt firing automatically on home render for household users with TV access (n=1 fires immediately, n>1 fires after TV picker)
- Update `handleTvRemoteTileTap` to read TV context from the unified home rather than `screen-tv-remote.dataset.tvDeviceId` (small adjustment to Part 2b's wiring)
- Mode A (at home) renders the existing tile flow; Mode B (not at home) and Mode C (non-household user) tile state per the state model's tile state matrix
- "Your TVs" menu item becomes informational/picker rather than a navigation drill-in
- Tap behavior dispatches based on (user role, proximity, active sessions)

**2c.2 — Active session relabeling + rejoin:**
- Query active sessions on home render: `SELECT id, app FROM sessions WHERE tv_device_id = <selected TV> AND ended_at IS NULL`
- Relabel matching app tiles with "Active Session" / "Rejoin [App]" / "[App] (active)" — exact label per implementation-time UX call (state model uses "Active Session" as umbrella; user-facing copy may be more specific)
- Tap behavior on active-session tile: `rpc_session_join` if needed (caller not yet a participant), then navigate. Role determined by user context: manager rejoin vs. at-home rejoin vs. not-home audience/player join.
- Cross-app switch: if active session exists for app A and user taps app B's tile, confirm dialog → on confirm: `rpc_session_end` for A, `rpc_session_start` for B, navigate
- Subscribe to `session_started` / `session_ended` for live tile relabeling on the home

**Locked decisions:**
- Single post-login home screen — no separate `screen-tv-remote`
- All tiles same size; mode-conditional rendering varies tile state, not layout
- Proximity at TV-connect, not per app launch
- Tap behavior dispatches by user context at runtime; same UI for manager-rejoin and not-home-audience-join

**Entry criteria:** 2b complete ✓ (commit `601d125`)
**Exit criteria:** Single post-login home renders correctly across Modes A/B/C; active sessions relabel matching tiles; rejoin works for all three contexts; cross-app switch prompts and works; live updates via realtime subscriptions
**Files touched:** `index.html` (substantial restructuring)
**Rough commit count:** 2 (2c.1 + 2c.2 split is the expected case)

### 2d — karaoke/stage.html full session integration [PENDING]

**Scope:**
- Read active session on load via `sessions` query filtered by `tv_device_id`
- Graceful fallback to pre-Session-5 solo mode if no session (dev/legacy only — production always has session via 2b)
- Query + render participant list with queue positions, active singer highlighted
- Subscribe to `participant_role_changed`, `queue_updated`, `session_ended`
- On singer promotion (queued → active): load newly-promoted user's `pre_selections` (song, venue, costume) as initial stage state
- Manager/host override UI: change venue mid-song, change costume mid-song, end song button (active singer → audience via `rpc_session_update_participant`)

**Locked decisions:**
- Venue/costume overrides mid-song update TV state, NOT the active singer's `pre_selections` (those are the starting state; once active, TV is the source of truth)
- End song button sends active singer to audience, not queued

**Entry criteria:** 2b complete (2c optional — they're independent)
**Exit criteria:** Stage renders session state and queue; manager override works; pre-selections load on promotion; session events cause UI updates
**Files touched:** `karaoke/stage.html`
**Rough commit count:** 1–2

### 2e — karaoke/singer.html mode-aware [PENDING]

**Scope:**
- On load, query own participant row; branch on `participation_role`:
  - `active`: current behavior (live push to TV, same as pre-Session-5)
  - `queued`: pre-selections save via `rpc_session_update_participant` (not live-pushed to TV); show queue position
  - `audience`: redirect to `audience.html`
- On promotion (queued → active via `participant_role_changed` event): switch modes, adopt current TV state
- Manager/host external state changes: subscribe to `participant_role_changed`, reflect changes
- Queue UI for managers: list of queued singers with pre_selections visible, promote-next button (calls `rpc_session_update_participant`)
- Queued-singer self-drop: queued singers can flip themselves back to `participation_role='audience'` via `rpc_session_update_participant`. This is a role change, NOT `rpc_session_leave` — the user stays in the session. Matches the active-singer-finishes-song pattern.

**Locked decisions:**
- Audience-role users on singer.html redirect to audience.html (not inline read-only state)
- Pre-selections UI (song + venue + costume) all ship in Part 2 (existing UIs adapt; not net-new)
- Queue UI is minimal functional (list + promote button); polished UX deferred

**Entry criteria:** 2b + 2d complete (singer needs session-aware stage)
**Exit criteria:** All 3 modes work; queued users pre-select without live push; manager can promote next; external state changes reflect
**Files touched:** `karaoke/singer.html`
**Rough commit count:** 1–2

### 2f — karaoke/audience.html session integration [PENDING]

**Scope:**
- On load: `rpc_session_join(session_id, 'audience')`
- Hide picker UIs entirely (not greyed — hidden)
- Subscribe to `participant_role_changed`, `queue_updated`, `session_ended`
- Read-only spectator display of current stage state
- Audience exit is implicit. Closing the phone app or navigating away does NOT fire any RPC. Audience rows remain with `left_at = null` until a future cleanup mechanism runs. Ghost audience count is an accepted Phase 1 trade-off — see DEFERRED "Participant cleanup mechanism" for the eventual solution.

**Locked decisions:**
- Audience is fully read-only: NO song/venue/costume picker (hidden, not greyed)
- Audience back-to-Elsewhere button deferred (separate DEFERRED entry)

**Entry criteria:** 2b complete (independent of 2d/2e)
**Exit criteria:** `audience.html` joins as audience; stays in sync; read-only
**Files touched:** `karaoke/audience.html`
**Rough commit count:** 1

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

Only managers see the Back-to-Elsewhere navigation button in `karaoke/singer.html` and `games/player.html`. Hosts and regular participants do not — they are app-scoped, meaning they can navigate within the app (songs, games) but cannot leave to Elsewhere home without going through a manager-initiated flow (end session, inactivity, admin reclaim).

This informs 2e (singer.html) and the Part 2 audience flow (2f): the Back button's DOM presence is conditional on `control_role === 'manager'`.

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
- Only managers see the Back-to-Elsewhere button
- "Potential participant" is derived UI state, not a schema value
- Non-manager exits use role transitions or implicit accumulation, never `rpc_session_leave` in Session 5 Part 2

## Applied migrations

All 4 migrations in `db/` are applied in Supabase:
- `db/008_sessions_and_participants.sql`
- `db/009_session_lifecycle_rpcs.sql`
- `db/010_manager_mechanics_rpcs.sql`
- `db/011_role_and_queue_mutation_rpcs.sql`

No pending migrations to apply on session resume.
