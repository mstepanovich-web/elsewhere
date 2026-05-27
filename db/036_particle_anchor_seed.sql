-- ============================================================================
-- Elsewhere — Venue Admin UI Stage A3: particle anchor seed
-- Migration: 036
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Third migration in the Venue Admin UI workstream (Stage A3 per
-- docs/VENUE-ADMIN-UI-A3-BUILD-SPEC.md §7's hybrid sequencing).
--
-- SEED-ONLY migration. No RPCs created. Per spec §2.1, db/035's
-- rpc_venue_anchor_upsert and rpc_venue_anchor_delete are type-agnostic
-- — db/035 declares v_known_types including 'particle' and validates
-- against the full vocabulary. The admin UI's particle authoring path
-- uses those existing RPCs unchanged.
--
-- One section, one transactional file:
--
--   1. Particle anchor seed (4 rows) — one per in-scope venue per spec
--      §0.3's locked enumeration: stadium, disco, speakeasy, festival.
--      INSERT ... ON CONFLICT (id) DO NOTHING for idempotency
--      (db/035 seed pattern). Deterministic ids: anc_par_<venue_id>.
--
-- Payload fidelity. Each row's payload jsonb is the §1 kind-discriminated
-- schema, transcribed from the procedural source at the cited line
-- numbers in karaoke/stage.html. The transcription was approved at
-- A3 §9 step 2 (the per-effect fidelity-check pass) and incorporates
-- the §1 amendment (commit 716746b): alpha pulled from color strings,
-- modulator allowed in array form (disco binds two), twinkle_phase_speed_range
-- optional on point-cloud (disco omits), polar.dist_range normalized
-- against max(canvas.width, canvas.height).
--
-- D8 dormancy. The 4 seeded particle anchors are DATA. Karaoke's read
-- path is unchanged — AMBIENT_PROFILES + addVenueEffects3D in
-- karaoke/stage.html stay load-bearing until Stage 6. shell/venue-renderers/
-- particle.js (Stage A3 §3) is registered but has no live consumer in
-- karaoke; its only consumer is admin-venues.html's preview surface.
--
-- Position consistency. All 4 anchors are 2D-canvas screen-space overlays
-- (not sphere-pinned), so yaw_deg and pitch_deg are both NULL — satisfies
-- db/032's venue_anchors_position_consistency CHECK constraint, which is
-- the type-agnostic paired-NULL rule
-- check ((yaw_deg is null) = (pitch_deg is null))
-- — both NULL passes for any type, exactly as db/035's audio seed.
--
-- Companion docs:
--   • docs/VENUE-ADMIN-UI-A3-BUILD-SPEC.md §1 (amended at 716746b) —
--     payload schema; §2 — this migration's scope; §0.3 — the 4 in-scope
--     venues; §6 — ghost-code boundary (4 ghost venues with procedural
--     particle code NOT translated by A3).
--   • db/032_venue_abstraction_schema.sql:231-301 — venue_anchors table
--     definition (FK to venue_defaults ON DELETE RESTRICT, CHECK on type
--     vocabulary including 'particle', paired-NULL position constraint).
--   • db/035_audio_anchor_rpcs_and_seed.sql:260-317 — audio seed pattern
--     this migration mirrors.
-- ============================================================================


begin;


-- ─── 1. Particle anchor seed (4 rows) ────────────────────────────────────
-- One row per in-scope venue per spec §0.3's locked enumeration.
-- honkytonk has NO particle anchor — its procedural particles were
-- deleted (karaoke/stage.html:4832 comment: "Neon sign flicker only —
-- removed amber dust particles"). Only a screen-tint flicker remains;
-- that's not a particle effect and is out of A3 scope.
--
-- Ghost venues (space, forest, underwater, dead-dragonlair) have
-- procedural 2D particle code but are NOT in the 26-venue inventory.
-- A3 leaves them untouched per spec §6 (Stage 6 cleanup territory).

insert into public.venue_anchors (
  id, venue_id, type, label, payload
) values

  -- stadium — 2D phone-lights (karaoke/stage.html:4627-4640)
  -- 400 white twinkling dots in the upper crowd region. Twinkle via
  -- per-particle sin(phase) on alpha. Modulated by crowd_brightness
  -- (the GSAP-driven cheer-swell scalar). Source's clamp(o * 0.7) is
  -- equivalent to the §1.2 alpha model's clamp(alpha * twinkle *
  -- modulator) by commutativity.
  ('anc_par_stadium', 'stadium', 'particle', 'Particles',
   '{
     "kind": "point-cloud",
     "context": "2d-canvas",
     "position_layout": "cartesian",
     "x_range": [0, 1],
     "y_range": [0.08, 0.60],
     "count": 400,
     "size": 1.4,
     "twinkle_phase_speed_range": [0.008, 0.033],
     "alpha": 0.7,
     "color": {"mode": "fixed", "value": "rgb(255,255,255)"},
     "render": {"shape": "circle", "mode": "solid"},
     "modulator": {"name": "crowd_brightness", "target": "alpha"}
   }'::jsonb),

  -- disco — mirror-ball dots (karaoke/stage.html:4670-4694, 4708-4732)
  -- 120 colored dots in a polar layout with vertical squash (ellipse
  -- projection), rotating around the canvas center at 0.012 rad/frame.
  -- No internal twinkle (twinkle_phase_speed_range omitted per amended
  -- §1.3). Two modulators: beat_scale modulates per-particle size,
  -- beat_brightness modulates alpha. The 0.6 alpha baseline matches
  -- the source's c.globalAlpha = 0.6 * beatState.brightness.
  -- The floor-flash gradient drawn from the same count:1 closure is
  -- OUT OF A3 SCOPE per spec §0.3 — it's a venue overlay, not a
  -- particle effect, and will be a future callout/overlay anchor type.
  ('anc_par_disco', 'disco', 'particle', 'Particles',
   '{
     "kind": "point-cloud",
     "context": "2d-canvas",
     "position_layout": "polar-projected",
     "polar": {
       "center": [0.5, 0.30],
       "dist_range": [0, 0.65],
       "vertical_squash": 0.4,
       "rotation_velocity": 0.012
     },
     "count": 120,
     "size_range": [1, 5],
     "alpha": 0.6,
     "color": {"mode": "hue_range", "range": [0, 360], "sat": 100, "lit": 70},
     "render": {"shape": "circle", "mode": "solid"},
     "modulator": [
       {"name": "beat_scale",      "target": "size"},
       {"name": "beat_brightness", "target": "alpha"}
     ]
   }'::jsonb),

  -- speakeasy — 2D smoke-wisps (karaoke/stage.html:4784-4804)
  -- 35 atmospheric smoke clouds spawning in the bottom 40% of canvas,
  -- drifting mildly upward, expanding (+0.2px/frame), fading (-0.00015
  -- per frame). Per-particle spawn alpha drawn from [0.015, 0.065];
  -- turbulence applies a small per-frame random walk on vx. Render
  -- via radial gradient (soft disc). respawn:false — one-shot 35-particle
  -- burst that dies out completely. The amber light shafts drawn
  -- separately from a count:1 closure are OUT OF A3 SCOPE (spotlights,
  -- Stage A5). The 3D sphere-mesh smoke variant (60 meshes via
  -- buildSpeakeasyEffects3D) is OUT OF A3 SCOPE per §0.2 (re-staged
  -- to a later stage paired with A5's Three.js work).
  ('anc_par_speakeasy', 'speakeasy', 'particle', 'Particles',
   '{
     "kind": "volumetric",
     "context": "2d-canvas",
     "spawn_region": {"x": [0, 1], "y": [0.6, 1.0]},
     "count": 35,
     "velocity_range": {"vx": [-0.2, 0.2], "vy": [-0.45, -0.10]},
     "size_init_range": [20, 65],
     "size_growth_rate": 0.2,
     "fade_rate": 0.00015,
     "alpha_init_range": [0.015, 0.065],
     "turbulence": {"strength": 0.02},
     "respawn": false,
     "color": {"mode": "fixed", "value": "rgb(210,190,160)"},
     "render": {"shape": "circle", "mode": "gradient"}
   }'::jsonb),

  -- festival — confetti (karaoke/stage.html:4904-4913)
  -- 80 colored rotating-rectangle confetti falling from the top edge.
  -- Per-particle hue drawn from [0,360], rotation init in [0, 2π],
  -- angular velocity in [-0.06, 0.06]. Falls off the bottom and dies
  -- (alive: y < canvas+20). respawn:false — source comment says
  -- "Continuous confetti" but the code is NOT continuous; byte-faithful
  -- encoding preserves the one-shot 80-particle burst behavior. Default
  -- alpha=1.0 (no globalAlpha set in source; fillStyle = hsl() carries
  -- no alpha). No modulator. The beat-synced lasers + strobe drawn
  -- from a separate count:1 closure are OUT OF A3 SCOPE (spotlights).
  ('anc_par_festival', 'festival', 'particle', 'Particles',
   '{
     "kind": "directional-emitter",
     "context": "2d-canvas",
     "spawn_edge": "top",
     "count": 80,
     "velocity_range": {"vx": [-1, 1], "vy": [0.4, 1.6]},
     "size_range": [2, 7],
     "rotation": {"init_range": [0, 6.28], "velocity_range": [-0.06, 0.06]},
     "respawn": false,
     "color": {"mode": "hue_range", "range": [0, 360], "sat": 100, "lit": 65},
     "render": {"shape": "rect", "mode": "solid"}
   }'::jsonb)

on conflict (id) do nothing;


commit;


-- ============================================================================
-- Verification queries (run AFTER COMMIT in Supabase SQL Editor)
-- ============================================================================
--
-- Three queries per spec §2.3. Expect ALL THREE to confirm. No anon/grant
-- queries needed — db/036 creates no functions.

-- ─── Q1. Seed landed: total count ─────────────────────────────────────────
select count(*) as particle_count
  from public.venue_anchors
 where type = 'particle';
-- Expect: particle_count = 4.

-- ─── Q2. Per-venue id / kind / label correctness ──────────────────────────
select id,
       venue_id,
       payload->>'kind' as kind,
       label
  from public.venue_anchors
 where type = 'particle'
 order by venue_id;
-- Expect 4 rows:
--   anc_par_disco       | disco       | point-cloud          | Particles
--   anc_par_festival    | festival    | directional-emitter  | Particles
--   anc_par_speakeasy   | speakeasy   | volumetric           | Particles
--   anc_par_stadium     | stadium     | point-cloud          | Particles

-- ─── Q3. Payload schema spot-check (kind-required fields present) ─────────
select id,
       payload->>'kind' as kind,
       payload->'count' as count,
       coalesce(
         payload->>'position_layout',
         payload->>'spawn_edge',
         case when payload ? 'spawn_region' then 'spawn_region present' end
       ) as kind_specific_marker
  from public.venue_anchors
 where type = 'particle'
 order by venue_id;
-- Expect 4 rows:
--   anc_par_disco       | point-cloud         | 120 | polar-projected
--   anc_par_festival    | directional-emitter | 80  | top
--   anc_par_speakeasy   | volumetric          | 35  | spawn_region present
--   anc_par_stadium     | point-cloud         | 400 | cartesian
-- Any row showing NULL in kind_specific_marker = payload missing the
-- kind-discriminating field; that's a transcription failure to fix.
-- ============================================================================
