// shell/venue-renderers/spotlight-3d.js
//
// 3D spotlight anchor renderer for the Venue Admin UI Stage A4b
// workstream. Sibling to A4a's shell/venue-renderers/spotlight.js
// (D-files-spot per spec docs/VENUE-ADMIN-UI-A4B-BUILD-SPEC.md §0.3) —
// NOT an extension of that file. 2D and 3D rendering share only the
// payload contract + kind dispatch; the underlying APIs are disjoint
// (canvas 2D vs Three.js WebGL).
//
// Registered to shell/venue-registry.js's anchor renderer registry
// at module load time under the DISTINCT KEY 'spotlight-3d' (NOT
// 'spotlight' — that key is owned by A4a's spotlight.js:830 for
// the 2D-canvas path). Distinct keys avoid the F3 clobber risk
// surfaced at Gate 2 (2026-05-28): the registry's current API is
// keyed by `type` alone with no context discriminator, so calling
// registerAnchorRenderer('spotlight', ...) from this module would
// REPLACE A4a's registration via the "warn + replace" semantics at
// shell/venue-registry.js:172-179. By using 'spotlight-3d' as a
// distinct key, both registrations coexist cleanly:
//   getAnchorRenderer('spotlight')    → A4a's 2D function (unchanged)
//   getAnchorRenderer('spotlight-3d') → this module's 3D function
//
// Gate 5 design choice (2026-05-28): distinct-keys over the spec
// §4.1-originally-locked context-aware registry extension. Rationale:
// only ONE future consumer reads from the registry (Stage A7's
// karaoke read-path switch); the admin preview reads via
// window.elsewhere globals (SECTION 5 below), NOT the registry.
// Extending register+get+all-callsites to support a {context} 3rd
// arg is over-engineered for a single future caller. The A7 read-
// path will derive the lookup key from the venue_anchors row as
//   key = anchor.payload.context === '3d-three' ? anchor.type + '-3d' : anchor.type
// — using `anchor.type` (the venue_anchors COLUMN value set by
// db/038's INSERT, e.g. 'spotlight') NOT `payload.type` (which is
// undefined for spotlight/particle payloads; `payload.type` exists
// only on audio payloads as a format discriminator, a naming-
// collision artifact verified pre-edit). The DB `type` column at
// public.venue_anchors stays 'spotlight' (db/032's
// venue_anchors_type_check vocabulary unchanged) — the '-3d' suffix
// is a renderer-registry-key derivation only, not a schema-level
// type. Spec §4.1 + §0.3 D-dispatch row amended to reflect this
// resolution; see Gate 5 commit cluster.
//
// Two kinds dispatched on payload.kind (spec §1.1):
//   • swept-beam-3d — N THREE.CylinderGeometry cone meshes pivoting
//                     near a sphere of radius `sphere_radius`,
//                     counter-rotating per per-cone angular speed,
//                     phi wobble via sin(frame * wobble_speed) *
//                     wobble_amplitude. Stadium 4-cone case is
//                     canonical (see db/038 anc_spot_stadium_beams3d).
//                     Source: karaoke/stage.html:2884-2935 (build) +
//                     2924-2933 (update).
//   • point-light   — N sprite Points on a flat ring (r ∈ r_range,
//                     y ∈ y_range, theta ∈ theta_range) with a
//                     SHARED THREE.PointsMaterial whose opacity
//                     flickers globally every flicker.frame_period
//                     frames. Speakeasy 40-candle case is canonical
//                     (see db/038 anc_spot_speakeasy_candles).
//                     Source: karaoke/stage.html:2980-3000 (build) +
//                     3024-3026 (update).
//
// ctx contract (spec §5.1):
//   ctx.scene       — THREE.Scene the caller owns; renderer attaches
//                     its meshes via ctx.scene.add(...). Renderer
//                     does NOT create its own scene/renderer/camera
//                     — that's the admin preview surface's job
//                     (spec §5.3). Karaoke's eventual A7 read-path
//                     switch will pass the existing panScene here.
//   ctx.camera      — THREE.PerspectiveCamera. Read-only from this
//                     module's perspective. Reserved for future
//                     camera-aware kinds; A4b's two kinds don't
//                     read it.
//   ctx.modulators? — optional. Not used by either A4b spotlight
//                     kind (modulators are particle-3d.js's
//                     concern — only point-cloud-3d binds
//                     crowd_brightness per spec D-modulator).
//                     Reserved for future spotlight modulators.
//
// {update, dispose} contract (D-contract, spec §3.3):
//   update(now)  — call per RAF tick. Mutates scene-object
//                  transforms/opacities. Does NOT call
//                  renderer.render() — the caller owns rendering.
//                  Internal _disposed flag is checked first; if set,
//                  the call is a no-op. This is the defense-in-depth
//                  pair to the admin RAF callback's st.disposed
//                  guard (spec §5.6) — either guard alone makes an
//                  in-flight frame after teardown safe.
//                  The `now` argument is accepted per spec §3.3 but
//                  IGNORED by both A4b spotlight kinds — they use an
//                  internal frame counter to match source motion
//                  math byte-for-byte (source uses frame counter,
//                  not wall-clock; see swept-beam-3d "Motion model"
//                  note below). Frame-rate dependence is a known
//                  property — accuracy verification at A7 per
//                  D-a7 item 1.
//   dispose()    — removes attached scene objects, disposes
//                  geometries + materials, sets _disposed = true.
//                  Idempotent. Defense-in-depth: a late update()
//                  call after dispose() is a no-op via the
//                  _disposed guard.
//
// Caller-owns-RAF (D-raf, spec §3.4): this renderer does NOT own a
// requestAnimationFrame loop. The admin preview's tickPreview3d
// (spec §5.5) owns the RAF and calls update(now) per frame, then
// calls renderer.render(scene, camera). Karaoke's A7 read-path
// switch will integrate analogously into the renderLoop at
// karaoke/stage.html:4012-4052.
//
// Modulators (spec D5 + A4a precedent): NONE for A4b spotlight
// kinds. swept-beam-3d uses per-cone frame-counter motion; point-
// light uses global-sync random flicker. Neither reads external
// scalars. The crowd_brightness modulator binding shipped in db/038
// is on the particle-3d anchor (anc_par_stadium_phonelights3d only)
// — handled by shell/venue-renderers/particle-3d.js, not this
// module.
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
//     §2.4 (swept-beam-3d schema + fidelity table), §2.5 (point-light
//     schema + fidelity table), §3 (renderer design), §4 (registry
//     dispatch), §5 (admin preview surface).
//   • shell/venue-renderers/spotlight.js — A4a 2D-canvas sibling;
//     this module mirrors its overall shape (header, handlers,
//     dispatcher, window publication). The registration call at
//     spotlight.js:830 is what this module deliberately does NOT
//     mirror until Gate 5.
//   • db/038_3d_anchor_seed.sql — the 2 spotlight anchor seeds this
//     renderer animates.
//   • karaoke/stage.html:2884-2935 (swept-beam-3d source) +
//     2980-3000 + 3024-3026 (point-light source).

import { registerAnchorRenderer } from '../venue-registry.js';


// ─────────────────────────────────────────────────────────────────────────
// SECTION 1 — Small helpers
// ─────────────────────────────────────────────────────────────────────────

/**
 * Uniform [min, max] random. Used for point-light spatial layout
 * (r/theta/y per-particle) + flicker opacity targets. Centralized so
 * the rand source is replaceable for deterministic preview testing
 * later (not in A4b scope).
 */
function randIn(min, max) {
  return min + Math.random() * (max - min);
}

/**
 * Map payload's string `side` value to THREE's numeric constant.
 * swept-beam-3d uses "back" (renders the INSIDE of the cone — the
 * light-beam-from-outside effect per source line 2896: `side:
 * THREE.BackSide`). Unknown side values fall back to FrontSide
 * with a warn (fail-loud/fail-safe posture matching the dispatcher).
 */
function mapSide(sideStr) {
  switch (sideStr) {
    case 'back':   return window.THREE.BackSide;
    case 'front':  return window.THREE.FrontSide;
    case 'double': return window.THREE.DoubleSide;
    default:
      console.warn(
        `spotlight-3d: unknown material.side "${sideStr}", ` +
        `falling back to FrontSide. Known: back, front, double.`
      );
      return window.THREE.FrontSide;
  }
}


// ─────────────────────────────────────────────────────────────────────────
// SECTION 2 — handleSweptBeam3d (spec §2.4, source 2884-2935)
// ─────────────────────────────────────────────────────────────────────────

/**
 * Stadium swept-beam-3d handler. Constructs `count` cone meshes from
 * per-item arrays (phis, theta_init, colors, speeds) + shared
 * geometry/material payloads. Each cone:
 *   - Geometry: THREE.CylinderGeometry with payload.geometry fields
 *     (radius_top, radius_bottom, height, radial_segments,
 *     height_segments, open_ended). Pre-translated by
 *     (0, geometry.translate_y, 0) to move the pivot to the cone's
 *     top point — source line 2893: `geo.translate(0, -150, 0)`.
 *   - Material: THREE.MeshBasicMaterial with per-cone color +
 *     shared opacity/side/depth_write/transparent. side='back'
 *     renders the inner cone surface (light-beam-from-outside).
 *   - Initial position: spherical-to-cartesian on a sphere of
 *     radius `sphere_radius` at (phi=phis[i], theta=theta_init[i]).
 *     Source convention (lines 2904-2908):
 *       x = r * sin(phi) * cos(theta)
 *       y = r * cos(phi)
 *       z = r * sin(phi) * sin(theta)
 *   - Initial orientation: cone.lookAt(look_at[0..2]) — aims the
 *     cone toward the scene origin (or wherever look_at points).
 *
 * Per-frame update (lines 2924-2933, reproduced byte-for-byte):
 *   - cone.userData.angle += speeds[i]       (continuous angular drift)
 *   - phi_active = phis[i] + sin(frame * wobble_speed) * wobble_amplitude
 *     (slow vertical sway — source: `sd.phi + Math.sin(frame * 0.01) * 0.08`)
 *   - theta_active = cone.userData.angle
 *   - Position recomputed from (sphere_radius, phi_active, theta_active)
 *   - cone.lookAt(look_at[0..2]) (re-aim — needed because position changed)
 *
 * Motion model is FRAME-COUNTER based, not wall-clock. Source uses a
 * frame counter incremented each render tick; this renderer mirrors
 * via internal `frame` variable incremented in update(). The `now`
 * argument to update() is IGNORED — accepted per spec §3.3 contract
 * but not consumed. Frame-rate dependence is a documented property;
 * A7's read-path switch is the first prod exercise where the
 * difference vs the source's render loop becomes observable (D-a7
 * item 1, captured in DEFERRED-c).
 */
function handleSweptBeam3d(anchor, ctx) {
  const payload = anchor.payload;
  const THREE = window.THREE;
  if (!THREE) {
    console.warn('spotlight-3d: window.THREE not loaded (r128 CDN script tag missing?)');
    return { update: () => {}, dispose: () => {} };
  }

  const count = payload.count;
  const geom = payload.geometry;
  const mat  = payload.material;
  const lookAt = payload.look_at;

  let _disposed = false;
  let frame = 0;
  const cones = [];

  // Build per-cone meshes from per-item arrays + shared geometry/material.
  for (let i = 0; i < count; i++) {
    const geo = new THREE.CylinderGeometry(
      geom.radius_top,
      geom.radius_bottom,
      geom.height,
      geom.radial_segments,
      geom.height_segments,
      geom.open_ended
    );
    geo.translate(0, geom.translate_y, 0);   // pivot at top (source line 2893)

    const meshMat = new THREE.MeshBasicMaterial({
      color:       new THREE.Color(payload.colors[i]),
      transparent: mat.transparent,
      opacity:     mat.opacity,
      side:        mapSide(mat.side),
      depthWrite:  mat.depth_write,
    });

    const cone = new THREE.Mesh(geo, meshMat);

    // Initial position on sphere of payload.sphere_radius at
    // (phi=phis[i], theta=theta_init[i]).
    const r0 = payload.sphere_radius;
    const phi0 = payload.phis[i];
    const theta0 = payload.theta_init[i];
    cone.position.set(
      r0 * Math.sin(phi0) * Math.cos(theta0),
      r0 * Math.cos(phi0),
      r0 * Math.sin(phi0) * Math.sin(theta0)
    );
    cone.lookAt(lookAt[0], lookAt[1], lookAt[2]);

    // Per-cone runtime state: angle drifts via speeds[i], starts at
    // theta_init[i] (matches source userData = {speed, angle: sd.theta}
    // at line 2909).
    cone.userData = {
      speed: payload.speeds[i],
      angle: theta0,
    };

    ctx.scene.add(cone);
    cones.push(cone);
  }

  function update(/* now */) {
    if (_disposed) return;
    frame++;
    const r = payload.sphere_radius;
    const wobblePhase = frame * payload.wobble_speed;
    const wobbleOffset = Math.sin(wobblePhase) * payload.wobble_amplitude;
    for (let i = 0; i < count; i++) {
      const cone = cones[i];
      cone.userData.angle += cone.userData.speed;
      const phiActive = payload.phis[i] + wobbleOffset;
      const thetaActive = cone.userData.angle;
      cone.position.set(
        r * Math.sin(phiActive) * Math.cos(thetaActive),
        r * Math.cos(phiActive),
        r * Math.sin(phiActive) * Math.sin(thetaActive)
      );
      cone.lookAt(lookAt[0], lookAt[1], lookAt[2]);
    }
  }

  function dispose() {
    if (_disposed) return;
    _disposed = true;
    for (const cone of cones) {
      ctx.scene.remove(cone);
      cone.geometry.dispose();
      cone.material.dispose();
    }
    cones.length = 0;
  }

  return { update, dispose };
}


// ─────────────────────────────────────────────────────────────────────────
// SECTION 3 — handlePointLight (spec §2.5, source 2980-3000 + 3024-3026)
// ─────────────────────────────────────────────────────────────────────────

/**
 * Speakeasy point-light handler. Constructs ONE THREE.Points instance
 * holding `count` vertices on a flat ring + ONE shared
 * THREE.PointsMaterial. The shared material is the load-bearing
 * detail — per-particle independent flicker would require a per-
 * vertex opacity attribute (like A4b's particle-3d.js point-cloud-3d
 * does via custom ShaderMaterial). The source DOESN'T do that here;
 * all 40 candles flicker in lockstep via a single shared
 * material.opacity write per N frames. A4b reproduces source
 * semantics exactly — this is a deliberate asymmetry vs
 * point-cloud-3d (spec §2.5 Motion model note + spec §3.7
 * D-twinkle commentary explaining why phone-lights got the shader
 * upgrade while candles didn't: the source's `phases` dead-code in
 * the phone-lights builder proves per-particle intent there; no such
 * evidence in the candles builder).
 *
 * Build (lines 2980-2999):
 *   - new THREE.BufferGeometry()
 *   - Per-vertex position via Float32Array(count * 3):
 *       r     = randIn(r_range[0], r_range[1])       // line 2986: 80 + rand*250
 *       theta = randIn(theta_range[0], theta_range[1]) // line 2987: rand * 2π
 *       y     = randIn(y_range[0], y_range[1])       // line 2988: -80 - rand*40
 *       x = r * cos(theta)                            // line 2987
 *       z = r * sin(theta)                            // line 2989
 *     Note: this is a FLAT RING in xz-plane at variable y, NOT a
 *     sphere (no phi). Spec §2.5 calls position_layout: "ring" to
 *     name this; the renderer doesn't read the field (purely
 *     descriptive), but the field documents the layout.
 *   - geometry.setAttribute('position', new BufferAttribute(pos, 3))
 *   - new THREE.PointsMaterial({color, size, sizeAttenuation,
 *     transparent, opacity: base_opacity, depthWrite})
 *   - new THREE.Points(geo, mat); ctx.scene.add(points)
 *
 * Per-frame update (lines 3024-3026, reproduced byte-for-byte):
 *   if (frame % flicker.frame_period === 0) {
 *     pointsMaterial.opacity = randIn(flicker.opacity_min, flicker.opacity_max);
 *   }
 * Global sync — all 40 candles share the material so all 40 flicker
 * to the same opacity value each tick. Source-faithful.
 */
function handlePointLight(anchor, ctx) {
  const payload = anchor.payload;
  const THREE = window.THREE;
  if (!THREE) {
    console.warn('spotlight-3d: window.THREE not loaded (r128 CDN script tag missing?)');
    return { update: () => {}, dispose: () => {} };
  }

  const count = payload.count;
  const flicker = payload.flicker;

  let _disposed = false;
  let frame = 0;

  // Build per-vertex positions on a flat ring at variable y.
  const positions = new Float32Array(count * 3);
  for (let i = 0; i < count; i++) {
    const r = randIn(payload.r_range[0], payload.r_range[1]);
    const theta = randIn(payload.theta_range[0], payload.theta_range[1]);
    positions[i * 3]     = r * Math.cos(theta);
    positions[i * 3 + 1] = randIn(payload.y_range[0], payload.y_range[1]);
    positions[i * 3 + 2] = r * Math.sin(theta);
  }

  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));

  const material = new THREE.PointsMaterial({
    color:            new THREE.Color(payload.color),
    size:             payload.sprite_size,
    sizeAttenuation:  payload.size_attenuation,
    transparent:      payload.transparent,
    opacity:          payload.base_opacity,
    depthWrite:       payload.depth_write,
  });

  const points = new THREE.Points(geometry, material);
  ctx.scene.add(points);

  function update(/* now */) {
    if (_disposed) return;
    frame++;
    if (frame % flicker.frame_period === 0) {
      material.opacity = randIn(flicker.opacity_min, flicker.opacity_max);
    }
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
// SECTION 4 — Entry dispatcher + registration
// ─────────────────────────────────────────────────────────────────────────

/**
 * The 3D-spotlight renderer entry point. Receives a venue_anchors
 * row (anchor) and a ctx carrying at least { scene }. Dispatches on
 * payload.context (must be '3d-three' for this module), then on
 * payload.kind. Returns { update, dispose } per D-contract.
 *
 * Fail-loud/fail-safe posture (mirrors A4a spotlight.js §1.7/§1.8):
 * unknown context, unknown kind, missing payload, missing scene,
 * missing THREE — all console.warn + return a no-op
 * { update: () => {}, dispose: () => {} } handle so the caller's
 * RAF loop and teardown sequence stay safe.
 */
function spotlightAnchor3dRenderer(anchor, ctx) {
  const payload = anchor && anchor.payload;
  if (!payload) {
    console.warn('spotlight-3d: anchor missing payload', anchor);
    return { update: () => {}, dispose: () => {} };
  }
  if (!ctx || !ctx.scene) {
    console.warn('spotlight-3d: ctx.scene required for 3d-three dispatch');
    return { update: () => {}, dispose: () => {} };
  }

  // Context dispatch — this module accepts only "3d-three".
  // "2d-canvas" anchors route to spotlight.js (A4a). Anything else
  // is a malformed payload.
  if (payload.context !== '3d-three') {
    console.warn(
      `spotlight-3d: unsupported context "${payload.context}". ` +
      `This module accepts only "3d-three"; "2d-canvas" anchors ` +
      `should route to spotlight.js (A4a) via the registry's ` +
      `context-aware dispatch.`
    );
    return { update: () => {}, dispose: () => {} };
  }

  // Kind dispatch — A4b accepts the 2 kinds below.
  switch (payload.kind) {
    case 'swept-beam-3d': return handleSweptBeam3d(anchor, ctx);
    case 'point-light':   return handlePointLight(anchor, ctx);
    default:
      console.warn(
        `spotlight-3d: unsupported kind "${payload.kind}". ` +
        `A4b 3D spotlight kinds: swept-beam-3d, point-light. ` +
        `A4a 2D kinds (swept-beam-2d, pulsed-laser, light-shaft) ` +
        `route to spotlight.js, not this module.`
      );
      return { update: () => {}, dispose: () => {} };
  }
}

// Register under DISTINCT KEY 'spotlight-3d' per Gate 5 decision
// (2026-05-28). A4a's spotlight.js:830 already registered
// ('spotlight', spotlightAnchorRenderer); using a distinct key here
// avoids the F3 clobber risk (registry's "warn + replace" semantics
// at shell/venue-registry.js:172-179). Both registrations coexist
// cleanly — the registry's Map holds two independent entries.
//
// Consumers:
//   - Admin preview (today): reads via window.elsewhere.spotlight3dRenderer
//     in SECTION 5 below — does NOT use the registry.
//   - Stage A7 karaoke read-path (future): derives lookup key as
//     `anchor.payload.context === '3d-three' ? anchor.type + '-3d' : anchor.type`
//     and calls getAnchorRenderer(lookupKey). A 3d-three spotlight
//     anchor routes here; a 2d-canvas spotlight anchor routes to
//     A4a's spotlight.js. Note: `anchor.type` is the venue_anchors
//     COLUMN value (set by db/038's INSERT, e.g. 'spotlight') —
//     NOT `payload.type` (which is undefined for spotlight/particle
//     payloads; payload.type exists only on audio payloads as a
//     format discriminator, a naming-collision artifact).
//
// db/032's venue_anchors_type_check vocabulary unchanged — the
// '-3d' suffix is registry-key only, not a DB type. See spec
// §4.1 + §0.3 D-dispatch row for the full rationale.
registerAnchorRenderer('spotlight-3d', spotlightAnchor3dRenderer);


// ─────────────────────────────────────────────────────────────────────────
// SECTION 5 — window.elsewhere.spotlight3dRenderer publication (spec §4.3)
// ─────────────────────────────────────────────────────────────────────────
// Matches A2 audio.js / A3 particle.js / A4a spotlight.js publication
// pattern — exposes the renderer entry point on
// window.elsewhere.spotlight3dRenderer for the admin preview's
// direct lookup at admin-venues.html (spec §6.4 per-anchor preview
// uses window.elsewhere?.spotlight3dRenderer?.spotlightAnchor3dRenderer?.()
// to instantiate the renderer per row, mirroring A4a's pattern at
// admin-venues.html:2882 — verified pre-spec investigation).
// Per CLAUDE.md "No build step" — inline scripts assume globals.

if (typeof window !== 'undefined') {
  window.elsewhere = window.elsewhere || {};
  window.elsewhere.spotlight3dRenderer = { spotlightAnchor3dRenderer };
}
