// shell/venue-renderers/overlay.js
//
// Overlay anchor renderer for the Venue Admin UI Stage 4.5 workstream.
// Implements venue_anchors rows of type='overlay' — screen-space visual
// overlays: a gradient or solid fill over a (normalized) canvas region,
// modulated either by a beat clock or a stochastic flicker. Registered
// to shell/venue-registry.js at module load.
//
// Three procedural ancestors translated (karaoke/stage.html @ 1fc2552):
//   • disco floor-flash  (4700-4721) — gradient-fill / beat / pulse
//   • festival strobe     (4873-4893) — solid-fill / beat / pulse
//   • honkytonk neon-tint (4837-4842) — solid-fill / stochastic / hold
//
// SELF-CONTAINED + SELF-DRIVING. Unlike particle.js / spotlight.js,
// overlay effects bind NO external venue scalar (no crowd_brightness-style
// modulator). The beat clock derives entirely from payload.modulator.bpm;
// the stochastic flicker runs its own Math.random() + frame counter. So
// this module needs NO preview oscillator — a preview animates correctly
// straight from the payload. Consequence: overlay contributes ZERO names
// to Stage 7's venue-modulator/driver registry.
//
// Per D8, importing this module does NOT change karaoke's read path.
// AMBIENT_PROFILES in karaoke/stage.html remains load-bearing until
// Stage 7. Registration is not a reader-path change (audio §8.2 Check 12
// / particle / spotlight precedent).
//
// ─── Payload contract (spec §2-§3): four orthogonal axes that compose ────
//   kind      — 'solid-fill' | 'gradient-fill'   (discriminates PAINT only)
//   region    — {x,y,w,h} normalized 0-1, default full-canvas {0,0,1,1}
//   fill      — solid-fill:   {color:"r,g,b"}      (alpha from modulator×envelope)
//               gradient-fill:{direction:"vertical", stops:[{pos,color,alpha_scale}]}
//   modulator — 'beat'       {bpm, first_trigger_beats, interval_beats, target_alpha}
//             | 'stochastic' {cooldown_frames, change_probability, states,
//                             low_state_probability, initial_state, alpha_scale}
//   envelope  — 'pulse' {rest_alpha, attack{duration_sec,ease}, decay{duration_sec,ease}}
//             | 'hold'  {}    (instant set on each event, persists until next)
//
// The renderer does two independent single-responsibility dispatches:
// on payload.kind (PAINT) and on payload.modulator.type (TIMING). The
// modulator emits (event, target_alpha); the envelope shapes the alpha
// trajectory per event; the paint draws the region at the current alpha.
// The two real pairings are (beat + pulse) and (stochastic + hold); only
// 'vertical' gradient direction is exercised in Stage 4.5 (spec D-fill).

import { registerAnchorRenderer } from '../venue-registry.js';


// ─── Pure-JS eases ────────────────────────────────────────────────────────
// Ported from spotlight.js EASE_FNS (GSAP power-N = degree-(N+1) polynomial:
// power1=quadratic, power2=cubic, power3=quartic). overlay needs power3.out
// (disco attack), power2.in (disco decay), and power1.out — NEW here: it is
// the resolution of the "default" ease sentinel. Festival's source uses
// gsap.to with NO ease key, so GSAP applies its default ease, which is
// Power1.easeOut (quadratic out). A4a's spotlight.js shipped power1.inOut,
// NOT power1.out — so this is the one ease overlay adds.
const EASE_FNS = {
  'power1.out': t => 1 - Math.pow(1 - t, 2),   // GSAP default ease (quad out)
  'power2.in':  t => t * t * t,                // cubic in
  'power3.out': t => 1 - Math.pow(1 - t, 4),   // quartic out
};

// Resolve an ease name to a function. The literal "default" maps to
// power1.out (GSAP's default ease). Unknown names fall back to linear with
// a console.warn — same fail-loud/fail-safe posture as spotlight.js easeOf.
function easeOf(name) {
  const key = name === 'default' ? 'power1.out' : name;
  const fn = EASE_FNS[key];
  if (!fn) {
    console.warn(
      `[overlay-renderer] unknown ease "${name}", using linear. ` +
      `Known: ${Object.keys(EASE_FNS).join(', ')}, default`
    );
    return t => t;
  }
  return fn;
}


// ─── Single-field alpha tween (advanceTween idiom from spotlight.js §2) ────
// state.tween = { start, target, start_ms, dur_ms, ease, on_complete } | null
// The pulse envelope chains two tweens: attack (rest→target), whose
// on_complete arms decay (target→rest). advanceTween clears the completed
// tween BEFORE invoking on_complete so the chained re-arm sticks — the
// exact ordering fix from spotlight.js's §9-step-3 review.
function advanceTween(state, now) {
  const tw = state.tween;
  if (!tw) return;
  const elapsed = now - tw.start_ms;
  const t = elapsed <= 0 ? 0 : elapsed >= tw.dur_ms ? 1 : elapsed / tw.dur_ms;
  state.alpha = tw.start + (tw.target - tw.start) * easeOf(tw.ease)(t);
  if (t >= 1) {
    state.tween = null;
    if (tw.on_complete) tw.on_complete();
  }
}


// ─── Small helpers ─────────────────────────────────────────────────────────
const clamp01 = v => (v < 0 ? 0 : v > 1 ? 1 : v);

// Map a normalized {x,y,w,h} region (0-1) to device pixels. Missing region
// degenerates to full-canvas (spec D-region default).
function regionToPx(region, w, h) {
  const r = region || { x: 0, y: 0, w: 1, h: 1 };
  return { x: r.x * w, y: r.y * h, w: r.w * w, h: r.h * h };
}


// ─── PAINT dispatch (on payload.kind) ──────────────────────────────────────
// Draws the region at the supplied alpha. Skips entirely when alpha <= 0,
// matching the source guards `if(flashState.alpha>0)` / `if(strobe.alpha>0)`
// (honkytonk's held alpha is always > 0, so it always draws — also faithful).
function paint(c, payload, alpha, w, h) {
  const a = clamp01(alpha);
  if (a <= 0) return;

  const px = regionToPx(payload.region, w, h);
  const kind = payload.kind;
  const fill = payload.fill || {};

  if (kind === 'solid-fill') {
    // fill.color is the "r,g,b" triple; alpha comes from modulator×envelope.
    c.fillStyle = `rgba(${fill.color || '255,255,255'},${a})`;
    c.fillRect(px.x, px.y, px.w, px.h);
    return;
  }

  if (kind === 'gradient-fill') {
    // Vertical linear gradient spanning the region's vertical extent
    // (top→bottom), matching disco's createLinearGradient(0, 0.6h, 0, h).
    // Stage 4.5 exercises 'vertical' only (spec D-fill).
    const grad = c.createLinearGradient(px.x, px.y, px.x, px.y + px.h);
    for (const s of (fill.stops || [])) {
      const sa = clamp01(a * (s.alpha_scale == null ? 1 : s.alpha_scale));
      grad.addColorStop(s.pos, `rgba(${s.color},${sa})`);
    }
    c.fillStyle = grad;
    c.fillRect(px.x, px.y, px.w, px.h);
  }
}


// ─── The exported renderer ──────────────────────────────────────────────────
/**
 * Renders an overlay anchor onto a 2D canvas.
 *
 * @param {Object} anchor - The venue_anchors row (must carry payload.kind)
 * @param {Object} ctx    - Consumer-supplied context object
 * @param {HTMLCanvasElement} ctx.canvas - Required: canvas to render into
 * @returns {{ stop: () => void }} - Teardown handle, parallel to audio/particle/spotlight
 */
export function overlayAnchorRenderer(anchor, ctx) {
  const payload = anchor?.payload || {};
  const canvas = ctx?.canvas;

  if (!canvas || typeof canvas.getContext !== 'function') {
    console.warn(
      '[overlay-renderer] missing or invalid ctx.canvas; expected HTMLCanvasElement',
      anchor
    );
    return { stop: () => {} };
  }

  // A4b triage 2026-05-31: hint Chrome to back this canvas with software (CPU)
  // instead of Skia GL, dodging the GPU-resource-pressure cross-context
  // contamination (see SESSION-A4B-VERIFICATION-PAUSE.md §1.6 item 4).
  const c = canvas.getContext('2d', { willReadFrequently: true });
  if (!c) {
    console.warn('[overlay-renderer] could not get 2d context', anchor);
    return { stop: () => {} };
  }

  const kind = payload.kind;
  if (kind !== 'solid-fill' && kind !== 'gradient-fill') {
    console.warn(
      '[overlay-renderer] unknown payload.kind:', kind,
      '(expected solid-fill / gradient-fill)', anchor
    );
    return { stop: () => {} };
  }

  const mod = payload.modulator || {};
  const env = payload.envelope || {};

  // Per-instance state.
  const state = {
    alpha: 0,        // current overlay alpha (0-1)
    tween: null,     // active envelope tween (pulse path only)
    frameCount: 0,   // stochastic cooldown counter (frames since last change)
  };
  let rafId = null;
  let running = true;
  const timeoutIds = [];

  // startPulse — attack tween (current→target) then, on completion, decay
  // tween (current→rest). Captures `start: state.alpha` at tween-arm time,
  // matching gsap.to's tween-from-current semantics (a new beat mid-decay
  // re-aims from wherever alpha currently is).
  function startPulse() {
    const target = mod.target_alpha == null ? 0 : mod.target_alpha;
    const rest = env.rest_alpha == null ? 0 : env.rest_alpha;
    const attack = env.attack || {};
    const decay = env.decay || {};
    state.tween = {
      start: state.alpha,
      target,
      start_ms: performance.now(),
      dur_ms: (attack.duration_sec || 0) * 1000,
      ease: attack.ease || 'default',
      on_complete: () => {
        state.tween = {
          start: state.alpha,
          target: rest,
          start_ms: performance.now(),
          dur_ms: (decay.duration_sec || 0) * 1000,
          ease: decay.ease || 'default',
          on_complete: null,
        };
      },
    };
  }

  // ─── TIMING setup: dispatch on modulator.type ───
  if (mod.type === 'beat') {
    // Rest at the envelope's resting alpha (0 for disco/festival) between
    // pulses. Beat scheduler: first event at BEAT*first_trigger_beats, then
    // every BEAT*interval_beats. setTimeout chain (cleared on stop) — the
    // spotlight.js beat-pulse idiom.
    state.alpha = env.rest_alpha == null ? 0 : env.rest_alpha;
    const BEAT = 60000 / mod.bpm;
    const interval = mod.interval_beats == null ? 1 : mod.interval_beats;
    const first = mod.first_trigger_beats == null ? 0 : mod.first_trigger_beats;
    const fireBeat = () => {
      if (!running) return;
      if (env.shape === 'hold') {
        // beat + hold (not used by the three effects, but composes): set
        // the target instantly, no envelope tween.
        state.alpha = clamp01(mod.target_alpha == null ? 0 : mod.target_alpha);
      } else {
        startPulse();
      }
      timeoutIds.push(setTimeout(fireBeat, BEAT * interval));
    };
    timeoutIds.push(setTimeout(fireBeat, BEAT * first));
  } else if (mod.type === 'stochastic') {
    // Held value, initialized to initial_state * alpha_scale. The per-frame
    // trial runs inside the RAF frame (it needs the frame cadence — the
    // cooldown is frame-counted, preserved for parity with the procedural
    // ancestor per spec §2.4 D-framerate).
    const scale = mod.alpha_scale == null ? 1 : mod.alpha_scale;
    state.alpha = (mod.initial_state == null ? 1 : mod.initial_state) * scale;
  } else {
    console.warn(
      '[overlay-renderer] unknown modulator.type:', mod.type,
      '(expected beat / stochastic) — overlay will hold its initial alpha',
      anchor
    );
  }

  // ─── RAF loop ───
  function frame(now) {
    if (!running) return;

    // Canvas size read each frame — admin DOM may resize between frames.
    const w = canvas.width;
    const h = canvas.height;

    if (mod.type === 'beat') {
      advanceTween(state, now);
    } else if (mod.type === 'stochastic') {
      state.frameCount++;
      const cooldown = mod.cooldown_frames == null ? 0 : mod.cooldown_frames;
      const prob = mod.change_probability == null ? 0 : mod.change_probability;
      if (state.frameCount > cooldown && Math.random() < prob) {
        const states = mod.states || [0, 1];
        const lowP = mod.low_state_probability == null ? 0.5 : mod.low_state_probability;
        const scale = mod.alpha_scale == null ? 1 : mod.alpha_scale;
        const chosen = Math.random() < lowP ? states[0] : states[1];
        state.alpha = chosen * scale;
        state.frameCount = 0;
      }
    }

    c.clearRect(0, 0, w, h);
    paint(c, payload, state.alpha, w, h);

    rafId = requestAnimationFrame(frame);
  }
  rafId = requestAnimationFrame(frame);

  function stop() {
    running = false;
    if (rafId !== null) {
      cancelAnimationFrame(rafId);
      rafId = null;
    }
    while (timeoutIds.length) clearTimeout(timeoutIds.pop());
    state.tween = null;
    try {
      c.clearRect(0, 0, canvas.width, canvas.height);
    } catch (_) {
      // canvas may have been removed from DOM; ignore.
    }
  }

  return { stop };
}


// ─── Registration ───────────────────────────────────────────────────────────

registerAnchorRenderer('overlay', overlayAnchorRenderer);

if (typeof window !== 'undefined') {
  window.elsewhere = window.elsewhere || {};
  window.elsewhere.overlayRenderer = {
    overlayAnchorRenderer,
  };
}
