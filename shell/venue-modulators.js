// shell/venue-modulators.js
//
// The venue modulator system for Stage 7a (the prerequisites sub-stage of
// Stage 7, the karaoke read-path switch) per
// docs/VENUE-ADMIN-UI-STAGE-7A-BUILD-SPEC.md §2.
//
// Produces the real, registry-resolvable venue-level driver scalars that the
// dormant renderers reference by name — replacing the per-renderer
// PREVIEW_OSCILLATORS heuristics (the sine approximations used only so the
// admin preview "looks alive"). Three drivers across two venues:
//
//   • crowd_brightness  (stadium) — the cheer-swell scalar driving phone-light
//     opacity. Source: karaoke/stage.html:4625-4634 (crowdState / cheerSwell).
//   • beat_scale + beat_brightness (disco) — the beat-pulse scalars driving
//     mirror-ball dot size + alpha. Source: :4692-4703 (beatState / pulseBeat).
//     These two are ONE driver: a single tween chain mutates both scalars in
//     LOCKSTEP (D-lockstep) — there is no path by which they desync.
//
// Reproduces the verbatim GSAP curves in PURE JS (D-driver) — same approach,
// proven 3× against the parity bar (spotlight, overlay, 3D). One motion
// vocabulary across the whole effect layer: the ease names + exponents here
// match spotlight.js / overlay.js exactly (power2.in = t³, etc.), plus the two
// new eases this stage adds (power2.out = 1-(1-t)³, power1.in = t²). GSAP-free:
// the renderers + admin preview have no GSAP, and one vocabulary is the better
// substrate for games/wellness/worlds to inherit.
//
// ─── DORMANT in Stage 7a (D-additive) ────────────────────────────────────────
// This module is published on window.elsewhere.modulators but consulted by
// NOTHING in karaoke yet. Stage 7a ships it UNREFERENCED — no <script> tag is
// added to any page (unlike the renderer dormant-publish, whose tags actually
// register the renderer into the registry, a real side-effect; this module has
// no equivalent registration to justify a tag). Stage 7b adds the tag with the
// first consumer and threads resolveModulator into the renderers'
// computeModulatorTargets (the signature change is 7b's first move). In 7a the
// resolver + D-guard exist here purely so they are unit-testable in isolation
// (import this module in the console and drive it). The admin preview is
// unchanged — it keeps its own PREVIEW_OSCILLATORS.
//
// ─── Tick-driven, single-clock (deterministic) ───────────────────────────────
// The driver is CALLER-TICKED: tickVenueModulators(now) advances both the
// schedule and the active tween off the ONE `now` passed in (the Stage 7b render
// loop will pass its frame `now`, so driver-time == render-time, no second
// clock). Determinism: feed synthetic `now` values and the scalar curves are
// reproducible without RAF or timer mocking. The attack→decay handoff threads
// that same `now` (advanceTween calls on_complete(now); the decay stamps
// start_ms = that now) — NO performance.now() leak (that would be a second clock,
// breaking both determinism and frame-sync; using the tick `now` also matches
// GSAP's onComplete-fires-on-frame behavior, so it is parity-faithful).

// ─── Ease table ──────────────────────────────────────────────────────────────
// GSAP power-N = degree-(N+1) polynomial: power1 = quadratic, power2 = cubic,
// power3 = quartic. Exponents verified identical to spotlight.js / overlay.js
// for shared names (power2.in = t³). power2.out + power1.in are NEW this stage.
const EASE_FNS = {
  'power2.out': t => 1 - Math.pow(1 - t, 3),   // NEW — cubic out  (stadium + disco attack)
  'power1.in':  t => t * t,                     // NEW — quadratic in (stadium decay)
  'power2.in':  t => t * t * t,                 // cubic in (disco decay) — matches spotlight.js / overlay.js
};

function easeOf(name) {
  const fn = EASE_FNS[name];
  if (!fn) {
    console.warn(`[venue-modulators] unknown ease "${name}", using linear`);
    return t => t;
  }
  return fn;
}

// ─── Multi-field tween primitive (D-lockstep) ────────────────────────────────
// One tween mutates N named scalars with ONE shared eased t. Disco's two scalars
// (beat_scale, beat_brightness) are two `fields` of a single tween — they cannot
// desync because there is exactly one t and one clock. on_complete receives the
// tick `now` so the chained decay stamps the same clock (single-clock handoff).
//
//   tween = { fields:[{name,start,target}], start_ms, dur_ms, ease, on_complete }
function advanceTween(state, now) {
  const tw = state.tween;
  if (!tw) return;
  const elapsed = now - tw.start_ms;
  const t = elapsed <= 0 ? 0 : elapsed >= tw.dur_ms ? 1 : elapsed / tw.dur_ms;
  const e = easeOf(tw.ease)(t);
  for (const f of tw.fields) {
    state.scalars[f.name] = f.start + (f.target - f.start) * e;   // ALL fields, one t — lockstep
  }
  if (t >= 1) {
    state.tween = null;
    if (tw.on_complete) tw.on_complete(now);   // single-clock handoff: pass the tick `now`
  }
}

// ─── Driver definitions (per venue) ──────────────────────────────────────────
// stadium = 1 scalar; disco = 2 scalars from ONE tween (D-lockstep). Every other
// venue has no driver (resolveModulator falls through to the D-guard for them —
// but no anchor binds a driver on those venues, so it never fires in practice).
// Constants are byte-faithful to the verbatim source (fidelity table §3):
//   stadium  crowdState 0.6 → 1.4 (0.8s power2.out) → 0.6 (3s power1.in), 4s/8-16s
//   disco    beatState  scale 1→1.8 / brightness 1→1.6 (0.08s power2.out)
//            → 1 / 1 (0.35s power2.in), every BEAT = 60000/120 = 500ms
const VENUE_DRIVERS = {
  stadium: {
    fields: [{ name: 'crowd_brightness', rest: 0.6, peak: 1.4 }],
    init:   { crowd_brightness: 0.6 },
    attack: { dur_sec: 0.8, ease: 'power2.out' },
    decay:  { dur_sec: 3.0, ease: 'power1.in' },
    first_ms: 4000,
    interval_ms: () => 8000 + Math.random() * 8000,   // randomized 8–16s (verbatim source cadence)
  },
  disco: {
    fields: [
      { name: 'beat_scale',      rest: 1.0, peak: 1.8 },
      { name: 'beat_brightness', rest: 1.0, peak: 1.6 },
    ],
    init:   { beat_scale: 1.0, beat_brightness: 1.0 },
    attack: { dur_sec: 0.08, ease: 'power2.out' },
    decay:  { dur_sec: 0.35, ease: 'power2.in' },
    first_ms: 500,                 // BEAT = 60000/120
    interval_ms: () => 500,
  },
};

// ─── Lifecycle (tick-driven, single active venue) ────────────────────────────
// active = { venueId, def, scalars, tween, activatedAt, nextFireMs } | null
let active = null;

function activateVenueDrivers(venueId) {
  deactivateVenueDrivers();
  const def = VENUE_DRIVERS[venueId] || null;
  active = {
    venueId,
    def,
    scalars: def ? { ...def.init } : {},
    tween: null,
    activatedAt: null,   // set on first tick — the schedule is relative to activation time
    nextFireMs: null,
  };
}

function deactivateVenueDrivers() {
  active = null;
}

// Advance the active venue's driver(s) by one frame. Call once per render frame
// with the frame's `now` (ms). No-op when there is no active venue or the active
// venue has no driver. Scheduling fires on cadence REGARDLESS of an in-flight
// tween (gsap.to-from-current semantics: a new attack overrides a running decay).
function tickVenueModulators(now) {
  if (!active || !active.def) return;
  if (active.activatedAt === null) {
    active.activatedAt = now;
    active.nextFireMs = now + active.def.first_ms;
  }
  if (now >= active.nextFireMs) {
    startAttack(now);
    active.nextFireMs = now + active.def.interval_ms();
  }
  advanceTween(active, now);
}

// Start an attack tween from the CURRENT scalar values (from-current, matching
// gsap.to). on_complete chains the decay using the SAME tick `now` that
// completed the attack — single-clock handoff.
function startAttack(now) {
  const d = active.def;
  active.tween = {
    fields: d.fields.map(f => ({ name: f.name, start: active.scalars[f.name], target: f.peak })),
    start_ms: now,
    dur_ms: d.attack.dur_sec * 1000,
    ease: d.attack.ease,
    on_complete: (completedNow) => {
      active.tween = {
        fields: d.fields.map(f => ({ name: f.name, start: active.scalars[f.name], target: f.rest })),
        start_ms: completedNow,
        dur_ms: d.decay.dur_sec * 1000,
        ease: d.decay.ease,
        on_complete: null,
      };
    },
  };
}

// ─── The resolver + the D-guard ──────────────────────────────────────────────
// Returns the active venue's current scalar for `name`. On an unresolved name,
// the D-guard: warn LOUD + SPECIFIC on EVERY unresolved call (not throttled — a
// missing driver must be impossible to ignore), naming both the driver name AND
// the target it was for; then return identity 1.0 (deterministic, non-crashing —
// the effect renders un-modulated so you can still see WHICH effect on WHICH
// venue is wrong, while the console names exactly what failed). NEVER falls back
// to a preview oscillator — silent substitution is the exact bug class the
// explicit resolver exists to prevent. The WARN is the load-bearing signal; the
// return value's only job is "stay deterministic, don't crash."
function resolveModulator(name, target) {
  if (active && Object.prototype.hasOwnProperty.call(active.scalars, name)) {
    return active.scalars[name];
  }
  // D-guard — loud + specific on EVERY unresolved call. `target` is optional (7b: 3D
  // callers pass name-only); when absent, drop the "for target" clause rather than
  // print "for target 'undefined'". The WARN is the load-bearing signal; identity 1.0
  // keeps the effect deterministic + visible. NEVER a silent oscillator fallback.
  const where = (target === undefined || target === null) ? '' : ` for target '${target}'`;
  console.warn(`[venue-modulators] unresolved driver '${name}'${where} — returning identity 1.0`);
  return 1.0;
}

// ─── Exports + dormant publication ───────────────────────────────────────────
export { activateVenueDrivers, deactivateVenueDrivers, tickVenueModulators, resolveModulator };

if (typeof window !== 'undefined') {
  window.elsewhere = window.elsewhere || {};
  window.elsewhere.modulators = {
    activateVenueDrivers,
    deactivateVenueDrivers,
    tickVenueModulators,
    resolveModulator,
  };
}
