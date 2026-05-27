-- ============================================================================
-- Elsewhere — Venue Admin UI Stage A4a: spotlight anchor seed (2D-canvas)
-- Migration: 037
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Fourth migration in the Venue Admin UI workstream (Stage A4a per
-- docs/VENUE-ADMIN-UI-A4A-BUILD-SPEC.md §2 + §9 sequencing). A4a is the
-- 2D-canvas-only sub-stage of A4 (A4 was sub-staged into A4a + A4b in
-- planning chat 2026-05-27 — see spec §0.2). A4b ships 3D spotlight
-- builders + the absorbed 3D particle paths + the new Three.js admin
-- preview surface as a separate migration cycle.
--
-- SEED-ONLY migration. No RPCs created. Per spec §2.1, db/035's
-- rpc_venue_anchor_upsert and rpc_venue_anchor_delete are type-agnostic
-- — db/035 declares v_known_types including 'spotlight' (db/035:93-94)
-- and validates against the full vocabulary. The admin UI's spotlight
-- authoring path uses those existing RPCs unchanged.
--
-- One section, one transactional file:
--
--   1. Spotlight anchor seed (3 rows) — one per in-scope venue per spec
--      §0.3's locked enumeration: stadium, festival, speakeasy.
--      INSERT ... ON CONFLICT (id) DO NOTHING for idempotency
--      (db/035 / db/036 seed pattern). Deterministic ids:
--      anc_spot_<venue_id>.
--
-- Payload fidelity. Each row's payload jsonb is the §1 kind-discriminated
-- schema, transcribed from the procedural source at the cited line
-- numbers in karaoke/stage.html. The transcription was approved at
-- A4a §9 step 1 (the per-effect fidelity-check pass) and incorporates
-- the §1 amendment (commit d50cbc9):
--   • geometry.gradient_stops added to all 3 kinds (per-kind gradient
--     stop configuration captured in payload, not hardcoded in the
--     renderer);
--   • color fragment DROPPED for hue-driven kinds (swept-beam-2d,
--     pulsed-laser) — per-item color comes from top-level `hues` array
--     + shared geometry.sat_pct/lit_pct;
--   • light-shaft RETAINS the color fragment (single shared color);
--   • drift_speeds negative-first for pulsed-laser (source's
--     (i%2 ? 1 : -1) * 0.005 evaluates with i=0 → 0%2=0 (falsy) → -1,
--     so the sign pattern is [-, +, -, +, -, +], not [+, -, +, -, +, -]
--     as initially drafted in §1.4);
--   • first_pulse_offset_beats scalar added to pulsed-laser (captures
--     source's setTimeout(beatPulse, BEAT*0.5) initial delay);
--   • geometry.pivot field added to swept-beam-2d for consistency
--     with §1.4 / §1.5.
--
-- D8 dormancy. The 3 seeded spotlight anchors are DATA. Karaoke's read
-- path is unchanged — AMBIENT_PROFILES + addVenueEffects3D in
-- karaoke/stage.html stay load-bearing until Stage A7 (the read-path
-- switch + AMBIENT_PROFILES retirement). shell/venue-renderers/
-- spotlight.js (Stage A4a §3) is registered but has no live consumer
-- in karaoke; its only consumer is admin-venues.html's preview surface.
--
-- Position consistency. All 3 anchors are 2D-canvas screen-space overlays
-- (not sphere-pinned), so yaw_deg and pitch_deg are both NULL — satisfies
-- db/032's venue_anchors_position_consistency CHECK constraint, which is
-- the type-agnostic paired-NULL rule
-- check ((yaw_deg is null) = (pitch_deg is null))
-- — both NULL passes for any type, exactly as db/035's audio seed and
-- db/036's particle seed.
--
-- Companion docs:
--   • docs/VENUE-ADMIN-UI-A4A-BUILD-SPEC.md §1 (amended at d50cbc9) —
--     payload schema; §2 — this migration's scope; §0.3 — the 3 in-scope
--     venues; §6 — ghost-code boundary (4 ghost venues with no spotlight
--     or 3D content; A4a leaves them untouched).
--   • db/032_venue_abstraction_schema.sql:253-258 — venue_anchors_type_check
--     CHECK constraint including 'spotlight' in the vocabulary.
--   • db/035_audio_anchor_rpcs_and_seed.sql:93-94 — v_known_types array
--     including 'spotlight' (RPC validation path).
--   • db/036_particle_anchor_seed.sql — the A3 seed pattern this
--     migration mirrors.
-- ============================================================================


begin;


-- ─── 1. Spotlight anchor seed (3 rows) ───────────────────────────────────
-- One row per in-scope venue per spec §0.3's locked enumeration.
-- INSERT order follows the spec's listing order (stadium, festival,
-- speakeasy); Q2/Q3 verification queries below display alphabetical by
-- venue_id (festival, speakeasy, stadium).
--
-- Disco has NO spotlight anchor — its only spotlight-candidate effect
-- was the floor-flash gradient, classified as overlay-class in the A4
-- foundation pass and deferred to Stage A4.5 per Direction §7.
--
-- Honkytonk has NO spotlight anchor — its neon-tint full-screen flicker
-- is overlay-class (foundation pass §10.2), deferred to Stage A4.5.
--
-- Ghost venues (space, forest, underwater, dead-dragonlair) have NO
-- spotlight or 3D content per foundation pass §10.1. Stage A7 cleanup
-- territory. A4a leaves them untouched.

insert into public.venue_anchors (
  id, venue_id, type, label, payload
) values

  -- stadium — 4 sweeping spotlight beams (karaoke/stage.html:4593-4666)
  -- 4 trapezoid-gradient beams pivoting at top-center of canvas,
  -- recursively sweeping to random target angles via GSAP power1.inOut
  -- timeline (1.5-4s per sweep) with staggered start (i*800ms). Each
  -- beam has its own hue from the palette [220,200,240,180]; alpha
  -- ranges [0.08, 0.14] at spawn and [0.06, 0.16] per sweep target.
  -- The 3-stop gradient (stops at 0/0.5/1 with mid-stop alpha × 0.4)
  -- is captured in geometry.gradient_stops per spec §1 amendment
  -- (d50cbc9). The phone-lights particle (lines 4628-4641) and
  -- cheer-swell crowd modulator (4616-4626) drive the A3-shipped
  -- particle anchor anc_par_stadium, NOT this spotlight anchor. The
  -- targetAngle field in the source spawn (line 4599) is dead code
  -- — unused by sweepBeam and correctly omitted from the payload.
  ('anc_spot_stadium', 'stadium', 'spotlight', 'Spotlights',
   '{
     "kind": "swept-beam-2d",
     "context": "2d-canvas",
     "count": 4,
     "hues": [220, 200, 240, 180],
     "angle_init": [-0.375, -0.125, 0.125, 0.375],
     "base_alpha_range": [0.08, 0.14],
     "sweep_target_range": [-0.425, 0.425],
     "sweep_alpha_range": [0.06, 0.16],
     "sweep_duration_range_ms": [1500, 4000],
     "sweep_ease": "power1.inOut",
     "stagger_ms": 800,
     "geometry": {
       "pivot": "top-center",
       "top_width_px": 12,
       "bottom_width_norm": 1.0,
       "height_norm": 1.0,
       "sat_pct": 80,
       "lit_pct": 95,
       "gradient_stops": [
         {"at": 0,   "alpha_mult": 1.0},
         {"at": 0.5, "alpha_mult": 0.4},
         {"at": 1,   "alpha_mult": 0.0}
       ]
     }
   }'::jsonb),

  -- festival — 6 beat-pulsing lasers (karaoke/stage.html:4844-4916)
  -- 6 narrow rotated lasers pivoting at bottom-center of canvas, with
  -- continuous base-angle drift (per-frame +=drift_speeds[i], reflect
  -- at |angle| > π*0.48 → drift_range=1.507964) AND a beat-pulse tween
  -- fired every BEAT ms (BPM=128 → 468.75ms per beat). Pulse envelope:
  -- attack power3.out 60ms (alpha→0.85, width→base*2.5) then decay
  -- power2.in 380ms back to base. First pulse fires at BEAT*0.5
  -- → first_pulse_offset_beats=0.5. drift_speeds is negative-first
  -- per source (i%2 ? 1 : -1) * 0.005 — at i=0, 0%2=0 (falsy) → -1
  -- → -0.005. The 3-stop gradient (stops at 0/0.6/1 with mid-stop
  -- alpha × 0.3) is captured in geometry.gradient_stops per spec §1
  -- amendment. The strobe overlay (lines 4870-4884) is OUT OF A4a
  -- SCOPE — overlay-class, Stage A4.5. The 80-particle confetti
  -- (lines 4905-4914) is A3-shipped as anc_par_festival.
  ('anc_spot_festival', 'festival', 'spotlight', 'Spotlights',
   '{
     "kind": "pulsed-laser",
     "context": "2d-canvas",
     "count": 6,
     "hues": [0, 60, 120, 180, 240, 300],
     "angle_init": [1.099557, 0.959557, 0.819557, 0.679557, 0.539557, 0.399557],
     "drift_speeds": [-0.005, 0.005, -0.005, 0.005, -0.005, 0.005],
     "base_widths_px": [3, 5, 3, 5, 3, 5],
     "bpm": 128,
     "drift_range": 1.507964,
     "base_alpha": 0.35,
     "peak_alpha": 0.85,
     "peak_width_mult": 2.5,
     "attack_ms": 60,
     "attack_ease": "power3.out",
     "decay_ms": 380,
     "decay_ease": "power2.in",
     "first_pulse_offset_beats": 0.5,
     "geometry": {
       "pivot": "bottom-center",
       "emit_direction": "up",
       "height_norm": 1.0,
       "sat_pct": 100,
       "lit_pct": 65,
       "gradient_stops": [
         {"at": 0,   "alpha_mult": 1.0},
         {"at": 0.6, "alpha_mult": 0.3},
         {"at": 1,   "alpha_mult": 0.0}
       ]
     }
   }'::jsonb),

  -- speakeasy — 3 drifting amber light shafts (karaoke/stage.html:4762-4827)
  -- 3 vertical trapezoid shafts at fixed x positions [0.25, 0.50, 0.75]
  -- of canvas width, drifting via GSAP sine.inOut tweens on both x
  -- (±40px around current) and alpha ([0.03, 0.09] per tween) over
  -- 4-8s with per-shaft random initial stagger [0, 2000]ms. Shafts
  -- DO NOT rotate — only x and alpha drift (kind boundary distinguishing
  -- light-shaft from swept-beam-2d / pulsed-laser per spec §1.1). The
  -- 2-stop gradient (0/1) is captured in geometry.gradient_stops per
  -- spec §1 amendment. light-shaft RETAINS the color fragment (fixed
  -- rgb(255,210,140)) because it's a single-shared-color kind, unlike
  -- the hue-driven kinds. The 35-wisp volumetric smoke (lines 4785-4805)
  -- is A3-shipped as anc_par_speakeasy. The 60-mesh 3D smoke and 40
  -- 3D candles in buildSpeakeasyEffects3D (karaoke/stage.html:2941-3037)
  -- are OUT OF A4a SCOPE — A4b territory (3D extension stage).
  ('anc_spot_speakeasy', 'speakeasy', 'spotlight', 'Spotlights',
   '{
     "kind": "light-shaft",
     "context": "2d-canvas",
     "count": 3,
     "x_init_norm": [0.25, 0.50, 0.75],
     "base_alpha_range": [0.04, 0.08],
     "width_range_px": [60, 100],
     "drift_distance_px": 80,
     "drift_alpha_range": [0.03, 0.09],
     "drift_duration_range_ms": [4000, 8000],
     "drift_stagger_max_ms": 2000,
     "drift_ease": "sine.inOut",
     "geometry": {
       "pivot": "top",
       "top_inset_factor": 0.3,
       "bottom_outset_factor": 1.0,
       "height_norm": 0.7,
       "gradient_stops": [
         {"at": 0, "alpha_mult": 1.0},
         {"at": 1, "alpha_mult": 0.0}
       ]
     },
     "color": {"mode": "fixed", "value": "rgb(255,210,140)"}
   }'::jsonb)

on conflict (id) do nothing;


commit;


-- ============================================================================
-- Verification queries (run AFTER COMMIT in Supabase SQL Editor)
-- ============================================================================
--
-- Three queries per spec §2.3. Expect ALL THREE to confirm. No anon/grant
-- queries needed — db/037 creates no functions.

-- ─── Q1. Seed landed: total count ─────────────────────────────────────────
select count(*) as spotlight_count
  from public.venue_anchors
 where type = 'spotlight';
-- Expect: spotlight_count = 3.

-- ─── Q2. Per-venue id / kind / label correctness ──────────────────────────
select id,
       venue_id,
       payload->>'kind' as kind,
       label
  from public.venue_anchors
 where type = 'spotlight'
 order by venue_id;
-- Expect 3 rows:
--   anc_spot_festival   | festival   | pulsed-laser   | Spotlights
--   anc_spot_speakeasy  | speakeasy  | light-shaft    | Spotlights
--   anc_spot_stadium    | stadium    | swept-beam-2d  | Spotlights

-- ─── Q3. Payload schema spot-check (kind-required fields present) ─────────
select id,
       payload->>'kind' as kind,
       (payload->>'count')::int as count,
       case payload->>'kind'
         when 'swept-beam-2d' then 'hues_len=' || jsonb_array_length(payload->'hues')
         when 'pulsed-laser'  then 'hues_len=' || jsonb_array_length(payload->'hues') ||
                                  ' bpm=' || (payload->>'bpm')
         when 'light-shaft'   then 'x_init_norm_len=' || jsonb_array_length(payload->'x_init_norm')
       end as kind_marker,
       case when payload->'geometry' ? 'gradient_stops'
            then 'gradient_stops present'
            else 'gradient_stops MISSING'
       end as gradient_check
  from public.venue_anchors
 where type = 'spotlight'
 order by venue_id;
-- Expect 3 rows:
--   anc_spot_festival   | pulsed-laser   | 6 | hues_len=6 bpm=128 | gradient_stops present
--   anc_spot_speakeasy  | light-shaft    | 3 | x_init_norm_len=3  | gradient_stops present
--   anc_spot_stadium    | swept-beam-2d  | 4 | hues_len=4         | gradient_stops present
--
-- Per-item array lengths must match `count` for each row:
--   stadium:   hues_len=4 == count=4 ✓
--   festival:  hues_len=6 == count=6 ✓
--   speakeasy: x_init_norm_len=3 == count=3 ✓
-- Any row with mismatched lengths, NULL in kind_marker, or 'MISSING' in
-- gradient_check = transcription failure to fix.
-- ============================================================================
