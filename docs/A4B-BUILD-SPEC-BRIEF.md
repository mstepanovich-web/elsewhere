# A4b Build-Spec Brief

**Purpose:** This is the brief Claude Code uses to author `docs/VENUE-ADMIN-UI-A4B-BUILD-SPEC.md`. It is NOT the spec itself — it is the locked decision set + structure + the verbatim-source anchors the spec must honor. Claude Code writes the full spec from this, then pauses for review before any code.

**Stage:** Phase 3 / Plan B — Venue Admin UI Stage **A4b** (3D venue effects: 3D spotlight + 3D particle extension + Three.js admin preview surface + panel standardization).

**Baseline commit:** `21991e8` (A4a closeout). Clean tree.

**Discipline carried from A4a (DEFERRED-d):** Specify by exact class name, exact codepoint, exact RPC signature, exact line reference. Match real code, not prose. The A4a foundation pass + the two pre-spec investigations already pulled the canonical patterns — the spec must cite them by name, not re-describe them.

---

## §0 — Locked decisions (do not re-litigate in the spec)

| # | Decision | Resolution |
|---|----------|-----------|
| D-scope | One stage or sub-stage | **One stage.** All 4 anchors + preview infra + renderers + panel standardization in one propose-pause cycle. Rationale: stadium's cones + phone-lights share one builder function (`buildStadiumEffects3D`), so splitting spotlight/particle would span the same procedural code across two stages. |
| D-files-spot | spotlight 3D file org | **Sibling `shell/venue-renderers/spotlight-3d.js`.** Overrides A4a spec §3.4's "extend the same file." 2D and 3D share only the payload contract + kind dispatch; rendering code is disjoint (2d-canvas vs WebGL). |
| D-files-par | particle 3D file org | **Sibling `shell/venue-renderers/particle-3d.js`.** Same logic. `particle.js` stays 2D-only. |
| D-dispatch | registry dispatch | Anchor registry dispatches on `payload.context`: `"2d-canvas"` → 2D module, `"3d-three"` → 3D module. Both 3D modules register against the existing anchor `type` (`spotlight`, `particle`). |
| D-contract | 3D renderer contract | **`{ update, dispose }`** — matches the source's verb (`buildStadiumEffects3D` returns `{update, dispose}`) and Three.js idiom. NO speculative `stop`. 2D stays `{ stop }` (self-RAF). The asymmetry is real and documented, not papered over. |
| D-raf | RAF ownership | 3D = **caller-owns-RAF** (renderer returns `{update, dispose}`; the admin preview owns the loop and calls `update()` per frame then renders). 2D = renderer-owns-RAF. Matches A4a D4 + confirmed against karaoke `renderLoop` lines 4012-4052. |
| D-webgl | preview context strategy | **Lazy context per preview canvas; `renderer.dispose()` + `renderer.forceContextLoss()` on EVERY exit path** (Stop, venue switch, kind switch, navigate away, panel reload). No shared-context-swap machinery. Bounded active contexts. |
| D-twinkle | phone-lights per-particle twinkle | **Build the correct version: custom `ShaderMaterial` with per-vertex phase attribute.** Honors the source's dead `phases` Float32Array (lines 2865-2868) which proves per-particle intent. Each of 2000 points twinkles on its own phase, like A3's 2D phone-lights `Math.sin(this.phase)`. This is the one genuinely novel rendering bit in A4b. |
| D-multianchor | multi-anchor UI | **Build it — functional floor.** Speakeasy genuinely has 2 spotlight anchors (light-shaft A4a + point-light A4b) that must be simultaneously visible/editable. Panel becomes anchor-LIST with per-anchor editor block + "add anchor (pick kind)" + per-anchor save/delete. No decorative extras (no drag-reorder, no inline rename). |
| D-standardize | panel standardization | **All three panels (audio/particle/spotlight) conform to the A3 canonical pattern + gain per-row Stop.** Dedicated verification section, separate from 3D-anchor checks, to contain A2/A3 regression risk. |
| D-datastatus | data-status attribute | Include `data-status` on new markup for shape-match with A2/A3. Do NOT build behavior onto it (showAnchorStatus selects by `.anchor-status` class; the attribute stays vestigial). |
| D-naming | anchor ids | Descriptive `_3d`/effect suffixes throughout (see §3). |
| D-modulator | 3D phone-lights modulator | Bind `crowd_brightness` modulator on `anc_par_stadium_phonelights3d` for A3 parity. Renderer: modulator-value-when-present, internal-sine-fallback-when-absent. Documented as **synthesized, not extracted** (source uses frame-counter sin, nothing to extract). |
| D-a7 | structurally deferred | Two items are A7's by nature, NOT punted: (1) full motion-accuracy verification (needs live karaoke read-path side-by-side, A7's switch); (2) ghost-venue shadowed dead-code deletion (lines 4935-4974, A7's retirement scope). A4b tightens (1) by faithfully reproducing source motion math + documenting the mapping. |

---

## §1 — The four anchors (db/038)

| Anchor id | type | payload.kind | context | count | respawn | modulator | notes |
|-----------|------|--------------|---------|-------|---------|-----------|-------|
| `anc_spot_stadium_beams3d` | spotlight | `swept-beam-3d` | `3d-three` | 4 | — | none | warm cream cones, counter-rotating pairs |
| `anc_spot_speakeasy_candles` | spotlight | `point-light` | `3d-three` | 40 | — | none | amber Points on tables, flicker |
| `anc_par_stadium_phonelights3d` | particle | `point-cloud-3d` | `3d-three` | 2000 | — | `crowd_brightness`→opacity (synthesized) | per-particle twinkle via shader |
| `anc_par_speakeasy_smoke3d` | particle | `volumetric-3d` | `3d-three` | 60 | true | none | sphere meshes, per-particle lifecycle |

Spec must derive each payload's full field set by quoting the verbatim source (§2 below) and mapping each procedural constant to a payload key — the same payload-vs-source fidelity table A4a used. Six-decimal precision on irrational values.

---

## §2 — Verbatim source anchors (the spec MUST quote these by line)

All at `karaoke/stage.html` @ `21991e8`.

- **Stadium cones (swept-beam-3d):** 2884-2935 (inside `buildStadiumEffects3D`). 4× `CylinderGeometry(0, 35, 300, 16, 1, true)`, `geo.translate(0,-150,0)`, `MeshBasicMaterial` opacity 0.06 BackSide depthWrite:false, colors `[0xfffce0,0xfffce0,0xfff0cc,0xfff0cc]`, positioned on r=380 sphere, `lookAt(0,0,0)`. Update: `angle += speed` (speeds `[0.003,-0.004,0.005,-0.003]`), phi wobble `sin(frame*0.01)*0.08`.
- **Speakeasy candles (point-light):** 2980-3000 (inside `buildSpeakeasyEffects3D`). 40× Points, `PointsMaterial` color `0xffaa33` size 4 sizeAttenuation opacity 0.7, scattered r∈[80,330] y∈[-120,-80]. Update: every 4 frames `opacity = 0.5 + random*0.5` (SHARED material = global sync flicker).
- **Stadium phone-lights (point-cloud-3d):** 2861-2882. 2000× Points, white size 2.5, hemisphere r=460-490 phi∈[0.471,2.670] y-flattened×0.4-80. Dead `phases` array 2865-2868 (intent: per-particle phase). Update 2920-2923: every 3 frames `opacity = 0.5 + sin(frame*0.04)*0.3` (global sync — A4b replaces with per-particle shader per D-twinkle).
- **Speakeasy smoke (volumetric-3d):** 2946-2974 build + 3005-3022 update. 60× `Mesh` of shared `SphereGeometry(1,6,6)` scaled 15-55, PER-PARTICLE `MeshBasicMaterial` color `0xbbbbaa` opacity∈[0.01,0.05]. Per-particle `{vy:0.08-0.20, vx/vz:±0.025, life, maxOpacity}`. Update: drift + `life+=0.003`, `opacity = maxOpacity*sin(life*π)`, respawn at `life%1>0.98`.
- **Three.js infra:** import line 621 (`three.js r128` cdnjs). Renderer/scene/camera lazy-init 2655-2664 (`panRenderer`/`panScene`/`panCamera3`, PerspectiveCamera 80° FOV near 0.01 far 2000 YXZ). Dispatcher 2848-2856 (`addVenueEffects3D`, singleton `venueEffects3D`). RAF 4012-4052 (`renderLoop` calls `venueEffects3D.update()` then `panRenderer.render`). Dispose patterns 2935-2938 (stadium) + 3030-3033 (speakeasy, + `smokeGeo.dispose()`).

**Entanglement note (§12.1):** `buildStadiumEffects3D` builds BOTH the cones (swept-beam-3d) AND the phone-lights (point-cloud-3d) — one function, one `objects[]`, one `update()`, one `dispose()`. The seed writes 2 separate anchors; the procedural code stays bundled until A7 deletes the function. Spec must note this so the read-path expectation is correct.

---

## §3 — Canonical panel pattern (the standardization target)

From the pre-spec investigation, by exact name:

**Container:** `.anchor-row-actions` (CSS at lines 401-415). NOT `.anchor-row-controls` (zero CSS matches — the root cause of the illegible A4a buttons).

**Canonical per-row markup (A3 particle, lines 2020-2028):**
```
<div class="anchor-row-actions">
  <button type="button" class="btn-play-{type}-preview">▶ Play preview</button>
  <button type="button" class="btn-replay-{type}-preview" hidden>↻ Replay</button>
  <button type="button" class="btn-stop-{type}-preview" hidden>⏹ Stop</button>   <!-- NEW per-row Stop, D-standardize -->
  <button type="button" class="btn-anchor-save">Save</button>
  ${isPending
    ? '<button type="button" class="btn-anchor-cancel">Cancel</button>'
    : '<button type="button" class="btn-anchor-delete">Delete</button>'}
</div>
<div class="anchor-status" data-status></div>
```

**Exact tokens:**
- Preview label: `▶ Play preview` (NOT `▶ Preview`)
- Replay glyph: **U+21BB** `↻` (NOT U+27F3 `⟳`)
- Stop glyph: `⏹` (U+23F9)
- Status: `<div class="anchor-status" data-status></div>`
- Cancel/Delete: render ONE based on `isPending`, never both
- Stop-all ID: `btn-stop-{type}-preview` form (rename A4a's `btn-stop-all-spotlight-previews` → `btn-stop-spotlight-preview`)

**Status CSS (canonical):** `.anchor-status` mono 10px faint; `.error`→#e07e7e; `.success`→gold.

**Per-row Stop state machine (NEW standard, applies to all 3 panels):**
- Idle: Preview visible; Replay + Stop hidden.
- Playing: Preview hidden; Replay + Stop visible.
- Click Replay: stop + play; stays Playing.
- Click Stop: stop; → Idle. (For 3D: Stop MUST trigger WebGL teardown per D-webgl.)

**A4a spotlight divergences to KILL** (5, all in `renderSpotlightAnchorRowHTML` 2430-2437): wrong container ①, wrong label ②, wrong glyph ③, missing data-status ④, both-buttons-rendered ⑤.

---

## §4 — Required spec sections (mirror A4a spec structure)

1. **§0 Foundation recap** — the locked decision set (§0 above), with the 4-anchor table.
2. **§1 Kind vocabulary** — 4 new kinds, each `context:"3d-three"`, sibling to A4a/A3 kinds. Map each to its source builder.
3. **§2 Payload schemas** — per-kind field set, derived from verbatim source (§2 anchors), payload-vs-source fidelity table, 6-decimal precision.
4. **§3 Renderer design** — `spotlight-3d.js` + `particle-3d.js`. `{update,dispose}` contract. Caller-owns-RAF. The custom ShaderMaterial for per-particle twinkle (D-twinkle) spec'd explicitly: vertex shader passes per-vertex `phase` attribute → fragment modulates alpha; document the r128 constraint (PointsMaterial can't do per-vertex opacity, hence the shader). Modulator synthesis for phone-lights (D-modulator).
5. **§4 Registry dispatch** — context-aware dispatch layer (`2d-canvas`/`3d-three`). Script tags: `spotlight-3d.js` + `particle-3d.js` added to BOTH `karaoke/stage.html` AND `admin-venues.html` (the A4a Check-21 lesson — enumerate both locations).
6. **§5 Three.js admin preview surface** — the new territory. Per-canvas lazy WebGLRenderer + Scene + PerspectiveCamera. The teardown contract (D-webgl): `dispose()` + `forceContextLoss()` on all exit paths, enumerated. Camera/FOV choice per kind. ~60 LOC estimate.
7. **§6 Multi-anchor panel** (D-multianchor) — anchor-LIST structure, per-anchor editor block, add-anchor-with-kind-picker, per-anchor save/delete. Replaces A4a's single-editor-swap-kind (closes DEFERRED-e: hide/show, not re-render). State management for N anchors per venue.
8. **§7 Panel standardization pass** (D-standardize) — apply §3 canonical pattern + per-row Stop to ALL THREE panels (audio/particle/spotlight). Explicitly list every edit per panel. This is the section whose verification is separate (§9).
9. **§8 db/038 migration** — 4 INSERTs, descriptive ids (§1), idempotent (ON CONFLICT), MIGRATIONS_APPLIED.md entry. Note the prod-apply-before-commit doctrine (user applies manually in Supabase SQL Editor).
10. **§9 Verification plan** — TWO check clusters:
    - **3D-anchor checks:** renderer registration (both modules), seed verification, per-kind admin preview (all 4 kinds render in Three.js preview), WebGL teardown verification (contexts released on Stop/switch/navigate — check via `WEBGL_lose_context` or context count), RPC authority gate, D8 dormancy (karaoke read-path unchanged — all 3D effects still procedural).
    - **Panel-standardization checks (separate):** all 3 panels use `.anchor-row-actions`, buttons legible/styled, per-row Stop works on each panel, A2/A3 round-trip still passes (regression), spotlight A4a anchors (light-shaft) still author correctly through the new multi-anchor list.
11. **§10 Ghost/edge inventory** — no ghost has 3D content (dispatcher only stadium+speakeasy). Record shadowed dead-code (4935-4974) finding as A7 DEFERRED refinement, correct A3 foundation pass's "no underwater key" claim. NO A4b action on it.
12. **§11 DEFERRED enumeration** — what closes in A4b (a,b,e,f,g + twinkle), what stays A7-structural (c motion-accuracy, ghost-cleanup). Be explicit that the pile is being actively drained, not grown.

---

## §5 — Build-order guidance for the spec

Suggested implementation sequence (spec refines):
1. db/038 (4 anchors) — apply to prod first, verify, THEN commit.
2. `spotlight-3d.js` + `particle-3d.js` renderers (incl. the twinkle shader).
3. Registry context-dispatch + script tags (both files, both locations).
4. Three.js admin preview surface (the new infra).
5. Multi-anchor panel restructure (spotlight panel first — it's the one with 2 anchors).
6. Panel standardization pass across all 3 panels.
7. Verification: 3D-anchor cluster, then panel-standardization cluster.
8. Closeout.

---

## §6 — Process reminders for Claude Code

- Propose-pause per gate. No file edits / commits in spec-authoring.
- Verify every call shape against the REAL RPC signature (`rpc_venue_anchor_upsert` = 3-arg `p_id, p_venue_id, p_partial`) and every DOM class against the REAL selector. This is DEFERRED-d; do not regress to interpreting prose.
- One paste block per task.
- No Co-Authored-By trailer. Subject-only commits unless told otherwise.
- User applies prod migrations manually. Claude Code never applies to prod.
- The two pre-existing untracked files stay untracked.
- PAUSE after delivering the spec. Planning chat reviews before any code.
