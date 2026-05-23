-- ============================================================================
-- Elsewhere — tv_devices.can_embed column
-- Migration: 030
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Adds a `can_embed` boolean column to public.tv_devices. The column
-- records whether the claimed TV device is embedding-capable per
-- ROOM-AUTHORITY-MODEL.md § "When the premium-control layer is active":
-- a device with both (a) a camera accessible to the TV browser, and
-- (b) the compositing pipeline to overlay participants into the venue.
-- This is the activation predicate for the premium-control layer.
--
-- ─── Scope: SCHEMA ONLY ──────────────────────────────────────────────────
-- This migration ships ONLY the column. It does NOT include:
--   • tv2.html self-report logic (camera detection + compositing-
--     pipeline detection at boot).
--   • Updates to rpc_claim_tv_device / rpc_link_tv_to_existing_household
--     to accept a self-reported value.
--   • Updates to the QR/claim URL bridge to carry the value from
--     tv2.html through claim.html to the claim RPCs.
--
-- That work is deferred — see DEFERRED.md "tv_devices.can_embed
-- self-report path" entry (the schema half is now DONE; the
-- self-report half remains active, blocked on the compositing
-- pipeline not yet existing as code).
--
-- ─── Default value rationale ────────────────────────────────────────────
-- NOT NULL DEFAULT false. Conservative: every existing tv_devices row
-- (claimed before this column existed) gets `false`. This is correct
-- for the activation-predicate use case — until a device has been
-- explicitly reported as embedding-capable by a future self-report
-- mechanism, treat it as non-embedding. Better to mis-classify a
-- camera-equipped device as non-embedding (no premium layer; the
-- room still works as a normal screen) than to mis-classify a plain
-- browser as embedding (premium layer turns on but embedding fails
-- at runtime when the camera doesn't exist).
--
-- All existing tv_devices rows in prod get `can_embed = false` on
-- apply. No retroactive flagging of any specific device — every
-- row, including the developer's own test devices, starts false.
-- Re-classification happens whenever the self-report path eventually
-- lands.
--
-- ─── Population status ──────────────────────────────────────────────────
-- This column is currently populated by NOTHING — there is no code
-- path that sets it to anything other than the DEFAULT. Adding a
-- writer is the deferred self-report work. The column is added now
-- so:
--   • C5 (the future ownership-seize RPC) can express its premium-
--     control-layer-active auth gate in SQL. With this column in
--     place, C5 is unblocked schema-side; its gate reads
--     `tv_devices.can_embed = true` for the screen the room is
--     bound to.
--   • Future readers (premium-filtered succession, room-state UX
--     surfaces) have a stable column to query against.
--
-- The functional consequence of shipping the schema with no writer:
-- every row reads `can_embed = false`, so the premium-control layer
-- is currently NEVER active in prod even if the C5 RPC ships. This
-- matches the conservative-default rationale above; the layer
-- becomes useful once the self-report writer lands.
--
-- ─── Idempotency / transaction wrapping ──────────────────────────────────
-- ALTER ... ADD COLUMN IF NOT EXISTS. begin;/commit; envelope. Safe
-- to re-run.
--
-- ─── Verification footer: see after COMMIT ──────────────────────────────
-- ============================================================================


begin;


alter table public.tv_devices
  add column if not exists can_embed boolean not null default false;


comment on column public.tv_devices.can_embed is
  'Whether this device is embedding-capable per ROOM-AUTHORITY-MODEL.md '
  '§ "When the premium-control layer is active" — i.e., has both a '
  'camera accessible to the TV browser AND the compositing pipeline to '
  'overlay participants into the venue. Activation predicate for the '
  'premium-control layer. Currently NO code path writes this column '
  '(the self-report mechanism is deferred — pending the compositing '
  'pipeline existing as code). Every row reads the DEFAULT false until '
  'the writer ships. First intended reader: the future ownership-seize '
  'RPC (DEFERRED entry "ownership-seize implementing RPC").';


commit;


-- ─── Verification ─────────────────────────────────────────────────────────
select 'migration 030 loaded' as status;

-- ============================================================================
-- POST-MIGRATION VERIFICATION
-- Run against prod via Supabase SQL Editor after applying.
--
-- 1. The column exists with the right type, nullability, and default.
--    SELECT column_name,
--           data_type,
--           is_nullable,
--           column_default
--      FROM information_schema.columns
--     WHERE table_schema = 'public'
--       AND table_name   = 'tv_devices'
--       AND column_name  = 'can_embed';
--    Expect: 1 row.
--      column_name    = 'can_embed'
--      data_type      = 'boolean'
--      is_nullable    = 'NO'
--      column_default = the boolean false. May render as `false` OR
--                       as `'false'::boolean` depending on Postgres
--                       version — either is correct; both mean the
--                       column defaults to false. The verbose render
--                       is not a failure.
--
-- 2. All existing tv_devices rows received the conservative default.
--    SELECT can_embed, count(*)
--      FROM public.tv_devices
--     GROUP BY can_embed
--     ORDER BY can_embed;
--    Expect: every row has can_embed = false (one row in the result
--    with can_embed = false and count = total rows; no row with
--    can_embed = true). If any can_embed = true row appears, the
--    schema migration was already partially applied OR someone has
--    written to the column outside the planned writer path — flag
--    immediately.
--
-- 3. The column COMMENT is recorded.
--    SELECT col_description('public.tv_devices'::regclass,
--                            (SELECT attnum
--                               FROM pg_attribute
--                              WHERE attrelid = 'public.tv_devices'::regclass
--                                AND attname  = 'can_embed'));
--    Expect: a non-null string mentioning ROOM-AUTHORITY-MODEL.md and
--    the premium-control layer activation predicate.
-- ============================================================================
