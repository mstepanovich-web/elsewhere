// shell/venue-renderers/spotlight.js
//
// Spotlight anchor renderer for the Venue Admin UI Stage A4a workstream.
// Implements 2D-canvas spotlight effects for venue_anchors rows of
// type='spotlight'. Registered to shell/venue-registry.js's anchor
// renderer registry at module load time.
//
// Per spec docs/VENUE-ADMIN-UI-A4A-BUILD-SPEC.md §3.1: SELF-CONTAINED.
// The renderer re-implements its own animation state (per-item arrays
// for active tweens, current values, target values, start times) and
// its own RAF loop, and renders into a canvas reference passed via ctx.
// It does NOT import, wrap, or call karaoke/stage.html's beam / laser /
// shaft closures inside AMBIENT_PROFILES — those mutate karaoke's
// shared global state, and calling them would inject preview content
// into karaoke's live loop. Karaoke stays byte-for-byte untouched (D8).
//
// Per spec §3.5: NO GSAP DEPENDENCY. The procedural source uses GSAP
// extensively (stadium beams' sweepBeam, festival lasers' beatPulse,
// speakeasy shafts' driftShaft — all gsap.to with named ease curves +
// onComplete chaining). This renderer reproduces those timelines
// semantically using requestAnimationFrame + per-tween elapsed-time
// tracking + pure-JS ease functions. The four ease curves A4a needs
// (power1.inOut / power2.in / power3.out / sine.inOut) match GSAP's
// naming verbatim — see EASE_FNS below.
//
// Three kinds dispatched on payload.kind (spec §1.1):
//   • swept-beam-2d  — N gradient-trapezoid beams pivoting at top-center,
//                       sweep-tweened on (angle, alpha). Stadium 4-beam
//                       case is canonical.
//   • pulsed-laser   — N narrow rotated lasers pivoting at bottom-center,
//                       continuous per-frame angle drift + beat-pulse
//                       tween chain on (alpha, width). Festival 6-laser
//                       case is canonical.
//   • light-shaft    — N vertical trapezoid shafts (no rotation),
//                       drift-tweened on (x, alpha). Speakeasy 3-shaft
//                       case is canonical.
//
// count:N per-item arrays (spec §1.6). For each kind, the payload
// declares per-item arrays of length count (e.g. stadium hues[4],
// festival angle_init[6], speakeasy x_init_norm[3]) alongside shared
// scalars. The renderer iterates 0..count-1 and reads array[i] or the
// scalar accordingly.
//
// payload.context dispatch (spec §1.7). Only "2d-canvas" is handled
// by A4a's renderer. Unknown context → console.warn + return
// { stop: () => {} } no-op handle. Forward-compatibility: A4b will
// extend this module with "3d-three" context support for swept-beam-3d
// + point-light kinds (siblings, not branches — spec §1.8).
//
// payload.kind dispatch (spec §1.8). Only the 3 A4a kinds accepted.
// Unknown kind (including A4b reservations swept-beam-3d / point-light
// before A4b ships) → console.warn + return no-op handle. Same posture
// as §1.7: fail loud (console.warn), fail safe (no throw, no broken
// handle).
//
// Modulators: NONE (per spec D5). A4a's spotlights bind no external
// scalars — every animated value is kind-internal payload (BPM, sweep
// duration range, alpha range, etc.). The 2D phone-lights particle
// anchor shipped in A3 is the only modulator binding in the workstream
// so far. A7 builds the driver registry; A4a contributes nothing.
//
// D8 dormancy. Registered but no live consumer in karaoke until Stage
// A7's read-path switch. Karaoke continues to use AMBIENT_PROFILES +
// addVenueEffects3D until then. The only consumer for now is the
// admin panel's preview surface.
//
// Companion docs:
//   • docs/VENUE-ADMIN-UI-A4A-BUILD-SPEC.md §1 (amended at d50cbc9),
//     §3 (renderer contract), §3.5 (GSAP-equivalent motion), §9
//     step 3 (this proposal's review gate)
//   • shell/venue-renderers/particle.js — A3 precedent for the
//     self-contained-RAF + registration patterns
//   • karaoke/stage.html:4593-4666 / 4844-4916 / 4762-4827 — the
//     three procedural sources

import { registerAnchorRenderer } from '../venue-registry.js';


// ─────────────────────────────────────────────────────────────────────────
// SECTION 1 — Ease functions (spec §3.5)
// ─────────────────────────────────────────────────────────────────────────

/**
 * Pure-JS ease functions matching GSAP's naming verbatim. Keys are the
 * exact strings stored in payload (e.g. "power1.inOut") so EASE_FNS[ease]
 * lookup matches the payload field directly with no translation layer.
 *
 * Mapping (GSAP power-N = degree-(N+1) polynomial):
 *   power1 = quadratic, power2 = cubic, power3 = quartic.
 *
 * Precision: native Math.pow / Math.cos accuracy (≥ 1e-15 across t∈[0,1]).
 * No bespoke ease curves — these four are A4a's entire motion vocabulary.
 */
const EASE_FNS = {
  'power1.inOut': t => t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2,
  'power2.in':    t => t * t * t,
  'power3.out':   t => 1 - Math.pow(1 - t, 4),
  'sine.inOut':   t => -(Math.cos(Math.PI * t) - 1) / 2,
};

/**
 * Look up an ease function by name. Unknown names fall back to linear
 * with a console.warn — same fail-loud/fail-safe posture as the kind
 * and context dispatchers below.
 */
function easeOf(name) {
  const fn = EASE_FNS[name];
  if (!fn) {
    console.warn(
      `spotlight: unknown ease "${name}", falling back to linear. ` +
      `Known eases: ${Object.keys(EASE_FNS).join(', ')}`
    );
    return t => t;
  }
  return fn;
}


// ─────────────────────────────────────────────────────────────────────────
// SECTION 2 — Tween primitives (spec §9 step 3 (a))
// ─────────────────────────────────────────────────────────────────────────

/**
 * Per-tween state shape. Each per-item state object holds at most one
 * `active_tween` of this shape at a time (null when no tween is
 * active). A tween can mutate MULTIPLE fields of the item in parallel —
 * the `fields` array carries one entry per field being tweened, each
 * with its own start_value/target_value. All fields share the same
 * eased t (the tween's elapsed-time progress through duration_ms).
 *
 *   {
 *     fields: [
 *       { name: 'angle', start: <number>, target: <number> },
 *       { name: 'alpha', start: <number>, target: <number> },
 *       ...
 *     ],
 *     start_time_ms: <ms timestamp from performance.now()>,
 *     duration_ms:   <number>,
 *     ease:          <string — key into EASE_FNS>,
 *     on_complete:   <function | null>  // typically starts the next tween
 *   }
 *
 * The multi-field design (vs one tween record per field) matches the
 * source's gsap.to({field1: ..., field2: ..., duration, ease}) calls,
 * which tween multiple fields in lockstep. See:
 *   - stadium sweepBeam (karaoke/stage.html:4608-4611) — angle + alpha
 *   - speakeasy driftShaft (4774-4779) — x + alpha
 *   - festival beatPulse attack (4860-4862) — alpha + width
 *   - festival beatPulse decay (4863) — alpha + width
 */

/**
 * Advance the active tween on `item` one frame. Mutates item[field.name]
 * for each field in the tween. On completion (t >= 1):
 *   1. Clears item.active_tween FIRST (so an on_complete callback that
 *      sets item.active_tween = <new tween> sticks).
 *   2. Invokes the tween's on_complete callback.
 *   3. Either item.active_tween is now the next tween (if on_complete
 *      chained), or still null (terminal tween).
 *
 * No return value — the function mutates item in place. The tick loop
 * does NOT reassign item.active_tween from this function's return.
 *
 * Animation-tick formula (spec §9 step 3 (a)):
 *   t = clamp((now - start_time_ms) / duration_ms, 0, 1)
 *   eased = EASE_FNS[tween.ease](t)
 *   item[field.name] = start + (target - start) * eased   // for each field
 *   if t >= 1: clear active_tween, then invoke on_complete
 */
function advanceTween(item, now) {
  const tween = item.active_tween;
  if (!tween) return;
  const elapsed = now - tween.start_time_ms;
  const t = elapsed <= 0 ? 0 : elapsed >= tween.duration_ms ? 1 : elapsed / tween.duration_ms;
  const eased = easeOf(tween.ease)(t);
  for (const f of tween.fields) {
    item[f.name] = f.start + (f.target - f.start) * eased;
  }
  if (t >= 1) {
    // Clear the completed tween BEFORE invoking on_complete so that
    // a callback that sets item.active_tween = <new tween> sticks.
    item.active_tween = null;
    const onComplete = tween.on_complete;
    if (onComplete) onComplete();
    // If on_complete set a new tween, it's now in item.active_tween;
    // if not, it stays null. Either way, no further work here.
  }
}


// ─────────────────────────────────────────────────────────────────────────
// SECTION 3 — Shared draw helpers (spec §9 step 3 (g))
// ─────────────────────────────────────────────────────────────────────────

/**
 * Build an HSL-based linear gradient from a gradient_stops array (spec §1
 * amendment d50cbc9). For each stop in the array:
 *   gradient.addColorStop(stop.at, hsla(hue, sat_pct, lit_pct, base_alpha * stop.alpha_mult))
 *
 * The per-stop alpha_mult pattern lets each gradient stop carry an
 * independent multiplier of the item's per-frame alpha:
 *   - stadium swept-beam-2d: stops at 0/0.5/1 with mults 1.0/0.4/0.0
 *     (source: addColorStop(0.5, alpha*0.4) at line 4653)
 *   - festival pulsed-laser: stops at 0/0.6/1 with mults 1.0/0.3/0.0
 *     (source: addColorStop(0.6, alpha*0.3) at line 4896)
 *   - speakeasy light-shaft: stops at 0/1 with mults 1.0/0.0 (no mid)
 *
 * @param grad   the CanvasGradient object (already created by caller)
 * @param stops  array of { at, alpha_mult } objects from payload.geometry.gradient_stops
 * @param hue    0..360 HSL hue
 * @param sat    0..100 HSL saturation pct
 * @param lit    0..100 HSL lightness pct
 * @param baseAlpha the item's current alpha (0..1); per-stop alpha = baseAlpha * mult
 */
function applyHslGradientStops(grad, stops, hue, sat, lit, baseAlpha) {
  for (const stop of stops) {
    const a = Math.max(0, Math.min(1, baseAlpha * stop.alpha_mult));
    grad.addColorStop(stop.at, `hsla(${hue},${sat}%,${lit}%,${a})`);
  }
}

/**
 * RGB-based variant of applyHslGradientStops — used by light-shaft kind
 * which carries a fixed RGB color fragment instead of hue/sat/lit.
 *
 * @param rgbTriple  parsed array [r, g, b]
 * @param baseAlpha  item's current alpha; per-stop alpha = baseAlpha * mult
 */
function applyRgbGradientStops(grad, stops, rgbTriple, baseAlpha) {
  const [r, g, b] = rgbTriple;
  for (const stop of stops) {
    const a = Math.max(0, Math.min(1, baseAlpha * stop.alpha_mult));
    grad.addColorStop(stop.at, `rgba(${r},${g},${b},${a})`);
  }
}

/**
 * Parse a "rgb(r,g,b)" color fragment value into [r, g, b]. Tolerant of
 * whitespace inside the parens. Returns [255, 255, 255] (white) on
 * malformed input, with a console.warn — same fail-safe posture as
 * elsewhere in this module.
 */
function parseRgbTriple(value) {
  const m = /rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)/.exec(value || '');
  if (!m) {
    console.warn(`spotlight: malformed rgb() color value "${value}", using white`);
    return [255, 255, 255];
  }
  return [parseInt(m[1], 10), parseInt(m[2], 10), parseInt(m[3], 10)];
}

/**
 * Uniform [a, b] random in inclusive range. Used for stagger / target /
 * duration / alpha ranges. Centralized so the rand source is replaceable
 * for deterministic preview testing later (not in A4a scope).
 */
function randIn(min, max) {
  return min + Math.random() * (max - min);
}


// ─────────────────────────────────────────────────────────────────────────
// SECTION 4 — handleSweptBeam2d (spec §1.3, source 4593-4666)
// ─────────────────────────────────────────────────────────────────────────

/**
 * Stadium swept-beam-2d handler. Constructs count beams from per-item
 * arrays (hues, angle_init) + shared scalars, runs a single active
 * sweep tween per beam (recursive — on_complete starts the next sweep),
 * and draws all beams to ctx.canvas per frame.
 *
 * ─── Source-fidelity citations (karaoke/stage.html:4593-4666) ───────────
 *
 * (1) Beam construction (lines 4597-4602):
 *
 *   SOURCE:
 *     const beams = Array.from({length:4}, (_,i)=>({
 *       angle: (i-1.5)*0.25,
 *       targetAngle: (Math.random()-0.5)*0.8,   // dead code — unused
 *       alpha: 0.08 + Math.random()*0.06,
 *       hue: [220,200,240,180][i]
 *     }));
 *
 *   RECONSTRUCTION:
 *     For i=0..count-1: beams[i] = {
 *       angle: payload.angle_init[i],           // explicit array, no formula at runtime
 *       alpha: randIn(...base_alpha_range),     // [0.08, 0.14]
 *       hue:   payload.hues[i],                 // [220, 200, 240, 180]
 *       active_tween: null                       // tween starts after stagger
 *     }
 *
 *   The source's `targetAngle` field is never read (sweepBeam computes
 *   its own newAngle fresh) — correctly omitted from the payload and
 *   from this reconstruction.
 *
 * (2) sweepBeam recursive tween (lines 4605-4612):
 *
 *   SOURCE:
 *     function sweepBeam(beam){
 *       if(currentAmbientVenue !== 'stadium') return;
 *       const newAngle = (Math.random()-0.5)*0.85;
 *       gsap.to(beam, {
 *         angle: newAngle, alpha: 0.06 + Math.random()*0.1,
 *         duration: 1.5 + Math.random()*2.5, ease:'power1.inOut',
 *         onComplete: ()=> sweepBeam(beam)
 *       });
 *     }
 *
 *   RECONSTRUCTION:
 *     sweepBeam(beam) sets beam.active_tween to a new tween record
 *     with fields=[{angle, …}, {alpha, …}], on_complete=()=>sweepBeam(beam).
 *     The renderer's `stopped` flag replaces the source's
 *     `currentAmbientVenue` guard. New target values drawn at tween-start.
 *
 * (3) Initial stagger + draw (lines 4614, 4646-4660):
 *
 *   SOURCE:
 *     beams.forEach((b,i)=> setTimeout(()=>sweepBeam(b), i*800));
 *     // draw: translate(ambientW/2, 0); rotate(b.angle); trapezoid 12 → ambientW
 *
 *   RECONSTRUCTION:
 *     For i=0..count-1: timeoutIds.push(setTimeout(() => sweepBeam(beams[i]), i * stagger_ms))
 *     Drawing uses payload.geometry (pivot top-center, top_width_px 12,
 *     bottom_width_norm 1.0, height_norm 1.0, gradient_stops 3-stop).
 */
function handleSweptBeam2d(anchor, ctx) {
  const payload = anchor.payload;
  const canvas = ctx.canvas;
  const c = canvas.getContext('2d');
  if (!c) {
    console.warn('spotlight: ctx.canvas has no 2D rendering context');
    return { stop: () => {} };
  }

  const count = payload.count;
  const geom = payload.geometry;
  const stops = geom.gradient_stops;

  let stopped = false;
  let rafId = null;
  const timeoutIds = [];

  // Build per-beam state from per-item arrays + shared scalars.
  const beams = [];
  for (let i = 0; i < count; i++) {
    beams.push({
      angle: payload.angle_init[i],
      alpha: randIn(payload.base_alpha_range[0], payload.base_alpha_range[1]),
      hue:   payload.hues[i],
      active_tween: null,
    });
  }

  // sweepBeam — start a new tween on this beam (angle + alpha together).
  // Recursive via on_complete (matches source's gsap.to onComplete chain).
  function sweepBeam(beam) {
    if (stopped) return;
    const newAngle = randIn(payload.sweep_target_range[0], payload.sweep_target_range[1]);
    const newAlpha = randIn(payload.sweep_alpha_range[0], payload.sweep_alpha_range[1]);
    const newDur   = randIn(payload.sweep_duration_range_ms[0], payload.sweep_duration_range_ms[1]);
    beam.active_tween = {
      fields: [
        { name: 'angle', start: beam.angle, target: newAngle },
        { name: 'alpha', start: beam.alpha, target: newAlpha },
      ],
      start_time_ms: performance.now(),
      duration_ms:   newDur,
      ease:          payload.sweep_ease,
      on_complete:   () => sweepBeam(beam),
    };
  }

  // Initial stagger: beam[i] starts its first sweep after stagger_ms × i.
  for (let i = 0; i < count; i++) {
    timeoutIds.push(setTimeout(() => sweepBeam(beams[i]), i * payload.stagger_ms));
  }

  // Drawing — translate(W/2, 0); rotate(angle); trapezoid + 3-stop gradient.
  function drawBeam(beam) {
    c.save();
    c.translate(canvas.width / 2, 0);
    c.rotate(beam.angle);
    const grad = c.createLinearGradient(0, 0, 0, canvas.height * geom.height_norm);
    applyHslGradientStops(grad, stops, beam.hue, geom.sat_pct, geom.lit_pct, beam.alpha);
    c.fillStyle = grad;
    const topHalf = geom.top_width_px / 2;
    const botHalf = (canvas.width * geom.bottom_width_norm) / 2;
    const h = canvas.height * geom.height_norm;
    c.beginPath();
    c.moveTo(-topHalf, 0);
    c.lineTo(topHalf, 0);
    c.lineTo(botHalf, h);
    c.lineTo(-botHalf, h);
    c.closePath();
    c.fill();
    c.restore();
  }

  // RAF loop — advance tweens, clear, draw.
  function tick() {
    if (stopped) return;
    const now = performance.now();
    for (const beam of beams) {
      advanceTween(beam, now);
    }
    c.clearRect(0, 0, canvas.width, canvas.height);
    for (const beam of beams) drawBeam(beam);
    rafId = requestAnimationFrame(tick);
  }
  rafId = requestAnimationFrame(tick);

  return {
    stop: () => {
      stopped = true;
      if (rafId !== null) cancelAnimationFrame(rafId);
      timeoutIds.forEach(id => clearTimeout(id));
      timeoutIds.length = 0;
      c.clearRect(0, 0, canvas.width, canvas.height);
    },
  };
}


// ─────────────────────────────────────────────────────────────────────────
// SECTION 5 — handlePulsedLaser (spec §1.4, source 4844-4916)
// ─────────────────────────────────────────────────────────────────────────

/**
 * Festival pulsed-laser handler. Constructs count lasers from per-item
 * arrays (hues, angle_init, drift_speeds, base_widths_px) + shared
 * scalars (bpm, drift_range, base/peak alphas, attack/decay envelope,
 * first_pulse_offset_beats). Runs TWO concurrent motion systems:
 *
 *   (i)  Continuous per-frame angle drift (NOT a tween — direct
 *        +=drift_speed with reflect at |angle| > drift_range)
 *   (ii) Beat-pulse tween chain: every BEAT ms, each laser starts an
 *        attack tween on (alpha, width); on_complete starts a decay
 *        tween back to base.
 *
 * ─── Source-fidelity citations (karaoke/stage.html:4844-4916) ───────────
 *
 * (1) Laser construction (lines 4849-4854):
 *
 *   SOURCE:
 *     const lasers = Array.from({length:6},(_,i)=>({
 *       hue: i*60, angle: Math.PI*0.35 - i*0.14,
 *       speed: (i%2?1:-1)*0.005,
 *       width: 3+i%2*2,
 *       alpha: 0.35
 *     }));
 *
 *   RECONSTRUCTION:
 *     For i=0..count-1: lasers[i] = {
 *       hue:        payload.hues[i],            // [0, 60, 120, 180, 240, 300]
 *       angle:      payload.angle_init[i],      // [1.099557, 0.959557, …]
 *       driftSpeed: payload.drift_speeds[i],    // [-0.005, 0.005, …]  (negative-first)
 *       width:      payload.base_widths_px[i],  // [3, 5, 3, 5, 3, 5]
 *       alpha:      payload.base_alpha,         // 0.35 shared
 *       active_tween: null
 *     }
 *
 * (2) Per-frame drift + reflect (line 4887):
 *
 *   SOURCE:
 *     update(){ lasers.forEach(l=>{ l.angle+=l.speed;
 *                                   if(Math.abs(l.angle)>Math.PI*0.48) l.speed*=-1; }); }
 *
 *   RECONSTRUCTION:
 *     For each laser: laser.angle += laser.driftSpeed;
 *                     if (Math.abs(laser.angle) > payload.drift_range)
 *                       laser.driftSpeed *= -1;
 *
 *     drift_range = 1.507964 (= Math.PI * 0.48 to 6 decimals per spec §1.4).
 *
 * (3) beatPulse attack→decay tween chain (lines 4857-4866):
 *
 *   SOURCE:
 *     function beatPulse(){
 *       if(currentAmbientVenue !== 'festival') return;
 *       lasers.forEach((l,i)=>{
 *         gsap.to(l, {
 *           alpha: 0.85, width: (3+i%2*2)*2.5,
 *           duration: 0.06, ease:'power3.out',
 *           onComplete:()=> gsap.to(l, { alpha: 0.35, width: 3+i%2*2, duration: 0.38, ease:'power2.in' })
 *         });
 *       });
 *       setTimeout(beatPulse, BEAT);
 *     }
 *     setTimeout(beatPulse, BEAT * 0.5);   // first pulse at half-beat offset
 *
 *   RECONSTRUCTION:
 *     beatPulse() iterates lasers, sets each laser.active_tween to an
 *     attack tween (fields: alpha→peak_alpha, width→base*peak_width_mult;
 *     duration: attack_ms; ease: attack_ease; on_complete: replaces
 *     active_tween with a decay tween (fields: alpha→base_alpha,
 *     width→base; duration: decay_ms; ease: decay_ease)). Self-reschedules
 *     via setTimeout(beatPulse, BEAT) where BEAT = 60000 / payload.bpm.
 *     First pulse at BEAT * first_pulse_offset_beats (= BEAT * 0.5).
 */
function handlePulsedLaser(anchor, ctx) {
  const payload = anchor.payload;
  const canvas = ctx.canvas;
  const c = canvas.getContext('2d');
  if (!c) {
    console.warn('spotlight: ctx.canvas has no 2D rendering context');
    return { stop: () => {} };
  }

  const count = payload.count;
  const geom = payload.geometry;
  const stops = geom.gradient_stops;
  const BEAT = 60000 / payload.bpm;

  let stopped = false;
  let rafId = null;
  const timeoutIds = [];

  // Build per-laser state.
  const lasers = [];
  for (let i = 0; i < count; i++) {
    lasers.push({
      hue:        payload.hues[i],
      angle:      payload.angle_init[i],
      driftSpeed: payload.drift_speeds[i],
      width:      payload.base_widths_px[i],
      alpha:      payload.base_alpha,
      active_tween: null,
    });
  }

  // beatPulse — for each laser, start attack tween; on_complete chains to decay tween.
  function beatPulse() {
    if (stopped) return;
    for (let i = 0; i < count; i++) {
      const l = lasers[i];
      const baseW = payload.base_widths_px[i];
      const peakW = baseW * payload.peak_width_mult;
      l.active_tween = {
        fields: [
          { name: 'alpha', start: l.alpha, target: payload.peak_alpha },
          { name: 'width', start: l.width, target: peakW },
        ],
        start_time_ms: performance.now(),
        duration_ms:   payload.attack_ms,
        ease:          payload.attack_ease,
        on_complete: () => {
          if (stopped) return;
          l.active_tween = {
            fields: [
              { name: 'alpha', start: l.alpha, target: payload.base_alpha },
              { name: 'width', start: l.width, target: baseW },
            ],
            start_time_ms: performance.now(),
            duration_ms:   payload.decay_ms,
            ease:          payload.decay_ease,
            on_complete:   null,
          };
        },
      };
    }
    // timeoutIds grows by 1 per beat; stop() clears all outstanding ids
    // on session end, so no leak during operational use.
    timeoutIds.push(setTimeout(beatPulse, BEAT));
  }
  // First pulse at BEAT × first_pulse_offset_beats.
  timeoutIds.push(setTimeout(beatPulse, BEAT * payload.first_pulse_offset_beats));

  // Drawing — translate(W/2, H); rotate(angle); fillRect width×H upward; 3-stop gradient.
  function drawLaser(laser) {
    c.save();
    c.translate(canvas.width / 2, canvas.height);
    c.rotate(laser.angle);
    const h = canvas.height * geom.height_norm;
    const grad = c.createLinearGradient(0, 0, 0, -h);   // emit upward
    applyHslGradientStops(grad, stops, laser.hue, geom.sat_pct, geom.lit_pct, laser.alpha);
    c.fillStyle = grad;
    c.fillRect(-laser.width / 2, -h, laser.width, h);
    c.restore();
  }

  // RAF loop — drift + tween + draw.
  function tick() {
    if (stopped) return;
    const now = performance.now();
    for (const laser of lasers) {
      // (i) continuous drift — direct mutation, not a tween
      laser.angle += laser.driftSpeed;
      if (Math.abs(laser.angle) > payload.drift_range) {
        laser.driftSpeed *= -1;
      }
      // (ii) advance any active pulse tween (mutates laser in place)
      advanceTween(laser, now);
    }
    c.clearRect(0, 0, canvas.width, canvas.height);
    for (const laser of lasers) drawLaser(laser);
    rafId = requestAnimationFrame(tick);
  }
  rafId = requestAnimationFrame(tick);

  return {
    stop: () => {
      stopped = true;
      if (rafId !== null) cancelAnimationFrame(rafId);
      timeoutIds.forEach(id => clearTimeout(id));
      timeoutIds.length = 0;
      c.clearRect(0, 0, canvas.width, canvas.height);
    },
  };
}


// ─────────────────────────────────────────────────────────────────────────
// SECTION 6 — handleLightShaft (spec §1.5, source 4762-4827)
// ─────────────────────────────────────────────────────────────────────────

/**
 * Speakeasy light-shaft handler. Constructs count shafts from per-item
 * array (x_init_norm) + shared scalars (alpha + width ranges, drift
 * envelope). Each shaft runs a single active drift tween mutating x AND
 * alpha in parallel (one tween record with two fields). Width is set
 * randomly at spawn and NOT tweened.
 *
 * ─── Source-fidelity citations (karaoke/stage.html:4762-4827) ───────────
 *
 * (1) Shaft construction (lines 4766-4770):
 *
 *   SOURCE:
 *     const shafts = Array.from({length:3}, (_,i)=>({
 *       x: ambientW*(0.25 + i*0.25),
 *       alpha: 0.04 + Math.random()*0.04,
 *       width: 60 + Math.random()*40
 *     }));
 *
 *   RECONSTRUCTION:
 *     For i=0..count-1: shafts[i] = {
 *       x:     payload.x_init_norm[i] * canvas.width,         // [0.25, 0.50, 0.75] × W
 *       alpha: randIn(...base_alpha_range),                    // [0.04, 0.08]
 *       width: randIn(...width_range_px),                      // [60, 100] px
 *       active_tween: null
 *     }
 *
 *   x is stored as absolute pixels (matching source). Initial position
 *   resolves x_init_norm against the current canvas.width — different
 *   canvas sizes (admin preview vs karaoke stage) yield different pixel
 *   x values, matching the source's ambientW-based positioning.
 *
 * (2) driftShaft recursive tween (lines 4774-4780):
 *
 *   SOURCE:
 *     gsap.to(s, {
 *       x: s.x + (Math.random()-0.5)*80,
 *       alpha: 0.03 + Math.random()*0.06,
 *       duration: 4 + Math.random()*4,
 *       ease: 'sine.inOut',
 *       onComplete: driftShaft
 *     });
 *
 *   RECONSTRUCTION:
 *     driftShaft(shaft) sets shaft.active_tween = {
 *       fields: [
 *         { name: 'x',     start: shaft.x,     target: shaft.x + (rand-0.5)*drift_distance_px },
 *         { name: 'alpha', start: shaft.alpha, target: randIn(...drift_alpha_range) },
 *       ],
 *       duration_ms: randIn(...drift_duration_range_ms),
 *       ease:        payload.drift_ease,         // 'sine.inOut'
 *       on_complete: () => driftShaft(shaft),
 *     }
 *
 *   drift_distance_px is 80 (canvas pixels). The (rand-0.5) centers the
 *   drift around 0, producing offset in [-40, +40] px from current x.
 *
 * (3) Initial stagger (line 4782):
 *
 *   SOURCE:
 *     shafts.forEach(s=>{
 *       function driftShaft(){ ... }
 *       setTimeout(driftShaft, Math.random()*2000);
 *     });
 *
 *   RECONSTRUCTION:
 *     For each shaft: timeoutIds.push(setTimeout(
 *       () => driftShaft(shaft),
 *       Math.random() * payload.drift_stagger_max_ms   // [0, 2000]
 *     ));
 */
function handleLightShaft(anchor, ctx) {
  const payload = anchor.payload;
  const canvas = ctx.canvas;
  const c = canvas.getContext('2d');
  if (!c) {
    console.warn('spotlight: ctx.canvas has no 2D rendering context');
    return { stop: () => {} };
  }

  const count = payload.count;
  const geom = payload.geometry;
  const stops = geom.gradient_stops;
  const rgbTriple = parseRgbTriple(payload.color.value);

  let stopped = false;
  let rafId = null;
  const timeoutIds = [];

  // Build per-shaft state. x resolves from normalized to absolute px.
  const shafts = [];
  for (let i = 0; i < count; i++) {
    shafts.push({
      x:     payload.x_init_norm[i] * canvas.width,
      alpha: randIn(payload.base_alpha_range[0], payload.base_alpha_range[1]),
      width: randIn(payload.width_range_px[0], payload.width_range_px[1]),
      active_tween: null,
    });
  }

  // driftShaft — start a new drift tween (x + alpha together).
  function driftShaft(shaft) {
    if (stopped) return;
    const xDelta = (Math.random() - 0.5) * payload.drift_distance_px;
    const newAlpha = randIn(payload.drift_alpha_range[0], payload.drift_alpha_range[1]);
    const newDur   = randIn(payload.drift_duration_range_ms[0], payload.drift_duration_range_ms[1]);
    shaft.active_tween = {
      fields: [
        { name: 'x',     start: shaft.x,     target: shaft.x + xDelta },
        { name: 'alpha', start: shaft.alpha, target: newAlpha },
      ],
      start_time_ms: performance.now(),
      duration_ms:   newDur,
      ease:          payload.drift_ease,
      on_complete:   () => driftShaft(shaft),
    };
  }

  // Initial stagger: each shaft starts at a random delay in [0, drift_stagger_max_ms].
  for (const shaft of shafts) {
    timeoutIds.push(setTimeout(
      () => driftShaft(shaft),
      Math.random() * payload.drift_stagger_max_ms
    ));
  }

  // Drawing — NO rotation; trapezoid using top_inset_factor + bottom_outset_factor.
  function drawShaft(shaft) {
    const h = canvas.height * geom.height_norm;
    const grad = c.createLinearGradient(0, 0, 0, h);
    applyRgbGradientStops(grad, stops, rgbTriple, shaft.alpha);
    c.fillStyle = grad;
    const topHalf = shaft.width * geom.top_inset_factor;
    const botHalf = shaft.width * geom.bottom_outset_factor;
    c.beginPath();
    c.moveTo(shaft.x - topHalf, 0);
    c.lineTo(shaft.x + topHalf, 0);
    c.lineTo(shaft.x + botHalf, h);
    c.lineTo(shaft.x - botHalf, h);
    c.closePath();
    c.fill();
  }

  // RAF loop.
  function tick() {
    if (stopped) return;
    const now = performance.now();
    for (const shaft of shafts) {
      advanceTween(shaft, now);
    }
    c.clearRect(0, 0, canvas.width, canvas.height);
    for (const shaft of shafts) drawShaft(shaft);
    rafId = requestAnimationFrame(tick);
  }
  rafId = requestAnimationFrame(tick);

  return {
    stop: () => {
      stopped = true;
      if (rafId !== null) cancelAnimationFrame(rafId);
      timeoutIds.forEach(id => clearTimeout(id));
      timeoutIds.length = 0;
      c.clearRect(0, 0, canvas.width, canvas.height);
    },
  };
}


// ─────────────────────────────────────────────────────────────────────────
// SECTION 7 — Entry dispatcher + registration
// ─────────────────────────────────────────────────────────────────────────

/**
 * The renderer entry point. Receives a venue_anchors row (anchor) and a
 * ctx with at least { canvas: HTMLCanvasElement }. Dispatches on
 * payload.context, then payload.kind. Returns { stop } per spec §3.3.
 *
 * Fail-loud/fail-safe posture (spec §1.7 / §1.8): unknown context or
 * unknown kind → console.warn + no-op stop handle. No throw.
 */
function spotlightAnchorRenderer(anchor, ctx) {
  const payload = anchor && anchor.payload;
  if (!payload) {
    console.warn('spotlight: anchor missing payload', anchor);
    return { stop: () => {} };
  }
  if (!ctx || !ctx.canvas) {
    console.warn('spotlight: ctx.canvas required for 2d-canvas dispatch');
    return { stop: () => {} };
  }

  // Context dispatch — A4a accepts only "2d-canvas". A4b will extend.
  if (payload.context !== '2d-canvas') {
    console.warn(
      `spotlight: unsupported context "${payload.context}". ` +
      `A4a accepts only "2d-canvas"; A4b will add "3d-three".`
    );
    return { stop: () => {} };
  }

  // Kind dispatch — A4a accepts the 3 kinds below.
  switch (payload.kind) {
    case 'swept-beam-2d': return handleSweptBeam2d(anchor, ctx);
    case 'pulsed-laser':  return handlePulsedLaser(anchor, ctx);
    case 'light-shaft':   return handleLightShaft(anchor, ctx);
    default:
      console.warn(
        `spotlight: unsupported kind "${payload.kind}". ` +
        `A4a kinds: swept-beam-2d, pulsed-laser, light-shaft. ` +
        `A4b will add: swept-beam-3d, point-light.`
      );
      return { stop: () => {} };
  }
}

registerAnchorRenderer('spotlight', spotlightAnchorRenderer);


// ─────────────────────────────────────────────────────────────────────────
// SECTION 8 — window.elsewhere.spotlightRenderer publication
// ─────────────────────────────────────────────────────────────────────────
// Matches audio.js / particle.js — exposes the renderer entry point on
// window.elsewhere.spotlightRenderer for console debugging access. Per
// CLAUDE.md "No build step" — inline scripts assume globals.

if (typeof window !== 'undefined') {
  window.elsewhere = window.elsewhere || {};
  window.elsewhere.spotlightRenderer = { spotlightAnchorRenderer };
}
