-- ============================================================================
-- Elsewhere — Venue Admin UI Stage A4b: 3D anchor seed (Three.js context)
-- Migration: 038
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Fifth migration in the Venue Admin UI workstream (Stage A4b per
-- docs/VENUE-ADMIN-UI-A4B-BUILD-SPEC.md §8). A4b is the 3D extension
-- sub-stage of A4 (A4 sub-staged into A4a + A4b in planning chat
-- 2026-05-27; A4a — 2D-canvas spotlight — shipped at f167ec6 + fixes
-- 0b2dec0 + 2056a72, closeout 21991e8). A4b ships:
--   • 2 new spotlight kinds (swept-beam-3d, point-light) for the
--     stadium 4 cone meshes + speakeasy 40 candle Points,
--   • 2 absorbed 3D particle paths (point-cloud-3d, volumetric-3d)
--     for the stadium 2000 phone-lights + speakeasy 60 sphere-mesh
--     smoke, deferred from A3 §0.2 re-staging,
--   • new Three.js admin preview surface in admin-venues.html,
--   • panel standardization pass (canonical .anchor-row-actions +
--     per-row Stop across all 3 panels).
--
-- SEED-ONLY migration. No RPCs created. Per spec §8.1, db/035's
-- rpc_venue_anchor_upsert and rpc_venue_anchor_delete are type-
-- agnostic (db/035:93-94 declares v_known_types including 'spotlight'
-- + 'particle' and validates against the full vocabulary). The admin
-- UI's 3D authoring path uses those existing RPCs unchanged. The
-- kind discriminator (swept-beam-3d, point-light, point-cloud-3d,
-- volumetric-3d) lives inside the payload jsonb and is renderer-side
-- only — db/035 does NOT validate kind, only type. Verified pre-apply
-- against db/035 by grep (no v_known_kinds / kind-allowlist exists).
--
-- One section, one transactional file:
--
--   1. 3D anchor seed (4 rows) — 2 spotlight + 2 particle, all with
--      payload.context = "3d-three". Deterministic ids per spec
--      §1.4 (D-naming): anc_spot_stadium_beams3d,
--      anc_spot_speakeasy_candles, anc_par_stadium_phonelights3d,
--      anc_par_speakeasy_smoke3d. INSERT ... ON CONFLICT (id) DO
--      NOTHING for idempotency (db/035/036/037 seed pattern).
--
-- Effect-descriptive labels (revised pre-apply 2026-05-28). Speakeasy
-- now has 2 spotlight anchors after A4b ships (light-shaft from A4a
-- 'Spotlights' + point-light from A4b 'Candles (3D)'). Generic
-- 'Spotlights (3D)' / 'Particles (3D)' would not distinguish effects
-- within a venue in the multi-anchor list (spec §6) or in the
-- kind-aware confirm dialog (spec §6.4). Effect-descriptive labels
-- make each row self-identifying:
--     anc_spot_stadium_beams3d        → 'Cone beams (3D)'
--     anc_spot_speakeasy_candles      → 'Candles (3D)'
--     anc_par_stadium_phonelights3d   → 'Phone lights (3D)'
--     anc_par_speakeasy_smoke3d       → 'Smoke (3D)'
--
-- Payload fidelity. Each row's payload jsonb is the spec §2.4-2.7
-- schema verbatim, derived from the §2 fidelity tables which were
-- in turn derived byte-for-byte from karaoke/stage.html source.
-- Six-decimal precision on irrational values (π → 3.141593,
-- π/2 → 1.570796, 2π → 6.283185) per spec §2.1. theta_init for
-- swept-beam-3d verified pre-apply against source lines 2886-2890:
-- [0.0, Math.PI, Math.PI/2, -Math.PI/2] → [0.000000, 3.141593,
-- 1.570796, -1.570796]. The negative sign on index 3 is load-bearing
-- — pairs [2]+[3] counter-rotate against pairs [0]+[1] per the
-- speeds array [0.003, -0.004, 0.005, -0.003].
--
-- D-twinkle synthesis note (point-cloud-3d only). The source uses
-- GLOBAL-SYNC twinkle (karaoke/stage.html:2920-2923 — every 3 frames,
-- one shared lightMat.opacity = 0.5 + sin(frame*0.04)*0.3). The
-- `phases` Float32Array at lines 2865-2868 is allocated with random
-- per-particle phases but NEVER READ by update() — dead code that
-- proves per-particle twinkle was intended but not implemented.
-- A4b's renderer (spec §3.7) builds the correct version: custom
-- THREE.ShaderMaterial with per-vertex `phase` attribute, fragment
-- shader computes per-particle alpha as
--   uBaseOpacity * (uAlphaCenter + sin(vPhase + uTime) * uAlphaSwing)
--                * uModulator
-- Payload encodes twinkle.mode = "per-particle-shader" + the four
-- shader-uniform values (phase_init, phase_omega_per_frame,
-- alpha_center, alpha_swing). The phase_omega_per_frame = 0.04
-- matches source's `Math.sin(frame * 0.04)` coefficient byte-for-
-- byte; the divergence is per-particle vs global-sync, not motion
-- math. The dead `phases` allocation is the evidence trail.
--
-- D-modulator synthesis note (point-cloud-3d only). The source
-- binds NO external scalar — uses pure frame counter. A4b adds the
-- `crowd_brightness` modulator binding for A3 parity (A3's
-- `anc_par_stadium` 2D phone-lights binds the same modulator at
-- `crowd_brightness → alpha`). When A7's modulator driver registry
-- ships, the value multiplies the per-particle shader twinkle. When
-- absent (current state, until A7), the multiplier defaults to 1.0
-- and per-particle shader twinkle is the sole motion. Documented
-- as SYNTHESIZED, not extracted — the binding is the conceptually
-- correct one for the 3D anchor (mirrors A3's 2D phone-lights
-- binding) but the source provides no scalar to extract.
--
-- Speakeasy smoke spawn-region asymmetry (volumetric-3d). The source
-- uses DIFFERENT phi_norm_ranges for initial spawn (line 2961:
-- `(0.4 + rand*0.5) * π` → [0.4, 0.9]) vs respawn (line 3018:
-- `(0.55 + rand*0.35) * π` → [0.55, 0.90]). Respawn is narrower —
-- avoids the lower edge where freshly-spawned particles would collide
-- with already-rising ones. A4b preserves this byte-faithfully via
-- two payload sub-objects: spawn_region_initial + spawn_region_respawn.
-- Per spec §2.7 Phi-range divergence note: NOT a bug, NOT a
-- normalization — source-faithful.
--
-- D8 dormancy. The 4 seeded 3D anchors are DATA. Karaoke's read path
-- is unchanged — buildStadiumEffects3D + buildSpeakeasyEffects3D at
-- karaoke/stage.html:2857-2940 + 2944-3037 stay load-bearing until
-- Stage A7. shell/venue-renderers/spotlight-3d.js + particle-3d.js
-- (Stage A4b §3) are registered but have no live consumer in karaoke;
-- their only consumer is admin-venues.html's Three.js preview surface
-- (spec §5).
--
-- Position consistency. All 4 anchors have yaw_deg = NULL and
-- pitch_deg = NULL — 3D anchors live in panScene world space (sphere
-- around scene origin); no screen-space yaw/pitch projection. Same
-- posture as A2/A3/A4a's 2D-canvas anchors. Satisfies db/032's
-- venue_anchors_position_consistency CHECK constraint, which is the
-- type-agnostic paired-NULL rule
-- check ((yaw_deg is null) = (pitch_deg is null))
-- — both NULL passes for any type.
--
-- Stadium 3D entanglement note (spec §12.1). buildStadiumEffects3D
-- at karaoke/stage.html:2857-2940 builds BOTH the 4 cone meshes
-- (swept-beam-3d) AND the 2000 phone-light Points (point-cloud-3d)
-- — one function, one objects[] array, one update(), one dispose().
-- db/038 writes 2 separate anchors for stadium (one spotlight, one
-- particle); the procedural code stays bundled until A7's read-path
-- switch deletes the function. The same builder also produces the
-- userData.phases dead code (line 2865-2868) referenced in the
-- D-twinkle synthesis note above.
--
-- Companion docs:
--   • docs/VENUE-ADMIN-UI-A4B-BUILD-SPEC.md §2 (payload schemas with
--     fidelity tables); §8 (this migration's scope); §1 (kind
--     vocabulary + anchor id naming); §0.3 (locked decisions).
--   • db/032_venue_abstraction_schema.sql:253-258 — venue_anchors_type_check
--     CHECK constraint permitting both 'spotlight' and 'particle'.
--   • db/035_audio_anchor_rpcs_and_seed.sql:93-94 — v_known_types
--     array including 'spotlight' and 'particle' in the RPC
--     validation path.
--   • db/036_particle_anchor_seed.sql + db/037_spotlight_anchor_seed.sql
--     — the A3 + A4a seed patterns this migration mirrors.
-- ============================================================================


begin;


-- ─── 1. 3D anchor seed (4 rows) ──────────────────────────────────────────
-- INSERT order follows spec §1.1 kind enumeration (stadium beams,
-- speakeasy candles, stadium phone-lights, speakeasy smoke). Q2/Q3
-- verification queries display alphabetical by id (smoke, phone-lights,
-- candles, beams).
--
-- All four payloads carry `context: "3d-three"`. The registry dispatch
-- (spec §4.1) routes 3d-three anchors to shell/venue-renderers/
-- spotlight-3d.js + particle-3d.js (Stage A4b §3); 2d-canvas anchors
-- continue routing to spotlight.js + particle.js (A4a + A3).
--
-- Ghost venues remain out of scope (foundation pass §10.1 confirmed
-- addVenueEffects3D dispatcher only registers stadium + speakeasy).

insert into public.venue_anchors (
  id, venue_id, type, label, payload
) values

  -- stadium — 4 sweeping spotlight cone meshes (karaoke/stage.html:2884-2935)
  -- 4 THREE.CylinderGeometry cone meshes (radiusTop=0, radiusBottom=35,
  -- height=300, radialSegments=16, openEnded=true) pre-translated by
  -- (0, -150, 0) to pivot at the top. MeshBasicMaterial with opacity
  -- 0.06, side=BackSide (renders inside of cone — light-beam-from-outside
  -- effect), depthWrite=false. Per-cone hex color (warm whites/creams
  -- [#fffce0, #fffce0, #fff0cc, #fff0cc] — distinct from the A4a 2D
  -- swept-beam-2d palette of cool blues/purples [220,200,240,180]).
  -- Initial position on r=380 sphere at (phi, theta) per-cone; lookAt
  -- (0,0,0). Per-frame update (lines 2924-2933): angle += speed per
  -- cone (speeds [0.003, -0.004, 0.005, -0.003] = opposite-pair
  -- counter-rotation), phi wobbles via sin(frame * 0.01) * 0.08
  -- (slow vertical sway, period ≈ 628 frames). Pure frame-counter
  -- motion — no GSAP. The 2D swept-beam-2d anchor (anc_spot_stadium,
  -- A4a-shipped) renders concurrently in the live game.
  ('anc_spot_stadium_beams3d', 'stadium', 'spotlight', 'Cone beams (3D)',
   '{
     "kind": "swept-beam-3d",
     "context": "3d-three",
     "count": 4,
     "phis":        [0.15, 0.15, 0.12, 0.12],
     "theta_init":  [0.000000, 3.141593, 1.570796, -1.570796],
     "colors":      ["#fffce0", "#fffce0", "#fff0cc", "#fff0cc"],
     "speeds":      [0.003, -0.004, 0.005, -0.003],
     "sphere_radius": 380,
     "wobble_amplitude": 0.08,
     "wobble_speed": 0.01,
     "look_at": [0, 0, 0],
     "geometry": {
       "radius_top": 0,
       "radius_bottom": 35,
       "height": 300,
       "radial_segments": 16,
       "height_segments": 1,
       "open_ended": true,
       "translate_y": -150
     },
     "material": {
       "opacity": 0.06,
       "side": "back",
       "depth_write": false,
       "transparent": true
     }
   }'::jsonb),

  -- speakeasy — 40 candle glow Points (karaoke/stage.html:2980-3000)
  -- THREE.Points (single BufferGeometry, 40 vertices) with
  -- PointsMaterial color=#ffaa33 (warm amber), size=4,
  -- sizeAttenuation=true, transparent=true, base_opacity=0.7,
  -- depthWrite=false. Spatial layout: flat ring at table height in
  -- xz-plane — r ∈ [80, 330], y ∈ [-120, -80], theta uniform [0, 2π].
  -- Motion: every 4 frames, set SHARED PointsMaterial.opacity to
  -- 0.5 + rand*0.5 (lines 3024-3026) — ALL 40 candles flicker in
  -- lockstep because they share one material. NOT per-particle flicker
  -- (the source could've added a per-vertex attribute like A4b's
  -- point-cloud-3d does for phone-lights, but didn't; A4b reproduces
  -- source semantics exactly — see spec §2.5 Motion model note).
  -- Speakeasy now has 2 spotlight anchors: anc_spot_speakeasy
  -- (light-shaft 'Spotlights', A4a) + this new anchor ('Candles (3D)',
  -- A4b). The multi-anchor PERMIT rule (A4a D2) makes this work
  -- cleanly; effect-descriptive labels distinguish them in the panel
  -- list (spec §6) and the kind-aware confirm dialog (spec §6.4).
  ('anc_spot_speakeasy_candles', 'speakeasy', 'spotlight', 'Candles (3D)',
   '{
     "kind": "point-light",
     "context": "3d-three",
     "count": 40,
     "color": "#ffaa33",
     "sprite_size": 4,
     "size_attenuation": true,
     "base_opacity": 0.7,
     "depth_write": false,
     "transparent": true,
     "position_layout": "ring",
     "r_range": [80, 330],
     "y_range": [-120, -80],
     "theta_range": [0.000000, 6.283185],
     "flicker": {
       "mode": "global-sync-random",
       "frame_period": 4,
       "opacity_min": 0.5,
       "opacity_max": 1.0
     }
   }'::jsonb),

  -- stadium — 2000 phone-light Points (karaoke/stage.html:2861-2882)
  -- THREE.Points (single BufferGeometry, 2000 vertices) with
  -- PointsMaterial color=#ffffff, size=2.5, sizeAttenuation=true,
  -- transparent=true, base_opacity=0.8, depthWrite=false. Spatial
  -- layout: hemisphere region around the camera, r ∈ [460, 490] (near
  -- panorama dome wall at r=500), phi ∈ [0.471, 2.670] (avoids top
  -- pole — encoded as phi_norm_range [0.15, 0.85] of π per spec §2.6),
  -- theta uniform [0, 2π]. Y-flattening: y = cos(phi) * 0.4 - 80
  -- (drops crowd region below origin, flattens vertically). The source
  -- twinkle at lines 2920-2923 is GLOBAL-SYNC (every 3 frames, shared
  -- material.opacity = 0.5 + sin(frame*0.04)*0.3). The phases
  -- Float32Array at lines 2865-2868 is allocated with per-particle
  -- random phases [0, 2π] but NEVER READ — dead code proving
  -- per-particle intent. A4b builds the correct per-particle version
  -- via custom ShaderMaterial (D-twinkle, spec §3.7); payload encodes
  -- twinkle.mode = "per-particle-shader" + the four uniform values.
  -- Modulator binding (D-modulator, spec §2.6 / §3.8): crowd_brightness
  -- → opacity, SYNTHESIZED for A3 parity (A3's anc_par_stadium 2D
  -- phone-lights binds the same modulator name; the 3D source binds
  -- nothing). Renderer multiplies the per-particle twinkle by the
  -- modulator value when present; defaults to 1.0 when absent (current
  -- state, until A7 ships the driver registry). The 2D point-cloud
  -- anchor (anc_par_stadium, A3-shipped) renders concurrently in the
  -- live game.
  ('anc_par_stadium_phonelights3d', 'stadium', 'particle', 'Phone lights (3D)',
   '{
     "kind": "point-cloud-3d",
     "context": "3d-three",
     "count": 2000,
     "color": "#ffffff",
     "sprite_size": 2.5,
     "size_attenuation": true,
     "base_opacity": 0.8,
     "depth_write": false,
     "transparent": true,
     "position_layout": "hemisphere_flattened",
     "r_range": [460, 490],
     "phi_norm_range": [0.15, 0.85],
     "theta_range": [0.000000, 6.283185],
     "y_flatten_factor": 0.4,
     "y_offset": -80,
     "twinkle": {
       "mode": "per-particle-shader",
       "phase_init": "random-2pi",
       "phase_omega_per_frame": 0.04,
       "alpha_center": 0.5,
       "alpha_swing": 0.3
     },
     "modulator": {"name": "crowd_brightness", "target": "opacity"}
   }'::jsonb),

  -- speakeasy — 60 sphere-mesh smoke wisps (karaoke/stage.html:2946-2974
  -- construction + 3005-3022 update). 60 individual THREE.Mesh instances
  -- sharing ONE SphereGeometry(1, 6, 6) low-poly sphere, each with its
  -- own MeshBasicMaterial (color=#bbbbaa warm grey, per-instance
  -- opacity ∈ [0.01, 0.05], transparent=true, depthWrite=false). Per-
  -- instance scale ∈ [15, 55]. Initial spawn region (line 2961):
  -- r ∈ [50, 350], phi ∈ [0.4π, 0.9π], theta uniform [0, 2π]. Per-
  -- particle internal state: vy ∈ [0.08, 0.20] (positive = upward
  -- drift), vx/vz ∈ [-0.025, 0.025], life ∈ [0, 1], maxOpacity =
  -- initial material opacity. Per-frame update (lines 3005-3022):
  -- position += velocity, life += 0.003, material.opacity =
  -- maxOpacity * sin(life * π) (fade-in at life=0, peak at life=0.5,
  -- fade-out at life=1). Respawn at life%1 > 0.98 to a DIFFERENT
  -- spawn region (line 3018): r ∈ [50, 350], phi ∈ [0.55π, 0.90π],
  -- theta [0, 2π]. The narrower respawn phi range avoids the lower
  -- edge — preserves the byte-faithful divergence via two payload
  -- sub-objects (spec §2.7 Phi-range divergence note). NOT a bug, NOT
  -- a normalization — source-faithful. respawn=true (continuous life
  -- cycle, unlike A3's 2D smoke anc_par_speakeasy which is
  -- respawn:false one-shot burst). The 2D volumetric anchor renders
  -- concurrently in the live game.
  ('anc_par_speakeasy_smoke3d', 'speakeasy', 'particle', 'Smoke (3D)',
   '{
     "kind": "volumetric-3d",
     "context": "3d-three",
     "count": 60,
     "respawn": true,
     "color": "#bbbbaa",
     "depth_write": false,
     "transparent": true,
     "sphere_geometry": {
       "radius": 1,
       "width_segments": 6,
       "height_segments": 6,
       "shared": true
     },
     "scale_range": [15, 55],
     "opacity_range": [0.01, 0.05],
     "vy_range": [0.08, 0.20],
     "vx_range": [-0.025, 0.025],
     "vz_range": [-0.025, 0.025],
     "life_init_range": [0, 1],
     "life_increment_per_frame": 0.003,
     "opacity_curve": "sin_pi",
     "respawn_threshold": 0.98,
     "spawn_region_initial": {
       "r_range": [50, 350],
       "phi_norm_range": [0.4, 0.9],
       "theta_range": [0.000000, 6.283185]
     },
     "spawn_region_respawn": {
       "r_range": [50, 350],
       "phi_norm_range": [0.55, 0.90],
       "theta_range": [0.000000, 6.283185]
     },
     "y_flatten_factor": 0.5,
     "y_offset": -30
   }'::jsonb)

on conflict (id) do nothing;


commit;


-- ============================================================================
-- Verification queries (run AFTER COMMIT in Supabase SQL Editor)
-- ============================================================================
--
-- Three queries per spec §8.3, with Q3 split into FOUR sub-queries
-- (one per kind) to avoid the Supabase SQL Editor `limit 100`
-- auto-append injecting inside a CASE-expression string literal —
-- the verification-mechanics artifact caught in A4a Check 20
-- (db/037 verification log notes). Expect ALL queries to confirm.
-- No anon/grant queries needed — db/038 creates no functions.

-- ─── Q1. Seed landed: total count of 3d-three anchors ─────────────────────
select count(*) as count_3d
  from public.venue_anchors
 where payload->>'context' = '3d-three';
-- Expect: count_3d = 4.

-- ─── Q2. Per-anchor id / venue_id / type / kind / label correctness ───────
select id,
       venue_id,
       type,
       payload->>'kind' as kind,
       label
  from public.venue_anchors
 where payload->>'context' = '3d-three'
 order by id;
-- Expect 4 rows (alphabetical by id):
--   anc_par_speakeasy_smoke3d       | speakeasy | particle  | volumetric-3d  | Smoke (3D)
--   anc_par_stadium_phonelights3d   | stadium   | particle  | point-cloud-3d | Phone lights (3D)
--   anc_spot_speakeasy_candles      | speakeasy | spotlight | point-light    | Candles (3D)
--   anc_spot_stadium_beams3d        | stadium   | spotlight | swept-beam-3d  | Cone beams (3D)

-- ─── Q3.1. swept-beam-3d per-item array lengths match count ───────────────
select id,
       (payload->>'count')::int                    as count,
       jsonb_array_length(payload->'phis')         as phis_len,
       jsonb_array_length(payload->'theta_init')   as theta_init_len,
       jsonb_array_length(payload->'colors')       as colors_len,
       jsonb_array_length(payload->'speeds')       as speeds_len
  from public.venue_anchors
 where id = 'anc_spot_stadium_beams3d';
-- Expect 1 row:
--   anc_spot_stadium_beams3d | 4 | 4 | 4 | 4 | 4
-- All four per-item arrays must equal count=4. Any mismatch = transcription failure.

-- ─── Q3.2. point-light kind marker (flicker config present) ───────────────
select id,
       (payload->>'count')::int                       as count,
       payload->'flicker'->>'mode'                    as flicker_mode,
       (payload->'flicker'->>'frame_period')::int     as flicker_period,
       payload->>'color'                              as color
  from public.venue_anchors
 where id = 'anc_spot_speakeasy_candles';
-- Expect 1 row:
--   anc_spot_speakeasy_candles | 40 | global-sync-random | 4 | #ffaa33

-- ─── Q3.3. point-cloud-3d twinkle + modulator (D-twinkle + D-modulator) ───
select id,
       (payload->>'count')::int                            as count,
       payload->'twinkle'->>'mode'                         as twinkle_mode,
       payload->'twinkle'->>'phase_init'                   as phase_init,
       (payload->'twinkle'->>'phase_omega_per_frame')::float as phase_omega,
       payload->'modulator'->>'name'                       as modulator_name,
       payload->'modulator'->>'target'                     as modulator_target
  from public.venue_anchors
 where id = 'anc_par_stadium_phonelights3d';
-- Expect 1 row:
--   anc_par_stadium_phonelights3d | 2000 | per-particle-shader | random-2pi | 0.04 | crowd_brightness | opacity

-- ─── Q3.4. volumetric-3d respawn + spawn regions (asymmetry preserved) ────
select id,
       (payload->>'count')::int                                          as count,
       (payload->>'respawn')::bool                                       as respawn,
       payload->'spawn_region_initial' is not null                       as has_initial,
       payload->'spawn_region_respawn' is not null                       as has_respawn,
       (payload->'spawn_region_initial'->'phi_norm_range'->>0)::float    as initial_phi_lo,
       (payload->'spawn_region_initial'->'phi_norm_range'->>1)::float    as initial_phi_hi,
       (payload->'spawn_region_respawn'->'phi_norm_range'->>0)::float    as respawn_phi_lo,
       (payload->'spawn_region_respawn'->'phi_norm_range'->>1)::float    as respawn_phi_hi
  from public.venue_anchors
 where id = 'anc_par_speakeasy_smoke3d';
-- Expect 1 row:
--   anc_par_speakeasy_smoke3d | 60 | true | true | true | 0.4 | 0.9 | 0.55 | 0.9
-- Initial phi range [0.4, 0.9], respawn phi range [0.55, 0.9] — DIFFERENT
-- lower bounds confirm the byte-faithful spawn-region asymmetry preservation
-- per spec §2.7 Phi-range divergence note.
-- ============================================================================
