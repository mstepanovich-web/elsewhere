-- ============================================================================
-- Elsewhere — Venue Admin UI Stage 1: rpc_venue_default_update
-- Migration: 034
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Single new SECURITY DEFINER RPC for admin-UI venue_defaults updates.
-- The first migration in the Venue Admin UI workstream (Stage A1 per
-- docs/VENUE-ADMIN-UI-A1-BUILD-SPEC.md §6).
--
-- UPDATE-only by construction. All 26 venue_defaults rows are pre-seeded
-- by db/003:126-152; the admin UI edits those rows, never creates new
-- ones. Creating new venues (Part 2 — post-Phase-5) is a separate spec
-- with full schema-side seeding (skybox path, name, category, etc.) and
-- is NOT this RPC's responsibility. Eliminating the INSERT branch
-- removes the silent-zero failure mode where an INSERT with partial
-- yaw/pitch would default NOT NULL columns to 0 via coalesce,
-- mis-seeding a venue's camera. The function refuses to operate on a
-- missing row (raises P0002) instead.
--
-- Error codes (each distinct so diagnostics are unambiguous):
--   • 42501 (insufficient_privilege) — caller is not authenticated, OR
--     caller's profiles.is_platform_admin is not true.
--   • 02000 (no_data)                — p_venue_id is null or empty.
--   • 22023 (invalid_parameter_value) — p_partial contains an unknown key
--     (not in the editable column set).
--   • 22004 (null_value_not_allowed)  — p_partial sets a NOT NULL column
--     (back_yaw / back_pitch / front_yaw / front_pitch) to null.
--   • P0002 (no_data_found)          — p_venue_id is well-formed but
--     references no existing venue_defaults row. Distinct from 02000
--     (input absent) so client diagnostics can distinguish "you didn't
--     pass a venue_id" from "the venue_id you passed doesn't exist."
--
-- Companion docs:
--   • docs/VENUE-ADMIN-UI-A1-BUILD-SPEC.md §6 — the binding spec.
--   • docs/VENUE-ADMIN-UI-DIRECTION.md (Plan B revision, commit c076f12)
--     — the workstream direction.
--   • db/003_admin_and_venue_settings.sql:44-78 — the venue_defaults
--     table definition + existing public-read + admin-write RLS.
--   • db/032_venue_abstraction_schema.sql:157-189 — the Phase-2
--     additive columns (camera_fov, motion jsonb, ambient jsonb).
--
-- Schema unchanged. No new tables, no new columns, no new indexes, no
-- new RLS policies. The existing "venue_defaults: admin write" RLS
-- policy (db/003:69-73, db/004:54-55 renamed to is_platform_admin)
-- remains in place as defense-in-depth for any direct table writes;
-- this RPC's own is_platform_admin check is the authoritative gate
-- for the admin-UI write path.
--
-- Grant surface: two REVOKEs + one GRANT to undo two layers of default
-- privileges. The default grants on new SECURITY DEFINER functions
-- under Supabase's public schema come from TWO independent mechanisms:
--
--   (1) PostgreSQL's own CREATE FUNCTION default — auto-grants EXECUTE
--       to PUBLIC. In Supabase this default has typically been revoked
--       at project setup, so the REVOKE FROM PUBLIC below is a no-op
--       in the current production environment. Kept as defensive belt
--       so the migration is environment-portable (a replay against a
--       fresh non-Supabase PostgreSQL would have the PUBLIC grant).
--
--   (2) Supabase's ALTER DEFAULT PRIVILEGES on the public schema —
--       auto-grants EXECUTE on new functions DIRECTLY to anon,
--       authenticated, and service_role. These are direct role grants,
--       NOT inherited from PUBLIC, so REVOKE FROM PUBLIC does not
--       affect them. The load-bearing fix in the Supabase environment
--       is REVOKE EXECUTE FROM anon — without it, the auto-grant to
--       anon survives and verification query 3 fails.
--
-- service_role retains EXECUTE intentionally — it's the backend-key
-- role Supabase uses for server-side operations (Edge Functions, admin
-- scripts) and legitimately needs RPC access.
--
-- The function's own auth.uid() gate (step 1 below) still raises 42501
-- for any anon caller, so the grant-level revoke is defense-in-depth
-- rather than a data-exposure mitigation. But the migration's stated
-- intent (no anon EXECUTE) must match reality so verification query 3
-- passes.
-- ============================================================================


begin;


-- ─── 1. rpc_venue_default_update (NEW) ───────────────────────────────────
-- Partial-update of public.venue_defaults via a jsonb of column ->
-- new-value pairs. Uses the jsonb `?` key-exists operator (not just
-- `->>` casting) to distinguish "key not present" (preserve existing
-- column value) from "key present with NULL" (clear, where the column
-- allows null). NOT NULL columns reject NULL values explicitly. The
-- existing venue_defaults_set_updated_at trigger (db/003:75-78)
-- maintains updated_at; this function explicitly sets updated_by from
-- auth.uid().
drop function if exists public.rpc_venue_default_update(text, jsonb);

create function public.rpc_venue_default_update(
  p_venue_id text,
  p_partial  jsonb
)
returns public.venue_defaults
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id      uuid    := auth.uid();
  v_is_admin     boolean;
  v_row          public.venue_defaults;
  v_key          text;
  v_known_keys   text[]  := ARRAY['back_yaw', 'back_pitch', 'front_yaw',
                                   'front_pitch', 'camera_fov', 'motion', 'ambient'];
  v_notnull_keys text[]  := ARRAY['back_yaw', 'back_pitch', 'front_yaw', 'front_pitch'];
begin
  -- 1. Authentication
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- 2. Admin gate. Defense-in-depth — the table's RLS also enforces
  --    is_platform_admin write, but SECURITY DEFINER functions bypass
  --    RLS so the gate must be re-asserted here.
  select is_platform_admin into v_is_admin
    from public.profiles
   where id = v_user_id;
  if coalesce(v_is_admin, false) = false then
    raise exception 'not a platform admin' using errcode = '42501';
  end if;

  -- 3. Validate venue_id presence. 02000 = caller passed nothing
  --    usable; distinct from P0002 below (caller passed a real string
  --    that doesn't match any seeded row).
  if p_venue_id is null or length(p_venue_id) = 0 then
    raise exception 'venue_id required' using errcode = '02000';
  end if;

  -- 4. Validate p_partial keys
  if p_partial is not null then
    for v_key in select jsonb_object_keys(p_partial) loop
      if not (v_key = any(v_known_keys)) then
        raise exception 'unknown key in p_partial: %', v_key
          using errcode = '22023';
      end if;
      if v_key = any(v_notnull_keys) and (p_partial->>v_key) is null then
        raise exception 'cannot null NOT NULL column: %', v_key
          using errcode = '22004';
      end if;
    end loop;
  end if;

  -- 5. UPDATE only — no INSERT branch (see file header for rationale).
  --    Key-exists semantics via the `?` operator preserve absent columns
  --    and allow explicit NULL on nullable columns. NOT NULL columns are
  --    guarded by step 4 (cannot reach this UPDATE with NULL).
  update public.venue_defaults set
    back_yaw     = case when p_partial ? 'back_yaw'     then (p_partial->>'back_yaw')::numeric     else back_yaw end,
    back_pitch   = case when p_partial ? 'back_pitch'   then (p_partial->>'back_pitch')::numeric   else back_pitch end,
    front_yaw    = case when p_partial ? 'front_yaw'    then (p_partial->>'front_yaw')::numeric    else front_yaw end,
    front_pitch  = case when p_partial ? 'front_pitch'  then (p_partial->>'front_pitch')::numeric  else front_pitch end,
    camera_fov   = case when p_partial ? 'camera_fov'   then (p_partial->>'camera_fov')::numeric   else camera_fov end,
    motion       = case when p_partial ? 'motion'       then p_partial->'motion'                   else motion end,
    ambient      = case when p_partial ? 'ambient'      then p_partial->'ambient'                  else ambient end,
    updated_by   = v_user_id
  where venue_id = p_venue_id
  returning * into v_row;

  -- 6. Verify the row existed. The function never creates rows.
  --    P0002 = no_data_found (plpgsql-canonical), distinct from the
  --    02000 raised in step 3 (which signals a malformed call rather
  --    than a missing row).
  if not found then
    raise exception 'venue not found: %', p_venue_id using errcode = 'P0002';
  end if;

  -- 7. Return the updated row
  return v_row;
end;
$$;

-- Defensive REVOKE against PostgreSQL's own CREATE FUNCTION default
-- (auto-grant EXECUTE to PUBLIC). In Supabase, PUBLIC defaults are
-- already revoked at project setup, so this is a no-op there. Kept so
-- the migration is correct against a fresh non-Supabase PostgreSQL.
revoke execute on function public.rpc_venue_default_update(text, jsonb) from public;

-- Load-bearing REVOKE for the Supabase environment: removes the direct
-- grant to anon that Supabase's ALTER DEFAULT PRIVILEGES auto-applies
-- to every new function in the public schema. This grant is NOT
-- inherited from PUBLIC, so the REVOKE above does not affect it. The
-- default grants to authenticated and service_role are deliberately
-- NOT revoked — authenticated's grant is what makes the function
-- callable by the admin UI, and service_role's grant supports backend
-- callers (Edge Functions, admin tools).
revoke execute on function public.rpc_venue_default_update(text, jsonb) from anon;

-- The grant below is now technically redundant in Supabase (the
-- ALTER DEFAULT PRIVILEGES already grants authenticated) but is
-- retained for explicit intent + portability to non-Supabase
-- PostgreSQL, where authenticated is not auto-granted.
grant execute on function public.rpc_venue_default_update(text, jsonb) to authenticated;

comment on function public.rpc_venue_default_update(text, jsonb) is
  'UPDATE-only partial update of public.venue_defaults. is_platform_admin '
  'gate (raises 42501 if not authenticated or not admin). Accepts a jsonb '
  'of column -> new-value pairs (subset of: back_yaw, back_pitch, '
  'front_yaw, front_pitch, camera_fov, motion, ambient). Uses the jsonb '
  '? key-exists operator so absent keys preserve the existing column '
  'value. Raises 02000 if p_venue_id is null/empty (input absent); '
  '22023 on an unknown key in p_partial; 22004 if a NOT NULL column is '
  'set to null; P0002 if p_venue_id is well-formed but references no '
  'existing venue_defaults row (the function never creates rows; venue '
  'seeding is db/003:126-152). Per docs/VENUE-ADMIN-UI-A1-BUILD-SPEC.md §6.';


commit;


-- ============================================================================
-- Verification queries (run AFTER COMMIT in Supabase SQL Editor)
-- ============================================================================

-- (1) Function exists with the expected signature and SECURITY DEFINER.
--     Expect: 1 row; prosecdef=t; returns='public.venue_defaults';
--             args='p_venue_id text, p_partial jsonb'.
select proname,
       prosecdef,
       pg_get_function_result(oid)    as returns,
       pg_get_function_arguments(oid) as args
  from pg_proc
 where proname = 'rpc_venue_default_update'
   and pronamespace = 'public'::regnamespace;

-- (2) GRANT EXECUTE landed for authenticated.
--     Expect: authed=true.
select has_function_privilege(
         'authenticated',
         'public.rpc_venue_default_update(text, jsonb)'::regprocedure,
         'EXECUTE'
       ) as authed;

-- (3) anon does NOT have EXECUTE (explicit minimum surface).
--     Expect: anon_authed=false.
select has_function_privilege(
         'anon',
         'public.rpc_venue_default_update(text, jsonb)'::regprocedure,
         'EXECUTE'
       ) as anon_authed;

-- (4) Body contains no INSERT statement against public.venue_defaults.
--     Expect: has_insert=false. The function is UPDATE-only by construction.
select (pg_get_functiondef(oid) ilike '%insert%into%venue_defaults%') as has_insert
  from pg_proc
 where proname = 'rpc_venue_default_update'
   and pronamespace = 'public'::regnamespace;
