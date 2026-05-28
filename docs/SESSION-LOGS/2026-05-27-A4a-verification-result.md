# Venue Admin UI Stage A4a — Verification Result Log

**Spec:** `docs/VENUE-ADMIN-UI-A4A-BUILD-SPEC.md` §8 (Checks 19–24)

**Workstream:** Phase 3 / Plan B — spotlight anchor renderer (2D-canvas only) + 3-kind authoring panel + db/037 3-anchor seed. The fourth Block A vertical slice per `docs/VENUE-ADMIN-UI-DIRECTION.md` §7's hybrid sequencing. A4a is the 2D-canvas-only sub-stage of A4 (A4 was sub-staged into A4a + A4b in planning chat 2026-05-27 because the 3D-preview surface is genuinely new architectural territory — `admin-venues.html` has zero Three.js code today; sub-staging isolates the 3D-preview-surface risk to A4b). A4b ships the 3D spotlight builders (stadium 4 cone meshes + speakeasy 40 candle Points) + absorbed 3D particle paths (stadium 2000 phone-lights + speakeasy 60 sphere-mesh smoke) + new Three.js preview surface as a separate propose-pause cycle.

**Commits in this stage (chronological on `main`):**
- `8528b82` — `docs: Venue Admin UI Stage A4a build spec`
- `d50cbc9` — `docs: Venue Admin UI Stage A4a build spec — §1 amendment from foundation pass` (gradient_stops added to all 3 kinds' geometry; color fragment dropped for hue-driven kinds; drift_speeds negative-first for pulsed-laser; first_pulse_offset_beats added; geometry.pivot consistency)
- `f167ec6` — `feat(venue-admin): Stage A4a — spotlight renderer + 3-kind anchor panel + db/037 + 3-anchor seed` (the implementation cluster: db/037 + spotlight.js + admin-venues.html + karaoke/stage.html one-line tag + MIGRATIONS_APPLIED.md row)
- `0b2dec0` — `fix(venue-admin): load spotlight.js in admin-venues.html for preview path (A4a Check 19 finding)` (mid-verification bug fix #1)
- `2056a72` — `fix(venue-admin): A4a spotlight save path — p_partial jsonb signature + .anchor-status class (A4a Check 21 findings)` (mid-verification bug fix #2 + #3, bundled — both blocked the Save path and were tightly coupled)

**Prod-apply state:**
- db/037 applied via Supabase SQL Editor 2026-05-27. All three §2.3 verification queries Q1–Q3 PASS on first run (Q3 split into 4 sub-queries due to a verification-mechanics artifact — see Check 20).
- Seed-id restore SQL applied 2026-05-27 post Check 21. Stadium spotlight anchor's id restored to the deterministic seed id `anc_spot_stadium` (see "Cleanup completed in this verification cycle" below).

---

## Outcome — all six §8 checks PASS

### Check 19 — Spotlight renderer registered

Loaded `karaoke/stage.html` (stadium). Browser console:

```
> window.elsewhere.anchorRegistry.getAnchorRenderer('spotlight')
< ƒ spotlightAnchorRenderer(anchor, ctx)

> window.elsewhere.anchorRegistry.getAnchorRenderer('particle')
< ƒ particleAnchorRenderer(anchor, ctx)

> window.elsewhere.anchorRegistry.getAnchorRenderer('audio')
< ƒ audioAnchorRenderer(anchor, ctx)
```

All three renderers register cleanly. The new `<script type="module" src="../shell/venue-renderers/spotlight.js">` tag at `karaoke/stage.html:18` loaded without error; the spotlight renderer joined the registry alongside the A2-shipped audio renderer and A3-shipped particle renderer.

**PASS** ✓

### Check 20 — Seed verification

Re-ran db/037's footer queries Q1–Q3 against prod 2026-05-27:

- **Q1** — `select count(*) from public.venue_anchors where type = 'spotlight'` returned `spotlight_count = 3`. ✓
- **Q2** — per-venue `id / venue_id / kind / label` ordered by `venue_id` returned exactly the 3 expected rows: `anc_spot_festival / festival / pulsed-laser / Spotlights`; `anc_spot_speakeasy / speakeasy / light-shaft / Spotlights`; `anc_spot_stadium / stadium / swept-beam-2d / Spotlights`. ✓
- **Q3** — payload schema spot-check via 4 sub-queries (split from the single CASE-expression form due to a verification-mechanics artifact — see note below) returned the correct kind-specific marker per row: stadium swept-beam-2d count=4 hues_len=4; festival pulsed-laser count=6 hues_len=6 bpm=128; speakeasy light-shaft count=3 x_init_norm_len=3; gradient_stops present in geometry on all 3 anchors. ✓

**Verification-mechanics note (not a payload issue).** Supabase SQL Editor auto-appends a `limit 100` clause to every query before sending it to the server. The original Q3 single-query form had a CASE expression containing a string literal `'hues_len=' || ...` — Supabase's parser injected the `limit 100` clause inside the string literal rather than appending it as a top-level clause, producing a malformed query. Resolution: split Q3 into 4 sub-queries (one per kind for the kind_marker + one for gradient_stops presence). Each sub-query is simple enough that the editor's `limit 100` appends correctly. The payload data is fully correct; the original Q3 form is functionally correct against a non-Supabase psql shell. This is a verification-tool artifact worth noting for future migrations whose Q3 uses complex CASE expressions.

**PASS** ✓

### Check 21 — Admin panel round-trip on stadium

Loaded `admin-venues.html` as platform admin. Selected stadium in the sidebar.

**Original anchor display:** the seeded spotlight anchor appeared with `id=anc_spot_stadium`, kind=swept-beam-2d, label='Spotlights', count=4, hues=[220,200,240,180], angle_init=[-0.375,-0.125,0.125,0.375], base_alpha_range=[0.08,0.14], sweep_target_range=[-0.425,0.425], sweep_alpha_range=[0.06,0.16], sweep_duration_range_ms=[1500,4000], sweep_ease='power1.inOut', stagger_ms=800, geometry={pivot:'top-center', top_width_px:12, bottom_width_norm:1.0, height_norm:1.0, sat_pct:80, lit_pct:95, gradient_stops:[{at:0,alpha_mult:1.0},{at:0.5,alpha_mult:0.4},{at:1,alpha_mult:0.0}]}. The form rendered the swept-beam-2d kind section (other kinds' sections were not present per A4a's re-render-on-kind-change pattern — divergent from A3's hide/show; see DEFERRED).

**Initial Preview (caught Bug 1 in flight to Check 19, then Bugs 2+3 in flight to Check 21):**

- **Bug 1** surfaced before Check 19 could run cleanly. Diagnostic against admin-venues.html showed it loaded `audio.js` + `particle.js` at lines 44–45 but NOT `spotlight.js` — the §9 step 4 proposal §4.7 specified the karaoke/stage.html script tag but not the admin-venues.html equivalent. A3 quietly loaded particle.js at admin-venues.html:45; A4a's proposal didn't extrapolate. Without the tag, `window.elsewhere.spotlightRenderer` was never published on the admin page, so the panel's preview path silently failed to instantiate the renderer. Fixed in `0b2dec0` — single-line addition at admin-venues.html:46. Check 19 then passed against `0b2dec0`.

- **Bug 2 + Bug 3** surfaced when the user pressed Save on a round-trip pending row during Check 21. Diagnostic against the RPC call:
  - **Bug 2:** my `onSpotlightAnchorSave` was drafted from the §9 step 4 proposal's "individual column params" framing — passing `p_id`, `p_venue_id`, `p_type`, `p_label`, `p_yaw_deg`, `p_pitch_deg`, `p_start_sec`, `p_end_sec`, `p_link`, `p_payload`, `p_is_broken` as 11 separate parameters. But db/035 defines `rpc_venue_anchor_upsert(p_id text, p_venue_id text, p_partial jsonb)` — **3 args**, with `p_partial` being a jsonb of column→value pairs. A3's call at line 1695 uses the correct shape. The proposal-vs-A3-implementation drift here: I wrote the call from the spec's English description without verifying against A3's actual call shape.
  - **Bug 3:** my `renderSpotlightAnchorRowHTML` emitted `<div class="anchor-row-status" data-status-for="${anchorId}">` for the status surface. But A3's `showAnchorStatus` (admin-venues.html:1780) does `row.querySelector('.anchor-status')` — different class. `statusEl` returned `null`, then `statusEl.textContent = msg` would throw. I invented the `anchor-row-status` / `data-status-for` patterns that don't exist anywhere in A3.

  Both fixed in `2056a72` as one commit (tightly coupled — both block the Save path; A3 Check 15 precedent at commit `27610e4` was the mid-verification fix template, single commit per bug-cluster). Check 21 re-ran against `2056a72`:

**Delete:** clicked Delete on the saved row. Confirm dialog: "Delete this spotlight anchor?". Confirmed. Row removed; "+ Add spotlight anchor" button still visible (PERMIT rule per spec §4.5 / D2 — A4a diverges from A2/A3 PREVENT); empty-state text shown.

**Re-create:** clicked "+ Add spotlight anchor". Pending row appeared with the default swept-beam-2d payload (per `defaultSpotlightPayloadForKind('swept-beam-2d')` — matches the spec §1.3 canonical case identical to stadium's seed values) and a panel-generated id `anc_eede3f17-...` (the `crypto.randomUUID()` path in `onAddSpotlightAnchor`, mirroring A3's pendingId pattern). Edited the payload's label to confirm dirty tracking armed the Save button. Clicked Save. RPC `rpc_venue_anchor_upsert` succeeded via the corrected 3-arg `p_partial` jsonb call; row transitioned from pending to saved (id preserved as the panel-generated UUID, NOT restored to the seed id — this is the expected hazard the SQL restore addresses, matching A2 hollywoodbowl + A3 stadium precedents).

**Database state post-round-trip:** one stadium spotlight row, id=`anc_eede3f17-...`. The round-trip lifecycle (Delete → Add → Save) works end-to-end. The id divergence from the deterministic seed id reproduces the A2/A3 hazard.

**Seed-id restore:** applied per the A2/A3 precedent before closeout. See "Cleanup completed in this verification cycle" for the SQL + result.

**PASS** ✓ — round-trip lifecycle confirmed; idempotency-hazard handling confirmed.

### Check 22 — Per-kind preview

Previewed each of the 3 A4a kinds:

- **stadium (swept-beam-2d):** 4 trapezoid-gradient spotlight beams pivoting at top-center of canvas (translate(W/2, 0); rotate by per-beam angle). Each beam's gradient runs the full canvas height; 3-stop gradient (0/0.5/1) with mid-stop alpha × 0.4 visibly correct (gradient softer in the middle than a 2-stop linear would be). Hues match the [220, 200, 240, 180] palette — cool blues + purples. Beams swept independently to random target angles via the power1.inOut ease reconstruction (slow continuous motion, 1.5–4s per sweep). Initial stagger of `i * 800ms` visible at preview start (beams kicked off in sequence). count:4 rendering confirmed (4 distinct beams, not 1). ✓

- **festival (pulsed-laser):** 6 narrow rotated lasers pivoting at bottom-center of canvas (translate(W/2, H); rotate by per-laser angle). Each laser's gradient runs upward (axis 0,0 → 0,-H); 3-stop gradient (0/0.6/1) with mid-stop alpha × 0.3 visibly correct. Hues stepped i×60 (red/orange/yellow/green/cyan/blue/magenta across the 6 lasers). Continuous base-angle drift was visible (lasers slowly traversing across their angle range, with reflect at ±π*0.48). Beat-pulse fired at BPM=128 (≈469ms per beat — visibly synchronized across all 6 lasers); attack phase (60ms power3.out, alpha→0.85, width→base×2.5) snapped each laser to peak; decay phase (380ms power2.in) eased back to base alpha=0.35 + base widths [3,5,3,5,3,5]. First pulse fired at BEAT × 0.5 offset per `first_pulse_offset_beats=0.5`. count:6 rendering confirmed. ✓

- **speakeasy (light-shaft):** 3 vertical trapezoid amber shafts at fixed x positions (0.25, 0.50, 0.75 of canvas width), no rotation. 2-stop gradient (0/1) ran top-to-bottom over canvas height × 0.7 (gradient bottom and path bottom coincide at y=0.7H — visibly correct). Color fixed at rgb(255,210,140) — warm amber. Shafts drifted independently on x (±40px around current via drift_distance_px=80) and alpha (per-tween random within [0.03, 0.09]); sine.inOut ease produced visibly smooth motion. Initial stagger of per-shaft `Math.random() * 2000ms` visible (shafts kicked off at scattered times). count:3 rendering confirmed. ✓

All 3 kinds render visually correctly. The kind-discriminated form swapped per-kind sections when the kind selector changed (A4a uses re-render on change; A3 uses hide/show — filed as DEFERRED). The preview canvas behaved as a bounded surface; no overflow into surrounding admin UI. The Stop button (panel top) successfully halted all active previews.

**PASS** ✓

### Check 23 — RPC authority gate

Fired `rpc_venue_anchor_upsert` from a signed-in non-admin browser session with a spotlight payload.

Request: fresh anchor id, `p_venue_id='stadium'`, `p_partial={type:'spotlight', payload:<minimal valid swept-beam-2d>, label:'Spotlights'}`.

Response: HTTP 403; body `{success:false, data:null, error:{code:42501, message:'not a platform admin'}}`. The is_platform_admin gate in db/035's `rpc_venue_anchor_upsert` body refused the call before any write attempted. No row created in `venue_anchors`.

Test method: signed in as a known non-admin user FIRST (not signed-out — a signed-out browser returns HTTP 401 from Supabase's auth gateway, which is a different gate than the in-RPC 42501 check under test). 401-vs-403 distinction matches the A2 Check 10 / A3 Check 17 test-method note.

**PASS** ✓ — DB gate intact for spotlight anchors (same gate as audio + particle anchors; same db/035 RPC body, just exercised with `type='spotlight'` in p_partial).

### Check 24 — D8 dormancy + karaoke read-path unchanged

Loaded `karaoke/stage.html` on stadium (the most-spotlight-heavy in-scope venue, with both 2D beams and 3D cones). The procedural `AMBIENT_PROFILES.stadium.anim()` ran as expected: 400 phone-light dots twinkling in the crowd area + 4 GSAP-swept spotlight beams + the GSAP `crowdState.brightness` cheer-swell loop. Stadium's 3D path (`buildStadiumEffects3D`) also ran: 2000 Three.js `Points` for phone lights + 4 cone meshes for spotlights.

Browser console: no errors related to `spotlight`, `anchor`, `renderer`, or `venue-registry`. The new `<script type="module" src="../shell/venue-renderers/spotlight.js">` tag at line 18 loaded and registered its renderer without issue (confirmed by Check 19).

`git diff f167ec6^ f167ec6 -- karaoke/stage.html` shows exactly one line changed — the new `<script>` tag. No reader-path change. D8 invariant intact.

Festival + speakeasy also verified visually — festival's 6 GSAP-pulsed lasers + strobe + confetti render unchanged; speakeasy's 3 GSAP-drifting amber shafts + smoke wisps + 3D candle Points + 3D smoke spheres render unchanged. The seeded spotlight anchors in db/037 are dormant data; the procedural code in karaoke/stage.html remains load-bearing until Stage A7 (the read-path switch + AMBIENT_PROFILES retirement).

**PASS** ✓

---

## Bugs caught this stage

Three distinct bugs caught across the verification cycle, all attributable to the same root cause: **§9 step 4 proposal-vs-A3-implementation drift**. The spec proposal described expected behavior in English but didn't enumerate every call shape + DOM-selector dependency against A3's actual implementation. The bugs surfaced in flight to Check 19 (Bug 1) and Check 21 (Bugs 2 + 3); all fixed mid-verification in two standalone commits, both pushed immediately so subsequent checks ran against corrected behavior.

**Bug 1 — admin-venues.html missing the `spotlight.js` script tag**

Hit pre-Check 19. The §9 step 4 spec said §4.7 covered "one new `<script>` tag in `karaoke/stage.html`" — true but incomplete. A3 also loads its renderer from `admin-venues.html:45` because that's where the preview path consumes `window.elsewhere.particleRenderer.particleAnchorRenderer(...)`. Without the equivalent admin-venues.html tag for spotlight, the preview path silently fails (no error — the `?.` chain on the optional `window.elsewhere?.spotlightRenderer?.spotlightAnchorRenderer?.(...)` call returns undefined, and the renderer never instantiates). The Check 19 console lookup against karaoke/stage.html would still pass (registry-side has the renderer because karaoke/stage.html does load it) but the admin preview wouldn't work.

Fix: single-line `<script type="module" src="shell/venue-renderers/spotlight.js"></script>` addition at admin-venues.html line 46. Shipped as commit `0b2dec0` mid-verification, pushed standalone.

**Bug 2 — `onSpotlightAnchorSave` called the RPC with 11 args instead of the 3-arg `p_partial` jsonb signature**

Hit during Check 21's first Save attempt. My §9 step 4 proposal (and the implementation that followed it) constructed:

```js
window.sb.rpc('rpc_venue_anchor_upsert', {
  p_id, p_venue_id, p_type, p_label, p_yaw_deg, p_pitch_deg,
  p_start_sec, p_end_sec, p_link, p_payload, p_is_broken
});  // ← 11 params
```

But the RPC signature from db/035:72-76 is `rpc_venue_anchor_upsert(p_id text, p_venue_id text, p_partial jsonb)` — exactly 3 params, with `p_partial` carrying a jsonb of column→value pairs. A3's call at admin-venues.html:1695-1699 uses the correct shape; I'd drafted the call from the spec's English description ("upsert the anchor's column values via RPC") without checking A3's actual call shape against the actual RPC signature.

Fix: rebuilt `onSpotlightAnchorSave` to construct `partial = { type: 'spotlight', payload, label }` and call:

```js
window.sb.rpc('rpc_venue_anchor_upsert', {
  p_id: anchorId, p_venue_id: venueId, p_partial: partial
});  // 3 params, A3-precedent shape
```

Also dropped the `argId = isPending ? null : anchorId` logic (always pass anchorId; the RPC dispatches INSERT vs UPDATE internally based on existence-check) and dropped `is_broken: false` from partial (column default is `false`; A3 omits it).

**Bug 3 — `renderSpotlightAnchorRowHTML` emitted `class="anchor-row-status"` but `showAnchorStatus` selects `.anchor-status`**

Hit during the same Save attempt as Bug 2 (the error toast would have thrown on null.textContent). My §9 step 4 proposal invented `<div class="anchor-row-status" data-status-for="${anchorId}">` as the status surface; A3's `showAnchorStatus` at admin-venues.html:1780-1786 does `row.querySelector('.anchor-status')`. The selector mismatch would have caused `statusEl.textContent = msg` to throw "Cannot set property 'textContent' of null" on every Save attempt, blocking even error-display.

Fix: changed the class to `anchor-status` and dropped the unused `data-status-for` attribute.

**Bugs 2 + 3 fixed in one commit (`2056a72`)** — tightly coupled (both block the Save path; both surfaced in the same diagnostic; one-commit pattern matches the A3 `27610e4` precedent of a single mid-verification fix commit per bug-cluster).

**Root cause synthesis.** All three bugs share the same antipattern: the §9 step 4 proposal was drafted in English description ("the panel calls the upsert RPC", "the panel surfaces status messages") without explicitly enumerating call shapes against existing A3 patterns. The A3 source file is the authoritative pattern reference; the spec's English description is a planning document, not a binding API contract. Future proposal cycles should include an explicit "verify call shape against existing RPC signatures + verify DOM class names against existing utility selectors" pass before locking the proposal. Filed as a DEFERRED entry (entry (d) in the closeout list).

**No other bugs caught this stage.**

---

## Test artifacts — row inventory

### Edited rows during this verification

One row touched in `public.venue_anchors`:
- **Stadium spotlight anchor** — deleted in Check 21's panel test (id=`anc_spot_stadium`), re-created via "+ Add" → form edit → Save with panel-generated id `anc_eede3f17-...`. Then restored to the seed id `anc_spot_stadium` via the seed-id restore SQL (see Cleanup).

### Other tables

No edits to other tables. Specifically:
- `venue_defaults` — unchanged (Stage A1 surface).
- `karaoke_venue_settings` — unchanged (anchor_patch is a Stage A7 concern).
- `costumes`, `venue_suggested_costumes` — unchanged (Stage A8 scope).

### Other anchors

No edits to audio or particle anchors. db/035's 19 audio rows + db/036's 4 particle rows intact and unaffected.

The 2 non-stadium spotlight anchors (festival, speakeasy) were previewed in Check 22 but not edited or saved; their database rows are unchanged from db/037's seed.

### Cleanup completed in this verification cycle

**Seed-id restore SQL** applied to prod 2026-05-27 via Supabase SQL Editor. Per the A2 hollywoodbowl + A3 stadium precedents — Check 21's round-trip left the stadium spotlight row with the panel-generated id `anc_eede3f17-...` rather than the seed id `anc_spot_stadium`. Re-applying db/037 in that state would INSERT a second row (ON CONFLICT (id) DO NOTHING wouldn't match the differently-named row), violating one-spotlight-anchor-per-venue at the seed-id level.

One-row UPDATE applied:

```sql
update public.venue_anchors
   set id = 'anc_spot_stadium'
 where venue_id = 'stadium'
   and type     = 'spotlight'
   and id       = 'anc_eede3f17-...'   -- panel-generated UUID from Check 21 round-trip
returning id, venue_id, type, label;
```

`RETURNING` result: exactly one row — `anc_spot_stadium | stadium | spotlight | Spotlights`. UPDATE matched the intended row only.

Post-UPDATE verification SELECT:

```sql
select id, venue_id, label, payload->>'kind' as kind, payload->'count' as count
  from public.venue_anchors
 where venue_id = 'stadium'
   and type     = 'spotlight';
```

Result: exactly one row — `anc_spot_stadium | stadium | Spotlights | swept-beam-2d | 4`. All 5 predicates (one row exists; id is seed id; label is 'Spotlights'; kind is 'swept-beam-2d'; count is 4) PASS. db/037 idempotency restored.

Label restoration not needed — the re-created anchor saved with `label='Spotlights'` (the panel's default, via `defaultSpotlightPayloadForKind` + `makeSpotlightAnchorRow`'s pending-anchor construction), matching the seed value byte-for-byte. The UPDATE touched `id` only.

FK-safety pre-verified: `venue_anchors.id` has no incoming FK references in the current schema (per db/032 — the planned per-app `anchor_patch` is a Stage A7 concern, not yet built). Updating the primary key was safe. Same posture as A2 hollywoodbowl + A3 stadium restores.

---

## Conclusion

Stage A4a ships clean. All six §8 verification checks PASS. Three bugs caught + fixed mid-verification across two commits (`0b2dec0` + `2056a72`); one schema-state divergence (the Check 21 idempotency hazard) restored via one-row SQL UPDATE before closeout.

A4a delivered:
- `shell/venue-renderers/spotlight.js` — self-contained 2D-canvas spotlight anchor renderer with 3-kind discriminated dispatch (swept-beam-2d / pulsed-laser / light-shaft). GSAP-equivalent motion via 4 pure-JS ease functions (`power1.inOut`, `power2.in`, `power3.out`, `sine.inOut`) matching GSAP's naming verbatim — no library dependency. Multi-field tween records (one tween mutates multiple item fields in lockstep). advanceTween ordering fix from §9 step 3 review (clears `item.active_tween` BEFORE on_complete invocation so callbacks that re-arm the tween stick). count:N per-item array iteration per spec §1.6.
- `admin-venues.html` — kind-discriminated spotlight authoring panel with bounded 2D-canvas preview surface, anchor-level dirty tracking via `state.spotlightAnchorDirty` Set, PERMIT multi-anchor rule per spec §4.5 / D2 (diverges from A2/A3 PREVENT — "+ Add" stays visible regardless of count). Per-item array length validation surfaces inline via `.array-length-mismatch` styling. v2.138 → v2.139. `state.spotlightAnchors` cache + `venueHasAnyDirty` + `discardAllForVenue` extended to include spotlight anchor dirty state. `loadAndRenderSpotlightPanel` called from venue-selection callback alongside particle/audio.
- `db/037_spotlight_anchor_seed.sql` — 3-row spotlight anchor seed (stadium swept-beam-2d count:4; festival pulsed-laser count:6; speakeasy light-shaft count:3). Disco excluded (floor-flash is overlay-class, Stage A4.5); honkytonk excluded (neon-tint is overlay-class, Stage A4.5); ghost venues excluded (no spotlight or 3D content per foundation pass §10.1).
- `karaoke/stage.html` — one-line `<script>` tag at line 18 registering the spotlight renderer (D8-permitted per the A2 Check 12 / A3 Check 18 precedent).

The §1 spec amendment landed pre-implementation at `d50cbc9` (gradient_stops added to all 3 kinds' geometry, color fragment dropped for hue-driven kinds, drift_speeds negative-first for pulsed-laser, first_pulse_offset_beats scalar added, geometry.pivot consistency) — all 3 payloads incorporate the amended schema cleanly. The §9 step 1 foundation/payload pass surfaced these as DIV-1 through DIV-6; DIV-1/2/3 resulted in spec amendment, DIV-4/5/6 resolved without schema impact.

Per Direction §7's hybrid sequencing: **A4a is 2D-canvas only**. The 3D spotlight builders (stadium 4 cone meshes via `buildStadiumEffects3D` + speakeasy 40 candle Points via `buildSpeakeasyEffects3D`) + the absorbed 3D particle paths (stadium 2000 phone-lights + speakeasy 60 sphere-mesh smoke, both deferred from A3 spec §0.2) + the new Three.js admin preview surface are A4b's scope. A4b ships as its own propose-pause cycle.

Per spec §5 / D8: **A4a ships dormant**. The 3 seeded spotlight anchors are data only; karaoke's read path continues consulting `AMBIENT_PROFILES` + `addVenueEffects3D` until Stage A7 (the read-path switch + AMBIENT_PROFILES retirement) promotes anchors to load-bearing.

Eight DEFERRED.md entries land in this closeout commit:
- (a) Modulator synthesis decision for A4b 3D phone-lights — A4b's new 3D phone-lights anchor binds `crowd_brightness` for parity with A3's 2D phone-lights anchor; the source uses frame-counter sin, so the binding is synthesized rather than extracted. A7's modulator-driver work needs the full inventory.
- (b) PERMIT multi-anchor structural UI evolution — when A4b ships speakeasy's 2nd spotlight anchor (point-light candles), the panel needs an anchor-list with per-anchor editor pattern, not the current "one kind at a time" pattern.
- (c) GSAP-equivalent motion accuracy verification gap — A7's read-path switch is the first prod exercise of the ease-function reconstruction; refinement may be needed if visible divergence surfaces.
- (d) §9 step 4 proposal-vs-A3-implementation drift cluster — 3 mid-verification findings (script tag missing, RPC signature mismatch, status element class mismatch). Future proposal cycles must explicitly verify call shapes against RPC signatures + DOM class names against utility selectors before locking.
- (e) Kind-switch UX divergence — A4a panel re-renders on kind change (discards other-kind edits); A3 uses hide/show via `[data-kind-section]` attribute toggle (preserves edits). Functional but suboptimal UX.
- (f) Spotlight panel button styling + Stop-all placement — low-contrast button styling inconsistent with A3's particle panel; "Stop all previews" button at panel top vs. previews at row bottom creates scroll-distance UX issue. Same issue affects particle panel.
- (g) Missing per-row Stop button on spotlight preview — current pattern (Preview → Replay toggle, no per-row Stop) treats preview as "always running until killed via global button." Per-row Stop would be cleaner. Applies to particle panel too.
- (h) Mid-implementation findings already recorded in MIGRATIONS_APPLIED.md: `state.spotlightAnchorDirty` Map→Set correction; pending-id pattern alignment to `anc_<uuid>`; `state.spotlightAnchors` Map cache addition.

Next deliverable on this thread per `docs/VENUE-ADMIN-UI-DIRECTION.md` §7's "Plan B hybrid sequencing": **Stage A4b — 3D spotlight (stadium cones + speakeasy candle Points) + 3D particle extension (stadium phone-lights + speakeasy smoke) + new Three.js admin preview surface.** A4b ships as its own propose-pause cycle.

Stage A4b foundation pass next.

---

## End of log
