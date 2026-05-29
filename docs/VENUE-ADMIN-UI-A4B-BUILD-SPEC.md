# Venue Admin UI — Stage A4b Build Spec

Status: binding spec for the A4b implementation cycle.
Extends: docs/VENUE-ADMIN-UI-DIRECTION.md §7 (the A1–A9 staging,
updated 2026-05-27 commit c2de05f; A4 sub-staging recorded in
commit 21991e8 — Stage 4 paragraph). A4b is the 3D extension
sub-stage of A4 — see §0.2.
Baseline commit: `21991e8` (A4a closeout, clean tree).
Foundation pass that produced the inventory + locked decisions:
`docs/A4B-BUILD-SPEC-BRIEF.md` (2026-05-28). Pre-spec investigations
that pulled the canonical patterns: the A4a foundation pass §11
(CLR-A4-1 through CLR-A4-8) + the 2026-05-28 panel-pattern
investigation (canonical `.anchor-row-actions`, glyph codepoints).
**Discipline carried from A4a (DEFERRED-d):** specify by exact
class name, exact codepoint, exact RPC signature, exact line
reference. Match real code, not prose.

═══════════════════════════════════════════════════════════════════════
§0 — CONTEXT AND LOCKED DECISIONS
═══════════════════════════════════════════════════════════════════════

§0.1 — What A4b is
A4b is the fifth Block A vertical slice and the second sub-stage of
A4: a 3D spotlight renderer + 3D particle extension + new Three.js
admin preview surface + panel-standardization pass that retrofits
the canonical pattern across all three existing panels (audio,
particle, spotlight).

Four new anchors land in `db/038`:
  • stadium 4 cone meshes        → kind: `swept-beam-3d`
  • speakeasy 40 candle Points   → kind: `point-light`
  • stadium 2000 phone-lights    → kind: `point-cloud-3d`
  • speakeasy 60 sphere smoke    → kind: `volumetric-3d`

Two new renderer modules (sibling files, NOT extensions):
  • `shell/venue-renderers/spotlight-3d.js` — D-files-spot
  • `shell/venue-renderers/particle-3d.js`  — D-files-par

One new architectural surface:
  • Three.js admin preview canvas pipeline in `admin-venues.html`
    (admin currently has zero Three.js; A4b adds the WebGLRenderer
    + Scene + PerspectiveCamera + RAF loop scaffolding).

One panel restructure (D-multianchor):
  • Spotlight panel becomes a true anchor-list with N concurrent
    editor blocks (speakeasy now genuinely has 2 spotlight anchors:
    light-shaft from A4a + point-light from A4b).

One cross-cutting cleanup (D-standardize):
  • All three panels conform to the A3 canonical pattern
    (`.anchor-row-actions`, `▶ Play preview`, U+21BB `↻ Replay`,
    `<div class="anchor-status" data-status></div>`, isPending-
    conditional Cancel/Delete) + gain a per-row Stop button.

Per D8, everything ships DORMANT — karaoke's read path still
consults `AMBIENT_PROFILES` + `addVenueEffects3D` until Stage A7
(the read-path switch + procedural-code retirement). A4b's
admin-side preview is the sole consumer of the registered 3D
renderers until A7.

§0.2 — Relationship to A4a
A4a shipped 2026-05-27 (commit `f167ec6` + fixes `0b2dec0` + `2056a72`,
closeout `21991e8`): 2D-canvas spotlight renderer + 3-kind
authoring panel + 3-row spotlight seed. A4 was sub-staged into
A4a + A4b on 2026-05-27 in planning chat because the 3D-preview
surface is genuinely new architectural territory (`admin-venues.html`
has zero Three.js code today); sub-staging isolated the preview-
surface risk to A4b.

A4b extends A4a's contract surface without modifying A4a's
shipped behavior:
  • `payload.context` discriminator (introduced A4a §1.7) — A4b
    populates `"3d-three"` on every 3D anchor.
  • Anchor type vocabulary (`spotlight`, `particle`) — A4b adds
    sibling kinds under existing types. No db/032 CHECK change.
  • Anchor registry mechanism — A4b registers 3D-context impls
    under the same anchor types. Dispatch on `payload.context`.

A4a's renderer module (`shell/venue-renderers/spotlight.js`) and
panel function block stay byte-for-byte unchanged EXCEPT for the
panel-standardization pass (D-standardize) which fixes the 5 known
divergences from canonical. The five fixes are surgical and listed
explicitly in §7.

§0.3 — Locked decisions (do not re-litigate)

| # | Decision | Resolution |
|---|----------|------------|
| **D-scope** | One stage or sub-stage | **One stage.** All 4 anchors + preview infra + renderers + panel standardization in one propose-pause cycle. Rationale: stadium cones + phone-lights share one builder function (`buildStadiumEffects3D` at karaoke/stage.html:2857-2940), so splitting spotlight/particle would span the same procedural code across two stages. |
| **D-files-spot** | Spotlight 3D file org | **Sibling `shell/venue-renderers/spotlight-3d.js`.** Overrides A4a spec §3.4's "extend the same file." 2D and 3D share only the payload contract + kind dispatch; rendering code is disjoint (2d-canvas vs WebGL). |
| **D-files-par** | Particle 3D file org | **Sibling `shell/venue-renderers/particle-3d.js`.** Same logic. `particle.js` stays 2D-only. |
| **D-dispatch** | Registry dispatch | **Distinct registry keys per (type, context) pair (Gate 5 decision 2026-05-28, revising the originally-locked context-aware-extension).** 2D modules register under their existing keys: `'audio'` / `'particle'` / `'spotlight'` (A2/A3/A4a registrations byte-for-byte unchanged). 3D modules register under distinct keys: `'spotlight-3d'` / `'particle-3d'`. Future Stage A7 read-path consumers derive the lookup key from the venue_anchors row: `key = anchor.payload.context === '3d-three' ? anchor.type + '-3d' : anchor.type` — using `anchor.type` (the table COLUMN value) NOT `payload.type` (which would be undefined; the spotlight/particle payloads don't carry a `type` key — `payload.type` exists only on audio payloads as a format discriminator, a naming-collision artifact). The DB `type` column at public.venue_anchors stays `'spotlight'` / `'particle'` etc. — db/032's `venue_anchors_type_check` vocabulary unchanged. The `-3d` suffix is a renderer-registry-key derivation only, not a schema-level type. No API change to `registerAnchorRenderer(type, impl)` or `getAnchorRenderer(type)` — they keep their existing 2-arg / 1-arg signatures at shell/venue-registry.js:154 + :205. Decision rationale: only ONE future consumer (the A7 read-path) reads the registry; admin preview uses `window.elsewhere.*Renderer` globals per §4.3. Extending register+get+all-callsites for a single future caller has larger surface than necessary. See Gate 2 DEFERRED-d findings F1-F5 (2026-05-28) for the evidence chain that motivated this revision. |
| **D-contract** | 3D renderer contract | **`{ update, dispose }`** — matches the source's verb (`buildStadiumEffects3D` returns `{update, dispose}` at karaoke/stage.html:2935-2938) and Three.js idiom. NO speculative `stop`. 2D stays `{ stop }` (self-RAF). The asymmetry is real and documented, not papered over. |
| **D-raf** | RAF ownership | 3D = **caller-owns-RAF** (renderer returns `{update, dispose}`; the admin preview owns the loop and calls `update()` per frame then renders). 2D = renderer-owns-RAF. Matches A4a D4 + confirmed against `karaoke/stage.html:4012-4052` (`renderLoop`). |
| **D-webgl** | Preview context strategy | **Lazy context per preview canvas; `renderer.dispose()` + `renderer.forceContextLoss()` on EVERY exit path** (Stop, venue switch, kind switch, navigate away, panel reload). No shared-context-swap machinery. Bounded active contexts. |
| **D-twinkle** | Phone-lights per-particle twinkle | **Build the correct version: custom `THREE.ShaderMaterial` with per-vertex `phase` attribute.** Honors the source's dead `phases` Float32Array (`karaoke/stage.html:2865-2868`) which proves per-particle intent. Each of 2000 points twinkles on its own phase, like A3's 2D phone-lights `Math.sin(this.phase)`. This is the one genuinely novel rendering bit in A4b. |
| **D-multianchor** | Multi-anchor UI | **Build it — functional floor.** Speakeasy genuinely has 2 spotlight anchors (light-shaft A4a + point-light A4b) that must be simultaneously visible/editable. Panel becomes anchor-LIST with per-anchor editor block + "add anchor (pick kind)" + per-anchor save/delete. No decorative extras (no drag-reorder, no inline rename). |
| **D-standardize** | Panel standardization | **All three panels (audio/particle/spotlight) conform to the A3 canonical pattern + gain per-row Stop.** Dedicated verification section, separate from 3D-anchor checks, to contain A2/A3 regression risk. |
| **D-datastatus** | `data-status` attribute | Include `data-status` on new markup for shape-match with A2/A3. Do NOT build behavior onto it (`showAnchorStatus` selects by `.anchor-status` class; the attribute stays vestigial). |
| **D-naming** | Anchor ids | Descriptive `_3d`/effect suffixes throughout (see §1.4). |
| **D-modulator** | 3D phone-lights modulator | Bind `crowd_brightness` modulator on `anc_par_stadium_phonelights3d` for A3 parity. Renderer multiplies per-particle twinkle by modulator value when present; defaults to 1.0 when no driver registered. Documented as **synthesized, not extracted** (source uses frame-counter sin, nothing to extract). |
| **D-a7** | Structurally deferred | Two items are A7's by nature, NOT punted: (1) full motion-accuracy verification (needs live karaoke read-path side-by-side, A7's switch); (2) ghost-venue shadowed dead-code deletion (`karaoke/stage.html:4935-4974`, A7's retirement scope). A4b tightens (1) by faithfully reproducing source motion math + documenting the mapping. |

═══════════════════════════════════════════════════════════════════════
§1 — KIND VOCABULARY
═══════════════════════════════════════════════════════════════════════

§1.1 — The four new kinds
A4b ships four sibling kinds, all carrying `payload.context: "3d-three"`,
all registered against EXISTING anchor types (`spotlight`,
`particle`). NO db/032 CHECK constraint change.

| Kind | Type | Source | Anchor |
|------|------|--------|--------|
| `swept-beam-3d` | spotlight | karaoke/stage.html:2884-2935 + update 2924-2933 (inside `buildStadiumEffects3D`) | `anc_spot_stadium_beams3d` |
| `point-light` | spotlight | karaoke/stage.html:2980-3000 + update 3024-3026 (inside `buildSpeakeasyEffects3D`) | `anc_spot_speakeasy_candles` |
| `point-cloud-3d` | particle | karaoke/stage.html:2861-2882 + update 2920-2923 (inside `buildStadiumEffects3D`) | `anc_par_stadium_phonelights3d` |
| `volumetric-3d` | particle | karaoke/stage.html:2946-2974 + update 3005-3022 (inside `buildSpeakeasyEffects3D`) | `anc_par_speakeasy_smoke3d` |

§1.2 — Sibling-kind discipline (per A4a §1.8)
Sibling-kinds, NOT 3D branches of A4a/A3 kinds. The kind dispatcher
in each 3D renderer module accepts only its kinds:

  • `spotlight-3d.js` accepts: `swept-beam-3d`, `point-light`.
    Rejects any other kind (warn + `{update:noop, dispose:noop}`).
  • `particle-3d.js` accepts: `point-cloud-3d`, `volumetric-3d`.
    Rejects any other kind (warn + no-op handle).

The 2D modules (A4a `spotlight.js` and A3 `particle.js`) are
unchanged: they continue to accept their A4a/A3 kinds and reject
the new 3D kinds (the rejection text in their existing dispatchers
already names `swept-beam-3d` and `point-light` as A4b-reserved
per A4a spec §1.8 — no edit needed there).

§1.3 — `payload.context = "3d-three"`
Every A4b seed row's payload carries `"context": "3d-three"`. The
registry dispatcher (§4) routes by context before kind. The
discriminator is the load-bearing field that lets one anchor
`type` (e.g. `spotlight`) host both 2D and 3D rendering paths
across two sibling renderer modules.

§1.4 — Anchor id naming (D-naming)
A4a used `anc_<typeprefix>_<venue>` (e.g. `anc_spot_speakeasy`).
A4b cannot reuse that — speakeasy already has `anc_spot_speakeasy`
(light-shaft from A4a). A4b's speakeasy spotlight anchor needs a
unique id, hence descriptive suffixes:

  • `anc_spot_stadium_beams3d`         (3D cones)
  • `anc_spot_speakeasy_candles`       (3D Points sprites)
  • `anc_par_stadium_phonelights3d`    (3D phone-lights)
  • `anc_par_speakeasy_smoke3d`        (3D sphere smoke)

The A4a-shipped row id `anc_spot_speakeasy` stays as the light-
shaft anchor. No retroactive rename. Multi-anchor PERMIT (A4a
D2) makes this work cleanly.

═══════════════════════════════════════════════════════════════════════
§2 — PAYLOAD SCHEMAS
═══════════════════════════════════════════════════════════════════════

§2.1 — Numerical precision policy
- Irrational values quoted to **6 decimal places** (matching A4a's
  §1.4 amendment policy for `Math.PI*0.35` → `1.099557`).
- Specifically: π → `3.141593`, π/2 → `1.570796`, 2π → `6.283185`.
- Whole numbers and exact decimals (e.g. 0.15, 0.04, 380) verbatim.
- Hex color literals expressed as web hex strings (`"#fffce0"`)
  in payload — renderer parses via `new THREE.Color(hexString)`.

§2.2 — Color value convention
A4a used `"color": {"mode": "fixed", "value": "rgb(255,210,140)"}`
for light-shaft. A4b's 3D kinds use web hex strings directly
(`"#fffce0"`) because Three.js's `THREE.Color` constructor accepts
hex strings natively. Per-item arrays of hex strings (`"colors":
["#fffce0", ...]`) match A4a's per-item hue array convention.
No `color: {mode: ...}` wrapper.

§2.3 — Modulator binding policy
Only `anc_par_stadium_phonelights3d` binds a modulator (D-modulator):

```json
"modulator": {"name": "crowd_brightness", "target": "opacity"}
```

The other three A4b kinds bind no modulator (matching A4a D5 for
the spotlights, and matching A3's speakeasy + festival particles
which also bind none). The modulator field is omitted from those
payloads.

═════════════════════════════════════════════════════════════════════

§2.4 — `swept-beam-3d` schema
Canonical case: stadium count:4. Source:
`karaoke/stage.html:2884-2935` (construction) + `2924-2933` (update).

```json
{
  "kind": "swept-beam-3d",
  "context": "3d-three",
  "count": 4,
  "phis":        [0.15, 0.15, 0.12, 0.12],
  "theta_init":  [0.000000, 3.141593, 1.570796, -1.570796],
  "colors":      ["#fffce0", "#fffce0", "#fff0cc", "#fff0cc"],
  "speeds":      [0.003, -0.004, 0.005, -0.003],
  "sphere_radius": 380,
  "wobble_amplitude": 0.08,
  "wobble_speed": 0.01,
  "look_at": [0, 0, 0],
  "geometry": {
    "radius_top": 0,
    "radius_bottom": 35,
    "height": 300,
    "radial_segments": 16,
    "height_segments": 1,
    "open_ended": true,
    "translate_y": -150
  },
  "material": {
    "opacity": 0.06,
    "side": "back",
    "depth_write": false,
    "transparent": true
  }
}
```

**Fidelity table (`swept-beam-3d`):**

| Payload field | Source line | Source expression | Evaluated |
|---|---|---|---|
| `count` | 2885-2890 | length of `spotData` array | 4 |
| `phis[i]` | 2885-2890 | `sd.phi` per entry | [0.15, 0.15, 0.12, 0.12] |
| `theta_init[i]` | 2885-2890 | `sd.theta` per entry | [0, π, π/2, -π/2] → 6-decimal |
| `colors[i]` | 2885-2890 | `sd.color` (hex literal) | [0xfffce0, 0xfffce0, 0xfff0cc, 0xfff0cc] → "#fffce0", … |
| `speeds[i]` | 2885-2890 | `sd.speed` per entry | [0.003, -0.004, 0.005, -0.003] |
| `sphere_radius` | 2902 | `const r = 380` | 380 |
| `wobble_amplitude` | 2928 | `Math.sin(frame*0.01)*0.08` amplitude | 0.08 |
| `wobble_speed` | 2928 | `Math.sin(frame*0.01)*0.08` frequency coefficient | 0.01 (per-frame phase delta) |
| `look_at` | 2908 | `cone.lookAt(0, 0, 0)` | [0, 0, 0] |
| `geometry.radius_top` | 2892 | `CylinderGeometry(0, ...)` 1st arg | 0 |
| `geometry.radius_bottom` | 2892 | `CylinderGeometry(_, 35, ...)` 2nd arg | 35 |
| `geometry.height` | 2892 | `CylinderGeometry(_, _, 300, ...)` 3rd arg | 300 |
| `geometry.radial_segments` | 2892 | `CylinderGeometry(_, _, _, 16, ...)` 4th arg | 16 |
| `geometry.height_segments` | 2892 | `CylinderGeometry(_, _, _, _, 1, ...)` 5th arg | 1 |
| `geometry.open_ended` | 2892 | `CylinderGeometry(_, _, _, _, _, true)` 6th arg | true |
| `geometry.translate_y` | 2893 | `geo.translate(0, -150, 0)` 2nd arg | -150 |
| `material.opacity` | 2895 | `MeshBasicMaterial({opacity: 0.06})` | 0.06 |
| `material.side` | 2896 | `THREE.BackSide` | "back" (renderer maps to `THREE.BackSide`) |
| `material.depth_write` | 2896 | `depthWrite: false` | false |
| `material.transparent` | 2895 | `transparent: true` | true |

**Motion model (per-frame, in `update()` at 2924-2933):**
- `cone.userData.angle += cone.userData.speed` (per cone)
- `phi_active = sd.phi + Math.sin(frame * wobble_speed) * wobble_amplitude`
- `theta_active = cone.userData.angle`
- Position recomputed from `(sphere_radius, phi_active, theta_active)` each frame; `cone.lookAt(look_at)` re-aims.
- NOTE: source `frame * 0.01` is per-frame counter starting at 0. Renderer reproduces via per-state `frame` counter (separate from `performance.now()`) for byte-exact match. Frame rate dependence is a known property — accuracy verification at A7 (D-a7 item 1).

§2.5 — `point-light` schema
Canonical case: speakeasy count:40. Source:
`karaoke/stage.html:2980-3000` (construction) + `3024-3026` (update).

```json
{
  "kind": "point-light",
  "context": "3d-three",
  "count": 40,
  "color": "#ffaa33",
  "sprite_size": 4,
  "size_attenuation": true,
  "base_opacity": 0.7,
  "depth_write": false,
  "transparent": true,
  "position_layout": "ring",
  "r_range": [80, 330],
  "y_range": [-120, -80],
  "theta_range": [0.000000, 6.283185],
  "flicker": {
    "mode": "global-sync-random",
    "frame_period": 4,
    "opacity_min": 0.5,
    "opacity_max": 1.0
  }
}
```

**Fidelity table (`point-light`):**

| Payload field | Source line | Source expression | Evaluated |
|---|---|---|---|
| `count` | 2982 | `const cCount = 40` | 40 |
| `color` | 2993 | `PointsMaterial({color: 0xffaa33})` | "#ffaa33" |
| `sprite_size` | 2993 | `size: 4` | 4 |
| `size_attenuation` | 2993 | `sizeAttenuation: true` | true |
| `base_opacity` | 2993 | `opacity: 0.7` | 0.7 |
| `depth_write` | 2993 | `depthWrite: false` | false |
| `transparent` | 2993 | `transparent: true` | true |
| `r_range[0]` | 2986 | `80 + Math.random() * 250` lower bound | 80 |
| `r_range[1]` | 2986 | `80 + Math.random() * 250` upper bound | 330 (= 80 + 250) |
| `y_range[0]` | 2988 | `-80 - Math.random() * 40` (most negative end) | -120 |
| `y_range[1]` | 2988 | `-80 - Math.random() * 40` (least negative end) | -80 |
| `theta_range` | 2987 | `Math.random() * Math.PI * 2` | [0, 2π] → [0.000000, 6.283185] |
| `flicker.frame_period` | 3025 | `if(frame % 4 === 0)` | 4 |
| `flicker.opacity_min` | 3026 | `0.5 + Math.random() * 0.5` lower bound | 0.5 |
| `flicker.opacity_max` | 3026 | `0.5 + Math.random() * 0.5` upper bound | 1.0 (= 0.5 + 0.5) |

**Motion model:** every `frame_period` frames, set the SHARED `PointsMaterial.opacity` to `randIn(opacity_min, opacity_max)` — all 40 candles flicker in lockstep because they share one material. Per-particle independent flicker is NOT in source; A4b reproduces source semantics exactly (no per-particle attribute upgrade, unlike `point-cloud-3d` D-twinkle).

§2.6 — `point-cloud-3d` schema
Canonical case: stadium count:2000. Source:
`karaoke/stage.html:2861-2882` (construction) + `2920-2923` (update).
**Note:** A4b diverges from source motion via D-twinkle — see §3.7.

```json
{
  "kind": "point-cloud-3d",
  "context": "3d-three",
  "count": 2000,
  "color": "#ffffff",
  "sprite_size": 2.5,
  "size_attenuation": true,
  "base_opacity": 0.8,
  "depth_write": false,
  "transparent": true,
  "position_layout": "hemisphere_flattened",
  "r_range": [460, 490],
  "phi_norm_range": [0.15, 0.85],
  "theta_range": [0.000000, 6.283185],
  "y_flatten_factor": 0.4,
  "y_offset": -80,
  "twinkle": {
    "mode": "per-particle-shader",
    "phase_init": "random-2pi",
    "phase_omega_per_frame": 0.04,
    "alpha_center": 0.5,
    "alpha_swing": 0.3
  },
  "modulator": {"name": "crowd_brightness", "target": "opacity"}
}
```

**Fidelity table (`point-cloud-3d`):**

| Payload field | Source line | Source expression | Evaluated |
|---|---|---|---|
| `count` | 2863 | `const count = 2000` | 2000 |
| `color` | 2876 | `PointsMaterial({color: 0xffffff})` | "#ffffff" |
| `sprite_size` | 2877 | `size: 2.5` | 2.5 |
| `size_attenuation` | 2877 | `sizeAttenuation: true` | true |
| `base_opacity` | 2878 | `opacity: 0.8` | 0.8 |
| `depth_write` | 2878 | `depthWrite: false` | false |
| `transparent` | 2878 | `transparent: true` | true |
| `r_range[0]` | 2868 | `460 + Math.random() * 30` lower | 460 |
| `r_range[1]` | 2868 | upper | 490 |
| `phi_norm_range[0]` | 2866 | `(Math.random()*0.7 + 0.15) * Math.PI` — coefficient lower | 0.15 |
| `phi_norm_range[1]` | 2866 | coefficient upper | 0.85 (= 0.15 + 0.7) |
| `theta_range` | 2867 | `Math.random() * Math.PI * 2` | [0, 2π] → [0.000000, 6.283185] |
| `y_flatten_factor` | 2871 | `r * Math.cos(phi) * 0.4 - 80` | 0.4 |
| `y_offset` | 2871 | `... - 80` | -80 |
| `twinkle.mode` | (SYNTHESIZED — D-twinkle) | source uses global-sync; A4b uses per-particle shader | "per-particle-shader" |
| `twinkle.phase_init` | 2868 (DEAD CODE) | `phases[i] = Math.random() * Math.PI * 2` (allocated, never read in source) | "random-2pi" |
| `twinkle.phase_omega_per_frame` | 2922 | `Math.sin(frame * 0.04)` frequency coefficient | 0.04 |
| `twinkle.alpha_center` | 2922 | `0.5 + Math.sin(...) * 0.3` center | 0.5 |
| `twinkle.alpha_swing` | 2922 | `0.5 + Math.sin(...) * 0.3` swing | 0.3 |
| `modulator` | (SYNTHESIZED — D-modulator) | source binds nothing; A4b adds `crowd_brightness` for A3 parity | as JSON above |

**D-twinkle synthesis note:** the source uses GLOBAL-SYNC twinkle
(every 3 frames, one shared `lightMat.opacity` value). The `phases`
Float32Array at line 2865-2868 is **allocated but never read by
`update()`** — dead code that proves per-particle intent never
implemented. A4b builds the correct version per D-twinkle: each
particle gets its own phase via a per-vertex shader attribute.
Renderer detail in §3.7. The `phase_omega_per_frame` matches the
source's `0.04` coefficient byte-for-byte; the divergence is per-
particle vs global-sync, not motion math.

**D-modulator synthesis note:** the source binds no external scalar
(uses frame counter). A4b adds the `crowd_brightness` modulator
binding for A3 parity (A3's `anc_par_stadium` 2D phone-lights also
binds this modulator). When A7's modulator driver registry is live,
the value multiplies the per-particle twinkle. When absent (current
state, until A7), the multiplier defaults to 1.0 — per-particle
shader twinkle is the sole motion. Renderer detail in §3.8.

§2.7 — `volumetric-3d` schema
Canonical case: speakeasy count:60. Source:
`karaoke/stage.html:2946-2974` (construction) + `3005-3022` (update).

```json
{
  "kind": "volumetric-3d",
  "context": "3d-three",
  "count": 60,
  "respawn": true,
  "color": "#bbbbaa",
  "depth_write": false,
  "transparent": true,
  "sphere_geometry": {
    "radius": 1,
    "width_segments": 6,
    "height_segments": 6,
    "shared": true
  },
  "scale_range": [15, 55],
  "opacity_range": [0.01, 0.05],
  "vy_range": [0.08, 0.20],
  "vx_range": [-0.025, 0.025],
  "vz_range": [-0.025, 0.025],
  "life_init_range": [0, 1],
  "life_increment_per_frame": 0.003,
  "opacity_curve": "sin_pi",
  "respawn_threshold": 0.98,
  "spawn_region_initial": {
    "r_range": [50, 350],
    "phi_norm_range": [0.4, 0.9],
    "theta_range": [0.000000, 6.283185]
  },
  "spawn_region_respawn": {
    "r_range": [50, 350],
    "phi_norm_range": [0.55, 0.90],
    "theta_range": [0.000000, 6.283185]
  },
  "y_flatten_factor": 0.5,
  "y_offset": -30
}
```

**Fidelity table (`volumetric-3d`):**

| Payload field | Source line | Source expression | Evaluated |
|---|---|---|---|
| `count` | 2948 | `const smokeCount = 60` | 60 |
| `respawn` | 3015 | `if(t > 0.98) { ... reset ... }` | true |
| `color` | 2953 | `MeshBasicMaterial({color: 0xbbbbaa})` | "#bbbbaa" |
| `depth_write` | 2955 | `depthWrite: false` | false |
| `transparent` | 2953 | `transparent: true` | true |
| `sphere_geometry.radius` | 2950 | `SphereGeometry(1, ...)` 1st arg | 1 |
| `sphere_geometry.width_segments` | 2950 | `SphereGeometry(_, 6, _)` 2nd arg | 6 |
| `sphere_geometry.height_segments` | 2950 | `SphereGeometry(_, _, 6)` 3rd arg | 6 |
| `sphere_geometry.shared` | 2950 | one geometry instantiation, 60 meshes use it | true |
| `scale_range[0]` | 2953 | `15 + Math.random() * 40` lower | 15 |
| `scale_range[1]` | 2953 | upper | 55 (= 15 + 40) |
| `opacity_range[0]` | 2955 | `Math.random() * 0.04 + 0.01` lower | 0.01 |
| `opacity_range[1]` | 2955 | upper | 0.05 (= 0.04 + 0.01) |
| `vy_range[0]` | 2967 | `0.08 + Math.random() * 0.12` lower | 0.08 |
| `vy_range[1]` | 2967 | upper | 0.20 (= 0.08 + 0.12) |
| `vx_range[0]` | 2968 | `(Math.random() - 0.5) * 0.05` lower | -0.025 |
| `vx_range[1]` | 2968 | upper | 0.025 |
| `vz_range[0]` | 2969 | `(Math.random() - 0.5) * 0.05` lower | -0.025 |
| `vz_range[1]` | 2969 | upper | 0.025 |
| `life_init_range` | 2970 | `Math.random()` (initial spawn life) | [0, 1] |
| `life_increment_per_frame` | 3010 | `mesh.userData.life += 0.003` | 0.003 |
| `opacity_curve` | 3013 | `maxOpacity * Math.sin(t * π)` | "sin_pi" |
| `respawn_threshold` | 3015 | `if(t > 0.98)` | 0.98 |
| `spawn_region_initial.r_range` | 2960 | `50 + Math.random() * 300` | [50, 350] |
| `spawn_region_initial.phi_norm_range` | 2961 | `(0.4 + Math.random() * 0.5) * Math.PI` | [0.4, 0.9] |
| `spawn_region_respawn.r_range` | 3017 | `50 + Math.random() * 300` | [50, 350] |
| `spawn_region_respawn.phi_norm_range` | 3018 | `(0.55 + Math.random() * 0.35) * Math.PI` | [0.55, 0.90] — **NOTE: different from initial** |
| `y_flatten_factor` | 2965, 3020 | `r * Math.cos(phi) * 0.5 - 30` | 0.5 |
| `y_offset` | 2965, 3020 | `... - 30` | -30 |

**Phi-range divergence note:** the initial spawn (line 2961) and
the respawn (line 3018) use **different `phi_norm_range`s** in the
source — initial covers `[0.4, 0.9]` (wider), respawn covers
`[0.55, 0.90]` (narrower, avoids the lower edge). A4b reproduces
this byte-faithfully via two separate payload sub-objects
(`spawn_region_initial` + `spawn_region_respawn`). NOT a bug, NOT
a normalization — source-faithful.

═══════════════════════════════════════════════════════════════════════
§3 — RENDERER DESIGN
═══════════════════════════════════════════════════════════════════════

§3.1 — Two new sibling files (D-files-spot, D-files-par)
`shell/venue-renderers/spotlight-3d.js` and
`shell/venue-renderers/particle-3d.js` are NEW files, peers of A2's
`audio.js`, A3's `particle.js`, A4a's `spotlight.js`.

Rationale (overrides A4a spec §3.4's "extend the same file"): the
2D and 3D rendering code is functionally disjoint. 2D uses
`canvas.getContext('2d')` + `c.fillRect` / `c.createLinearGradient`.
3D uses Three.js scene graph + WebGL. Combining into one file would
roughly double the file size with no shared logic between the
context branches. Cleaner separation: each module is concerned
with one rendering API. They share only the payload contract (the
kind + context dispatcher patterns are duplicated, not coupled).

§3.2 — Self-contained posture (mirror of A4a §3.1)
Both 3D modules are SELF-CONTAINED. They re-implement their own
state and accept a scene/camera reference passed via `ctx`. They
do NOT import, wrap, or call `karaoke/stage.html`'s
`buildStadiumEffects3D` / `buildSpeakeasyEffects3D` — those mutate
`panScene` and have global side-effects. Calling them would
inject preview content into karaoke's live panorama. Karaoke
stays byte-for-byte untouched (D8).

NO `import 'three'` — the global `THREE` is loaded via the CDN
script tag at `karaoke/stage.html:621` (and the analogous tag
added at `admin-venues.html` per §4.2). The 3D renderers reference
`THREE.WebGLRenderer`, `THREE.Scene`, etc. as globals.

§3.3 — Renderer contract (D-contract)
Entry signatures:

```
spotlightAnchor3dRenderer(anchor, ctx) → { update, dispose }
particleAnchor3dRenderer(anchor, ctx)  → { update, dispose }
```

Where:
  - `ctx.scene` is the `THREE.Scene` to add geometry to.
  - `ctx.camera` is the `THREE.PerspectiveCamera` (renderer may
    inspect FOV / aspect for kind-specific behavior, but
    typically doesn't mutate it).
  - `ctx.modulators` (optional) is a getter `(name) => number | null`
    that resolves modulator values. When absent OR returns null,
    renderer uses the no-modulator fallback (default 1.0 multiplier).

Returns:
  - `update(now)` — call per RAF tick. Mutates scene-object
    state (positions, opacities, shader uniforms). Does NOT call
    `renderer.render()` — the caller (admin preview or future A7
    karaoke read-path) owns the render call.
  - `dispose()` — removes all added objects from the scene,
    disposes geometries + materials + (for D-twinkle) custom
    `ShaderMaterial`. Idempotent.

NO speculative `stop` method. The verb is `dispose` — matches the
source builder pattern at `karaoke/stage.html:2935-2938` +
`3030-3033` byte-for-byte. The caller's "Stop" UI action invokes
`dispose()` AND the per-canvas `renderer.dispose()` +
`renderer.forceContextLoss()` (D-webgl, §5.5).

§3.4 — Caller-owns-RAF (D-raf)
3D renderers do NOT own a RAF. The caller's render loop owns it,
and calls `update(now)` per frame before rendering. This matches
karaoke's pattern at `karaoke/stage.html:4012-4052` (`renderLoop`):

```js
// reference — current karaoke pattern
function renderLoop(){
  requestAnimationFrame(renderLoop);
  ...
  if(venueEffects3D) venueEffects3D.update();
  panRenderer.render(panScene, panCamera3);
}
```

A4b's admin preview surface (§5) follows the same pattern per
canvas. 2D renderers (A2/A3/A4a) keep their `{ stop }` + self-RAF
contract — the asymmetry is documented per D-contract.

§3.5 — Per-kind handlers in `spotlight-3d.js`

**`handleSweptBeam3d(anchor, ctx) → {update, dispose}`** —
Stadium swept-beam-3d.
- Constructs `count` cones: per-cone `THREE.CylinderGeometry`
  (parameters from payload.geometry) + `geo.translate(0,
  payload.geometry.translate_y, 0)` + per-cone `MeshBasicMaterial`
  (color from `payload.colors[i]`, opacity/side/depthWrite/transparent
  from `payload.material`). Each cone added to `ctx.scene` and
  tracked in private `objects[]`.
- Initial position: per-cone, on sphere of `payload.sphere_radius`
  at `(phi=payload.phis[i], theta=payload.theta_init[i])`.
- Initial orientation: `cone.lookAt(payload.look_at[0..2])`.
- Per-cone runtime state: `{angle: payload.theta_init[i], speed:
  payload.speeds[i]}`.
- Private `frame` counter starts at 0; increments in each `update()`.
- `update()` per cone:
  - `angle += speed`
  - `phi_active = payload.phis[i] + Math.sin(frame * payload.wobble_speed) * payload.wobble_amplitude`
  - Recompute position from `(payload.sphere_radius, phi_active, angle)`.
  - `cone.lookAt(payload.look_at[0..2])`.
- `dispose()`: for each cone, `ctx.scene.remove(cone)`,
  `cone.geometry.dispose()`, `cone.material.dispose()`. Clear
  `objects[]`.

**`handlePointLight(anchor, ctx) → {update, dispose}`** —
Speakeasy point-light.
- Constructs single `THREE.BufferGeometry` with `position`
  Float32Array (`count` × 3): per-vertex random `r ∈ payload.r_range`,
  `theta ∈ payload.theta_range`, `y ∈ payload.y_range` → cartesian.
- Single `THREE.PointsMaterial` from payload (color, size,
  sizeAttenuation, transparent, opacity=base_opacity, depthWrite).
- Single `THREE.Points` mesh added to `ctx.scene`.
- Private `frame` counter.
- `update()`: if `frame % payload.flicker.frame_period === 0`,
  set `material.opacity = randIn(opacity_min, opacity_max)`.
  ONE shared material — all 40 candles flicker in lockstep.
- `dispose()`: `ctx.scene.remove(points)`, `points.geometry.dispose()`,
  `points.material.dispose()`.

§3.6 — Per-kind handlers in `particle-3d.js`

**`handlePointCloud3d(anchor, ctx) → {update, dispose}`** —
Stadium phone-lights with D-twinkle.
- Constructs single `THREE.BufferGeometry`:
  - `position` Float32Array (`count` × 3): per-vertex random r ∈
    `payload.r_range`, phi ∈ `(payload.phi_norm_range × π)`, theta ∈
    `payload.theta_range`. Then `y = (Math.cos(phi) * payload.y_flatten_factor) + payload.y_offset` applied per-vertex (overwrites y from spherical conversion).
  - `phase` Float32Array (`count` × 1): per-vertex random in `[0, 2π]`
    when `payload.twinkle.phase_init === "random-2pi"`.
  - `geometry.setAttribute('phase', new THREE.BufferAttribute(phases, 1))`.
- ShaderMaterial per §3.7 (vertex shader + fragment shader spec'd
  there). Uniforms: `uColor`, `uBaseOpacity`, `uTime`, `uModulator`,
  `uAlphaCenter`, `uAlphaSwing`, `uSize`, `uSizeAttenuation`.
- Single `THREE.Points` added to `ctx.scene`.
- Private `frame` counter.
- `update(now)`:
  - `frame++`
  - `uniforms.uTime.value = frame * payload.twinkle.phase_omega_per_frame`
  - `uniforms.uModulator.value = resolveModulator(ctx, payload.modulator) ?? 1.0`
    (see §3.8 for the resolution logic).
- `dispose()`: `ctx.scene.remove(points)`, `points.geometry.dispose()`,
  `points.material.dispose()`.

**`handleVolumetric3d(anchor, ctx) → {update, dispose}`** —
Speakeasy 3D smoke.
- Constructs ONE shared `THREE.SphereGeometry` from
  `payload.sphere_geometry` (radius, widthSegments, heightSegments).
- For i in [0, count): builds per-mesh state:
  - scale = randIn(payload.scale_range)
  - per-mesh `MeshBasicMaterial` (color from payload.color, opacity
    = randIn(payload.opacity_range), transparent + depthWrite from
    payload).
  - `mesh = new THREE.Mesh(sharedGeo, mat)`
  - `mesh.scale.setScalar(scale)`
  - initial position from `spawn_region_initial`:
    `r = randIn(spawn_region_initial.r_range)`
    `phi = randIn(spawn_region_initial.phi_norm_range) * π`
    `theta = randIn(spawn_region_initial.theta_range)`
    position cartesian via standard spherical; `y = cos(phi) * payload.y_flatten_factor + payload.y_offset`
  - userData = `{vy: randIn(vy_range), vx: randIn(vx_range), vz:
    randIn(vz_range), life: randIn(life_init_range), maxOpacity:
    mat.opacity}`
- Track `objects[]` (each Mesh) + the shared `sharedGeo`.
- `update()` per mesh:
  - `position.y += userData.vy`; `position.x += userData.vx`;
    `position.z += userData.vz`.
  - `userData.life += payload.life_increment_per_frame`.
  - `t = userData.life % 1`; `material.opacity = userData.maxOpacity * Math.sin(t * Math.PI)`.
  - If `t > payload.respawn_threshold` AND `payload.respawn === true`:
    respawn position from `spawn_region_respawn` (NOT
    `spawn_region_initial` — note phi range divergence per §2.7);
    `userData.life = randIn([0, 0.1])`.
- `dispose()`: per mesh, `ctx.scene.remove(mesh)`,
  `mesh.material.dispose()` (NOT mesh.geometry — it's shared).
  Then `sharedGeo.dispose()` once.

§3.7 — The custom twinkle ShaderMaterial (D-twinkle)
The novel piece. r128 `THREE.PointsMaterial` cannot express
per-vertex opacity — its `opacity` is a single material-wide
scalar. Per-particle independent twinkle requires `THREE.ShaderMaterial`
with a custom vertex+fragment shader pair, plus a per-vertex
`phase` attribute on the BufferGeometry.

**Geometry attribute setup:**

```js
const phases = new Float32Array(count);
for (let i = 0; i < count; i++) phases[i] = Math.random() * Math.PI * 2;
geometry.setAttribute('phase', new THREE.BufferAttribute(phases, 1));
```

**Vertex shader (passes `phase` to fragment via varying, computes
gl_PointSize per the standard PointsMaterial sizeAttenuation
formula):**

```glsl
attribute float phase;
varying float vPhase;
uniform float uSize;
uniform float uSizeAttenuation;

void main() {
  vPhase = phase;
  vec4 mvPosition = modelViewMatrix * vec4(position, 1.0);
  gl_Position = projectionMatrix * mvPosition;
  // Standard r128 PointsMaterial sizeAttenuation formula
  gl_PointSize = uSize * (uSizeAttenuation > 0.5 ? (300.0 / -mvPosition.z) : 1.0);
}
```

**Fragment shader (modulates per-particle alpha via vPhase + time +
modulator):**

```glsl
varying float vPhase;
uniform vec3 uColor;
uniform float uBaseOpacity;
uniform float uTime;
uniform float uModulator;
uniform float uAlphaCenter;
uniform float uAlphaSwing;

void main() {
  float twinkle = uAlphaCenter + sin(vPhase + uTime) * uAlphaSwing;
  float alpha = uBaseOpacity * twinkle * uModulator;
  gl_FragColor = vec4(uColor, clamp(alpha, 0.0, 1.0));
}
```

**Uniforms object (passed to `THREE.ShaderMaterial({uniforms,
vertexShader, fragmentShader, transparent: true, depthWrite:
false})`):**

```js
{
  uColor:           { value: new THREE.Color(payload.color) },
  uBaseOpacity:     { value: payload.base_opacity },
  uTime:            { value: 0 },
  uModulator:       { value: 1.0 },
  uAlphaCenter:     { value: payload.twinkle.alpha_center },
  uAlphaSwing:      { value: payload.twinkle.alpha_swing },
  uSize:            { value: payload.sprite_size },
  uSizeAttenuation: { value: payload.size_attenuation ? 1.0 : 0.0 }
}
```

**r128 compatibility notes:**
- `THREE.ShaderMaterial` does NOT inherit standard PointsMaterial
  attributes — vertex shader must compute `gl_PointSize` explicitly.
- The `300.0 / -mvPosition.z` formula matches PointsMaterial's
  internal sizeAttenuation logic in r128.
- `material.transparent: true` and `depthWrite: false` must be
  set on the ShaderMaterial directly (uniforms can't set them).
- The custom `phase` attribute is named exactly `phase` (not
  `aPhase` etc.) — vertex shader's `attribute float phase`
  declaration must match.

§3.8 — Modulator value resolution (D-modulator)
The renderer's per-frame `update()` resolves the modulator value:

```
modulatorValue = ctx.modulators?.('crowd_brightness') ?? 1.0
```

- When `ctx.modulators` getter is absent (current state — A7's
  driver registry not built yet): `1.0`. Per-particle shader
  twinkle is the sole motion.
- When `ctx.modulators` is present and returns a number: use it.
  Per-particle twinkle multiplied by the driver value.
- When `ctx.modulators` is present but returns `null`/`undefined`:
  `1.0`. Same fallback as no-getter.

A7 ships the modulator driver registry. Before A7, the admin
preview's `ctx.modulators` may be set to a preview oscillator
(matching A3 particle.js's preview oscillator approach for the
modulator names A3 binds — `crowd_brightness`, `beat_scale`,
`beat_brightness`). Whether to include the oscillator in A4b is
implementation-cycle scope (small additive feature — see §12
build order).

═══════════════════════════════════════════════════════════════════════
§4 — REGISTRY DISPATCH
═══════════════════════════════════════════════════════════════════════

§4.1 — Distinct registry keys per (type, context) pair
The anchor registry is the type→impl map established in Phase 2
(`shell/venue-registry.js`). Each registered impl maps to a single
key string. Per Gate 5 decision (2026-05-28), A4b uses DISTINCT
KEYS to register the 3D renderer modules without colliding with
A2/A3/A4a's 2D registrations:

**Registry keys (final state after Gate 5):**
- `'audio'`        → A2's `audioAnchorRenderer` (unchanged)
- `'particle'`     → A3's `particleAnchorRenderer` (unchanged)
- `'spotlight'`    → A4a's `spotlightAnchorRenderer` (unchanged)
- `'spotlight-3d'` → A4b's `spotlightAnchor3dRenderer` [NEW]
- `'particle-3d'`  → A4b's `particleAnchor3dRenderer` [NEW]

**Registration pattern in each 3D module (at file scope, after
the SECTION dispatcher closes):**

```js
// In spotlight-3d.js
registerAnchorRenderer('spotlight-3d', spotlightAnchor3dRenderer);

// In particle-3d.js
registerAnchorRenderer('particle-3d', particleAnchor3dRenderer);
```

NO API change to `registerAnchorRenderer(type, impl)` or
`getAnchorRenderer(type)` — the current 2-arg / 1-arg signatures
at `shell/venue-registry.js:154` + `:205` stay intact. The 2D module
registrations (A2 `audio.js`, A3 `particle.js`, A4a `spotlight.js`)
stay byte-for-byte unchanged.

**A7 read-path lookup-key derivation (future consumer):**
The Stage A7 karaoke read-path will derive the registry lookup
key from the venue_anchors row:

```js
const lookupKey = anchor.payload.context === '3d-three'
  ? anchor.type + '-3d'
  : anchor.type;
const impl = getAnchorRenderer(lookupKey);
```

— using `anchor.type` (the venue_anchors COLUMN value set by
db/038's INSERT, e.g. `'spotlight'` / `'particle'`) NOT
`payload.type`. `payload.type` is undefined for spotlight/particle
payloads — verified pre-write 2026-05-28 against db/038's
payload jsonb (no `"type"` key inside). `payload.type` exists
only on audio payloads as a format discriminator (`'mp3'`), a
naming-collision artifact between two unrelated schema layers.

So a particle anchor with `payload.context = '3d-three'` routes to
the `'particle-3d'` registration; a 2d-canvas spotlight anchor
routes to `'spotlight'`; etc. The DB `type` column at
`public.venue_anchors` stays `'spotlight'` / `'particle'` —
db/032's `venue_anchors_type_check` vocabulary unchanged. The
`-3d` suffix is a renderer-registry-key derivation only, not a
schema-level type.

**Rationale (Gate 5 decision 2026-05-28 — revising the originally-
locked context-aware-extension):**

The spec's originally-locked approach (registerAnchorRenderer
gaining a `{context}` 3rd arg, getAnchorRenderer gaining a 2nd
arg, internal Map re-keyed by `(type, context)` composite) would
have required:

- Modifying `registerAnchorRenderer` signature at
  `shell/venue-registry.js:154`.
- Modifying `getAnchorRenderer` signature at line 205.
- Updating ALL renderer-module registration calls (audio.js,
  particle.js, spotlight.js, spotlight-3d.js, particle-3d.js) in
  lockstep.
- Updating every existing `getAnchorRenderer` call site to pass
  context.

But the actual call-site surface is small:
- Admin preview reads via `window.elsewhere.*Renderer` globals
  (NOT the registry) per §4.3.
- Only ONE future consumer reads the registry — the Stage A7
  karaoke read-path switch, which doesn't ship until A7.

So the spec-originally-locked approach was over-engineered for a
single future caller. The distinct-keys approach has zero impact
on the working A2/A3/A4a registrations and adds two 2-arg
registration calls — strictly smaller surface. See Gate 2
DEFERRED-d findings F1-F5 (2026-05-28) for the evidence chain.

§4.2 — Script tag enumeration: BOTH locations (DEFERRED-d lesson)
The A4a Check 19 finding (commit `0b2dec0`) caught that spec §4.7
specified `karaoke/stage.html`'s registration tag but not
`admin-venues.html`'s. The admin page also loads the renderer
modules so its preview path can access `window.elsewhere.*Renderer`.

A4b specifies BOTH locations explicitly:

**`karaoke/stage.html` additions (after existing renderer tags at
lines 15-17 of A4a-post state — verify by checking current head):**
```html
<script type="module" src="../shell/venue-renderers/spotlight-3d.js"></script>
<script type="module" src="../shell/venue-renderers/particle-3d.js"></script>
```

**`admin-venues.html` additions (after existing renderer tags at
lines 44-46 of A4a-post state):**
```html
<script type="module" src="shell/venue-renderers/spotlight-3d.js"></script>
<script type="module" src="shell/venue-renderers/particle-3d.js"></script>
```

Note path difference: `../shell/...` from karaoke/ (subdirectory)
vs `shell/...` from admin-venues.html (repo root). Match the A4a
pattern verbatim.

§4.3 — Module publication
Each 3D module publishes its entry on `window.elsewhere` for
console debugging access + admin panel preview lookup:

```js
// spotlight-3d.js (end of file)
if (typeof window !== 'undefined') {
  window.elsewhere = window.elsewhere || {};
  window.elsewhere.spotlight3dRenderer = { spotlightAnchor3dRenderer };
}

// particle-3d.js
if (typeof window !== 'undefined') {
  window.elsewhere = window.elsewhere || {};
  window.elsewhere.particle3dRenderer = { particleAnchor3dRenderer };
}
```

Admin panel preview accesses via
`window.elsewhere?.spotlight3dRenderer?.spotlightAnchor3dRenderer?.(anchor, ctx)`
etc. Matches A4a's pattern at admin-venues.html:2882.

**Two parallel access paths (today and future) — Gate 5 clarification:**

Each renderer module exposes its entry function through TWO
independent channels:

1. **Registry lookup** (consumer: Stage A7's karaoke read-path,
   not yet built): `getAnchorRenderer('spotlight-3d')` returns the
   `spotlightAnchor3dRenderer` entry function directly.

2. **Window global** (consumer: admin preview surface, today):
   `window.elsewhere.spotlight3dRenderer.spotlightAnchor3dRenderer`
   returns the same entry function via the publication object.

Both paths resolve to the same function reference. The registry
path is for downstream consumers that don't know the module's
JS-side identity (they only know the anchor's `(type, context)`
pair derived from the venue_anchors row); the window-global path
is for consumers that already know they want the 3D renderer
(e.g. the admin preview's per-row preview button knows it's a 3D
anchor and looks up
`window.elsewhere.spotlight3dRenderer.spotlightAnchor3dRenderer`
directly without traversing the registry).

The naming convention diverges slightly between channels —
**registry keys are kebab-case with `-3d` suffix**
(`'spotlight-3d'`, `'particle-3d'`); **window globals are
camelCase with `3dRenderer` suffix** (`spotlight3dRenderer`,
`particle3dRenderer`). Both conventions match their respective
ecosystems (registry stores string keys matching the DB-derived
(`anchor.type`, `anchor.payload.context`)-pair pattern per §4.1;
window globals match the JS-property camelCase convention).

═══════════════════════════════════════════════════════════════════════
§5 — THREE.JS ADMIN PREVIEW SURFACE
═══════════════════════════════════════════════════════════════════════

§5.1 — New architectural territory
`admin-venues.html` currently has ZERO Three.js code. A4b adds the
minimal scaffolding to host per-anchor 3D previews. ~60-80 LOC
estimate.

The preview surface must:
1. Load Three.js (CDN script tag added to `admin-venues.html` head).
2. Per preview canvas, lazy-construct `WebGLRenderer` + `Scene` +
   `PerspectiveCamera` + RAF loop.
3. Pass `{scene, camera, modulators?}` as `ctx` to the 3D renderer.
4. Call `renderer.update(now)` per RAF tick, then
   `webglRenderer.render(scene, camera)`.
5. Tear down WebGL contexts cleanly on every exit path (D-webgl).

§5.2 — Three.js CDN load
Add to `admin-venues.html` head (BEFORE the renderer module tags
in §4.2):

```html
<script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>
```

Same CDN as `karaoke/stage.html:621`. Global `window.THREE`. r128.

§5.3 — Per-canvas lazy WebGLRenderer + Scene + PerspectiveCamera
Each 3D preview canvas (one per spotlight-3d OR particle-3d
anchor row) gets its own WebGL context. Lazy construction
(materialize on first Preview click, NOT at row render time —
avoids needlessly creating contexts for never-previewed anchors).

Construction shape:

```js
function createPreviewContext3d(canvasEl, kind) {
  const renderer = new THREE.WebGLRenderer({
    canvas: canvasEl, antialias: true, alpha: true
  });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setSize(canvasEl.width, canvasEl.height, false);   // false: don't override canvas style
  const scene = new THREE.Scene();
  const aspect = canvasEl.width / canvasEl.height;
  const fov = previewFovForKind(kind);                         // see §5.4
  const camera = new THREE.PerspectiveCamera(fov, aspect, 0.1, 2000);
  positionCameraForKind(camera, kind);                          // see §5.4
  return { renderer, scene, camera };
}
```

§5.4 — Camera/FOV choice per kind
Each kind has a sensible default camera/FOV for the bounded admin
preview canvas:

| Kind | FOV | Camera position | look_at |
|------|-----|-----------------|---------|
| `swept-beam-3d` | 60° | (0, 200, 600) | (0, 0, 0) |
| `point-light` | 60° | (0, 50, 400) | (0, -80, 0) |
| `point-cloud-3d` | 80° | (0, 0, 0) | (0, 0, -1) |
| `volumetric-3d` | 60° | (0, 0, 250) | (0, -30, 0) |

These reproduce karaoke's panorama-from-center viewpoint (for
phone-lights, which surround the camera) OR an external observer
angle (for cones / candles / smoke, which are objects placed in
space around the origin).

`previewFovForKind` and `positionCameraForKind` are lookup
helpers. Implementation cycle finalizes the exact values via
visual inspection of each preview; the table above is the starting
point.

§5.5 — RAF loop ownership (admin owns it)
Admin preview owns the RAF, calls `renderer.update(now)` then
`webglRenderer.render(scene, camera)`. State tracked per anchor:

```js
state.spotlight3dPreviewState = new Map();
// anchorId -> { webglRenderer, scene, camera, rendererHandle, rafId, disposed }
//
// rendererHandle is the { update, dispose } from the 3D renderer.
// rafId is the cancel handle from requestAnimationFrame.
// disposed is the frame-guard flag flipped by tearDownPreview3d (§5.6).
//   Initialized to false on context creation; set true as step 0 of teardown.
```

State management parallel for `particle3dPreviewState`. Both new
Map instances on `state` per A4a's pattern for 2D preview state.

**RAF callback pattern (with frame-guard):**

```js
function tickPreview3d(anchorId, stateMap) {
  const st = stateMap.get(anchorId);
  // Frame-guard: cancelAnimationFrame does NOT cancel an in-flight
  // frame already dispatched by the browser. If teardown ran between
  // the schedule and the fire, this callback fires anyway. Without
  // this guard, the next two calls would render against a WebGL
  // context that loseContext() killed in §5.6 step 4 — producing
  // intermittent INVALID_OPERATION console errors.
  if (!st || st.disposed) return;
  try {
    st.rendererHandle.update(performance.now());
    st.webglRenderer.render(st.scene, st.camera);
  } catch (e) {
    console.warn('preview3d tick error:', e);
  }
  st.rafId = requestAnimationFrame(() => tickPreview3d(anchorId, stateMap));
}
```

The renderer's `update()` is ALSO guarded by an internal disposed
flag flipped by its own `dispose()` (defensive second layer; see
§5.6 step 2 note). Two guard layers — the admin's `st.disposed`
gates the render-path; the renderer's internal flag gates the
update-path. Either flip alone suffices to make the in-flight
frame a safe no-op; both flip during teardown.

§5.6 — Teardown contract (D-webgl): exit path enumeration
WebGL contexts MUST be released on EVERY exit path. The browser
caps active contexts ≈ 16; orphaned contexts trigger eviction of
older ones (potentially the user's current preview).

**Every exit path:** call this sequence:

```js
function tearDownPreview3d(anchorId, stateMap) {
  const st = stateMap.get(anchorId);
  if (!st) return;
  // 0. Set disposed flag FIRST. cancelAnimationFrame() does NOT
  //    cancel an already-dispatched in-flight frame; the next
  //    tickPreview3d may still fire with st in-hand. Both the
  //    admin RAF callback (§5.5) and the renderer's update() (its
  //    own internal guard set in step 2) check this flag and
  //    early-return. Without step 0, an in-flight frame between
  //    step 1 and step 4 will call render() on a context that
  //    loseContext() just killed → INVALID_OPERATION in console.
  st.disposed = true;
  // 1. Cancel RAF (stop scheduling FUTURE frames; does NOT stop an
  //    in-flight frame — that's what step 0's flag is for)
  if (st.rafId != null) cancelAnimationFrame(st.rafId);
  // 2. Dispose renderer's scene contents (geometries + materials).
  //    The renderer's dispose() flips its own internal disposed
  //    state so any later update() call (e.g. from an in-flight
  //    frame that slipped past step 0) is a no-op.
  try { st.rendererHandle?.dispose?.(); } catch (_) {}
  // 3. Dispose THREE.WebGLRenderer (releases GPU-side resources)
  try { st.webglRenderer?.dispose?.(); } catch (_) {}
  // 4. Force WebGL context loss (frees the context slot in the
  //    browser's bounded pool — ~16 contexts max)
  try {
    const gl = st.webglRenderer?.getContext?.();
    const ext = gl?.getExtension?.('WEBGL_lose_context');
    if (ext) ext.loseContext();
  } catch (_) {}
  stateMap.delete(anchorId);
  // Restore UI (Preview visible, Replay/Stop hidden) per §7
  ...
}
```

**Frame-guard summary:**

| Where | Guard | Set by |
|---|---|---|
| Admin RAF callback (§5.5 `tickPreview3d`) | `if (!st || st.disposed) return;` | `tearDownPreview3d` step 0 |
| Renderer's `update()` (internal) | `if (this._disposed) return;` (or closure equivalent) | Renderer's own `dispose()` (called by §5.6 step 2) |

Either guard alone makes the in-flight frame safe. Both flip
during teardown — defense in depth, mirroring D-webgl's "every
exit path" rigor.

**Exit paths that must invoke teardown:**
1. User clicks per-row Stop button (new in A4b, §7).
2. User clicks per-row Replay button (stop → re-init).
3. User navigates to a different venue (`venueHasAnyDirty`
   discard path + venue-selection trigger).
4. User clicks panel "Stop all previews" button.
5. Row is deleted (anchor save → reload → row replaced).
6. `beforeunload` (page navigation away).
7. Kind switch in the row's kind selector (multi-anchor panel
   per §6 may show a kind dropdown that switches between
   `swept-beam-3d` ↔ `point-light` etc.).

**Verification:** Check 28 (3D-anchor cluster) exercises the
teardown path explicitly via `WEBGL_lose_context` extension and
context-count audit.

═══════════════════════════════════════════════════════════════════════
§6 — MULTI-ANCHOR PANEL (D-multianchor)
═══════════════════════════════════════════════════════════════════════

§6.1 — From single-editor-swap-kind to anchor-list
A4a's spotlight panel renders a single editor at a time per anchor,
with a kind selector that re-renders the row on kind change
(DEFERRED-e: re-render discards other-kind edits; A3 particle
panel uses hide/show via `[data-kind-section]` — exact mechanism
cited in §6.7). For A4b, the structure changes in two parts:

**Anchor-list structure (replaces single-editor pattern):** the
spotlight + particle panels render N rows (N = saved + pending
anchor count for selected venue), each its own self-contained
editor block. Each row holds the kind label (read-only for saved
rows, mutable via selector for pending rows), the field section,
the preview canvas, and the canonical action row (§7).

**Kind-switch policy (D-multianchor refinement):**

- **PENDING (unsaved) anchors:** kind selector is visible and
  interactive. Switching kind preserves field state via the A3
  hide/show pattern: ALL kind sections are emitted in the DOM
  concurrently, each as
  `<div class="<type>-kind-section" data-kind-section="<kindname>"
  ${kind === '<kindname>' ? '' : ' hidden'}>`. The kind-input
  handler toggles the `hidden` attribute on non-matching sections.
  No re-render, no innerHTML replacement, no state discard. Exact
  citation in §6.7. This is the canonical A3 pattern at
  `admin-venues.html:1903 + 1938 + 1960` (emit side) +
  `admin-venues.html:2033, 2043-2046` (toggle side). Properly
  closes DEFERRED-e by IMPLEMENTATION: switching kind during
  active authoring (e.g. "let me compare swept-beam-2d vs
  swept-beam-3d before committing") preserves entered field
  values across toggles.

- **SAVED anchors:** kind is stable / read-only. The saved row
  shows the kind as a text label (no selector). To "change kind"
  on an existing saved anchor: user clicks "+ Add anchor", picks
  the desired kind, edits, Saves; then deletes the old anchor.
  Natural multi-anchor model — no kind-mutation on persisted
  rows; no implicit-rewrite semantics. Matches D-multianchor "no
  decorative extras" posture (§6.6) — kind-edit-in-place would
  be a hidden destroy + recreate masquerading as an update.

For NEW anchors (clicked "+ Add"), the kind picker appears as
the first interaction — inline dropdown or fresh pending row
stub with kind selector. User picks a kind; the pending row
instantiates with the kind's default payload via
`defaultSpotlightPayloadForKind(kind)` (existing A4a function,
extended to know A4b kinds) or `defaultParticlePayloadForKind(kind)`
(existing A3 function, extended similarly). The kind selector
remains interactive — switching kinds uses the §6.7 hide/show
mechanism — until Save converts the row to "saved" state (at
which point the kind locks).

§6.2 — Per-anchor editor block shape
Each row contains:
- Header strip: id (mono, faint), kind label (read-only), pending
  badge if applicable, dirty dot.
- Field section: kind-discriminated form, same shape per kind as
  A4a's `renderSpotlightKindSection`.
- Preview canvas (per the kind's context — 2D for A4a kinds, 3D
  for A4b kinds).
- Action row (canonical per §7): Play preview / Replay / Stop /
  Save / Cancel-or-Delete.
- Status div.

§6.3 — Add-anchor-with-kind-picker
"+ Add spotlight anchor" button at panel header. On click:
- Inline kind dropdown materializes at the panel top OR inside a
  fresh pending row stub:
  - Kinds available: `swept-beam-2d`, `pulsed-laser`,
    `light-shaft`, `swept-beam-3d`, `point-light` (all 5
    A4a+A4b spotlight kinds).
  - For particle panel: `point-cloud`, `directional-emitter`,
    `volumetric`, `point-cloud-3d`, `volumetric-3d` (all 5
    A3+A4b particle kinds).
- User picks kind → pending row materializes with
  `defaultSpotlightPayloadForKind(kind)` (existing A4a function,
  extended to know A4b kinds) or `defaultParticlePayloadForKind(kind)`
  (existing A3 function, extended similarly).
- Pending row enters dirty state automatically (Save/Cancel enabled).

§6.4 — Per-anchor save/delete

**Per-row Save (both pending + saved rows):** calls
`rpc_venue_anchor_upsert` with the EXACT 3-arg signature verified
in A4a Check 21 (DEFERRED-d, db/035:72-76):

```js
await window.sb.rpc('rpc_venue_anchor_upsert', {
  p_id: anchorId, p_venue_id: venueId, p_partial: partial
});
```

Where `partial = { type, payload, label }` per A3's
`onParticleAnchorSave` at `admin-venues.html:2137`. For pending
rows, `anchorId` is the panel-generated UUID (`anc_<uuid>` per A3's
pattern, A4a adopted at line 1959 + 2842); the RPC's INSERT branch
fires (existence check returns no row → INSERT). For saved rows,
the UPDATE branch fires (key-exists semantics preserve absent
columns). The 3-arg `p_partial` jsonb pattern was the load-bearing
A4a fix at commit `2056a72`; A4b carries it forward.

**Per-row Delete (SAVED rows):** four-step canonical sequence,
adapted from A4a's `onSpotlightAnchorDelete` at
`admin-venues.html:2816-2842` (the more thorough of the A3/A4a
delete patterns — splits pending vs saved explicitly):

1. **Confirm dialog** — use A3's kind-aware format from
   `onParticleAnchorDelete` at `admin-venues.html:2175`:
   `'Delete {type} anchor (kind: {kindLabel}) for {venueId}?'`
   where `kindLabel = anchor?.payload?.kind || anchorId` and
   `{type}` is the panel's anchor type (audio / particle /
   spotlight). Disambiguates multi-anchor venues — speakeasy's
   light-shaft vs candles confirm dialogs identify which is being
   deleted. (A4a's bare `'Delete this spotlight anchor?'` at line
   2821 is the under-specified variant the canonical pattern
   replaces.)
2. **Stop the preview** — for 2D anchors (A4a kinds, A3 kinds,
   A2 audio): call the existing `stop<Type>Preview(anchorId)`
   (e.g. `stopSpotlightPreview` at A4a's line 2823). For A4b 3D
   anchors: invoke the FULL §5.6 `tearDownPreview3d(anchorId,
   stateMap)` sequence — set `disposed = true`, cancel RAF,
   dispose renderer handle, dispose `WebGLRenderer`, force
   context loss via `WEBGL_lose_context`. Load-bearing per D-webgl
   — WebGL contexts MUST release before the row is removed; row
   removal does not implicitly trigger context loss.
3. **Call the RPC** — `rpc_venue_anchor_delete` from db/035:213-215
   (the `(p_id text)` SECURITY DEFINER function, anon-revoked +
   authenticated-granted at db/035:250-252):
   ```js
   const { error } = await window.sb.rpc('rpc_venue_anchor_delete', {
     p_id: anchorId
   });
   ```
   On error: show inline status via `showAnchorStatus(anchorId,
   'Delete failed' + code + ': ' + message, 'error')` per A3's
   pattern at line 2187; do NOT update local cache (the server
   row still exists). On success: proceed to step 4.
4. **Update cache + reload** — remove from
   `state.<type>Anchors.get(venueId)`, clear
   `state.<type>AnchorDirty.delete(anchorId)`, then call
   `loadAndRender<Type>Panel(venueId)` to re-render from the
   updated server state. Mirrors A3's update path at
   `admin-venues.html:2181-2184`.

**Per-row Delete (PENDING rows):** NO server call. The pending
anchor has never been INSERTed into prod; calling the RPC would
fail with `P0002 no_data_found` per db/035's error vocabulary
(see RPC header at db/035:35-36). Pending Delete discards locally:

```js
stop<Type>Preview(anchorId);           // 2D stop OR §5.6 3D teardown
state.<type>AnchorNew.delete(anchorId);
state.<type>AnchorDirty.delete(anchorId);
await loadAndRender<Type>Panel(venueId);
```

No confirm dialog for pending Delete — the row was never
persisted; discarding is the expected interpretation of "Delete"
on something that doesn't exist server-side. Matches A4a's
`onSpotlightAnchorDelete` pending branch at
`admin-venues.html:2820-2831`.

**Per-row Cancel (pending rows only — the canonical
isPending-conditional button per §7):** same discard path as
pending Delete. Cancel is the conventional verb for "I don't want
this pending row"; Delete is conventionally for saved rows. The
canonical anchor-row markup renders either Cancel (pending) or
Delete (saved), never both — they route to the same discard path
for pending rows.

**Step ordering rationale (all panels):**

| Order | Step | Why |
|---|---|---|
| 1 | Confirm | User intent gate; reversible if user cancels |
| 2 | Stop preview / 3D teardown | Release resources BEFORE row removal — prevents orphan RAF / WebGL context if step 3 errors |
| 3 | RPC call | Network round-trip; can fail |
| 4 | Cache + re-render | Only on RPC success; sync local state to server truth |

For pending rows: steps 1+3 skip (no confirm, no RPC); steps 2+4
run as local-discard.

§6.5 — State management for N anchors per venue
A4a's state shape already supports multi-anchor (Set for dirty,
Map for pending-new, Map for saved-cache, Map for preview state).
A4b extends:

```js
// In state init block (currently lines ~812-820 of A4a-post)
state.spotlight3dPreviewState = new Map();  // anchorId -> 3D preview state per §5.5
state.particle3dPreviewState  = new Map();  // anchorId -> 3D preview state per §5.5
```

The existing `state.spotlightAnchors` Map (saved-anchor cache,
added in A4a) and `state.spotlightAnchorDirty` Set continue to
work — they index by anchorId; multi-anchor is just multiple
entries.

§6.6 — What's NOT in scope
Per D-multianchor "no decorative extras":
- NO drag-to-reorder anchors within a venue.
- NO inline rename of anchor ids (id is set at create-time via
  the panel-generated UUID, then either kept or restored to a
  seed id via SQL UPDATE per the A2/A3/A4a precedents).
- NO "duplicate anchor" button.
- NO bulk-delete / bulk-save across anchors.

Each of those is independently small but adds UI surface that
isn't on the functional floor. File as DEFERRED if needed; do
not ship in A4b.

§6.7 — Closes DEFERRED-e (kind-switch UX divergence) by IMPLEMENTATION

The A4a closeout filed DEFERRED-e about A4a's re-render-on-kind-
switch losing other-kind edits. A4b closes it BY IMPLEMENTATION —
adopt A3's hide/show mechanism for pending-row kind switches (per
§6.1) — rather than BY REMOVAL (the previous spec draft's "delete
+ recreate for ALL anchors" answer would have closed DEFERRED-e by
foreclosing the operation, unfriendly during active authoring).

The hide/show pattern only governs the PENDING phase, when the
kind is still mutable. The "natural multi-anchor model" for
changing a SAVED anchor's kind (per §6.1: add new anchor with
desired kind, then delete the old anchor) remains the answer for
persisted rows. Two different operations: pending-kind-switch is
field-state-preserving via DOM toggle; saved-kind-change is
create-new-then-delete-old.

**A3's hide/show mechanism — to mirror by exact name:**

- **Emit side** (`renderParticleAnchorRowHTML` at
  `admin-venues.html:1847`, with section markers at lines 1903,
  1938, 1960): each kind section is emitted as
  `<div class="particle-kind-section" data-kind-section="<kindname>"${kind === '<kindname>' ? '' : ' hidden'}>`.
  All three kind sections (`point-cloud`, `directional-emitter`,
  `volumetric`) present in the DOM concurrently; non-current ones
  carry the `hidden` HTML attribute inline at render time. The
  position-layout sub-swap inside `point-cloud` uses the same
  pattern with `data-pl-section="<layout>"` at `admin-venues.html:1912`
  (cartesian) + `:1922` (polar-projected).

- **Toggle side** (`onParticleAnchorFieldInput` at
  `admin-venues.html:2033`, kind branch at lines 2043-2046):

  ```js
  if (field === 'kind') {
    row.querySelectorAll('[data-kind-section]').forEach(s => {
      s.hidden = (s.dataset.kindSection !== event.target.value);
    });
  }
  ```

  No re-render, no innerHTML replacement, no state discard. The
  DOM stays stable; only `.hidden` flips. Each input inside the
  hidden sections retains its `.value` across toggles — that's
  the field-state preservation.

**A4b applies this pattern to:**

- **Spotlight panel pending-row kind switch (5 kinds):**
  `swept-beam-2d`, `pulsed-laser`, `light-shaft`, `swept-beam-3d`,
  `point-light`. Each kind's field section emitted as
  `<div class="spotlight-kind-section" data-kind-section="<kindname>"${kind === '<kindname>' ? '' : ' hidden'}>` — class prefix
  matches the existing A4a `.spotlight-kind-section` CSS at
  `admin-venues.html` (already declared from A4a's stylesheet
  block). For the 3D kinds, the preview canvas inside the kind
  section is a `<canvas>` element ready for the §5 WebGL
  scaffolding; hidden sections do not instantiate WebGL contexts
  (the §5.3 lazy-construction posture defers context creation to
  Preview click, well after kind selection).

- **Particle panel pending-row kind switch (5 kinds):**
  `point-cloud`, `directional-emitter`, `volumetric`,
  `point-cloud-3d`, `volumetric-3d`. Already canonical from A3 —
  just extends the existing `[data-kind-section]` toggle to cover
  the two new 3D kinds. The position_layout sub-section pattern
  is unchanged from A3 — no A4b particle kind introduces a sub-
  layout switch; the existing `[data-pl-section]` mechanism
  continues to work for A3's `point-cloud` kind only.

- **Spotlight panel field-input handler** (replaces A4a's
  re-render path at admin-venues.html:onSpotlightAnchorFieldInput
  kind branch): switch from re-render to the A3 hide/show toggle.
  Cite the A3 toggle code verbatim (lines 2043-2046) — same
  selector, same `.hidden` flip.

DEFERRED-e was filed with priority "Low — UX-only divergence;
functional behavior is correct" in the A4a closeout. A4b's
implementation moves it from "deferred" to "resolved by canonical-
pattern adoption" — DEFERRED-d discipline applied to a UX
question: the canonical A3 pattern is the answer; specify by
exact mechanism + line citation, not by re-description.

═══════════════════════════════════════════════════════════════════════
§7 — PANEL STANDARDIZATION PASS (D-standardize)
═══════════════════════════════════════════════════════════════════════

§7.1 — Apply the canonical pattern to all three panels
The pre-spec investigation (2026-05-28) pulled the A3 canonical
pattern by exact name. A4b applies it to all three panels (audio,
particle, spotlight) for visual + structural consistency.

Canonical per-row markup (A3 particle template, extended with
per-row Stop per D-standardize):

```html
<div class="anchor-row-actions">
  <button type="button" class="btn-play-{type}-preview">▶ Play preview</button>
  <button type="button" class="btn-replay-{type}-preview" hidden>↻ Replay</button>
  <button type="button" class="btn-stop-{type}-preview"   hidden>⏹ Stop</button>
  <button type="button" class="btn-anchor-save">Save</button>
  ${isPending
    ? '<button type="button" class="btn-anchor-cancel">Cancel</button>'
    : '<button type="button" class="btn-anchor-delete">Delete</button>'}
</div>
<div class="anchor-status" data-status></div>
```

Where `{type}` ∈ {audio, particle, spotlight} (and there may be a
4th token for 3D vs 2D within particle/spotlight panels — see
§7.4).

**Exact tokens:**
- Container class: `anchor-row-actions` (NOT `anchor-row-controls`)
- Preview label: `▶ Play preview` (NOT `▶ Preview`)
- Replay glyph: **U+21BB** `↻` (NOT U+27F3 `⟳`)
- Stop glyph: **U+23F9** `⏹`
- Status div: `<div class="anchor-status" data-status></div>`
  (vestigial `data-status` attribute included for shape-match with
  A2/A3, per D-datastatus)
- Cancel/Delete: render ONE based on `isPending`, never both
- Stop-all button ID: `btn-stop-{type}-preview` (rename
  A4a's `btn-stop-all-spotlight-previews` → `btn-stop-spotlight-preview`)

§7.2 — Per-row Stop state machine (NEW standard, all 3 panels)
- Idle: Preview visible; Replay + Stop hidden.
- Playing: Preview hidden; Replay + Stop visible.
- Click Replay: invoke stop → invoke play; stays Playing.
- Click Stop: invoke stop; → Idle.
- For 3D anchors (point-cloud-3d, volumetric-3d, swept-beam-3d,
  point-light): Stop MUST trigger the full WebGL teardown per
  §5.6 (D-webgl). NOT just `cancelAnimationFrame` + DOM-state
  toggle — the per-canvas WebGLRenderer + context must release.

§7.3 — The 5 A4a divergences to KILL
In A4a's `renderSpotlightAnchorRowHTML` (admin-venues.html
lines 2430-2437 at `21991e8`):

| # | A4a divergence | Canonical |
|---|---|---|
| ① | `<div class="anchor-row-controls">` | `<div class="anchor-row-actions">` |
| ② | `▶ Preview` | `▶ Play preview` |
| ③ | `⟳ Replay` (U+27F3) | `↻ Replay` (U+21BB) |
| ④ | `<div class="anchor-status"></div>` | `<div class="anchor-status" data-status></div>` |
| ⑤ | Cancel + Delete BOTH rendered | One via `isPending` conditional |

All 5 fixed in the §7.4 per-panel edit enumeration below.

§7.4 — Per-panel edit enumeration

**Audio panel (admin-venues.html lines 1578-1590 area):**
- Already canonical for ①②④⑤ ✓ (audio shipped pre-A3 with the
  canonical pattern).
- Add per-row Stop button (NEW): `<button type="button" class="btn-stop-audio-preview" hidden>⏹ Stop</button>` between Replay (NOT present in audio — audio is one-shot playback) and Save. **Audio has no Replay button** because audio is single-shot playback; A4b's standardization keeps audio's existing button row plus the new Stop. Stop button hidden by default; visible when audio is actively playing.
- `btn-stop-preview` panel-header button ID: rename to
  `btn-stop-audio-preview` for the per-type-prefix convention.
- Add `stopAudioPreview(anchorId)` per-row function +
  `onStopAudioPreview(rowEl)` handler + wireHandlers click delegate.
- Existing `onPlayPreview` flow: on play, show Stop button; on
  audio-end callback, hide Stop button.

**Particle panel (admin-venues.html lines 2020-2028 area):**
- Already canonical for ①②③④⑤ ✓ (particle is the SOURCE of the
  canonical pattern).
- Add per-row Stop button: `<button type="button" class="btn-stop-particle-preview" hidden>⏹ Stop</button>` between Replay and Save.
- Panel-header `btn-stop-particle-preview` button ID: already
  matches the per-row class name — minor collision risk; the
  per-row class is `.btn-stop-particle-preview` (class) and the
  panel-header id is `btn-stop-particle-preview` (id). Different
  attribute namespaces in HTML/CSS but read carefully in event
  delegation. The wireHandlers click delegate must distinguish:
  delegate on `.anchor-row` first; if matched, treat as per-row
  Stop; otherwise the panel-header click handler fires.
- Add `stopParticlePreview(anchorId)` per-row handler (already
  exists for the Replay path — re-use; just wire to the new Stop
  button click).

**Spotlight panel (admin-venues.html lines 2430-2437 area):**
- Fix all 5 divergences per §7.3.
- Add per-row Stop button.
- Rename panel-header `btn-stop-all-spotlight-previews` → `btn-stop-spotlight-preview` (drop "all" + "previews" plural for the per-type-prefix convention).
- Per-row Stop wiring + multi-anchor restructure per §6.

§7.5 — CSS additions
The canonical `.anchor-row-actions` CSS at lines 401-415 already
covers `.btn-anchor-save` (gold), `.btn-anchor-delete` (red), and
`disabled` state (opacity .4). No changes needed to existing
rules.

Add for the per-row Stop button styling consistency:

```css
.btn-anchor-save,
.btn-anchor-cancel,
.btn-anchor-delete,
.btn-play-audio-preview,    .btn-stop-audio-preview,
.btn-play-particle-preview, .btn-replay-particle-preview, .btn-stop-particle-preview,
.btn-play-spotlight-preview, .btn-replay-spotlight-preview, .btn-stop-spotlight-preview {
  /* Inherit base button styling from .anchor-row-actions button (line 404) */
}
```

The selector above is NOT a new rule but a NOTE that all the new
button classes inherit via the `.anchor-row-actions button` base.
Adding them to the explicit selector list is optional — current
`.anchor-row-actions button` rule already targets descendants.
No CSS edit required beyond verification.

§7.6 — Verification (deferred to §9 cluster 2)
Panel-standardization checks are in a separate verification cluster
(§9.2) to contain A2/A3 regression risk. Specifically:
- A2 audio round-trip still works (Check 33).
- A3 particle round-trip still works (Check 34).
- A4a spotlight light-shaft round-trip still works through the
  new multi-anchor list (Check 35).
- Per-row Stop functions correctly on all 3 panels (Check 36).

═══════════════════════════════════════════════════════════════════════
§8 — db/038 — THE 3D ANCHOR SEED MIGRATION
═══════════════════════════════════════════════════════════════════════

§8.1 — No new RPCs
db/035's `rpc_venue_anchor_upsert` and `rpc_venue_anchor_delete`
are type-agnostic. db/032's `venue_anchors_type_check` permits
`spotlight` + `particle`. NO schema change. db/038 is SEED-ONLY.

§8.2 — Migration content
`db/038_3d_anchor_seed.sql` — one transactional file:
- 4 INSERT rows into `public.venue_anchors`, types `spotlight` (2)
  + `particle` (2), with the deterministic ids per §1.4 (D-naming):
  - `anc_spot_stadium_beams3d` (swept-beam-3d, count:4)
  - `anc_spot_speakeasy_candles` (point-light, count:40)
  - `anc_par_stadium_phonelights3d` (point-cloud-3d, count:2000)
  - `anc_par_speakeasy_smoke3d` (volumetric-3d, count:60)
- Each row's `payload` jsonb is the §2 schema verbatim. Labels:
  - swept-beam-3d → 'Spotlights (3D)'
  - point-light → 'Spotlights (3D)'
  - point-cloud-3d → 'Particles (3D)'
  - volumetric-3d → 'Particles (3D)'
- `ON CONFLICT (id) DO NOTHING` for idempotency.
- Position consistency: all 3D anchors have `yaw_deg` = NULL and
  `pitch_deg` = NULL (3D anchors live in panScene world space; no
  screen-space yaw/pitch). Same posture as A2/A3/A4a's 2D-canvas
  anchors. Satisfies db/032's paired-NULL CHECK.

§8.3 — Verification footer
db/038 carries a verification-query footer (db/034/035/036/037
pattern):
- **Q1** — `select count(*) from public.venue_anchors where (payload->>'context') = '3d-three'` returns `count_3d = 4`.
- **Q2** — per-anchor `id / venue_id / type / payload->>'kind' / label` ordered by id:
  - `anc_par_speakeasy_smoke3d / speakeasy / particle / volumetric-3d / Particles (3D)`
  - `anc_par_stadium_phonelights3d / stadium / particle / point-cloud-3d / Particles (3D)`
  - `anc_spot_speakeasy_candles / speakeasy / spotlight / point-light / Spotlights (3D)`
  - `anc_spot_stadium_beams3d / stadium / spotlight / swept-beam-3d / Spotlights (3D)`
- **Q3** — payload schema spot-check via case-by-kind expression
  pattern from A4a Check 20 (split into 4 sub-queries to avoid the
  Supabase SQL Editor `limit 100` auto-append injecting inside
  CASE strings — A4a Check 20 verification-mechanics note):
  - swept-beam-3d: phis_len=4, colors_len=4, speeds_len=4
  - point-light: count=40, flicker.frame_period present
  - point-cloud-3d: count=2000, twinkle.mode=per-particle-shader, modulator.name=crowd_brightness
  - volumetric-3d: count=60, respawn=true, spawn_region_initial+respawn both present

§8.4 — Migrations tracker
db/038 recorded in `db/MIGRATIONS_APPLIED.md` AFTER prod apply,
per doctrine. The tracker is ordered by apply-date — record the
actual append position. The migration's apply-cycle gate is human-
side (user runs in Supabase SQL Editor); Claude Code never applies
to prod.

═══════════════════════════════════════════════════════════════════════
§9 — VERIFICATION PLAN
═══════════════════════════════════════════════════════════════════════

Per D-standardize, verification splits into TWO clusters. Run
**Cluster 1 (3D-anchor checks)** first; on PASS, run **Cluster 2
(panel-standardization checks)** which contains the A2/A3
regression risk. Both clusters must PASS before closeout commit.

Numbered Checks 25-36, continuing from A4a's 19-24.

§9.1 — Cluster 1: 3D-anchor checks (Checks 25-30)

**Check 25 — 3D renderers registered**

Load `karaoke/stage.html` (any venue). Browser console:

```
> window.elsewhere.anchorRegistry.getAnchorRenderer('spotlight', {context: '3d-three'})
< ƒ spotlightAnchor3dRenderer(anchor, ctx)

> window.elsewhere.anchorRegistry.getAnchorRenderer('particle', {context: '3d-three'})
< ƒ particleAnchor3dRenderer(anchor, ctx)
```

Also sanity-check `window.elsewhere.spotlight3dRenderer.spotlightAnchor3dRenderer`
+ `window.elsewhere.particle3dRenderer.particleAnchor3dRenderer` resolve to functions.

**Check 26 — Seed verification**

Re-run db/038's footer queries Q1-Q3 against prod. All 3 PASS
expected values per §8.3. Run on Supabase SQL Editor; split Q3
into 4 sub-queries per the A4a Check 20 verification-mechanics
note.

**Check 27 — Per-kind admin preview (all 4 kinds render)**

Load `admin-venues.html` as platform admin. For each of the 4 in-
scope venues (stadium, speakeasy), navigate to the spotlight or
particle panel that hosts the 3D anchor:
- **stadium spotlight panel** — confirm `anc_spot_stadium_beams3d`
  row appears alongside the A4a-shipped `anc_spot_stadium`
  (light-shaft) — multi-anchor list shows both. Click Preview on
  beams3d row: bounded 3D canvas shows 4 cones rotating in counter-
  pairs with phi wobble.
- **stadium particle panel** — `anc_par_stadium_phonelights3d`
  row appears alongside `anc_par_stadium` (2D phone-lights). Preview
  shows 2000 white points scattered on hemisphere with **independent
  per-particle twinkle** (each particle visibly fades at its own
  phase — confirms D-twinkle shader is working).
- **speakeasy spotlight panel** — both `anc_spot_speakeasy`
  (light-shaft) and `anc_spot_speakeasy_candles` (point-light)
  appear. Preview candles: 40 amber Points at table-height ring,
  global-sync flicker every 4 frames.
- **speakeasy particle panel** — `anc_par_speakeasy_smoke3d`
  alongside `anc_par_speakeasy` (2D smoke). Preview shows 60 grey
  sphere meshes drifting upward, fading in/out per life cycle,
  respawning continuously (respawn:true).

All 4 previews must render visually plausibly within ~5 seconds of
Preview click. WebGL errors in console = fail.

**Check 28 — WebGL teardown (D-webgl verification)**

The teardown contract is the hardest-to-verify A4b deliverable.
Test method:

1. Open `admin-venues.html`. Open DevTools → Console.
2. Run: `let getCtxCount = () => Array.from(document.querySelectorAll('canvas')).filter(c => { try { return c.getContext('webgl') !== null; } catch (_) { return false; } }).length`
3. Navigate to stadium; click Preview on `anc_spot_stadium_beams3d`. Verify `getCtxCount()` returns 1 (new context).
4. Click per-row Stop button. Verify `getCtxCount()` returns 0 (context released via `forceContextLoss`).
5. Repeat steps 3-4 for each of the 4 3D anchor types.
6. Click Preview on `anc_spot_stadium_beams3d`, then click Replay; verify `getCtxCount()` stays at 1 (Replay = stop + restart, net 1 context).
7. Click Preview on `anc_spot_stadium_beams3d`; switch venue to speakeasy without clicking Stop. Verify `getCtxCount()` returns 0 (venue-switch triggered teardown).
8. Open Preview on 3 different 3D anchors simultaneously across two venues. Verify `getCtxCount() <= 3`. No leak.

PASS condition: all 8 steps verify; context count never grows
beyond the count of actively-previewed anchors; navigate-away
releases all.

**Check 29 — RPC authority gate**

Same posture as A4a Check 23. Fire `rpc_venue_anchor_upsert` from
signed-in non-admin browser with a 3D spotlight payload. Expect
HTTP 403 / code 42501. Test method: sign in as non-admin FIRST
(401 means signed-out, different gate).

**Check 30 — D8 dormancy + karaoke read-path unchanged**

Load `karaoke/stage.html` on stadium AND speakeasy. Confirm:
- Stadium: 4 GSAP-swept 2D beams + 400 2D phone-lights + 4 3D
  cone meshes (from `buildStadiumEffects3D`) + 2000 3D `Points`
  phone-lights — all rendered via the procedural AMBIENT_PROFILES
  + addVenueEffects3D paths. NOT via the registered renderers.
- Speakeasy: 3 GSAP-drifted 2D shafts + 35 2D smoke wisps + 60 3D
  sphere smoke + 40 3D candle Points — all procedural.
- Browser console: NO errors related to `spotlight-3d`,
  `particle-3d`, or `venue-registry`.
- `git diff 21991e8 HEAD -- karaoke/stage.html` shows EXACTLY 2
  lines changed — the new `<script>` tags for spotlight-3d.js +
  particle-3d.js. No reader-path change. D8 invariant intact.

§9.2 — Cluster 2: panel-standardization checks (Checks 31-36)

This cluster contains A2/A3 regression risk. Run AFTER Cluster 1
PASSes.

**Check 31 — All 3 panels use `.anchor-row-actions`**

In DevTools Elements panel, inspect a sample anchor row in each
of the 3 panels. Confirm:
- Audio anchor row: container `<div class="anchor-row-actions">` ✓ (already canonical)
- Particle anchor row: container `<div class="anchor-row-actions">` ✓ (already canonical)
- Spotlight anchor row: container `<div class="anchor-row-actions">` ✓ (FIXED by §7.4 — was `.anchor-row-controls`)

Confirm via DevTools Computed Styles that all 3 inherit the
`.anchor-row-actions button:disabled` opacity:.4 rule when a button
is disabled (e.g. Save when no dirty edits).

**Check 32 — Button labels + glyphs match canonical**

Inspect a particle anchor row + a spotlight anchor row + (where
applicable) an audio anchor row:
- Preview button label: `▶ Play preview` (NOT `▶ Preview` —
  spotlight panel was fixed by §7.4).
- Replay glyph (in particle + spotlight panels): U+21BB `↻`
  (NOT U+27F3 `⟳` — spotlight panel was fixed).
- Stop glyph (new in all 3 panels): U+23F9 `⏹`.
- Status div: `<div class="anchor-status" data-status></div>`
  (spotlight `data-status` attribute fixed by §7.4).

Manual visual confirmation in DevTools. Sanity-check the codepoints
by copy-pasting from DevTools into a Unicode lookup if needed.

**Check 33 — A2 audio round-trip regression test**

Re-run A2 Check 8 (audio panel round-trip) end-to-end. Specifically:
- Select hollywoodbowl in sidebar.
- Audio anchor `anc_aud_hollywoodbowl` renders in panel.
- Click Play preview — sound starts.
- Click new per-row Stop button — sound stops. Stop button hides.
- Click Play preview again — sound starts.
- Click Save (no dirty state to save; should be disabled). Click Delete.
  Confirm dialog. Confirmed. Row removes.
- Click "+ Add audio anchor". Pending row appears. Sound_id field.
  Enter "hollywoodbowl". Click Save. Anchor row reappears with
  panel-generated UUID id.
- Apply seed-id restore SQL per A2 precedent to restore
  `anc_aud_hollywoodbowl`.

PASS condition: audio panel works end-to-end through the new per-
row Stop pattern + button restyling. No regressions in lifecycle.

**Check 34 — A3 particle round-trip regression test**

Re-run A3 Check 15 end-to-end on stadium. Particle anchor
`anc_par_stadium` round-trips through Delete → Add → Save → Preview
→ Replay → Stop (new!) lifecycle. Apply seed-id restore SQL post-
test.

PASS condition: particle panel works end-to-end through the new
per-row Stop pattern. No regression in `respawn:false` 8-second
"Preview ended" affordance (still active per A3 27610e4 fix).

**Check 35 — A4a spotlight light-shaft round-trip through multi-anchor list**

Select speakeasy in sidebar. Spotlight panel shows TWO anchor rows:
- `anc_spot_speakeasy` (light-shaft) — A4a-shipped
- `anc_spot_speakeasy_candles` (point-light) — A4b-shipped

Click Preview on light-shaft row. Bounded 2D canvas shows 3
drifting amber shafts. Click Stop. Canvas clears.

Click Edit on light-shaft row. Modify base_alpha_range field.
Click Save. Verify save succeeds via the canonical 3-arg p_partial
RPC call (the A4a Check 21 fix should still be in place — verify
via DevTools Network tab the POST body has `{p_id, p_venue_id,
p_partial}` not the broken 11-arg shape).

PASS condition: light-shaft round-trip works in the multi-anchor
panel; existing data unchanged; per-row state isolated between
the two anchors.

**Check 36 — Per-row Stop works on all 3 panels**

For each of the 3 panels (audio, particle, spotlight):
- Click Preview on any anchor row → Stop button appears.
- Click per-row Stop button → preview ends, Stop button hides,
  Preview button reappears.
- Confirm no orphaned audio playback / RAF loops / WebGL contexts
  via console audit:
  ```
  > performance.measureUserAgentSpecificMemory?.()
  > getCtxCount()  // from Check 28
  ```
  Memory + context count return to baseline within ~2 seconds of
  Stop click.

PASS condition: per-row Stop works on all 3 panels; no orphan
resources.

═══════════════════════════════════════════════════════════════════════
§10 — GHOST-CODE BOUNDARY + D8 DORMANCY
═══════════════════════════════════════════════════════════════════════

§10.1 — No ghost has 3D content
`addVenueEffects3D` at `karaoke/stage.html:2848-2856` only
dispatches to `buildStadiumEffects3D` and `buildSpeakeasyEffects3D`.
No other venue (including the 4 ghost venues: space, forest,
underwater, dead-dragonlair) has 3D content. A4b leaves all ghost
code untouched.

§10.2 — Shadowed dead-code refinement (lines 4935-4974)
The A4b foundation pass §10.2 surfaced that `dragonlair` AND
`underwater` have full AMBIENT_PROFILES entries with `anim`
functions at `karaoke/stage.html:4935-4974` — these are SHADOWED
by the `anim: null` entries at lines 4988-4990 (JS object-literal
late-binding: the second `dragonlair: {...}` definition wins).
A3 foundation pass §10.1 missed this — its claim that "ghost
venues have anim:null" was post-shadowing true but pre-shadowing
false. A3 foundation pass also incorrectly stated "no 'underwater'
venue key exists" — partial correction: 'underwater' is referenced
at lines 1944 + 4956 in the source.

A4b takes NO ACTION on the shadowed dead code. It is A7's
retirement scope. A4b updates the existing "ghost venue keys
deleted during A7 retirement pass" DEFERRED entry to add:
- Refinement: lines 4935-4974 (dragonlair + underwater shadowed
  full profiles) should be deleted alongside the audio-only
  shadowing entries at 4988-4990 during the A7 cleanup. The
  shadowed code is functionally dead but cluttering and could
  confuse a future implementer who searches for "underwater" or
  "dragonlair" patterns.
- Correction: A3 foundation pass §10.1's claim about ghost venue
  composition was incomplete; A4b foundation pass §10.2 has the
  corrected inventory.

§10.3 — D8 dormancy confirmation
A4b ships dormant per the A2/A3/A4a pattern. Specifically:
- The 4 seeded 3D anchors are DATA in `venue_anchors`.
- Karaoke's read path is UNCHANGED — `AMBIENT_PROFILES` +
  `addVenueEffects3D` in `karaoke/stage.html` stay load-bearing
  until Stage A7. The seeded anchors are not consulted by
  karaoke; the procedural builders continue to run.
- The 2 new renderer modules are REGISTERED but have no live
  consumer in karaoke. Their only consumer until A7 is the admin
  panel's preview surface.
- The 2 new `<script>` tags in karaoke/stage.html are
  REGISTRATION-ONLY per the A2 Check 12 / A3 Check 18 / A4a
  Check 30 precedent. No reader-path change.

═══════════════════════════════════════════════════════════════════════
§11 — DEFERRED ENUMERATION
═══════════════════════════════════════════════════════════════════════

§11.1 — What closes in A4b
The A4a closeout filed 8 DEFERRED entries (a-h). A4b closes 5 of
them outright:

- **A4a-(a) Modulator synthesis decision for A4b 3D phone-lights** —
  A4b resolves: bind `crowd_brightness` with synthesized rationale
  (D-modulator + §2.6 + §3.8). Closed.
- **A4a-(b) PERMIT multi-anchor structural UI evolution** — A4b
  builds the multi-anchor panel (§6). Closed.
- **A4a-(d) §9 step 4 proposal-vs-A3-implementation drift cluster** —
  the PROCESS gap was the deferred item; A4b applies the discipline
  throughout (every RPC call shape, every DOM class verified
  against real code, citing line:column in this spec). Closed
  as a process improvement. Future stages should continue the
  discipline.
- **A4a-(e) Kind-switch UX divergence** — A4b's multi-anchor
  restructure (§6) sidesteps the kind-switch problem entirely:
  each saved anchor has a fixed kind; "change kinds" means
  "create new + delete old." Closed.
- **A4a-(f) Spotlight + particle panel button styling +
  Stop-all placement** — A4b applies the canonical pattern (§7)
  to all three panels + adds per-row Stop. Closed.
- **A4a-(g) Missing per-row Stop button on preview** — A4b adds
  per-row Stop (§7.2). Closed.

§11.2 — D-twinkle closure
The "synthesized" decision (D-twinkle: replace source's global-
sync twinkle with per-particle shader) is implemented in A4b. The
implementation closes the design question. A7's read-path
verification (D-a7 item 1: motion-accuracy side-by-side) verifies
the per-particle twinkle matches the source's overall feel.

§11.3 — What stays A7-structural
Two items remain queued for A7, structurally (not punted):

- **A4a-(c) GSAP-equivalent motion accuracy verification gap** —
  A7's read-path switch is the first prod exercise of the
  renderer-driven paths. Full verification needs side-by-side
  against the procedural code, which A7 enables. A4b's source-
  faithful reproduction of motion math gets us as close as
  possible pre-A7.
- **Ghost-venue shadowed dead-code deletion (lines 4935-4974)** —
  A7's retirement scope. A4b updates the existing DEFERRED entry
  with refinement + correction notes per §10.2.

§11.4 — What A4b generates new
Anticipated entries to file at A4b closeout (final list determined
during implementation):

1. **r128 → r150+ migration consideration.** r128 is from 2021;
   the project depends on it via CDN. r150+ has ES module support
   + improved ShaderMaterial integration. Out of scope for A4b
   (don't change the library version mid-stage) but worth filing
   if the ShaderMaterial implementation reveals r128-specific
   pain.
2. **Modulator preview oscillator for admin panel (parity with A3
   particle.js).** Whether to ship in A4b is implementation-cycle
   scope. If skipped, file as DEFERRED for the next admin-UI
   polish pass.
3. **Camera/FOV per-kind tuning** (§5.4 starting values). The
   table in §5.4 is the reasonable starting point; implementation
   cycle may need to tune per visual inspection. Tuning becomes
   payload metadata or stays as renderer-side defaults — file
   the decision either way.

§11.5 — The pile is being actively drained
At A4a closeout: 8 new DEFERRED entries filed. At A4b closeout
(projected): 5 of those close + 3 stay structural + ≤3 new files.
Net delta: from +8 to roughly 0 or slightly positive. The pattern
is "stage closeout files a cluster; subsequent stages drain
multiple entries per closeout." A4b is the first stage where the
draining mechanism actually works at scale.

═══════════════════════════════════════════════════════════════════════
§12 — IMPLEMENTATION SEQUENCE
═══════════════════════════════════════════════════════════════════════

Propose-pause-apply throughout. Each numbered item is a review gate.

  1. **Foundation/payload pass** — for each of the 4 in-scope 3D
     effects, quote the procedural source block and propose the
     exact db/038 payload it produces. Show the per-item array
     unpacking against the source's per-index code (where
     applicable — swept-beam-3d has 4 indexed entries; the other
     3 kinds are scalars + ranges). THIS IS THE LOAD-BEARING
     REVIEW — payload-vs-source fidelity. Pause for review.

  2. **Propose db/038 in full** — 4 seed rows + verification
     footer. Pause for review.

  3. **Propose `spotlight-3d.js`** — full module:
     - Self-contained posture (§3.1 / §3.2).
     - `{update, dispose}` contract (§3.3 / D-contract).
     - Caller-owns-RAF (§3.4 / D-raf).
     - `handleSweptBeam3d` (§3.5).
     - `handlePointLight` (§3.5).
     - Context dispatch (only `"3d-three"` accepted; warn + no-op
       for any other context).
     - Kind dispatch (only `swept-beam-3d` + `point-light`
       accepted; warn + no-op for unknown kinds).
     - Registration with `{context: '3d-three'}` option (§4.1).
     - Window publication (§4.3).
     Pause for review.

  4. **Propose `particle-3d.js`** — full module:
     - Same scaffolding as spotlight-3d.js.
     - `handlePointCloud3d` with custom ShaderMaterial (§3.6 +
       §3.7 + D-twinkle).
     - `handleVolumetric3d` with shared SphereGeometry (§3.6 +
       D-modulator's `volumetric-3d` does NOT bind modulator).
     - Modulator value resolution per §3.8 (only `point-cloud-3d`
       uses it).
     Pause for review.

  5. **Propose registry context-dispatch extension** — if the
     existing `registerAnchorRenderer` in
     `shell/venue-registry.js` doesn't accept a `{context}`
     option, propose the minimal extension. Backward-compatible
     (default `'2d-canvas'`; existing 2D registrations unchanged).
     Pause for review.

  6. **Propose `admin-venues.html` Three.js preview infra** (§5).
     Includes:
     - CDN script tag for three.js r128.
     - `createPreviewContext3d(canvasEl, kind)` helper.
     - `previewFovForKind` + `positionCameraForKind` lookups.
     - `tearDownPreview3d(anchorId, stateMap)` helper (§5.6).
     - Per-row RAF loop owner.
     - State Map declarations (`spotlight3dPreviewState`,
       `particle3dPreviewState`).
     Pause for review.

  7. **Propose multi-anchor panel restructure** (§6). Includes:
     - Refactor `renderSpotlightPanel` from single-editor to
       anchor-list shape.
     - Refactor `renderParticlePanel` similarly (it's already
       single-anchor per A3 PREVENT; A4b extends to multi-anchor
       for the 3D variant).
     - Audio panel: STAYS single-anchor per A2 PREVENT. Just
       gets the per-row Stop addition from §7.
     - Add-anchor-with-kind-picker (§6.3).
     - Default payload functions extended for new kinds (§6.3).
     Pause for review.

  8. **Propose panel standardization pass** (§7). Includes the
     5 spotlight-divergence fixes + the per-row Stop addition for
     all 3 panels + the Stop-all button ID renames. Show every
     edit per panel.
     Pause for review.

  9. **On approval: apply db/038 to prod** (Supabase SQL Editor,
     human-side gate). Run Q1-Q3. ON PASS: commit the implementation
     (spotlight-3d.js + particle-3d.js + admin-venues.html +
     karaoke/stage.html two-line tag + db/038 file +
     MIGRATIONS_APPLIED.md row) as one commit. No push until the
     gate.

  10. **Push gate.** Then verification:
      - Cluster 1 (Checks 25-30): 3D-anchor checks. ON PASS:
      - Cluster 2 (Checks 31-36): panel-standardization checks.
      File DEFERRED entries per §11.4 as discoveries land.

  11. **A4b verification result log** at
      `docs/SESSION-LOGS/YYYY-MM-DD-A4b-verification-result.md`.
      Mirror A4a log structure (§8 Checks results, Cleanup
      section, Conclusion, DEFERRED list).

  12. **Closeout commit** — docs only:
      - Verification log (new file).
      - DEFERRED.md entries (per §11).
      - CONTEXT.md "Latest shipped" update (A4b shipped; A4a
        demoted to Recent shipped).
      - EXECUTION-HANDOFF.md (A4b stage block + next-stage
        trigger A5 or A4.5).
      - ROADMAP.md (A4b shipped marker).
      - Direction §7 (Stage 4 paragraph: A4b ✓ shipped marker
        alongside A4a's existing ✓).
      Commit subject: `docs: Venue Admin UI Stage A4b closeout — verification log + DEFERRED entries + doc-currency`
      No body. No Co-Authored-By trailer.
      `git add docs/` discipline: stage individually, NOT
      wildcard (avoid the A4a closeout `git add docs/` mishap
      that pulled the two pre-existing untracked files —
      see A4a closeout commit `20f56cb`→`21991e8` force-push
      correction).

No Co-Authored-By trailer on any A4b commit. db/038 applies to
prod BEFORE the implementation commit lands (A2/A3/A4a ordering).
User runs the migration in Supabase SQL Editor manually; Claude
Code never applies to prod.

— END OF A4b BUILD SPEC —
