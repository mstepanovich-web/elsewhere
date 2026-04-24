# Session 5 Part 2 Breakdown

**Status:** Part 2a complete (commit `d1b4edd`). Parts 2b–2f pending.
**Created:** 2026-04-23
**Parent plan:** `docs/SESSION-5-PLAN.md` (commit `2b40313`)

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
- `index.html` `handleTvRemoteTileTap`: call `rpc_session_start` before `publishLaunchApp`; emit `session_started` after RPC succeeds
- `karaoke/singer.html` + `games/player.html` `handleBackToElsewhere`: call `rpc_session_leave`; SELECT follow-up to detect if session ended as side effect (manager-alone branch); emit `session_ended` + `exit_app` only if session ended
- `tv2.html`: subscribe to `session_ended`; navigate to apps grid on receive
- `karaoke/stage.html` + `games/tv.html`: on `exit_app`, check session state before navigating; stay if session still active

**Locked decisions:**
- (a) SELECT follow-up (not RPC return-type change) to detect session-ended-as-side-effect
- Sessions always created on app-tile tap in Session 5; "no session" fallback is for dev/direct-nav only
- 2b may be split into 2b.1 (phone-side) + 2b.2 (TV-side) if scope feels sprawling — judgment call at implementation

**Entry criteria:** 2a complete ✓
**Exit criteria:** DB session rows created/ended at correct lifecycle points; no stale rows; TV stays on stage when session continues, navigates back on `session_ended`
**Files touched:** `index.html`, `karaoke/singer.html`, `games/player.html`, `tv2.html`, `karaoke/stage.html`, `games/tv.html`
**Rough commit count:** 1–2

### 2c — Apps grid session-awareness [PENDING]

**Scope:**
- `index.html` `screen-tv-remote` on mount: query active session + caller's participant row
- Relabel active-app tile: "Rejoin Karaoke" (caller is participant) / "Karaoke (active)" (caller not participant) / normal (no session)
- Tap active-session tile with caller as participant: `rpc_session_join` if needed + navigate
- Tap different-app tile with session active: confirm dialog "End current session to start [app]?" → on confirm: `rpc_session_end` + `publishSessionEnded` + `rpc_session_start` + navigate
- Subscribe to `session_started` / `session_ended` for live relabeling

**Locked decisions:**
- Apps grid scoping is per currently-selected TV, not global across user's TVs
- Minimum-viable visual polish (plain relabel + confirm dialog); badge styling / animations deferred

**Entry criteria:** 2b complete
**Exit criteria:** Apps grid reflects session state; rejoin works; cross-app switching prompts confirmation; live updates
**Files touched:** `index.html`
**Rough commit count:** 1–2

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

Per Session 5 design: Back to Elsewhere = navigate but stay in session. The phone navigates to apps grid; the TV stays on the current session UNLESS the session ends (manager was alone, no eligible promotee).

No user-facing "Leave session" button. Exits happen via:
- Explicit end session (manager only)
- Going inactive (10-min threshold)
- Auto-promote-then-leave for managers

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
- SELECT follow-up to detect session-ended-as-side-effect

## Applied migrations

All 4 migrations in `db/` are applied in Supabase:
- `db/008_sessions_and_participants.sql`
- `db/009_session_lifecycle_rpcs.sql`
- `db/010_manager_mechanics_rpcs.sql`
- `db/011_role_and_queue_mutation_rpcs.sql`

No pending migrations to apply on session resume.
