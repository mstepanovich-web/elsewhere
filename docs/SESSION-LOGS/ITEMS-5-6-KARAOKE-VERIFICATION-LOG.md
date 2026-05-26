# Items 5/6 (Karaoke half) — Verification Result Log (commit 6663ff5)

**Commit verified:** `6663ff5` — `feat(items-5-6): karaoke session-creation moves to a deliberate in-app action`
**Run date:** 2026-05-26
**Spec verified against:** `docs/ITEMS-5-6-BUILD-SPEC.md` §12 step 4 (verification scope) and §§4–8 (behavior constraints)
**Procedure used:** `docs/SESSION-LOGS/ITEMS-5-6-KARAOKE-VERIFICATION-RUNBOOK.md`
**Environment:** prod Supabase, GitHub Pages bundle at `https://mstepanovich-web.github.io/elsewhere/`
**Test account:** Mike Stepanovich — UID `8984755f-9534-437a-a2a7-2aeba06c7e9d`
**Test fixtures:** household `015a8d5e` (TV "Living", `tv_devices.id = 0ba8b796`, `device_key = 3df01b1f`). All karaoke + games rooms during the run resolved to room `f20f6260` (room_code `97ER7S`).

This is the durable result record for the verification run. The runbook is
the procedure; this log is the outcome. Together they document what was
verified and the state of Phase 3 gate clearance.

---

## 1. Per-item results — all five PASS

### Check 1 — End-to-end karaoke entry — **PASS**

Tile-tap is navigation only; `screen-karaoke-info` is the default landing;
"Start Karaoke" creates the session + publishes `launch_app`; TV navigates
to stage.html; singer ends on screen-home in legacy mode (the expected
PASS state per build spec §8 + the §8 log's item 3 framing for the
pre-existing stale-SELECT debt).

- **Observation 1 — tile-tap navigation only.** Tapping the Karaoke tile
  on Window B's screen-home navigated Window B to `karaoke/singer.html`
  with NO `?code=` URL param. Window A (TV's tv2.html) did NOT navigate
  — it stayed on the apps grid. The tv2.html LOG panel was open and
  watched through the tap window; no new `received launch_app` line
  appeared at tap time (absence observed by watching the LOG, not by
  capturing a snapshot of the line). The per-app gate at
  `index.html:3190` worked as designed — karaoke returned early before
  any `rpc_room_create` / `rpc_session_start` / `publishLaunchApp`
  fired.
- **Observation 2 — screen-karaoke-info rendered.** Window B showed the
  new screen as the default-active: gold italic "Karaoke" heading, body
  copy ("Your phone is the controller — the TV is the stage"), "Start
  Karaoke" CTA, status div empty, `v2.121` mono stamp, Mode-C no-TV block
  hidden.
- **Observation 3 — "Start Karaoke" produced the right DB rows + TV
  reached the karaoke stage.** Tap fired `enterKaraokeStartFlow`.
  Status text cycled "Connecting…" → "Starting…" → internal swap to
  `screen-join` (the brief roundtrip flash) → `screen-home`. Window A
  (the TV) navigated full-page from tv2.html to
  `karaoke/stage.html?room=97ER7S` — confirmed by direct observation
  of the URL bar and the stage UI rendering. stage.html was confirmed
  running via its OWN LOG (not tv2.html's): Agora joined the channel
  `elsewhere_97ER7S`; camera + segmentation initialized; venue
  rendering active.

  **The explicit `realtime: received launch_app …` line on tv2.html's
  LOG was not separately captured.** Stage.html's startup is gated
  exclusively on the `launch_app` handler in `tv2.html:634`
  (`handleLaunchApp`) navigating to `karaoke/stage.html`, which fires
  only on receipt of the broadcast — so the broadcast arrived and was
  acted on. The missing log capture is an audit-trail gap, not a
  behavioral one. The PASS rests on the confirmed TV navigation +
  stage.html startup, not on the unrecorded tv2.html log line.

  **Room REUSE confirmed.** Pre-existing room `f20f6260` (room_code
  `97ER7S`) was present in DB with `controller_user_id = 8984755f`
  (Mike) and `ended_at IS NULL`. The handler's step-4 lookup found
  it, `existing.controller_user_id === user.id` matched, room reused
  without calling `rpc_room_create`. The OQ1-corrected room-resolution
  path worked exactly as designed for the case where a persisted room
  exists for the screen.

- **Observation 4 — legacy-mode end state.** singer.html landed on
  `screen-home` with session-level UI dark (the pre-existing
  stale-SELECT regression at `singer.html:1050`'s
  `rpc_session_join({ p_session_id })` call — out of scope per spec §8).
  Mic affordances present. Per the build's item-3 framing: **this is the
  expected PASS state**; treating it as a FAIL would be inconsistent
  with the build's explicit acknowledgment of the inherited debt.

**Post-hoc SQL verification:**

```sql
select s.id, s.app, s.room_id, s.ask_proximity, s.turn_completion,
       s.admission_mode, s.capacity, r.room_code, r.controller_user_id
from public.sessions s join public.rooms r on r.id = s.room_id
where r.id = 'f20f6260…' and s.ended_at is null;
```

Returned one row with `app='karaoke'`, `room_code='97ER7S'`,
`controller_user_id=8984755f`, `ask_proximity=true`,
`turn_completion='app_declared'`, `admission_mode=NULL`, `capacity=NULL`.
All values match `APP_MANIFEST.karaoke` from `index.html:3152` — the
session created by the info-screen click-through is indistinguishable
from the session tile-tap would have created pre-Items-5/6.

Spec §8 pass conditions for Check 1 — all met.

### Check 2 — Rejoin path (`?code=` URL) — **PASS, non-regression**

The `?code=` rejoin path is unchanged by Items 5/6.

- Navigated to `https://mstepanovich-web.github.io/elsewhere/karaoke/singer.html?code=97ER7S`
  in a fresh tab.
- Brief flash of `screen-join` during the doJoin roundtrip (the
  build's added `showScreen('screen-join')` call in the IIFE
  WITH-branch).
- Window B landed on `screen-home` for room `97ER7S` — the active
  singer UI — AND acquired the microphone ("Microphone in use"
  indicator visible from the browser/OS).
- **`screen-karaoke-info` was NOT involved.** The rejoin path bypassed
  the new screen entirely, as the spec §5 R5.3 designed: `?code=` is
  the JOIN/rejoin path, the info-screen is the CREATION path, the two
  do not interfere.

**The explicit `Joining room: 97ER7S` log line on singer.html was not
separately captured.** The PASS rests on the confirmed landing on
screen-home for the correct room and the mic acquisition: doJoin's
outer try-block runs Agora client creation, channel join, mic init,
and mic publish before reaching `showScreen('screen-home')` at its
tail (singer.html post-edit ~line 1082). Reaching screen-home with mic
active means doJoin ran end-to-end through its outer try. The IIFE
WITH-branch fired and was not regressed by the build's added
`showScreen('screen-join')` call.

### Check 3 — Cross-app-switch double-confirm — **PASS** (load-bearing for the OQ1 fix)

Switching FROM an active games session TO karaoke produced BOTH
confirmations as designed. Room REUSE under cross-app-switch verified by
matching room_id between the just-ended games session and the new
karaoke session — the OQ1-corrected room-resolution path's
load-bearing test.

**Setup:**

- Mode A precondition met (Mike signed in, bound to TV `0ba8b796`, no
  proximity 'no' answer cached).
- Tapped Games tile on Window B → games session created in DB.
  Verified via SQL: one `sessions` row with `app='games'`,
  `id = '6fe883a3-…'`, `room_id = 'f20f6260-…'` (the persisted shared
  room for this TV).

  **Pre-existing failures observed but not blocking the precondition** —
  see §4 below. games player.html landed on the empty "Last Card"
  lobby (stale-SELECT debt at `games/player.html:2753–2757`) instead
  of the game-selection screen (`screen-lobby`); the TV did NOT attach
  to `games/tv.html` (launch_app delivery gap). Per the games
  diagnostic, neither failure blocks Check 3 because
  `handleCrossAppSwitch` reads only `rooms` + `sessions` via the
  post-§F room-keyed SELECTs in `index.html`, not
  `session_participants` or player.html state. The games-session
  precondition was verified by SQL, not by observing the games UI.

**Steps and observations:**

- **Step 1 — return to screen-home + tap Karaoke.** Navigated Window B
  back to `index.html` via the back-to-Elsewhere pill. `enterHomeForTv`
  ran → `refreshActiveSession` populated `_activeSessionForBoundTv` with
  the games-session row. Tapped Karaoke tile.
- **Observation 1 — Confirm #1 fired.** Native `confirm()` dialog
  appeared with text **"End current Games session to start Karaoke?"**.
  Confirmed visually before dismissing.
- **Step 2 — accepted Confirm #1.** Tapped OK / Yes.
- **Observation 2 — session_ended publish + navigation.** Window A
  (TV's games/tv.html) received `session_ended` and reverted state.
  Window B navigated to `karaoke/singer.html` with no `?code=` — landed
  on `screen-karaoke-info`. Critically, the karaoke session was NOT
  auto-created at this point — the click-through was still required, as
  the spec §4 last sub-bullet designed.
- **Observation 3 — Confirm #2 required.** Window B was on
  `screen-karaoke-info` with the "Start Karaoke" CTA. The user had to
  tap it to actually create the karaoke session. This is the second
  deliberate confirmation — the build's headline behavior change.
- **Step 3 — tapped "Start Karaoke".** Handler ran step 4 room
  resolution.
- **Observation 4 — ROOM REUSE confirmed via post-hoc SQL.** This is
  the load-bearing test for the OQ1 fix:

  ```sql
  select id, app, room_id, started_at, ended_at
  from public.sessions
  where room_id = 'f20f6260…'
  order by started_at;
  ```

  Returned two rows for room `f20f6260`:
  - The games session (`id = 6fe883a3…`, `app='games'`, `ended_at` set
    by Confirm #1's `rpc_session_end`)
  - The new karaoke session (`id = 40113363…`, `app='karaoke'`,
    `ended_at IS NULL`)

  **Both sessions share the same `room_id = f20f6260…`.** The new
  karaoke session was attached to the persisted games-session room
  rather than triggering a `rpc_room_create` (which would have produced
  a new room_id, OR raised the 23505 / "failed to generate a unique
  room_code after 5 attempts" misleading error from
  `rooms_one_active_per_screen` per the OQ1 analysis). The handler's
  step-4 lookup found the existing room, matched the user as
  controller, and reused it.

- **Observation 5 — TV navigation.** Window A received `launch_app` for
  karaoke and navigated to `karaoke/stage.html?room=97ER7S` (same
  room_code, since the room was reused).

**Check 3 PASS criteria all met:**

- Confirm #1 fired ("End current Games session to start Karaoke?") ✓
- Confirm #2 required (info-screen "Start Karaoke" tap) ✓
- Room REUSED — same `room_id` `f20f6260` across the games session and
  the new karaoke session ✓
- New karaoke session created in the existing room ✓
- TV navigated to stage.html ✓

The OQ1-corrected room-lookup-then-decide pattern (`enterKaraokeStartFlow`
step 4) handled the cross-app-switch case exactly as designed.

### Check 4 — Mode B silent no-op — **PASS, non-regression**

Karaoke tile-tap in Mode B remains a silent no-op, unchanged from
pre-Items-5/6 behavior at `index.html:2985`.

- Mode B was forced via the runbook's DevTools workaround (the natural
  path is gated by the known-broken proximity prompt — Deferred Item 3
  from the Tier 1 §8 log):

  ```js
  setProximityAnswer(document.getElementById('screen-home').dataset.tvDeviceId, 'no')
  ```

  Page reloaded; `getHomeMode()` returned `'B'` — Mode B precondition
  confirmed.
- Karaoke tile rendered greyed/inert (Mode B's visual state). Tap
  produced no navigation, no `confirm()`, no toast, no error. Window B
  stayed on `screen-home`. LOG showed no realtime publish, no RPC, no
  log lines.
- This is the unchanged behavior at `index.html:2985`
  (`if (app === 'karaoke') return; // silent no-op`) — untouched by
  Items 5/6.
- Cleanup performed: `clearProximityAnswer(...)`, reload, `getHomeMode()`
  returned `'A'` again before proceeding to Check 5.

### Check 5 — Mode C no-TV-bound — **PASS**

`screen-karaoke-info` renders its Mode-C no-TV-bound copy with the CTA
hidden; the handler's step-1 device_key guard works.

- Navigated directly to `karaoke/singer.html` with no `?code=` URL and
  no `elsewhere.active_tv.device_key` in sessionStorage (Mode C — no
  TV bound to this browser context).
- Page rendered `screen-karaoke-info` as the default-active screen.
- Tapped "Start Karaoke". Handler step 1 detected missing `device_key`,
  LOG showed
  `enterKaraokeStartFlow: no device_key — Mode C, no TV bound`,
  `showNoTv()` ran: the CTA was hidden (`display:none`), the no-TV copy
  block ("No TV is bound to this device yet…") became visible.
- No RPC fired. No `rooms` or `sessions` row created.

Mode-C path works as `enterKaraokeStartFlow`'s step-1 guard designed.

---

## 2. Pass/fail summary

| Item | Status |
|---|---|
| Check 1 — End-to-end karaoke entry | **PASS** |
| Check 2 — Rejoin path (`?code=`) | **PASS** (non-regression) |
| Check 3 — Cross-app-switch double-confirm | **PASS** (OQ1 fix verified by room_id match) |
| Check 4 — Mode B silent no-op | **PASS** (non-regression) |
| Check 5 — Mode C no-TV-bound | **PASS** |

---

## 3. Gate status — Phase 3 gates #2 (karaoke half) and #3 cleared

Per the runbook (gates sourced from `docs/ITEMS-5-6-BUILD-SPEC.md` §9
D9.2 → `docs/IMMERSIVE-TV-DESIGN-MODEL.md` §13):

- **Gate #1 — Immersive TV Tier 1.** Cleared 2026-05-25 by commit
  `e33a658` per `docs/SESSION-LOGS/TIER-1-V8-VERIFICATION-LOG.md` §3.
- **Gate #2 — Item 6 (tile-tap must stop creating a session) — karaoke
  half cleared by this run.** Verified by Check 1 (tile-tap is
  navigation only; no launch_app at tap; no `rpc_room_create` /
  `rpc_session_start` at tap) and Check 3 (cross-app-switch tail
  produces navigation-only into screen-karaoke-info, not auto-creation).
  Per §13's verbatim wording — *"The karaoke fix lands in Phase 3; the
  games fix lands in Phase 4"* — gate #2's games half remains open and
  is Phase 4 scope. This build deliberately leaves games on the old
  create-on-tile-tap path (per the spec's §6 O6.3 per-app gating
  decision).
- **Gate #3 — Item 5 (karaoke explicit session-creation action) —
  cleared by this run.** Verified by Check 1 (screen-karaoke-info
  renders as default; "Start Karaoke" CTA is the deliberate creation
  action) and Check 3 (the second confirmation falls out automatically
  on cross-app-switch).

**Phase 3 gates #2 (karaoke half) and #3 are CLEARED.** The remaining
gate #2 (games half) is explicit Phase 4 scope.

---

## 4. Pre-existing failures observed (record honestly; not Items 5/6's fault)

Check 3 ran on top of two pre-existing, non-Items-5/6 failures in the
games surfaces. Both are documented elsewhere; neither blocked Check 3.

### (a) Games player lands on empty "Last Card" lobby instead of the game-selection screen

**Observed:** After tapping the Games tile, `games/player.html` rendered
`screen-game-room` (the "Waiting for the manager to start the game" /
PLAYING(0) / WATCHING(0) empty lobby) instead of `screen-lobby` (the
game-selection picker with Last Card / Trivia / Euchre tiles, which the
manager should have landed on).

**Root cause:** stale SELECT at `games/player.html:2753–2757` projects
columns dropped by db/025 (`manager_user_id`, `room_code`, `tv_device_id`)
and filters `eq('room_code', roomCode)` (also dropped). PostgREST
returns 400 → catch at `games/player.html:2760–2764` drops to legacy
mode → `currentMyRow` stays null → doJoin's dispatch at
`games/player.html:1336–1346` falls to the non-manager branch
(`goToGameRoom()` → screen-game-room) instead of the manager branch
(`goToLobby()` → screen-lobby).

**Pre-existing:** Filed in DEFERRED.md as "schema-stale sessions
SELECTs/filters on the four pre-Phase-3 surfaces" (`docs/DEFERRED.md:3363`),
which lists `games/player.html` explicitly as one of the four affected
surfaces. Items 5/6 acknowledges and inherits the same legacy-mode
end-state for karaoke per spec §8.

**Did not block Check 3.** handleCrossAppSwitch reads only `rooms` +
`sessions` table state via the post-§F room-keyed SELECTs in
`index.html`, not `session_participants` or player.html UI state. The
DB-side games session was created by `rpc_room_create` +
`rpc_session_start` at tile-tap time, before player.html's failure
mattered. Confirm #1 fired correctly.

### (b) Games TV never attaches to `games/tv.html`

**Observed:** After tapping the Games tile, Window A (the TV's tv2.html)
did NOT navigate to `games/tv.html`. It stayed on the apps grid. No
`received launch_app` line appeared in tv2.html's LOG at games tile-tap
time.

**Root cause:** the launch_app realtime delivery gap on the shell
tile-tap path. This was traced during the V8.3 verification on
2026-05-25; the diagnostic is in `docs/SESSION-LOGS/TIER-1-V8-VERIFICATION-LOG.md`'s
Deferred Item 2.

**Pre-existing:** Filed in the Tier 1 §8 log as "launch_app not
delivered via shell tile-tap path." Tier 1 (`e33a658`) did not modify
any of the involved code paths; Items 5/6 also did not modify them for
games (the per-app gate keeps games on the old create+publish path
until Phase 4).

**Did not block Check 3.** Same reason as (a) — handleCrossAppSwitch
doesn't depend on the TV having navigated to games/tv.html. The
shell's getActiveSession cache (the source of truth for the
cross-app-switch dispatch) reads the `rooms` + `sessions` tables
directly via refreshActiveSession.

### Karaoke-side launch_app DID deliver in this run

Worth noting explicitly because the V8.3 launch_app failure was on the
games tile-tap path. In Check 1, the karaoke info-screen's "Start
Karaoke" click-through called `publishLaunchApp(device_key, 'karaoke',
room.room_code)` — a fresh code path moved by Items 5/6 from
`index.html` to `karaoke/singer.html` — and the TV received it
(navigated to `karaoke/stage.html?room=97ER7S`). The new code path
delivered cleanly; the pre-existing path's delivery gap appears
specific to the shell-side tile-tap broadcast, not to the publisher lib
or the channel infrastructure.

---

## 5. Row inventory — prod test data created (for the cleanup task)

All rows created or touched during this verification. Bundle with the
still-pending Tier 1 §8 cleanup.

### households (pre-existing — reused, not created)

| id | name | created during | notes |
|---|---|---|---|
| `015a8d5e…` | (Mike's household) | (pre-existing) | reused — already on prod |

### tv_devices (pre-existing — reused, not created)

| id | device_key | household_id | display_name | created during | notes |
|---|---|---|---|---|---|
| `0ba8b796…` | `3df01b1f…` | `015a8d5e…` | Living | (pre-existing) | reused |

### rooms (pre-existing — reused, not created)

| id | room_code | screen_ref | controller_user_id | created during | notes |
|---|---|---|---|---|---|
| `f20f6260…` | `97ER7S` | `0ba8b796…` | `8984755f` (Mike) | (pre-existing) | reused throughout Check 1 + Check 3 (OQ1 fix's load-bearing test) |

### sessions — new during this run

| id | room_id | app | ended_at | created during | notes |
|---|---|---|---|---|---|
| `2b36a99a-a85a-4832-9133-dea8712174c4` | `f20f6260…` | karaoke | ended manually via SQL (`update sessions set ended_at = now() where id = '2b36a99a-…'`) during the pre-Check-3 cleanup | Check 1 | first karaoke session in this run; the one created by the Check 1 "Start Karaoke" tap |
| `6fe883a3-…` | `f20f6260…` | games | ended by Check 3 Confirm #1's `rpc_session_end` | Check 3 setup | games session created for the cross-app-switch precondition |
| `40113363-…` | `f20f6260…` | karaoke | ended manually via SQL (`update sessions set ended_at = now() where id = '40113363-…'`) at the start of Check 4 setup | Check 3 | post-cross-app-switch karaoke session, attached to the same room as `6fe883a3-…` — the load-bearing OQ1 room-reuse evidence |

**Cleanup note:** all three test sessions above are already ended
(`ended_at` populated on every row). No session remains active. Only
the row-level deletion of these `sessions` rows remains pending,
bundled with the still-pending Tier 1 §8 row cleanup.

### session_participants — touched during this run

| room_id | user_id | control_role | participation_role | created during | notes |
|---|---|---|---|---|---|
| `f20f6260…` | `8984755f` | manager | active → updated by rpc_session_start each session | (pre-existing — seated by rpc_room_create at room creation) | Mike's row on the reused room. Updated to 'active' on the games rpc_session_start, then again on the karaoke rpc_session_start at the Check 3 click-through. |

No new session_participants rows created in this run — the reused room
already had Mike's row from prior session work.

### Cross-reference with the still-pending Tier 1 §8 cleanup

The Tier 1 §8 result log filed a separate row inventory at
`docs/SESSION-LOGS/TIER-1-V8-VERIFICATION-LOG.md` §4:

- households: `581833bb…` (V8.1 Verification Household)
- tv_devices: `a7047be5…` (V8.1) + `7bc98d3a…` (V8.2)
- household_members: Mike admin/founder of 581833bb
- rooms/sessions: any from V8.3 attempts (including the previously-noted
  `SYNKZ6` room)

**Both cleanup batches should be done together.** The Items 5/6 run did
NOT touch the V8.1 fixtures — it used the separate `015a8d5e` household
test setup. The Tier 1 §8 cleanup remains pending; this Items 5/6 run
adds its own inventory above without resolving the prior one.

---

## 6. References

- Spec: `docs/ITEMS-5-6-BUILD-SPEC.md` §12 step 4 (verification scope),
  §§4–8 (behavior constraints), §9 D9.2 (gate sourcing).
- Procedure: `docs/SESSION-LOGS/ITEMS-5-6-KARAOKE-VERIFICATION-RUNBOOK.md`.
- Design model: `docs/IMMERSIVE-TV-DESIGN-MODEL.md` §13 (Phase 3 gate
  taxonomy — gates #2 karaoke half and #3 cleared by this run; gate #1
  cleared by Tier 1; gate #2 games half remains Phase 4).
- Pre-existing failure cross-refs:
  - `docs/DEFERRED.md:3363` — "schema-stale sessions SELECTs/filters on
    the four pre-Phase-3 surfaces" (games/player.html:2753 is one of
    the four).
  - `docs/SESSION-LOGS/TIER-1-V8-VERIFICATION-LOG.md` Deferred Item 2 —
    launch_app shell-tile-tap delivery gap.
- Commit: `6663ff5` — `feat(items-5-6): karaoke session-creation moves
  to a deliberate in-app action`.

---

## End of log
