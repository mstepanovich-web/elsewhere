-- ============================================================================
-- Elsewhere — Phase 2 venue abstraction: schema migration
-- Migration: 032
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Implements `docs/PHASE-2-BUILD-SPEC.md` §4.5 — the database schema for
-- the venue abstraction. Built against PHASE-2-BUILD-SPEC.md §2-§6 (the
-- four-layer model, the unified anchor system, the costume library, and
-- the per-app override pattern). Revised after planning-chat review of
-- the initial draft (two revisions folded in: motion as jsonb, and FK
-- on-delete behavior RESTRICT rather than CASCADE — see Design
-- decisions 3 + 4 below).
--
-- ─── Scope: SCHEMA ONLY ──────────────────────────────────────────────────
-- This migration ships the data layer for Phase 2's dormant abstraction.
-- It does NOT include:
--   • Any client/shell code (`shell/venue-*.js` modules — separate task).
--   • Any SECURITY DEFINER RPCs for mutation (admin UI is a fast-follow
--     per PHASE-2-BUILD-SPEC.md §7; RPC layer follows the admin UI task).
--   • Any modification of `karaoke/stage.html`, `karaoke/singer.html`,
--     or `venues.json` (Phase 2 non-goals per §10: "no karaoke adoption",
--     "no app rendering layers").
--   • Any per-app override seeding (Phase 2 ships dormant; no live data).
--   • Costume bundle file moves (`karaoke/effects/*.deepar` stay where
--     they are; the cross-app `/costumes/` location decision is out of
--     scope for the schema). Records reference assets by `asset_ref`;
--     the resolver/renderer composes the URL.
--
-- All writes flow through SECURITY DEFINER RPCs per repo doctrine
-- (INFRA.md:166). Those RPCs are NOT written by this migration —
-- only the tables, columns, indexes, RLS, and triggers.
--
-- ─── OQ2 decision (per spec §4.5 + §9 OQ2): JSONB ─────────────────────────
-- The following columns are stored as `jsonb`:
--   • venue_anchors.payload            (per-type anchor payload)
--   • venue_anchors.link               (per-target deeplink)
--   • venue_defaults.motion            (per-type motion params)
--   • venue_defaults.ambient           (per-type ambient profile)
--   • karaoke_venue_settings.motion_override
--   • karaoke_venue_settings.ambient_override
--   • karaoke_venue_settings.anchor_patch  (delta set keyed by anchor id)
-- Rationale (per spec, extended per planning-chat review): each of
-- these carries a variable parameter set keyed by a type. Payload
-- varies by anchor type (§3.2). Motion params vary by motion type
-- (`static` needs nothing, `orbit` carries a numeric speed, a future
-- `elliptical` would carry radii + tilt). Ambient varies by ambient
-- shape. Link varies by navigation target. Anchor patch is a delta
-- set, not a value override, so it doesn't fit any single shape. All
-- are awkward to normalize and natural as JSON. Trade-off accepted:
-- opaque to SQL querying (no per-field indexing today). Future
-- migration can add expression indexes on specific jsonb paths if a
-- query pattern emerges.
--
-- ─── Design decision 1: extend `venue_defaults` (not companion) ──────────
-- The new venue-default attributes (default camera, motion, ambient)
-- ADD COLUMNS to the existing `venue_defaults` table rather than create
-- a companion. Reasoning:
--   1. db/003's own header (lines 19-22) documents the intended evolution:
--      "Post-refactor path: venue_defaults graduates into a unified
--      venues table with image/sound/animation columns" — the schema
--      designer's documented forward path is extension, not split.
--   2. The existing public-read + is_platform_admin-write RLS, the
--      set_updated_at trigger, and the venue_id PK all apply unchanged
--      to the new columns. A companion would duplicate this scaffolding.
--   3. The Phase-2 resolver fetches a single defaults row per venue;
--      a companion table forces a join the resolver doesn't otherwise
--      need.
-- HARD CONSTRAINT preserved: existing front_yaw / front_pitch /
-- back_yaw / back_pitch columns are UNTOUCHED. Additive only.
--
-- The default ANCHOR SET is not a column on venue_defaults — it is the
-- many-to-one FK relationship from venue_anchors back to venue_defaults.
-- A venue's "default anchor set" is the set of venue_anchors rows where
-- venue_id matches; the resolver materializes the set per request.
--
-- ─── Design decision 2: extend `karaoke_venue_settings` (not generalized) ─
-- Per-app overrides for the new attributes ADD COLUMNS to the existing
-- `karaoke_venue_settings` table rather than create a generalized
-- `app_venue_settings(app, venue_id, …)` cross-app table. Reasoning:
--   1. The existing `<app>_venue_settings` pattern is per-app-table
--      (shell/venue-settings.js:loadVenueSettings takes `app` and
--      queries `${app}_venue_settings` by composition). Phase 2 keeps
--      that pattern; future games / wellness add their own
--      `games_venue_settings` / `wellness_venue_settings` tables with
--      the same column shape via copy-this-pattern migrations.
--   2. A generalized table would require migrating the existing
--      karaoke_venue_settings rows + dropping the old table, which
--      violates this migration's additive-only constraint.
--   3. The existing trigger + RLS apply unchanged.
-- The `anchor_patch` column is jsonb (per OQ2) and intentionally has
-- no `_override` suffix — patches are a delta set, not a value override,
-- so the existing `_override` naming would mislead.
--
-- ─── Design decision 3: motion as a single jsonb column ──────────────────
-- The initial draft modeled motion as a text column (rotation_mode) plus
-- a numeric column (rotation_deg_per_sec). Planning-chat review collapsed
-- this into a SINGLE jsonb column `motion`, with parallel `motion_override`
-- on karaoke_venue_settings. Reasoning: motion types have differing
-- parameter sets — `static` needs no params, `orbit` carries a numeric
-- speed, a future `elliptical` would carry radii + tilt. A jsonb column
-- accommodates all of these without a schema change for each new type
-- (the same reasoning that settled OQ2 for the anchor payload). Speed
-- is always stored as a number inside the jsonb (never a word). No CHECK
-- constraint at the column level; the renderer registry interprets
-- unrecognized types gracefully. Recognized types today: `static`,
-- `orbit`; others extend without migration.
--
-- ─── Design decision 4: FK ON DELETE RESTRICT (not CASCADE) ──────────────
-- The three foreign keys from authored content tables back to
-- venue_defaults / costumes use ON DELETE RESTRICT, not CASCADE:
--   • venue_anchors.venue_id              → venue_defaults(venue_id)  RESTRICT
--   • venue_suggested_costumes.venue_id   → venue_defaults(venue_id)  RESTRICT
--   • venue_suggested_costumes.costume_id → costumes(id)              RESTRICT
-- Reasoning: anchors and the suggested-costume association are AUTHORED
-- CONTENT. Deleting a venue (or a costume) while anchors or suggestions
-- still reference it should be BLOCKED at the database level, forcing
-- the admin (or migration author) to deliberately clean up dependent
-- content first. RESTRICT is the safety backstop beneath the admin UI's
-- confirm-then-delete dialog. CASCADE would silently destroy authored
-- content on a venue delete — exactly the wrong default for editable
-- content. Today venues are an enumerated set with no live delete path;
-- this is the forward-compatibility safety choice. The `updated_by` FK
-- to auth.users(id) does not specify ON DELETE — Postgres default
-- (NO ACTION) is appropriate for audit references.
--
-- ─── New tables (3) ──────────────────────────────────────────────────────
--   • venue_anchors             — one row per default anchor record
--                                 (§3.1 base fields + jsonb payload).
--   • costumes                  — cross-app costume library (records;
--                                 asset files live elsewhere).
--   • venue_suggested_costumes  — association: venue → ordered list of
--                                 suggested costume ids (§6).
--
-- ─── Idempotency / transaction wrapping ──────────────────────────────────
-- ADD COLUMN IF NOT EXISTS, CREATE TABLE IF NOT EXISTS, CREATE INDEX IF
-- NOT EXISTS, DROP POLICY IF EXISTS + CREATE POLICY pattern (matches
-- db/003 / db/005), DROP TRIGGER IF EXISTS + CREATE TRIGGER pattern.
-- Single begin/commit envelope. Safe to re-run.
--
-- ─── Non-goals (per spec §10) ────────────────────────────────────────────
-- This migration does NOT:
--   • Modify any existing column (yaw/pitch + overrides untouched).
--   • Clear or move any data (additive only; no cutover).
--   • Touch any RPC, function, or view.
--   • Seed costumes or anchors (Phase 2 ships dormant; tables created
--     empty; admin UI / future migration populates).
--   • Create games_venue_settings / wellness_venue_settings (deferred
--     to their respective phases per UAP §5).
--
-- ─── Verification footer: see after COMMIT ──────────────────────────────
-- ============================================================================


begin;


-- ─── 1. venue_defaults: add Phase-2 default-attribute columns ─────────────
-- Naming: existing columns (front_yaw, back_pitch, …) name the VIEW
-- dimension; the table name implies "default." The new columns name the
-- ATTRIBUTE itself, without _default suffix, because none of them carry
-- a view dimension. The implicit "default" is the table's identity.
alter table public.venue_defaults
  add column if not exists camera_fov  numeric,
  add column if not exists motion      jsonb,
  add column if not exists ambient     jsonb;

comment on column public.venue_defaults.camera_fov is
  'Default camera field-of-view in degrees for this venue. NULL means '
  'the renderer uses its own default (karaoke today: 80°). Per-app '
  'overrides via <app>_venue_settings.camera_fov_override. Resolver '
  'chain matches the existing 4-level pattern: per-app override → DB '
  'default → venues.json fallback → renderer hardcoded default.';

comment on column public.venue_defaults.motion is
  'Default camera motion for this venue, as jsonb. Shape: '
  '{"type": "<motion-type>", ...type-specific params}. Stored as jsonb '
  '(per OQ2 rationale extended to motion) because parameter sets vary '
  'across motion types — ''static'' needs no params; ''orbit'' carries '
  'a numeric speed; a future ''elliptical'' would carry radii + tilt. '
  'Recognized types today: ''static'', ''orbit''; others extend without '
  'schema change. Speed is always a number (never a word). No CHECK '
  'constraint at the column level — the renderer registry interprets '
  'unrecognized types gracefully. NULL means ''static''.';

comment on column public.venue_defaults.ambient is
  'Default ambient profile for this venue as jsonb (per OQ2). Shape '
  'intentionally unconstrained at the schema level — interpreted by '
  'the renderer. Typical shape today: {"audio": {"type": "mp3", '
  '"sound_id": "stadium"}}. NULL means no ambient configured.';


-- ─── 2. karaoke_venue_settings: add Phase-2 override columns ──────────────
-- Mirrors §1's additions in the per-app override layer. NULL = inherit
-- from venue_defaults, matching the existing _override semantic.
alter table public.karaoke_venue_settings
  add column if not exists camera_fov_override  numeric,
  add column if not exists motion_override      jsonb,
  add column if not exists ambient_override     jsonb,
  add column if not exists anchor_patch         jsonb;

comment on column public.karaoke_venue_settings.camera_fov_override is
  'Karaoke-specific override of venue_defaults.camera_fov. NULL means '
  'inherit the default. Resolved by shell/venue-settings.js''s '
  'generalized resolver (see PHASE-2-BUILD-SPEC.md §5).';

comment on column public.karaoke_venue_settings.motion_override is
  'Karaoke-specific override of venue_defaults.motion. Same jsonb '
  'shape as venue_defaults.motion. NULL means inherit. Wholesale '
  'replacement (scalar override semantic) — not a patch.';

comment on column public.karaoke_venue_settings.ambient_override is
  'Karaoke-specific override of venue_defaults.ambient. NULL means '
  'inherit. Same jsonb shape as venue_defaults.ambient.';

comment on column public.karaoke_venue_settings.anchor_patch is
  'Karaoke-specific anchor-set patch (jsonb). NOT an override of the '
  'default anchor set — a DELTA APPLIED to it. Shape per '
  'PHASE-2-BUILD-SPEC.md §4.4: { "add": [<anchor records>], '
  '"suppress": ["<anchor_id>", ...], "modify": { "<anchor_id>": '
  '{<field overrides>} } }. The resolver computes effective set = '
  'venue default anchor set + this patch. NULL means no patch (use '
  'default set as-is). No _override suffix because patch semantics '
  'differ from scalar overrides — patches preserve drift-resistance '
  'by inheriting unspecified default anchors.';


-- ─── 3. venue_anchors: new table ──────────────────────────────────────────
-- One row per default anchor (§3.1 base fields). The default anchor set
-- for a venue is the set of rows where venue_id matches — no separate
-- "anchor set" identity is needed.
create table if not exists public.venue_anchors (
  id          text         primary key,
  venue_id    text         not null
                           references public.venue_defaults(venue_id) on delete restrict,
  type        text         not null,
  yaw_deg     numeric,
  pitch_deg   numeric,
  label       text         not null default '',
  start_sec   numeric,
  end_sec     numeric,
  link        jsonb,
  payload     jsonb        not null default '{}'::jsonb,
  is_broken   boolean      not null default false,
  created_at  timestamptz  not null default now(),
  updated_at  timestamptz  not null default now(),
  updated_by  uuid         references auth.users(id),

  -- §3.2 anchor type vocabulary. CHECK constraint (not ENUM type) per
  -- repo convention (db/008 uses CHECK for participation_role values)
  -- — easier to extend in future migrations via DROP+CREATE CONSTRAINT
  -- than ALTER TYPE ADD VALUE. Adding a new anchor type per spec §3.2
  -- ("The set is extensible") means: extend this CHECK + register a
  -- renderer for the new type.
  constraint venue_anchors_type_check
    check (type in (
      'callout', 'pin', 'spotlight', 'particle',
      'audio', 'video', 'link-hotspot'
    )),

  -- §3.1 screen-space rule: an anchor either has both yaw_deg and
  -- pitch_deg (sphere-pinned) or neither (screen-space overlay).
  -- Enforces the rule at the schema level so a half-positioned anchor
  -- can't enter the table.
  constraint venue_anchors_position_consistency
    check ((yaw_deg is null) = (pitch_deg is null))
);

comment on table public.venue_anchors is
  'Default anchor records for each venue. An anchor is a typed element '
  '(§3.2: callout / pin / spotlight / particle / audio / video / '
  'link-hotspot) pinned to a yaw/pitch position on the 360° sphere, '
  'optionally time-windowed, optionally a navigable hotspot. Both '
  'yaw_deg and pitch_deg NULL means a screen-space overlay (not '
  'sphere-pinned) per §3.1. Per-app patches (karaoke_venue_settings.'
  'anchor_patch and future <app>_venue_settings.anchor_patch) modify '
  'the effective set per app without mutating these default rows.';

comment on column public.venue_anchors.id is
  'Stable unique anchor id (TTS convention: anc_xxxxxx). Stability '
  'required — the per-app anchor_patch references anchors by this id '
  'for suppress/modify operations (§4.4 drift-avoidance).';

comment on column public.venue_anchors.payload is
  'Type-specific anchor payload as jsonb (per OQ2). Shape varies by '
  'type (§3.2): spotlight payload differs from audio payload differs '
  'from callout payload. The schema does not enforce per-type shape; '
  'the renderer registry (PHASE-2-BUILD-SPEC.md §5.4) interprets.';

comment on column public.venue_anchors.is_broken is
  'Validity flag (§3.2, derived from TTS _broken). When true, the '
  'anchor''s referenced asset is missing or invalid; renderers should '
  'skip the anchor rather than throw. Lets a venue with one missing '
  'audio file still render its other anchors gracefully.';

comment on column public.venue_anchors.link is
  'Optional jsonb deeplink (§3.3). Non-null = navigable hotspot. Shape '
  'depends on the navigation target: {"venue_id": "X"} for venue→venue '
  'navigation; {"scene_id": "Y"} or similar reserved for sequenced '
  'apps. NULL = not a hotspot. Spec §3.3: this is what makes the venue '
  'graph a graph rather than a flat list.';


-- Indexes. The resolver always fetches by venue_id (every venue load
-- queries "all anchors for venue X"). The composite (venue_id, type)
-- index supports future "all spotlight anchors for venue X" queries
-- which a per-type renderer pass might want.
create index if not exists venue_anchors_venue_idx
  on public.venue_anchors(venue_id);

create index if not exists venue_anchors_venue_type_idx
  on public.venue_anchors(venue_id, type);


-- RLS: public read (matches venue_defaults pattern — clients need to
-- resolve anchors at render time without admin auth), admin write
-- gated on profiles.is_platform_admin (matches the existing pattern
-- for venue tables per db/003 + db/004).
alter table public.venue_anchors enable row level security;

drop policy if exists "venue_anchors: public read" on public.venue_anchors;
create policy "venue_anchors: public read"
  on public.venue_anchors
  for select
  using (true);

drop policy if exists "venue_anchors: admin write" on public.venue_anchors;
create policy "venue_anchors: admin write"
  on public.venue_anchors
  for all
  using (exists (
    select 1 from public.profiles
     where id = auth.uid() and is_platform_admin = true
  ))
  with check (exists (
    select 1 from public.profiles
     where id = auth.uid() and is_platform_admin = true
  ));


-- updated_at trigger — reuses public.set_updated_at() defined pre-db/003
-- and used by venue_defaults / karaoke_venue_settings triggers.
drop trigger if exists venue_anchors_set_updated_at on public.venue_anchors;
create trigger venue_anchors_set_updated_at
  before update on public.venue_anchors
  for each row execute function public.set_updated_at();


-- ─── 4. costumes: cross-app costume library ───────────────────────────────
-- The library of every authorable costume across the platform. Costume
-- bundles physically live at karaoke/effects/*.deepar today and remain
-- there in Phase 2 (the "where do costume assets live" question is
-- decoupled from the schema — see PHASE-2-BUILD-SPEC.md §6 + OQ3).
-- Records reference assets by asset_ref; the resolver/renderer composes
-- the URL via a base-URL constant in the consuming surface.
create table if not exists public.costumes (
  id          text         primary key,
  name        text         not null,
  category    text,
  slot        text,
  asset_ref   text         not null,
  is_broken   boolean      not null default false,
  created_at  timestamptz  not null default now(),
  updated_at  timestamptz  not null default now(),
  updated_by  uuid         references auth.users(id)
);

comment on table public.costumes is
  'Cross-app costume library (PHASE-2-BUILD-SPEC.md §6). One row per '
  'authorable costume. Bundles live at karaoke/effects/ today; '
  'asset_ref stores the filename and the renderer composes the URL. '
  'Phase 2 ships this table EMPTY (no seed) — populated by admin UI '
  '(fast-follow) or future per-app migrations. Costume APPLICATION '
  '(compositing onto users) is each app''s rendering-layer concern, '
  'is premium-gated, and is NOT built in Phase 2.';

comment on column public.costumes.id is
  'Stable costume id. Convention follows the existing inline '
  'DEEPAR_EFFECTS pattern in karaoke/singer.html and karaoke/stage.html '
  '(e.g. ''dar-stallone'', ''dar-flower-face''). Stability required — '
  'venue_suggested_costumes references by id.';

comment on column public.costumes.slot is
  'Where on the user the costume composites. Vocabulary intentionally '
  'unconstrained at the schema level — typical values per DEEPAR_EFFECTS: '
  '''face'', ''hat'', ''bg''. CHECK constraint deferred until the slot '
  'vocabulary settles cross-app.';

comment on column public.costumes.asset_ref is
  'Asset filename (e.g. ''Stallone.deepar''). The renderer composes the '
  'full URL — today the karaoke convention is ELSEWHERE_EFFECTS_BASE '
  '+ asset_ref where the base is the GitHub Pages effects path. A '
  'future cross-app costume root would change the base only, not '
  'these records.';

comment on column public.costumes.is_broken is
  'Validity flag. When true, the asset is missing or invalid; '
  'consumers skip the costume gracefully.';


alter table public.costumes enable row level security;

drop policy if exists "costumes: public read" on public.costumes;
create policy "costumes: public read"
  on public.costumes
  for select
  using (true);

drop policy if exists "costumes: admin write" on public.costumes;
create policy "costumes: admin write"
  on public.costumes
  for all
  using (exists (
    select 1 from public.profiles
     where id = auth.uid() and is_platform_admin = true
  ))
  with check (exists (
    select 1 from public.profiles
     where id = auth.uid() and is_platform_admin = true
  ));


drop trigger if exists costumes_set_updated_at on public.costumes;
create trigger costumes_set_updated_at
  before update on public.costumes
  for each row execute function public.set_updated_at();


-- ─── 5. venue_suggested_costumes: association table ───────────────────────
-- Per-venue ordered list of suggested costume ids. The suggested list is
-- a venue attribute (defaulted, app-overridable per §6) — but the spec
-- treats the BASE association as a defaulted attribute on the venue. An
-- app's override of the suggested list lives in <app>_venue_settings as
-- a future jsonb column (deferred — only karaoke needs costume rendering
-- today, and karaoke uses the default suggested list).
--
-- "Never limited to the suggested list" rule (§6): the user may always
-- pick from the full `costumes` library. This table is curation, not a
-- gate.
create table if not exists public.venue_suggested_costumes (
  venue_id    text         not null
                           references public.venue_defaults(venue_id) on delete restrict,
  costume_id  text         not null
                           references public.costumes(id) on delete restrict,
  position    integer      not null default 0,
  primary key (venue_id, costume_id)
);

comment on table public.venue_suggested_costumes is
  'Per-venue curated list of suggested costumes (PHASE-2-BUILD-SPEC.md '
  '§6). Association table between venue_defaults and costumes. '
  '`position` orders the list within a venue. The list is curation — '
  'the user may always pick from the full `costumes` library; this '
  'table does NOT gate costume availability.';

comment on column public.venue_suggested_costumes.position is
  'Ordering within the venue''s suggested list. Lower position appears '
  'first in the picker. Ties broken by costume_id (deterministic). '
  'Default 0 means unordered. No uniqueness constraint on '
  '(venue_id, position) — ties are allowed; admin re-ordering does '
  'not need to push positions around to avoid collision.';


-- Composite index supports "all suggested costumes for venue X ordered
-- by position" — the canonical resolver query pattern.
create index if not exists venue_suggested_costumes_venue_position_idx
  on public.venue_suggested_costumes(venue_id, position);


alter table public.venue_suggested_costumes enable row level security;

drop policy if exists "venue_suggested_costumes: public read"
  on public.venue_suggested_costumes;
create policy "venue_suggested_costumes: public read"
  on public.venue_suggested_costumes
  for select
  using (true);

drop policy if exists "venue_suggested_costumes: admin write"
  on public.venue_suggested_costumes;
create policy "venue_suggested_costumes: admin write"
  on public.venue_suggested_costumes
  for all
  using (exists (
    select 1 from public.profiles
     where id = auth.uid() and is_platform_admin = true
  ))
  with check (exists (
    select 1 from public.profiles
     where id = auth.uid() and is_platform_admin = true
  ));

-- No set_updated_at trigger on venue_suggested_costumes — it is a pure
-- association with no mutable lifecycle fields beyond `position`. If an
-- admin re-orders, the existing row's position is updated in-place; the
-- audit trail (who/when changed it) is not currently tracked. If that
-- becomes a real need, a future migration adds updated_at/by + trigger.


commit;


-- ─── Verification ─────────────────────────────────────────────────────────
select 'migration 032 loaded' as status;

-- ============================================================================
-- POST-MIGRATION VERIFICATION
--
-- After applying via Supabase SQL Editor, run these queries to confirm
-- the schema landed as intended.
--
-- ─── (1) venue_defaults: new columns present, existing columns intact ────
-- SELECT column_name, data_type, is_nullable
--   FROM information_schema.columns
--  WHERE table_schema = 'public'
--    AND table_name   = 'venue_defaults'
--  ORDER BY ordinal_position;
-- --   Expect: original columns (venue_id text, front_yaw numeric,
-- --   front_pitch numeric, back_yaw numeric, back_pitch numeric,
-- --   updated_at, updated_by) STILL PRESENT and unchanged, PLUS the
-- --   three new columns (camera_fov numeric YES, motion jsonb YES,
-- --   ambient jsonb YES). All new columns nullable.
--
-- ─── (2) karaoke_venue_settings: new columns present ─────────────────────
-- SELECT column_name, data_type, is_nullable
--   FROM information_schema.columns
--  WHERE table_schema = 'public'
--    AND table_name   = 'karaoke_venue_settings'
--  ORDER BY ordinal_position;
-- --   Expect: original columns (venue_id text, singer_yaw_override,
-- --   singer_pitch_override, audience_yaw_override,
-- --   audience_pitch_override, updated_at, updated_by) STILL PRESENT,
-- --   PLUS the four new (camera_fov_override numeric YES,
-- --   motion_override jsonb YES, ambient_override jsonb YES,
-- --   anchor_patch jsonb YES).
--
-- ─── (3) venue_anchors: table exists with correct shape ──────────────────
-- SELECT column_name, data_type, is_nullable, column_default
--   FROM information_schema.columns
--  WHERE table_schema = 'public'
--    AND table_name   = 'venue_anchors'
--  ORDER BY ordinal_position;
-- --   Expect: id text NO, venue_id text NO, type text NO, yaw_deg
-- --   numeric YES, pitch_deg numeric YES, label text NO default ''::text,
-- --   start_sec numeric YES, end_sec numeric YES, link jsonb YES,
-- --   payload jsonb NO default '{}'::jsonb, is_broken boolean NO
-- --   default false, created_at + updated_at timestamptz NO default
-- --   now(), updated_by uuid YES.
--
-- ─── (4) venue_anchors: check constraints active ─────────────────────────
-- SELECT conname, pg_get_constraintdef(oid)
--   FROM pg_constraint
--  WHERE conrelid = 'public.venue_anchors'::regclass
--    AND contype  = 'c'
--  ORDER BY conname;
-- --   Expect: 2 rows.
-- --   venue_anchors_position_consistency: CHECK (((yaw_deg IS NULL) =
-- --     (pitch_deg IS NULL)))
-- --   venue_anchors_type_check: CHECK ((type = ANY (ARRAY['callout',
-- --     'pin', 'spotlight', 'particle', 'audio', 'video',
-- --     'link-hotspot']::text[])))
--
-- ─── (5) venue_anchors: indexes + FK to venue_defaults ───────────────────
-- SELECT indexname, indexdef
--   FROM pg_indexes
--  WHERE schemaname = 'public' AND tablename = 'venue_anchors'
--  ORDER BY indexname;
-- --   Expect: 3 rows — venue_anchors_pkey (id), venue_anchors_venue_idx
-- --   (venue_id), venue_anchors_venue_type_idx (venue_id, type).
--
-- SELECT conname, pg_get_constraintdef(oid)
--   FROM pg_constraint
--  WHERE conrelid = 'public.venue_anchors'::regclass
--    AND contype  = 'f';
-- --   Expect: 2 FKs — one to venue_defaults(venue_id) ON DELETE RESTRICT
-- --   for venue_id; one to auth.users(id) for updated_by (no explicit
-- --   ON DELETE — Postgres default NO ACTION applies).
--
-- ─── (6) venue_anchors: RLS enabled + policies present ───────────────────
-- SELECT relname, relrowsecurity
--   FROM pg_class
--  WHERE relname = 'venue_anchors' AND relnamespace = 'public'::regnamespace;
-- --   Expect: relrowsecurity = t.
--
-- SELECT polname, polcmd, pg_get_expr(polqual, polrelid) AS using_expr,
--        pg_get_expr(polwithcheck, polrelid) AS check_expr
--   FROM pg_policy
--  WHERE polrelid = 'public.venue_anchors'::regclass
--  ORDER BY polname;
-- --   Expect: 2 rows — "venue_anchors: public read" with polcmd='r',
-- --   using_expr='true'. "venue_anchors: admin write" with polcmd='*',
-- --   using_expr referencing profiles.is_platform_admin = true.
--
-- ─── (7) venue_anchors: trigger present ──────────────────────────────────
-- SELECT tgname, tgenabled, pg_get_triggerdef(oid)
--   FROM pg_trigger
--  WHERE tgrelid = 'public.venue_anchors'::regclass
--    AND tgname  = 'venue_anchors_set_updated_at';
-- --   Expect: 1 row, tgenabled='O', def contains BEFORE UPDATE + EXECUTE
-- --   FUNCTION public.set_updated_at().
--
-- ─── (8) costumes: table + RLS + trigger ─────────────────────────────────
-- SELECT column_name, data_type, is_nullable
--   FROM information_schema.columns
--  WHERE table_schema = 'public' AND table_name = 'costumes'
--  ORDER BY ordinal_position;
-- --   Expect: id text NO, name text NO, category text YES, slot text
-- --   YES, asset_ref text NO, is_broken boolean NO default false,
-- --   created_at + updated_at timestamptz NO, updated_by uuid YES.
--
-- SELECT relrowsecurity FROM pg_class
--  WHERE relname = 'costumes' AND relnamespace = 'public'::regnamespace;
-- --   Expect: t.
--
-- SELECT polname FROM pg_policy
--  WHERE polrelid = 'public.costumes'::regclass ORDER BY polname;
-- --   Expect: 2 rows ("costumes: admin write", "costumes: public read").
--
-- SELECT tgname FROM pg_trigger
--  WHERE tgrelid = 'public.costumes'::regclass
--    AND tgname = 'costumes_set_updated_at';
-- --   Expect: 1 row.
--
-- ─── (9) venue_suggested_costumes: table + FKs + RLS + index ─────────────
-- SELECT column_name, data_type, is_nullable
--   FROM information_schema.columns
--  WHERE table_schema = 'public' AND table_name = 'venue_suggested_costumes'
--  ORDER BY ordinal_position;
-- --   Expect: venue_id text NO, costume_id text NO, position integer
-- --   NO default 0.
--
-- SELECT conname, pg_get_constraintdef(oid)
--   FROM pg_constraint
--  WHERE conrelid = 'public.venue_suggested_costumes'::regclass
--    AND contype IN ('p','f')
--  ORDER BY contype, conname;
-- --   Expect: 1 PK (venue_id, costume_id) + 2 FKs — venue_id →
-- --   venue_defaults(venue_id) ON DELETE RESTRICT, costume_id →
-- --   costumes(id) ON DELETE RESTRICT.
--
-- SELECT indexname FROM pg_indexes
--  WHERE schemaname = 'public' AND tablename = 'venue_suggested_costumes'
--  ORDER BY indexname;
-- --   Expect: 2 rows — venue_suggested_costumes_pkey (composite PK),
-- --   venue_suggested_costumes_venue_position_idx (venue_id, position).
--
-- SELECT relrowsecurity FROM pg_class
--  WHERE relname = 'venue_suggested_costumes'
--    AND relnamespace = 'public'::regnamespace;
-- --   Expect: t.
--
-- SELECT polname FROM pg_policy
--  WHERE polrelid = 'public.venue_suggested_costumes'::regclass
--  ORDER BY polname;
-- --   Expect: 2 rows ("venue_suggested_costumes: admin write",
-- --   "venue_suggested_costumes: public read").
--
-- ─── (10) Empty-state confirmation (Phase 2 ships dormant) ───────────────
-- SELECT count(*) AS anchor_count FROM public.venue_anchors;
-- --   Expect: 0.
--
-- SELECT count(*) AS costume_count FROM public.costumes;
-- --   Expect: 0.
--
-- SELECT count(*) AS suggested_count FROM public.venue_suggested_costumes;
-- --   Expect: 0.
--
-- ─── (11) Existing venue_defaults rows untouched + new columns NULL ──────
-- SELECT count(*) AS total_venues,
--        count(*) FILTER (WHERE camera_fov IS NOT NULL) AS with_camera_fov,
--        count(*) FILTER (WHERE motion     IS NOT NULL) AS with_motion,
--        count(*) FILTER (WHERE ambient    IS NOT NULL) AS with_ambient
--   FROM public.venue_defaults;
-- --   Expect: total_venues = 26 (the count seeded by db/003), all
-- --   "with_*" counts = 0 (no defaults populated yet — admin UI / future
-- --   migration sets them).
--
-- ─── (12) Existing karaoke_venue_settings rows untouched ─────────────────
-- SELECT count(*) AS karaoke_settings_rows,
--        count(*) FILTER (WHERE singer_yaw_override IS NOT NULL)
--          AS singer_yaw_overrides_intact
--   FROM public.karaoke_venue_settings;
-- --   Expect: existing row count unchanged; existing override values
-- --   intact (additive migration did not touch).
-- ============================================================================
