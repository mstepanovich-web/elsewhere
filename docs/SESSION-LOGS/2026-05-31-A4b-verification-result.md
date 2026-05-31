# Venue Admin UI Stage A4b — Verification Result Log

**Spec:** `docs/VENUE-ADMIN-UI-A4B-BUILD-SPEC.md` (foundation brief at `docs/A4B-BUILD-SPEC-BRIEF.md`)

**Workstream:** Phase 3 / Plan B — 3D venue effects: 3D spotlight (stadium 4 cone meshes + speakeasy 40 candle Points) + 3D particle extension (stadium 2000 phone-lights + speakeasy 60 sphere-mesh smoke) + new Three.js admin preview surface + 2D panel-standardization retrofit. The fifth Block A vertical slice per `docs/VENUE-ADMIN-UI-DIRECTION.md` §7's hybrid sequencing. A4b is the 3D-canvas sub-stage of A4 (A4 was sub-staged into A4a + A4b in planning chat 2026-05-27); A4a shipped 2026-05-27 (`f167ec6` + closeout `21991e8`). A4b closes Stage 4 of the A1-A8 staging; the next deliverable is Stage 4.5 (overlay renderer) — see Conclusion below.

**Commits in this stage (chronological on `main`):**
- `48b7b38` — `db: A4b 3D anchor seed (db/038) — 4 anchors, 3d-three context` (gate 1, shipped pre-verification, prod-applied 2026-05-28)
- `995b0e7` — `wip(venue-admin): Stage A4b verification branch — 3D venue effects + Three.js admin preview + 2D panel standardization` (Gates 2-8c implementation bundle)
- `42c501e` — `fix(venue-admin): A4b verification — escape backtick trap in renderSpotlightAnchorRowHTML comment block` (triage 1)
- `604f1fa` — `fix(venue-admin): A4b verification — clone preview canvas per Play to survive forceContextLoss` (triage 2, superseded by 8f713a0)
- `8f713a0` — `fix(venue-admin): A4b verification — canvas lifecycle redesign + 3D wrap CSS (Fix 1 redo)` (triage 3)
- `6c269fe` — `fix(venue-admin): A4b verification — lifecycle parity (4 handlers) + Chrome GPU-pressure mitigation + 3D camera framing` (triage 4 + Fix 2 camera)
- `db04b91` — `docs(venue-admin): A4b closeout — version bumps + build-spec brief + pause-doc DEFERRED entries` (closing commit on a4b-verify)
- `d26f309` — `feat(venue-admin): Stage A4b — 3D venue effects + Three.js admin preview + 2D panel standardization` (--no-ff merge to main)

**Prod-apply state:**
- db/038 applied via Supabase SQL Editor 2026-05-28. The 4 seed anchors (`anc_spot_stadium_beams3d`, `anc_spot_speakeasy_candles`, `anc_par_stadium_phonelights3d`, `anc_par_speakeasy_smoke3d`) are present in `public.venue_anchors` with `payload.context = '3d-three'` and the seeded payloads byte-faithful to spec §2.4-2.7.
- Verification deploy via GitHub Pages branch-source switch (a4b-verify → built 2026-05-31, source reverted to main post-closeout).
- iOS Capacitor bundle resynced post-merge (`~/sync-app.sh` + `npx cap sync ios` 2026-05-31). Xcode rebuild + install on device is the Mike-side follow-up before the next session.

---

## Outcome — 12 of 13 cluster checks PASS, 1 deferred

### Cluster 1 — Foundation + registration + dormancy

**C1.1 — 3D renderer registration (globals + registry).** Console expressions confirmed `window.elsewhere.spotlight3dRenderer` and `window.elsewhere.particle3dRenderer` resolve to objects; `await import('shell/venue-registry.js').then(m => [m.getAnchorRenderer('spotlight-3d'), m.getAnchorRenderer('particle-3d')])` returned two functions. Distinct-keys registration per the Gate 5 D-dispatch revision (originally spec §4.1's context-aware extension; revised to use `'spotlight-3d'` / `'particle-3d'` distinct registry keys derived from `(anchor.type, payload.context)` per spec §0.3 amendment). **PASS** ✓

**C1.2 — db/038 seed visible in stadium + speakeasy.** Stadium spotlight panel shows both `anc_spot_stadium` (A4a 2D, swept-beam-2d, light-shaft) AND `anc_spot_stadium_beams3d` (A4b 3D, swept-beam-3d) — D-multianchor verified. Stadium particle panel shows `anc_par_stadium` (A3 2D, point-cloud) AND `anc_par_stadium_phonelights3d` (A4b 3D, point-cloud-3d). Speakeasy similarly shows both 2D and 3D spotlight + particle anchors alongside the A4a/A3 anchors. All 4 db/038 seeded anchors reachable in the UI. **PASS** ✓

**C1.3 — Per-kind preview render × 4 3D anchors.** Each of the 4 db/038 anchors previewed via per-row ▶ Play; each rendered visible Three.js geometry — swept-beam-3d 4 cones radiating from origin (post Fix 2), point-light 40 candle sprites in flat ring, point-cloud-3d 2000 twinkling phone-light points, volumetric-3d 60 drifting smoke spheres. **PASS** ✓

**C1.4 — WebGL context teardown / leak.** Play/Stop cycled 4-6 times on point-cloud-3d (the longest-running preview path). Canvas count cycled `baseline → baseline+1 → baseline` cleanly per cycle. No monotonic growth, no sad-face icon, no TypeError. Per-Play creates fresh canvas via `createElement` + `appendChild`; per-Stop removes via `st.canvasEl.remove()` after `webglRenderer.dispose()` + `forceContextLoss()` per D-webgl. The wrap's CSS `aspect-ratio: 2/1` keystone holds the bordered box stable when empty. **PASS** ✓

**C1.5 — RPC gate refuses non-admin.** **DEFERRED.** A4b modified zero auth/gate code (verified by grep: changes were admin-venues.html lifecycle handlers + CSS + 2 renderer module `getContext` lines, none in `shell/auth.js` or admin-venues.html's boot/gate section at L1171+). Risk of A4b breaking the platform-admin gate is effectively zero. Sign-out friction (admin-venues.html has no sign-out affordance, see Bugs / UX bundle below) made the explicit verification lower-priority than verification value. Re-verify at next session that involves auth-adjacent changes. Filed as DEFERRED §1.6 item 5 + carry-over (Conclusion).

**C1.6 — D8 dormancy — karaoke/stage.html still works for 2D venues.** Opened `karaoke/stage.html` (deployed a4b-verify branch URL); loaded a 2D venue. Page rendered correctly, console clean. The 2 new `<script type="module">` tags for `spotlight-3d.js` + `particle-3d.js` loaded and registered against the venue-registry without breaking karaoke's existing render path. The renderer-modules `registerAnchorRenderer('spotlight-3d', ...)` and `registerAnchorRenderer('particle-3d', ...)` fire on script load; karaoke does not yet consult those entries (the read-path switch is Stage A7 part 1, formerly "Block B"). **PASS** ✓

### Cluster 2 — Panel standardization + critical 8c production-bug regression check

**C2.1 — .anchor-row-actions legible across all 5 panels + Stop button present.** All 5 panels (audio, particle 2D, particle 3D, spotlight 2D, spotlight 3D) render the canonical `.anchor-row-actions` container with legible buttons (the pre-A4a regression — the zero-CSS-match `.anchor-row-controls` typo from Gate 8a — is no longer present). Per-row ■ Stop button present on all preview-capable rows (2D + 3D). Audio panel uses a panel-level stop-all rather than per-row Stop (per the existing A2 pattern, recorded under "Bugs / UX bundle" item 2 as a future panel-standardization unification item). **PASS** ✓

**C2.2 — A2 audio regression (preview / save / persist).** On a venue with audio anchors: preview → label edit → Save → reload → confirm persisted → revert. All clean. The lifecycle-parity change to `onPlayParticlePreview` / `onPlaySpotlightPreview` did not regress audio (audio panel was not modified in this commit's lifecycle work — A2's preview path uses a panel-level "stop all" + a single playback handle, not per-row preview state). **PASS** ✓

**C2.3 — A3 particle 2D regression — preview / save / persist (non-volumetric kind).** Point-cloud kind: preview → label edit → Save → persist → revert → Stop. All clean. The lifecycle-parity change (fresh canvas per Play, remove on Stop) verified working on the A3 2D path — `endedTimerId` soft-timeout logic preserved for one-shot kinds. **PASS** ✓

**C2.4 — A4a light-shaft 2D round-trip (8b regression sentinel).** Loaded the speakeasy `anc_spot_speakeasy` (A4a light-shaft) anchor: label round-trip via Save with no other edits → reload → confirmed persisted → reverted. The 8b refactor target (per-kind-section-scoped `readSpotlightPayloadFromRow`) round-trips cleanly — the label survives the reader + RPC + reload path. Stricter SQL byte-compare not run; UI round-trip + revert sufficient evidence per Mike's call given (a) the 2D `spotlight.js` code paths were not touched by the lifecycle commits, only the `getContext('2d')` calls got the `willReadFrequently: true` hint added, and (b) C2.6's analogous byte-equivalent round-trip on the 3D side passes byte-equal modulo benign jsonb canonicalization (see C2.6). **PASS** ✓

**C2.5 — A4a kind-toggle preservation (DEFERRED-e fix).** Pending swept-beam-2d row: typed `[10, 20, 30, 40]` into hues field → toggled kind to pulsed-laser → toggled back to swept-beam-2d → hues value survived. The §6.7 DEFERRED-e fix (per-kind sections hidden via `[hidden]` rather than re-rendered) preserves cross-kind field values on the 2D path. **PASS** ✓

**C2.6 — A4b 3D round-trip × 4 anchors + spot-check SQL.** All 4 db/038 anchors saved via UI with no edits; PostgREST query before+after diffed via Python with `0.0 ↔ 0` int-valued-float normalization (Mike pre-cleared this as benign jsonb canonicalization, not progressive drift). Round-trip result: ✓ all 4 anchors label + payload byte-equal modulo jsonb canonicalization. Spot-check SQL (`db/spot-check-3d-asymmetry.sql`) confirmed the §2.7 spawn-region asymmetry survives: `spawn_region_initial.phi_norm_range = [0.4, 0.9]` and `spawn_region_respawn.phi_norm_range = [0.55, 0.9]` both present and distinct in the round-tripped `anc_par_speakeasy_smoke3d` payload. The load-bearing asymmetry (the narrower respawn region per spec §2.7, which avoids the lower edge where freshly-spawned particles would collide with already-rising ones) is preserved. **PASS** ✓

**C2.7 — 🚨 8c volumetric velocity_range fix verification.** Loaded speakeasy `anc_par_speakeasy` (A3 2D volumetric particle anchor — the 8c production-bug target). Edited `vy` range from seeded value to `[-0.99, -0.01]` (a clearly distinct value). Saved. Hard-reloaded (Cmd+Shift+R). Reloaded payload showed `vy: [-0.99, -0.01]` — the edit persisted. Then reverted to seeded value. **The pre-8c production bug is gone**: previously, the unscoped reader queried the first matching textarea in the row regardless of which kind section was visible, so editing volumetric's `velocity_range` silently returned the directional-emitter's hidden `velocity_range` value instead of volumetric's edited one (silent data loss on save). Post-8c, the per-kind-section-scoped reader correctly returns volumetric's edited value. **PASS** ✓

---

## Bugs caught this stage

Four bugs caught during verification, plus a fifth class (camera framing) surfaced when 3D previews became reachable. All fixed mid-verification; the chain is preserved in the branch's commit history (5 fix commits) and bundled into the --no-ff merge to main.

**Bug 1 — L2984 backtick trap (commit `42c501e`, A4b verification Cluster 1.2).**

Symptom: stadium spotlight panel crashed on load with `TypeError: kind is not a function` from `admin-venues.html:2984:34` via `renderSpotlightAnchorRowHTML → makeSpotlightAnchorRow → liveAnchors.forEach`.

Root cause: unescaped backticks (U+0060) inside an HTML comment inside the outer template literal of `renderSpotlightAnchorRowHTML` (2D spotlight row renderer, defined at L2964). The JS lexer closed the outer template literal at the first backtick (col 24), then parsed the rest of the comment as `.fld - kind\`...\`(...)` — a binary subtraction with the right operand being a tagged template literal where `kind` (the function parameter, a string) was treated as the tag function. Runtime threw on every 2D spotlight anchor render.

Pre-existing Gate 8a regression — the comment block was added during A4a's panel-standardization retrofit and shipped to prod because A4a verification didn't load a venue with a 2D spotlight anchor after 8a landed (A4a's three test venues were stadium/festival/speakeasy, none of which were exercised in their 2D spotlight render path post-8a). A4b verification surfaced it on stadium load because stadium has both `anc_spot_stadium` (2D, A4a) and `anc_spot_stadium_beams3d` (3D, A4b); the forEach hit the 2D row first (id.asc), crashed, never reached the 3D row.

Fix: two backticks → single quotes at L2984, matching the style of the nearby L3252 comment which uses single quotes for the analogous selector reference. Audit confirmed (awk + grep) this is the sole instance of unescaped backticks inside HTML comments inside template literals in admin-venues.html. Recorded as DEFERRED §1.6 item 1 (A4a verification protocol gap — include "load each venue × each anchor type" baseline in future verification protocols).

**Bug 2 — WebGL precision crash (Fix 1, commit `604f1fa` — superseded by `8f713a0`).**

Symptom: point-cloud-3d preview rendered correctly on first Play, then crashed Play-after-Stop with `TypeError: Cannot read properties of null (reading 'precision')` from `three.min.js:6 (WebGLCapabilities)`.

Root cause: `tearDownPreview3d` calls `webglRenderer.dispose()` + `webglRenderer.forceContextLoss()` per D-webgl. `forceContextLoss()` permanently severs the WebGL context attached to the canvas DOM element. The next Play reused the same canvas via `rowEl.querySelector('.spotlight-3d-preview-canvas')` and constructed a new `THREE.WebGLRenderer({canvas: canvasEl})`; Three.js called `canvas.getContext('webgl')` which returned the lost context, then `gl.getShaderPrecisionFormat(gl.VERTEX_SHADER, gl.HIGH_FLOAT)` returned null, then `.precision` on null threw.

Fix 1 (commit `604f1fa`, superseded): clone the canvas via `cloneNode(false)` + `replaceChild` before constructing the new WebGLRenderer. Returned `canvasEl` from `createPreviewContext3d` so callers could update `st.canvasEl` to the fresh node.

**Bug 3 — Canvas stacking introduced by Fix 1 (Fix 1-redo, commit `8f713a0`).**

Symptom: Fix 1 eliminated the precision crash but introduced a stacked-canvas bug. Each Play/Stop cycle visibly accumulated canvases vertically in the wrap div: Play renders correctly → Stop shows a "sad face" broken-canvas icon (the dead force-lost canvas left in the DOM) → Play again renders but stacks a new canvas above the dead one → 3 stacked canvases after 3rd Play.

Root cause: indeterminate from static reading. `replaceChild` *should* swap exactly one node, and audit confirmed no other DOM references to the preview canvas DOM nodes (no ResizeObserver, no event listeners, no module-level caches; the renderer modules never see the canvas).

Fix 1-redo (commit `8f713a0`): canvas lifecycle redesign — instead of clone+replaceChild, use `wrapEl.querySelectorAll('canvas').forEach(c => c.remove())` + `createElement` + `appendChild` per Play; `st.canvasEl.remove()` per Stop in tearDownPreview3d. Three plain DOM ops with unambiguous semantics — no `replaceChild` dependency. Also closed a pre-existing CSS gap discovered during this triage: the 3D wrap classes (`.particle-3d-preview-canvas-wrap`, `.spotlight-3d-preview-canvas-wrap`) had zero CSS rules anywhere in admin-venues.html or elsewhere-theme.css (the L2314 comment "parallels the 2D wrap class for max-width:480px bounding" promised parallel styling but the rules were never written). Added CSS mirroring the 2D wrap + `aspect-ratio: 2/1` on the wrap as the keystone that keeps the bordered box visually stable when the canvas is removed on Stop.

**Bug 4 — Cross-context canvas contamination (commit `6c269fe`).**

Symptom: order-dependent. Hard-reload → Play 2D spotlight first → renders fine. Hard-reload → Play 3D spotlight first → Stop → Play 2D spotlight → fails with `spotlight.js:331 spotlight: ctx.canvas has no 2D rendering context` (canvas.getContext('2d') returned null).

Three plausible mechanisms ruled out by code analysis:
1. `spotlight.js` canvas acquisition — uses `ctx.canvas` only (no document lookups, no fallback acquisition).
2. `stopAllOther3dPreviews` teardown chain — only touches `st.canvasEl` in `state.spotlight3dPreviewState` / `state.particle3dPreviewState`, which are set exclusively to freshly-created 3D canvases.
3. Three.js r128 WebGLRenderer constructor — minified bundle has zero `querySelector` / `getElementsByTagName` / `getElementById` calls (verified by `curl` + `grep`); uses `parameters.canvas` if provided, otherwise creates a fresh canvas via `createElementNS`. Internal helper canvases (`xt` for texture image conversion, `P` for texture resizing) are held module-level and never inserted into page DOM.

DOM diagnostic confirmed scoping is correct: before-Play and after-3D-Stop runs both show the 2D canvas remains under `anc_spot_stadium` with its 2D class, untouched. The 3D path never reaches the 2D canvas at the DOM level.

Working hypothesis (unverified): Chrome's hardware-accelerated 2D canvas implementation (Skia GL backend) shares GPU resource accounting with WebGL contexts. Prior WebGL allocation can cause subsequent `getContext('2d')` calls to be refused under GPU pressure even after the WebGL context is disposed. The order-dependency (3D Play first → 2D Play fails) is the fingerprint of this class of bugs in Chrome's canvas implementation.

Mitigations applied in commit `6c269fe`:
1. **Defensive fresh-canvas-per-Play lifecycle on all four preview handlers** (2D+3D spotlight, 2D+3D particle). Each `getContext('2d')` call happens on a fresh DOM element with no prior history. Mirrors the 3D handlers' lifecycle from Fix 1-redo onto the 2D handlers.
2. **`willReadFrequently: true` on every 2D `getContext` call** in `spotlight.js` (3 sites — handleSweptBeam2d, handlePulsedLaser, handleLightShaft) and `particle.js` (1 site). Hints Chrome to use software/CPU backing for the 2D canvas instead of Skia GL — directly counters the GPU pressure mechanism.
3. Added `aspect-ratio: 2/1` to the 2D wrap CSS rules (`.spotlight-preview-canvas-wrap`, `.particle-preview-canvas-wrap`) so they hold their bounding box when canvas is removed on Stop (same pattern as the 3D wrap CSS from Fix 1-redo).

Symptom-resolved. Root cause is browser-internal and not fixable from JS. Filed as DEFERRED §1.6 item 4 with the hypothesis, full repro, and three-mechanism elimination recorded.

**Fix 2 — Camera framing for the black-rendering 3D kinds (commit `6c269fe`).**

Symptom: swept-beam-3d, point-light, volumetric-3d all rendered black on first Play during C1.3 (point-cloud-3d rendered correctly throughout). Diagnosis: `positionCameraForKind` values placed the camera at distance 5-18 from origin, but the source anchor geometry lives at `sphere_radius` 80-490 (cones, candles, smoke). The mesh geometry was entirely outside the camera frustum. point-cloud-3d worked despite the same camera positioning because `THREE.Points` with `sizeAttenuation: true` keeps point sprites visible regardless of distance.

Fix: camera POVs updated to match actual geometry placement:
- `swept-beam-3d`: camera at origin (0,0,0) looking up at (0,380,0); FOV bumped 60° → 90° to fit the 4 cones spread near +Y at sphere_radius 380. Matches karaoke's panorama-center POV (the camera is at the center of the panorama and looks outward at the cones).
- `point-light`: camera at (0,80,350) looking at (0,-100,0). External viewpoint, looking down at the 40-candle ring at y≈-100.
- `volumetric-3d`: camera at (0,50,450) looking at (0,-50,0). External viewpoint, far enough to see the drifting smoke volume.
- `point-cloud-3d`: unchanged — Mike confirmed it renders correctly.

Camera values are math-derived (per the geometry math in spec §2.4-2.7), not yet visually iterated. Mike's C1.3 verification confirmed all 4 kinds render visible geometry post-fix; no iteration needed for this stage. Future visual-polish iterations may refine the framing if motion-accuracy verification (Stage A7) surfaces specific issues — out of scope here.

---

## Test artifacts — row inventory

### Edited rows during this verification

5 anchors touched in `public.venue_anchors` during the verification sweep:

- **Stadium spotlight beams3d** (`anc_spot_stadium_beams3d`) — saved no-edits during C2.6. Round-trip clean modulo benign jsonb canonicalization (`0.0` → `0` on int-valued floats; details in C2.6 PASS note).
- **Speakeasy spotlight candles** (`anc_spot_speakeasy_candles`) — saved no-edits during C2.6. Round-trip clean.
- **Stadium particle phonelights3d** (`anc_par_stadium_phonelights3d`) — saved no-edits during C2.6. Round-trip clean.
- **Speakeasy particle smoke3d** (`anc_par_speakeasy_smoke3d`) — saved no-edits during C2.6. §2.7 spawn-region asymmetry confirmed preserved. Round-trip clean.
- **Speakeasy particle volumetric 2D** (`anc_par_speakeasy`) — edited during C2.7 to verify the 8c production-bug fix. Edit was `vy` range to `[-0.99, -0.01]`; persisted across hard-reload; then reverted to seeded value pre-closeout.

### Other tables

No edits to other tables. Specifically:
- `venue_defaults` — unchanged (Stage A1 surface).
- `karaoke_venue_settings` — unchanged (anchor_patch is Stage A7 concern).
- `costumes`, `venue_suggested_costumes` — unchanged (Stage A8 scope).

### Other anchors

No edits to audio anchors (db/035's 19 audio rows intact). A label round-trip was performed on `anc_spot_speakeasy` (A4a light-shaft) during C2.4 with no other edits; label round-tripped cleanly via the 8b-refactored reader. A label round-trip was also performed on a 2D particle non-volumetric anchor during C2.3. No A3 particle 2D anchors edited beyond C2.7's volumetric `vy` round-trip (reverted).

### Cleanup completed in this verification cycle

- **C2.7 revert**: `anc_par_speakeasy.payload.vy` reverted from the C2.7 edit `[-0.99, -0.01]` back to the seeded value before closeout. Database state matches db/036's seed post-closeout.
- **No seed-id restore needed** — A4b's 4 new anchors (db/038) were touched only via no-edit saves; the panel-generated UUID divergence pattern from A4a Check 21 doesn't apply because no Add-then-Save-from-pending cycle was exercised on the 3D anchors this stage.

---

## Conclusion

Stage A4b ships clean. 12 of 13 cluster checks PASS; C1.5 (RPC gate non-admin refuse) deferred — A4b modified zero auth/gate code, risk of breakage effectively zero. Four bugs caught + fixed mid-verification across four fix commits; camera framing for the 3D previews resolved as Fix 2 in the same commit as the fourth bug fix.

A4b delivered:

- **`shell/venue-renderers/spotlight-3d.js`** — self-contained 3D spotlight anchor renderer dispatching on `payload.kind ∈ {swept-beam-3d, point-light}`. Returns `{update, dispose}` per D-contract (caller-owns-RAF per D-raf). swept-beam-3d uses per-cone `THREE.CylinderGeometry` + `MeshBasicMaterial(side: BackSide)` with frame-counter-based angle drift + sin-wobble phi modulation matching `buildStadiumEffects3D` byte-faithfully. point-light uses a single shared `THREE.PointsMaterial` whose opacity flickers globally every `flicker.frame_period` frames — source-faithful per the candles builder's lack of per-particle phase array.

- **`shell/venue-renderers/particle-3d.js`** — self-contained 3D particle anchor renderer dispatching on `payload.kind ∈ {point-cloud-3d, volumetric-3d}`. point-cloud-3d uses a custom `THREE.ShaderMaterial` with per-vertex `phase` BufferAttribute (the D-twinkle synthesis — completes the source's dead `phases` Float32Array allocation by wiring it through to fragment-shader-side per-particle independent twinkle). `crowd_brightness` modulator binding multiplies whole-cloud alpha when present; falls back to 1.0 when no driver registered (the dormant-state behavior until A7). `uTime` uniform wraps `% 2π` per spec §3.7 r128 precision-cliff note — REQUIRED, not cosmetic (GLSL mediump precision in fragment shaders causes unbounded `uTime` accumulator to lose precision within minutes, making twinkle go choppy then freeze). volumetric-3d uses N independent `MeshBasicMaterial` spheres sharing one `SphereGeometry`; per-instance userData carries vy/vx/vz/life/maxOpacity; per-frame opacity follows `maxOpacity * sin(life * π)`; respawn at `life > respawn_threshold` to the narrower `spawn_region_respawn` per the §2.7 asymmetry.

- **`admin-venues.html`** — kind-discriminated 3D spotlight + 3D particle authoring panels with bounded Three.js preview surface (~60-80 LOC scaffolding, the first Three.js code in admin-venues.html ever; the file previously had zero Three.js per D-webgl). Per-row Play/Replay/Stop wiring for 3D rows + the per-section-scoped payload readers (7c) that both Preview AND Save (7d) call. One-at-a-time 3D preview budget across BOTH spotlight 3D and particle 3D Maps (HAZARD B — both compete for the ~16 WebGL context cap). Canvas lifecycle: fresh canvas per Play (createElement + appendChild to the stable wrap parent), canvas removal on Stop (st.canvasEl.remove() after webglRenderer.dispose() + forceContextLoss()), wrap CSS `aspect-ratio: 2/1` keystone keeps the bordered box stable when empty. Replay = Play (no separate handler — the Play handler always re-allocates fresh context + fresh handle, which IS Replay's semantics). 2D panel-standardization retrofit (D-standardize): canonical `.anchor-row-actions` across all 5 panels, per-row ■ Stop button on all preview-capable 2D rows. v2.139 → v2.140.

- **`karaoke/stage.html`** — two new `<script type="module">` tags loading `spotlight-3d.js` + `particle-3d.js` (D8-permitted per the A2 Check 12 / A3 Check 18 precedent — registration only, no read-path change until A7). v2.101 → v2.102 (both L457 + L614 occurrences).

- **`shell/venue-renderers/spotlight.js` + `shell/venue-renderers/particle.js`** — `willReadFrequently: true` hint added to every `getContext('2d')` call (3 sites in spotlight.js, 1 site in particle.js). Mitigates Chrome's GPU-resource-pressure cross-context contamination per the Bug 4 hypothesis. No behavior change for the 2D rendering itself.

- **`db/038_3d_anchor_seed.sql`** — 4-row 3D anchor seed (`anc_spot_stadium_beams3d`, `anc_spot_speakeasy_candles`, `anc_par_stadium_phonelights3d`, `anc_par_speakeasy_smoke3d`). Applied prod 2026-05-28. All anchors carry `payload.context = '3d-three'`.

- **Schema vocabulary unchanged.** `db/032`'s `venue_anchors_type_check` (`type` column: `'spotlight'` / `'particle'` / `'audio'` / etc.) NOT extended. The `-3d` suffix is a renderer-registry-key derivation only — A7 read-path will derive the lookup key from the row as `key = anchor.payload.context === '3d-three' ? anchor.type + '-3d' : anchor.type` per the Gate 5 D-dispatch revision. Filed as DEFERRED §1.6 item 2 — decision needed before A7 on whether to extend the known-types list in `shell/venue-registry.js` or accept the registration warnings permanently.

Per Direction §7's hybrid sequencing: **A4b closes Stage 4** (Stage 4 = A4a + A4b umbrella). The 3D builders and the absorbed 3D particle paths that were structurally deferred from A3 (per A3 spec §0.2) are now data-driven and dormant in the registry. The next stage on this thread is **Stage 4.5** — see "Next" below.

Per spec §0.3 / D8: **A4b ships dormant**. The 4 seeded 3D anchors are data only; karaoke's read path continues consulting `AMBIENT_PROFILES` + `addVenueEffects3D` until Stage A7 (the read-path switch + AMBIENT_PROFILES retirement + venue modulator system + ghost-venue-shadowed-dead-code deletion). A4b's renderer modules are registered against `shell/venue-registry.js` and accessible via `window.elsewhere.spotlight3dRenderer` / `window.elsewhere.particle3dRenderer`; the only live consumer until A7 is the admin preview surface in admin-venues.html.

### DEFERRED entries filed at closeout

Six items recorded in `docs/SESSION-A4B-VERIFICATION-PAUSE.md` §1.6 and to be filed in `docs/DEFERRED.md` at the next session start:

1. **A4a verification protocol gap.** Gate 8a panel standardization shipped without exercising 2D spotlight rendering on stadium/festival/speakeasy. The L2984 backtick trap (Bug 1 this stage) was discoverable on any venue with a 2D spotlight but A4a verification didn't load one after 8a landed. Mitigation: include "load each venue × each anchor type" as a baseline check in future verification protocols, especially after panel-standardization or comment-block edits.

2. **Registry vocabulary extension for `spotlight-3d` / `particle-3d` keys.** `shell/venue-registry.js:165` warns that these keys are not in the known anchor type vocabulary (spec §3.2 + db/032 CHECK). Registration accepted per Gate 5's distinct-keys revision but warning fires on every page load. Two options: (a) extend the known-types list in venue-registry.js to include the `-3d`-suffixed keys, or (b) accept the warning permanently as part of the registry-key / DB-type split. Decision needed before A7 hits the same vocabulary boundary on the read-path switch.

3. **Pages-deploy-via-API path documentation.** The `gh api -X PUT /repos/.../pages` + `POST /pages/builds` + poll-workflow path used in this verification cycle is reusable. Worth documenting as a verified-branch-deploy pattern in CLAUDE.md or a sibling doc — saves manual web-UI clicks on every future verification cycle that needs branch-source switching.

4. **Cross-context canvas contamination (Chrome GPU-pressure hypothesis).** Full repro, three ruled-out mechanisms (spotlight.js canvas acquisition, teardown chain, Three.js r128 source), and Chrome's hardware-accelerated 2D canvas (Skia GL backend) sharing GPU resource accounting with WebGL contexts as the working hypothesis. Mitigations applied (defensive fresh-canvas-per-Play + willReadFrequently:true) are sufficient for the symptom. Root cause is browser-internal and not fixable from JS. Future debugging path: `chrome://gpu-internals` exposure during the bug repro. Worth re-checking if it re-emerges during the unified-app migration when these canvases get touched differently.

5. **C1.5 RPC gate verification carry-over.** Deferred this stage because A4b modified zero auth/gate code. Re-verify at next session that touches auth-adjacent surfaces.

6. **UX bundle (4 findings).**
   - `'ok'` vs `'success'` class drift on Save success status. Five save handlers; three use `'success'` (audio L1938, particle 2D L2728, particle 3D L4741), but both spotlight handlers (A4a 2D L3719, A4b 3D L4641) use `'ok'` which has no CSS rule — falls back to `var(--color-text-faint)` instead of gold. Trivial fix: `'ok'` → `'success'` at L3719 + L4641. Held during A4b triage to keep the focused commit clean.
   - Stop-button location inconsistency. Audio panel's Stop is at the row-top-right outside `.anchor-row-actions`; spotlight 2D / particle 2D / 3D have Stop in the action row alongside Save. Worth a panel-standardization unification pass post-A4b.
   - No sign-out affordance on admin-venues.html. To switch accounts, admin must navigate to a different Elsewhere surface (the shell `index.html`) and sign out from there. Trivial addition — sign-out link near the admin badge would close this. Also significant friction for any future "verify as non-admin" testing cycle (see DEFERRED item 5).
   - Save-flow behavioral inconsistencies across panels (beyond the class drift). Mike noted behavior delta during the verification sweep; pending more detailed repro from the next verification cycle.

### Next

Per `docs/VENUE-ADMIN-UI-DIRECTION.md` §7 (Plan B hybrid sequencing) + Mike's closeout instruction:

- **Immediate next: Stage 4.5 (overlay renderer + overlay authoring panel).** Per the per-type mini-spec pattern (like A3 had its own spec at `docs/VENUE-ADMIN-UI-A3-BUILD-SPEC.md` and A4a/A4b had their own specs). Stage 4.5 handles the overlay-class effects that A3 and A4 both surfaced but didn't schedule — specifically disco's floor-flash + festival's strobe (the overlay-class effects per A3 foundation pass §10.1 + A4a's exclusion of these venues from db/037). Adds `'overlay'` to the `db/032_venue_abstraction_schema.sql` `venue_anchors_type_check` CHECK constraint as part of its migration. Foundation pass + spec draft is the natural next session.

- **Then: Stage 5 (remaining types).** `callout`, `pin`, `video`, `link-hotspot` per spec §3.2's vocabulary list. Ships per opportunity (long-tail; not blocked on A4.5 unless karaoke depends on a Stage 5 type for the A7 read-path switch).

- **Then: Stage 6 (per-app override editor for `anchor_patch`).** The karaoke-specific override surface. Can ship in any order after Stage 1; lower priority than 1-5/7.

- **Then: Stage 7 — the karaoke reader-path switch.** Part 1 = the rewire older docs called "Block B" (which is PART OF Stage 7, NOT a separate downstream stage per Direction §7 lines 437-449). Part 2 = visual parity verification across every translated venue before any procedural code is removed. Part 3 = delete `AMBIENT_PROFILES` + `addVenueEffects3D` + implement the venue modulator system. **This is where A4b's dormant 3D renderers go live** (the registry-resolved data-driven path becomes karaoke's authoritative source).

- **Then: Stage 8 (costume library + suggested-costumes editor).** Ships when karaoke's costume rendering is rewired. Direction §7 implies this can ride alongside or after A7.

### Carry-over into next session

- **C1.5 (non-admin gate verification).** Re-verify when next session involves auth-adjacent changes. Needs a reachable sign-out affordance — the UX-bundle item below (no-sign-out on admin-venues.html) is the natural pre-req. Either fix the sign-out item first, OR use the shell `index.html` sign-out as the work-around path.

- **UX-bundle item 6 (`'ok'` → `'success'` class drift fix + Stop-button location + no-sign-out + save-flow inconsistencies).** Worth a small panel-polish commit before any stage that touches admin permissions (Stage 6's per-app override editor would be the natural venue, since 6 is admin-permissions-adjacent). The class-drift fix is the smallest concrete change (`'ok'` → `'success'` at L3719 + L4641); the rest are panel-standardization unification scope.

---

## End of log
