# Venue Admin UI — Stage A4a Build Spec

Status: binding spec for the A4a implementation cycle.
Extends: docs/VENUE-ADMIN-UI-DIRECTION.md §7 (the A1–A9 staging, updated
2026-05-27 commit c2de05f). A4 is sub-staged into A4a + A4b — see §0.2.
Foundation pass that produced the inventory + the decisions encoded
here: planning chat 2026-05-27 (CLR-A4-1 through CLR-A4-8 resolutions
D1–D6 below).

═══════════════════════════════════════════════════════════════════════
§0 — CONTEXT AND RE-STAGING
═══════════════════════════════════════════════════════════════════════

§0.1 — What A4a is
A4a is the fourth Block A vertical slice: a spotlight anchor renderer +
a spotlight authoring panel in admin-venues.html + a seed migration
(db/037) translating the procedural 2D spotlight effects of 3 karaoke
venues (stadium, festival, speakeasy) into data-driven venue_anchors
rows of type='spotlight'.

It follows the pattern A2/A3 set: a self-registering renderer module in
shell/venue-renderers/, an authoring panel added to admin-venues.html,
a seed migration, and a one-line registration <script> tag in
karaoke/stage.html. Per D8, everything ships DORMANT — the seeded
anchors are data only, karaoke's read path is unchanged, the
procedural AMBIENT_PROFILES spotlight code stays load-bearing until
Stage A7 (the read-path switch + AMBIENT_PROFILES retirement).

§0.2 — Relationship to A4b (the 3D extension stage)
A4 was sub-staged into A4a + A4b in planning chat 2026-05-27. A4a
covers 2D-canvas spotlight only. A4b covers the 3D spotlight builders
(stadium 4 cone meshes, speakeasy 40 candle Points), the absorbed 3D
particle paths (stadium 2000 THREE.Points phone-lights, speakeasy 60
sphere-mesh smoke), and the new Three.js preview surface in
admin-venues.html.

The sub-staging rationale, locked: A4 surface is 1.5–2× A3's; the 3D
preview is genuinely new architectural territory (admin-venues.html
has zero Three.js code today); sub-staging isolates the
3D-preview-surface risk to A4b so 2D spotlights can ship on the A3
precedent. A4b ships as its own propose-pause cycle after A4a's
closeout.

A4a's payload contract is FORWARD-COMPATIBLE with A4b — the context
field is declared and the kind set is open — but A4a does NOT
pre-commit 3D fields in its kinds. A4b will introduce
swept-beam-3d and point-light as SIBLING kinds (not 3D branches of
A4a's kinds), per D6 below.

§0.3 — A4a's scope: exactly 3 anchors across 3 venues
  • stadium   — 4 sweeping spotlight beams   → kind: swept-beam-2d
  • festival  — 6 beat-pulsing lasers        → kind: pulsed-laser
  • speakeasy — 3 drifting amber light shafts → kind: light-shaft

OUT OF A4a SCOPE, stated explicitly so an implementer does not
translate them:
  • Stadium 3D cone meshes (karaoke/stage.html:2884-2935), speakeasy
    3D candle Points (2980-3000) — A4b's spotlight 3D scope.
  • Stadium 3D phone-lights (2861-2882, 2000 THREE.Points), speakeasy
    3D smoke (2946-3027, 60 sphere meshes) — A4b's absorbed-3D
    particle scope, deferred from A3 §0.2.
  • Festival strobe (4860-4872, full-screen white flash on every 4th
    beat) — overlay-class, Stage A4.5.
  • Disco floor-flash (4683-4694, full-screen pink/purple gradient
    flash on beat) — overlay-class, Stage A4.5. Disco appears
    NOWHERE in A4a — its only spotlight-candidate effect was the
    floor-flash, and the foundation pass classified that as
    overlay-class.
  • Honkytonk neon-tint flicker (4829-4842, full-screen
    rgba(255,100,50,…) tint with random alpha toggle) — overlay-class,
    Stage A4.5. Surfaced by the foundation pass (§10.2), not in the
    original Direction §7 A4.5 enumeration; the DEFERRED entry
    covering A4.5 picks it up.
  • The 4 ghost venues (space, forest, underwater, dead-dragonlair).
    None have spotlight or 3D content (foundation pass §10.1
    verified). Stage A7 cleanup territory. See §6.

═══════════════════════════════════════════════════════════════════════
§1 — THE SPOTLIGHT PAYLOAD CONTRACT
═══════════════════════════════════════════════════════════════════════

§1.1 — Discriminated union, keyed by payload.kind
Spotlight anchors are venue_anchors rows with type='spotlight'. The
type column is unchanged from db/032's vocabulary — 'spotlight' is
already a permitted value (db/032:253-258) and already in db/035's
v_known_types array (db/035:93-94). NO schema change.

payload.kind is the discriminator. A4a ships THREE kinds, all
2D-canvas:
  • swept-beam-2d — N gradient-trapezoid beams, top-pivot, with
                    GSAP-equivalent slow angle sweep + alpha tween.
                    Stadium 4-beam case is canonical.
  • pulsed-laser  — N narrow rotated lasers, bottom-pivot, with base
                    angle drift + fast beat-pulse on alpha + width.
                    Festival 6-laser case is canonical.
  • light-shaft   — N vertical trapezoid shafts (no rotation), with
                    GSAP-equivalent slow x-drift + alpha breath.
                    Speakeasy 3-shaft case is canonical.

The kind boundary is defined by RENDER GEOMETRY + MOTION TIMELINE,
not by field presence:
  - swept-beam-2d = top-pivot rotating trapezoid + per-beam slow
                    continuous sweep
  - pulsed-laser  = bottom-pivot rotating narrow rect + base drift
                    + per-beat alpha+width pulse
  - light-shaft   = no-rotation vertical trapezoid + per-shaft slow
                    x-drift + alpha breath
Per D6, A4b introduces swept-beam-3d (stadium 3D cones) and
point-light (speakeasy 3D candles) as SIBLING kinds — not as 3D
branches of A4a's kinds. The 2D and 3D variants of the conceptually
"same" effect remain separate kinds for renderer-implementation
clarity.

§1.2 — Shared field fragments
A4a's spotlight contract inherits the SHARED FRAGMENT mechanism A3
established. The fragments declared once in particle.js's payload
schema and used uniformly across kinds are reused here. DO NOT
re-declare them — A4a's renderer imports/duplicates the same
semantics.

  fragment "color":
    one of:
      { "mode": "fixed", "value": "rgb(255,255,255)" }                 // RGB only — alpha is NEVER inside the color string
    The color fragment carries a single shared color across all items
    of an anchor. For kinds with per-item color variation (swept-beam-2d
    and pulsed-laser, both hue-driven), the color fragment is OMITTED;
    per-item color comes from the top-level `hues` array (§1.6
    count:N pattern) combined with shared `geometry.sat_pct` /
    `geometry.lit_pct`. The hue_range mode is reserved for future
    kinds that need range-distributed hues per item — A4a does not
    use it (A3 particle.js uses hue_range for disco mirror-ball
    point-cloud + festival confetti directional-emitter, but those
    are particle kinds, not spotlight kinds).
    Of A4a's three kinds, only light-shaft carries a color fragment
    (fixed RGB amber).
  fragment "modulator" (optional, cite A3 spec §1.6):
    Inherited by reference from docs/VENUE-ADMIN-UI-A3-BUILD-SPEC.md
    §1.6. Shape: single binding object OR array of binding objects,
    each {name: <string>, target: <particle property name>}. Per D5,
    A4a's three kinds bind NO modulators — every animated scalar is
    kind-internal payload (BPM, sweep_duration_range, alpha range,
    width range, attack/decay ms). The modulator field is declared
    optional in each kind's schema for forward compatibility but
    every A4a seed row OMITS it. A7 builds the driver registry;
    A4a contributes nothing to it.

Alpha model — uniform across spotlight kinds. Alpha is ALWAYS its
own field, never embedded in the color string. The renderer
combines alpha sources as follows:
  - per-item base alpha drawn from a base_alpha_range or
    base_alpha scalar (kind-specific naming, see §1.3-1.5);
  - kind-internal motion (sweep tween for swept-beam-2d,
    beat-pulse tween for pulsed-laser, drift tween for
    light-shaft) mutates that per-item alpha over time;
  - the final alpha is clamped to [0,1] at draw time.
There is no fade_rate analog for A4a spotlights — every spotlight
kind ships eternal items (no death, no respawn). The per-item alpha
is bounded by the kind's tween range, which is itself bounded.

§1.3 — swept-beam-2d schema
Canonical case: stadium count:4. Source: karaoke/stage.html:4593-4666.

{
  "kind": "swept-beam-2d",
  "context": "2d-canvas",
  "count": 4,
  // Per-beam arrays (length = count) per §1.6:
  "hues": [220, 200, 240, 180],                  // HSL hue per beam
  "angle_init": [-0.375, -0.125, 0.125, 0.375],  // formula in source: (i-1.5)*0.25
  // Shared scalars across all beams:
  "base_alpha_range": [0.08, 0.14],              // per-beam initial: 0.08 + rand*0.06
  "sweep_target_range": [-0.425, 0.425],         // each sweep targets (rand-0.5)*0.85
  "sweep_alpha_range": [0.06, 0.16],             // re-tweened alpha range: 0.06 + rand*0.1
  "sweep_duration_range_ms": [1500, 4000],       // 1.5 + rand*2.5 seconds
  "sweep_ease": "power1.inOut",                  // GSAP-equivalent per §3.5
  "stagger_ms": 800,                             // beams start staggered
  // Geometry — shared linear gradient trapezoid:
  "geometry": {
    "pivot": "top-center",                       // c.translate(ambientW/2, 0) — pivot at top-center of canvas
    "top_width_px": 12,                          // c.moveTo(-6,0) → c.lineTo(6,0)
    "bottom_width_norm": 1.0,                    // c.lineTo(±ambientW*0.5, ambientH)
    "height_norm": 1.0,                          // gradient runs full canvas height
    "sat_pct": 80,                               // hsla saturation
    "lit_pct": 95,                               // hsla lightness
    "gradient_stops": [
      { "at": 0,   "alpha_mult": 1.0 },          // c.createLinearGradient(0,0,0,ambientH).addColorStop(0, alpha)
      { "at": 0.5, "alpha_mult": 0.4 },          // .addColorStop(0.5, alpha*0.4)
      { "at": 1,   "alpha_mult": 0.0 }           // .addColorStop(1, 0)
    ]
  },
  // No color fragment — hue-driven kind uses top-level `hues` array
  // (§1.6 count:N pattern) + shared geometry.sat_pct/lit_pct. See §1.2.
  // No modulator for A4a per D5
}

The angle_init array can be expressed as a formula reference in the
panel form OR as an explicit length-4 array. Implementation proposal
§9 step 4 picks the form. The seed migration emits the explicit
array (deterministic, no runtime formula evaluation).

§1.4 — pulsed-laser schema
Canonical case: festival count:6, BPM:128. Source:
karaoke/stage.html:4844-4916.

{
  "kind": "pulsed-laser",
  "context": "2d-canvas",
  "count": 6,
  // Per-laser arrays (length = count) per §1.6:
  "hues": [0, 60, 120, 180, 240, 300],           // i*60
  "angle_init": [1.1, 0.96, 0.82, 0.68, 0.54, 0.40],  // π*0.35 - i*0.14
  "drift_speeds": [-0.005, 0.005, -0.005, 0.005, -0.005, 0.005],  // (i%2 ? 1 : -1) * 0.005 — i=0 evaluates 0%2=0 (falsy)→-1, so negative-first
  "base_widths_px": [3, 5, 3, 5, 3, 5],          // 3 + (i%2)*2
  // Shared scalars across all lasers:
  "bpm": 128,                                    // 469ms per beat
  "drift_range": 1.508,                          // |angle| > π*0.48 → reflect
  "base_alpha": 0.35,                            // per-laser steady alpha
  "peak_alpha": 0.85,                            // GSAP pulse target
  "peak_width_mult": 2.5,                        // pulse width = base * 2.5
  "attack_ms": 60,                               // gsap.to duration: 0.06
  "attack_ease": "power3.out",                   // GSAP-equivalent per §3.5
  "decay_ms": 380,                               // gsap.to duration: 0.38
  "decay_ease": "power2.in",
  "first_pulse_offset_beats": 0.5,               // setTimeout(beatPulse, BEAT * 0.5) — first pulse fires half a beat after start
  // Geometry — bottom-pivot rotated rect with linear gradient:
  "geometry": {
    "pivot": "bottom-center",                    // c.translate(ambientW/2, ambientH)
    "emit_direction": "up",                      // gradient axis 0,0,0,-ambientH
    "height_norm": 1.0,                          // fillRect(-w/2, -ambientH, w, ambientH)
    "sat_pct": 100,
    "lit_pct": 65,
    "gradient_stops": [
      { "at": 0,   "alpha_mult": 1.0 },          // .addColorStop(0, alpha)
      { "at": 0.6, "alpha_mult": 0.3 },          // .addColorStop(0.6, alpha*0.3)
      { "at": 1,   "alpha_mult": 0.0 }           // .addColorStop(1, 0)
    ]
  },
  // No color fragment — hue-driven kind uses top-level `hues` array
  // (§1.6 count:N pattern) + shared geometry.sat_pct/lit_pct. See §1.2.
  // No modulator for A4a per D5
}

The pulse cadence is BPM-derived: the renderer schedules a pulse
every (60000 / bpm) ms; first pulse fires at (BEAT * 0.5) per the
source's `setTimeout(beatPulse, BEAT * 0.5)`.

§1.5 — light-shaft schema
Canonical case: speakeasy count:3. Source:
karaoke/stage.html:4762-4827.

{
  "kind": "light-shaft",
  "context": "2d-canvas",
  "count": 3,
  // Per-shaft arrays (length = count):
  "x_init_norm": [0.25, 0.50, 0.75],             // ambientW*(0.25 + i*0.25) → normalized
  // Shared scalars across all shafts:
  "base_alpha_range": [0.04, 0.08],              // 0.04 + rand*0.04
  "width_range_px": [60, 100],                   // 60 + rand*40
  "drift_distance_px": 80,                       // (rand-0.5)*80
  "drift_alpha_range": [0.03, 0.09],             // re-tweened: 0.03 + rand*0.06
  "drift_duration_range_ms": [4000, 8000],       // 4 + rand*4 seconds
  "drift_stagger_max_ms": 2000,                  // setTimeout(driftShaft, rand*2000)
  "drift_ease": "sine.inOut",                    // GSAP-equivalent per §3.5
  // Geometry — vertical trapezoid (no rotation):
  "geometry": {
    "pivot": "top",                              // top edge at y=0
    "top_inset_factor": 0.3,                     // c.moveTo(s.x - s.width*0.3, 0)
    "bottom_outset_factor": 1.0,                 // c.lineTo(s.x ± s.width, ambientH*0.7)
    "height_norm": 0.7,                          // ambientH*0.7
    "gradient_stops": [
      { "at": 0, "alpha_mult": 1.0 },            // .addColorStop(0, rgba(...,alpha))
      { "at": 1, "alpha_mult": 0.0 }             // .addColorStop(1, rgba(...,0))
    ]
  },
  "color": { "mode": "fixed", "value": "rgb(255,210,140)" },
  // No modulator for A4a per D5
}

light-shaft has no rotation — shafts only drift on x and alpha. This
is the kind boundary distinguishing it from swept-beam-2d (which
rotates) and pulsed-laser (which rotates + beat-pulses).

§1.6 — count:N + per-item arrays pattern (D2 / Option C hybrid)
The Option C hybrid resolved in CLR-A4-5: count:N for uniform groups
where the items share structural shape but vary in indexed parameters.
Stadium 4 beams, festival 6 lasers, speakeasy 3 shafts all match —
each item is the same render geometry with per-index variation in a
small set of fields.

Convention:
  - Fields that vary per item are ARRAYS of length `count`.
  - Fields uniform across items are SCALARS.
  - The renderer iterates 0..count-1 and reads array[i] or the
    scalar accordingly.
  - The schema declares which fields are arrays via naming (plural
    nouns for arrays: `hues`, `angle_init`, `drift_speeds`,
    `base_widths_px`, `x_init_norm`). The implementation can also
    use Array.isArray() checks defensively, but the contract is
    that array fields use plural names.

Example unpacking (festival pulsed-laser, count:6):

  payload.hues          → [0, 60, 120, 180, 240, 300]  // 6 entries
  payload.angle_init    → [1.1, 0.96, …, 0.40]         // 6 entries
  payload.drift_speeds  → [0.005, -0.005, …, -0.005]   // 6 entries
  payload.base_widths_px → [3, 5, 3, 5, 3, 5]          // 6 entries
  payload.bpm           → 128                           // scalar
  payload.peak_alpha    → 0.85                          // scalar

Renderer: for (let i = 0; i < payload.count; i++) {
  const laser = {
    hue:        payload.hues[i],
    angle:      payload.angle_init[i],
    driftSpeed: payload.drift_speeds[i],
    baseWidth:  payload.base_widths_px[i],
    currentAlpha: payload.base_alpha,                   // shared scalar
    currentWidth: payload.base_widths_px[i],
  };
  …
}

PERMIT multi-anchor (D2): a venue may have multiple spotlight
anchors. A4a's 3 in-scope venues each have exactly 1, but the PERMIT
rule is the schema invariant for forward compatibility — speakeasy
already needs PERMIT in A4b (it gains a point-light candle anchor
alongside its light-shaft anchor). Panel UI per §4.5.

§1.7 — payload.context = "2d-canvas"
Every A4a seed row's payload carries `"context": "2d-canvas"`. This
is the discriminator A4b extends with `"3d-three"`. A4a's spotlight
renderer:
  - dispatches on context: only "2d-canvas" is handled
  - if context is missing or any other value, the renderer warns
    via console.warn and returns {stop: () => {}} (no-op handle)
  - this posture mirrors A3's particle.js with unknown payload.kind
    values — fail loud (console), fail safe (no throw, no broken
    handle).

§1.8 — Known uncovered patterns / A4b kind reservations
A4a's contract leaves space for A4b's sibling kinds without
specifying them. The following names are RESERVED — A4a does not
register them, does not emit seed rows of these kinds, but
documents them so the kind namespace is coherent across stages:

  • swept-beam-3d — A4b. Stadium 3D cone meshes. Renderer reads
                    `context: "3d-three"` and constructs THREE.Mesh
                    cone instances via ctx.scene. Sibling to
                    swept-beam-2d, not a 3D branch of it.
  • point-light   — A4b. Speakeasy 3D candle Points. Renderer
                    constructs THREE.Points with PointsMaterial.
                    Closest 3D analog of swept-beam in concept
                    (point-source light) but renders as sprite
                    points, not beam geometry.

A4b's spec defines these kinds in full. A4a's renderer must not
register them and must not accept payloads with these kind values.
If the renderer receives an unknown kind (any value not in A4a's
three-kind set: swept-beam-2d / pulsed-laser / light-shaft), it
warns via console.warn and returns { stop: () => {} } as a no-op
handle — same posture as §1.7's unknown-context handling. Fail
loud (console), fail safe (no throw, no broken handle).

═══════════════════════════════════════════════════════════════════════
§2 — db/037 — THE SPOTLIGHT 2D ANCHOR SEED MIGRATION
═══════════════════════════════════════════════════════════════════════

§2.1 — No new RPCs
db/035's rpc_venue_anchor_upsert and rpc_venue_anchor_delete are
type-agnostic — db/035 declares v_known_types including 'spotlight'
(db/035:93-94) and validates against the full vocabulary. A4a needs
NO new RPCs. db/037 is a SEED-ONLY migration.

§2.2 — Migration content
db/037_spotlight_anchor_seed.sql — one transactional file:
  - 3 INSERT rows into public.venue_anchors, type='spotlight', one
    per in-scope venue, with deterministic ids
    anc_spot_<venue_id>:
      anc_spot_stadium, anc_spot_festival, anc_spot_speakeasy
  - Each row's payload is the kind-appropriate schema from §1.3-1.5,
    transcribed from the procedural code at the cited line numbers.
    label = 'Spotlights' for all 3 (parallel to A2's 'Ambient' and
    A3's 'Particles').
  - ON CONFLICT (id) DO NOTHING for idempotency (db/035/036 seed
    pattern).
  - The payload values are NOT invented — they are read off the
    procedural code. The implementation cycle must quote each
    procedural source block (§9 step 1) and show the payload it
    produces, for review, BEFORE the migration is finalized.
    Payload-vs-source fidelity is the load-bearing review step,
    same as A3.

Position consistency. All 3 anchors are 2D-canvas screen-space
overlays (not sphere-pinned), so yaw_deg and pitch_deg are both
NULL — satisfies db/032's venue_anchors_position_consistency CHECK
constraint, which is the type-agnostic paired-NULL rule.

§2.3 — Verification footer
db/037 carries a verification-query footer (db/034/035/036 pattern):
  - Q1: count(*) where type='spotlight' = 3
  - Q2: the 3 rows, ordered by venue_id; id matches
    anc_spot_<venue_id>; payload->>'kind' is the expected kind per
    venue; label='Spotlights'
  - Q3: each payload validates against its kind schema (spot-check
    payload->>'kind', payload->'count', and one kind-required
    marker field per kind — e.g. `hues` array length matches count,
    `bpm` present on pulsed-laser, `x_init_norm` array length
    matches count on light-shaft).
No anon/grant checks needed — db/037 creates no functions.

§2.4 — Migrations tracker
db/037 is recorded in db/MIGRATIONS_APPLIED.md AFTER prod apply, per
doctrine. MIGRATIONS_APPLIED.md is ordered by apply-date, not
migration number — record db/037's actual row position, do not
assume.

═══════════════════════════════════════════════════════════════════════
§3 — shell/venue-renderers/spotlight.js — THE RENDERER MODULE
═══════════════════════════════════════════════════════════════════════

§3.1 — Self-contained
spotlight.js is SELF-CONTAINED. It re-implements its own animation
state (per-item arrays for active tweens, current values, target
values, start times) and its own RAF loop, and renders into a canvas
reference passed to it via ctx. It does NOT import, wrap, or call
karaoke/stage.html's spawnParticles / startParticleLoop / the
beam/laser/shaft closures in AMBIENT_PROFILES — those mutate
karaoke's shared global state, and calling them would inject preview
content into karaoke's live loop. Karaoke stays byte-for-byte
untouched (D8). This parallels A2's audio.js and A3's particle.js.

§3.2 — Registration
spotlight.js registers on the anchor registry at module load:
  registerAnchorRenderer('spotlight', spotlightAnchorRenderer)
exposed via window.elsewhere.anchorRegistry per
shell/venue-registry.js. Same mechanism as audio.js / particle.js.

§3.3 — Renderer contract
The renderer is given a spotlight anchor (the venue_anchors row) and
a 2D-canvas render target. Entry signature:

  spotlightAnchorRenderer(anchor, ctx) → { stop }

where ctx.canvas is the HTMLCanvasElement render target. The
renderer:
  - parses payload.context; if not "2d-canvas", warns + returns
    { stop: () => {} } no-op handle (§1.7)
  - parses payload.kind, dispatches to the kind's update/draw logic;
    unknown kind → same no-op posture
  - iterates count:N items per §1.6 — instantiates a per-item state
    object holding the kind-specific runtime fields (current alpha,
    current angle, current width, current x, active tween record)
  - owns a private animation-state array + RAF loop for that effect
  - applies kind-specific motion (sweep tween for swept-beam-2d,
    beat-pulse tween for pulsed-laser, drift tween for light-shaft)
    per §3.5
  - exposes a teardown: state-array purge + RAF cancel + canvas
    clear

Per D4 (RAF ownership): A4a's renderer OWNS its RAF and returns
{ stop }, matching the A3 particle.js precedent. A4a is 2D-only so
this is the only path. A4b introduces caller-owns-RAF for 3D
(renderers return { update, stop } and the admin preview owns the
loop) — A4a does NOT pre-commit to that API change.

§3.4 — Directory
spotlight.js goes in the existing shell/venue-renderers/ directory
alongside audio.js and particle.js. A4a does NOT split into
spotlight-2d.js / spotlight-3d.js — A4a is 2D-only by design and
A4b will EXTEND the same file (not split). The file gains new kinds
in A4b; the 2D kinds A4a ships remain registered under
type='spotlight'.

§3.5 — GSAP-equivalent motion (no GSAP dependency)
The procedural source uses GSAP extensively. Stadium beams: recursive
gsap.to with power1.inOut ease + onComplete chaining. Festival
lasers: two-phase gsap.to (attack power3.out → onComplete → decay
power2.in). Speakeasy shafts: recursive gsap.to with sine.inOut ease
+ onComplete chaining.

A4a's renderer reproduces these timelines semantically WITHOUT a GSAP
dependency — there is no GSAP import in shell/venue-renderers/ and
this spec does not introduce one. The mechanism: requestAnimationFrame
+ per-tween elapsed-time tracking + pure JS ease functions.

Ease functions needed, by kind:
  • swept-beam-2d  → power1.inOut (stadium beams' sweepBeam tween)
  • pulsed-laser   → power3.out (attack phase) + power2.in (decay
                     phase) — two-phase envelope per beat
  • light-shaft    → sine.inOut (speakeasy shafts' driftShaft tween)

The explicit per-tween state shape, the pure-JS ease-function
implementations, and the per-kind timeline reconstruction (mapping
each GSAP call in the procedural source to its renderer counterpart)
are §9 step 3 implementation-proposal content — propose-pause-review
items, not spec-binding content. Source fidelity is load-bearing:
the proposal quotes the procedural source side-by-side with the
renderer reconstruction so the reviewer can verify each GSAP
parameter maps correctly. Same posture A3 spec §9 step 3 took for
the CLR-5/6/7 renderer-contract items.

═══════════════════════════════════════════════════════════════════════
§4 — admin-venues.html — THE SPOTLIGHT AUTHORING PANEL
═══════════════════════════════════════════════════════════════════════

§4.1 — Panel placement
A spotlight anchor panel is added to admin-venues.html, sibling to
A2's audio anchor panel and A3's particle anchor panel, below the
venue_defaults editor. Shows spotlight anchors for the selected
venue (0 or, for the 3 in-scope venues post-seed, 1; potentially
more in future under PERMIT).

§4.2 — Per-kind form
KIND-DISCRIMINATED, mirroring A3's particle panel pattern.
Selecting/displaying a kind shows that kind's fields (§1.3-1.5). The
shared form structure (anchor row, kind selector, save/delete/preview
controls, dirty tracking) reuses A3's pattern verbatim. The
implementation proposal §9 step 4 must show the form structure for
all 3 A4a kinds for review.

§4.3 — count:N + per-item array fields
Per-item array fields (e.g. stadium's hues array of length 4,
festival's hues/angle_init/drift_speeds/base_widths_px arrays of
length 6) display in the panel as JSON textareas — mirroring A3's
pattern for arrays inside particle payloads. The textarea content is
parsed on save and round-trips with the payload.

Validation on save:
  - count must be a positive integer
  - each array field's length must equal count; mismatch → save
    blocked with an inline error showing "expected N items, got M"
  - scalar fields parse as numbers (NaN blocks save)

The implementation proposal must show how a count:6 festival
anchor's per-laser arrays display in the form, including the
validation surface when an array length diverges from count.

§4.4 — Preview surface
The panel includes a bounded 2D-canvas preview area. Clicking Preview
renders the spotlight effect live into that canvas using
spotlight.js; editing payload fields re-renders (debounced or
explicit re-render button per implementation proposal). The preview
canvas is owned by the admin page — NOT karaoke's #ambient-layer.

2D ONLY. No Three.js in admin-venues.html for A4a. A4b adds the
Three.js scaffolding for 3D preview; A4a leaves that surface
untouched. The preview must be bounded (spotlight content must not
overflow into other admin UI areas) and must have a Stop control.

The preview reuses A3's particle preview lifecycle pattern: a Stop
button cancels the active RAF and clears the canvas; switching
anchors stops any active preview first; navigating away from the
admin page stops everything.

§4.5 — Lifecycle
Create / save / delete / preview, mirroring A2/A3 audio + particle
panel lifecycles and reusing the rpc_venue_anchor_upsert and
rpc_venue_anchor_delete calls.

Multi-anchor policy: PERMIT per D2 — a venue may have multiple
spotlight anchors. "+ Add" remains available regardless of how many
spotlight anchors already exist on the selected venue. (A4a's 3
in-scope venues each have exactly 1 spotlight anchor, but the PERMIT
rule is the schema invariant for forward compatibility — speakeasy
gains a 2nd spotlight anchor in A4b when point-light candles ship,
and future venues may layer effects.)

This diverges from A2 (audio: PREVENT — one audio anchor per venue)
and A3 (particle: PREVENT — one particle anchor per venue). The
PERMIT rule is intentional and locked per D2; do not import A2/A3's
"+ Add hides when one exists" behavior.

§4.6 — Version label
admin-venues.html currently displays v2.138 (set in A3's
implementation commit e9c52e9 + closeout). A4a touches
admin-venues.html — bump the badge to the next number. The
implementation proposal proposes the exact number against the count
of admin-venues.html touches since A3 (which may include the doc
catch-up pass or any interim commits the implementation cycle
discovers). Provisional target: v2.139 if A4a is the only
admin-venues.html change since A3 closeout.

§4.7 — karaoke/stage.html
One-line addition: a <script type="module"> tag loading
spotlight.js, alongside audio.js's and particle.js's tags.
Registration only — permitted per D8 / A2 Check 12 / A3 Check 18
precedent. No other karaoke change.

═══════════════════════════════════════════════════════════════════════
§5 — D8 / DORMANCY
═══════════════════════════════════════════════════════════════════════

A4a ships dormant, exactly as A2 and A3 did:
  - The 3 seeded spotlight anchors are data; karaoke's read path
    does not consult them.
  - The procedural beam / laser / shaft closures inside
    AMBIENT_PROFILES.<venue>.anim() remain load-bearing.
  - addVenueEffects3D stays untouched (A4a doesn't touch 3D anyway).
  - spotlight.js is registered but has no live consumer in karaoke;
    its only consumer is the admin panel's preview.
Stage A7 (the read-path switch + AMBIENT_PROFILES retirement)
promotes the registry path to canonical. A4a makes NO karaoke
read-path change.

No dormancy hazards identified for the spotlight 2D work
(foundation pass §9). The GSAP-equivalent motion in spotlight.js is
internal to the renderer; spotlight.js is module-scoped and does
not touch karaoke's gsap import, AMBIENT_PROFILES, or any global
state.

═══════════════════════════════════════════════════════════════════════
§6 — GHOST-CODE BOUNDARY
═══════════════════════════════════════════════════════════════════════

The 4 ghost venues (space, forest, underwater, dead-dragonlair) are
Stage A7 cleanup territory per the "ghost venue keys deleted during
A7 retirement pass" DEFERRED entry. None have spotlight or 3D
content (foundation pass §10.1 verified — spacestation,
enchantedforest, dragonlair all have `anim: null`; "underwater" has
no venue key at all). A4a leaves all ghost code untouched.

═══════════════════════════════════════════════════════════════════════
§7 — DEFERRED ITEMS A4a GENERATES
═══════════════════════════════════════════════════════════════════════

Anticipated entries to file at A4a closeout (NOT now). Final list
determined during implementation + verification; this section
enumerates the planning-time anticipation:

  1. A4a ships modulator-free spotlights per D5. The 2D phone-lights
     particle anchor that A3 shipped is currently the only
     modulator binding in the workstream (crowd_brightness → alpha).
     A4b's 3D phone-lights anchor binds the same modulator for
     parity (synthesized — the source uses frame-counter sin, but
     the binding is the conceptually correct one). A4a contributes
     nothing to the modulator-driver inventory A7 will build. File
     a DEFERRED entry noting the A4b synthesis decision so A7
     understands the full inventory of names it must implement.

  2. PERMIT multi-anchor rule per D2 is a UI behavior. The form-swap
     behavior currently assumes "one anchor at a time, kind
     selector picks which kind to show" — works for A4a's 1
     anchor-per-venue reality. When A4b ships speakeasy with both
     light-shaft AND point-light anchors, the panel's per-kind
     dispatch needs to surface BOTH anchors in the same panel
     (anchor list + per-anchor editor). A4a's panel must not block
     this evolution. File a DEFERRED entry capturing the structural
     multi-anchor authoring question.

  3. The GSAP-equivalent motion implementation in spotlight.js
     (§3.5) reproduces source ease curves. The reconstruction is
     mathematically equivalent within numerical precision but A7's
     read-path switch is the first time the registry-driven path
     runs in production. If A7 reveals a visible divergence between
     source GSAP behavior and renderer behavior — e.g. timing
     accumulator drift over long sessions, or ease-curve asymmetry
     near t=0/t=1 — the ease functions may need refinement. File a
     DEFERRED entry covering this verification gap.

Final list filed at closeout. The implementation cycle may surface
additional items.

═══════════════════════════════════════════════════════════════════════
§8 — VERIFICATION CHECKLIST
═══════════════════════════════════════════════════════════════════════

Run after db/037 + spotlight.js + the admin panel ship. Mirrors A3's
§8 structure. Numbered Checks 19–24, continuing from A3's 13–18.

Check 19 — Spotlight renderer registered.
  Load karaoke/stage.html. Console:
  window.elsewhere.anchorRegistry.getAnchorRenderer('spotlight')
  returns the renderer function (not null).

Check 20 — Seed verification.
  db/037's footer queries Q1–Q3: 3 spotlight anchors, ids
  anc_spot_<venue> for stadium / festival / speakeasy, correct kind
  per venue (swept-beam-2d / pulsed-laser / light-shaft),
  label='Spotlights', payloads schema-valid (count present, plural
  array fields match count, kind-required scalars present).

Check 21 — Admin panel round-trip.
  On one in-scope venue (pick stadium): the seeded spotlight anchor
  appears in the panel with the right kind + fields. Preview
  renders the 4-beam sweep in the bounded canvas. Delete the anchor
  (confirm dialog, empty state, "+ Add" still present per PERMIT).
  Re-create through the panel, set the kind + fields (including the
  per-beam arrays), Save. Preview again.

  NOTE: as with A2's hollywoodbowl round-trip and A3's stadium
  round-trip, the re-created anchor will have a panel-generated id,
  not anc_spot_stadium — restore it to the seed id via a one-row
  UPDATE before closeout so db/037 stays idempotent. Plan the
  restore as part of Check 21, not as a closeout afterthought. (Do
  not repeat A2 + A3's hazard — plan the restore.)

Check 22 — Per-kind preview.
  Preview each of the 3 A4a kinds at least once (swept-beam-2d via
  stadium, pulsed-laser via festival, light-shaft via speakeasy).
  Confirm each renders plausibly and the kind-discriminated form
  shows the right fields. Confirm count:N rendering:
    - stadium preview shows 4 sweeping beams, not 1
    - festival preview shows 6 beat-pulsing lasers, not 1
    - speakeasy preview shows 3 drifting shafts, not 1
  Confirm festival's beat-pulse fires on the expected cadence
  (~469ms per beat at BPM=128) and decays back to base over ~380ms.
  Confirm stadium's beams stagger by ~800ms at startup. Confirm
  speakeasy's shafts drift slowly (4-8s per drift).

Check 23 — RPC authority gate.
  Signed-in non-admin calling rpc_venue_anchor_upsert with a
  spotlight payload → HTTP 403 / code 42501. (db/035's gate;
  re-confirmed for type='spotlight'.) Sign IN as non-admin first —
  a signed-out browser gives 401, which is not the gate under test
  (A2/A3 test-method note).

Check 24 — D8 dormancy + karaoke read-path unchanged.
  karaoke/stage.html spotlight playback for the 3 venues still runs
  via the procedural AMBIENT_PROFILES path; no new console errors
  from the spotlight.js script tag. git diff confirms the only
  karaoke/stage.html change is the one registration <script> tag.
  Visually confirm stadium spotlights, festival lasers, speakeasy
  shafts still render in karaoke as before A4a.

═══════════════════════════════════════════════════════════════════════
§9 — IMPLEMENTATION SEQUENCE
═══════════════════════════════════════════════════════════════════════

Propose-pause-apply throughout. Each numbered item is a review gate.

  1. Foundation/payload pass: for each of the 3 in-scope effects,
     quote the procedural source block (stadium 4593-4666, festival
     4844-4916, speakeasy 4762-4827) and propose the exact db/037
     payload it produces. Show the count:N per-item array unpacking
     against the source's per-item indexed code — i.e. show that
     stadium's `hues: [220,200,240,180]` matches the source's
     `[220,200,240,180][i]` lookup, festival's `angle_init` array
     evaluates the `π*0.35 - i*0.14` formula explicitly for i=0..5,
     etc. THIS IS THE LOAD-BEARING REVIEW — payload-vs-source
     fidelity. Pause for review.

  2. Propose db/037 in full (3 seed rows + verification footer).
     Pause for review.

  3. Propose spotlight.js (renderer module, 3 kinds + count:N
     iteration + GSAP-equivalent motion per §3.5 + ctx.canvas-only
     context handling). The proposal must include:

     (a) Per-tween state shape — the runtime object held by each
         per-item state, recording the active tween's field,
         start_value, target_value, start_time, duration_ms, ease
         identifier, and on_complete reference. Animation-tick
         formula: t = clamp((now - start_time) / duration_ms, 0, 1);
         eased = ease_fn[tween.ease](t); item[tween.field] =
         start_value + (target_value - start_value) * eased; on
         t >= 1, invoke on_complete.

     (b) Ease-function JS implementations — pure functions, no
         library import. The four ease functions A4a needs:
           power1.inOut  // GSAP power1 = quadratic
             t => t < 0.5 ? 2*t*t : 1 - Math.pow(-2*t + 2, 2) / 2
           power2.in     // GSAP power2 = cubic
             t => t * t * t
           power3.out    // GSAP power3 = quartic
             t => 1 - Math.pow(1 - t, 4)
           sine.inOut
             t => -(Math.cos(Math.PI * t) - 1) / 2

     (c) Per-kind timeline reconstruction — side-by-side quoted
         from the procedural source:
           • swept-beam-2d: each beam runs a single active tween at
             a time. On_complete picks a new random target_angle
             within sweep_target_range, a new random target_alpha
             within sweep_alpha_range, a new random duration within
             sweep_duration_range_ms — then starts a new tween.
             Initial stagger via per-beam delayed start of
             stagger_ms × i.
           • pulsed-laser: each laser runs a continuous base-angle
             drift (NOT a tween — direct +=drift_speed per frame,
             with reflect at drift_range) AND a beat-pulse tween
             chain triggered every (60000 / bpm) ms. Chain shape:
             attack (alpha→peak_alpha + width→peak_width_mult×
             base_width over attack_ms via attack_ease) →
             on_complete → decay (alpha→base_alpha +
             width→base_width over decay_ms via decay_ease).
             First pulse at (BEAT × 0.5) per source.
           • light-shaft: each shaft runs a single active tween (x
             AND alpha tweened in parallel by the SAME tween
             record's eased t, reading x_start/x_target and
             alpha_start/alpha_target). On_complete picks a new
             x_target = x + (rand-0.5)*drift_distance_px, new
             alpha_target within drift_alpha_range, new duration
             within drift_duration_range_ms — restart. Initial
             stagger via per-shaft delayed start of rand ×
             drift_stagger_max_ms.

     The reconstruction is the load-bearing part — review must
     confirm each GSAP parameter in the procedural source maps to
     the renderer's tween record correctly. Same propose-pause
     discipline A3 spec §9 step 3 used for the CLR-5/6/7
     renderer-contract items. Pause for review.

  4. Propose the admin-venues.html spotlight panel (per-kind form +
     count:N array field display + JSON textarea validation +
     preview surface + lifecycle including PERMIT "+ Add" behavior +
     the v2.NN bump). Pause for review.

  5. On approval: apply db/037 to prod (Supabase SQL Editor), run
     Q1–Q3. THEN commit the implementation (spotlight.js +
     admin-venues.html + karaoke/stage.html one-line tag + db/037
     file + MIGRATIONS_APPLIED.md row) as one commit. No push until
     the gate.

  6. Push gate. Then verification Checks 19–24, one at a time. Plan
     the Check 21 seed-id restore (§8) so closeout is clean.

  7. A4a verification result log, then file the §7 DEFERRED entries
     (final list determined during the cycle — §7's list is the
     planning-time anticipation, not the binding list).

No Co-Authored-By trailer. db/037 applies to prod BEFORE the
implementation commit lands (A2/A3 ordering).

— END OF A4a BUILD SPEC —
