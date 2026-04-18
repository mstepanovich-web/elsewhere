-- ============================================================================
-- Elsewhere — Contacts: avatar support (Phase 1 Path B, Session 3)
-- Migration: 002
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Adds avatar_url to the contacts table. Actual image files live in the
-- Supabase Storage bucket "contact-avatars" (private, user-scoped folders)
-- which is provisioned via the Supabase dashboard — buckets and their RLS
-- policies are managed in the UI, not in migration SQL.
--
-- RLS on contacts already covers this column: row-level policies apply to
-- whole rows, so the existing "contacts: owner can …" policies from
-- migration 001 automatically gate reads/writes of avatar_url.
-- ============================================================================

alter table public.contacts
  add column if not exists avatar_url text;

comment on column public.contacts.avatar_url is
  'Supabase Storage URL (signed) for the contact''s photo, served from the '
  'contact-avatars bucket. NULL if no avatar uploaded. The underlying file '
  'lives at <account_id>/<contact_id>.jpg in the bucket.';


-- ─── Verification ───────────────────────────────────────────────────────────
select 'migration 002 loaded' as status;
