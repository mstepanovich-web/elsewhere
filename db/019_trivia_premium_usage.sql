-- ============================================================================
-- Elsewhere — Trivia premium usage tracking
-- Migration: 019
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Per-user per-UTC-day usage counter for the Trivia Phase 2 premium path
-- (Anthropic-backed question generation via the generate-trivia Edge
-- Function). Rate limit is DAILY_LIMIT = 20 generations per user per UTC
-- day, enforced server-side in the Edge Function (not via DB constraint —
-- the function reads the count, decides, and increments on success).
--
-- Tables in this migration:
--   • trivia_premium_usage(user_id uuid, day date, count int)
--                                                  PK (user_id, day)
--
-- Key behaviors:
--
-- No reset mechanism needed. Keying on (user_id, day) means each new day
-- gets a fresh row; old rows naturally fall away from queries because the
-- function only ever queries `WHERE day = today_utc`. Old rows accumulate
-- but are bounded O(users × days). A future cleanup cron can DELETE rows
-- with day < current_date - 30 if storage becomes a concern. Not required
-- for correctness.
--
-- RLS policy: enabled with NO policies. All client-side reads/writes are
-- denied by RLS. The generate-trivia Edge Function uses the service-role
-- key (SUPABASE_SERVICE_ROLE_KEY) which bypasses RLS by design — that's
-- the intended access path. The browser cannot bypass the rate-limit by
-- writing to this table directly.
--
-- An optional read-policy (commented out below) would let users see their
-- own usage count for a future "you've used N/20 today" UI indicator.
-- Off by default; uncomment if/when that UI ships.
--
-- Cascade behavior: ON DELETE CASCADE from auth.users. If a user is deleted,
-- their usage rows are cleaned up automatically.
--
-- Idempotency: CREATE TABLE IF NOT EXISTS. Safe to re-run. The RLS ALTER
-- and policy block is also idempotent — ALTER TABLE ... ENABLE RLS on a
-- table that already has RLS enabled is a no-op.
-- ============================================================================


-- ─── 1. trivia_premium_usage table ──────────────────────────────────────────
create table if not exists public.trivia_premium_usage (
  user_id  uuid    not null references auth.users(id) on delete cascade,
  day      date    not null,
  count    integer not null default 0 check (count >= 0),
  primary key (user_id, day)
);

comment on table public.trivia_premium_usage is
  'Per-user per-UTC-day counter for Trivia Phase 2 premium generations. '
  'Read/write by the generate-trivia Edge Function via service-role key. '
  'RLS denies all client-side access; rate-limit (20/day) is enforced '
  'server-side in the Edge Function. Composite PK (user_id, day) means '
  'no reset mechanism is needed — each new day gets a fresh row.';


-- ─── 2. RLS — enabled, no policies ──────────────────────────────────────────
-- Service-role key (used by the Edge Function) bypasses RLS by design.
-- Browser clients are denied entirely; rate-limit cannot be bypassed.
alter table public.trivia_premium_usage enable row level security;

-- Optional future read policy for a "you've used N/20 today" UI indicator.
-- Off by default; uncomment if/when that UI ships.
--
-- create policy "users see their own usage" on public.trivia_premium_usage
--   for select using (auth.uid() = user_id);
