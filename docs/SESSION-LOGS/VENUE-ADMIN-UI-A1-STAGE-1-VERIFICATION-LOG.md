# Venue Admin UI Stage A1 (Stage 1) — Verification Result Log

**Commit verified:** `9cf4b70` (Stage A1 — db/034 + admin-venues.html) + `606674f` (path-pattern fix applied after initial Check 1 failure; see Bug 1 below)
**Migration applied to prod:** `db/034_venue_default_update_rpc.sql` on 2026-05-26 via Supabase SQL Editor (recorded in `db/MIGRATIONS_APPLIED.md` row 41)
**Run date:** 2026-05-26
**Environment:** prod GitHub Pages (https://mstepanovich-web.github.io/elsewhere/) + prod Supabase
**Verifier:** Mike Stepanovich, signed-in as platform admin (UID `8984755f-9534-437a-a2a7-2aeba06c7e9d`)
**Outcome:** **PASS** — all six §8.1 checks pass against prod. Two bugs were caught during verification and fixed before declaring PASS; both are recorded honestly below — Stage A1 does NOT ship in a single propose-apply cycle, it took one path-pattern fix and one anon-grant fix.

This log records the post-deploy verification of Stage A1 against the build spec `docs/VENUE-ADMIN-UI-A1-BUILD-SPEC.md` §8.1. Stage 2 (audio renderer + audio anchor authoring + 19 audio-only venue translations) is OUT OF SCOPE for this verification — it ships as its own propose-pause cycle later.

---

## Outcome — all six §8.1 checks PASS

### Check 1 — Admin-only access

The boot sequence's three branches (signed-out → signin-gate; signed-in non-admin → admin-gate; signed-in admin → editor) were exercised in three browser contexts:

- **Signed-out browser:** admin-venues.html loaded → "Sign in required" gate card rendered with link to `index.html`. No editor visible. PASS.
- **Signed-in non-admin** (a separate test account without `profiles.is_platform_admin = true`): admin-venues.html loaded → "Not authorized" gate card rendered, terminal (no escape to the editor). PASS.
- **Signed-in admin (Mike):** admin-venues.html loaded → editor rendered with the 26-venue sidebar grouped by category. The user-display in the header showed Mike's email + the ADMIN badge. PASS.

> Check 1 ultimately PASSED on the post-fix commit (`606674f`). The initial verification against `9cf4b70` FAILED — admin-venues.html loaded but the sidebar was empty because shell modules + assets 404'd. Root cause and fix recorded as Bug 1 below.

### Check 2 — Read-only identity display

Selected several venues from the sidebar (stadium, default, hollywoodbowl, vegas). For each:
- `venue_id`, `name`, `icon`, `category` rendered in the read-only header per D1.
- Skybox preview image loaded from `venues/<id>.jpg` (e.g. `venues/stadium.jpg`). For `default` (`skyboxId: null`), the "(no skybox)" placeholder rendered instead of the image.
- No editable affordance was present on the identity fields. PASS.

### Check 3 — Edit + save flow

Selected `stadium`. Edited `back_yaw` from its pre-test value `-247` to `-248`. Verified:
- Save button enabled when the field went dirty (was disabled prior to edit). PASS.
- Status text changed `(unsaved changes)` → `Saving…` → `Saved` briefly on click.
- Refresh the page; the saved value `-248` persisted (read back from the database). PASS.
- Opened `karaoke/stage.html?venue=stadium` in a new tab; the change was reflected per karaoke's existing rendering. PASS.

(See Test artifacts section for the full edit sequence and revert.)

### Check 4 — Dirty-state navigation warning

Edited stadium's `back_yaw` again, setting it to `-250` (dirty, not yet saved). Attempted to close the tab. The browser fired the native `beforeunload` confirm dialog ("Leave site? Changes you made may not be saved" or equivalent per browser locale). PASS.

Clicked Cancel; confirmed the editor still showed the dirty state with `-250` in the input. Clicked the in-UI "Discard changes" button to drop the dirty buffer; the input reverted to the last saved value (`-247` at this point — see Test artifacts for the full sequence). Re-attempted tab close; the beforeunload warning no longer fired (`state.dirty.size` had returned to 0). PASS.

`-250` was never persisted to the database — it lived only in the in-memory dirty buffer and was discarded via the in-UI "Discard changes" button.

### Check 5 — RPC authority gate

From a signed-in non-admin browser, opened DevTools console and ran:
```js
await window.sb.rpc('rpc_venue_default_update', {
  p_venue_id: 'stadium',
  p_partial: { back_yaw: 999 }
});
```
Response: error with code `42501` (`insufficient_privilege`), message `not a platform admin`. PASS.

The same call from the admin browser succeeded (changed back_yaw to the test value), confirming the gate distinguishes admin from non-admin and not just unauthenticated callers.

### Check 6 — Per-venue verification SQL

Ran AFTER Check 3's save (with `back_yaw = -248` as the most recent persisted value; the subsequent revert to `-247` and Check 4's discard sequence had not yet occurred at this point):

```sql
select venue_id, back_yaw, back_pitch, front_yaw, front_pitch,
       camera_fov, motion, ambient, updated_at, updated_by
from public.venue_defaults
where venue_id = 'stadium';
```

Returned one row with:
- `back_yaw = -248` (Check 3's saved value)
- `updated_by = 8984755f-9534-437a-a2a7-2aeba06c7e9d` (Mike's UID)
- `updated_at` ≈ time of Check 3's save (2026-05-26 UTC)
- Other columns unchanged from their pre-test values

PASS. The audit trail is correctly populated by the RPC.

---

## Bugs caught during verification — characterized + fixed

Stage A1 did NOT pass on the first cycle. Two distinct bugs were caught and resolved before the PASS above was declared. Recording both honestly so the propose-pause-apply-verify rhythm is preserved in the record.

### Bug 1 — GitHub Pages subpath path bug (`admin-venues.html`)

**Symptom:** Check 1's admin browser loaded `admin-venues.html`, the page rendered the header + an empty sidebar + the empty-state placeholder; the venue list never populated. Browser console showed:

```
GET https://mstepanovich-web.github.io/shell/auth.js  404 (Not Found)
GET https://mstepanovich-web.github.io/shell/venue-settings.js  404 (Not Found)
```

(Same 404 pattern would have applied to `venues.json`, `venues/<id>.jpg`, `karaoke/stage.html`, `index.html` had loading reached them; `shell/auth.js`'s failure aborted boot.)

**Root cause:** The original `admin-venues.html` (`9cf4b70`) used absolute paths with leading slashes — `import '/shell/auth.js'`, `fetch('/venues.json')`, `<a href="/index.html">`, etc. GitHub Pages serves the repo from the `/elsewhere/` subpath. A leading-slash absolute path resolves against the *origin*, not the repo subpath, so `/shell/auth.js` became `https://mstepanovich-web.github.io/shell/auth.js` (404, no `/elsewhere/`) instead of `https://mstepanovich-web.github.io/elsewhere/shell/auth.js` (the actual file). The rest of the repo (`tv2.html`, `index.html`, `claim.html`, `nhhu-home.html`, `karaoke/*.html`) uses **relative paths** consistently — `src="shell/auth.js"` from repo root, `src="../shell/auth.js"` from `karaoke/` subdir — and none use a `<base>` tag.

**Secondary root cause:** beyond the path issue, the original `admin-venues.html` used a different shell-module consumption pattern from the rest of the repo. It used inline ES module imports (`import { loadVenueSettings } from '...'`) where every other entry point uses side-effect `<script type="module" src="...">` tags + accesses via `window.elsewhere.venueSettings`. `shell/venue-settings.js:506-515` actually registers its helpers on `window.elsewhere.venueSettings` for exactly this consumption pattern; the ES-import path was never the convention. So even fixing the leading-slash on `/shell/venue-settings.js` to `shell/venue-settings.js` in the import statement would have left the module-load timing unaligned with the rest of the repo.

**Fix (commit `606674f`):** Six absolute paths lost their leading slash, and the shell-module consumption pattern was switched to match the rest of the repo:

1. `<head>` gained two relative-path `<script type="module" src="shell/...">` tags (mirroring `tv2.html` line 9 and similar in `index.html` + `karaoke/stage.html`).
2. The inline `<script type="module">` block became plain `<script>`; the ES `import` statements were deleted in favor of a doc comment naming the globals consumed.
3. A new `waitForVenueSettings()` helper was added — verbatim port from `karaoke/stage.html:2570-2585` (the proven 50ms-poll-with-5s-timeout pattern). `loadVenues()` rewrote to consume `vs.loadVenueSettings('karaoke')` via the wait, not as an imported function.
4. Six leading slashes dropped: `/shell/auth.js` (now via script tag), `/shell/venue-settings.js` (same), `/venues.json` (fetch), `/venues/<id>.jpg` (skybox img.src), `/karaoke/stage.html?venue=<id>` (preview link href), `/index.html` (sign-in gate link).

Diff: +37 / −8 LOC. No behavior change beyond fixing the 404s; the RPC call shape and all UI logic are unchanged. After 606674f was pushed and GitHub Pages caught up, Check 1 re-ran and PASSED.

**Why this was missed pre-deploy:** the spec §5.1 says *"Loads `shell/auth.js` + `shell/venue-settings.js` as ES modules (matches `tv2.html` / `claim.html` pattern). Inline JS for the rest."* That sentence does NOT specify the convention is "side-effect script tag + global registration" rather than "inline ES module import"; the implementation pass made a reasonable but incorrect inference. Future entry-point specs should call out the exact pattern as load-bearing rather than just "matches X.html." Recording as a process note, not a build issue.

### Bug 2 — db/034 anon-grant gap (Supabase default privileges)

**Symptom:** During the post-COMMIT verification of db/034 in the SQL Editor, query 3 returned `anon_authed = true` — but the migration's stated intent (per its file header and spec §6.5) was that anon should NOT have EXECUTE. Function intent ≠ actual grant surface.

**Root cause discovered via diagnostic:** The grant list on `rpc_venue_default_update` came back as `service_role EXECUTE, authenticated EXECUTE, anon EXECUTE, postgres EXECUTE` with NO row for `PUBLIC`. Two facts emerged:

1. PostgreSQL's `CREATE FUNCTION` default-grants EXECUTE to `PUBLIC`. In a fresh PostgreSQL this would have been the source of anon's access (anon inherits PUBLIC). But in Supabase, the PUBLIC default is revoked at project setup — the diagnostic confirmed no PUBLIC row in the grant list. So the original `revoke execute … from public` statement in db/034 ran as a no-op in this environment.

2. Supabase configures `ALTER DEFAULT PRIVILEGES` on the `public` schema to auto-grant EXECUTE on every new function DIRECTLY to `anon`, `authenticated`, and `service_role`. These are direct role grants, NOT inherited from `PUBLIC`, so `REVOKE EXECUTE … FROM PUBLIC` does not affect them. The direct grant to anon was the load-bearing source of `anon_authed = true`.

**Fix (applied to prod 2026-05-26, file amended before commit):** Added `REVOKE EXECUTE ON FUNCTION public.rpc_venue_default_update(text, jsonb) FROM anon;` to the migration. The `REVOKE FROM PUBLIC` statement was kept as defensive belt (it's a no-op in Supabase but correct for any future non-Supabase replay). After the REVOKE FROM anon was applied:
- Query 3 returned `anon_authed = false` ✓
- Query 2 still returned `authed = true` ✓ (the direct grant to authenticated is independent of the anon revoke)

**No data exposure window:** The function's first executable check is `if v_user_id is null then raise exception 'not authenticated' using errcode = '42501'`. Anon callers would have been blocked at runtime by this gate regardless of whether the grant-level revoke was in place. The Bug 2 fix is **defense-in-depth** — making the grant surface match the function's runtime behavior — not a remediation of an actual exposure.

**Why this was missed pre-deploy:** The build spec's §6.5 *("anon does NOT get execute — admin actions require sign-in")* and §8.1 Check 5's expectation (`anon_authed = false`) implicitly assumed PostgreSQL's PUBLIC-default mechanism. The spec author (me, during the propose-pause cycle) didn't know about Supabase's `ALTER DEFAULT PRIVILEGES` direct-grant configuration; the build spec's REVOKE FROM PUBLIC was correct in PostgreSQL-vanilla terms but insufficient in Supabase. The same class of issue — Supabase-specific platform behavior that diverges from PostgreSQL-vanilla expectations and isn't visible from the schema surface — has been documented in CLAUDE.md before: the `--no-verify-jwt` requirement on Edge Function deploys (CLAUDE.md line 167; described there as a "real footgun"). The mechanisms differ but the lesson is the same: Supabase's platform configuration sometimes diverges from PostgreSQL-vanilla expectations, and the divergence isn't visible until apply time.

The full diagnostic walk is captured in `db/MIGRATIONS_APPLIED.md` row 41's Notes column (the "Grant surface — two REVOKEs + one GRANT" paragraph).

---

## Broader flag for a future DEFERRED entry

The Supabase `ALTER DEFAULT PRIVILEGES` mechanism that caused Bug 2 affects **every prior SECURITY DEFINER RPC in the repo's migration history**, not just db/034. Specifically, every `CREATE FUNCTION public.rpc_*` from db/006 onward (rpc_claim_tv_device, rpc_session_*, rpc_room_*, rpc_karaoke_*, etc.) issues `GRANT EXECUTE … TO authenticated` (which is additive — Supabase already granted authenticated by default) but does NOT issue `REVOKE EXECUTE … FROM anon`. So every one of those RPCs currently has `anon` with grant-level EXECUTE.

**Actual exposure: none identified.** Every existing RPC body has an `auth.uid() is null → raise 42501` check as its first executable statement (verified by inspection during the C2 surface-side investigation and the §F shell-rework on 2026-05-22+). Anon callers are blocked at runtime across the entire RPC surface.

**Defense-in-depth gap: real.** The grant-level surface across the existing RPC catalog does not match the per-function intent. A `\dp public.rpc_*` audit by a security reviewer would show anon-with-EXECUTE on dozens of functions, which contradicts the apparent admin/authenticated-only design intent.

**Recommended future work (DEFERRED entry):**
> Sweep migration that issues `REVOKE EXECUTE ON FUNCTION public.<name>(args) FROM anon` for every SECURITY DEFINER RPC in db/006+. No behavior change (the runtime gates stay in place); aligns grant surface with intent. Low priority; defense-in-depth only. Pairs with db/034's REVOKE FROM anon pattern as the template.

This entry is not filed in this log — it'll be added to `docs/DEFERRED.md` as part of a separate doc-pass that bundles other pending DEFERRED entries (the cleanup row inventory from prior verifications, the singer.html:1010 orphan-getElementById bug, etc.).

---

## Test artifacts — row inventory

### Edited rows during this verification

Only `venue_defaults` was touched (no anchor rows authored — Stage 1 doesn't have anchor authoring; that's Stage 2). One venue was touched during the test sequence:

- **`stadium`:** (the only venue touched during the verification)
  - Pre-test value: `back_yaw = -247` (the prior admin-tuned value via the existing "Set View Coordinates" dialog in `karaoke/stage.html`).
  - **Check 3 edit:** `back_yaw` set to `-248`, saved via the admin UI through `rpc_venue_default_update`.
  - **Check 6 SQL read here:** returned `back_yaw = -248`, `updated_by = 8984755f` (Mike's UID), `updated_at` ≈ time of Check 3's save.
  - **Reverted to `-247`:** saved revert via the UI to restore the pre-test state before Check 4's exercise.
  - **Check 4 edit:** `back_yaw` set to `-250` in the input (dirty, not yet saved). `beforeunload` fired on tab-close attempt; Cancel was clicked to keep the tab open; then the in-UI "Discard changes" button was used to drop the dirty buffer. **`-250` was never written to the database** — it lived only in the in-memory dirty state.
  - **Final state — `back_yaw = -247`** (the saved revert; `-250` was only ever in the dirty buffer and was discarded).

### Other tables

- **`venue_anchors`:** untouched. Stage 1 has no anchor authoring. Stage 2 will populate 19 rows.
- **`karaoke_venue_settings`:** untouched. Stage 1 has no per-app override editing (D2 / D3 — that arrives in Stage 7).
- **`venue_suggested_costumes`:** untouched. Stage 8 territory.

### Cleanup pending

None new from this verification — the stadium row is back at its pre-test value `-247`. The accumulated row-inventory cleanup from prior verifications (Tier 1 §8, Items 5/6, 595e004) is still pending and unaffected by this run.

---

## Conclusion

**Stage A1 verified.** All six §8.1 checks pass against prod 2026-05-26:

- Admin-only access enforced (Check 1)
- Read-only identity display correct (Check 2)
- Edit + save flow works end-to-end through `rpc_venue_default_update` (Check 3)
- Dirty-state navigation warning fires (Check 4)
- RPC authority gate rejects non-admin direct calls (Check 5)
- Per-venue verification SQL confirms persistence + audit columns (Check 6)

Two bugs were caught during verification and fixed before PASS was declared:
- **Bug 1** (GitHub Pages subpath path bug) — `admin-venues.html` shipped with absolute `/shell/...` paths that 404'd under the `/elsewhere/` deploy subpath; fixed in commit `606674f` (relative paths + the shell-globals script-tag pattern that matches `tv2.html` / `karaoke/stage.html`).
- **Bug 2** (db/034 anon-grant gap) — `REVOKE FROM PUBLIC` was insufficient against Supabase's `ALTER DEFAULT PRIVILEGES` direct grant to anon; fixed in the migration with `REVOKE EXECUTE … FROM anon` before commit. No data-exposure window (function body's 42501 gate blocked anon at runtime regardless).

**Broader defense-in-depth flag** for a future sweep migration that REVOKES EXECUTE FROM anon across every prior SECURITY DEFINER RPC. No actual exposure; alignment work only.

Stage A1's deliverable surface is live and verified: `admin-venues.html` is the working write path for `venue_defaults` edits via the `rpc_venue_default_update` RPC. **Stage 2** (audio renderer impl + audio anchor authoring + 19 audio-only venue translations + `db/035` anchor RPCs) is the next deliverable on this thread per `docs/VENUE-ADMIN-UI-A1-BUILD-SPEC.md` §7's hybrid sequencing, and ships as its own propose-pause cycle.

---

## End of log
