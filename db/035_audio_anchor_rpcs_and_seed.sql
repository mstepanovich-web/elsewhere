-- ============================================================================
-- Elsewhere — Venue Admin UI Stage 2: anchor RPCs + audio anchor seed
-- Migration: 035
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Second migration in the Venue Admin UI workstream (Stage A2 per
-- docs/VENUE-ADMIN-UI-A1-BUILD-SPEC.md §7).
--
-- Three sections, one transactional file (mirrors db/003's structure
-- of admin setup + table creation + seed inserts in one file):
--
--   1. rpc_venue_anchor_upsert  — INSERT-or-UPDATE on the id column,
--      SECURITY DEFINER, is_platform_admin-gated. Supports the admin
--      UI's create + edit operations on venue_anchors rows.
--
--   2. rpc_venue_anchor_delete  — delete by id, same gating. Supports
--      the admin UI's delete + the §8.2 Check 9 round-trip.
--
--   3. Audio anchor seed (19 rows) — programmatic seed per §7.3.
--      INSERT ... ON CONFLICT (id) DO NOTHING for idempotency.
--      The 19 audio-only venues' sound references are fully known
--      from AMBIENT_PROFILES (per the A1 foundation pass's locked
--      enumeration in spec §2); hand-authoring through the UI would
--      be busywork against a known data set.
--
-- Error codes (same vocabulary as db/034 plus P0002 for anchor delete):
--   • 42501 — caller is not authenticated, OR caller's
--     profiles.is_platform_admin is not true.
--   • 02000 — p_id is null/empty (upsert+delete); p_venue_id is
--     null/empty (upsert).
--   • 22023 — p_partial contains an unknown key, OR a 'type' value
--     not in the venue_anchors_type_check vocabulary (defensive; the
--     DB CHECK also rejects).
--   • 22004 — INSERT path missing required 'type' in p_partial.
--   • P0002 — p_venue_id well-formed but no matching venue_defaults
--     row (upsert); p_id has no matching venue_anchors row (delete).
--
-- Grant surface — REVOKE FROM PUBLIC + REVOKE FROM anon + GRANT TO
-- authenticated per RPC. Per the Stage A1 verification log's Bug 2
-- doctrine: Supabase's ALTER DEFAULT PRIVILEGES auto-grants EXECUTE
-- directly to anon on every new public-schema function — these direct
-- grants are NOT inherited from PUBLIC, so REVOKE FROM PUBLIC alone is
-- a no-op in Supabase. REVOKE FROM anon is the load-bearing fix.
-- REVOKE FROM PUBLIC kept as defensive belt for non-Supabase replay.
-- service_role retains EXECUTE intentionally (backend-key role).
--
-- Companion docs:
--   • docs/VENUE-ADMIN-UI-A1-BUILD-SPEC.md §7 — the binding spec.
--   • docs/SESSION-LOGS/VENUE-ADMIN-UI-A1-STAGE-1-VERIFICATION-LOG.md
--     — Bug 2 (the anon-grant doctrine this migration applies from
--     the start, not as a post-apply fix).
--   • db/032_venue_abstraction_schema.sql:231-301 — venue_anchors
--     table definition (FK to venue_defaults ON DELETE RESTRICT,
--     CHECK on type vocabulary, paired-NULL check on yaw/pitch).
--   • db/003_admin_and_venue_settings.sql:126-152 — venue_defaults
--     seed pattern (INSERT ... ON CONFLICT DO NOTHING) this seed
--     section mirrors.
-- ============================================================================


begin;


-- ─── 1. rpc_venue_anchor_upsert (NEW) ────────────────────────────────────
-- INSERT-or-UPDATE on the id column. Existence is checked first; if a
-- row exists for p_id, UPDATE with key-exists semantics (only fields in
-- p_partial are touched). If no row, INSERT with provided fields plus
-- p_id and p_venue_id; INSERT requires 'type' in p_partial since the
-- column is NOT NULL.
drop function if exists public.rpc_venue_anchor_upsert(text, text, jsonb);

create function public.rpc_venue_anchor_upsert(
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
                                  'audio', 'video', 'link-hotspot'];
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

revoke execute on function public.rpc_venue_anchor_upsert(text, text, jsonb) from public;
revoke execute on function public.rpc_venue_anchor_upsert(text, text, jsonb) from anon;
grant  execute on function public.rpc_venue_anchor_upsert(text, text, jsonb) to authenticated;

comment on function public.rpc_venue_anchor_upsert(text, text, jsonb) is
  'INSERT-or-UPDATE of public.venue_anchors. is_platform_admin gate '
  '(raises 42501 if not authenticated or not admin). Accepts p_id, '
  'p_venue_id, and a jsonb of column -> new-value pairs (subset of: '
  'type, yaw_deg, pitch_deg, label, start_sec, end_sec, link, payload, '
  'is_broken). UPDATE path uses the jsonb ? key-exists operator so '
  'absent keys preserve existing column values. INSERT path requires '
  '''type'' in p_partial (NOT NULL column). Raises 02000 if p_id or '
  'p_venue_id is null/empty; P0002 if p_venue_id is well-formed but '
  'no matching venue_defaults row; 22023 on unknown p_partial key or '
  'on type not in the anchor type vocabulary; 22004 if INSERT path '
  'lacks ''type''. Per docs/VENUE-ADMIN-UI-A1-BUILD-SPEC.md §7.';


-- ─── 2. rpc_venue_anchor_delete (NEW) ────────────────────────────────────
-- Delete by id. Raises P0002 if no row matches (distinct from 02000
-- input-absent semantics). The venue_anchors → venue_defaults FK is
-- ON DELETE RESTRICT but that guards against deleting venues with live
-- anchors, not against deleting anchors themselves — anchor delete is
-- unconstrained.
drop function if exists public.rpc_venue_anchor_delete(text);

create function public.rpc_venue_anchor_delete(p_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id  uuid    := auth.uid();
  v_is_admin boolean;
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

  -- 3. Validate p_id presence
  if p_id is null or length(p_id) = 0 then
    raise exception 'anchor id required' using errcode = '02000';
  end if;

  -- 4. Delete; raise if no row matched
  delete from public.venue_anchors where id = p_id;
  if not found then
    raise exception 'anchor not found: %', p_id using errcode = 'P0002';
  end if;
end;
$$;

revoke execute on function public.rpc_venue_anchor_delete(text) from public;
revoke execute on function public.rpc_venue_anchor_delete(text) from anon;
grant  execute on function public.rpc_venue_anchor_delete(text) to authenticated;

comment on function public.rpc_venue_anchor_delete(text) is
  'DELETE a public.venue_anchors row by id. is_platform_admin gate '
  '(raises 42501 if not). Raises 02000 if p_id is null/empty; P0002 '
  'if no row matches p_id. Per docs/VENUE-ADMIN-UI-A1-BUILD-SPEC.md §7.';


-- ─── 3. Audio anchor seed (19 rows) ──────────────────────────────────────
-- One row per audio-only venue per spec §2's locked inventory. Uses
-- the db/003 INSERT ... ON CONFLICT DO NOTHING pattern for idempotency
-- — re-running the migration leaves seeded rows unchanged. Deterministic
-- ids (anc_aud_<venue_id>) per §7.3.
--
-- enchantedforest uses sound_id='enchantedforest' (NOT 'forest') per
-- OQ-S1's resolution in spec §10 — matches the AMBIENT_PROFILES entry's
-- hardcoded playAmbientMp3('enchantedforest') rather than the unused
-- soundId: "forest" field in venues.json.
--
-- kids-dino2 uses the shared kids-dino sound (sound_id='kids-dino')
-- per the AMBIENT_PROFILES entry at karaoke/stage.html:4990.
insert into public.venue_anchors (
  id, venue_id, type, label, payload
) values
  ('anc_aud_hollywoodbowl',  'hollywoodbowl',  'audio', 'Ambient',
   '{"type":"mp3","sound_id":"hollywoodbowl"}'::jsonb),
  ('anc_aud_amphitheater',   'amphitheater',   'audio', 'Ambient',
   '{"type":"mp3","sound_id":"amphitheater"}'::jsonb),
  ('anc_aud_colosseum',      'colosseum',      'audio', 'Ambient',
   '{"type":"mp3","sound_id":"colosseum"}'::jsonb),
  ('anc_aud_drivein',        'drivein',        'audio', 'Ambient',
   '{"type":"mp3","sound_id":"drivein"}'::jsonb),
  ('anc_aud_rooftop',        'rooftop',        'audio', 'Ambient',
   '{"type":"mp3","sound_id":"rooftop"}'::jsonb),
  ('anc_aud_broadway',       'broadway',       'audio', 'Ambient',
   '{"type":"mp3","sound_id":"broadway"}'::jsonb),
  ('anc_aud_supperclub',     'supperclub',     'audio', 'Ambient',
   '{"type":"mp3","sound_id":"supperclub"}'::jsonb),
  ('anc_aud_cabaret',        'cabaret',        'audio', 'Ambient',
   '{"type":"mp3","sound_id":"cabaret"}'::jsonb),
  ('anc_aud_bourbonstreet',  'bourbonstreet',  'audio', 'Ambient',
   '{"type":"mp3","sound_id":"bourbonstreet"}'::jsonb),
  ('anc_aud_saloon',         'saloon',         'audio', 'Ambient',
   '{"type":"mp3","sound_id":"saloon"}'::jsonb),
  ('anc_aud_spacestation',   'spacestation',   'audio', 'Ambient',
   '{"type":"mp3","sound_id":"spacestation"}'::jsonb),
  ('anc_aud_enchantedforest','enchantedforest','audio', 'Ambient',
   '{"type":"mp3","sound_id":"enchantedforest"}'::jsonb),
  ('anc_aud_dragonlair',     'dragonlair',     'audio', 'Ambient',
   '{"type":"mp3","sound_id":"dragonlair"}'::jsonb),
  ('anc_aud_kids-candy',     'kids-candy',     'audio', 'Ambient',
   '{"type":"mp3","sound_id":"kids-candy"}'::jsonb),
  ('anc_aud_kids-dino',      'kids-dino',      'audio', 'Ambient',
   '{"type":"mp3","sound_id":"kids-dino"}'::jsonb),
  ('anc_aud_kids-dino2',     'kids-dino2',     'audio', 'Ambient',
   '{"type":"mp3","sound_id":"kids-dino"}'::jsonb),
  ('anc_aud_kids-northpole', 'kids-northpole', 'audio', 'Ambient',
   '{"type":"mp3","sound_id":"kids-northpole"}'::jsonb),
  ('anc_aud_kids-princess',  'kids-princess',  'audio', 'Ambient',
   '{"type":"mp3","sound_id":"kids-princess"}'::jsonb),
  ('anc_aud_kids-winter',    'kids-winter',    'audio', 'Ambient',
   '{"type":"mp3","sound_id":"kids-winter"}'::jsonb)
on conflict (id) do nothing;


commit;


-- ============================================================================
-- Verification queries (run AFTER COMMIT in Supabase SQL Editor)
-- ============================================================================

-- ─── rpc_venue_anchor_upsert ──────────────────────────────────────────────

-- (1) Function exists with the expected signature and SECURITY DEFINER.
select proname, prosecdef, pg_get_function_result(oid) as returns,
       pg_get_function_arguments(oid) as args
  from pg_proc
 where proname = 'rpc_venue_anchor_upsert' and pronamespace = 'public'::regnamespace;
-- Expect: 1 row, prosecdef=t, returns=public.venue_anchors,
--         args='p_id text, p_venue_id text, p_partial jsonb'.

-- (2) authenticated has EXECUTE.
select has_function_privilege('authenticated',
  'public.rpc_venue_anchor_upsert(text, text, jsonb)'::regprocedure, 'EXECUTE') as authed;
-- Expect: authed=true.

-- (3) anon does NOT have EXECUTE.
select has_function_privilege('anon',
  'public.rpc_venue_anchor_upsert(text, text, jsonb)'::regprocedure, 'EXECUTE') as anon_authed;
-- Expect: anon_authed=false.


-- ─── rpc_venue_anchor_delete ──────────────────────────────────────────────

-- (4) Function exists.
select proname, prosecdef, pg_get_function_result(oid) as returns,
       pg_get_function_arguments(oid) as args
  from pg_proc
 where proname = 'rpc_venue_anchor_delete' and pronamespace = 'public'::regnamespace;
-- Expect: 1 row, prosecdef=t, returns=void, args='p_id text'.

-- (5) authenticated has EXECUTE; (6) anon does NOT.
select has_function_privilege('authenticated',
  'public.rpc_venue_anchor_delete(text)'::regprocedure, 'EXECUTE') as authed;
select has_function_privilege('anon',
  'public.rpc_venue_anchor_delete(text)'::regprocedure, 'EXECUTE') as anon_authed;
-- Expect: authed=true; anon_authed=false.


-- ─── Audio anchor seed ────────────────────────────────────────────────────

-- (7) Seed landed: total count.
select count(*) as audio_count from public.venue_anchors where type = 'audio';
-- Expect: audio_count = 19.

-- (8) Per-venue sound_id correctness, including the kids-dino2 shared sound.
select venue_id, payload->>'sound_id' as sound_id, label
  from public.venue_anchors
 where type = 'audio'
 order by venue_id;
-- Expect 19 rows. For 18 venues: sound_id = venue_id.
-- For kids-dino2: sound_id = 'kids-dino' (the shared-sound exception).
-- label = 'Ambient' for all 19.
-- ============================================================================
