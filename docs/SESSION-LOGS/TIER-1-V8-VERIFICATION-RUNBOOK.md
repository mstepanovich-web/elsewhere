# Tier 1 §8 — Verification Runbook (commit e33a658)

Operational runbook for the §8 verification run of commit `e33a658`
(`feat(tier-1): web-only Immersive TV claim trigger on tv2.html`).
This is a procedure doc, not a durable spec — the spec is
`docs/IMMERSIVE-TV-TIER-1-BUILD-SPEC.md` §8.

Live human-run procedure. Claude Code prepared the materials; a human
runs the browser steps and the SQL queries. Fill in row IDs as you go
in §6 (Row inventory).

---

## 0. Test accounts and prereqs

- **Account A — Mike Stepanovich.**
  UID `8984755f-9534-437a-a2a7-2aeba06c7e9d`.
  (Verified in repo at `docs/SESSION-5-PART-3B-VERIFICATION-LOG.md:37`.)
- **Account B — michael stepanovich.**
  UID `a2ae608d-a819-4a2b-8073-f723d1850d52`.
  (Verified in repo at `docs/SESSION-5-PART-3B-VERIFICATION-LOG.md:39`.)

### Fixed account assignment

- **V8.1 (new-household branch).** Run Q1 (§1). If exactly one account
  has zero household_members rows, that account runs V8.1. If both have
  zero, **Account A** runs V8.1. If both already have memberships,
  **Account A** runs V8.1 anyway and creates an additional household;
  note in §6 that V8.1 produced an additional household for an
  already-householded account.
- **V8.2 (link-existing branch).** Always runs as the V8.1 account
  (Account A in the standard case above), linking laptop B to the
  household V8.1 just created. Account A is that household's admin
  (`rpc_claim_tv_device` sets the founder as `role='admin'`,
  `joined_via='founder'`), so the `is_household_admin` gate on
  `rpc_link_tv_to_existing_household` passes.

Two laptops (or two browser profiles on one laptop) are needed for
V8.1 + V8.2 + V8.3, because each branch needs its own unclaimed
`device_key`. See §2 for how to get clean keys.

You also need:
- A **second surface** for V8.3 (sends a `launch_app` broadcast to the
  laptop). Easiest: a phone running the iOS Elsewhere app, OR a second
  logged-in browser tab loading `index.html`. See V8.3.
- Access to the Supabase SQL Editor at the project console for the
  queries.

---

## 1. Pre-step SQL

Run each query in the Supabase SQL Editor. Capture the result.

### Q1 — Household memberships for both test UIDs

```sql
select
  hm.user_id,
  hm.household_id,
  h.name as household_name,
  hm.role,
  hm.joined_via,
  hm.joined_at
from public.household_members hm
join public.households h on h.id = hm.household_id
where hm.user_id in (
  '8984755f-9534-437a-a2a7-2aeba06c7e9d',  -- Mike Stepanovich (Account A)
  'a2ae608d-a819-4a2b-8073-f723d1850d52'   -- michael stepanovich (Account B)
)
order by hm.user_id, hm.joined_at;
```

**What the result tells you:**

- **Zero rows for an account** → that account is in NO household.
  Eligible for the V8.1 new-household branch as the natural choice.
- **One or more rows for an account** → that account is in a
  household. Eligible for the V8.2 link-existing branch. Still
  eligible for V8.1 — `rpc_claim_tv_device` unconditionally creates a
  *new* household even for someone who's already in one; the account
  ends up in an additional household. Acceptable for verification;
  flag in §6.
- `role` is `'admin'` or `'user'` (`CHECK` constraint at `db/006:97`).
  V8.2 requires the linker be `admin` of the target household
  (`rpc_link_tv_to_existing_household` calls `is_household_admin`).
  `joined_via` is one of `'founder' | 'pre_invite' | 'scan_approved'`
  (`db/006:99`); the V8.1 founder is created with
  `joined_via='founder'`.

### Q2 — `tv_devices` rows by device_key

After you've decided what device_keys you'll test with (see §2 for how
to obtain them), run this with the actual keys filled in:

```sql
select
  td.id            as tv_device_id,
  td.device_key,
  td.household_id,
  h.name           as household_name,
  td.display_name,
  td.registered_by,
  td.registered_at,
  td.last_seen_at
from public.tv_devices td
left join public.households h on h.id = td.household_id
where td.device_key in (
  'PASTE-DEVICE-KEY-FROM-LAPTOP-A-LOCALSTORAGE',
  'PASTE-DEVICE-KEY-FROM-LAPTOP-B-LOCALSTORAGE'
);
```

**What the result tells you:**

- **Zero rows for a device_key** → unclaimed. Ready for a fresh-claim
  test (V8.1 or V8.2).
- **One row for a device_key** → already claimed. NOT usable for a
  fresh-claim test until you either use a different browser/profile
  that mints a new key, or clear the key from localStorage and reload
  tv2.html (which mints a new one — note the orphan in §6).

**"Ready to test V8.1":** at least one device_key returns zero rows.
**"Ready to test V8.2":** a DIFFERENT device_key (separate from V8.1's)
also returns zero rows.

If both keys come back already-claimed: **stop**, decide how to get a
clean key per §2 before proceeding.

---

## 2. Getting clean unclaimed device_keys

`tv2.html` mints a `device_key` once per browser (or browser profile)
via `getOrCreateDeviceKey()` (`tv2.html:451`) and persists it in
`localStorage` under key `'elsewhere.tv.device_key'`. Same browser →
same key forever. To get a fresh key:

**Method A — fresh browser profile (cleanest).**
- Chrome: People → Add → new profile → open `tv2.html` in that
  profile. Each profile has isolated localStorage.
- Firefox: Profile Manager (`about:profiles`) → Create New Profile.
- Safari: limited — use a separate macOS user account, or use
  Method B.

**Method B — clear localStorage in the current browser.**
1. Open `tv2.html` (you'll see the QR claim screen).
2. Open DevTools (`Cmd-Opt-I` on Mac).
3. Console tab. Paste: `localStorage.removeItem('elsewhere.tv.device_key')`
   and press Enter.
4. Hard-reload the page (`Cmd-Shift-R`).
5. `tv2.html` mints a new key on boot. To inspect the new key, paste in
   console: `localStorage.getItem('elsewhere.tv.device_key')`.

**Caveat with Method B:** if the previous key was a claimed
`tv_devices` row, that row stays in prod after you mint a new one —
the row is now orphaned (no browser holds its key). Note the orphan
device_key in §6 so cleanup catches it.

**Inspecting the current device_key on a laptop (without changing it):**

DevTools console:
```js
localStorage.getItem('elsewhere.tv.device_key')
```

Returns the UUID-shaped string (or `null` if tv2.html has never run in
this browser). Capture this value — you'll need it for Q2 and the
post-hoc verification SQL in V8.1 / V8.2.

**For this verification you need two distinct unclaimed device_keys**
(one for V8.1, one for V8.2). The cleanest setup is two fresh browser
profiles, A and B.

---

## 3. Per-item run checklists

### V8.1 — New-household branch

**Goal:** prove `rpc_claim_tv_device` is reached from `tv2.html` and
creates a household + a `tv_devices` row, lands on `screen-apps`.

**Setup:**
- Laptop / browser profile **A** (per §0 assignment).
- Confirm via §1 Q2 that this browser's `device_key` (from §2) is
  UNCLAIMED.
- Account A must have a current authenticated session in this browser.
  If not signed in: open `index.html` first, sign in via magic link
  (check the email), then navigate to `tv2.html`.

**Steps:**

1. Navigate to `https://mstepanovich-web.github.io/elsewhere/tv2.html`
   on laptop A.
2. **Observation 1.** Expect: `screen-claiming` renders. Verify:
   - Title: "Set up this TV"
   - Subtitle: "Scan with your iPhone's camera to claim this TV into
     your household."
   - QR code visible (encodes `claim.html?device_key=…`)
   - Below the QR: backup code (6 hex chars uppercase)
   - **NEW (Tier 1):** "Set up without the app →" button below the
     backup code
3. Tap the **"Set up without the app →"** button.
4. **Observation 2.** Expect: page transitions to `tv2-screen-claim`
   (the new picker screen). Verify:
   - Top: "← Back" link, page title "Claim This TV"
   - Page sub: "Adding this TV to your household."
   - "TV name" input (empty, placeholder "e.g. Living Room TV")
   - "Household" select — first option "Create a new household"; if
     the test account is in any households, those are listed below
   - "New household name (optional)" input visible (because select
     defaults to `__new__`)
   - Empty status div, "Claim TV →" submit button
5. Fill in:
   - TV name: `Verification TV V8.1`
   - Household select: leave as "Create a new household"
   - New household name: `V8.1 Verification Household`
6. Click **"Claim TV →"**.
7. **Observation 3.** Expect:
   - Status text shows "Claiming…" briefly
   - Then "Claimed — opening apps…" briefly
   - Page transitions to `screen-apps`:
     - Household name "V8.1 Verification Household" in the apps header
     - "Use your phone to select an app" subtitle
     - Three app tiles: Karaoke, Games, Wellness (Wellness disabled)

**Post-hoc SQL verification:**

```sql
select
  h.id            as household_id,
  h.name          as household_name,
  h.created_by    as household_created_by,
  h.created_at    as household_created_at,
  td.id           as tv_device_id,
  td.device_key,
  td.display_name as tv_display_name,
  td.registered_by,
  td.registered_at,
  hm.role,
  hm.joined_via
from public.households h
join public.tv_devices td on td.household_id = h.id
left join public.household_members hm
  on hm.household_id = h.id and hm.user_id = h.created_by
where h.name = 'V8.1 Verification Household'
  and td.device_key = 'PASTE-DEVICE-KEY-FROM-LAPTOP-A'
order by h.created_at desc
limit 1;
```

**V8.1 passes when:**

- One row returned.
- `household_created_by = ` Account A's UID.
- `tv_devices.registered_by = ` Account A's UID.
- `tv_devices.device_key = ` laptop A's device_key.
- `household_members.role = 'admin'`, `joined_via = 'founder'`.
- Laptop A is on `screen-apps` showing the right household name.

**Record in §6:** household.id, tv_devices.id, device_key, and the
auto-created household_members row.

---

### V8.2 — Link-existing branch

**Goal:** prove `rpc_link_tv_to_existing_household` is reached and
links the laptop to the V8.1-created household.

**Setup:**
- Laptop / browser profile **B** (a DIFFERENT device_key from V8.1).
- Account A signs in on laptop B (Account A is the V8.1 household's
  admin — per §0 fixed assignment).
- Confirm via §1 Q2 that laptop B's device_key is UNCLAIMED.

**If a second unclaimed device_key isn't available:** stop here, mark
V8.2 as **BLOCKED**, report which §2 method you tried.

**Steps:**

1. Navigate to `tv2.html` on laptop B.
2. **Observation 1.** Expect: `screen-claiming` with THIS laptop's QR
   (different device_key than laptop A's).
3. Tap **"Set up without the app →"**.
4. **Observation 2.** Expect: `tv2-screen-claim` opens. The household
   picker now includes the V8.1-created household
   ("V8.1 Verification Household") alongside "Create a new household".
5. Fill in:
   - TV name: `Verification TV V8.2`
   - Household select: choose **"V8.1 Verification Household"** (not
     `__new__`)
   - Verify the "New household name (optional)" row **hides** when you
     select a non-`__new__` option.
6. Click **"Claim TV →"**.
7. **Observation 3.** Expect:
   - "Claiming…" → "Claimed — opening apps…" → `screen-apps`
   - Apps header shows "V8.1 Verification Household"

**Post-hoc SQL verification:**

```sql
select
  td.id            as tv_device_id,
  td.device_key,
  td.household_id,
  h.name           as household_name,
  td.display_name  as tv_display_name,
  td.registered_by,
  td.registered_at
from public.tv_devices td
join public.households h on h.id = td.household_id
where td.device_key = 'PASTE-DEVICE-KEY-FROM-LAPTOP-B';
```

**V8.2 passes when:**

- One row returned.
- `household_id = ` the V8.1 household's UUID (the EXISTING household,
  not a new one).
- `household_name = 'V8.1 Verification Household'`.
- `device_key = ` laptop B's device_key (distinct from laptop A's).
- `tv_devices.registered_by = ` Account A's UID.
- Laptop B is on `screen-apps`.

**No new `household_members` row should be created** by this branch
(the linker was already a member). Sanity check:

```sql
select count(*) from public.household_members
where household_id = 'PASTE-V8.1-HOUSEHOLD-ID';
-- Expect: same count as before V8.2 (1, if only Account A is a member).
```

**Record in §6:** tv_devices.id, device_key (household.id is V8.1's —
same row).

---

### V8.3 — `launch_app` reception on claimed laptop

**Goal:** prove the claimed laptop (post-V8.1) is in `screen-apps`,
subscribed to its `tv_device:<device_key>` Supabase realtime channel
(set up at boot — `tv2.html:489` `subscribeToHandoffChannel`), and
reacts correctly to a `launch_app` broadcast (handled at
`tv2.html:634` `handleLaunchApp`).

**Scope note:** V8.3 tests the tv2.html **SUBSCRIBER** side. If the
broadcast doesn't arrive on laptop A, diagnose "did the sender send"
**before** concluding that Tier 1 broke reception. Tier 1 made no
change to the subscription wiring (boot path untouched) — the most
likely cause of an arrival failure is upstream (the sender). The
broadcast sender is the shell tile-tap path in `index.html:3161`
(`handleTvRemoteTileTap`), which calls `publishLaunchApp` at
`index.html:3328`. Verify that path completed: a session row should
exist for the room; the LOG panel on the sending surface should not
show errors.

**Setup:**
- Laptop A is on `screen-apps` (post-V8.1). Leave it open.
- Tap the bottom-left **LOG** affordance to open the log panel so
  incoming events are visible.

**Stage the broadcast — preferred option:**

Open `https://mstepanovich-web.github.io/elsewhere/index.html` on a
phone or second browser profile, signed in as Account A (the
household admin of "V8.1 Verification Household"). The shell should
auto-bind to laptop A via `enterYourTvsFlow` / `enterHomeForTv`. Tap a
tile (Karaoke or Games). This fires `handleTvRemoteTileTap` →
`rpc_room_create` + `rpc_session_start` + `publishLaunchApp`. Laptop A
should react.

This also creates one `rooms` row and one `sessions` row tied to the
TV. Track both for cleanup (§6).

**Observation:**

- On `launch_app` with `app='karaoke'`: laptop A navigates (full-page)
  to `karaoke/stage.html?room=<room_code>`.
- On `launch_app` with `app='games'`: laptop A navigates to
  `games/tv.html?room=<room_code>`.
- LOG panel on laptop A shows lines like
  `realtime: received launch_app app=karaoke room=ABCDEF` before the
  navigation.

**V8.3 passes when:** laptop A receives the broadcast (visible in LOG
or by page navigation) and lands on the per-app TV surface.

**Record in §6:** `rooms.id` and `sessions.id` from the just-created
session.

---

### V8.5 — Unregressed surfaces + unauthed gate

**Goal:** confirm tv2.html's three existing screens still render
correctly, and the new unauthed-click path shows the inline prompt
(not a raw 42501).

**Setup:**
- Fresh browser profile **C** (a third clean device_key) for the
  screen-claiming render + unauthed click test. Or reuse an existing
  profile AFTER clearing localStorage per §2 Method B.
- DO NOT sign in.

**Steps:**

1. Navigate to `tv2.html` on profile C with NO authenticated session.
2. **Observation 1 (screen-claiming render).** Expect:
   - Title, subtitle, QR code, backup code all render
   - **The new "Set up without the app →" button visible below the
     backup code**
   - Empty space (sign-in prompt hidden)
3. Click **"Set up without the app →"** while not signed in.
4. **Observation 2 (auth gate).** Expect:
   - The page does **NOT** navigate. You stay on `screen-claiming`.
   - The inline sign-in prompt appears below the button. Exact text
     (curly quotes are the committed characters — `tv2.html:279`):

     > Sign in to Elsewhere on this browser first, then tap “Set up
     > without the app” again.

   - No `alert()`, no error banner, no 42501.
   - The LOG panel shows: `tv2-claim: not authenticated — showing
     sign-in prompt`.
5. Sign in on this browser via `index.html`, then return to `tv2.html`.
   Tap the button again.
6. **Observation 3.** Expect: the inline prompt is hidden (re-set at
   the top of every `enterTv2ClaimScreen` entry), and the page
   navigates to `tv2-screen-claim`. (Do NOT submit — cancel via
   "← Back" to return to screen-claiming. This is a gate test, not a
   claim test.)

**Verify the other two existing screens are unregressed:**

7. **screen-signin render.** To land here, use laptop A's profile
   (already claimed via V8.1). Sign out via `index.html`'s user menu,
   then navigate back to `tv2.html`. Expect:
   - Title "Sign in to this TV"
   - QR + household-name caption
     ("V8.1 Verification Household · Verification TV V8.1") + "Not
     your TV? Reset" link
   - No regression from Tier 1 (Tier 1 added markup only to
     screen-claiming, not screen-signin).
8. **screen-apps render.** Sign back in on laptop A. `tv2.html` should
   land on `screen-apps`. Confirm header + 3 tiles unchanged.

**Non-regression argument for `enterYourTvsFlow` and the presence
question:** both live entirely in `index.html`, which `e33a658` did
not modify. By construction, unchanged. No live test required (record
this on the report).

**V8.5 passes when:** all three existing screens render correctly with
the additions (only `screen-claiming` is affected by Tier 1), and the
unauthed-click inline prompt fires without reaching the form or any
42501.

---

## 4. V8.4 — iOS-app claim path (non-regression, no live test)

V8.4 is satisfied by **structural non-regression**, not a live re-test:

- Commit `e33a658` modifies only `tv2.html` (+224 lines, 0 removed;
  confirm with `git show --stat e33a658`).
- `index.html`, `claim.html`, and `shell/auth.js` are untouched.
- The iOS-claim path is: iOS app → `elsewhere://tv-claim?device_key=…`
  → `shell/auth.js`'s `appUrlOpen` listener → dispatches
  `elsewhere:tv-claim` CustomEvent → `index.html`'s listener →
  `onTvClaimDeepLink` → `enterTvClaimScreen` → `submitTvClaim`
  (`index.html:1934`) → `rpc_claim_tv_device` /
  `rpc_link_tv_to_existing_household`. Every file and function in this
  chain is untouched by `e33a658`.
- The iOS-claim path is therefore unchanged by construction.

**V8.4: PASS (non-regression argument).** No iOS device test required
for this commit. (A full hardware sync per CLAUDE.md doctrine is still
appropriate at session close, but not for V8.4 specifically.)

---

## 5. Reporting — per-item pass/fail

Fill in after running:

| Item | Status (PASS / FAIL / BLOCKED) | Notes |
|---|---|---|
| V8.1 — new-household branch | | |
| V8.2 — link-existing branch | | |
| V8.3 — launch_app reception | | |
| V8.4 — iOS path non-regression | PASS — structural | (Pre-filled per §4) |
| V8.5 — existing screens + auth gate | | |

---

## 6. Row inventory — for the cleanup task

Fill in EVERY prod row created during verification. The cleanup task
deletes these.

### Households

| household.id | name | created_by (UID) | created during | notes |
|---|---|---|---|---|
| | V8.1 Verification Household | | V8.1 | |

### tv_devices

| tv_devices.id | device_key | household_id | display_name | registered_by | created during | notes |
|---|---|---|---|---|---|---|
| | | | Verification TV V8.1 | | V8.1 | |
| | | | Verification TV V8.2 | | V8.2 | |

### household_members (newly created — NOT existing memberships)

| household_id | user_id | role | joined_via | created during | notes |
|---|---|---|---|---|---|
| | | admin | founder | V8.1 (auto, by `rpc_claim_tv_device`) | |

### rooms (from V8.3)

| rooms.id | screen_ref | owner_user_id | room_code | created during | notes |
|---|---|---|---|---|---|
| | | | | V8.3 | |

### sessions (from V8.3)

| sessions.id | room_id | app | ended_at | created during | notes |
|---|---|---|---|---|---|
| | | | | V8.3 | |

### Orphan device_keys (from clearing localStorage)

| device_key | tv_devices.id (if still in DB) | notes |
|---|---|---|
| | | E.g. "old key in profile A before §2 Method B cleared it" |

---

## 7. Notes / observations

Free-form. Anything unexpected during the run — copy console errors,
screenshots if useful, paths you took that diverged from the steps
above. Future verification runs read this section first.

---

## End of runbook

After this run completes, hand the §5 pass/fail table + the §6 row
inventory back to Claude Code for:
1. The §8 verification report (consolidated against the spec).
2. The cleanup task (deletes the inventoried rows).
