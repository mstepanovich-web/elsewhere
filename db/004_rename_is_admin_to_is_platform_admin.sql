-- ============================================================================
-- Elsewhere — Rename profiles.is_admin → profiles.is_platform_admin
-- Migration: 004
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Corrective migration following db/003. The name "is_admin" is ambiguous
-- in a product with multiple admin contexts (platform operator, session
-- host/manager, group owner). Rename to "is_platform_admin" to make the
-- scope explicit: platform-level operator rights (tune venue defaults,
-- edit shared content), distinct from session-level manager role and
-- group-level ownership.
--
-- db/003 is left intact — it shipped the initial column + policies under
-- the old name; this migration is the corrective step.
--
-- Wrapped in conditional DO block so re-running the migration is safe.
-- ============================================================================


-- ─── 1. Drop the RLS policies that reference the old column name ───────────
-- Postgres would auto-resolve the rename, but dropping + recreating keeps
-- the policy expression readable in pg_policies and the migration log.
drop policy if exists "venue_defaults: admin write"         on public.venue_defaults;
drop policy if exists "karaoke_venue_settings: admin write" on public.karaoke_venue_settings;


-- ─── 2. Rename the column (idempotent via DO block) ────────────────────────
do $$
begin
  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name   = 'profiles'
       and column_name  = 'is_admin'
  ) then
    alter table public.profiles rename column is_admin to is_platform_admin;
  end if;
end $$;

comment on column public.profiles.is_platform_admin is
  'Platform operator flag. When true, this user can write to '
  'venue_defaults and per-app venue settings tables, and access other '
  'platform-scoped admin tooling. Distinct from session-level manager '
  'role (games/karaoke "manager" is per-session) and group-level '
  'ownership (groups.owner_id). Defaults false; flip manually in the '
  'SQL editor or via a maintainer-run migration.';


-- ─── 3. Recreate the RLS policies referencing the new column name ─────────
create policy "venue_defaults: admin write"
  on public.venue_defaults
  for all
  using (exists (select 1 from public.profiles where id = auth.uid() and is_platform_admin = true))
  with check (exists (select 1 from public.profiles where id = auth.uid() and is_platform_admin = true));

create policy "karaoke_venue_settings: admin write"
  on public.karaoke_venue_settings
  for all
  using (exists (select 1 from public.profiles where id = auth.uid() and is_platform_admin = true))
  with check (exists (select 1 from public.profiles where id = auth.uid() and is_platform_admin = true));


-- ─── Verification ──────────────────────────────────────────────────────────
select 'migration 004 loaded' as status;
