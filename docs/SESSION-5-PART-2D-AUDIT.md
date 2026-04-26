# Session 5 Part 2d Pre-Implementation Audit

**Created:** 2026-04-26
**Purpose:** Pre-implementation audit for Session 5 Parts 2d.0 (database migration) and 2d.1 (karaoke/stage.html session integration). Verifies technical defaults against existing code, locks decisions, and defines the section-by-section implementation plan.
**Pattern:** Same approach as the chat-only 2c.3 audit, captured here as a durable artifact (modeling docs/KARAOKE-FUNCTION-AUDIT.md).
**Spec sources:** `docs/KARAOKE-CONTROL-MODEL.md` § 4.2 + § 5.1, `docs/SESSION-5-PART-2-BREAKDOWN.md` § 2d.1, `docs/KARAOKE-FUNCTION-AUDIT.md`.
**Investigation HEAD:** `d2d430f`.

---

## Summary

2d.1 was originally scoped as a stage.html-only change adding session-aware read/display. The audit surfaced two hard blockers (B1 cross-user RPC permission, B2 profiles RLS) that require new server-side RPCs. These RPCs ship as a prerequisite migration **2d.0** (`db/013_karaoke_session_helpers.sql`) before 2d.1 implementation begins.

The audit also collapsed 2d.2 into 2d.1 (manager override UI moved off stage.html per the Karaoke Control Model), expanded 2d.1 with two small migration-window improvements (room code override, Agora session-ended grace), and locked 13 implementation decisions covering schema reads, realtime subscription pattern, song-end RPC contract, double-fire guarding, solo-mode tolerance, and teardown behavior.

**Estimated implementation time:** 2d.0 ~1-1.5 hours, 2d.1 ~3-4 hours, plus verification.

---

## Locked decisions

### DECISION-AUDIT-1 — Stage.html owns song-end → role transition trigger

When the YouTube video on stage.html ends, stage.html calls `rpc_karaoke_song_ended(p_session_id)` (new RPC, ships in 2d.0). The RPC atomically transitions just-finished active singer to `audience` and queue head from `queued` to `active`. Stage.html then publishes `participantRoleChanged` and `queueUpdated` events.

"Read-only" in 2d.1 means **no user-input mutators**, not "no mutators at all." Event-driven mutations (responding to internal events like song-end, or to received realtime events) are part of 2d.1's scope.

### DECISION-AUDIT-2 — 2d.2 collapses into 2d.1

Original 2d.2 scope (manager override UI on stage.html for venue/costume mid-song, end song button) is moved off stage.html per Karaoke Control Model § 4.2. Remaining 2d.2 work (pre_selections loading on promotion, end-session navigation, song-end RPC) folds into 2d.1.

2d.1 final estimate: ~6-8 sections, ~3-4 hours.

### DECISION-AUDIT-3 — Three-value `participation_role` schema is sufficient

`participation_role` (enum: `active` / `queued` / `audience`) is the platform schema and stays unchanged. Karaoke's UI labels (Session Manager, Active Singer, Available Singer, Audience) are derivations on top, computed in client code.

Eligibility (HHU + at-home + has TV device) is a **client-side, self-only derivation**. Each user computes their own eligibility for their own UI. No cross-user eligibility check is ever required because Session Manager only promotes from queue, and queue entry is self-gated by eligibility.

### DECISION-AUDIT-4 — Unified queue list

Queue list content is identical across stage.html queue panel and Session Manager phone UI: avatar + name + position + song + venue. Active Singer highlighted with avatar ring + label. Single rendering component, single data source. Action affordances (reorder, remove, force-promote) are role-gated overlays in singer.html (2e), not in 2d.1.

### DECISION-AUDIT-5 — Solo mode behavior

When stage.html loads with no active session for this `tv_device_id`:

- Queue button stays visible in `#ctrl` cluster (consistent with existing buttons)
- Queue panel renders empty placeholder
- "Up Next" card and 360° tour overlay don't activate
- Realtime subscriptions skipped
- Song-end RPC skipped
- Console warning logged
- Existing pre-Session-5 functionality (Way 1: QR + Agora room code) preserved verbatim

Way 1 itself is **not removed** in 2d.1. Captured as a post-Session-5 cleanup item in DEFERRED.md.

### DECISION-AUDIT-6 — Two new RPCs ship as 2d.0 in `db/013`

Prerequisite migration before 2d.1 implementation:

**`rpc_karaoke_song_ended(p_session_id uuid)`** — Atomic dual transition. Internally:
1. Finds current `participation_role='active'` participant; transitions to `audience`
2. Finds queue head (`participation_role='queued'`, lowest `queue_position`, `left_at IS NULL`); transitions to `active`
3. Returns updated session state
4. Idempotent (per DECISION-AUDIT-13)

Auth gate: `SECURITY DEFINER`; gate via `is_session_participant(session_id) OR is_tv_household_member(tv_device_id)` (broad enough to include stage.html's TV-claimer auth context).

**`rpc_session_get_participants(p_session_id uuid)`** — Returns participant rows with `display_name` joined from profiles. Bypasses owner-only profiles RLS via SECURITY DEFINER.

Returned fields per row: `user_id`, `control_role`, `participation_role`, `queue_position`, `pre_selections`, `joined_at`, `display_name`.

Auth gate: same as `rpc_karaoke_song_ended`.

### DECISION-AUDIT-7 — Routine resolutions

**B3 (avatars):** Use existing `avatarInitialsForName` + `avatarClassForName` pattern from contacts (`index.html` lines 3534, 3544). Initials + color hash. No `profiles.avatar_url` column added.

**B4 (pre_selections JSON shape):**
```json
{
  "song":    { "video_id": "...", "title": "...", "artist": "...", "thumbnail_url": "..." },
  "venue":   { "id": "...", "name": "..." },
  "costume": { "effect_id": "...", "name": "..." }
}
```
2d.1 reads `song` and `venue` only. `costume` reserved for singer.html UI in 2e. 2e will be the first writer.

**B5 (realtime publishing):** Stage.html publishes `publishParticipantRoleChanged` + `publishQueueUpdated` after RPC success, mirroring `index.html` lines 3134-3137 pattern. Try/catch + log + continue; no retry.

**B6 (double-fire guard):** Module-scoped `_currentSongInstanceId` set in `ytPlaySong()` to `videoId + ':' + ytSongStartTime`. Claimed-and-cleared at top of `doEnd()`. Guards both YT-ENDED and Stop-button entry paths.

### DECISION-AUDIT-8 — Subscription pattern mirrors 2c.3.1

New helpers `startStageRealtimeSub(device_key)` / `stopStageRealtimeSub()` modeled exactly on `index.html`'s `startHomeRealtimeSub` / `stopHomeRealtimeSub` (lines 2487-2546):

- Module-scoped `_stageRealtimeChannel` + `_stageRealtimeChannelDeviceKey`
- Idempotent start (no-op if already subscribed to same key)
- Three event handlers on one channel: `participant_role_changed`, `queue_updated`, `session_ended`
- All three handlers re-query (no payload parsing — DECISION-6 from 2c.3.1)
- 5s timeout + settled flag + 3-state-check ceremony copied verbatim
- Silent failure degrades to cold path
- Subscription lifecycle: bound to loaded session, NOT to queue panel open/close (Pattern A)

### DECISION-AUDIT-9 — Two channel instances coexist on stage.html

Don't refactor `wireExitAppListener`. The new subscription is an independent channel instance. Both target `tv_device:<device_key>`; server-side multiplexing handles the rest.

### DECISION-AUDIT-10 — session_ended graceful teardown (Option B)

On `session_ended` received:
1. Call `doEnd()` to wind down any active song (existing teardown code path)
2. Call `stopStageRealtimeSub()` to clean up the realtime subscription
3. Navigate to `../tv2.html`

### DECISION-AUDIT-11 — Room code override from DB

On session load, override the room code displayed in `idle-panel` and singer-link QR with `sessions.room_code` from the loaded session row. Falls back to URL `ROOM_CODE` in solo mode.

Affected lines (per Area 4 finding): stage.html line 4032 (singer link generation) and line 4033 (`#idle-room-code` text).

### DECISION-AUDIT-12 — Migration-window grace via Agora `session-ended` message

Before stage.html teardown on `session_ended`:
- Stage.html sends `sendMsg({type:'session-ended'})` Agora data message
- Singer.html handles it as a sibling to existing `song-ended` handler (line 688): mute mic + return to screen-home

This adds ~5 LOC to stage.html (in `session_ended` handler) and ~5 LOC to singer.html (in `handleStageMsg`). Net effect: when manager ends session mid-song, singer's phone updates gracefully even before 2e adds proper Supabase realtime subscription.

This is the only 2d.1 change that touches singer.html. Cleanly removed in 2e if redundant.

### DECISION-AUDIT-13 — RPC idempotency requirement for 2d.0

`rpc_karaoke_song_ended` handles edge cases gracefully:
- No active singer in session → no demotion needed; proceed to promotion check (or no-op)
- No queue head → no promotion needed; demote-only behavior
- Both empty → no-op return without error
- Same `session_id` called twice rapidly (multi-tab race) → second call sees state already advanced and no-ops

Returns the current session state row in all cases (callers can detect no-op via comparison if needed).

---

## Findings by area

### Area 1 — stage.html integration points

**File size and structure (verified at HEAD `d2d430f`):**
- `karaoke/stage.html` is 5,254 lines (matches `KARAOKE-FUNCTION-AUDIT.md`)
- Bottom-right cluster: `#ctrl` at line 406, `position:fixed`, flex layout, 8 visible buttons
- Comments panel: `#comment-bar` at line 370, `position:fixed`, slide-out via transform + class toggle (lines 145-158)
- Idle panel: `#idle-panel` at lines 339-350, gated on `ARRIVED_VIA_QR` constant (line 587)

**Boot sequence:**
- `enterStage()` defined at lines 3973-4014, idempotent via `_called` flag
- Triggered by user click on "Step on Stage →" at line 545 (only user-gesture entry)
- Auto-init before user gesture: shell module imports (lines 13-15), constants (lines 580-587), `wireAdminAuth()` (lines 5188-5195), `wireUp()` (lines 5247-5251)
- 2d.1 session-load fits as sibling to `wireAdminAuth` — auth-bound, not gesture-bound

**YouTube + song-end:**
- Player created at line 3575 inside `window.onYouTubeIframeAPIReady`
- Song-end detected via `onStateChange` handler (lines 3603-3632), ENDED branch
- `doEnd()` at lines 3859-3875 — reentrant from ≥3 call sites (YT ENDED, Stop button, singer `'end'` echo)
- Existing `sendMsg({type:'song-ended'})` at line 3867 — **must be preserved** (singer.html depends on it)

**Existing realtime wiring:**
- Only `wireExitAppListener` registered at line 5245
- `onExit` handler at lines 5216-5242 — canonical pattern for `device_key → tv_devices.id → sessions` lookup chain
- Zero existing Supabase realtime subscriptions; 2d.1 introduces the first
- Five existing Supabase queries (lines 4934, 5036, 5037, 5222, 5225) — all use `.maybeSingle()`, try/catch + fallback

### Area 2 — Realtime handler patterns

**`shell/realtime.js` surface:**
- 9 publishers exposed on `window` (4 pre-Session-5 + 5 Session 5)
- Only one specialized subscriber helper: `wireExitAppListener` (purpose-built for `exit_app`)
- No generic subscribe-and-teardown helper; consumers manage channel lifecycle inline
- Event emission matrix in file header (lines 29-47)

**Canonical subscription pattern:** `index.html`'s `startHomeRealtimeSub` / `stopHomeRealtimeSub` (lines 2487-2546). 2d.1 mirrors exactly.

**`wireExitAppListener` known limitation:** Auto-tears-down channel BEFORE invoking `onExit` callback (lines 209-213). If `onExit` decides to stay (session active), the `exit_app` subscription is gone. Phase-1 recovery seam, documented at `stage.html` lines 5210-5215. 2d.1's new channel is independent and not affected.

**Channel naming:** `tv_device:<device_key>` is the only Supabase realtime topic across the codebase. Verified.

**Multi-consumer pattern:** Each `sb.channel(topic)` call creates an independent instance; server-side multiplexing handles routing. 2d.1's new channel coexists with `wireExitAppListener`'s channel without interference.

### Area 3 — RPC / query contract verification

**Sessions table (`db/008` lines 41-67):** 11 columns including `tv_device_id`, `app`, `manager_user_id`, `started_at`, `last_activity_at`, `room_code`, `current_state` (jsonb), `admission_mode`, `capacity`, `ask_proximity`, `turn_completion`, `ended_at`. Unique partial index on `(tv_device_id) WHERE ended_at IS NULL` enforces one active session per TV.

**RLS:** SELECT allowed for participants OR household members of the TV's household. Stage.html's TV-claimer auth covers via household membership.

**Session_participants table (`db/008` lines 80-98):** 9 columns. Indexes: one-manager-per-session, one-active-row-per-user-per-session, queue ordering. RLS: SELECT allowed for co-participants or household members.

**`rpc_session_update_participant` (`db/011` lines 65-235):** Cross-user `participation_role` changes require caller to be active participant AND have manager/host role. **This is why DECISION-AUDIT-1 needed the new `rpc_karaoke_song_ended` wrapper.** Stage.html's TV-claimer auth context generally doesn't satisfy these checks.

**Profiles RLS (`db/001` lines 47-50):** Owner-only SELECT. **This is why DECISION-AUDIT-6 needed the `rpc_session_get_participants` SECURITY DEFINER RPC.** Direct or nested-select queries from stage.html see `null` for other users' display_names.

**No existing session_participants reads:** 2d.1 establishes the first read pattern. 2e will be the first writer of `pre_selections`.

**Active session query for 2d.1:**
```javascript
.from('sessions')
.select('id, app, manager_user_id, admission_mode, capacity, room_code, started_at, current_state')
.eq('tv_device_id', tv.id)
.is('ended_at', null)
.maybeSingle()
```

**Participants query for 2d.1:** Calls new `rpc_session_get_participants` (SECURITY DEFINER), receives rows with display_name pre-joined.

**Room code propagation:** `rpc_session_start` → `sessions.room_code` → `publishLaunchApp` → `tv2.html` → URL `?room=` → `stage.html`. Same value at every step in normal flow. Mismatch only happens in dev/direct-nav scenarios.

### Area 4 — Interim-state warnings

**Migration-window scenarios categorized (10 total):**

| # | Scenario | Category | 2d.1 action |
|---|---|---|---|
| 1 | Active singer finishes song | ACCEPTABLE | Preserve existing Agora `song-ended` message |
| 2 | New queue head promoted | DEFERRED to 2e | Document migration-window limitation |
| 3a | Audience on session_ended | ACCEPTABLE | Existing Agora `user-left` covers it |
| 3b | Singer on session_ended | DEFERRED to 2e (but bridged) | DECISION-AUDIT-12: Agora `session-ended` grace |
| 4 | Race on stage.html load | ACCEPTABLE | No race (await chain in handleTvRemoteTileTap) |
| 5 | Solo mode edge cases | DEFENSIVE | Mirror `onExit`'s 3-failure-path pattern |
| 6 | Multiple stage.html instances | DEFENSIVE in B1 RPC design | Idempotency in `rpc_karaoke_song_ended` |
| 7 | Publish failure after RPC | ACCEPTABLE | Try/catch + log + continue |
| 8 | Teardown mid-RPC | ACCEPTABLE | No defensive code; consumers re-query on mount |
| 9 | Room code mismatch | DEFENSIVE (small) | DECISION-AUDIT-11: override from DB |
| 10 | Agora ↔ Supabase divergence | ACCEPTABLE | Already in DEFERRED |

**Migration-window limitations (between 2d.1 ship and 2e ship):**

1. **Queue head promotion is silent on phone.** Newly-promoted users get no notification, no Take Stage prompt, no UI change on screen-home. Manager must verbally cue them. Resolves in 2e.
2. **Session end is silent on singer.html for queued users.** DECISION-AUDIT-12 covers active singer; queued users still get no notification when session ends mid-wait. Resolves in 2e.
3. **Ghost queue head causes stage stall.** If queue head closed their phone, song-end auto-promotes them in DB but stage gets no audio/video. Manager has no in-UI way to skip until 2e. Already in DEFERRED ("Participant cleanup mechanism").
4. **Multi-tab stage.html not user-protected.** Mitigated by RPC idempotency (DECISION-AUDIT-13) and in-tab guard (DECISION-AUDIT-7 B6).
5. **Singer.html doesn't call `rpc_session_join`.** Singers connect via Agora only; no `session_participants` rows are created from their flow. Queue panel stays empty until 2e adds the join flow. Pre-Session-5 Agora-based singing still works. Documented as expected.

---

## Doc updates queued (post-audit)

These doc updates land alongside or after the audit doc commit:

1. **`docs/KARAOKE-CONTROL-MODEL.md` § 1** — Add two-layer vocabulary subsection (one paragraph: `participation_role` is a slot marker; eligibility is app-computed from external state per DECISION-AUDIT-3)
2. **`docs/KARAOKE-CONTROL-MODEL.md` § 2** — Fix Active Singer / queue-empty contradiction (just-finished singer with empty queue transitions to `participation_role='audience'`, UI label "Available Singer")
3. **`docs/KARAOKE-CONTROL-MODEL.md` § 4.2** — Update queue panel content to include song + venue (per DECISION-AUDIT-4)
4. **`docs/KARAOKE-CONTROL-MODEL.md` § 5.1** — Clarify "read-only" framing means no user-input mutators; note 2d.2 collapse
5. **`docs/SESSION-5-PART-2-BREAKDOWN.md`** — Add 2d.0 sub-part; update 2d.1 to reflect collapsed scope; update applied-migrations section to note `db/013` pending
6. **`docs/DEFERRED.md`** — New entry: "Remove Way 1 (pre-Session-5 entry path)" — Low priority, post-Session-5 trigger

These are mechanical applications of decisions already made. Recommended to land as a single doc-update commit cluster after this audit doc commits, before 2d.0 implementation begins.

---

## Section-by-section plan

The implementation plan is held separately (working notes; not committed). After this audit doc lands, the plan defines:

- **2d.0** — Single migration commit with both new RPCs (`rpc_karaoke_song_ended`, `rpc_session_get_participants`); SQL editor verification; total ~1-1.5 hours
- **2d.1** — ~6-8 sections covering session-load wiring, queries, realtime subscription, queue button + panel DOM, queue list rendering, "Up Next" card + idle 360° overlay, song-end RPC + double-fire guard, session_ended teardown; total ~3-4 hours

Section-by-section commits per workflow convention. Each section: propose → pause for review → apply on approval. No diffs in this audit doc.

---

## Open items (non-blocking)

- **Manager Override mechanism (Options A/B/C)** — deferred to 2e per `KARAOKE-CONTROL-MODEL.md` § 5.7 and existing DEFERRED.md entry. Not a 2d.1 concern.
- **Way 1 removal** — captured for post-Session-5 cleanup. Not 2d.1 territory.
- **Audience.html unified-app migration** — frozen for Session 5 per Karaoke Control Model § 4.3. Not 2d.1 territory.
- **2c.x polish items** — separate from 2d.1 (see `SESSION-5-PART-2-BREAKDOWN.md` § 2c.2/2c.3 watch items).

---

## Next actions

1. Commit this audit doc to `docs/SESSION-5-PART-2D-AUDIT.md` (single commit, doc trailer per convention)
2. Apply queued doc updates (4 control-model sections + 1 breakdown + 1 DEFERRED entry) — recommended as a single commit cluster
3. Implement 2d.0 (`db/013_karaoke_session_helpers.sql` + SQL editor verification)
4. Implement 2d.1 section-by-section per the implementation plan

---

## Footer

Audit conducted via Claude Code investigation across four areas: stage.html integration points, realtime handler patterns, RPC/query contract verification, interim-state warnings. Findings synthesized into 13 locked decisions. Two new RPCs (DECISION-AUDIT-6) carved out as prerequisite migration 2d.0 to unblock 2d.1.

Convention: Commit message uses `docs(audit):` prefix. Trailer: `Co-Authored-By: Claude <noreply@anthropic.com>`.
