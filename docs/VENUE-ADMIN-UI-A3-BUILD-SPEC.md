# Venue Admin UI — Stage A3 Build Spec

Status: binding spec for the A3 implementation cycle.
Extends: docs/VENUE-ADMIN-UI-A1-BUILD-SPEC.md §7 (the A1–A8 staging). This
spec is A3's detail and ALSO re-stages §7 — see §0.2.

═══════════════════════════════════════════════════════════════════════
§0 — CONTEXT AND RE-STAGING
═══════════════════════════════════════════════════════════════════════

§0.1 — What A3 is
A3 is the third Block A vertical slice: a particle anchor renderer + a
particle authoring panel in admin-venues.html + a seed migration (db/036)
translating the procedural 2D particle effects of 4 karaoke venues into
data-driven venue_anchors rows of type='particle'.

It follows the pattern A2 set: a self-registering renderer module in
shell/venue-renderers/, an authoring panel added to admin-venues.html, a
seed migration, and a one-line registration <script> tag in
karaoke/stage.html. Per D8, everything ships DORMANT — the seeded anchors
are data only, karaoke's read path is unchanged, the procedural
AMBIENT_PROFILES particle code stays load-bearing until Stage 6.

§0.2 — Re-staging of spec §7: A3 is 2D-CANVAS ONLY
The A3 foundation pass established that 2 of the 4 affected venues
(stadium, speakeasy) emit particles in BOTH a 2D canvas AND a Three.js
scene concurrently. The 3D particle code lives inside buildStadiumEffects3D
and buildSpeakeasyEffects3D — the same Three.js builder functions that
Stage A5 (spotlight + 3D builders) must already translate.

DECISION: A3 covers 2D-canvas particles ONLY. The 3D particle paths
(stadium's 2000 THREE.Points, speakeasy's 60 sphere meshes) defer to a
later stage paired with A5's Three.js work, so the 3D rendering context is
solved once by whoever is already in the Three.js builders. This re-stages
§7: A3 is the 2D particle slice; 3D particles are added to A5's scope (or a
dedicated A5-adjacent sub-stage — A5's spec decides).

§0.3 — A3's scope: exactly 4 anchors across 4 venues
  • stadium    — 2D phone-lights        → kind: point-cloud
  • disco      — mirror-ball dots       → kind: point-cloud (polar-projected)
  • speakeasy  — 2D smoke-wisps         → kind: volumetric
  • festival   — confetti               → kind: directional-emitter
honkytonk has NO particle anchor — its procedural particles were deleted
(karaoke/stage.html:4832 comment); only a screen-tint flicker remains.

OUT OF A3 SCOPE, stated explicitly so an implementer does not translate
them:
  • All spotlight-class effects — stadium's sweeping beams, festival's
    lasers, speakeasy's amber light shafts, the 3D cone meshes, the 3D
    candle Points. These are type='spotlight', Stage A5.
  • The count:1 "hack-particle" venue overlays — disco's floor-flash
    gradient and space's 12-panel overlay. These live INSIDE the same
    count:1 closures as real particles but are venue-level rectangle/
    gradient overlays, NOT particles. disco's ONLY A3 deliverable is the
    mirror-ball dots. The floor-flash is a future callout/overlay type,
    not A3.
  • The 4 ghost venues (space, forest, underwater, dead-dragonlair). Their
    procedural particle code exists but the venues are not in the
    26-venue inventory; they are Stage 6 cleanup. See §6.

═══════════════════════════════════════════════════════════════════════
§1 — THE PARTICLE PAYLOAD CONTRACT
═══════════════════════════════════════════════════════════════════════

§1.1 — Discriminated union, keyed by payload.kind
Particle anchors are venue_anchors rows with type='particle'. The type
column is unchanged from db/032's vocabulary — 'particle' is already a
permitted value. ALL sub-discrimination lives inside the payload jsonb,
exactly as A2's audio payload used payload.type='mp3'. NO schema change.

payload.kind is the discriminator. A3 ships THREE kinds:
  • point-cloud        — a fixed set of particles, eternal, per-particle
                         twinkle, no spatial traversal. Sub-discriminated
                         by position_layout (see §1.3).
  • directional-emitter — particles spawn at a canvas edge, traverse along
                         a velocity vector, and die (off-canvas or by
                         fade). Optionally respawn.
  • volumetric         — particles spawn distributed in a region, drift
                         slowly, optionally expand, fade by alpha.
                         Optionally respawn.

The kind boundary is defined by SPAWN GEOMETRY + LIFETIME MODEL, not by
field presence:
  - point-cloud      = fixed positions + eternal + twinkle
  - directional-emitter = edge spawn + vector traverse + die
  - volumetric       = region spawn + drift + fade
Fields like respawn, turbulence, fade are SHARED fragments (§1.2), not
boundary markers. A directional-emitter with respawn:true is still a
directional-emitter.

§1.2 — Shared field fragments
These fragments recur across kinds. Declare them ONCE in the renderer's
schema and have each kind reference them — do not re-declare per kind.

  fragment "color":
    one of:
      { "mode": "fixed",     "value": "rgba(255,255,255,0.7)" }
      { "mode": "hue_range", "range": [0,360], "sat": 100, "lit": 65 }
  fragment "render":
    { "shape": "circle" | "rect", "mode": "solid" | "stroke" | "gradient",
      "line_width": <number, only when mode=stroke> }
  fragment "turbulence":
    { "strength": <number> }   // per-frame velocity random-walk magnitude;
                               // absent = no turbulence
  fragment "modulator" (optional, see §1.4):
    { "name": <string>, "target": <particle property name> }

Single shared scalar fields usable by any kind: count (int),
size or size_range, fade_rate (number; absent = no fade), respawn (bool;
default false).

§1.3 — point-cloud schema
{
  "kind": "point-cloud",
  "context": "2d-canvas",
  "position_layout": "cartesian" | "polar-projected",
  // cartesian (stadium):
  "x_range": [0,1], "y_range": [0.08,0.60],   // normalized to canvas
  // polar-projected (disco) — used INSTEAD of x_range/y_range:
  "polar": {
    "center": [0.5, 0.30],          // normalized canvas center
    "dist_range": [<min>,<max>],    // normalized radial distance
    "vertical_squash": 0.4,         // ellipse projection factor
    "rotation_velocity": 0.012      // radians/frame on the shared accumulator
  },
  "count": 400,
  "size": 1.4,                                  // or "size_range":[a,b]
  "twinkle_phase_speed_range": [0.008, 0.033],
  "color": <color fragment>,
  "render": <render fragment>,                  // typically circle/solid
  "modulator": <modulator fragment, optional>
}
position_layout is the ONLY internal branch in A3's schema. cartesian uses
x_range/y_range; polar-projected uses the polar object instead. The
renderer dispatches on position_layout within the point-cloud arm.

§1.4 — directional-emitter schema
{
  "kind": "directional-emitter",
  "context": "2d-canvas",
  "spawn_edge": "top" | "bottom" | "left" | "right",
  "count": 80,
  "velocity_range": { "vx": [-1,1], "vy": [0.4,1.6] },
  "size_range": [2,7],
  "rotation": { "init_range":[0,6.28], "velocity_range":[-0.06,0.06] },
                                                // optional; confetti uses it
  "turbulence": <turbulence fragment, optional>,
  "fade_rate": <number, optional>,              // absent=die off-canvas only
  "respawn": false,                             // bool, default false
  "color": <color fragment>,
  "render": <render fragment>
}
festival confetti is the canonical case: spawn_edge:"top", rotation
present, no turbulence, no fade_rate, respawn:false.

§1.5 — volumetric schema
{
  "kind": "volumetric",
  "context": "2d-canvas",
  "spawn_region": { "x":[0,1], "y":[0.6,1.0] },  // normalized
  "count": 35,
  "velocity_range": { "vx":[-0.2,0.2], "vy":[-0.45,-0.1] },
  "size_init_range": [20,65],
  "size_growth_rate": 0.2,                       // optional; absent=no growth
  "fade_rate": 0.00015,
  "turbulence": <turbulence fragment, optional>,
  "respawn": false,                              // bool, default false
  "color": <color fragment>,
  "render": <render fragment>                    // speakeasy: circle/gradient
}
speakeasy 2D smoke is the canonical case: region spawn, mild upward
velocity, size_growth_rate present, fade_rate present, turbulence present,
respawn:false, render gradient.

§1.6 — The modulator field (Q5 resolution)
Some procedural effects read a venue-level GSAP-driven scalar
(stadium's crowdState.brightness, disco's beatState.scale). A3 does NOT
build the modulator SYSTEM — that is a cross-cutting concern (it drives
spotlights too) and belongs to a later integration stage. A3 only records
the BINDING:
  "modulator": { "name": "crowd_brightness", "target": "alpha" }
  "modulator": { "name": "beat_scale",       "target": "size"  }
name is an opaque string (the renderer does not resolve it to a real
driver in A3). target names the particle property the scalar modulates —
required, because stadium modulates alpha and disco modulates size.
For A3's dormant preview, the renderer drives the named modulator with a
simple built-in oscillator so the preview looks alive. Real modulator
wiring is deferred. See §7 (DEFERRED) — "venue modulator system."

§1.7 — Known uncovered pattern: P1 (drift + wrap + twinkle)
The foundation pass found that 2 ghost venues (space starfield, forest
fireflies) exhibit a pattern the 3-kind set does NOT cover: a cloud of
particles that is eternal-twinkling (like point-cloud) BUT has linear
spatial drift with edge-WRAP (not die-and-respawn). The distinguishing
feature is wrap-around vs traverse-and-die.

This is recorded as a DELIBERATE deferral, not an omission. None of A3's 4
in-scope effects exhibit P1. When a P1-shaped venue is built, or a ghost
resurrected, the resolution is a 4th kind — provisional name
"drifting-cloud" — added additively (payload.kind is the discriminator, so
a 4th kind does not disturb the existing 3). A DEFERRED.md entry records
this; see §7.

═══════════════════════════════════════════════════════════════════════
§2 — db/036 — THE PARTICLE ANCHOR SEED MIGRATION
═══════════════════════════════════════════════════════════════════════

§2.1 — No new RPCs
db/035's rpc_venue_anchor_upsert and rpc_venue_anchor_delete are
type-agnostic — db/035 declares v_known_types including 'particle' and
validates against the full vocabulary. A3 needs NO new RPCs. db/036 is a
SEED-ONLY migration.

§2.2 — Migration content
db/036_particle_anchor_seed.sql — one transactional file:
  - 4 INSERT rows into public.venue_anchors, type='particle', one per
    in-scope venue, with deterministic ids anc_par_<venue_id>:
      anc_par_stadium, anc_par_disco, anc_par_speakeasy, anc_par_festival
  - Each row's payload is the kind-appropriate schema from §1, transcribed
    from the procedural code at the cited line numbers. label = 'Particles'
    for all 4 (parallel to A2's seed using label='Ambient').
  - ON CONFLICT (id) DO NOTHING for idempotency (db/035 seed pattern).
  - The payload values are NOT invented — they are read off the procedural
    code. The implementation cycle must quote each procedural source block
    and show the payload it produces, for review, BEFORE the migration is
    finalized. Payload-vs-source fidelity is the load-bearing review step.

§2.3 — Verification footer
db/036 carries a verification-query footer (db/034/035 pattern):
  - Q1: count(*) where type='particle' = 4
  - Q2: the 4 rows, ordered by venue_id; id matches anc_par_<venue_id>;
    payload->>'kind' is the expected kind per venue; label='Particles'
  - Q3: each payload validates against its kind schema (spot-check
    payload->>'kind' and the presence of kind-required fields)
No anon/grant checks needed — db/036 creates no functions. (db/035's RPCs
already carry their grant surface.)

§2.4 — Migrations tracker
db/036 is recorded in db/MIGRATIONS_APPLIED.md AFTER prod apply, per
doctrine. Note: MIGRATIONS_APPLIED.md is ordered by apply-date, not
migration number — record db/036's actual row position, do not assume.

═══════════════════════════════════════════════════════════════════════
§3 — shell/venue-renderers/particle.js — THE RENDERER MODULE
═══════════════════════════════════════════════════════════════════════

§3.1 — Self-contained (Q1 resolution)
particle.js is SELF-CONTAINED. It re-implements its own particle array,
its own RAF loop, and renders into a canvas reference passed to it. It does
NOT import, wrap, or call karaoke/stage.html's spawnParticles /
runParticleLoop — those mutate karaoke's shared global particles[] array,
and calling them would inject preview particles into karaoke's live loop.
Karaoke stays byte-for-byte untouched (D8). This parallels A2's audio.js
being self-contained rather than extracting playAmbientMp3.

§3.2 — Registration
particle.js registers on the anchor registry at module load:
  registerAnchorRenderer('particle', particleAnchorRenderer)
exposed via window.elsewhere.anchorRegistry per shell/venue-registry.js.
Same mechanism as audio.js.

§3.3 — Renderer contract
The renderer is given a particle anchor (the venue_anchors row) and a
2D-canvas render target. It:
  - parses payload.kind, dispatches to the kind's update/draw logic
  - on point-cloud: dispatches further on position_layout
  - owns a private particle array + RAF loop for that effect
  - applies shared fragments (color, render, turbulence, fade, respawn)
    uniformly across kinds
  - drives any modulator with a built-in oscillator (preview only, §1.6)
  - exposes a teardown: particle-array purge + RAF cancel + canvas clear
A2's audio renderer returned a { stop } handle; particle's renderer
returns an equivalent teardown handle. Define the exact handle shape in
the implementation proposal.

§3.4 — Directory
particle.js goes in the existing shell/venue-renderers/ directory
alongside audio.js. A3 does NOT split into particle-2d.js/particle-3d.js —
A3 is 2D-only (§0.2); a 3D module is a later-stage concern.

═══════════════════════════════════════════════════════════════════════
§4 — admin-venues.html — THE PARTICLE AUTHORING PANEL
═══════════════════════════════════════════════════════════════════════

§4.1 — Panel placement
A particle anchor panel is added to admin-venues.html, sibling to A2's
audio anchor panel, below the venue_defaults editor. It shows the
particle anchors for the selected venue (0 or, for the 4 in-scope venues
post-seed, 1).

§4.2 — Per-kind form
Unlike audio (one flat form), the particle panel's edit form is
KIND-DISCRIMINATED: selecting/displaying a kind shows that kind's fields
(§1.3–1.5). The shared fragments render as shared sub-forms. The
implementation proposal must show the form structure for all 3 kinds for
review.

§4.3 — Preview surface (Q6 resolution)
The panel includes a bounded 2D-canvas preview area. Clicking Preview
renders the particle effect live into that canvas using particle.js;
editing payload fields re-renders. The preview canvas is owned by the
admin page — it is NOT karaoke's #ambient-layer. 2D only; no Three.js in
admin-venues.html for A3. The preview must be bounded (particles must not
overflow into other admin UI areas) and must have a Stop control.

§4.4 — Lifecycle
Create / save / delete / preview, mirroring A2's audio panel lifecycle and
reusing its dirty-tracking + the rpc_venue_anchor_upsert/_delete calls.
Multi-anchor policy: A3 follows A2's PREVENT rule — a venue may have at
most one particle anchor in A3; "+ Add" hides when one exists. (If a venue
ever needs layered particle effects, that revisits the UI guardrail, not
the schema — same reasoning as A2.)

§4.5 — Version label
admin-venues.html still lacks the v2.NN version badge (DEFERRED.md entry,
filed in the doc catch-up pass). A3 touches admin-venues.html — fold the
badge in here. Match the tv2.html convention; the implementation proposal
proposes the exact placement + numbering.

§4.6 — karaoke/stage.html
One-line addition: a <script type="module"> tag loading particle.js,
alongside audio.js's tag. Registration only — permitted per D8 / the
A2 precedent (spec §8.2 Check 12). No other karaoke change.

═══════════════════════════════════════════════════════════════════════
§5 — D8 / DORMANCY
═══════════════════════════════════════════════════════════════════════

A3 ships dormant, exactly as A2 did:
  - The 4 seeded particle anchors are data; karaoke's read path does not
    consult them.
  - The procedural spawnParticles calls inside AMBIENT_PROFILES.<venue>
    .anim() remain load-bearing.
  - addVenueEffects3D stays untouched.
  - particle.js is registered but has no live consumer in karaoke; its
    only consumer is the admin panel's preview.
Stage 6 (AMBIENT_PROFILES retirement) promotes the registry path to
canonical. A3 makes NO karaoke read-path change.

═══════════════════════════════════════════════════════════════════════
§6 — GHOST-CODE BOUNDARY
═══════════════════════════════════════════════════════════════════════

The 4 ghost venues (space, forest, underwater, dead-dragonlair) have
procedural 2D particle code but are NOT in the 26-venue inventory. A3 does
NOT translate them — Stage 6 cleanup territory. They are relevant to A3
only as cross-check data (the foundation pass used them to pressure-test
the kind set). Two of them (space, forest) exhibit pattern P1 (§1.7).
A3 leaves all ghost code untouched.

═══════════════════════════════════════════════════════════════════════
§7 — DEFERRED ITEMS A3 GENERATES
═══════════════════════════════════════════════════════════════════════

Two items for DEFERRED.md, to be filed during A3's closeout (not now):
  1. P1 / "drifting-cloud" 4th particle kind — the drift+wrap+twinkle
     pattern (§1.7). Low priority; additive when a P1 venue is built.
  2. Venue modulator system — the real wiring of GSAP-driven scalars
     (crowd_brightness, beat_scale) that particles AND spotlights read
     (§1.6). Cross-cutting; belongs to a later integration stage. A3 only
     records the binding, not the driver.
The 3D-particle stage re-staging (§0.2) is a §7-staging change, recorded
in this spec; whether it needs a separate DEFERRED entry or just rides
A5's spec is A5's call.

═══════════════════════════════════════════════════════════════════════
§8 — VERIFICATION CHECKLIST
═══════════════════════════════════════════════════════════════════════

Run after db/036 + particle.js + the admin panel ship. Mirrors the A2 §8.2
structure.

Check 13 — Particle renderer registered.
  Load karaoke/stage.html. Console:
  window.elsewhere.anchorRegistry.getAnchorRenderer('particle')
  returns the renderer function (not null).

Check 14 — Seed verification.
  db/036's footer queries Q1–Q3: 4 particle anchors, ids anc_par_<venue>,
  correct kind per venue, label='Particles', payloads schema-valid.

Check 15 — Admin panel round-trip.
  On one in-scope venue (pick stadium): the seeded particle anchor appears
  in the panel with the right kind + fields. Preview renders the effect in
  the bounded canvas. Delete the anchor (confirm dialog, empty state,
  "+ Add" reappears). Re-create through the panel, set the kind + fields,
  Save. Preview again. NOTE: as with A2's hollywoodbowl round-trip, the
  re-created anchor will have a panel-generated id, not anc_par_stadium —
  restore it to the seed id via a one-row UPDATE before closeout so db/036
  stays idempotent. (Do not repeat A2's hazard — plan the restore.)

Check 16 — Per-kind preview.
  Preview each of the 3 kinds at least once (point-cloud via stadium or
  disco, directional-emitter via festival, volumetric via speakeasy).
  Confirm each renders plausibly and the kind-discriminated form shows the
  right fields. Confirm disco's polar-projected layout renders as an
  ellipse, not a cartesian scatter.

Check 17 — RPC authority gate.
  Signed-in non-admin calling rpc_venue_anchor_upsert with a particle
  payload → HTTP 403 / code 42501. (db/035's gate; re-confirmed for
  type='particle'.) Sign IN as non-admin first — a signed-out browser
  gives 401, which is not the gate under test (A2 test-method note).

Check 18 — D8 dormancy + karaoke read-path unchanged.
  karaoke/stage.html particle playback for the 4 venues still runs via the
  procedural AMBIENT_PROFILES path; no new console errors from the
  particle.js script tag. git diff confirms the only karaoke/stage.html
  change is the one registration <script> tag.

═══════════════════════════════════════════════════════════════════════
§9 — IMPLEMENTATION SEQUENCE
═══════════════════════════════════════════════════════════════════════

Propose-pause-apply throughout. Each numbered item is a review gate.
  1. Foundation/payload pass: for each of the 4 in-scope effects, quote
     the procedural source block and propose the exact db/036 payload it
     produces. THIS IS THE LOAD-BEARING REVIEW — payload-vs-source
     fidelity. Pause for review.
  2. Propose db/036 in full (the 4 seed rows + verification footer).
     Pause for review.
  3. Propose particle.js (the renderer, all 3 kinds + shared fragments +
     the position_layout branch + the preview oscillator). Pause.
  4. Propose the admin-venues.html particle panel (per-kind form + preview
     surface + lifecycle + the v2.NN badge). Pause.
  5. On approval: apply db/036 to prod (Supabase SQL Editor), run Q1–Q3.
     THEN commit the implementation (particle.js + admin-venues.html +
     karaoke/stage.html one-line tag + db/036 file + MIGRATIONS_APPLIED.md
     row) as one commit. No push until the gate.
  6. Push gate. Then verification Checks 13–18, one at a time. Plan the
     Check 15 seed-id restore (§8) so closeout is clean.
  7. A3 verification result log, then file the two §7 DEFERRED entries.

No Co-Authored-By trailer. db/036 applies to prod BEFORE the
implementation commit lands (the A2 ordering).

— END OF A3 BUILD SPEC —
