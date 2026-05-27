# Venue Admin UI Stage A2 (Stage 2) — Verification Result Log

**Commits verified:** `9d58a8d` (Stage A2 implementation — db/035 + audio.js + admin-venues.html + stage.html + MIGRATIONS_APPLIED.md row) + `647c31b` (predecessor doc commit — §8.2 Check 8 spec correction)
**Migration applied to prod:** `db/035_audio_anchor_rpcs_and_seed.sql` on 2026-05-26 via Supabase SQL Editor (recorded in `db/MIGRATIONS_APPLIED.md` row 41). All 8 migration-footer verification queries (Q1–Q8) PASSED first try, including the anon-revoke checks (Q3, Q6) — see "No bugs this stage" below.
**Run date:** 2026-05-26
**Environment:** prod GitHub Pages (https://mstepanovich-web.github.io/elsewhere/) + prod Supabase
**Verifier:** Mike Stepanovich, signed-in as platform admin (UID `8984755f-9534-437a-a2a7-2aeba06c7e9d`)
**Outcome:** **PASS** — all five §8.2 checks pass against prod. **No bugs caught this stage** (unlike A1's two — see "No bugs this stage" below). Stage A2 ships in one propose-apply cycle.

This log records the post-deploy verification of Stage A2 against the build spec `docs/VENUE-ADMIN-UI-A1-BUILD-SPEC.md` §8.2 (revised by `8187c5d` for the programmatic-seed approach + `647c31b` for the Check 8 expression). Stage 2 is the first vertical slice through the architecture (UI → DB → registry → renderer → karaoke preview); the audio anchor renderer is the simplest type and the easiest to validate end-to-end.

Per D8, Stage A2 ships AMBIENT_PROFILES-first — the 19 seeded anchors are dormant data; karaoke/stage.html continues reading from AMBIENT_PROFILES until Stage 6 (the AMBIENT_PROFILES retirement) promotes anchors to load-bearing.

---

## Outcome — all five §8.2 checks PASS

### Check 8 — Audio renderer registered

Loaded `karaoke/stage.html` in a fresh browser tab. DevTools console:

```js
window.elsewhere.anchorRegistry.getAnchorRenderer('audio')
```

Returned the `audioAnchorRenderer` function (not null). The audio renderer module is correctly loaded by the new `<script type="module" src="../shell/venue-renderers/audio.js"></script>` tag in stage.html, and the module's self-registration block (`registerAnchorRenderer('audio', audioAnchorRenderer)` at the bottom of audio.js) executed on module load. PASS.

(Per the §8.2 Check 8 spec correction in `647c31b`, this check uses the actual registry path on `window.elsewhere.anchorRegistry`. The original spec's `window.getAnchorRenderer` reference would have short-circuited to false against the real registry exposure.)

### Check 9 — Seed verification + admin panel round-trip

**Step 1 (seed verification)** — folded with db/035's own migration-footer verification queries (Q7, Q8). Both passed:

- Q7: `count(*)` of audio anchors = **19** ✓
- Q8: 19 rows, ordered by venue_id; for 18 venues `sound_id = venue_id`; for **kids-dino2** specifically `sound_id = 'kids-dino'` (the shared-sound exception); for **enchantedforest** specifically `sound_id = 'enchantedforest'` (per OQ-S1, NOT `'forest'`); `label = 'Ambient'` for all 19.

These results were captured during the db/035 prod-apply step on 2026-05-26 (db/MIGRATIONS_APPLIED.md row 41); not re-run during this UI verification.

**Step 1(c) idempotency** — not re-verified during this UI session (the post-apply verification already exercises this implicitly: re-running db/035 would have been blocked by `DROP FUNCTION IF EXISTS` + the seed's `ON CONFLICT (id) DO NOTHING`, and no rows would change). The idempotency design is structural, not behavioral. Confirmed by code inspection alone.

**Step 2 (path equivalence on 3 venues)** — picked at random: hollywoodbowl (big), supperclub (bars), kids-northpole (kids).

- For each: in admin-venues.html, selected the venue; the seeded audio anchor appeared in the panel with the expected `sound_id` (matching venue_id, except kids-dino2 which was not in this random sample). Clicked Play preview — the expected mp3 played from `/sounds/<sound_id>.mp3`. Opened `karaoke/stage.html?venue=<id>` in a new tab; the same mp3 played through AMBIENT_PROFILES. The two paths were sonically equivalent (same file, same loop, no audible difference).
- For **kids-dino2** specifically (verified separately): the seeded anchor's `sound_id = 'kids-dino'` (the shared-sound exception); admin panel Play preview played kids-dino.mp3 through the renderer; `karaoke/stage.html?venue=kids-dino2` played the same kids-dino.mp3 through AMBIENT_PROFILES's hardcoded `playAmbientMp3('kids-dino')` dispatcher at karaoke/stage.html:4990. Both paths reach the same file via different lookups — confirmed equivalent.

**Step 3 (admin panel round-trip on hollywoodbowl)** — the load-bearing test of the admin panel's create / save / delete / preview lifecycle without bulk authoring:

- Selected `hollywoodbowl`; the seeded `anc_aud_hollywoodbowl` anchor appeared with `sound_id = hollywoodbowl`.
- Clicked **Delete** on the anchor — native confirm dialog appeared ("Delete audio anchor 'hollywoodbowl' for hollywoodbowl?"), clicked OK. The row disappeared from the panel. The empty-state ("No audio anchors yet for this venue…") rendered. The "+ Add audio anchor" button reappeared (had been hidden by the multi-anchor PREVENT rule when count ≥ 1).
- Verified via SQL post-delete:
  ```sql
  select count(*) from public.venue_anchors
   where venue_id = 'hollywoodbowl' and type = 'audio';
  -- Returned: 0.
  ```
- Clicked **+ Add audio anchor** — a new pending row appeared with a client-generated `anc_<uuid>` id (specifically a UUID from `crypto.randomUUID()`, distinct from the seed's `anc_aud_hollywoodbowl` pattern). Set `sound_id = "hollywoodbowl"` in the input; the Save button enabled (dirty + sound_id non-empty). Clicked Save. The new row persisted; the dirty indicator cleared; the "Saved" status briefly displayed.
- Verified via SQL post-recreate:
  ```sql
  select id, payload->>'sound_id' as sound_id
  from public.venue_anchors
  where venue_id = 'hollywoodbowl' and type = 'audio';
  -- Returned: 1 row, id = anc_<uuid> (panel-generated, NOT anc_aud_hollywoodbowl),
  --          sound_id = 'hollywoodbowl'.
  ```
- Clicked **Play preview** on the new anchor — hollywoodbowl.mp3 played correctly through the renderer.
- "+ Add audio anchor" button hidden again (count returned to 1; the multi-anchor PREVENT rule re-engaged).

**Post-round-trip restore (one-row UPDATE).** The Check 9 Step 3 round-trip left hollywoodbowl's audio anchor in a state that diverged from the seed in two ways: the id was `anc_<uuid>` (panel-generated, not `anc_aud_hollywoodbowl`) and the label was empty (the panel doesn't default to 'Ambient' on add; the seed had set it to 'Ambient'). Both divergences would have created a real prod hazard: if db/035 were ever re-run, its `ON CONFLICT (id) DO NOTHING` would NOT catch the panel-generated id (different from the seed's id), and a second `anc_aud_hollywoodbowl` row would be inserted — violating the one-audio-anchor-per-venue invariant the multi-anchor PREVENT rule enforces UI-side.

The divergence was restored to seed state via a single UPDATE before this log was committed:

```sql
update public.venue_anchors
   set id    = 'anc_aud_hollywoodbowl',
       label = 'Ambient'
 where venue_id = 'hollywoodbowl'
   and type     = 'audio';
```

The id column is the PK; zero incoming FK references exist anywhere in `db/*.sql` (verified via `awk` across all migrations), so the UPDATE is safe — no cascade concerns, no FK violations. The existing `venue_anchors_set_updated_at` BEFORE-UPDATE trigger fires expectedly and bumps `updated_at`.

Post-UPDATE state confirmed:

```sql
select id, venue_id, type, label, payload->>'sound_id' as sound_id
  from public.venue_anchors
 where venue_id = 'hollywoodbowl' and type = 'audio';
-- Returned: 1 row.
-- id = 'anc_aud_hollywoodbowl', label = 'Ambient',
-- sound_id = 'hollywoodbowl' (preserved through the UPDATE).
```

The hollywoodbowl venue's audio anchor now matches the seed's intended state exactly. db/035 remains idempotent — re-running it would hit `ON CONFLICT (id) DO NOTHING` against the restored `anc_aud_hollywoodbowl` row and skip cleanly.

**Multi-anchor PREVENT verified** — the "+ Add audio anchor" button was hidden whenever the venue had count ≥ 1 audio anchors, with the inline note ("This venue already has an audio anchor. Edit or delete the existing anchor to change the sound.") appearing in its place. After deleting hollywoodbowl's anchor (count → 0), the button reappeared; after re-creating it (count → 1), it hid again. Constraint working as designed per Item 3 of the implementation pass.

PASS.

### Check 10 — RPC authority gates

**Test methodology note:** the first attempt was made from a **signed-OUT** browser, which returned HTTP **401 Unauthorized** at the Supabase REST layer. This is NOT the gate the check is meant to verify — 401 = unauthenticated rejection (Supabase rejects before the RPC even runs because no JWT is present). The VALID test for the `is_platform_admin` gate requires a **signed-IN non-admin** browser, which exercises the RPC's body and reaches the `if coalesce(v_is_admin, false) = false then raise exception 'not a platform admin' using errcode = '42501'` check. That raise becomes an HTTP **403 Forbidden** at the REST layer.

After switching to a signed-in non-admin browser, both RPCs were tested:

```js
// rpc_venue_anchor_upsert
await window.sb.rpc('rpc_venue_anchor_upsert', {
  p_id: 'test_anchor_id', p_venue_id: 'stadium',
  p_partial: { type: 'audio', payload: { sound_id: 'test' } }
});
// → HTTP 403 Forbidden; error.code = '42501'; error.message = 'not a platform admin'.

// rpc_venue_anchor_delete
await window.sb.rpc('rpc_venue_anchor_delete', { p_id: 'anc_aud_hollywoodbowl' });
// → HTTP 403 Forbidden; error.code = '42501'; error.message = 'not a platform admin'.
```

Both gates correctly rejected the non-admin caller. The same calls from the admin browser succeeded (verified via the Check 9 round-trip — the recreate would have failed otherwise). PASS.

**Recording the 401-vs-403 distinction:** future runners of this check should sign in as a non-admin user FIRST before invoking the RPCs from DevTools. A 401 response means you forgot to sign in (the check didn't actually exercise the admin gate); a 403 with `code: '42501'` means the admin gate is working. The spec's §8.2 Check 10 phrasing ("Non-admin calls rpc_venue_anchor_upsert → 42501") refers to the SQL error code, which surfaces as HTTP 403 at the Supabase REST layer.

### Check 11 — D8 dormancy invariant (anchor delete unaffects karaoke)

During Check 9 Step 3, after deleting hollywoodbowl's anchor (between the delete and the recreate), opened `karaoke/stage.html?venue=hollywoodbowl` in a new tab. hollywoodbowl.mp3 played correctly through AMBIENT_PROFILES. Karaoke playback was UNAFFECTED by the anchor's absence — D8's dormancy invariant intact. The deleted anchor was dormant data; deleting it didn't change the karaoke playback path because AMBIENT_PROFILES is still load-bearing.

Confirmed no new console errors in karaoke/stage.html attributable to the audio.js script tag (the registration happens at module load; no run-time errors from the side-effect import).

PASS.

### Check 12 — karaoke/stage.html read path unchanged

`git diff 8187c5d 9d58a8d -- karaoke/stage.html` shows exactly **one** line added: the `<script type="module" src="../shell/venue-renderers/audio.js"></script>` tag at line 16 (alongside the existing three module-load tags). Zero changes to `AMBIENT_PROFILES`, zero changes to `addVenueEffects3D`, zero changes to the `getProfile` dispatcher or any of the procedural anim() functions — the reader path is byte-for-byte unchanged. The script tag addition is REGISTRATION, not a reader-path change, and is explicitly permitted per spec §8.2 Check 12.

PASS.

---

## No bugs caught this stage

Recording plainly: **zero bugs caught during Stage A2 verification**. Stage A2 ships in one propose-apply cycle. Contrast with Stage A1 (verified 2026-05-26 in `docs/SESSION-LOGS/VENUE-ADMIN-UI-A1-STAGE-1-VERIFICATION-LOG.md`), which caught and fixed two bugs during verification:

1. **A1 Bug 1** (GitHub Pages subpath path bug — admin-venues.html shipped with absolute `/shell/...` paths that 404'd; fixed in `606674f`) — N/A for Stage A2 because admin-venues.html's path discipline was already correct from `606674f`; the new audio.js + the four panel inserts all use relative paths consistent with the rest of the file. The Stage A2 implementation pass deliberately checked path discipline against the A1 fix doctrine before writing.

2. **A1 Bug 2** (db/034 anon-grant gap — initial verification Q3 returned `anon_authed=true` because Supabase's `ALTER DEFAULT PRIVILEGES` direct-grants EXECUTE to anon, REVOKE FROM PUBLIC alone was a no-op, fixed by adding REVOKE FROM anon) — **N/A for Stage A2 because the REVOKE FROM anon was BAKED INTO db/035 from the start**, per the A1 verification log's Bug 2 doctrine. db/035's Q3 (`anon_authed=false` for rpc_venue_anchor_upsert) and Q6 (same for rpc_venue_anchor_delete) BOTH PASSED FIRST TRY against prod 2026-05-26 — no post-apply detour. The doctrine that surfaced in A1's verification was applied prophylactically in A2's build.

The Stage A2 propose-pause-apply rhythm benefited directly from A1's findings. Specifically: A2's `db/035` migration scaffolding includes both `REVOKE EXECUTE ... FROM public` (defensive) and `REVOKE EXECUTE ... FROM anon` (load-bearing in Supabase) per RPC, with explanatory comments in the migration header tying it to A1's discovery.

The broader defense-in-depth flag from the A1 log (the same anon-grant gap affects every prior SECURITY DEFINER RPC in db/006+) remains an active item for a future DEFERRED-entry-style sweep migration; not addressed in this Stage 2 work, but the A2 build does not contribute to it (the two new RPCs in db/035 already have REVOKE FROM anon applied, so they don't add to the gap).

---

## Test artifacts — row inventory

### Edited rows during this verification

Only `venue_anchors` was touched (no venue_defaults edits this stage; Stage A2 doesn't modify venue_defaults). One anchor was exercised in the Check 9 round-trip and subsequently restored:

- **`hollywoodbowl` audio anchor:**
  - **Pre-test state:** one row with `id = 'anc_aud_hollywoodbowl'` (the seeded id from db/035), `venue_id = 'hollywoodbowl'`, `type = 'audio'`, `payload = {"type":"mp3","sound_id":"hollywoodbowl"}`, `label = 'Ambient'`, all other fields nullable defaults.
  - **Check 9 Step 3 delete:** the seeded row was deleted via the admin panel through `rpc_venue_anchor_delete('anc_aud_hollywoodbowl')`. Confirmed via SQL: count = 0.
  - **Check 9 Step 3 recreate:** a new row was created through the admin panel's "+ Add audio anchor" button. The panel generated a client-side UUID (via `crypto.randomUUID()`), prefixed with `anc_` per the spec, yielding an id of the form `anc_<uuid>` — distinct from the seed's `anc_aud_hollywoodbowl` pattern. The new row had `sound_id = 'hollywoodbowl'` (matching the seeded sound) and `label = ''` (the panel doesn't default the label).
  - **Post-round-trip restore:** the id/label divergence was restored to seed state via a one-row UPDATE before this log was committed (the SQL is quoted in Check 9 Step 3 above, with FK-safety analysis). The hollywoodbowl venue's audio anchor now matches the seed exactly: `id = 'anc_aud_hollywoodbowl'`, `label = 'Ambient'`, `sound_id = 'hollywoodbowl'`. db/035 remains idempotent.

  **Final state — restored.** The venue has one audio anchor (count = 1, the invariant); the row matches the seed in every column except `updated_at`/`updated_by` (which now reflect the test sequence's most recent operation — expected and harmless).

### Other tables

- **`venue_defaults`:** untouched. Stage A2 doesn't edit venue_defaults (Stage A1 ships that path; subsequent stages may extend it).
- **`karaoke_venue_settings`:** untouched. Stage 7 territory (per-app override editor).
- **`venue_suggested_costumes`:** untouched. Stage 8 territory.

### Other anchors

- **The other 18 seeded audio anchors** (all venues except hollywoodbowl) were untouched during this verification. Their `id` columns retain the seed's deterministic `anc_aud_<venue_id>` form. Stages 3+ may add anchors of other types (particle, spotlight) without disturbing them.

### Cleanup completed in this verification cycle

The Check 9 round-trip's id/label divergence on hollywoodbowl was restored via the one-row UPDATE described above; db/035 remains idempotent; **nothing pending**. No further row cleanup is required from this verification.

---

## Conclusion

**Stage A2 verified.** All five §8.2 checks pass against prod 2026-05-26:

- Audio renderer registered in the anchor registry (Check 8 — corrected expression per `647c31b`)
- 19 audio anchors seeded; per-venue sound_id correctness confirmed; admin panel round-trip validates create/edit/delete/preview lifecycle; multi-anchor PREVENT working (Check 9)
- RPC authority gates reject non-admin callers with HTTP 403 / SQL 42501 (Check 10, with the 401-vs-403 test-method note recorded for future runners)
- D8 dormancy invariant intact — karaoke playback unaffected by anchor delete (Check 11)
- karaoke/stage.html read path byte-for-byte unchanged except for the one permitted registration line (Check 12)

**No bugs caught this stage.** db/035's anon-revoke baked in from the start (per the A1 Bug 2 doctrine) meant Q3/Q6 PASSED first try — no post-apply detour like A1 had. The Stage A2 propose-pause-apply rhythm benefited directly from A1's findings being folded into the build proposal.

The Check 9 round-trip's id/label divergence on hollywoodbowl was restored to seed state via a one-row UPDATE before this log committed — db/035 remains idempotent and the venue's audio anchor matches the seed exactly.

**Stage A2's deliverable surface is live and verified:**
- `shell/venue-renderers/audio.js` is loaded by both karaoke/stage.html and admin-venues.html; the audio renderer is registered in `window.elsewhere.anchorRegistry` per spec.
- `admin-venues.html` exposes the audio anchor panel below the venue_defaults editor; create/edit/delete/preview lifecycle works end-to-end through the new RPCs.
- 19 audio-only venues have their seeded anchors in `venue_anchors` table; dormant per D8 until Stage 6.

**Per D8, this commit does NOT change karaoke playback.** AMBIENT_PROFILES remains load-bearing for the 19 audio-only venues. Stage 6 (the AMBIENT_PROFILES retirement) will promote the registry-backed renderer path to canonical and retire AMBIENT_PROFILES + the 3 ghost keys + the duplicate dragonlair entry (per spec §3, post-Stage-5 cleanup).

**Stage 3** (particle renderer + particle authoring panel + the procedural venues' particle-effect translations) is the next deliverable on this thread per `docs/VENUE-ADMIN-UI-A1-BUILD-SPEC.md` §7's hybrid sequencing, and ships as its own propose-pause cycle. Stage 3's payload-contract design will be the broadest structural decision in the per-type slices — the particle vocabulary may need sub-discriminators (`point-cloud`, `emitter`, `directional-rain`) per the spec's hint.

---

## End of log
