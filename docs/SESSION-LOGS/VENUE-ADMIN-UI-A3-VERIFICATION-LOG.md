# Venue Admin UI Stage A3 — Verification Result Log

**Spec:** `docs/VENUE-ADMIN-UI-A3-BUILD-SPEC.md` §8 (Checks 13–18)

**Workstream:** Phase 3 / Plan B — particle anchor renderer + 3-kind authoring panel + db/036 4-anchor seed. The third Block A vertical slice per `docs/VENUE-ADMIN-UI-DIRECTION.md` §7's hybrid sequencing.

**Commits in this stage (chronological on `main`):**
- `bc8c448` — `docs: Venue Admin UI Stage A3 build spec`
- `716746b` — `docs(a3-spec): §1 amendment — alpha pulled from color, modulator array form, twinkle optional, polar dist basis pinned` (the schema amendment from the foundation pass's CLR resolutions, ahead of implementation)
- `e9c52e9` — `feat(venue-admin): Stage A3 — particle renderer + 3-kind anchor panel + db/036 + 4-anchor seed` (the implementation cluster: db/036 + particle.js + admin-venues.html + karaoke/stage.html one-line tag + MIGRATIONS_APPLIED.md row)
- `27610e4` — `fix(venue-admin): gate particle preview-ended label on kind (A3 Check 15 bug)` (mid-verification bug fix, pushed standalone so subsequent Check 15 + Check 16 ran against the corrected behavior; see "Bugs caught this stage" below)

**Prod-apply state:**
- db/036 applied via Supabase SQL Editor 2026-05-26. All three §2.3 verification queries Q1–Q3 PASS on first run.
- Seed-id restore SQL applied 2026-05-27 post Check 15. Stadium particle anchor's id restored to the deterministic seed id `anc_par_stadium` (see "Cleanup completed in this verification cycle" below).

---

## Outcome — all six §8 checks PASS

### Check 13 — Particle renderer registered

Loaded `karaoke/stage.html` (stadium). Browser console:

```
> window.elsewhere.anchorRegistry.getAnchorRenderer('particle')
< ƒ particleAnchorRenderer(anchor, ctx)
```

The renderer is registered. Function returned (not `null`).

**PASS** ✓

### Check 14 — Seed verification

Re-ran db/036's footer queries Q1–Q3 against prod 2026-05-27:

- **Q1** — `select count(*) from public.venue_anchors where type = 'particle'` returned `particle_count = 4`. ✓
- **Q2** — per-venue `id / venue_id / kind / label` ordered by `venue_id` returned exactly the 4 expected rows: `anc_par_disco / disco / point-cloud / Particles`; `anc_par_festival / festival / directional-emitter / Particles`; `anc_par_speakeasy / speakeasy / volumetric / Particles`; `anc_par_stadium / stadium / point-cloud / Particles`. ✓
- **Q3** — payload schema spot-check returned all 4 rows with correct `kind_specific_marker`: `disco → polar-projected`, `festival → top`, `speakeasy → spawn_region present`, `stadium → cartesian`. ✓

**PASS** ✓

### Check 15 — Admin panel round-trip on stadium

Loaded `admin-venues.html` as platform admin. Selected stadium in the sidebar.

**Original anchor display:** the seeded particle anchor appeared with `id=anc_par_stadium`, kind=point-cloud, label='Particles', count=400, alpha=0.7, x_range=[0,1], y_range=[0.08,0.60], twinkle_phase_speed_range=[0.008, 0.033], color={mode:"fixed", value:"rgb(255,255,255)"}, modulator={name:"crowd_brightness", target:"alpha"}, render={shape:"circle", mode:"solid"}. The form rendered the point-cloud kind section with the cartesian sub-section visible (polar sub-section hidden).

**Initial Preview (caught Bug 1 — see "Bugs caught this stage"):** clicked Play preview. The bounded canvas rendered ~400 twinkling white dots in the upper band, alpha modulated by both internal twinkle phase and the crowd_brightness preview oscillator. Effect correct visually. BUT the "Preview ended — click Replay" label appeared at ~8s despite the dots still twinkling. This was Bug 1, fixed mid-verification (commit `27610e4`); after the fix Check 15 was re-run and the label did not fire.

**Delete:** clicked Delete on the saved row. Confirm dialog: "Delete particle anchor (kind: point-cloud) for stadium?". Confirmed. Row removed; "+ Add particle anchor" button reappeared; empty-state text shown.

**Re-create:** clicked "+ Add particle anchor". Pending row appeared with the default point-cloud / cartesian payload (per `defaultParticlePayloadForKind('point-cloud')`) and a panel-generated id `anc_86cd468d-627d-49a1-b871-1e0bfdf617f4` (the `crypto.randomUUID()` path in `onAddParticleAnchor`). Edited the payload fields to match the original stadium values. Clicked Save. RPC `rpc_venue_anchor_upsert` succeeded; row transitioned from pending to saved (id preserved as the panel-generated UUID, NOT restored to the seed id — this is the expected hazard the SQL restore addresses).

**Database state post-round-trip:** one stadium particle row, id=`anc_86cd468d-627d-49a1-b871-1e0bfdf617f4`. The round-trip lifecycle (Delete → Add → Save) works end-to-end. The id divergence from the deterministic seed id reproduces the A2 hollywoodbowl idempotency hazard.

**Seed-id restore:** applied per the A2 precedent before closeout. See "Cleanup completed in this verification cycle" for the SQL + result.

**PASS** ✓ — round-trip lifecycle confirmed; idempotency-hazard handling confirmed.

### Check 16 — Per-kind preview

Previewed each of the 3 kinds across all 4 in-scope venues:

- **stadium (point-cloud, cartesian):** ~400 twinkling white dots in the upper band (y ∈ [0.08, 0.60]). Per-particle phase animation visible — each dot independently fading in and out at its drawn twinkle_phase_speed. Overall brightness modulated by the `crowd_brightness` preview oscillator (gentle swells matching the 10s sine period). No "Preview ended" label (kind-gate fix `27610e4` is live). ✓

- **disco (point-cloud, polar-projected):** 120 colored dots arranged on an ellipse (polar projection with vertical_squash=0.4 — visibly wider horizontally than vertically). Rotating around canvas-center at 0.012 rad/frame. Per-particle hue from the [0, 360] range. Beat-pulse modulator visibly affecting BOTH size (sharp bumps every 500ms via `beat_scale` → size) AND alpha (corresponding brightness pulses via `beat_brightness` → alpha). The polar projection renders correctly — dots that compute outside the canvas bounds clip per CLR-8. No "Preview ended" label. ✓

- **festival (directional-emitter):** ~80 colored rectangles falling from the top edge (`spawn_edge:"top"`), each rotating per its per-particle rotV. Random hues across the full 360° range. Particles fall off the bottom and die (alive: y < canvas+20). After ~5s the effect drains to empty; the "Preview ended" soft-timeout fires at 8s as designed (for `respawn:false` directional-emitter). ✓

- **speakeasy (volumetric):** ~35 amber gradient blobs spawning in the bottom 40% of the canvas, drifting upward (mild positive |vy|), growing in size (+0.2/frame via `size_growth_rate`), fading in alpha (−0.00015/frame via `fade_rate`), with small horizontal turbulence on vx (CLR-6 formula). Per-particle spawn alpha drawn from `alpha_init_range: [0.015, 0.065]`. Effect drains to empty after ~6–7s; "Preview ended" soft-timeout fires at 8s as designed (for `respawn:false` volumetric). ✓

All 3 kinds render visually correctly. The kind-discriminated form swapped per-kind sections when the kind selector changed. The polar/cartesian sub-swap toggled within point-cloud. The preview canvas behaved as a bounded surface; no overflow into surrounding admin UI. The Replay button reset the effect cleanly each click.

**Finding (filed as DEFERRED, not bug):** disco's `rotation_velocity = 0.012` rad/frame reads as visually fast against the bounded admin preview canvas. NOT a renderer correctness bug (CLR-7 polar normalization basis verified correct; renderer faithfully honors the seeded value). This is a venue-tuning question — does the byte-faithful-from-procedural-source value feel right in production? Filed as DEFERRED entry "disco `rotation_velocity` (and other seeded velocity/rate values) reads visually fast at seed value" — the question generalizes to festival vy, speakeasy size_growth_rate / fade_rate, stadium twinkle range; all 4 payloads ship byte-faithful and may benefit from in-context retuning once the admin UI gains in-situ tuning workflows (post-A8, Admin UI Part 2).

**PASS** ✓

### Check 17 — RPC authority gate

Fired `rpc_venue_anchor_upsert` from a signed-in non-admin browser session with a particle payload.

Request: fresh anchor id, `p_venue_id='stadium'`, `p_partial={type:'particle', payload:<minimal valid point-cloud>, label:'Particles'}`.

Response: HTTP 403; body `{success:false, data:null, error:{code:42501, message:'not a platform admin'}}`. The is_platform_admin gate in db/035's `rpc_venue_anchor_upsert` body refused the call before any write attempted. No row created in `venue_anchors`.

Test method: signed in as a known non-admin user FIRST (not signed-out — a signed-out browser returns HTTP 401 from Supabase's auth gateway, which is a different gate than the in-RPC 42501 check under test). 401-vs-403 distinction matches the A2 Check 10 test-method note.

**PASS** ✓ — DB gate intact for particle anchors (same gate as audio anchors; same db/035 RPC body, just exercised with `type='particle'` in p_partial).

### Check 18 — D8 dormancy + karaoke read-path unchanged

Loaded `karaoke/stage.html` on stadium (the most-particle-heavy in-scope venue). The procedural `AMBIENT_PROFILES.stadium.anim()` ran as expected: 400 phone-light dots twinkling in the crowd area + 4 GSAP-swept spotlight beams + the GSAP `crowdState.brightness` cheer-swell loop. Stadium's 3D path (`buildStadiumEffects3D`) also ran: 2000 Three.js `Points` for phone lights + 4 cone meshes for spotlights.

Browser console: no errors related to `particle`, `anchor`, `renderer`, or `venue-registry`. The new `<script type="module" src="../shell/venue-renderers/particle.js">` tag at line 17 loaded and registered its renderer without issue.

`git diff bc8c448 27610e4 -- karaoke/stage.html` shows exactly one line changed — the new `<script>` tag. No reader-path change. D8 invariant intact.

**PASS** ✓

---

## Bugs caught this stage

**Bug 1 — `onPlayParticlePreview` armed the preview-ended timer on point-cloud (eternal kind)**

Hit during Check 15 — stadium's point-cloud preview rendered correctly (twinkling dots in the upper band, y_range respected) BUT the "Preview ended — click Replay" label appeared after 8 seconds despite the effect being eternal by kind definition (point-cloud particles never die; the dots were still on the canvas).

Cause: the 8s ended-timer guard in `onPlayParticlePreview` was `if (payload.respawn !== true)`. point-cloud has no `respawn` field, so `undefined !== true` evaluates true, arming the timer wrongly. The "Preview ended" affordance is only meaningful for kinds that produce one-shot effects which drain to empty (directional-emitter / volumetric with `respawn !== true`). point-cloud is eternal by §1.1 kind definition and must never arm.

Fix: gated the timer on kind first, respawn second. Arms only when `payload.kind === 'directional-emitter' || payload.kind === 'volumetric'` AND `payload.respawn !== true`. A 5-line comment block was added at the timer-arm site naming §1.1 + the rationale, so a future "simplify the guard" cleanup doesn't regress it.

Shipped as commit `27610e4` mid-verification (pushed standalone, not folded into the closeout) so the rest of Check 15 + Check 16 could run against the corrected behavior. No A2 precedent for mid-verification bug fixes — this was the first time in the venue-admin workstream that a verification finding produced a fix needing to be live for subsequent checks. The closeout commit (this one) bundles only docs; the code fix is honestly recorded as a mid-verification finding in this log.

**No other bugs caught this stage.**

---

## Test artifacts — row inventory

### Edited rows during this verification

One row touched in `public.venue_anchors`:
- **Stadium particle anchor** — deleted in Check 15's panel test (id=`anc_par_stadium`), re-created via "+ Add" → form edit → Save with panel-generated id `anc_86cd468d-627d-49a1-b871-1e0bfdf617f4`. Then restored to the seed id `anc_par_stadium` via the seed-id restore SQL (see Cleanup).

### Other tables

No edits to other tables. Specifically:
- `venue_defaults` — unchanged (the Stage A1 surface is untouched in A3).
- `karaoke_venue_settings` — unchanged (anchor_patch is a Stage A7 concern).
- `costumes`, `venue_suggested_costumes` — unchanged (Stage A8 scope).

### Other anchors

No edits to audio anchors. db/035's 19 audio anchor rows intact and unaffected.

The 3 non-stadium particle anchors (disco, speakeasy, festival) were previewed in Check 16 but not edited or saved; their database rows are unchanged from db/036's seed.

### Cleanup completed in this verification cycle

**Seed-id restore SQL** applied to prod 2026-05-27 via Supabase SQL Editor. Per the A2 hollywoodbowl precedent — Check 15's round-trip left the stadium particle row with the panel-generated id `anc_86cd468d-627d-49a1-b871-1e0bfdf617f4` rather than the seed id `anc_par_stadium`. Re-applying db/036 in that state would INSERT a second row (ON CONFLICT (id) DO NOTHING wouldn't match the differently-named row), violating one-particle-anchor-per-venue.

One-row UPDATE applied:

```sql
update public.venue_anchors
   set id = 'anc_par_stadium'
 where venue_id = 'stadium'
   and type     = 'particle'
   and id       = 'anc_86cd468d-627d-49a1-b871-1e0bfdf617f4'
returning id, venue_id, type, label;
```

`RETURNING` result: exactly one row — `anc_par_stadium | stadium | particle | Particles`. UPDATE matched the intended row only.

Post-UPDATE verification SELECT:

```sql
select id, venue_id, label, payload->>'kind' as kind, payload->'count' as count
  from public.venue_anchors
 where venue_id = 'stadium'
   and type     = 'particle';
```

Result: exactly one row — `anc_par_stadium | stadium | Particles | point-cloud | 400`. All 5 predicates (one row exists; id is seed id; label is 'Particles'; kind is 'point-cloud'; count is 400) PASS. db/036 idempotency restored.

Label restoration not needed — the re-created anchor saved with `label='Particles'` (the panel's default, via `defaultParticlePayloadForKind` + `makeParticleAnchorRow`'s pending-anchor construction), matching the seed value byte-for-byte. The UPDATE touched `id` only.

FK-safety pre-verified: `venue_anchors.id` has no incoming FK references in the current schema (per db/032 — the planned per-app `anchor_patch` is a Stage A7 concern, not yet built). Updating the primary key was safe.

---

## Conclusion

Stage A3 ships clean. All six §8 verification checks PASS. One bug caught + fixed mid-verification (commit `27610e4`); one schema-state divergence (the Check 15 idempotency hazard) restored via one-row SQL UPDATE before closeout.

A3 delivered:
- `shell/venue-renderers/particle.js` — self-contained 2D-canvas particle anchor renderer with 3-kind discriminated dispatch (point-cloud / directional-emitter / volumetric), all four deferred renderer-contract items implemented (CLR-5 alpha formula, CLR-6 turbulence math, CLR-7 polar normalization basis, CLR-8 polar canvas-clip), built-in preview oscillators for the modulator names A3 binds (`crowd_brightness`, `beat_scale`, `beat_brightness`).
- `admin-venues.html` — kind-discriminated particle authoring panel with bounded preview surface, anchor-level dirty tracking, PREVENT multi-anchor rule mirroring A2, first v2.NN version stamp (`v2.138`).
- `db/036_particle_anchor_seed.sql` — 4-row particle anchor seed (stadium / disco / speakeasy / festival; honkytonk excluded per the deleted-particles comment at `karaoke/stage.html:4832`).
- `karaoke/stage.html` — one-line `<script>` tag at line 17 registering the particle renderer (D8-permitted per the A2 Check 12 precedent).

The §1 spec amendment landed pre-implementation at `716746b` (alpha pulled out of color strings, modulator array form, twinkle_phase_speed_range optional, polar dist normalized against max(canvas.width, canvas.height)) — all 4 payloads incorporate the amended schema cleanly.

Per spec §0.2 re-staging: **A3 is 2D-canvas only**. The 3D particle paths (stadium's 2000 Three.js Points + speakeasy's 60 sphere meshes) defer to a later stage paired with the Three.js builder work — the 3D rendering context is solved once by whoever is already in the Three.js builders.

Per spec §5 / D8: **A3 ships dormant**. The 4 seeded particle anchors are data only; karaoke's read path continues consulting `AMBIENT_PROFILES` + `addVenueEffects3D` until Stage 6 (the AMBIENT_PROFILES retirement) promotes anchors to load-bearing.

Six DEFERRED.md entries land in this closeout commit:
- Three per spec §7's planned closeout list: P1 / drifting-cloud 4th particle kind; venue modulator system; particle panel validates JSON well-formedness only, not §1 schema shape.
- The admin-venues logout-gap entry filed earlier in the verification cycle (was on disk awaiting closeout per Option B).
- Disco rotation_velocity tuning entry filed during this closeout (Check 16 visual-correctness finding generalized to other seeded velocity/rate values).
- A3 spec A5→A4 numbering-drift entry filed during this closeout (the spec's internal "Stage A5" cross-references should be "Stage A4" per Direction §7).

Next deliverable on this thread per `docs/VENUE-ADMIN-UI-DIRECTION.md` §7's "Plan B hybrid sequencing" (the authoritative A1–A8 staging — `docs/VENUE-ADMIN-UI-A1-BUILD-SPEC.md` §7 is the Stage 2 audio fold-in spec, not the staging list): **Stage A4 — spotlight renderer + spotlight authoring panel + stadium/disco/speakeasy spotlight translations, INCLUDING the translation of the 2 Three.js 3D builders for stadium and speakeasy.** The §0.2 re-staging note and the venue modulator system DEFERRED entry both point at this stage as the place where the 3D rendering context is solved once.

**Numbering note.** The A3 spec internally refers to spotlight as "Stage A5" (~6-8 references across `docs/VENUE-ADMIN-UI-A3-BUILD-SPEC.md` §§0.2, 6, 7, etc.). This is a numbering drift relative to Direction §7's authoritative staging — Direction §7 calls spotlight **Stage 4**, not 5. A3 spec corrections deferred to a future touch of that file (see DEFERRED.md entry "A3 build spec internal references to spotlight as 'Stage A5' should be 'Stage A4'"). The A3 spec's "A5 (spotlight + 3D builders)" cross-references should be read as "A4."

Stage A4 ships as its own propose-pause cycle.

---

## End of log
