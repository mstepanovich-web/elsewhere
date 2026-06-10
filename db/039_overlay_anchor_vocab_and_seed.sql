-- ============================================================================
-- Elsewhere — Venue Admin UI Stage 4.5: overlay type vocab + overlay anchor seed
-- Migration: 039
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Sixth migration in the Venue Admin UI workstream (Stage 4.5 per
-- docs/VENUE-ADMIN-UI-A4.5-BUILD-SPEC.md §7). Introduces the `overlay`
-- anchor type: screen-space visual overlays that are neither directional
-- light sources (spotlight) nor particulate matter (particle) nor
-- informative markers (callout). Translates three procedural ancestors
-- from karaoke/stage.html's AMBIENT_PROFILES: disco floor-flash,
-- festival strobe, honkytonk neon-tint.
--
-- UNLIKE db/036 (particle) and db/037 (spotlight), which were SEED-ONLY
-- because db/035's RPC vocabulary already covered their types, this
-- migration is a VOCAB-EXTENSION migration: `overlay` is NOT yet in the
-- type vocabulary, so it must be added in BOTH places that mirror it —
-- the DB CHECK constraint AND the RPC's v_known_types array — or admin
-- overlay upserts will be rejected (errcode 22023) by the RPC even after
-- the CHECK is widened. This is the correctness keystone of the stage.
--
-- Three sections, one transactional file (mirrors db/035's structure):
--
--   1. Extend venue_anchors_type_check — DROP + re-CREATE the CHECK
--      constraint, adding exactly one value ('overlay') to the existing
--      seven. Per the db/032:248-253 doctrine (CHECK, not ENUM type,
--      precisely so it extends via DROP+CREATE rather than ALTER TYPE).
--
--   2. Extend rpc_venue_anchor_upsert's vocab mirror — CREATE OR REPLACE
--      the function with its FULL body byte-faithful to db/035:72-187,
--      changing only the v_known_types array (gains 'overlay'). The RPC
--      validates p_partial->>'type' against v_known_types defensively
--      (db/035:131-136); leaving it stale would reject overlay upserts.
--      CREATE OR REPLACE preserves grants; the grant block (section 3)
--      is re-stated belt-and-suspenders per the db/035 Bug-2 doctrine.
--
--   3. Overlay anchor seed (3 rows) — one per in-scope venue, deterministic
--      ids (anc_ovl_<venue>_<effect>), INSERT ... ON CONFLICT (id) DO
--      NOTHING for idempotency (the db/035 seed pattern). Payload carries
--      ONLY kind/region/fill/modulator/envelope — the anchor `type` is
--      the table column ('overlay'), never duplicated inside payload
--      (matches db/035's audio seed: column type='audio', payload's own
--      "type":"mp3" is a payload-internal discriminator, not the anchor
--      type). All three are screen-space: yaw_deg/pitch_deg default NULL,
--      satisfying db/032's venue_anchors_position_consistency CHECK.
--
-- Type vocabulary (8 values after this migration):
--   callout, pin, spotlight, particle, audio, video, link-hotspot, overlay
--   (DO NOT add 'spotlight-3d'/'particle-3d' — those are renderer-registry
--    keys per A4b's Gate-5 D-dispatch, NOT DB types; the 3D-ness lives in
--    payload.context, not the type column. See db/032 + the A4b spec.)
--
-- Overlay payload contract (per spec §2-§3):
--   kind       — 'solid-fill' | 'gradient-fill' (discriminates PAINT only)
--   region     — {x,y,w,h} normalized 0-1 (full-canvas {0,0,1,1} default)
--   fill       — solid-fill: {color:"r,g,b"}; gradient-fill: {direction, stops[]}
--   modulator  — 'beat' {bpm, first_trigger_beats, interval_beats, target_alpha}
--                | 'stochastic' {cooldown_frames, change_probability, states,
--                                low_state_probability, initial_state, alpha_scale}
--   envelope   — 'pulse' {rest_alpha, attack{duration_sec,ease}, decay{...}}
--                | 'hold' {} (instant set, persists until next event)
--                ease ∈ {explicit GSAP-equiv name | "default" (→ power1.out)}
--
-- Source ancestors (karaoke/stage.html @ 1fc2552):
--   disco floor-flash  — lines 4700-4721  (gradient-fill / beat / pulse)
--   festival strobe     — lines 4873-4893  (solid-fill / beat / pulse)
--   honkytonk neon-tint — lines 4837-4842  (solid-fill / stochastic / hold)
--
-- Error codes (inherited from db/035's rpc_venue_anchor_upsert, unchanged):
--   42501 / 02000 / 22023 / 22004 / P0002 — see db/035 header.
--
-- Stage 4.5 ships DORMANT per D8: the 3 seeded anchors are data only;
-- karaoke/stage.html keeps reading AMBIENT_PROFILES until Stage 7. This
-- migration adds no reader-path change.
--
-- Companion docs:
--   • docs/VENUE-ADMIN-UI-A4.5-BUILD-SPEC.md §7 — the binding spec.
--   • docs/A4_5-BUILD-SPEC-BRIEF.md — the foundation brief (locked decisions).
--   • db/035_audio_anchor_rpcs_and_seed.sql:72-204 — the canonical
--     rpc_venue_anchor_upsert body this migration reproduces (one line
--     changed) + the grant doctrine.
--   • db/032_venue_abstraction_schema.sql:248-266 — the type CHECK +
--     position-consistency CHECK this migration extends/satisfies.
-- ============================================================================


begin;


-- ─── 1. Extend the type vocabulary (DROP + re-CREATE per db/032 doctrine) ─────
-- db/032:254-258 declared seven values. This adds exactly one: 'overlay'.
-- The DROP+ADD re-validates existing rows; all current rows carry valid
-- types, so the ADD succeeds. CHECK (not ENUM) precisely so this is a
-- one-statement extension rather than an ALTER TYPE ADD VALUE.
alter table public.venue_anchors drop constraint venue_anchors_type_check;
alter table public.venue_anchors add constraint venue_anchors_type_check
  check (type in (
    'callout', 'pin', 'spotlight', 'particle',
    'audio', 'video', 'link-hotspot', 'overlay'
  ));


-- ─── 2. Extend rpc_venue_anchor_upsert's vocab mirror ────────────────────────
-- FULL body reproduced byte-faithful from db/035:72-187. The ONLY change
-- is the v_known_types array, which gains 'overlay' (last element). All
-- argument types, the return type, security definer, search_path, the six
-- declared variables, all six numbered logic blocks, the UPDATE path's
-- nine key-exists CASE clauses, the INSERT path's required-type guard and
-- twelve-column insert, and `return v_row` are unchanged. CREATE OR REPLACE
-- (not db/035's drop+create) because the function exists in prod — replace
-- preserves dependencies + grants + the existing comment.
create or replace function public.rpc_venue_anchor_upsert(
  p_id       text,
  p_venue_id text,
  p_partial  jsonb
)
returns public.venue_anchors
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id     uuid    := auth.uid();
  v_is_admin    boolean;
  v_row         public.venue_anchors;
  v_existing_id text;
  v_venue_ok    boolean;
  v_key         text;
  v_type        text;
  v_known_keys  text[]  := ARRAY['type', 'yaw_deg', 'pitch_deg', 'label',
                                  'start_sec', 'end_sec', 'link',
                                  'payload', 'is_broken'];
  v_known_types text[]  := ARRAY['callout', 'pin', 'spotlight', 'particle',
                                  'audio', 'video', 'link-hotspot', 'overlay'];
begin
  -- 1. Authentication
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- 2. Admin gate
  select is_platform_admin into v_is_admin
    from public.profiles where id = v_user_id;
  if coalesce(v_is_admin, false) = false then
    raise exception 'not a platform admin' using errcode = '42501';
  end if;

  -- 3. Validate p_id and p_venue_id presence
  if p_id is null or length(p_id) = 0 then
    raise exception 'anchor id required' using errcode = '02000';
  end if;
  if p_venue_id is null or length(p_venue_id) = 0 then
    raise exception 'venue_id required' using errcode = '02000';
  end if;

  -- 4. Verify venue_id exists
  select true into v_venue_ok
    from public.venue_defaults where venue_id = p_venue_id;
  if v_venue_ok is null then
    raise exception 'venue not found: %', p_venue_id using errcode = 'P0002';
  end if;

  -- 5. Validate p_partial keys + type-vocabulary defensively
  if p_partial is not null then
    for v_key in select jsonb_object_keys(p_partial) loop
      if not (v_key = any(v_known_keys)) then
        raise exception 'unknown key in p_partial: %', v_key
          using errcode = '22023';
      end if;
    end loop;
    if p_partial ? 'type' then
      v_type := p_partial->>'type';
      if not (v_type = any(v_known_types)) then
        raise exception 'invalid anchor type: %', v_type
          using errcode = '22023';
      end if;
    end if;
  end if;

  -- 6. Existence-driven branch: UPDATE if row present, INSERT if not
  select id into v_existing_id from public.venue_anchors where id = p_id;

  if v_existing_id is not null then
    -- UPDATE path: key-exists semantics; only touch present columns.
    update public.venue_anchors set
      type        = case when p_partial ? 'type'        then p_partial->>'type'                  else type end,
      yaw_deg     = case when p_partial ? 'yaw_deg'     then (p_partial->>'yaw_deg')::numeric    else yaw_deg end,
      pitch_deg   = case when p_partial ? 'pitch_deg'   then (p_partial->>'pitch_deg')::numeric  else pitch_deg end,
      label       = case when p_partial ? 'label'       then p_partial->>'label'                 else label end,
      start_sec   = case when p_partial ? 'start_sec'   then (p_partial->>'start_sec')::numeric  else start_sec end,
      end_sec     = case when p_partial ? 'end_sec'     then (p_partial->>'end_sec')::numeric    else end_sec end,
      link        = case when p_partial ? 'link'        then p_partial->'link'                   else link end,
      payload     = case when p_partial ? 'payload'     then p_partial->'payload'                else payload end,
      is_broken   = case when p_partial ? 'is_broken'   then (p_partial->>'is_broken')::boolean  else is_broken end,
      updated_by  = v_user_id
    where id = p_id
    returning * into v_row;
  else
    -- INSERT path: require 'type' (NOT NULL column on the table).
    if p_partial is null or not (p_partial ? 'type') then
      raise exception 'type required for new anchor (NOT NULL column)'
        using errcode = '22004';
    end if;

    insert into public.venue_anchors (
      id, venue_id, type,
      yaw_deg, pitch_deg, label, start_sec, end_sec, link, payload, is_broken,
      updated_by
    )
    values (
      p_id, p_venue_id, p_partial->>'type',
      (p_partial->>'yaw_deg')::numeric,
      (p_partial->>'pitch_deg')::numeric,
      coalesce(p_partial->>'label', ''),
      (p_partial->>'start_sec')::numeric,
      (p_partial->>'end_sec')::numeric,
      case when p_partial ? 'link' then p_partial->'link' else null end,
      coalesce(p_partial->'payload', '{}'::jsonb),
      coalesce((p_partial->>'is_broken')::boolean, false),
      v_user_id
    )
    returning * into v_row;
  end if;

  return v_row;
end;
$$;


-- ─── 3. Re-affirm grant surface (belt-and-suspenders) ────────────────────────
-- CREATE OR REPLACE preserves the db/035 grants; re-stated per the Stage A1
-- Bug-2 doctrine (Supabase auto-grants EXECUTE to anon directly; REVOKE FROM
-- anon is the load-bearing line, REVOKE FROM PUBLIC is the non-Supabase belt).
-- service_role retains EXECUTE intentionally. rpc_venue_anchor_delete is
-- type-agnostic and untouched by this migration.
revoke execute on function public.rpc_venue_anchor_upsert(text, text, jsonb) from public;
revoke execute on function public.rpc_venue_anchor_upsert(text, text, jsonb) from anon;
grant  execute on function public.rpc_venue_anchor_upsert(text, text, jsonb) to authenticated;


-- ─── 4. Overlay anchor seed (3 rows) ─────────────────────────────────────────
-- One row per in-scope venue. db/035 ON CONFLICT DO NOTHING idempotent
-- pattern; column list (id, venue_id, type, label, payload) — yaw_deg/
-- pitch_deg default NULL (screen-space), is_broken defaults false, link/
-- start_sec/end_sec NULL. Payload carries ONLY kind/region/fill/modulator/
-- envelope; the anchor type is the `type` column.
--
-- Fidelity (each constant traces to karaoke/stage.html source per spec §2.5):
--   disco     — 0.18 target / 0.05 power3.out attack / 0.4 power2.in decay /
--               bottom-40% region / vertical pink(255,180,255@1.0)→purple
--               (120,80,255@0.5) gradient / 120 BPM / 0.5+1 beats.
--   festival  — 0.25 target / 0.04 default attack / 0.2 default decay /
--               full region / solid white / 128 BPM / first@beat-4, every-4th.
--   honkytonk — 180-frame cooldown / 0.02 per-frame prob / [0.3,1.0] states /
--               0.3 low-state prob / 1.0 init / 0.04 alpha-scale / solid amber
--               (255,100,50) / hold envelope (instant, no ease).
insert into public.venue_anchors (
  id, venue_id, type, label, payload
) values
  ('anc_ovl_disco_floorflash', 'disco', 'overlay', 'Overlay',
   '{"kind":"gradient-fill","region":{"x":0,"y":0.6,"w":1,"h":0.4},"fill":{"direction":"vertical","stops":[{"pos":0,"color":"255,180,255","alpha_scale":1.0},{"pos":1,"color":"120,80,255","alpha_scale":0.5}]},"modulator":{"type":"beat","bpm":120,"first_trigger_beats":0.5,"interval_beats":1,"target_alpha":0.18},"envelope":{"shape":"pulse","rest_alpha":0,"attack":{"duration_sec":0.05,"ease":"power3.out"},"decay":{"duration_sec":0.4,"ease":"power2.in"}}}'::jsonb),

  ('anc_ovl_festival_strobe', 'festival', 'overlay', 'Overlay',
   '{"kind":"solid-fill","region":{"x":0,"y":0,"w":1,"h":1},"fill":{"color":"255,255,255"},"modulator":{"type":"beat","bpm":128,"first_trigger_beats":4,"interval_beats":4,"target_alpha":0.25},"envelope":{"shape":"pulse","rest_alpha":0,"attack":{"duration_sec":0.04,"ease":"default"},"decay":{"duration_sec":0.2,"ease":"default"}}}'::jsonb),

  ('anc_ovl_honkytonk_neon', 'honkytonk', 'overlay', 'Overlay',
   '{"kind":"solid-fill","region":{"x":0,"y":0,"w":1,"h":1},"fill":{"color":"255,100,50"},"modulator":{"type":"stochastic","cooldown_frames":180,"change_probability":0.02,"states":[0.3,1.0],"low_state_probability":0.3,"initial_state":1.0,"alpha_scale":0.04},"envelope":{"shape":"hold"}}'::jsonb)
on conflict (id) do nothing;


commit;


-- ============================================================================
-- Verification queries (run AFTER COMMIT in Supabase SQL Editor)
-- ============================================================================

-- (1) CHECK constraint now admits 'overlay' (and still the original seven).
select pg_get_constraintdef(oid) as type_check_def
  from pg_constraint
 where conname = 'venue_anchors_type_check'
   and conrelid = 'public.venue_anchors'::regclass;
-- Expect: CHECK ((type = ANY (ARRAY[... 'link-hotspot'::text, 'overlay'::text]))) — 8 values.

-- (2) RPC vocab mirror now contains 'overlay'.
select pg_get_functiondef('public.rpc_venue_anchor_upsert(text, text, jsonb)'::regprocedure)
       like '%''overlay''%' as rpc_has_overlay;
-- Expect: rpc_has_overlay = true.

-- (3) Grant surface intact post-replace.
select has_function_privilege('authenticated',
  'public.rpc_venue_anchor_upsert(text, text, jsonb)'::regprocedure, 'EXECUTE') as authed,
       has_function_privilege('anon',
  'public.rpc_venue_anchor_upsert(text, text, jsonb)'::regprocedure, 'EXECUTE') as anon_authed;
-- Expect: authed=true, anon_authed=false.

-- (4) Seed landed: count.
select count(*) as overlay_count from public.venue_anchors where type = 'overlay';
-- Expect: overlay_count = 3.

-- (5) Per-venue kind/modulator/envelope spot-check.
select venue_id,
       payload->>'kind'              as kind,
       payload->'modulator'->>'type' as modulator_type,
       payload->'envelope'->>'shape' as envelope_shape,
       label
  from public.venue_anchors
 where type = 'overlay'
 order by venue_id;
-- Expect 3 rows:
--   disco     | gradient-fill | beat       | pulse | Overlay
--   festival  | solid-fill    | beat       | pulse | Overlay
--   honkytonk | solid-fill    | stochastic | hold  | Overlay

-- (6) Position-consistency: all overlay anchors are screen-space (both NULL).
select count(*) as bad_position from public.venue_anchors
 where type = 'overlay' and (yaw_deg is not null or pitch_deg is not null);
-- Expect: bad_position = 0.
-- ============================================================================
