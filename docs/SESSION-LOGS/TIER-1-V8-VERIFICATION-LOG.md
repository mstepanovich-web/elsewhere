# Tier 1 §8 — Verification Result Log (commit e33a658)

**Commit verified:** `e33a658` — `feat(tier-1): web-only Immersive TV claim trigger on tv2.html`
**Run date:** 2026-05-25
**Spec verified against:** `docs/IMMERSIVE-TV-TIER-1-BUILD-SPEC.md` §8
**Procedure used:** `docs/SESSION-LOGS/TIER-1-V8-VERIFICATION-RUNBOOK.md`
**Environment:** prod Supabase, GitHub Pages bundle at `https://mstepanovich-web.github.io/elsewhere/`
**Test account:** Mike Stepanovich — UID `8984755f-9534-437a-a2a7-2aeba06c7e9d`

This is the durable result record for the §8 run. The runbook is the
procedure; this log is the outcome. Together they document what was
verified and what wasn't.

---

## 1. Per-item results

### V8.1 — New-household branch — **PASS**

The tv2.html web claim trigger reached `rpc_claim_tv_device` and
completed end-to-end:

- **Client-side observation:** screen-claiming → "Set up without the
  app →" → tv2-screen-claim (auth-gated, passed) → form submitted →
  status text "Claiming…" → "Claimed — opening apps…" → screen-apps
  rendered with household name "V8.1 Verification Household" and the
  three app tiles. tv2.html LOG showed the success trace:
  `tv2-claim: success, re-rendering state` → `renderCurrentState` re-ran →
  `rpc_tv_is_registered` returned registered → `showAppsScreen` fired.
- **SQL-side observation:**
  - One `households` row created — id `581833bb-43b7-4943-8afd-03eb88465281`,
    name "V8.1 Verification Household", `created_by = 8984755f`.
  - One `tv_devices` row created — id `a7047be5-3cf0-4fd5-a066-44f8f533d436`,
    `display_name = "Verification TV V8.1"`, `device_key = f7b250cf-7e28-4645-9601-d3e48d27bf95`,
    `household_id = 581833bb…`, `registered_by = 8984755f`.
  - One `household_members` row created automatically by
    `rpc_claim_tv_device` — `(household_id=581833bb…, user_id=8984755f,
    role='admin', joined_via='founder')`.

Spec §8 pass conditions for V8.1 — all met.

### V8.2 — Link-existing-household branch — **PASS**

The tv2.html web claim trigger reached `rpc_link_tv_to_existing_household`
on a second device_key and linked to the V8.1 household:

- **Client-side observation:** tv2-screen-claim on the second laptop's
  device_key showed the V8.1 household in the picker; selecting it
  hid the "New household name" row as designed; submit → "Claimed —
  opening apps…" → screen-apps with the V8.1 household name.
- **SQL-side observation:**
  - One additional `tv_devices` row created — id `7bc98d3a-cb25-4587-9702-7fb3e9618fa0`,
    `device_key = d0c453b4-13a5-4953-98b2-de27379f39b4`,
    `household_id = 581833bb…` (the EXISTING V8.1 household, not a new
    one), `registered_by = 8984755f`.
  - `household_members` count for household `581833bb…` unchanged at 1
    after V8.2 (sanity check passed — no new membership row was
    created, consistent with the link branch not adding members).

One anomaly observed — see Deferred item 1.

Spec §8 pass conditions for V8.2 — link-side behavior met; the
display-name discrepancy is recorded but does not invalidate the
branch (the link itself succeeded).

### V8.3 — `launch_app` reception — **BLOCKED (not a Tier 1 regression)**

The claimed TV did NOT receive a `launch_app` broadcast when the tester
drove the controller through the shell tile-tap path. tv2.html on the
claimed laptop showed `realtime: subscribed` at boot and stopped
logging after `heartbeat: ok` — i.e. the subscriber was alive and
waiting for an event that never arrived.

**Why this is BLOCKED, not FAIL:**

Tier 1 (commit `e33a658`) modified only `tv2.html` (+224 / −0). It did
NOT touch:

- the realtime subscription wiring in `tv2.html` (`subscribeToHandoffChannel`
  at line 489, the `launch_app` event handler at line 634 — both
  pre-existing, unchanged by `e33a658`);
- `publishLaunchApp` in `shell/realtime.js:128` (sender lib — unchanged);
- `handleTvRemoteTileTap` in `index.html:3161` (the ONLY publisher
  call site, at line 3328 — unchanged);
- any `index.html` UI or routing on the controller side.

The subscriber side was confirmed healthy in this run. The sender side
is the cause and is pre-existing, untouched-by-Tier-1 behavior. The
in-session sender-path trace identified two suspected contributing
factors: the shell tile-tap / room-reuse path failing to publish
under the conditions tested (room `SYNKZ6` observed reused as stale;
no fresh `publishLaunchApp` call observed in the controller's
traces), and — hypothesized but not confirmed — the known-broken
"Are you at home?" presence prompt possibly leaving the controller
in Mode B (where the karaoke tile is a silent no-op per
`index.html:2985`). The controller's mode during the failed attempts
was not directly verified in this run; the Mode B factor is a
plausibility from the code paths, not an observation.

V8.3 verifies infrastructure that Tier 1 does NOT build. Recording
BLOCKED with the cause documented (Deferred item 2). See §3 for gate
status implications.

### V8.4 — iOS-app claim path — **PASS, by construction**

Commit `e33a658` is `tv2.html`-only (`git show --stat e33a658`:
1 file changed, 224 insertions, 0 deletions). The iOS-claim path —
`elsewhere://tv-claim` → `shell/auth.js` `appUrlOpen` handler →
`elsewhere:tv-claim` CustomEvent → `index.html`'s `onTvClaimDeepLink`
→ `enterTvClaimScreen` → `submitTvClaim` → `rpc_claim_tv_device` /
`rpc_link_tv_to_existing_household` — runs through `index.html`,
`claim.html`, and `shell/auth.js`, all of which are untouched by
`e33a658`. Path is unchanged by construction. No iOS device re-test
required for V8.4 specifically.

### V8.5 — Unregressed surfaces + unauthed gate — **PASS**

- **screen-claiming render:** loaded correctly with the new "Set up
  without the app →" button below the backup code. QR + backup code
  + title + subtitle all rendered unchanged.
- **Unauthed click gate:** clicking the button while signed out
  showed the inline sign-in prompt (curly-quoted "Set up without the
  app" matching the committed markup). The page did NOT navigate to
  tv2-screen-claim, did NOT call the claim RPC, did NOT produce a raw
  42501 error. tv2.html LOG showed
  `tv2-claim: not authenticated — showing sign-in prompt`.
- **screen-apps:** observed throughout the run as the V8.1 / V8.2
  landing screen — rendered correctly with the V8.1 household name
  in the header and the 3 app tiles. Unregressed.
- **screen-signin:** unregressed by construction. Tier 1's markup
  additions are confined to `screen-claiming` (the new button + inline
  prompt at `tv2.html:278–279`); `screen-signin` (`tv2.html:253–264`)
  is untouched by `e33a658`. Not explicitly observed in this run.
- `enterYourTvsFlow` and the proximity question both live in
  `index.html` which `e33a658` did not modify — unchanged by
  construction (no live test required for these specifically).

Spec §8 pass conditions for V8.5 — all met.

---

## 2. Pass/fail summary

| Item | Status |
|---|---|
| V8.1 — new-household branch | **PASS** |
| V8.2 — link-existing branch | **PASS** (with one anomaly — Deferred item 1) |
| V8.3 — launch_app reception | **BLOCKED** (pre-existing non-Tier-1 cause — Deferred item 2) |
| V8.4 — iOS path non-regression | **PASS** (structural) |
| V8.5 — existing screens + auth gate | **PASS** |

---

## 3. Gate status — Phase 3 gate #1 cleared

Every §8 item that Tier 1 itself is responsible for — V8.1, V8.2, V8.4,
V8.5 — passed. V8.3 is BLOCKED on a documented, pre-existing,
non-Tier-1 condition that exists in code paths `e33a658` did not
touch.

**Phase 3 gate #1** (per `docs/IMMERSIVE-TV-DESIGN-MODEL.md` §13) —
the web-only Immersive TV claim trigger — is **CLEARED**.

The other two Phase 3 gates (items 5/6 — session-creation rework) are
separate workstreams and are not affected by this verification's
outcome.

---

## 4. Row inventory — prod test data created (for the cleanup task)

All rows created during this verification, for later cleanup:

### households

| id | name | created_by | created during |
|---|---|---|---|
| `581833bb-43b7-4943-8afd-03eb88465281` | V8.1 Verification Household | `8984755f` (Mike) | V8.1 |

### tv_devices

| id | device_key | household_id | display_name | registered_by | created during |
|---|---|---|---|---|---|
| `a7047be5-3cf0-4fd5-a066-44f8f533d436` | `f7b250cf-7e28-4645-9601-d3e48d27bf95` | `581833bb…` | Verification TV V8.1 | `8984755f` | V8.1 |
| `7bc98d3a-cb25-4587-9702-7fb3e9618fa0` | `d0c453b4-13a5-4953-98b2-de27379f39b4` | `581833bb…` | (null — see Deferred 1) | `8984755f` | V8.2 |

### household_members

| household_id | user_id | role | joined_via | created during |
|---|---|---|---|---|
| `581833bb…` | `8984755f` | admin | founder | V8.1 (auto, by `rpc_claim_tv_device`) |

### rooms / sessions

V8.3 attempts via the shell tile-tap path may have created `rooms`
and/or `sessions` rows under Mike's account. Room code `SYNKZ6`
was observed in the in-session diagnostic trace. The cleanup task
should query `rooms` and `sessions` for rows created
`>= 2026-05-25` and owned by / controlled by Mike's UID before
deleting, so any V8.3-attempt rows are caught regardless of which
specific room codes they used.

---

## 5. Deferred items

Filed for follow-up; not fixed in this run.

### Item 1 — V8.2 link-existing branch does not persist `tv_display_name`

The tester entered "Verification TV V8.2" in the TV-name field before
submitting the link-to-existing-household flow. The resulting
`tv_devices` row (id `7bc98d3a…`) has `display_name = NULL`.

The new-household branch in the same form correctly persisted
`display_name = "Verification TV V8.1"` to the V8.1 tv_devices row.
The discrepancy is between the two branches of the same picker, not a
client-side missing field.

Verified against the RPC body in `db/006_household_and_tv_devices.sql`:
the signature `rpc_link_tv_to_existing_household(p_device_key text,
p_household_id uuid)` has only those two arguments (lines 330–333),
and the body's INSERT writes only `(household_id, device_key,
registered_by)` (line 354) — `display_name` has no slot in the
existing call and is left NULL on the inserted row. Compare with
`rpc_claim_tv_device` (lines 285–321) which takes
`(p_device_key, p_household_name, p_tv_display_name)` and writes
`display_name` in its INSERT. So the discrepancy is inherited from
the index.html original, not introduced by Tier 1; but the TV-name
field on the form implies the field will be persisted, so the UX is
misleading.

Minor; the link itself succeeded. Two possible follow-ups: (a) hide
the TV-name field in the link branch (consistent with current RPC
shape), or (b) add `p_tv_display_name` to
`rpc_link_tv_to_existing_household` and pass it through. Worth a look;
not a Tier 1 blocker.

### Item 2 — `launch_app` not delivered via shell tile-tap path (this run's V8.3 cause)

Under the conditions tested in this run, the controller's shell
tile-tap path did NOT publish a `launch_app` broadcast to the claimed
TV's `tv_device:<device_key>` channel. The subscriber side
(`tv2.html` on the claimed laptop) was healthy — `realtime: subscribed`
logged at boot — and stopped logging after `heartbeat: ok`, indicating
no event ever arrived.

The cause is pre-existing in `index.html` and was traced during this
run (see the in-session sender-path investigation against the live
state). Three contributing factors identified:

1. **Stale room reuse (observed).** A pre-existing room `SYNKZ6` was
   being reused by `handleTvRemoteTileTap`'s room-resolution logic
   (`index.html:3186–3207`) — when a cached room exists for the
   bound TV, the path reuses it instead of calling `rpc_room_create`.
   The reused state did not lead to a fresh `publishLaunchApp` call
   under the path the tester took.
2. **Suspected Mode B trap (hypothesis, not observed).** Linked to
   Deferred item 3's known-broken proximity prompt: IF the proximity
   answer for this TV was 'no' (Mode B) during the failed attempts,
   the karaoke tile is a silent no-op per `index.html:2985`. The
   controller's mode at the time was not directly verified in this
   run; this factor is a plausibility from the code paths surfaced
   in the sender-path trace, not a confirmed observation. Recorded
   to consider during investigation, not as established cause.
3. **No publisher call site outside `handleTvRemoteTileTap`
   (structural).** Verified by `grep -rn "publishLaunchApp" index.html
   karaoke/ games/ shell/`: one publisher (`index.html:3328`),
   reachable only from `handleTvRemoteTileTap`. Any path that bypasses
   `handleTvRemoteTileTap` cannot fire `launch_app`. Join-by-room-code
   surfaces (`singer.html?code=…`, `player.html?room=…`) bypass it
   by design and never publish.

Pre-existing `index.html` behavior. Tier 1's `e33a658` did not modify
any of the involved code paths (`handleTvRemoteTileTap`,
`publishLaunchApp`, `handleHomeTileTap`, the `tv2.html` realtime
subscription, the `handleLaunchApp` receiver). Tracked here because
it blocked V8.3 in this run.

Follow-up: needs a dedicated investigation of the room-reuse /
stale-session interaction in `handleTvRemoteTileTap`, paired with
the presence-prompt fix (Deferred item 3) so the suspected-Mode-B
factor can be either confirmed or ruled out. Likely overlaps with
the items 5/6 build spec (which restructures tile-tap UX — see
`docs/ITEMS-5-6-BUILD-SPEC.md`) but is distinct from it: items 5/6
move session creation off tile-tap; this issue is that tile-tap
doesn't publish even when it should under current code.

### Item 3 — "Are you at home?" presence prompt is non-functional (pre-existing, known)

Recorded here for completeness because it contributed to V8.3 being
blocked. The `index.html` proximity banner ("Are you at home?" — markup
at `index.html:1156–1166`) renders correctly, but clicking "Yes, I'm
at home" does not transition state to Mode A as expected. Pre-existing,
documented elsewhere prior to this run. Out of scope for Tier 1; noted
because it intersected with the V8.3 BLOCKED outcome via the Mode A/B
gate in `handleHomeTileTap`.

---

## 6. References

- Spec: `docs/IMMERSIVE-TV-TIER-1-BUILD-SPEC.md` §8 (verification
  criteria).
- Procedure: `docs/SESSION-LOGS/TIER-1-V8-VERIFICATION-RUNBOOK.md`
  (the runbook this log answers).
- Design model: `docs/IMMERSIVE-TV-DESIGN-MODEL.md` §13 (Phase 3 gate
  taxonomy — gate #1 is this; gates #2 and #3 are items 5/6).
- Commit: `e33a658` — `feat(tier-1): web-only Immersive TV claim
  trigger on tv2.html`.

---

## End of log
