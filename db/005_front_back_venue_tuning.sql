-- ============================================================================
-- Elsewhere — Front/back venue view tuning
-- Migration: 005
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Splits venue view tuning into independent front (audience view) and
-- back (singer/panorama view) pairs. Previously venue_defaults stored a
-- single yaw+pitch pair that implicitly represented the audience-view
-- camera target; the singer-view tuning lived only in venues.json as
-- `startYaw` and had no DB override path.
--
-- This migration:
--   • venue_defaults — adds front_yaw + front_pitch + back_yaw + back_pitch,
--     migrates the existing yaw → front_yaw and pitch → front_pitch, then
--     drops the old single-pair columns. back_yaw / back_pitch start NULL;
--     admins tune them via the rebuilt "Set View Coordinates" dialog.
--   • karaoke_venue_settings — adds singer_{yaw,pitch}_override and
--     audience_{yaw,pitch}_override; drops the old yaw_override /
--     pitch_override columns. No data preservation — the pre-rework
--     feature was never used end-to-end.
--
-- RLS policies are untouched: they reference profiles.is_platform_admin,
-- not any of the renamed / dropped columns. Verified no policy expression
-- names these columns directly.
--
-- Wrapped in idempotent guards (add if not exists, drop if exists, DO
-- blocks with information_schema checks) so re-running the migration is
-- safe. The UPDATE that copies yaw → front_yaw uses COALESCE so it won't
-- clobber any front_yaw value an admin has already tuned between runs.
-- ============================================================================


-- ─── 1. venue_defaults: add the four new columns ──────────────────────────
alter table public.venue_defaults
  add column if not exists front_yaw   numeric,
  add column if not exists front_pitch numeric,
  add column if not exists back_yaw    numeric,
  add column if not exists back_pitch  numeric;


-- ─── 2. Migrate existing yaw/pitch into front_yaw/front_pitch ─────────────
-- Only runs when the old `yaw` column still exists (first-run case).
-- COALESCE means a second run won't overwrite a front_yaw value that
-- an admin has since edited.
do $$
begin
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and table_name   = 'venue_defaults'
       and column_name  = 'yaw'
  ) then
    update public.venue_defaults
       set front_yaw   = coalesce(front_yaw,   yaw),
           front_pitch = coalesce(front_pitch, pitch);
  end if;
end $$;


-- ─── 3. Drop the old single-pair columns from venue_defaults ──────────────
alter table public.venue_defaults
  drop column if exists yaw,
  drop column if exists pitch;


-- ─── 4. venue_defaults: column comments ───────────────────────────────────
comment on column public.venue_defaults.front_yaw is
  'Canonical yaw (degrees) for the AUDIENCE view — static camera '
  'orientation when viewers look toward the performer / stage. Migrated '
  'from the pre-005 venue_defaults.yaw column. Shared across every app '
  'that renders this venue.';

comment on column public.venue_defaults.front_pitch is
  'Canonical pitch (degrees) for the AUDIENCE view. Migrated from the '
  'pre-005 venue_defaults.pitch column.';

comment on column public.venue_defaults.back_yaw is
  'Canonical yaw (degrees) for the SINGER / panorama view — camera '
  'orientation when a performer looks out from the stage toward the '
  'audience. Starts NULL after db/005; admins tune via the Set View '
  'Coordinates dialog on karaoke/stage.html. Resolves to '
  'venues.json.startYaw if both this column and the karaoke override '
  'are NULL.';

comment on column public.venue_defaults.back_pitch is
  'Canonical pitch (degrees) for the SINGER / panorama view. Starts '
  'NULL; resolves to 0 if unset and the karaoke override is NULL.';


-- ─── 5. karaoke_venue_settings: add four new override columns ────────────
alter table public.karaoke_venue_settings
  add column if not exists singer_yaw_override     numeric,
  add column if not exists singer_pitch_override   numeric,
  add column if not exists audience_yaw_override   numeric,
  add column if not exists audience_pitch_override numeric;


-- ─── 6. Drop the old single-pair override columns ───────────────────────
alter table public.karaoke_venue_settings
  drop column if exists yaw_override,
  drop column if exists pitch_override;


-- ─── 7. karaoke_venue_settings: column comments ─────────────────────────
comment on column public.karaoke_venue_settings.singer_yaw_override is
  'Karaoke-specific override of the singer-view yaw. NULL means inherit '
  'from venue_defaults.back_yaw (which itself falls back to '
  'venues.json.startYaw if NULL).';

comment on column public.karaoke_venue_settings.singer_pitch_override is
  'Karaoke-specific override of the singer-view pitch. NULL means '
  'inherit from venue_defaults.back_pitch (fallback 0 if NULL).';

comment on column public.karaoke_venue_settings.audience_yaw_override is
  'Karaoke-specific override of the audience-view yaw. NULL means '
  'inherit from venue_defaults.front_yaw.';

comment on column public.karaoke_venue_settings.audience_pitch_override is
  'Karaoke-specific override of the audience-view pitch. NULL means '
  'inherit from venue_defaults.front_pitch.';


-- ─── Verification — run after the migration to confirm shape ────────────
select column_name, data_type, is_nullable
  from information_schema.columns
 where table_schema = 'public'
   and table_name in ('venue_defaults', 'karaoke_venue_settings')
 order by table_name, ordinal_position;
