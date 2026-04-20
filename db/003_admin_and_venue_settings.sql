-- ============================================================================
-- Elsewhere — Admin flag + venue view-coordinate tuning tables
-- Migration: 003
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Contents:
--   • profiles.is_admin           — admin flag on the profile row
--   • venue_defaults              — global defaults per venue (yaw, pitch)
--   • karaoke_venue_settings      — karaoke-specific overrides
--                                   (NULL on a column = inherit default)
--   • seed data pre-populated from venues.json at migration write time
--
-- Two-level resolution model (see PHASE1-NOTES "Venue property override
-- pattern"): karaoke reads karaoke_venue_settings first; any NULL override
-- falls back to venue_defaults. Public read on both tables so non-admin
-- clients can resolve the right view. Write is admin-only, gated by
-- profiles.is_admin via RLS.
--
-- Post-refactor path: venue_defaults graduates into a unified venues table
-- with image/sound/animation columns; karaoke_venue_settings becomes one of
-- many per-app override tables (wellness_venue_settings, etc.), all
-- following the same NULL-means-inherit convention.
-- ============================================================================


-- ─── 1. profiles.is_admin ───────────────────────────────────────────────────
alter table public.profiles
  add column if not exists is_admin boolean not null default false;

comment on column public.profiles.is_admin is
  'When true, this user can write to venue_defaults and per-app venue '
  'settings tables. Gates admin UI like the karaoke "Set View Coordinates" '
  'dialog. Defaults false; flip via this migration or via direct update '
  'by a project maintainer.';

-- Seed Mike as admin. Subquery resolves to his auth.users.id so we don't
-- hardcode a UUID — works on any project where this email exists.
update public.profiles
   set is_admin = true
 where id = (select id from auth.users where email = 'm.stepanovich@gmail.com');


-- ─── 2. venue_defaults ──────────────────────────────────────────────────────
create table if not exists public.venue_defaults (
  venue_id    text        primary key,
  yaw         numeric     not null default 0,
  pitch       numeric     not null default 0,
  updated_at  timestamptz not null default now(),
  updated_by  uuid        references auth.users(id)
);

comment on table public.venue_defaults is
  'Canonical yaw/pitch per venue, shared across every product that renders '
  'the venue (karaoke, wellness, Room Mode, …). Seeded from venues.json at '
  'migration time; maintained thereafter via the admin "Set View '
  'Coordinates" dialog in karaoke/stage.html. Yaw and pitch correspond to '
  'the static camera orientation in audience view (staticYaw / staticPitch '
  'in venues.json).';

alter table public.venue_defaults enable row level security;

drop policy if exists "venue_defaults: public read" on public.venue_defaults;
create policy "venue_defaults: public read"
  on public.venue_defaults
  for select
  using (true);

drop policy if exists "venue_defaults: admin write" on public.venue_defaults;
create policy "venue_defaults: admin write"
  on public.venue_defaults
  for all
  using (exists (select 1 from public.profiles where id = auth.uid() and is_admin = true))
  with check (exists (select 1 from public.profiles where id = auth.uid() and is_admin = true));

drop trigger if exists venue_defaults_set_updated_at on public.venue_defaults;
create trigger venue_defaults_set_updated_at
  before update on public.venue_defaults
  for each row execute function public.set_updated_at();


-- ─── 3. karaoke_venue_settings ──────────────────────────────────────────────
-- Per-app override layer. NULL on either column means "inherit from
-- venue_defaults". Resolution logic lives client-side in the shared
-- shell/venue-settings.js helper (resolveVenueProperty). Adding future
-- override columns (sound_override, anim_override, etc.) extends the
-- override model without reshaping the schema.
create table if not exists public.karaoke_venue_settings (
  venue_id        text        primary key,
  yaw_override    numeric,
  pitch_override  numeric,
  updated_at      timestamptz not null default now(),
  updated_by      uuid        references auth.users(id)
);

comment on table public.karaoke_venue_settings is
  'Karaoke-specific yaw/pitch overrides. A NULL column means inherit the '
  'value from venue_defaults. A row with both columns NULL is equivalent '
  'to having no row at all (pure inheritance).';

alter table public.karaoke_venue_settings enable row level security;

drop policy if exists "karaoke_venue_settings: public read" on public.karaoke_venue_settings;
create policy "karaoke_venue_settings: public read"
  on public.karaoke_venue_settings
  for select
  using (true);

drop policy if exists "karaoke_venue_settings: admin write" on public.karaoke_venue_settings;
create policy "karaoke_venue_settings: admin write"
  on public.karaoke_venue_settings
  for all
  using (exists (select 1 from public.profiles where id = auth.uid() and is_admin = true))
  with check (exists (select 1 from public.profiles where id = auth.uid() and is_admin = true));

drop trigger if exists karaoke_venue_settings_set_updated_at on public.karaoke_venue_settings;
create trigger karaoke_venue_settings_set_updated_at
  before update on public.karaoke_venue_settings
  for each row execute function public.set_updated_at();


-- ─── 4. Seed venue_defaults from venues.json (at migration write time) ──────
-- Values mirror venues.json staticYaw / staticPitch. Seeding every venue
-- explicitly (not just the non-zero ones) so the admin dialog has a row to
-- UPDATE for every venue — saves handling INSERT-on-first-save in client
-- code. Upsert-style: does nothing if a row already exists for that id.
insert into public.venue_defaults (venue_id, yaw, pitch) values
  ('default',         0,    0),
  ('stadium',         151,  -17),
  ('festival',        109,  -6),
  ('hollywoodbowl',   0,    0),
  ('amphitheater',    0,    0),
  ('colosseum',       0,    0),
  ('drivein',         0,    0),
  ('disco',           23,   0),
  ('vegas',           -150, 2),
  ('rooftop',         0,    0),
  ('broadway',        0,    0),
  ('speakeasy',       201,  -1),
  ('honkytonk',       -71,  6),
  ('supperclub',      0,    0),
  ('cabaret',         0,    0),
  ('bourbonstreet',   0,    0),
  ('saloon',          0,    0),
  ('spacestation',    0,    0),
  ('enchantedforest', 0,    0),
  ('dragonlair',      0,    0),
  ('kids-candy',      0,    0),
  ('kids-dino',       0,    0),
  ('kids-dino2',      0,    0),
  ('kids-northpole',  0,    0),
  ('kids-princess',   0,    0),
  ('kids-winter',     0,    0)
on conflict (venue_id) do nothing;


-- ─── Verification ───────────────────────────────────────────────────────────
select 'migration 003 loaded' as status;
