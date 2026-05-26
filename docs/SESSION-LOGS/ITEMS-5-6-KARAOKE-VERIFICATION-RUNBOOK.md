# Items 5/6 (Karaoke half) — Verification Runbook (commit 6663ff5)

Operational runbook for the live verification of commit `6663ff5`
(`feat(items-5-6): karaoke session-creation moves to a deliberate in-app action`).
This is a procedure doc, not a durable spec — the spec is
`docs/ITEMS-5-6-BUILD-SPEC.md` §12 step 4 (verification scope) and §§4–8
(behavior constraints). Gate definitions are sourced from the spec's
§9 D9.2 cross-reference to `docs/IMMERSIVE-TV-DESIGN-MODEL.md` §13.

Live human-run procedure. Claude Code prepared the materials; a human
runs the browser steps and the SQL queries. Fill in row IDs as you go
in §8 (Row inventory).

**Important — pre-run requirement:** Commit `6663ff5` must be **pushed
to origin/main and deployed to GitHub Pages** before this run. Verify
with `curl -s https://mstepanovich-web.github.io/elsewhere/karaoke/singer.html | grep -c "screen-karaoke-info"` — must return ≥ 1. If it
returns 0, GitHub Pages hasn't picked up the deploy yet; wait ~60s and
retry.

---

## 0. Test account, browsers, and TV claim state

- **Test account: Mike Stepanovich** — UID `8984755f-9534-437a-a2a7-2aeba06c7e9d`.
  Sign in via magic link if needed.

### TV claim state

Two paths depending on whether the Tier 1 §8 cleanup has been run:

- **If cleanup has NOT run** (V8.1 household + tv_devices still in prod
  — confirm via §1 Q1 below): reuse "V8.1 Verification Household"
  (`581833bb-43b7-4943-8afd-03eb88465281`) and its bound tv_devices
  row. The laptop's localStorage `elsewhere.tv.device_key` should
  match one of: `f7b250cf-7e28-4645-9601-d3e48d27bf95` (Verification
  TV V8.1) or `d0c453b4-13a5-4953-98b2-de27379f39b4`.
- **If cleanup HAS run** (V8.1 rows gone): claim a fresh TV via the
  Tier 1 web-claim flow (open `tv2.html`, tap "Set up without the
  app →", complete the picker). Record the new household + tv_devices
  ids in §8.

### Browser windows needed

- **Window A (the TV)** — a laptop browser tab on `tv2.html`,
  registered. Should show `screen-apps` with the household name.
  This is what would receive `launch_app` broadcasts. Keep its
  DevTools console + LOG panel open throughout the run for trace
  capture.
- **Window B (the controller)** — a phone OR a second browser profile
  on the SAME laptop, on `index.html`, signed in as Mike. After
  sign-in + `enterYourTvsFlow`, this should auto-bind to Window A's
  TV (n=1 case) OR show the TV-picker (n=2+ case — select Window A's
  TV). Window B is where the user taps the Karaoke tile.

### Verifying the deploy reaches both surfaces

- Window A (tv2.html): the new build doesn't change tv2.html. No
  visual difference expected. (The build is verified by behavior
  in the subsequent checks, not by tv2.html content.)
- Window B (index.html → karaoke tile → singer.html): the new screen
  `screen-karaoke-info` must render on `singer.html` with no `?code=`
  URL param. If `singer.html` still defaults to `screen-join` (the
  pre-Items-5/6 landing), the deploy hasn't picked up the new build —
  hard-reload (`Cmd-Shift-R`) to bypass cache. If still failing,
  abort and investigate the deploy.

### Known-broken affordance you may hit

- **Proximity prompt non-functional** — `index.html`'s "Are you at
  home?" banner's "Yes, I'm at home" button does nothing (Deferred
  Item 3 from the Tier 1 §8 result log, `docs/SESSION-LOGS/TIER-1-V8-VERIFICATION-LOG.md`).
  This may interact with Mode A/B detection and is called out in
  Check 4. Workaround: write `sessionStorage` directly via DevTools
  console (steps in Check 4 setup).

### Proximity default — why Check 1 is runnable

The "Are you at home?" prompt is broken (can't record a "yes"), but
this does **NOT** block the karaoke flow. `getHomeMode()` returns `'A'`
when no proximity answer is cached (`index.html:2113-2114` — the
comment "'yes' OR null (unanswered) both render as Mode A — default-yes
per state model" sits above the `return 'A'` at line 2116; the
`return 'B'` at line 2112 fires only when the cached answer is
strictly `'no'`). So a signed-in household member on a bound TV with
no proximity answer lands in Mode A, and the karaoke tile-tap
navigates normally.

Mode B is reached ONLY by an explicit `'no'` — which is why Check 4
needs the DevTools workaround below to force it. Checks 1, 2, 3, 5
all run on the natural Mode A default; no workaround needed for them.

---

## 1. Pre-step SQL

Run each in the Supabase SQL Editor. Capture results.

### Q1 — Is the V8.1 environment intact?

```sql
-- V8.1 household + tv_devices + Mike's membership
select
  h.id            as household_id,
  h.name,
  td.id           as tv_device_id,
  td.device_key,
  td.display_name,
  hm.role,
  hm.joined_via
from public.households h
left join public.tv_devices td on td.household_id = h.id
left join public.household_members hm
  on hm.household_id = h.id
 and hm.user_id      = '8984755f-9534-437a-a2a7-2aeba06c7e9d'
where h.id = '581833bb-43b7-4943-8afd-03eb88465281'
order by td.registered_at;
```

**Outcome:**
- Returns ≥ 1 row with `name='V8.1 Verification Household'` → V8.1
  environment intact; reuse it.
- Returns 0 rows → V8.1 has been cleaned up; you'll need to claim a
  fresh TV (record the new ids in §8).

### Q2 — Any leftover active rooms or sessions for the V8.1 TV?

```sql
-- Active rooms tied to either V8.1 tv_devices id
select id as room_id, room_code, controller_user_id, owner_user_id,
       screen_ref, created_at, ended_at
from public.rooms
where screen_ref in (
  'a7047be5-3cf0-4fd5-a066-44f8f533d436',  -- Verification TV V8.1
  '7bc98d3a-cb25-4587-9702-7fb3e9618fa0'   -- V8.2 link (no display_name)
)
  and ended_at is null;

-- Active sessions in those rooms
select s.id as session_id, s.room_id, s.app, s.started_at, s.ended_at,
       r.room_code
from public.sessions s
join public.rooms r on r.id = s.room_id
where r.screen_ref in (
  'a7047be5-3cf0-4fd5-a066-44f8f533d436',
  '7bc98d3a-cb25-4587-9702-7fb3e9618fa0'
)
  and s.ended_at is null;
```

**Outcome:**
- 0 active rooms AND 0 active sessions → clean slate; ready to run
  Check 1.
- ≥ 1 active room with `controller_user_id = 8984755f` and no active
  session → this is the room-reuse case the build's step-4 lookup
  handles. Check 1 will REUSE this room (the path the spec §5.5(b)
  describes). Note in §8 that an existing room was reused.
- ≥ 1 active session → a session is already running on the TV. Check
  1 will exercise the 23505 same-app rejoin branch. Record session_id
  for §8 as a row potentially affected by the run.
- ≥ 1 active room with `controller_user_id ≠ 8984755f` → another user
  is the controller; Check 1 will trigger the non-controller alert
  ("You aren't the manager…"). Either run a SQL DELETE of that room
  first (out of band, with care), or run Check 1 from the controller's
  account instead. **Flag this case in §8 if it occurs.**

### Q3 — Confirm the deployed build is 6663ff5

```bash
# Run in shell (not SQL Editor)
curl -s https://mstepanovich-web.github.io/elsewhere/karaoke/singer.html | grep -c "screen-karaoke-info"
# Expect: ≥ 1 (the new markup is live)

curl -s https://mstepanovich-web.github.io/elsewhere/index.html | grep -c "Items 5/6 — per-app gate"
# Expect: ≥ 1 (the new shell comment is live)
```

If either returns 0, the deploy hasn't propagated. Wait, hard-reload,
retry. If persistently 0 after several minutes, abort — investigate
the GitHub Pages build.

---

## 2. Check 1 — End-to-end karaoke entry (THE HEADLINE)

**Goal:** Prove tile-tap is navigation only (no session created at tile
tap); `screen-karaoke-info` lands as the default screen; "Start
Karaoke" creates the session + publishes `launch_app`; TV navigates to
`karaoke/stage.html`; singer ends on `screen-home` in legacy mode (the
**expected PASS outcome** per build spec §8 + the §8 result log's item
3 framing).

### Setup

- Window A: `tv2.html` on the claimed laptop, showing `screen-apps`
  with the V8.1 (or fresh) household header. LOG panel open.
- Window B: `index.html` on phone or second browser profile, signed in
  as Mike, on `screen-home` bound to the same TV (auto-bound via
  `enterYourTvsFlow`'s n=1 branch, or selected via the n=2 picker).
  The home tile-grid should be visible.

### Steps

1. **Window B**, tap the **Karaoke** tile (🎤).
2. **Observation 1.1 — tile-tap is navigation only.** Expect:
   - Window B's URL changes to `…/karaoke/singer.html` (no `?code=`).
   - Window A (TV) does NOT navigate. tv2.html LOG should NOT show a
     `received launch_app` line (which would have fired today's
     pre-Items-5/6 broadcast). If launch_app DID fire here, the
     per-app gate is broken — FAIL.
3. **Observation 1.2 — screen-karaoke-info renders.** Window B
   should now show:
   - Big italic gold "Karaoke" heading
   - Body copy: "Sing together. Your phone is the controller…"
   - Gold pill button: **"Start Karaoke"**
   - Below the button: small mono "v2.121" version stamp
   - The Mode-C no-TV-bound block should be HIDDEN (the user has a
     bound TV via Window B's home binding).
4. Tap **"Start Karaoke"**.
5. **Observation 2 — status text + TV navigation.** Expect on
   Window B (singer.html):
   - Status text "Connecting…" briefly under the button
   - Status text "Starting…" briefly
   - Internal screen swap to `screen-join` (the room-code rendered
     view — brief flash while doJoin runs Agora connect)
   - Then internal screen swap to `screen-home` (the active singer
     UI — song picker, settings)
6. **Observation 3 — TV navigation.** Within ~1–2 seconds of step 5,
   Window A's `tv2.html` should:
   - LOG panel shows: `realtime: received launch_app app=karaoke
     room=<ROOMCODE>` (where ROOMCODE is the 6-char room code)
   - Page navigates (full-page) to `karaoke/stage.html?room=<ROOMCODE>`
   - The stage UI renders.
7. **Observation 4 — legacy-mode acknowledgment.** Window B
   (singer.html on `screen-home`) is in **LEGACY MODE — this is the
   expected PASS state** per build spec §8 + §8 result log's item 3.
   You may see: empty queue rendering, no role-aware UI, mic affordances
   present but session-level UI dark. Singer.html LOG should show:
   - `Session: rpc_session_join failed (… function … does not exist
     … or arg mismatch …) — legacy mode` (the pre-existing
     stale-SELECT debt at singer.html:1050; out of scope for this
     spec per §8).
   The user IS on screen-home; the session-level UI being dark is
   today's universal singer.html state. **DO NOT mark this as a FAIL.**

### Post-hoc SQL verification

```sql
-- Confirm a real rooms row was created/reused
select id as room_id, room_code, controller_user_id, owner_user_id,
       screen_ref, created_at, ended_at
from public.rooms
where screen_ref = '<TV_DEVICE_ID-FROM-§0>'
  and ended_at is null;

-- Confirm a real sessions row exists for that room with app='karaoke'
select s.id as session_id, s.room_id, s.app, s.started_at, s.ended_at,
       s.ask_proximity, s.turn_completion, s.admission_mode, s.capacity
from public.sessions s
join public.rooms r on r.id = s.room_id
where r.screen_ref = '<TV_DEVICE_ID-FROM-§0>'
  and s.ended_at is null;
```

**Expected:**
- One `rooms` row with `controller_user_id = 8984755f` (Mike), valid
  `room_code` (6 chars, no `0/1/I/L/O`), `screen_ref` matching the
  bound TV.
- One `sessions` row with `app = 'karaoke'`, `ask_proximity = true`,
  `turn_completion = 'app_declared'`, `admission_mode = NULL`,
  `capacity = NULL`, `ended_at = NULL`. These match the
  `APP_MANIFEST.karaoke` values from `index.html:3152`.

Record both ids in §8.

### Check 1 PASS criteria

All of:
- Tile-tap navigated to `singer.html` WITHOUT `?code=` (Obs 1.1)
- `screen-karaoke-info` rendered as default (Obs 1.2)
- "Start Karaoke" produced a `rooms` row + `sessions` row (post-hoc
  SQL)
- TV received `launch_app` and navigated to stage.html (Obs 3)
- Singer ended on `screen-home`, legacy-mode is acceptable (Obs 4)

### Check 1 FAIL conditions

- launch_app fires on tile-tap (Obs 1.1) — gate broken
- `screen-join` renders instead of `screen-karaoke-info` (Obs 1.2) —
  default-active swap not deployed; check cache + §1 Q3
- "Start Karaoke" produces no DB rows — handler did not reach
  rpc_session_start
- TV does not navigate to stage.html — diagnose per the V8.3 sender-
  path pattern (this build moved the publisher to the click-through;
  the path is fresh code — check Window B's console for
  `publishLaunchApp` errors)
- Singer ends stranded on `screen-join` with "Could not connect" —
  Agora connect failed in doJoin's outer try (a Network/Agora-SDK
  issue, NOT items 5/6's fault, but record it)

---

## 3. Check 2 — Rejoin path (`?code=` URL)

**Goal:** Prove the rejoin path (existing `?code=` URL + auto-join
IIFE + doJoin) is **unchanged** by Items 5/6.

### Setup

Capture a valid `room_code` to test with:

- **Option A — reuse the Check 1 room:** the `rooms.room_code` from
  Check 1's post-hoc SQL. Cleanest; the session is still active.
- **Option B — query for an existing active karaoke room:**
  ```sql
  select r.room_code from public.rooms r
  join public.sessions s on s.room_id = r.id
  where s.app = 'karaoke' and s.ended_at is null and r.ended_at is null
  order by r.created_at desc limit 1;
  ```

### Steps

1. In a fresh browser tab (Window B or new), navigate to:
   `https://mstepanovich-web.github.io/elsewhere/karaoke/singer.html?code=<ROOMCODE>`
2. **Observation 1 — auto-join IIFE path.** Expect:
   - Brief flash of `screen-join` (the WITH-`?code=` branch shows it
     during the roundtrip per the IIFE's `showScreen('screen-join')`
     call added in this build)
   - Room code visible briefly in the join input
   - After ~600ms (the existing IIFE's setTimeout): doJoin fires
   - LOG shows `Joining room: <ROOMCODE>` followed by Agora join
3. **Observation 2 — landing.** Expect:
   - Page swaps to `screen-home` (the active singer UI)
   - Singer in legacy mode (same as Check 1's Obs 4 — pre-existing
     stale-SELECT; out of scope)

### Check 2 PASS criteria

- The auto-join IIFE fired (LOG shows `Joining room`)
- Singer ended on `screen-home`
- No `screen-karaoke-info` involvement — the rejoin path BYPASSES
  the new screen entirely (it is the CREATION path; `?code=` is the
  JOIN path; per spec §5 R5.3 they don't interfere)

### Check 2 FAIL conditions — diagnostic split

Check 2 is a non-regression check; its purpose is catching whether
this build's addition of `showScreen('screen-join')` to the auto-join
IIFE WITH-branch broke the rejoin path. The diagnostic signal that
distinguishes (a) pre-existing flakiness from (b) an Items-5/6
regression is whether **doJoin ever fired** — the singer.html LOG's
first doJoin line is `Joining room: <ROOMCODE>` (logged at the top of
doJoin's outer try, post-edit at `karaoke/singer.html:1010`).

**(b) — HARD FAIL (Items 5/6 IIFE regression):**

- Page loads with `?code=<ROOMCODE>` in URL, stays stuck on
  `screen-karaoke-info` (or any screen other than screen-join /
  screen-home).
- Singer LOG does NOT show `Joining room: <ROOMCODE>`.
- This means the IIFE WITH-branch never reached
  `window.addEventListener('load', () => setTimeout(doJoin, 600))` —
  the new `showScreen('screen-join')` call (or some other change in
  the IIFE block) threw an error and broke the auto-join sequence.

**(a) — RECORD but DO NOT FAIL (pre-existing Agora/network flakiness):**

- Singer LOG DOES show `Joining room: <ROOMCODE>` — doJoin fired.
- Page lands on `screen-join` with error in `#join-err` (e.g.
  "Could not connect — check code and try again") and Go button
  reset to "Go →" — doJoin's outer catch (`singer.html` post-edit at
  ~line 1085) caught an Agora connect / mic init / channel join
  failure.
- This is the same Agora/network risk today's URL-coded auto-join
  carries; it is not introduced by Items 5/6. Record in §9 Notes,
  but do not mark Check 2 as FAIL on this signal alone.

If Check 2 hits the (a) signal: re-run on a different network / try
hard-reload / try a different test account. If it still fails on (a),
the network is the issue, not the build.

---

## 4. Check 3 — Cross-app-switch double-confirm (most setup-heavy)

**Goal:** Prove switching FROM an active games session TO karaoke
produces BOTH:
1. The "End current Games session to start Karaoke?" confirm dialog
   (from `handleCrossAppSwitch`)
2. The `screen-karaoke-info` "Start Karaoke" tap (the new in-app
   creation action)

Per build spec §4: this double-confirm is **intended**, not a
regression. Eliminating it would re-introduce non-deliberate session
creation — Items 5/6 exists to prevent that.

### Setup — establish an active games session FIRST

Items 5/6 leaves games' tile-tap-create-on-tap path unchanged
(per-app gate keeps games on today's path until Phase 4). So a normal
games tile-tap will create a session.

**Pre-conditions:**
- Window A (TV): `tv2.html` on `screen-apps`
- Window B (controller): `index.html` signed in as Mike, on
  `screen-home` bound to the TV
- No existing active session on the TV (per §1 Q2)

**Steps to set up an active games session:**

1. **Window B**, tap the **Games** tile (🃏).
2. **Observe** Window B navigates to `games/player.html?room=<ROOMCODE>&mgr=1`.
   Window A (TV) navigates to `games/tv.html?room=<ROOMCODE>`.
3. Confirm an active session exists:
   ```sql
   select s.id, s.app, s.room_id, r.room_code
   from public.sessions s join public.rooms r on r.id = s.room_id
   where r.screen_ref = '<TV_DEVICE_ID>'
     and s.ended_at is null;
   -- Expect: one row with app='games'
   ```
4. Record this session_id + room_id in §8.

**Now go back to the shell to trigger the cross-app switch:**

5. Window B: tap the back-to-Elsewhere pill (← Elsewhere) to return
   to the shell home. (Or navigate to `index.html` directly.)
6. Confirm Window B is on `screen-home` with the bound-TV header
   visible.

### Steps — the cross-app switch

7. **Window B**, tap the **Karaoke** tile.
8. **Observation 1 — confirm #1 fires.** Expect a native
   `confirm()` dialog: **"End current Games session to start
   Karaoke?"**
9. Click **OK / Yes**.
10. **Observation 2 — session_ended publish + navigation to
    singer.html.** Expect:
    - Window A (TV's games/tv.html) receives `session_ended`. tv2.html
      isn't open here — but if the games TV page handles it, it may
      navigate back to tv2.html. (Tv2.html only opens when the laptop
      is on the apps grid; mid-session the TV is on games/tv.html.
      Behavior here is whatever games/tv.html's exit handling does —
      record what you observe but don't gate the check on it.)
    - Window B navigates to `karaoke/singer.html` (no `?code=`)
    - **`screen-karaoke-info` renders** (NOT the active singer UI)
11. **Observation 3 — confirm #2 (the "Start Karaoke" tap).** The
    user is now on `screen-karaoke-info`. They must tap "Start
    Karaoke" to actually create the karaoke session.

    **DO NOT** skip this. Tapping it IS the second confirmation, by
    design. If `screen-karaoke-info` were bypassed and the karaoke
    session created automatically, that would be the bug Items 5/6
    fixes.
12. Tap **"Start Karaoke"**.
13. **Observation 4 — room is REUSED (not re-created).** Inspect via
    SQL:
    ```sql
    -- Active rooms on this TV
    select id, room_code, screen_ref, owner_user_id, created_at, ended_at
    from public.rooms
    where screen_ref = '<TV_DEVICE_ID>'
    order by created_at desc;
    ```
    **Expected:** the SAME `rooms.id` and `room_code` from step 3 —
    the games-session room. The room's `ended_at` is still NULL
    (rpc_session_end ended the games SESSION row, not the ROOM —
    per db/025 semantics). The new karaoke session attaches to this
    persisted room.

    **If a NEW room appears instead of reusing the existing one**,
    the build's step-4 lookup-or-create logic is broken — FAIL. The
    step-4 lookup is the OQ1-corrected code we added specifically
    for this case.
14. **Observation 5 — karaoke session exists.**
    ```sql
    select id, app, room_id, started_at from public.sessions
    where room_id = '<ROOM_ID-FROM-STEP-3>'
    order by started_at desc;
    -- Expect: TWO rows for this room — the ended games session
    -- (ended_at not null) and the new karaoke session (ended_at null,
    -- app='karaoke').
    ```
15. **Observation 6 — TV navigation.** Window A: tv2.html (if it
    reverted post-games-end) receives `launch_app` for karaoke and
    navigates to `karaoke/stage.html?room=<ROOMCODE-FROM-STEP-3>`.
    Same room code as the games session used.

### Check 3 PASS criteria

- Confirm #1 ("End current Games session to start Karaoke?") fired
- Confirm #2 (info-screen "Start Karaoke" tap) was required
- Room was REUSED (same rooms.id; lookup-or-create worked)
- New karaoke session created in the existing room
- TV navigated to stage.html

### Check 3 FAIL conditions

- Confirm #1 was skipped (handleCrossAppSwitch broken — unchanged in
  this build, so a real bug)
- After confirm #1, karaoke session auto-created without
  screen-karaoke-info (info-screen step bypassed — the bug Items 5/6
  exists to fix; would mean the gate is broken in handleCrossAppSwitch
  path)
- After "Start Karaoke", a NEW room created instead of reusing the
  games room — step-4 lookup-or-create broken (OQ1 fix didn't work)
- Cryptic "Couldn't create the room: failed to generate a unique
  room_code after 5 attempts" error → exactly the OQ1 failure mode
  the build fix prevents → FAIL

---

## 5. Check 4 — Mode B (proximity = no) silent no-op

**Goal:** Confirm karaoke tile-tap in Mode B remains a silent no-op
(unchanged from pre-Items-5/6 behavior per spec §4 last sub-bullet).

### Mode B reachability — known issue

Per the Tier 1 §8 result log's Deferred Item 3: **the "Are you at
home?" proximity prompt is non-functional.** Specifically the "Yes,
I'm at home" button does nothing. Whether the "No, I'm not" button
works was not verified during the §8 run — it MAY work, but treat as
unconfirmed.

### Reaching Mode B reliably — DevTools workaround

The reliable path is to write the proximity answer directly into
sessionStorage:

1. Window B: open DevTools (Cmd-Opt-I), Console tab.
2. Get the bound TV's `tv_device_id` — this is the **`tv_devices.id`
   UUID** (e.g. `a7047be5-3cf0-4fd5-a066-44f8f533d436`), NOT the
   `device_key` (e.g. `f7b250cf-7e28-4645-9601-d3e48d27bf95`). The
   two are both UUIDs and easily confused; the proximity cache keys
   on `tv_device_id`. Read it via:
   ```js
   document.getElementById('screen-home').dataset.tvDeviceId
   ```
   Capture this UUID.

3. Write the 'no' answer — PRIMARY path uses the real shell API:
   ```js
   setProximityAnswer(document.getElementById('screen-home').dataset.tvDeviceId, 'no')
   ```
   `setProximityAnswer` is defined at `index.html:2080` and is
   console-reachable (top-level function in the non-module script).
   It is a thin wrapper around the sessionStorage write below — using
   the real API removes any room for key-format error.

   FALLBACK path (raw write, equivalent — use only if the function
   call above fails for any reason):
   ```js
   sessionStorage.setItem('elsewhere.proximity.' + document.getElementById('screen-home').dataset.tvDeviceId, 'no')
   ```
   Verbatim of the wrapper's body — prefix `'elsewhere.proximity.'`
   + tv_device_id, value `'no'`.

4. Reload the page (regular reload, NOT hard-reload — preserve
   sessionStorage).
5. Verify Mode B by typing in the console:
   ```js
   getHomeMode()
   // Expect: 'B'
   ```
   `getHomeMode` is defined at `index.html:2104` as a top-level function
   declaration in the non-module `<script>` block — it is reachable
   from the console. If it returns 'A' or 'C', the cached 'no' isn't
   being read (likely the wrong UUID was used — verify you pasted
   tv_device_id, NOT device_key); do not proceed until 'B' is
   confirmed.

### Steps

6. Window B is on `screen-home` (Mode B). Tap the **Karaoke** tile
   (🎤).
7. **Observation — silent no-op.** Expect:
   - NO navigation (Window B stays on `screen-home`)
   - NO alert, no toast, no error
   - LOG (if visible) shows no realtime publish

This is the pre-Items-5/6 behavior at `index.html:2985`
(`if (app === 'karaoke') return; // silent no-op`), unchanged by this
build.

### Cleanup after Check 4

```js
clearProximityAnswer(document.getElementById('screen-home').dataset.tvDeviceId)
```
(or the equivalent raw `sessionStorage.removeItem('elsewhere.proximity.' + …)`).

Reload. Confirm `getHomeMode()` returns 'A' again before Check 5.

### Check 4 PASS criteria

- Tile-tap in Mode B produces no navigation, no alert, no toast.

### Check 4 FAIL conditions

- Karaoke tile-tap in Mode B navigates to anywhere — Mode B's silent
  no-op was unintentionally changed by this build (it shouldn't have
  been — `index.html:2985`'s line is untouched per git diff).

---

## 6. Check 5 — Mode C (no TV bound)

**Goal:** Confirm `screen-karaoke-info` renders its Mode-C
no-TV-bound copy with the CTA hidden.

### Reaching Mode C

Two options:
- **Option A — fresh browser profile signed in as a user with no
  TVs:** create a new browser profile, navigate to `index.html`, sign
  in via magic link as a fresh test account that has no
  `household_members` rows. (Skip if no such account is available.)
- **Option B — sign out, then navigate:** Window B, sign out via the
  user menu. Confirm `getHomeMode()` returns 'C'. Tile-tap should
  navigate to plain `karaoke/singer.html` (Mode C direct-nav).

### Steps

1. Mode C precondition established (per Option A or B above).
2. Tile-tap Karaoke (or navigate directly to
   `https://mstepanovich-web.github.io/elsewhere/karaoke/singer.html`
   — Mode C direct-nav navigates here without `?code=`).
3. **Observation — Mode C screen-karaoke-info rendering.** Expect:
   - `screen-karaoke-info` renders as the default screen
   - Tap "Start Karaoke" → the handler's step 1 detects missing
     `device_key` → calls `showNoTv()` → the CTA hides, the
     "No TV is bound to this device yet…" no-TV copy appears below
     where the CTA was
   - tv2.html LOG (if a Window A is open as the TV) shows nothing —
     no publish, no nav
   - No DB row created

### Check 5 PASS criteria

- screen-karaoke-info renders without rejecting the load
- Tapping "Start Karaoke" without a bound TV: CTA disappears, no-TV
  copy appears, NO RPC fires, NO DB rows created

### Check 5 FAIL conditions

- Mode C tile-tap doesn't reach singer.html at all (Mode C
  `handleKaraokeTap` broken — unchanged in this build, so a real bug)
- The handler attempts an RPC despite no device_key (the Mode C
  guard at step 1 of `enterKaraokeStartFlow` failed) → FAIL
- A raw error message appears in the status div instead of the
  no-TV copy block being shown

---

## 7. Pass/fail reporting table

Fill in after running:

| Check | Status (PASS / FAIL / BLOCKED) | Notes |
|---|---|---|
| 1 — End-to-end karaoke entry | | |
| 2 — Rejoin path (`?code=`) | | |
| 3 — Cross-app-switch double-confirm | | |
| 4 — Mode B silent no-op | | |
| 5 — Mode C no-TV-bound render | | |

### Phase 3 gates cleared on PASS — sourced from the build spec

The build spec cross-references the gate definitions at
`docs/ITEMS-5-6-BUILD-SPEC.md` §9 D9.2 → `docs/IMMERSIVE-TV-DESIGN-MODEL.md` §13.
Per §13's verbatim listing:

- **Gate #1 — Immersive TV Tier 1.** Cleared 2026-05-25 by commit
  `e33a658` (V8 verification log `docs/SESSION-LOGS/TIER-1-V8-VERIFICATION-LOG.md` §3).
- **Gate #2 — Item 6 (tile-tap must stop creating a session).** §13
  states verbatim: *"The karaoke fix lands in Phase 3; the games fix
  lands in Phase 4."* This build clears the **karaoke half** of gate
  #2. The games half remains open and lands in Phase 4.
- **Gate #3 — Item 5 (karaoke explicit session-creation action).**
  Cleared in full by this build.

This run clears gate #3 fully and gate #2's karaoke half when Checks 1,
3, and 5 all PASS. Gate #2's games half is explicitly out of scope —
Phase 4. (Checks 2 and 4 are non-regression; FAILs there don't block
the gate-clearance call but must be investigated.)

---

## 8. Row inventory — for the cleanup task

Fill in EVERY prod row created or modified during verification. Bundle
with the still-pending Tier 1 §8 cleanup if that hasn't run yet.

### households

| id | name | created_by | created during | notes |
|---|---|---|---|---|
| `581833bb-43b7-4943-8afd-03eb88465281` | V8.1 Verification Household | `8984755f` | (Tier 1 §8) | reused — pre-existing |

### tv_devices

| id | device_key | household_id | display_name | created during | notes |
|---|---|---|---|---|---|
| `a7047be5-3cf0-4fd5-a066-44f8f533d436` | f7b250cf… | 581833bb… | Verification TV V8.1 | (Tier 1 §8) | reused |
| `7bc98d3a-cb25-4587-9702-7fb3e9618fa0` | d0c453b4… | 581833bb… | (null) | (Tier 1 §8) | reused |

### rooms — new/touched during this run

| id | room_code | screen_ref (tv_device_id) | controller_user_id | created during | notes |
|---|---|---|---|---|---|
| | | | | Check 1 | created or reused |
| | | | | Check 3 | reused from games-session room |

### sessions — new/touched during this run

| id | room_id | app | ended_at | created during | notes |
|---|---|---|---|---|---|
| | | games | (ended via cross-app-switch) | Check 3 setup | |
| | | karaoke | (active or ended) | Check 1 | |
| | | karaoke | (active or ended) | Check 3 | same room_id as games session above |

### session_participants — touched during this run

| room_id | user_id | control_role | participation_role | joined_via | created during | notes |
|---|---|---|---|---|---|---|
| | `8984755f` | manager | audience (initial) | rpc_room_create | Check 1 / Check 3 | auto-seated by rpc_room_create or pre-existing from games session |

### Orphan device_keys

(none expected unless you cleared sessionStorage during Mode B/C tests)

---

## 9. Notes / observations

Free-form. Anything unexpected during the run — copy console errors,
screenshots if useful. Specifically note:

- Whether tv2.html received the `launch_app` broadcast in Check 1
  (this is the path that V8.3 found blocked under the pre-Items-5/6
  tile-tap flow — Items 5/6 moves the publisher to a different code
  path, so this is a fresh exercise of the broadcast delivery; if
  it still fails, capture the diagnostic per the V8.3 sender-path
  trace pattern).
- Whether the room-reuse in Check 3 worked or produced the "failed
  to generate a unique room_code after 5 attempts" error (that error
  would indicate the OQ1 fix didn't take — important diagnostic
  signal).
- Whether the legacy-mode end-state in Check 1's Obs 4 looks as
  expected (singer on screen-home, session-level UI dark but mic
  affordances functional). If session-level UI mysteriously WORKS,
  the stale-SELECT debt may have been fixed elsewhere — note that
  too, but it's NOT the success criterion for this build.

---

## End of runbook

After this run completes, hand the §7 pass/fail table + §8 row
inventory back to Claude Code for:
1. The verification result log (mirroring `TIER-1-V8-VERIFICATION-LOG.md`'s
   structure).
2. The combined cleanup task (Items 5/6 rows + still-pending Tier 1 §8
   rows).
