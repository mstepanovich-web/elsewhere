# SESSION 5 PLAN — Universal session + participants + queue model

**Status:** Design complete, implementation not started
**Drafted:** 2026-04-23
**Depends on:** Session 4.10's `household_members.role` column (already shipped in Session 4.10). Session 4.11's admin UI is NOT a dependency — Session 5's admin RPCs can ship standalone; UI for triggering them lands in 4.11 or later.
**Unblocks:** Real multi-user features across every app; Session 5 follow-up work (audience back-nav, wellness app, polished queue UIs per app)

---

## Goal

Replace today's ad-hoc room-code-based session model with a universal schema-backed session + participants + queue layer shared across every app (karaoke, games, future wellness). Each app parameterizes its behavior through a declarative role manifest rather than forking its own coordination logic. Session 5 ships the foundation; individual-app UX refinements ride on top.

---

## Scope

### In scope

- **Two new tables** — `sessions` and `session_participants`, with RLS
- **Session lifecycle RPCs** — start, join, leave, transfer manager, reclaim orphan, admin force-reclaim, update participant role, update queue position, self-promote, end session
- **Role manifest per app** — declarative config (admission_mode, capacity, pre_selection keys, turn_completion) declared by each app
- **Karaoke integration** — stage/singer/audience read session state; singer queue with pre-selections; manager/host override hooks
- **Games integration** — tv.html/player.html use session_participants; per-game admission_mode declarations; obsoletes the `?mgr=1` URL mechanism
- **Proximity self-declaration UX** — "Are you at home?" prompt gated by app-level `ask_proximity` flag; no wifi hints, no dev override in Phase 1
- **`shell/realtime.js` extraction** — Part 1 prerequisite; eliminates inline duplication before Session 5 adds five new events

### Out of scope (explicitly)

- **TV-to-TV cross-household connectivity** — Phase 2+. Session 5 is single-TV sessions only.
- **Time-windowed admission mode** — `wait_for_next` covers most use cases. Add only if real demand surfaces.
- **Polished singer/player queue UI** — plumbing only in Session 5. UI refinement is a follow-up session per-app.
- **Audience back-to-Elsewhere navigation UX** — separate DEFERRED entry. Session 5's role manifest clarifies audience semantics; the button/UX work picks up afterward.
- **Wellness app implementation** — app doesn't exist yet. Schema supports `app = 'wellness'` for future.
- **Full room code removal** — room codes remain as presentational backup on the sessions table. Future session removes.
- **Games `?mgr=1` URL bug standalone fix** — obsoleted by Session 5's session_participants lookup; no separate fix needed.

### On ship, also do

Mark the following DEFERRED entries as **Completed in Session 5**:
- "Per-app role manifest for multi-user sessions" (High)
- "Multi-phone session coordination + session manager role" (High)
- "Proximity self-declaration" (High)
- "Session manager inactivity + household-admin override" (High)
- "Extract publishExitApp + related realtime helpers into shell/realtime.js" (Low — closed via Part 1)

Leave open (Session 5 does not close):
- "Audience back-to-Elsewhere navigation" — role manifest clarifies semantics; implementation picks up after
- "Phone-based household pre-invites (SMS verification)" — Session 4.10.1 scope, not Session 5

---

## Architecture decisions (explicit answers, no punting)

### 1. Universal model — applies to ALL apps

Session 5's session + participants + queue schema is THE coordination model for every app in the platform, including wellness (when it ships) and any future app. Apps do NOT fork their own session logic. They parameterize behavior via a role manifest declared per-app.

This forecloses a tempting but dangerous path: each app inventing its own multi-user state ("karaoke has singer_queue table, games has game_sessions table, wellness has classes table"). That path leads to N² coordination code and makes cross-app features impossible.

### 2. Schema shape — two new tables

**`sessions`** — one row per active session on a given TV:

```sql
create table sessions (
  id                uuid primary key default gen_random_uuid(),
  tv_device_id      uuid not null references tv_devices(id) on delete cascade,
  app               text not null check (app in ('karaoke', 'games', 'wellness')),
  manager_user_id   uuid not null references auth.users(id),
  started_at        timestamptz not null default now(),
  last_activity_at  timestamptz not null default now(),
  room_code         text,                     -- presentational backup
  current_state     jsonb not null default '{}'::jsonb,
  capacity          int,                      -- nullable; null = unlimited
  ended_at          timestamptz               -- null = still active
);

-- at most one active session per TV
create unique index sessions_one_active_per_tv
  on sessions(tv_device_id) where ended_at is null;
```

**`session_participants`** — one row per user per session:

```sql
create table session_participants (
  id                 uuid primary key default gen_random_uuid(),
  session_id         uuid not null references sessions(id) on delete cascade,
  user_id            uuid not null references auth.users(id) on delete cascade,
  control_role       text not null check (control_role in ('manager', 'host', 'none')) default 'none',
  participation_role text not null check (participation_role in ('active', 'queued', 'audience')) default 'audience',
  pre_selections     jsonb not null default '{}'::jsonb,
  queue_position     int,                    -- null when not queued
  joined_at          timestamptz not null default now(),
  left_at            timestamptz             -- null = still in session
);

-- at most one manager per session at a time
create unique index session_participants_one_manager
  on session_participants(session_id)
  where control_role = 'manager' and left_at is null;
```

No new columns on `household_members`; household roles stay where they are.

### 3. Two independent role axes

Every participant has two roles on two orthogonal axes.

**`control_role`** — who has authority over the session:
- `manager` — exactly one per active session. Created by the user who originated the session. Transferable. Can always override active participants.
- `host` — zero or more. Assigned by the manager. Equivalent powers to manager for the session's duration, EXCEPT host cannot transfer the manager role.
- `none` — default for everyone else.

**`participation_role`** — what they're doing right now:
- `active` — currently performing/playing whatever the app defines as primary engagement
- `queued` — waiting to become active
- `audience` — present but not trying to perform (default)

Mutually exclusive within the `participation_role` axis at any moment. The two axes are independent: e.g., `control_role=host, participation_role=audience` (host observing) or `control_role=none, participation_role=active` (regular participant performing).

Rationale for decoupling: a manager should be able to step away from the mic (no longer `active` singer) without losing authority to change venue or end the song.

### 4. Admission modes — declared per-app in role manifest

Four admission modes govern how queued users become active:

| Mode | Behavior | Example app |
|------|----------|-------------|
| `manager_approved_single` | Manager picks one queued user at a time to promote | Karaoke singer; Pictionary artist |
| `manager_approved_batch` | Manager can admit multiple queued users on command | Some board games, Euchre lobby |
| `wait_for_next` | Queued users admitted together as the next round/event starts | Trivia rounds; wellness classes that can't admit mid-session |
| `self_join` | Queued users auto-promote when capacity allows; `capacity=null` = unlimited | Large party games, large wellness sessions |

Each app declares its mode in a role manifest. The session layer reads the manifest when setting up a new session for that app.

The manifest shape (exact serialization format resolved at Part 1 implementation per Open Question):

```
{
  app: "karaoke",
  ask_proximity: true,
  admission_mode: "manager_approved_single",
  capacity: 1,
  pre_selection_schema: { song: {...}, venue: {...}, costume: {...} },
  turn_completion: "app_declared",
  roles: {
    manager:  { ... },
    host:     { ... },
    active:   { ... },
    queued:   { ... },
    audience: { ... }
  }
}
```

The `roles` object defines per-role properties other than proximity (capacity per role if needed, UI labels, permissions, etc.) but does NOT contain a `requires_proximity` field per role — proximity is an app-level concern per Decision 8.

### 5. Self-join semantics (when `admission_mode = self_join`)

- **Capacity** — nullable integer column on `sessions`. Null = unlimited. When null, queue is effectively a pass-through (users go directly to `active`).
- **Queue order** — FIFO. Not parameterized in Phase 1.
- **Re-entry after leaving `active`** — user goes to end of queue. Cooldown enforcement deferred.
- **Turn-completion modes** (declared per app):
  - `app_declared` — the app emits a "turn complete" signal when the active user's turn ends. Platform promotes the next queued user.
  - `indefinite` — active user stays until they explicitly leave or the manager removes them.
  - `timed` — deferred (not Phase 1).
- **Queue visibility** — position + identity of queued users + identity of active user(s) all visible to every participant. No private queues in Phase 1.

### 6. Pre-selection metadata — generic JSON

`session_participants.pre_selections` is a generic `jsonb` column. The platform stores but does not inspect. Apps define their own schema:

- **Karaoke:** `{ song: {...}, venue: {...}, costume: {...} }`
- **Games:** infrastructure exists; no specific schema defined in Session 5 (apps add as needed)
- **Future apps:** whatever makes sense

Pre-selections load when a user transitions from `queued` to `active` (or from joining directly to `active` in non-queue flows). The consuming app reads the JSON at transition time.

### 7. Manager mechanics

- **Session originator = initial manager.** First user to tap an app tile on the phone-as-remote `screen-tv-remote` creates the session via `rpc_session_start`. That user's row gets `control_role='manager'`.
- **Explicit transfer** — manager calls `rpc_session_transfer_manager(session_id, to_user_id)`. Target must be an existing participant. Old manager becomes `control_role='none'` unless separately designated host.
- **Manager leaves** — when current manager's row gets `left_at` set, role auto-promotes to first host (by `joined_at` ascending). If no hosts, promotes to first non-audience participant. If none, session ends.
- **Inactivity orphan** — `last_activity_at` older than 10 minutes → session orphaned. Any household member of the TV's household can call `rpc_session_reclaim_manager`. Threshold fixed at 10 min in Phase 1.
- **Household admin force-reclaim** — separate RPC `rpc_session_admin_reclaim`. Requires `household_members.role='admin'` on the TV's household. Works regardless of inactivity. The "head of household yanks the remote" escape hatch.

### 8. Proximity self-declaration ("Are you at home?") — per-app setting

Proximity requirement is a property of the app, not of individual roles. Each app declares a single flag in its role manifest:

- `ask_proximity: true` — prompt fires on first session interaction
- `ask_proximity: false` — never prompts

**Per-app defaults:**
- Karaoke: `ask_proximity: true` (singer needs to be at the TV for camera projection)
- Games: `ask_proximity: false` (players can play from anywhere)
- Wellness: `ask_proximity: true` (form tracking needs camera; when app lands)

**Prompt behavior when `ask_proximity = true`:**
- First interaction with app per session → prompt "Are you at home?"
- User taps **Yes** → proceeds to their intended role. No additional confirmation.
- User taps **No** → confirm dialog: "Confirming you're not home. You'll join as audience. Continue?" → Confirm routes to audience; Cancel returns to prompt.

**No enforcement beyond role routing.** A user who answers "Yes" but isn't actually at the TV will have their turn fail gracefully when the app tries to use the local camera (no video projected, no crash). Manager/host can skip them or cancel their turn. This is consistent with Phase 1's tolerance for manual-recovery seams.

**Recovery:** a user who answered "No" incorrectly can log out and re-enter to get the prompt again. No separate "change proximity" UI.

**Not included in Phase 1:**
- Wifi-based proximity hints (SSID matching, public IP) — simplifies implementation; accepts re-prompt overhead
- Role-level proximity requirements — per-app flag covers all cases cleanly
- Auto-detection of actual proximity — trust-based, not enforced

### 9. Realtime events — single channel, no forking

All Session 5 events ride the existing `tv_device:<device_key>` channel. No new channels. Consistent with the 4.10 → 4.10.2 → 4.10.3 pattern; extending it keeps all session coordination on one subscription per TV.

New events added in Session 5:

| Event | Payload | Fired by |
|-------|---------|----------|
| `session_started` | `{session_id, app, manager_user_id, room_code}` | Phone on `rpc_session_start` |
| `manager_changed` | `{session_id, new_manager_user_id, reason}` | Phone (transfer) or TV (orphan reclaim) |
| `participant_role_changed` | `{session_id, user_id, control_role?, participation_role?}` | Whoever made the change |
| `queue_updated` | `{session_id}` | Consumers re-fetch queue state |
| `session_ended` | `{session_id, reason}` | Whoever ended it |

Existing events unchanged: `session_handoff`, `launch_app`, `exit_app`.

### 10. `shell/realtime.js` extraction happens in Part 1

Before adding any of the new events inline, Part 1 extracts the existing publish/subscribe boilerplate into `shell/realtime.js`. Rationale: adding five new events to multiple in-app pages each inline would compound the duplication documented in the DEFERRED entry. Extract first, add events through the helper.

Reference: DEFERRED "Extract publishExitApp + related realtime helpers into shell/realtime.js" (filed at 4.10.3 session-end, commit `08695cd`).

### 11. Room code migration strategy

- Sessions have UUID identity (`sessions.id`). This is the canonical session reference everywhere in code.
- `sessions.room_code` column retains a human-readable code for UX where useful (lobby displays, share links, etc.). Presentational only.
- UI treatment: de-emphasize room codes. Smaller display, less prominent placement. Don't remove entirely — users have learned to reference room codes in friends-and-family contexts.
- Full room code removal is a future session (not Session 5).

### 12. Games `?mgr=1` URL param — obsoleted naturally

The pre-Session-5 `?mgr=1` URL param on `games/player.html` (used by 4.10.2's phone-as-remote launch flow) is replaced by `session_participants.control_role` lookup. player.html on load checks: am I in this session's participants? If yes, what's my control_role? Branch UI accordingly.

This closes the pre-existing "Games deep-link auto-manager bug" (tracked as a Pre-Session-5 Blocker in DEFERRED's Migrated section) without a separate fix.

---

## Data model

### Tables

See Architecture Decision 2 for `sessions` and `session_participants` definitions.

### RLS sketch

Full policy text finalized during implementation. Rough shape:

- **`sessions`** — read by anyone who is a participant (via a join on `session_participants`) OR a household member of the TV's household. Direct writes blocked at table level; all mutations go through RPCs.
- **`session_participants`** — read by anyone in the same session + household admins of the TV's household. Direct writes blocked; all mutations go through RPCs.

All mutations go through RPCs. No direct inserts/updates/deletes from client.

### RPCs

Core surface:

- `rpc_session_start(p_tv_device_id uuid, p_app text, p_admission_mode text, p_capacity int, p_ask_proximity boolean, p_turn_completion text, p_room_code text default null) → sessions` — creates session; inserts caller as manager. (Manifest values are client-supplied rather than server-resolved; this was the implementation choice at Part 1b.1 — the pre-1b.1 spec assumed a 2-param server-manifest-lookup form.)
- `rpc_session_join(p_session_id uuid, p_participation_role text) → session_participants` — adds caller; enforces proximity gate for non-audience roles
- `rpc_session_leave(p_session_id uuid) → session_participants` — sets caller's `left_at`
- `rpc_session_end(p_session_id uuid) → sessions` — manager-only; sets `ended_at`
- `rpc_session_transfer_manager(p_session_id uuid, p_to_user_id uuid) → sessions` — manager-only
- `rpc_session_reclaim_manager(p_session_id uuid) → sessions` — any household member; enforces orphan check (`last_activity_at < now - 10min`)
- `rpc_session_admin_reclaim(p_session_id uuid) → sessions` — household admin only; bypasses orphan check
- `rpc_session_update_participant(p_session_id uuid, p_user_id uuid, p_control_role text default null, p_participation_role text default null, p_pre_selections jsonb default null) → session_participants` — manager/host only; null args = unchanged
- `rpc_session_update_queue_position(p_session_id uuid, p_user_id uuid, p_new_position int) → session_participants` — manager/host only
- `rpc_session_promote_self_from_queue(p_session_id uuid) → session_participants` — caller-initiated; works only when session is in `self_join` admission_mode AND capacity allows

RPC bodies handle all permission checks and proximity gating. Realtime broadcast emission is client-side — callers publish the relevant event via shell/realtime.js after the RPC returns successfully. (The pre-1b.1 spec assumed server-side emission from inside RPC bodies; Part 1b.1 shipped client-publish instead. See the emission matrix in shell/realtime.js header.) Client-side realtime handlers react to broadcasts but do not duplicate authority checks.

---

## Parts breakdown

Each Part is a review pause-point with clear entry/exit criteria. Rough commit count per Part in parentheses.

### Part 1 — Schema + RPCs + shell/realtime.js extraction (2–3 commits)

**Entry:** current main HEAD or descendant. Session 4.10.1 is orthogonal; Session 4.11 technically required for the admin force-reclaim RPC to have a meaningful admin UI, but the RPC itself can ship standalone.

**Work:**
- **1a** — `db/008_sessions_and_participants.sql`: new tables, RLS policies, indexes. Apply and verify in Supabase SQL editor.
- **1b** — RPC set (see Data model § RPCs). Verify each callable with correct permission enforcement.
- **1c** — Extract `shell/realtime.js`. Move `publishSessionHandoff`, `publishLaunchApp`, `publishExitApp`, and the TV-side `handleSessionHandoff`, `handleLaunchApp`, `handleExitApp` out of their current inline locations into the shared module. Consumers reduce from ~30 inline lines each to ~3-line calls.

**Exit:**
- Migration applied; RPCs callable from SQL editor with correct permission enforcement
- All pre-existing realtime consumers work unchanged (regression-tested via 4.10.2 + 4.10.3 flows — claim, launch, back-to-home)

**Files touched:**
- New: `db/008_sessions_and_participants.sql`, `shell/realtime.js`
- Modified: `index.html`, `tv2.html`, `karaoke/singer.html`, `karaoke/stage.html`, `games/player.html`, `games/tv.html` (each imports + uses shell/realtime.js)

### Part 2 — Karaoke integration (1–2 commits)

**Entry:** Part 1 complete.

**Work:**
- Define karaoke role manifest: `admission_mode: 'manager_approved_single'`, `capacity: 1`, `pre_selection_schema: { song, venue, costume }`, `turn_completion: 'app_declared'`, `ask_proximity: true`
- `karaoke/stage.html`: read session state on load (not just room code). Render queue state. React to `participant_role_changed` + `queue_updated` realtime events.
- `karaoke/singer.html`: queue entry flow, pre-selection save on queue join, render of queue position. Manager UI for promote-next-singer. Host UI for override actions (change venue mid-song, end song).
- `karaoke/audience.html`: read-only participant; joins as `audience` role; no control_role.
- Active singer's `pre_selections` loads at `queued → active` transition.

**Exit:** Multi-singer karaoke flow works end-to-end. Manager approval path works. Host override works. Active-singer transitions replay pre-selections.

**Files touched:** `karaoke/stage.html`, `karaoke/singer.html`, `karaoke/audience.html`. No DB changes.

### Part 3 — Games integration (2–3 commits)

**Entry:** Part 2 complete (karaoke proves the pattern).

**Work:**
- Define role manifest per game engine (all with `ask_proximity: false`):
  - **Last Card** — `admission_mode: 'wait_for_next'` or `'manager_approved_batch'` (implementation-time call; both supportable), `capacity: 8` (approximate)
  - **Trivia** — `admission_mode: 'self_join'`, `capacity: null` (unlimited)
  - **Euchre** — `admission_mode: 'manager_approved_batch'`, `capacity: 4`
  - **Pictionary (when it lands)** — `admission_mode: 'manager_approved_single'` for artist role, `self_join` for guessers
- `games/tv.html` + `games/player.html`: replace `?mgr=1` URL param check with `session_participants` lookup
- Retire ad-hoc Agora-broadcast lobby state; lobby becomes a `session_participants` query
- Manager override hooks: interrupt turn, skip active, end game mid-round

**Exit:** Games flow works with session_participants. Grep for `?mgr=1` / `urlP.get('mgr')` in games/ should return zero matches post-Part-3.

**Files touched:** `games/tv.html`, `games/player.html`, `games/engine/*.js`

### Part 4 — Proximity self-declaration UX (1–2 commits)

**Entry:** Part 3 complete.

**Work:**
- New shell screen `screen-proximity` (or inline modal) that poses "Are you at home?"
- First-interaction detection per session: if the target app's manifest has `ask_proximity: true` and user hasn't answered yet this session, prompt before proceeding with any session interaction
- **Yes** path: proceed to the intended role (whatever the user requested — manager/host/active/audience)
- **No** path: confirm dialog ("Confirming you're not home. You'll join as audience. Continue?") → route to `audience` on confirm; return to prompt on cancel
- Recovery path: user re-enters session after logout to get the prompt again (no dedicated "change proximity" UI per Decision 8)

**Exit:** Proximity prompt fires correctly when and only when the target app's `ask_proximity=true`. Yes/No routing works. Apps with `ask_proximity=false` never show the prompt.

**Files touched:** `index.html` (new screen + JS)

### Part 5 — Verification (1 commit)

**Entry:** Parts 1–4 complete.

**Work:**
- Create `docs/SESSION-5-VERIFICATION.md` patterned on prior verification docs
- **Requires 2+ test Supabase accounts** — finally unblocking the Part E Flows 3+4 DEFERRED entry from Session 4.10
- Flows:
  1. **Multi-user karaoke** — two users join, queue ordering, manager approves, singer change mid-song (host override)
  2. **Multi-user game (Trivia)** — self-join flow, unlimited capacity, game state sync across all participants
  3. **Manager transfer** — explicit transfer, old manager loses powers, new manager gains them
  4. **Orphaned session reclaim** — manager leaves, 10-min wait, other household member reclaims
  5. **Household admin force-reclaim** — admin overrides regardless of inactivity
  6. **Proximity gate** — on karaoke (`ask_proximity=true`), "Yes" user can take control roles; "No" user lands on audience via confirm dialog. On games (`ask_proximity=false`), prompt never fires.
  7. **Cross-app isolation** — karaoke session on TV A, games session on TV B simultaneously; no cross-talk
  8. **Regression** — all 4.10.2 + 4.10.3 flows still work (forward launch, back-to-home, post-claim auto-route, etc.)

**Exit:** All flows pass on real hardware. Verification doc committed.

**Files touched:** new `docs/SESSION-5-VERIFICATION.md`

---

## Verification approach

Patterned on `docs/PART-E-VERIFICATION.md` + `docs/SESSION-4.10.3-VERIFICATION.md`. Multi-user flows are the differentiator — Session 5 is the first session that genuinely needs 2+ test accounts.

The Part E Flows 3+4 DEFERRED entry ("guest access + pre-invited member verification") becomes directly testable during Session 5's verification; fold those flows in or close them as a side effect.

---

## Deferred items likely to emerge

Pre-log so we catch them during session-end ritual:

- **Polished singer queue UI** — Session 5 ships queue plumbing only. Visualization, drag-reorder, skip-ahead affordances, etc. are polish for a follow-up session.
- **Polished player queue UI per game** — same pattern; per-game polish.
- **Time-windowed admission mode** — if real demand surfaces post-ship.
- **Cooldown on re-entry** — if abuse patterns surface (e.g., one user repeatedly grabs the mic).
- **Queue concurrency edge cases** — two users call `rpc_session_promote_self_from_queue` simultaneously at capacity=1; only one succeeds. Handler mechanics and UX for the losing request.
- **Role manifest format refactor** — if the JS-object approach turns out awkward in practice, move to a JSON file or DB table in a future refactor.
- **Wifi-based proximity hints** — if the once-per-session re-prompt overhead becomes annoying after real usage, revisit wifi SSID / public-IP fingerprinting as an optimization. Phase 1 accepts the overhead.
- **Audience back-to-Elsewhere button** — carried forward from 4.10.3. Session 5's role manifest clarifies audience semantics; implementation picks up after Session 5 ships.
- **Full room code removal** — future session.
- **Games `?mgr=1` obsolescence cleanup** — Part 3 removes consultation of the param. Dead code (the mgrCheck UI element, the URL parsing) may need a follow-up cleanup commit.
- **Timed turn-completion mode** — `self_join` apps that want auto-timeout per turn (e.g., "30 seconds per drawing").

---

## Open questions for implementation

Genuinely code-level — can't be resolved in planning. Kept minimal.

- **Exact `sessions.current_state` JSON schema per app** — each app defines its own (karaoke stores YouTube video_id + playback position; games stores current turn, cards, etc.). Schemas emerge during integration; don't pre-specify.
- **Queue position recalculation on participant leave/reorder** — the naive "UPDATE all rows with higher position by -1" works but has concurrency concerns. Implementation may prefer a gap-tolerant ordering (e.g., positions 10, 20, 30 with inserts at 15, 25). Resolve at code-time.
- **Role manifest file location** — single JSON at `shell/role-manifests.json` vs per-app JS modules (one next to each app's entry HTML) vs DB table. Pick at Part 1 implementation time based on what fits cleanest with the existing app structure.

---

## Related existing architecture

- **Two-device model for TV** — unchanged. TV is the display; phone is the remote. Session 5 adds a formal session identity on top; the device model below is untouched.
- **Session handoff via realtime channel** — single `tv_device:<device_key>` channel pattern established in Session 4.10 Part C. Session 5 adds five new events to the same channel. No channel forking.
- **Phone-as-remote model** — Session 4.10.2's core UX (n=1 skip, display-only TV grid, phone navigates into participant app). Session 5 layers session state on top without changing the forward-flow UX.
- **Household + TV device model** — Session 4.10's tables (`households`, `tv_devices`, `household_members`, `pending_household_invites`) stay unchanged. Session 5 adds `sessions` + `session_participants` referencing `tv_devices` and `auth.users`.
- **DEFERRED tolerates-manual-recovery philosophy** — Session 5 inherits Phase 1's posture of accepting manual-refresh recovery for realtime failures, rather than building heartbeat/reconnect complexity.
