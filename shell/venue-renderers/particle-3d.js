// shell/venue-renderers/particle-3d.js
//
// 3D particle anchor renderer for the Venue Admin UI Stage A4b
// workstream. Sibling to A3's shell/venue-renderers/particle.js
// (D-files-par per spec docs/VENUE-ADMIN-UI-A4B-BUILD-SPEC.md §0.3) —
// NOT an extension of that file. 2D and 3D rendering share only the
// payload contract + kind dispatch; the underlying APIs are disjoint
// (canvas 2D vs Three.js WebGL).
//
// Registered to shell/venue-registry.js's anchor renderer registry
// at module load time under the DISTINCT KEY 'particle-3d' (NOT
// 'particle' — that key is owned by A3's particle.js:636 for the
// 2D-canvas path). Distinct keys avoid the F3 clobber risk
// surfaced at Gate 2 (2026-05-28): the registry's current API is
// keyed by `type` alone with no context discriminator, so calling
// registerAnchorRenderer('particle', ...) from this module would
// REPLACE A3's registration via the "warn + replace" semantics at
// shell/venue-registry.js:172-179. By using 'particle-3d' as a
// distinct key, both registrations coexist cleanly:
//   getAnchorRenderer('particle')    → A3's 2D function (unchanged)
//   getAnchorRenderer('particle-3d') → this module's 3D function
//
// Gate 5 design choice (2026-05-28): distinct-keys over the spec
// §4.1-originally-locked context-aware registry extension. Rationale:
// only ONE future consumer reads from the registry (Stage A7's
// karaoke read-path switch); the admin preview reads via
// window.elsewhere globals (SECTION 6 below), NOT the registry.
// Extending register+get+all-callsites to support a {context} 3rd
// arg is over-engineered for a single future caller. The A7 read-
// path will derive the lookup key from the venue_anchors row as
//   key = anchor.payload.context === '3d-three' ? anchor.type + '-3d' : anchor.type
// — using `anchor.type` (the venue_anchors COLUMN value set by
// db/038's INSERT, e.g. 'particle') NOT `payload.type` (which is
// undefined for spotlight/particle payloads; `payload.type` exists
// only on audio payloads as a format discriminator, a naming-
// collision artifact verified pre-edit). The DB `type` column at
// public.venue_anchors stays 'particle' (db/032's
// venue_anchors_type_check vocabulary unchanged) — the '-3d' suffix
// is a renderer-registry-key derivation only, not a schema-level
// type. Spec §4.1 + §0.3 D-dispatch row amended to reflect this
// resolution; see Gate 5 commit cluster.
//
// Two kinds dispatched on payload.kind (spec §1.1):
//   • point-cloud-3d — N sprite Points on a flattened hemisphere
//                       with per-particle independent twinkle via
//                       custom THREE.ShaderMaterial + per-vertex
//                       `phase` attribute. Optional `crowd_brightness`
//                       modulator binding multiplies whole-cloud
//                       alpha. Stadium 2000-light case is canonical
//                       (db/038 anc_par_stadium_phonelights3d).
//                       Source: karaoke/stage.html:2861-2882 (build)
//                       + 2920-2923 (update — GLOBAL-SYNC twinkle
//                       that A4b upgrades to per-particle per
//                       D-twinkle).
//   • volumetric-3d  — N independent sphere meshes sharing one
//                       SphereGeometry. Each has its own
//                       MeshBasicMaterial (per-particle opacity)
//                       and per-instance userData (vy/vx/vz/life/
//                       maxOpacity). Drifts upward, fades in+out per
//                       life cycle, respawns at life%1 > threshold
//                       to a NARROWER spawn region (spec §2.7
//                       phi-range asymmetry). Speakeasy 60-smoke
//                       case is canonical (db/038
//                       anc_par_speakeasy_smoke3d).
//                       Source: karaoke/stage.html:2946-2974 (build)
//                       + 3005-3022 (update) + 3030-3033 (dispose).
//
// ctx contract (spec §3.3 + §5.1):
//   ctx.scene       — THREE.Scene the caller owns; renderer attaches
//                     its meshes/points via ctx.scene.add(...).
//                     Renderer does NOT create its own scene/renderer/
//                     camera — that's the admin preview surface's
//                     job (spec §5.3). Karaoke's eventual A7
//                     read-path switch will pass the existing
//                     panScene here.
//   ctx.camera      — THREE.PerspectiveCamera. Read-only from this
//                     module's perspective. Reserved for future
//                     camera-aware kinds; A4b's two kinds don't
//                     read it.
//   ctx.modulators? — optional function getter `(name) => number | null`
//                     per spec §3.3 contract. ONLY point-cloud-3d
//                     reads this — it resolves `crowd_brightness`
//                     each frame to multiply the ShaderMaterial's
//                     `uModulator` uniform. When absent OR returns
//                     null/undefined, defaults to 1.0 (synthesized-
//                     binding fallback per D-modulator + spec §3.8).
//                     volumetric-3d does not bind any modulator.
//
// {update, dispose} contract (D-contract, spec §3.3):
//   update(now)  — call per RAF tick. Mutates scene-object
//                  transforms/opacities/shader-uniforms. Does NOT
//                  call renderer.render() — the caller owns
//                  rendering. Internal _disposed flag is checked
//                  first; if set, the call is a no-op. Defense-in-
//                  depth pair to the admin RAF callback's
//                  st.disposed guard (spec §5.6).
//                  The `now` argument is accepted per spec §3.3 but
//                  IGNORED by both A4b particle kinds — they use an
//                  internal frame counter to match source motion
//                  math byte-for-byte. Frame-rate dependence is a
//                  known property; accuracy verification at A7 per
//                  D-a7 item 1, captured in DEFERRED-c.
//   dispose()    — removes attached scene objects, disposes
//                  geometries + materials, sets _disposed = true.
//                  Idempotent. For volumetric-3d, the shared
//                  SphereGeometry is disposed ONCE (mirroring source
//                  3030-3033's explicit smokeGeo.dispose() after the
//                  per-mesh forEach); the renderer's cleaner pattern
//                  disposes per-mesh material individually + the
//                  shared geometry once at the end, avoiding the
//                  source's idempotent-redundant per-mesh geometry
//                  disposal.
//
// Caller-owns-RAF (D-raf, spec §3.4): this renderer does NOT own a
// requestAnimationFrame loop. The admin preview's tickPreview3d
// (spec §5.5) owns the RAF and calls update(now) per frame, then
// calls renderer.render(scene, camera). Karaoke's A7 read-path
// switch will integrate analogously into the renderLoop at
// karaoke/stage.html:4012-4052.
//
// D-twinkle synthesis (point-cloud-3d ONLY, spec §3.7). The source
// at karaoke/stage.html:2920-2923 uses GLOBAL-SYNC twinkle:
//   if(frame % 3 === 0) lightMat.opacity = 0.5 + Math.sin(frame * 0.04) * 0.3;
// — one shared material.opacity write every 3 frames; all 2000 lights
// flicker in lockstep. BUT: the source ALSO allocates a `phases`
// Float32Array at lines 2865-2868:
//   const phases = new Float32Array(count);
//   for (let i = 0; i < count; i++) phases[i] = Math.random() * Math.PI * 2;
// — and NEVER READS IT from update(). Dead code. The presence of
// the per-particle phase array is evidence that per-particle
// independent twinkle was intended but not implemented (likely
// because PointsMaterial can't express per-vertex opacity).
//
// A4b completes the intent via THREE.ShaderMaterial with a per-vertex
// `phase` attribute on the BufferGeometry. The vertex shader passes
// `phase` to the fragment shader via a varying; the fragment shader
// computes per-particle alpha as
//   uBaseOpacity * (uAlphaCenter + sin(vPhase + uTime) * uAlphaSwing)
//                * uModulator
// where uTime accumulates `frame * twinkle.phase_omega_per_frame` per
// update() call, WRAPPED MODULO 2π (the precision-cliff fix — see
// the update() function below). With per-particle phase, each light
// twinkles on its own offset; without per-particle phase (all
// phases = 0), the shader would reduce to `sin(uTime)` and produce
// the source's global-sync twinkle exactly. The motion math is the
// same; the divergence is per-particle vs global-sync.
//
// D-modulator synthesis (point-cloud-3d ONLY, spec §3.8). The source
// binds NO external scalar — the 3D path uses pure frame-counter sin
// and reads no global state. A4b ADDS the `crowd_brightness` binding
// for parity with A3's 2D phone-lights anchor (anc_par_stadium, which
// DOES bind `crowd_brightness → alpha`). The binding is synthesized,
// not extracted — the conceptually-correct binding name from A3's
// pattern, but the source provides nothing to extract.
//
// When A7's modulator driver registry ships, the resolved value
// multiplies the per-particle shader twinkle via the `uModulator`
// uniform. When absent (current state, until A7), the multiplier
// defaults to 1.0 — per-particle shader twinkle is the sole motion.
//
// D8 dormancy: registered but no live consumer in karaoke until
// Stage A7's read-path switch. Karaoke continues to use
// addVenueEffects3D + buildStadiumEffects3D + buildSpeakeasyEffects3D
// at karaoke/stage.html:2848-3037 until then. Only consumer for now
// is admin-venues.html's Three.js preview surface (spec §5).
//
// THREE library access: r128 loaded via CDN at karaoke/stage.html:621
// and at admin-venues.html (CDN tag added by A4b implementation per
// spec §5.2). Available as global window.THREE. NO `import 'three'`
// — matches CLAUDE.md's "No build step" doctrine and the source's
// `new THREE.*` access pattern.
//
// Companion docs:
//   • docs/VENUE-ADMIN-UI-A4B-BUILD-SPEC.md §1 (kind vocabulary),
//     §2.6 (point-cloud-3d schema + fidelity table), §2.7 (volumetric-3d
//     schema + fidelity table + phi-range divergence note), §3 (renderer
//     design), §3.7 (D-twinkle ShaderMaterial spec — vertex shader,
//     fragment shader, uniforms, r128 compat notes), §3.8 (D-modulator
//     value resolution), §5 (admin preview surface).
//   • shell/venue-renderers/particle.js — A3 2D-canvas sibling;
//     this module mirrors its overall shape. The registration call
//     at particle.js is what this module deliberately does NOT
//     mirror until Gate 5.
//   • shell/venue-renderers/spotlight-3d.js — Gate 2 sibling
//     (A4b's other 3D renderer); same module shape, no shader.
//   • db/038_3d_anchor_seed.sql — the 2 particle anchor seeds this
//     renderer animates.
//   • karaoke/stage.html:2861-2882 + 2920-2923 (point-cloud-3d source)
//     + 2946-2974 + 3005-3022 + 3030-3033 (volumetric-3d source).

import { registerAnchorRenderer } from '../venue-registry.js';


// ─────────────────────────────────────────────────────────────────────────
// SECTION 1 — Small helpers
// ─────────────────────────────────────────────────────────────────────────

/**
 * Uniform [min, max] random. Used for both kinds' per-particle
 * spatial layouts + life inits + scale/opacity ranges. Centralized
 * so the rand source is replaceable for deterministic preview
 * testing later (not in A4b scope).
 */
function randIn(min, max) {
  return min + Math.random() * (max - min);
}

/**
 * Resolve a modulator binding to its current value via ctx.modulators
 * getter. Returns 1.0 when:
 *   - binding is absent (kind doesn't bind any modulator)
 *   - ctx.modulators getter is absent (A7's driver registry not yet
 *     live — current state until A7 ships)
 *   - getter returns null / undefined / NaN
 * Otherwise returns the numeric value from the getter.
 *
 * Matches D-modulator value-resolution per spec §3.8. The fallback to
 * 1.0 makes the binding a no-op (the per-particle shader twinkle is
 * the sole motion) until A7's driver registry resolves real values.
 */
function resolveModulator(ctx, binding) {
  if (!binding || !ctx || typeof ctx.modulators !== 'function') return 1.0;
  const val = ctx.modulators(binding.name);
  if (val === null || val === undefined || Number.isNaN(val)) return 1.0;
  return val;
}


// ─────────────────────────────────────────────────────────────────────────
// SECTION 2 — Twinkle shader sources (spec §3.7 — verbatim)
// ─────────────────────────────────────────────────────────────────────────
// The custom ShaderMaterial for point-cloud-3d per D-twinkle. r128's
// THREE.PointsMaterial cannot express per-vertex opacity (its
// `opacity` is a single material-wide scalar). To get per-particle
// independent twinkle, we drop down to ShaderMaterial with a
// per-vertex `phase` BufferAttribute that the vertex shader passes
// to the fragment shader as a varying. The fragment shader modulates
// alpha using vPhase + uTime + uModulator + the alpha center/swing
// uniforms.
//
// r128 compatibility notes (spec §3.7):
//   - ShaderMaterial does NOT inherit standard PointsMaterial
//     attributes; the vertex shader MUST compute `gl_PointSize`
//     explicitly. The formula `gl_PointSize = uSize * (uSizeAttenuation
//     > 0.5 ? (300.0 / -mvPosition.z) : 1.0)` matches PointsMaterial's
//     internal sizeAttenuation logic in r128.
//   - `material.transparent: true` and `material.depthWrite: false`
//     must be set on the ShaderMaterial constructor directly (uniforms
//     can't carry them).
//   - The custom `phase` attribute is named exactly `phase` (not
//     `aPhase`) — the vertex shader's `attribute float phase`
//     declaration must match the BufferAttribute key in
//     geometry.setAttribute('phase', ...).
//   - GLSL mediump precision cliff on uTime: see update() in the
//     point-cloud-3d handler for the modulo-2π wrap and the
//     rationale.

const POINT_CLOUD_3D_VERTEX_SHADER = `
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
`;

const POINT_CLOUD_3D_FRAGMENT_SHADER = `
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
`;


// ─────────────────────────────────────────────────────────────────────────
// SECTION 3 — handlePointCloud3d (spec §2.6 + §3.7 + §3.8, source 2861-2882)
// ─────────────────────────────────────────────────────────────────────────

/**
 * Stadium point-cloud-3d handler. Constructs ONE THREE.Points
 * holding `count` vertices on a flattened hemisphere + ONE custom
 * THREE.ShaderMaterial driving per-particle independent twinkle.
 *
 * Build (lines 2861-2882, with A4b's D-twinkle synthesis layered on):
 *   - new THREE.BufferGeometry()
 *   - Per-vertex `position` Float32Array(count * 3):
 *       phi   = randIn(phi_norm_range[0], phi_norm_range[1]) * π
 *               // source 2867: (rand*0.7 + 0.15) * π = randIn(0.15, 0.85) * π
 *       theta = randIn(theta_range[0], theta_range[1])
 *               // source 2868: rand * 2π
 *       r     = randIn(r_range[0], r_range[1])
 *               // source 2869: 460 + rand*30 = randIn(460, 490)
 *       x = r * sin(phi) * cos(theta)                  // source 2870
 *       y = r * cos(phi) * y_flatten_factor + y_offset // source 2871: cos(phi)*0.4 - 80
 *       z = r * sin(phi) * sin(theta)                  // source 2872
 *   - Per-vertex `phase` Float32Array(count) per D-twinkle:
 *       phases[i] = Math.random() * Math.PI * 2
 *       // matches the source's DEAD `phases` allocation at lines
 *       // 2865-2868 (allocated, never read by update() — A4b
 *       // completes the intent)
 *   - geometry.setAttribute('position', new BufferAttribute(pos, 3))
 *   - geometry.setAttribute('phase',    new BufferAttribute(phases, 1))
 *   - new THREE.ShaderMaterial with the §3.7 vertex+fragment shaders
 *     and the 8 uniforms (uColor, uBaseOpacity, uTime, uModulator,
 *     uAlphaCenter, uAlphaSwing, uSize, uSizeAttenuation). transparent
 *     and depthWrite set on the constructor directly per §3.7 r128
 *     compat notes.
 *   - new THREE.Points(geo, mat); ctx.scene.add(points)
 *
 * Per-frame update:
 *   - frame++
 *   - uniforms.uTime.value = (frame * phase_omega_per_frame) % (2π)
 *     // Wrap is REQUIRED for shader precision — see comment in update()
 *     // below. Mathematically exact (sin is 2π-periodic).
 *   - uniforms.uModulator.value = resolveModulator(ctx, payload.modulator)
 *     // D-modulator (spec §3.8). When ctx.modulators getter returns null/
 *     // absent (current state until A7), defaults to 1.0 — per-particle
 *     // shader twinkle is the sole motion.
 *
 * Dispose:
 *   - ctx.scene.remove(points)
 *   - geometry.dispose() — covers both position + phase BufferAttributes
 *   - material.dispose() — disposes the ShaderMaterial (drops shader
 *     program references)
 */
function handlePointCloud3d(anchor, ctx) {
  const payload = anchor.payload;
  const THREE = window.THREE;
  if (!THREE) {
    console.warn('particle-3d: window.THREE not loaded (r128 CDN script tag missing?)');
    return { update: () => {}, dispose: () => {} };
  }

  const count = payload.count;
  const twinkle = payload.twinkle;
  const modulatorBinding = payload.modulator;
  const TWO_PI = 2 * Math.PI;

  let _disposed = false;
  let frame = 0;

  // Build per-vertex position + phase arrays.
  const positions = new Float32Array(count * 3);
  const phases    = new Float32Array(count);
  const PI = Math.PI;
  for (let i = 0; i < count; i++) {
    // phi from normalized range × π — source 2867: (rand*0.7 + 0.15) * π
    const phi = randIn(payload.phi_norm_range[0], payload.phi_norm_range[1]) * PI;
    const theta = randIn(payload.theta_range[0], payload.theta_range[1]);
    const r = randIn(payload.r_range[0], payload.r_range[1]);
    positions[i * 3]     = r * Math.sin(phi) * Math.cos(theta);
    // y-flatten — source 2871: r * cos(phi) * 0.4 - 80
    positions[i * 3 + 1] = r * Math.cos(phi) * payload.y_flatten_factor + payload.y_offset;
    positions[i * 3 + 2] = r * Math.sin(phi) * Math.sin(theta);
    // D-twinkle per-vertex phase — source 2868 (dead-code intent completed by A4b)
    phases[i] = twinkle.phase_init === 'random-2pi'
      ? Math.random() * PI * 2
      : 0;
  }

  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geometry.setAttribute('phase',    new THREE.BufferAttribute(phases, 1));

  // Custom ShaderMaterial per spec §3.7. transparent + depthWrite
  // set directly (uniforms can't carry them per r128 compat note).
  const uniforms = {
    uColor:           { value: new THREE.Color(payload.color) },
    uBaseOpacity:     { value: payload.base_opacity },
    uTime:            { value: 0 },
    uModulator:       { value: 1.0 },
    uAlphaCenter:     { value: twinkle.alpha_center },
    uAlphaSwing:      { value: twinkle.alpha_swing },
    uSize:            { value: payload.sprite_size },
    uSizeAttenuation: { value: payload.size_attenuation ? 1.0 : 0.0 },
  };
  const material = new THREE.ShaderMaterial({
    uniforms,
    vertexShader:   POINT_CLOUD_3D_VERTEX_SHADER,
    fragmentShader: POINT_CLOUD_3D_FRAGMENT_SHADER,
    transparent:    payload.transparent,
    depthWrite:     payload.depth_write,
  });

  const points = new THREE.Points(geometry, material);
  ctx.scene.add(points);

  function update(/* now */) {
    if (_disposed) return;
    frame++;
    // Advance uTime by phase_omega_per_frame each frame, WRAPPED
    // MODULO 2π. The wrap is REQUIRED, not cosmetic — GLSL fragment
    // shaders default to mediump precision on much hardware, and an
    // unbounded uTime accumulator inside sin(vPhase + uTime) loses
    // precision within minutes (twinkle goes choppy then freezes).
    // sin() is 2π-periodic so the wrap is mathematically exact —
    // DO NOT "simplify" it away.
    //
    // Matches source's sin(frame * 0.04) coefficient byte-for-byte
    // (phase_omega_per_frame = 0.04); the source escapes the
    // precision cliff because Math.sin runs on CPU in double
    // precision. Moving sin into the shader introduces this risk.
    // With per-particle vPhase attribute (also in [0, 2π)), the
    // shader's sin argument stays bounded in [0, 4π).
    uniforms.uTime.value = (frame * twinkle.phase_omega_per_frame) % TWO_PI;
    // D-modulator value resolution (spec §3.8). Default 1.0 keeps
    // the shader-twinkle as the sole motion until A7's driver
    // registry resolves real values.
    uniforms.uModulator.value = resolveModulator(ctx, modulatorBinding);
  }

  function dispose() {
    if (_disposed) return;
    _disposed = true;
    ctx.scene.remove(points);
    geometry.dispose();
    material.dispose();
  }

  return { update, dispose };
}


// ─────────────────────────────────────────────────────────────────────────
// SECTION 4 — handleVolumetric3d (spec §2.7, source 2946-2974 + 3005-3022)
// ─────────────────────────────────────────────────────────────────────────

/**
 * Speakeasy volumetric-3d handler. Constructs N independent
 * THREE.Mesh instances sharing ONE SphereGeometry (per
 * payload.sphere_geometry.shared = true — source line 2950:
 * `const smokeGeo = new THREE.SphereGeometry(1, 6, 6)` instantiated
 * once outside the per-mesh loop). Each mesh gets its OWN
 * MeshBasicMaterial (per-particle opacity), per-instance scale, and
 * per-instance userData carrying velocity (vy/vx/vz), life counter,
 * and maxOpacity (the spawn-time opacity that the life-cycle modulates).
 *
 * The phi-range asymmetry (spec §2.7 + db/038 NOTE) is preserved
 * byte-faithfully: initial spawn uses spawn_region_initial.phi_norm_range
 * (source 2961: [0.4, 0.9]); respawn uses spawn_region_respawn.phi_norm_range
 * (source 3018: [0.55, 0.9]). The respawn region is narrower — avoids
 * the lower edge where freshly-spawned particles would collide with
 * already-rising ones. NOT a bug, NOT a normalization — source-faithful.
 *
 * Build (lines 2946-2974):
 *   - Shared geometry: new THREE.SphereGeometry(
 *       payload.sphere_geometry.radius,         // source: 1
 *       payload.sphere_geometry.width_segments, // source: 6
 *       payload.sphere_geometry.height_segments // source: 6
 *     )
 *   - For each i in [0, count):
 *       scale     = randIn(scale_range[0], scale_range[1])           // source 2952: 15 + rand*40
 *       opacity0  = randIn(opacity_range[0], opacity_range[1])       // source 2955: rand*0.04 + 0.01
 *       mat       = new THREE.MeshBasicMaterial({
 *         color:       new THREE.Color(payload.color),               // source: 0xbbbbaa
 *         transparent: payload.transparent,                          // source: true
 *         opacity:     opacity0,
 *         depthWrite:  payload.depth_write,                          // source: false
 *       })
 *       mesh      = new THREE.Mesh(sharedGeo, mat)
 *       Initial position from spawn_region_initial (source 2960-2964):
 *         r     = randIn(spawn_region_initial.r_range[0..1])        // source: 50 + rand*300
 *         phi   = randIn(spawn_region_initial.phi_norm_range[0..1]) * π
 *                 // source 2961: (0.4 + rand*0.5) * π
 *         theta = randIn(spawn_region_initial.theta_range[0..1])
 *                 // source 2962: rand * 2π
 *         x = r * sin(phi) * cos(theta)
 *         y = r * cos(phi) * y_flatten_factor + y_offset
 *             // source 2965: cos(phi)*0.5 - 30
 *         z = r * sin(phi) * sin(theta)
 *       mesh.scale.setScalar(scale)
 *       mesh.userData = {
 *         vy:         randIn(vy_range[0], vy_range[1]),              // source 2967: 0.08 + rand*0.12
 *         vx:         randIn(vx_range[0], vx_range[1]),              // source 2968: (rand-0.5)*0.05
 *         vz:         randIn(vz_range[0], vz_range[1]),              // source 2969: (rand-0.5)*0.05
 *         life:       randIn(life_init_range[0], life_init_range[1]),// source 2970: rand
 *         maxOpacity: opacity0,
 *       }
 *       ctx.scene.add(mesh)
 *
 * Per-frame update (lines 3005-3022):
 *   For each mesh:
 *     mesh.position.y += mesh.userData.vy
 *     mesh.position.x += mesh.userData.vx
 *     mesh.position.z += mesh.userData.vz
 *     mesh.userData.life += payload.life_increment_per_frame  // source: 0.003
 *     t = mesh.userData.life % 1
 *     mesh.material.opacity = mesh.userData.maxOpacity * sin(t * π)
 *       // opacity_curve = "sin_pi" — source 3013: maxOpacity * Math.sin(t * π)
 *     if (payload.respawn && t > payload.respawn_threshold) {
 *       // Respawn at spawn_region_respawn (the NARROWER region):
 *       r     = randIn(spawn_region_respawn.r_range)
 *       phi   = randIn(spawn_region_respawn.phi_norm_range) * π
 *               // source 3018: (0.55 + rand*0.35) * π — [0.55, 0.9], narrower than initial [0.4, 0.9]
 *       theta = randIn(spawn_region_respawn.theta_range)
 *       mesh.position.set(spherical to cartesian, with same y-flatten)
 *       mesh.userData.life = randIn(0, 0.1) — source 3027: rand * 0.1
 *     }
 *
 * Dispose (mirrors source 3030-3033 with a cleanup refinement):
 *   - For each mesh: ctx.scene.remove(mesh); mesh.material.dispose()
 *   - sharedGeo.dispose() — ONCE at the end (source loops per-mesh
 *     geometry.dispose() which is idempotent-redundant on a shared
 *     geometry; the renderer's cleaner pattern disposes once)
 */
function handleVolumetric3d(anchor, ctx) {
  const payload = anchor.payload;
  const THREE = window.THREE;
  if (!THREE) {
    console.warn('particle-3d: window.THREE not loaded (r128 CDN script tag missing?)');
    return { update: () => {}, dispose: () => {} };
  }

  const count = payload.count;
  const PI = Math.PI;
  const spawnInitial = payload.spawn_region_initial;
  const spawnRespawn = payload.spawn_region_respawn;
  const yFlatten = payload.y_flatten_factor;
  const yOffset  = payload.y_offset;
  const sphereGeo = payload.sphere_geometry;

  let _disposed = false;
  const meshes = [];

  // Shared geometry — instantiated ONCE (source line 2950).
  const sharedGeo = new THREE.SphereGeometry(
    sphereGeo.radius,
    sphereGeo.width_segments,
    sphereGeo.height_segments
  );

  /**
   * Internal helper: compute cartesian (x, y, z) from a spawn region's
   * (r, phi_norm, theta) ranges, applying the y-flatten formula. Used
   * for both initial spawn and respawn paths so the asymmetry only
   * lives in the caller's `region` argument choice.
   */
  function spawnPositionInRegion(region) {
    const r = randIn(region.r_range[0], region.r_range[1]);
    const phi = randIn(region.phi_norm_range[0], region.phi_norm_range[1]) * PI;
    const theta = randIn(region.theta_range[0], region.theta_range[1]);
    return {
      x: r * Math.sin(phi) * Math.cos(theta),
      y: r * Math.cos(phi) * yFlatten + yOffset,
      z: r * Math.sin(phi) * Math.sin(theta),
    };
  }

  // Build per-instance meshes (each with own material).
  for (let i = 0; i < count; i++) {
    const scale = randIn(payload.scale_range[0], payload.scale_range[1]);
    const opacity0 = randIn(payload.opacity_range[0], payload.opacity_range[1]);

    const material = new THREE.MeshBasicMaterial({
      color:       new THREE.Color(payload.color),
      transparent: payload.transparent,
      opacity:     opacity0,
      depthWrite:  payload.depth_write,
    });

    const mesh = new THREE.Mesh(sharedGeo, material);

    // Initial position from spawn_region_initial (wider phi range).
    const pos = spawnPositionInRegion(spawnInitial);
    mesh.position.set(pos.x, pos.y, pos.z);
    mesh.scale.setScalar(scale);

    // Per-instance internal state. maxOpacity captures the spawn-time
    // opacity that the sin(life * π) life-cycle curve modulates against.
    mesh.userData = {
      vy:         randIn(payload.vy_range[0], payload.vy_range[1]),
      vx:         randIn(payload.vx_range[0], payload.vx_range[1]),
      vz:         randIn(payload.vz_range[0], payload.vz_range[1]),
      life:       randIn(payload.life_init_range[0], payload.life_init_range[1]),
      maxOpacity: opacity0,
    };

    ctx.scene.add(mesh);
    meshes.push(mesh);
  }

  function update(/* now */) {
    if (_disposed) return;
    for (let i = 0; i < count; i++) {
      const mesh = meshes[i];
      const ud = mesh.userData;
      mesh.position.x += ud.vx;
      mesh.position.y += ud.vy;
      mesh.position.z += ud.vz;
      ud.life += payload.life_increment_per_frame;
      const t = ud.life % 1;
      // opacity_curve "sin_pi" — source 3013: maxOpacity * sin(t * π)
      mesh.material.opacity = ud.maxOpacity * Math.sin(t * PI);
      // Respawn at the NARROWER spawn region per spec §2.7 asymmetry.
      if (payload.respawn && t > payload.respawn_threshold) {
        const pos = spawnPositionInRegion(spawnRespawn);
        mesh.position.set(pos.x, pos.y, pos.z);
        // Source 3027: life = rand * 0.1 — restart in the early
        // fade-in band so the just-respawned mesh isn't visible mid-fade.
        ud.life = Math.random() * 0.1;
      }
    }
  }

  function dispose() {
    if (_disposed) return;
    _disposed = true;
    // Remove all meshes + dispose their individual materials.
    for (const mesh of meshes) {
      ctx.scene.remove(mesh);
      mesh.material.dispose();
      // NOTE: NOT disposing mesh.geometry — it's the shared sharedGeo.
      // Cleaner than source's per-mesh geometry.dispose() loop which
      // calls dispose() N times on the same geometry (idempotent but
      // redundant).
    }
    meshes.length = 0;
    // Shared geometry disposed ONCE at the end.
    sharedGeo.dispose();
  }

  return { update, dispose };
}


// ─────────────────────────────────────────────────────────────────────────
// SECTION 5 — Entry dispatcher + registration
// ─────────────────────────────────────────────────────────────────────────

/**
 * The 3D-particle renderer entry point. Receives a venue_anchors row
 * (anchor) and a ctx carrying at least { scene }. Dispatches on
 * payload.context (must be '3d-three' for this module), then on
 * payload.kind. Returns { update, dispose } per D-contract.
 *
 * Fail-loud/fail-safe posture (mirrors A4a spotlight.js §1.7/§1.8 +
 * Gate 2 spotlight-3d.js): unknown context, unknown kind, missing
 * payload, missing scene, missing THREE — all console.warn + return
 * a no-op { update: () => {}, dispose: () => {} } handle so the
 * caller's RAF loop and teardown sequence stay safe.
 */
function particleAnchor3dRenderer(anchor, ctx) {
  const payload = anchor && anchor.payload;
  if (!payload) {
    console.warn('particle-3d: anchor missing payload', anchor);
    return { update: () => {}, dispose: () => {} };
  }
  if (!ctx || !ctx.scene) {
    console.warn('particle-3d: ctx.scene required for 3d-three dispatch');
    return { update: () => {}, dispose: () => {} };
  }

  // Context dispatch — this module accepts only "3d-three".
  // "2d-canvas" anchors route to particle.js (A3). Anything else is
  // a malformed payload.
  if (payload.context !== '3d-three') {
    console.warn(
      `particle-3d: unsupported context "${payload.context}". ` +
      `This module accepts only "3d-three"; "2d-canvas" anchors ` +
      `should route to particle.js (A3) via the registry's ` +
      `context-aware dispatch.`
    );
    return { update: () => {}, dispose: () => {} };
  }

  // Kind dispatch — A4b accepts the 2 kinds below.
  switch (payload.kind) {
    case 'point-cloud-3d': return handlePointCloud3d(anchor, ctx);
    case 'volumetric-3d':  return handleVolumetric3d(anchor, ctx);
    default:
      console.warn(
        `particle-3d: unsupported kind "${payload.kind}". ` +
        `A4b 3D particle kinds: point-cloud-3d, volumetric-3d. ` +
        `A3 2D kinds (point-cloud, directional-emitter, volumetric) ` +
        `route to particle.js, not this module.`
      );
      return { update: () => {}, dispose: () => {} };
  }
}

// Register under DISTINCT KEY 'particle-3d' per Gate 5 decision
// (2026-05-28). A3's particle.js:636 already registered
// ('particle', particleAnchorRenderer); using a distinct key here
// avoids the F3 clobber risk (registry's "warn + replace" semantics
// at shell/venue-registry.js:172-179). Both registrations coexist
// cleanly — the registry's Map holds two independent entries.
//
// Consumers:
//   - Admin preview (today): reads via window.elsewhere.particle3dRenderer
//     in SECTION 6 below — does NOT use the registry.
//   - Stage A7 karaoke read-path (future): derives lookup key as
//     `anchor.payload.context === '3d-three' ? anchor.type + '-3d' : anchor.type`
//     and calls getAnchorRenderer(lookupKey). A 3d-three particle
//     anchor routes here; a 2d-canvas particle anchor routes to
//     A3's particle.js. Note: `anchor.type` is the venue_anchors
//     COLUMN value (set by db/038's INSERT, e.g. 'particle') —
//     NOT `payload.type` (which is undefined for spotlight/particle
//     payloads; payload.type exists only on audio payloads as a
//     format discriminator, a naming-collision artifact).
//
// db/032's venue_anchors_type_check vocabulary unchanged — the
// '-3d' suffix is registry-key only, not a DB type. See spec
// §4.1 + §0.3 D-dispatch row for the full rationale.
registerAnchorRenderer('particle-3d', particleAnchor3dRenderer);


// ─────────────────────────────────────────────────────────────────────────
// SECTION 6 — window.elsewhere.particle3dRenderer publication (spec §4.3)
// ─────────────────────────────────────────────────────────────────────────
// Matches A2 audio.js / A3 particle.js / A4a spotlight.js / Gate 2
// spotlight-3d.js publication pattern — exposes the renderer entry
// point on window.elsewhere.particle3dRenderer for the admin
// preview's direct lookup at admin-venues.html (spec §6.4 per-anchor
// preview uses
// window.elsewhere?.particle3dRenderer?.particleAnchor3dRenderer?.()
// to instantiate the renderer per row).
// Per CLAUDE.md "No build step" — inline scripts assume globals.

if (typeof window !== 'undefined') {
  window.elsewhere = window.elsewhere || {};
  window.elsewhere.particle3dRenderer = { particleAnchor3dRenderer };
}
