# 595e004 (karaoke db/025+db/026 schema catch-up) — Verification Result Log

**Commit verified:** `595e004` — "karaoke: catch up singer/stage to db/025+db/026 schema (read + mutation)"
**Run date:** 2026-05-26
**Environment:** prod GitHub Pages + prod Supabase
**Verifier:** Mike Stepanovich (single-user run; caveats below)
**Outcome:** **PASS** — all three checks. One non-blocking pre-existing issue characterized; one observed-and-resolved-on-the-spot item with an optional residual confirmation.

This log records the post-deploy verification of commit `595e004`, which migrated `karaoke/singer.html` and `karaoke/stage.html` off the pre-Phase-3 stale schema (db/025 dropped `sessions.manager_user_id`, `sessions.room_code`, `sessions.tv_device_id`; db/026 re-keyed RPCs from `p_session_id` to `p_room_id`). The verification specifically confirms that the legacy-mode degradation documented in `docs/SESSION-LOGS/ITEMS-5-6-KARAOKE-VERIFICATION-LOG.md` Observation 4 (lines 70–74) is retired.

---

## Outcome — all three checks PASS

### Check 1 — full session-wired entry (creation path)

A karaoke session was created via the production flow:
`index.html` → tap **Karaoke** tile → `screen-karaoke-info` → tap **"Start Karaoke"** → `enterKaraokeStartFlow`.

**Singer side (the session-creator browser):**
- Landed on `screen-home` with the **session-wired role banner** visible: *"🎤 You can sing — pick a song to add to the queue"*. This banner is rendered by `renderSessionUI` (`karaoke/singer.html:2294+`) only when `currentMyRow.participation_role === 'audience'` — meaning `currentMyRow` populated, not null.
- Singer LOG showed `refreshSessionState: session 9bec9ec4-... loaded with N participants; my role=audience` — confirming the full chain (rooms-lookup → sessions-lookup-by-`room_id` → `rpc_session_get_participants({ p_room_id })`) executed end-to-end without 400 or signature mismatch.
- **No "legacy mode" log line** appeared anywhere in the session boot. The pre-595e004 failure mode (`Session: rpc_session_join failed (… function … does not exist … or arg mismatch …) — legacy mode`) did NOT fire.

**Stage side (the TV browser):**
- `tv2.html` received the `launch_app` broadcast on the `tv_device:3df01b1f-...` channel and navigated to `karaoke/stage.html?room=97ER7S`.
- Stage LOG showed `refreshSessionState: session 9bec9ec4-... loaded with 1 participants` — confirming the post-595e004 read chain (rooms by `screen_ref` → sessions by `room_id` → `rpc_session_get_participants({ p_room_id })`) ran cleanly. No `manager_user_id` error, no 400 on the sessions query, no "solo mode" fallback.

The legacy-mode degradation that `ITEMS-5-6-KARAOKE-VERIFICATION-LOG.md:70-74` documented as the inherited PASS state (*"singer.html landed on screen-home with session-level UI dark — out of scope per spec §8"*) is **retired** by this commit.

### Check 2 — mutation path

After landing in session-wired mode (Check 1), the singer selected a song and tapped Start.

**Observed:**
- Singer LOG showed `selfUpdate OK` with the participation_role transition `audience → active`. This is the call at `karaoke/singer.html:2758` (params object built at line 2746) — one of the 7 RPC callers that 595e004 re-keyed from `p_session_id` to `p_room_id`.
- Song lifecycle executed normally: start-countdown → mic acquired → song played to stop-song.
- **None of the 7 re-keyed RPC callers** (`rpc_session_update_participant` × 3 in singer.html, `rpc_session_update_queue_position` × 2 in singer.html, `rpc_karaoke_song_ended` × 1 in singer.html, `rpc_karaoke_song_ended` × 1 in stage.html) produced a 400 or signature-mismatch error in either browser's console.

This is the mutation-side verification that the commit message promised: *"full session-wired mode reaches both read AND mutation paths"*. Confirmed.

### Check 3 — `?code=` rejoin path

A third browser tab navigated directly to `https://mstepanovich-web.github.io/elsewhere/karaoke/singer.html?code=97ER7S`.

**Observed:**
- The deep-link entry triggered `setTimeout(doJoin, 600)` via the existing auto-join IIFE (`karaoke/singer.html:744`).
- doJoin's chain (post-595e004): Agora join → mic init → rooms-lookup by `room_code = '97ER7S'` → sessions-lookup by `room_id` → `rpc_session_join({ p_room_id, p_participation_role: 'audience' })`.
- The `rpc_session_join` call returned **HTTP 409 / SQLSTATE 23505** ("already an active participant in this room"). This is **expected behavior** — the same user already had an active `session_participants` row from the session-creator tab (Check 1). doJoin's 23505 catch handler at `karaoke/singer.html:1063-1067` correctly interpreted this as *"already a participant (page refresh) — refreshing state"* and called `refreshSessionState`.
- `refreshSessionState` then executed the post-595e004 chain successfully: `refreshSessionState: session 9bec9ec4-... loaded ... my role=audience`. `currentMyRow` populated.
- The rejoin tab landed on `screen-home` in full session-wired mode, identical to Check 1's end state.

The 23505 was the design-correct response — `rpc_session_join`'s body (`db/026:132-142`) explicitly raises this error when an active row already exists for the (room, user) pair, and the catch routes doJoin into the page-refresh path that reads the existing row rather than inserting a duplicate. No regression.

---

## Observed, non-blocking — characterized

### singer.html:1010 TypeError

**Symptom:** `Uncaught TypeError: Cannot set properties of null (setting 'textContent') at singer.html:1010:52` — repeated ~7–10 times per session (one per 3-second `setInterval` tick).

**Root cause:** The line at `karaoke/singer.html:1010` calls `document.getElementById('stat-w').textContent = n`. **No `#stat-w` element exists in the markup** — `grep -rn "stat-w"` across the repo returns exactly one hit: the JS reader itself. The element ID was never present (likely a v2.93 directory-restructure orphan — commit `78777690` `git mv`d the file; the `#stat-w` markup either was removed or never carried over; the JS reader was left behind).

**Provenance — NOT a 595e004 regression:**
- `git blame -L 1010,1010 karaoke/singer.html` → commit `9125956a` (mstepanovich-web, 2026-04-12 20:33:18 -0400). Line has been present **six weeks before 595e004** landed.
- `git show 595e004 -- karaoke/singer.html | grep "^@@"` → first hunk at line 1037 (27 lines below 1010). 595e004 did NOT touch the setInterval block.
- `git show 6f907b0 -- karaoke/singer.html | grep "^@@"` → hunks at lines 777 and 978. Did NOT touch line 1010 either.

**Functional impact:** Cosmetic only. The throw on line 1010 aborts the rest of the 3-second interval callback, so lines 1011–1012 (which target `#perf-w` and `#aud-cnt`, both of which DO exist in the markup) never execute — the on-screen "0 watching" labels stay stale at their initial markup value. **No business-logic reader consumes these labels**; the session, mutations, and song playback all read from `currentSession` / `currentMyRow` / `agoraClient.remoteUsers` directly, not from DOM textContent. Verified during this run: the session functioned fully despite ~7–10 console errors per session.

**Tracking:** Three suggested fixes — (a) add the missing `<span id="stat-w">0</span>` to the markup, (b) null-guard the three setters in the callback, or (c) remove the orphan reference entirely — are recorded in this session's investigation transcript. Not blocking this verification. Should be folded into a small follow-up fix or DEFERRED entry; not in scope for 595e004.

---

## Resolved — MANAGE QUEUE in both windows is correct (one optional residual confirmation)

**Conclusion:** the double MANAGE QUEUE observed in this run is **NOT a bug**. It is one manager row rendered faithfully in two windows of the same authenticated user. Single-manager-per-room is structurally enforced by the partial-unique index `session_participants_one_manager` on `(room_id) WHERE control_role = 'manager' AND left_at IS NULL` (`db/008:109-112`, re-keyed from `session_id` to `room_id` by `db/025:232-234`). This was resolved by the read-only role-enforcement investigation run alongside this verification — not an open concern.

**What was observed:** Both the session-creator tab and the `?code=` rejoin tab showed the **MANAGE QUEUE** tile/affordance on `screen-home`.

**Why this is correct:** Both browsers were the same authenticated user (Mike, UID `8984755f-...`). With one user across two windows, the partial-unique indexes guarantee:

- `session_participants_one_manager` → at most one `control_role='manager'` row per room.
- `session_participants_one_active_per_user` → at most one active row per (room, user).

Both windows are therefore reading the SAME backing `session_participants` row — the manager row created by `rpc_room_create` (`db/027:252-257`) when the session was created in Check 1. Both windows correctly resolve `currentMyRow` to that same manager row, and both correctly render MANAGE QUEUE per the UI gate at `karaoke/singer.html:2790` (`isManager = currentMyRow?.control_role === 'manager'`). The DB cannot hold a second `control_role='manager'` row for the same room with `left_at IS NULL` — the partial-unique index would raise SQLSTATE `23505` on the attempt.

This is the structurally right behavior for the multi-window-same-user case: authority is per-row in the schema; the UI renders that row faithfully wherever the user is signed in. The same model supports a single user being signed in on laptop + phone simultaneously.

**Optional residual confirmation (not blocking):** A live two-user test — a DIFFERENT user (not Mike) joining via `?code=` and confirming they do NOT see MANAGE QUEUE — was not performed in this run. Per the schema + `rpc_session_join`'s `INSERT ... control_role='none'` (`db/026:155-160`), the schema already guarantees the outcome. A future runbook can pair this confirmation with a two-user test if one is scheduled for an unrelated reason, but it is not required to close this verification.

---

## Test-setup caveats — recorded explicitly

- **Single-user run.** Mike played all three roles: TV (Window A, `tv2.html` → `stage.html`), session-creator (Window B, `index.html` → `screen-karaoke-info` → `enterKaraokeStartFlow`), and rejoin singer (Window C, `singer.html?code=97ER7S`). Same pattern as the Items 5/6 verification on 2026-05-25.

- **Proximity feature is broken and was bypassed.** Per `docs/SESSION-LOGS/ITEMS-5-6-KARAOKE-VERIFICATION-RUNBOOK.md` §0 (post-commit `6c4406b`): `setProximityAnswer` does not persist across reloads; the banner's "Yes, I'm at home" button is observably non-functional. The bypass: `getHomeMode()` returns `'A'` when no proximity answer is cached (default-yes per `index.html:2116`), so the karaoke tile remained tappable from the default Mode A state. The banner was ignored throughout the run. No proximity API calls were made or relied on.

- **Fixture (carried over from Items 5/6 / Tier 1 §8 runs):**
  - Household: `015a8d5e-9ece-4e30-a334-7983f0818c3c` ("Living")
  - TV: `0ba8b796-a685-4acb-8011-e2729e124fc7` (device_key `3df01b1f-3ef5-4ccb-8576-f5d816a47393`)
  - Room: `f20f6260-...` / room_code `97ER7S` — REUSED via `enterKaraokeStartFlow`'s lookup-or-create path (`karaoke/singer.html:858-873`)
  - Session: `9bec9ec4-...` — created during Check 1; controller `8984755f` (Mike)
  - TV binding restored at run start via the localStorage device_key method:
    ```js
    localStorage.setItem('elsewhere.tv.device_key', '3df01b1f-3ef5-4ccb-8576-f5d816a47393');
    ```
    Documented in the read-only TV-binding investigation conducted earlier this session.

- **Deploy state at run time:** `main` at `6f907b0` (the doc-comment cleanup commit immediately after 595e004). The deploy can be confirmed live via the post-595e004-added "rooms-lookup-hop" comment string in singer.html.

---

## Conclusion

**595e004 verified.** The db/025+db/026 stale-schema degradation is retired across all three verified surfaces:

- **Creation path** (Check 1) — `enterKaraokeStartFlow` → session-wired singer + stage. No legacy-mode fallback.
- **Mutation path** (Check 2) — the 7 re-keyed RPC callers fire cleanly. `participation_role` transitions work; song lifecycle works.
- **Rejoin path** (Check 3) — `?code=` deep-link → session-wired on rejoin. 23505 same-user handling correct.

The Items 5/6 verification log's Observation 4 ("expected PASS in legacy mode") is no longer the end state. Phase 3's deliberate-in-app-session-creation slice for karaoke now reaches **full session-wired mode** on every entry path.

Non-blocking observations and the resolved-with-optional-residual item are recorded above. None blocks closing this verification.

---

## Row inventory — for the cleanup task

Rows touched during this run, for future DB cleanup pairing with the Items 5/6 + Tier 1 §8 backlog:

### rooms — REUSED
- `f20f6260-...` / room_code `97ER7S` / `controller_user_id=8984755f`, `owner_user_id=8984755f`, `screen_ref=0ba8b796-...` — reused, not re-created.

### sessions — NEW
- `9bec9ec4-...` / `app='karaoke'` / `room_id=f20f6260-...` / `started_at` at Check 1 time / `ended_at` TBD (not ended at log-write time; pending cleanup).

### session_participants — touched
- One row for Mike (`user_id=8984755f-...`) in room `f20f6260-...`, `control_role='manager'`, `participation_role` transitioned `audience` → `active` during Check 2's mutation. Single row observed by both session-creator and rejoin tabs.

### Cleanup pending
Bundled with the prior runs' cleanup (Tier 1 §8 + Items 5/6 + this verification). Proposed SQL not executed yet; will pair with a future DB-cleanup pass.

---

## End of log
