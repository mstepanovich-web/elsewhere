// shell/venue-renderers/particle.js
//
// Particle anchor renderer for the Venue Admin UI Stage A3 workstream.
// Implements 2D-canvas particle effects for venue_anchors rows of
// type='particle'. Registered to shell/venue-registry.js's anchor
// renderer registry at module load time.
//
// Per spec docs/VENUE-ADMIN-UI-A3-BUILD-SPEC.md §3.1 (Q1 resolution):
// SELF-CONTAINED. The renderer re-implements its own particle array
// and RAF loop and renders into a canvas reference passed via ctx.
// It does NOT import, wrap, or call karaoke/stage.html's spawnParticles
// / runParticleLoop — those mutate karaoke's shared global particles[]
// array, and calling them would inject preview particles into karaoke's
// live loop. Karaoke stays byte-for-byte untouched (D8 invariant).
//
// Three kinds dispatched on payload.kind (spec §1.1):
//   • point-cloud         — fixed positions, optional twinkle, eternal.
//                           Sub-dispatched on position_layout (cartesian
//                           vs polar-projected).
//   • directional-emitter — edge spawn, vector traverse, optional fade,
//                           optional respawn.
//   • volumetric          — region spawn, drift, optional growth + fade,
//                           gradient render.
//
// Alpha model (§1.2): uniform across all kinds. Color fragments carry
// RGB only; alpha is the scalar `alpha` field (default 1.0) OR
// `alpha_init_range` for per-particle spawn distribution. fade_rate
// decrements per-frame. A modulator targeting "alpha" multiplies.
// Final alpha clamped to [0,1] at draw time.
//
// CLR-5 — Point-cloud alpha formula (deferred renderer-contract item):
//   final_alpha = clamp(alpha * (0.2 + sin(phase)*0.8) * modulator_alpha, 0, 1)
// when twinkle_phase_speed_range is present; the sin term collapses
// to 1.0 when twinkle is absent (disco's no-twinkle case).
//
// CLR-6 — Turbulence formula: vx += (Math.random()-0.5) * strength
// per frame, per particle. Renderer applies turbulence to vx only;
// vy is unaffected (matches the procedural source pattern).
//
// CLR-7 — polar.dist_range normalizes against max(canvas.width,
// canvas.height) — matches the procedural source's
// Math.max(ambientW, ambientH) basis.
//
// CLR-8 — polar-projected layouts clip to canvas at render time
// (particles whose computed (x,y) fall outside canvas bounds are
// skipped, not drawn).
//
// Modulator preview (§1.6): A3 ships DORMANT. The real venue-level
// modulator drivers (stadium's cheerSwell for crowd_brightness, disco's
// pulseBeat for beat_scale/beat_brightness) are not wired to the
// registry. For admin-panel preview, the renderer drives each named
// modulator with a built-in oscillator so the preview looks alive.
// Real wiring is a later integration stage (see §7 DEFERRED — "venue
// modulator system").
//
// Per D8, importing this module does NOT change karaoke's read path.
// AMBIENT_PROFILES + addVenueEffects3D in karaoke/stage.html remain
// load-bearing until Stage 6. Registration of this renderer in the
// registry is permitted per A2's Check 12 precedent (registration is
// not a reader-path change).

import { registerAnchorRenderer } from '../venue-registry.js';

// ─── Modulator preview oscillators ───────────────────────────────────────
// Each function takes elapsed-ms-since-effect-start and returns a scalar
// the renderer multiplies into the targeted particle property. Values
// approximate the source venue's GSAP-driven dynamics; exact fidelity
// to the GSAP easing isn't required for preview (the goal is "looks
// alive"). When the real modulator system lands, this map is replaced
// by registry-resolved drivers.
const PREVIEW_OSCILLATORS = {
  // stadium cheer-swell: GSAP brightens 0.6 → 1.4 over 0.8s, decays
  // 1.4 → 0.6 over 3s, repeats every 8-16s. Preview: continuous sine,
  // range [0.6, 1.4], period 10s.
  crowd_brightness: (t) =>
    1.0 + 0.4 * Math.sin((2 * Math.PI * t) / 10000),

  // disco 120bpm pulse: source GSAP pulses scale 1 → 1.8 → 1, brightness
  // 1 → 1.6 → 1, 500ms per beat. Preview: half-rectified sine at 2Hz
  // (one pulse per 500ms), giving sharp-attack soft-decay shape.
  beat_scale: (t) =>
    1.0 + 0.8 * Math.max(0, Math.sin((2 * Math.PI * t) / 500)),

  beat_brightness: (t) =>
    1.0 + 0.6 * Math.max(0, Math.sin((2 * Math.PI * t) / 500)),
};

// Fallback identity oscillator for unknown modulator names.
const DEFAULT_OSCILLATOR = () => 1.0;

// Computes the per-frame multiplier for each modulator target.
// Returns { alpha, size } with default 1.0 for any unbound target.
// Accepts both single-object and array forms (§1.6 / CLR-1).
function computeModulatorTargets(modulator, elapsedMs) {
  const targets = { alpha: 1.0, size: 1.0 };
  if (!modulator) return targets;
  const bindings = Array.isArray(modulator) ? modulator : [modulator];
  for (const b of bindings) {
    if (!b || !b.name || !b.target) continue;
    const osc = PREVIEW_OSCILLATORS[b.name] || DEFAULT_OSCILLATOR;
    targets[b.target] = osc(elapsedMs);
  }
  return targets;
}

// ─── Color helpers ───────────────────────────────────────────────────────
// resolveSpawnColor reads payload.color (RGB only per §1.2) and returns
// a per-particle resolved color descriptor. For mode:"fixed", carries
// the RGB triplet through. For mode:"hue_range", draws a hue at spawn
// from the configured range (per-particle hue variety, the disco /
// festival pattern).

function resolveSpawnColor(colorFragment) {
  if (!colorFragment) return { fixedRgb: 'rgb(255,255,255)' };
  if (colorFragment.mode === 'fixed') {
    return { fixedRgb: colorFragment.value || 'rgb(255,255,255)' };
  }
  if (colorFragment.mode === 'hue_range') {
    const range = colorFragment.range || [0, 360];
    const hue = range[0] + Math.random() * (range[1] - range[0]);
    return {
      hue,
      sat: colorFragment.sat ?? 100,
      lit: colorFragment.lit ?? 50,
    };
  }
  return { fixedRgb: 'rgb(255,255,255)' };
}

// Combines a resolved color with a current alpha into a complete CSS
// color string. Final alpha clamped here per the §1.2 alpha model.
//
// fixedRgb path extracts the three RGB components with a tolerant
// regex (any internal whitespace around digits / commas accepted),
// then constructs a canonical compact rgba string. This is robust to
// admin-typed input like "rgb(255, 255, 255)" which a substring-replace
// approach would have mangled. Unparseable strings fall back to white-
// at-the-requested-alpha with a console warning, so a malformed admin
// input still renders SOMETHING visible (the admin notices and fixes)
// rather than silently producing invalid CSS.
//
// Per amended §1.2, fixedRgb is RGB only — alpha lives in its own
// scalar field. Inputs like "rgba(r,g,b,a)" fall through to the
// warn-and-default path (the regex's required 'rgb(' prefix doesn't
// match 'rgba(' because of the 'a' between 'b' and '(').
//
// hsla path unchanged — alpha is already a first-class slot in the
// hsla format string.
function colorWithAlpha(resolved, alpha) {
  const a = Math.max(0, Math.min(1, alpha));
  if (resolved.fixedRgb) {
    const m = /rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)/.exec(
      resolved.fixedRgb
    );
    if (m) {
      return `rgba(${m[1]},${m[2]},${m[3]},${a})`;
    }
    console.warn(
      '[particle-renderer] could not parse color.value as rgb(r,g,b):',
      resolved.fixedRgb,
      '— falling back to white. Per spec §1.2, color fragment mode:"fixed" expects rgb(r,g,b) only (no alpha component, no hex, no percentages).'
    );
    return `rgba(255,255,255,${a})`;
  }
  return `hsla(${resolved.hue}, ${resolved.sat}%, ${resolved.lit}%, ${a})`;
}

// Helper: draw range-from-array into a fresh value.
function pickInRange(range, fallback) {
  if (!Array.isArray(range) || range.length < 2) return fallback;
  return range[0] + Math.random() * (range[1] - range[0]);
}

// ─── point-cloud ──────────────────────────────────────────────────────────

function spawnPointCloud(payload, w, h) {
  const count = payload.count || 0;
  const layout = payload.position_layout;
  const twinkleRange = payload.twinkle_phase_speed_range; // optional (CLR-2)

  // Size: either scalar `size` or `size_range`
  const sizeRange = Array.isArray(payload.size_range)
    ? payload.size_range
    : [payload.size ?? 1, payload.size ?? 1];

  const particles = [];

  if (layout === 'polar-projected') {
    const polar = payload.polar || {};
    const distRange = polar.dist_range || [0, 0];
    // CLR-7: normalize against max(width, height)
    const distScale = Math.max(w, h);
    for (let i = 0; i < count; i++) {
      particles.push({
        angle: Math.random() * Math.PI * 2,
        dist:
          (distRange[0] +
            Math.random() * (distRange[1] - distRange[0])) *
          distScale,
        baseSize: pickInRange(sizeRange, 1),
        phase: twinkleRange ? Math.random() * Math.PI * 2 : 0,
        twinkleSpeed: twinkleRange ? pickInRange(twinkleRange, 0) : 0,
        spawnColor: resolveSpawnColor(payload.color),
      });
    }
  } else {
    // cartesian (default)
    const xRange = payload.x_range || [0, 1];
    const yRange = payload.y_range || [0, 1];
    for (let i = 0; i < count; i++) {
      particles.push({
        x: (xRange[0] + Math.random() * (xRange[1] - xRange[0])) * w,
        y: (yRange[0] + Math.random() * (yRange[1] - yRange[0])) * h,
        baseSize: pickInRange(sizeRange, 1),
        phase: twinkleRange ? Math.random() * Math.PI * 2 : 0,
        twinkleSpeed: twinkleRange ? pickInRange(twinkleRange, 0) : 0,
        spawnColor: resolveSpawnColor(payload.color),
      });
    }
  }

  return particles;
}

function updatePointCloud(particles) {
  // Eternal kind — only phase advances (when twinkle present).
  for (const p of particles) {
    if (p.twinkleSpeed) p.phase += p.twinkleSpeed;
  }
}

function drawPointCloud(c, particles, payload, w, h, rotAccum, mods) {
  const baseAlpha = payload.alpha ?? 1.0;
  const layout = payload.position_layout;
  const polar = payload.polar || {};
  const verticalSquash = polar.vertical_squash ?? 1.0;
  const center = polar.center || [0.5, 0.30];
  const cx = center[0] * w;
  const cy = center[1] * h;
  const hasTwinkle = !!payload.twinkle_phase_speed_range;
  const render = payload.render || { shape: 'circle', mode: 'solid' };

  for (const p of particles) {
    // Position
    let drawX;
    let drawY;
    if (layout === 'polar-projected') {
      const a = p.angle + rotAccum;
      drawX = cx + Math.cos(a) * p.dist;
      drawY = cy + Math.sin(a) * p.dist * verticalSquash;
      // CLR-8: clip to canvas at render time
      if (drawX < 0 || drawX > w || drawY < 0 || drawY > h) continue;
    } else {
      drawX = p.x;
      drawY = p.y;
    }

    // Size: per-particle baseSize × modulator-targeting-size
    const drawSize = p.baseSize * mods.size;

    // Alpha: CLR-5 formula
    //   final_alpha = clamp(alpha * twinkleFactor * mods.alpha, 0, 1)
    // where twinkleFactor = (0.2 + sin(phase)*0.8) when twinkle present,
    // else 1.0 (collapses to no internal modulation).
    const twinkleFactor = hasTwinkle
      ? 0.2 + Math.sin(p.phase) * 0.8
      : 1.0;
    const finalAlpha = baseAlpha * twinkleFactor * mods.alpha;

    // Render — point-cloud is shape:circle, mode:solid in A3's scope.
    c.beginPath();
    c.arc(drawX, drawY, drawSize, 0, Math.PI * 2);
    if (render.mode === 'stroke') {
      c.lineWidth = render.line_width || 1;
      c.strokeStyle = colorWithAlpha(p.spawnColor, finalAlpha);
      c.stroke();
    } else {
      c.fillStyle = colorWithAlpha(p.spawnColor, finalAlpha);
      c.fill();
    }
  }
}

// ─── directional-emitter ──────────────────────────────────────────────────

function spawnDirectionalEmitterParticle(payload, w, h) {
  const edge = payload.spawn_edge || 'top';
  const velRange = payload.velocity_range || { vx: [0, 0], vy: [0, 0] };
  const sizeRange = payload.size_range || [1, 1];
  const rotation = payload.rotation;

  // Spawn position at the named edge with a small off-canvas offset
  // (matches the procedural source's y:-10 for top-spawning confetti).
  let x;
  let y;
  switch (edge) {
    case 'bottom':
      x = Math.random() * w;
      y = h + 10;
      break;
    case 'left':
      x = -10;
      y = Math.random() * h;
      break;
    case 'right':
      x = w + 10;
      y = Math.random() * h;
      break;
    case 'top':
    default:
      x = Math.random() * w;
      y = -10;
      break;
  }

  // Spawn alpha: alpha_init_range takes precedence over scalar alpha
  // (per the §1.2 alpha model). For festival confetti, neither field
  // is set, so default 1.0.
  const alphaInitRange = payload.alpha_init_range;
  const spawnAlpha = alphaInitRange
    ? pickInRange(alphaInitRange, payload.alpha ?? 1.0)
    : payload.alpha ?? 1.0;

  return {
    x,
    y,
    vx: pickInRange(velRange.vx, 0),
    vy: pickInRange(velRange.vy, 0),
    size: pickInRange(sizeRange, 1),
    rot: rotation ? pickInRange(rotation.init_range, 0) : 0,
    rotV: rotation ? pickInRange(rotation.velocity_range, 0) : 0,
    alpha: spawnAlpha,
    spawnColor: resolveSpawnColor(payload.color),
  };
}

function spawnDirectionalEmitter(payload, w, h) {
  const count = payload.count || 0;
  const particles = [];
  for (let i = 0; i < count; i++) {
    particles.push(spawnDirectionalEmitterParticle(payload, w, h));
  }
  return particles;
}

function updateDirectionalEmitter(particles, payload, w, h) {
  const turbulence = payload.turbulence;
  const fadeRate = payload.fade_rate || 0;
  const respawn = payload.respawn === true;
  const margin = 20;

  const alive = [];
  for (const p of particles) {
    p.x += p.vx;
    p.y += p.vy;
    if (p.rotV) p.rot += p.rotV;
    // CLR-6: turbulence is per-frame random-walk on vx
    if (turbulence) {
      p.vx += (Math.random() - 0.5) * (turbulence.strength || 0);
    }
    if (fadeRate) p.alpha -= fadeRate;

    const offCanvas =
      p.x < -margin ||
      p.x > w + margin ||
      p.y < -margin ||
      p.y > h + margin;
    const faded = p.alpha <= 0;

    if (offCanvas || faded) {
      if (respawn) {
        alive.push(spawnDirectionalEmitterParticle(payload, w, h));
      }
      continue;
    }
    alive.push(p);
  }
  return alive;
}

function drawDirectionalEmitter(c, particles, mods, render) {
  const r = render || { shape: 'circle', mode: 'solid' };
  for (const p of particles) {
    const finalAlpha = p.alpha * mods.alpha;
    const finalSize = p.size * mods.size;

    if (r.shape === 'rect') {
      // Rotated fillRect (festival confetti pattern).
      c.save();
      c.translate(p.x, p.y);
      c.rotate(p.rot);
      c.fillStyle = colorWithAlpha(p.spawnColor, finalAlpha);
      c.fillRect(-finalSize / 2, -finalSize / 2, finalSize, finalSize);
      c.restore();
    } else {
      // shape:circle
      c.beginPath();
      c.arc(p.x, p.y, finalSize, 0, Math.PI * 2);
      if (r.mode === 'stroke') {
        c.lineWidth = r.line_width || 1;
        c.strokeStyle = colorWithAlpha(p.spawnColor, finalAlpha);
        c.stroke();
      } else {
        c.fillStyle = colorWithAlpha(p.spawnColor, finalAlpha);
        c.fill();
      }
    }
  }
}

// ─── volumetric ───────────────────────────────────────────────────────────

function spawnVolumetricParticle(payload, w, h) {
  const region = payload.spawn_region || { x: [0, 1], y: [0, 1] };
  const velRange = payload.velocity_range || { vx: [0, 0], vy: [0, 0] };
  const sizeInitRange = payload.size_init_range || [1, 1];
  const alphaInitRange = payload.alpha_init_range;
  const baseAlpha = payload.alpha ?? 1.0;

  return {
    x: (region.x[0] + Math.random() * (region.x[1] - region.x[0])) * w,
    y: (region.y[0] + Math.random() * (region.y[1] - region.y[0])) * h,
    vx: pickInRange(velRange.vx, 0),
    vy: pickInRange(velRange.vy, 0),
    size: pickInRange(sizeInitRange, 1),
    // alpha_init_range takes precedence over scalar alpha per §1.2
    alpha: alphaInitRange ? pickInRange(alphaInitRange, baseAlpha) : baseAlpha,
    spawnColor: resolveSpawnColor(payload.color),
  };
}

function spawnVolumetric(payload, w, h) {
  const count = payload.count || 0;
  const particles = [];
  for (let i = 0; i < count; i++) {
    particles.push(spawnVolumetricParticle(payload, w, h));
  }
  return particles;
}

function updateVolumetric(particles, payload, w, h) {
  const turbulence = payload.turbulence;
  const fadeRate = payload.fade_rate || 0;
  const growthRate = payload.size_growth_rate || 0;
  const respawn = payload.respawn === true;
  // Larger margin than directional-emitter because volumetric particles
  // can grow significantly past their spawn size.
  const margin = 100;

  const alive = [];
  for (const p of particles) {
    p.x += p.vx;
    p.y += p.vy;
    if (growthRate) p.size += growthRate;
    if (fadeRate) p.alpha -= fadeRate;
    if (turbulence) {
      // CLR-6: turbulence on vx only
      p.vx += (Math.random() - 0.5) * (turbulence.strength || 0);
    }

    const offCanvas =
      p.x < -margin ||
      p.x > w + margin ||
      p.y < -margin ||
      p.y > h + margin;
    const faded = p.alpha <= 0;

    if (offCanvas || faded) {
      if (respawn) {
        alive.push(spawnVolumetricParticle(payload, w, h));
      }
      continue;
    }
    alive.push(p);
  }
  return alive;
}

function drawVolumetric(c, particles, mods, render) {
  const r = render || { shape: 'circle', mode: 'gradient' };
  for (const p of particles) {
    const finalAlpha = p.alpha * mods.alpha;
    const finalSize = p.size * mods.size;

    if (r.mode === 'gradient' && r.shape === 'circle') {
      // Radial gradient: full alpha at center → transparent at edge
      // (speakeasy smoke pattern). createRadialGradient + fillRect
      // bounding box wide enough to hold the gradient.
      const g = c.createRadialGradient(p.x, p.y, 0, p.x, p.y, finalSize);
      g.addColorStop(0, colorWithAlpha(p.spawnColor, finalAlpha));
      g.addColorStop(1, colorWithAlpha(p.spawnColor, 0));
      c.fillStyle = g;
      c.fillRect(
        p.x - finalSize,
        p.y - finalSize,
        finalSize * 2,
        finalSize * 2
      );
    } else {
      // Fallback solid circle.
      c.beginPath();
      c.arc(p.x, p.y, finalSize, 0, Math.PI * 2);
      c.fillStyle = colorWithAlpha(p.spawnColor, finalAlpha);
      c.fill();
    }
  }
}

// ─── The exported renderer ────────────────────────────────────────────────

/**
 * Renders a particle anchor onto a 2D canvas.
 *
 * @param {Object} anchor - The venue_anchors row (must carry payload.kind)
 * @param {Object} ctx    - Consumer-supplied context object
 * @param {HTMLCanvasElement} ctx.canvas - Required: canvas to render into
 * @returns {{ stop: () => void }} - Teardown handle parallel to audio.js
 */
export function particleAnchorRenderer(anchor, ctx) {
  const payload = anchor?.payload || {};
  const canvas = ctx?.canvas;

  if (!canvas || typeof canvas.getContext !== 'function') {
    console.warn(
      '[particle-renderer] missing or invalid ctx.canvas; expected HTMLCanvasElement',
      anchor
    );
    return { stop: () => {} };
  }

  const c = canvas.getContext('2d', { willReadFrequently: true });   // A4b triage 2026-05-31: hint Chrome to back this canvas with software (CPU) instead of Skia GL, dodging the GPU-resource-pressure cross-context contamination (see SESSION-A4B-VERIFICATION-PAUSE.md §1.6 item 4)
  if (!c) {
    console.warn('[particle-renderer] could not get 2d context', anchor);
    return { stop: () => {} };
  }

  const kind = payload.kind;
  if (!kind) {
    console.warn('[particle-renderer] anchor payload missing kind', anchor);
    return { stop: () => {} };
  }

  // Initial spawn
  let particles;
  switch (kind) {
    case 'point-cloud':
      particles = spawnPointCloud(payload, canvas.width, canvas.height);
      break;
    case 'directional-emitter':
      particles = spawnDirectionalEmitter(
        payload,
        canvas.width,
        canvas.height
      );
      break;
    case 'volumetric':
      particles = spawnVolumetric(payload, canvas.width, canvas.height);
      break;
    default:
      console.warn(
        '[particle-renderer] unknown payload.kind:',
        kind,
        '(expected point-cloud / directional-emitter / volumetric)',
        anchor
      );
      return { stop: () => {} };
  }

  // Per-instance state
  const t0 = performance.now();
  let rotAccum = 0; // point-cloud polar-projected rotation accumulator
  let rafId = null;
  let running = true;

  function frame(now) {
    if (!running) return;

    // Canvas size read each frame — admin DOM may resize between frames.
    const w = canvas.width;
    const h = canvas.height;

    // Modulator values for this frame
    const elapsed = now - t0;
    const mods = computeModulatorTargets(payload.modulator, elapsed);

    // Clear (full canvas — A3 assumes one effect per canvas)
    c.clearRect(0, 0, w, h);

    // Per-kind tick
    switch (kind) {
      case 'point-cloud': {
        if (payload.position_layout === 'polar-projected') {
          const rv = payload.polar?.rotation_velocity || 0;
          rotAccum += rv;
        }
        updatePointCloud(particles);
        drawPointCloud(c, particles, payload, w, h, rotAccum, mods);
        break;
      }
      case 'directional-emitter': {
        particles = updateDirectionalEmitter(particles, payload, w, h);
        drawDirectionalEmitter(c, particles, mods, payload.render);
        break;
      }
      case 'volumetric': {
        particles = updateVolumetric(particles, payload, w, h);
        drawVolumetric(c, particles, mods, payload.render);
        break;
      }
    }

    rafId = requestAnimationFrame(frame);
  }

  rafId = requestAnimationFrame(frame);

  function stop() {
    running = false;
    if (rafId !== null) {
      cancelAnimationFrame(rafId);
      rafId = null;
    }
    particles = [];
    try {
      c.clearRect(0, 0, canvas.width, canvas.height);
    } catch (_) {
      // canvas may have been removed from DOM; ignore.
    }
  }

  return { stop };
}

// ─── Registration ─────────────────────────────────────────────────────────

registerAnchorRenderer('particle', particleAnchorRenderer);

if (typeof window !== 'undefined') {
  window.elsewhere = window.elsewhere || {};
  window.elsewhere.particleRenderer = {
    particleAnchorRenderer,
  };
}
