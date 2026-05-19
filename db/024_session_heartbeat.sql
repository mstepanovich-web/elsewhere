-- ============================================================================
-- Elsewhere — session_participants.last_seen_at + heartbeat RPC
-- Migration: 024
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Implements W9 from docs/ADMISSION-MODEL-V2.md § 10. Adds implicit-leave
-- detection so participants who close their tab, kill their browser, or
-- lose network are removed from session_participants automatically.
-- Without this, ghost participants linger forever in the table, breaking
-- player counts, turn rotation, and downstream UX.
--
-- Mechanism: client heartbeat + server-side prune coordinated in a
-- single RPC. The client wiring lands in the next commit
-- (games/player.html — bundled into the existing 20-second Agora
-- keepalive at line 1201).
--
-- WHAT THIS MIGRATION DOES:
--   1. Adds last_seen_at timestamptz NOT NULL DEFAULT now() to
--      session_participants. Existing rows get now() at migration time;
--      they immediately appear "live" and won't be falsely pruned until
--      the threshold elapses.
--   2. Adds a partial index (session_id, last_seen_at) WHERE left_at
--      IS NULL to serve the prune WHERE clause.
--   3. Adds rpc_session_heartbeat(p_session_id uuid) RETURNS integer.
--      SECURITY DEFINER. Two-step body:
--        (a) bumps caller's row's last_seen_at = now()
--        (b) prunes stale peers in same session (last_seen_at <
--            now() - interval '60 seconds') by setting left_at = now()
--      Returns count of pruned peer rows so the client can
--      conditionally publish participant_role_changed.
--
-- WHY RPC-ONLY, NO TRIGGER:
--
-- Considered a separate AFTER UPDATE OF last_seen_at trigger handling
-- the prune. Rejected for v1 because:
--
--   1. session_participants is RPC-mutated only in this codebase. The
--      trigger's main value-add (catching non-RPC bumps) does not apply.
--   2. Single debug surface — all logic in the RPC body. When a prune
--      doesn't fire as expected, no "did the trigger fire?" detective
--      work.
--   3. Race properties identical. Concurrent heartbeats double-pruning
--      the same stale peer is idempotent in both approaches via the
--      WHERE left_at IS NULL guard — an already-pruned row is excluded
--      from the second writer's UPDATE target set.
--
-- 60-SECOND THRESHOLD RATIONALE:
--
-- Client heartbeat interval is 20 seconds (next commit). 60 seconds
-- tolerates two missed beats plus 20s grace. This covers Mobile Safari
-- background eviction (~10-20s JS pause when the user app-switches),
-- which would otherwise cause false-positive pruning of a real user
-- who briefly checked another app.
--
-- The false-positive cost (real user gets pruned during a brief
-- app-switch, forcing re-join friction) is worse than the false-negative
-- cost (ghost lingers for up to 60s, recoverable via manager End Game
-- or natural game-over). Optimizing for the former.
--
-- RACE IDEMPOTENCE:
--
-- Multiple participants heartbeating concurrently may each prune the
-- same stale peer. The UPDATE statement guards on `WHERE left_at IS
-- NULL` — already-pruned rows are excluded, so the second writer's
-- ROW_COUNT for that row is 0. left_at = now() on an already-left row
-- never happens because of the guard.
--
-- The participant_role_changed broadcasts that clients fire after
-- prune count > 0 are idempotent on the receive side
-- (refreshSessionState re-reads the table; duplicate refreshes
-- converge to the same state). No dedup logic needed.
--
-- DEFERRED (filed for W10 docs/DEFERRED.md):
--
--   Capacitor iOS app-lifecycle hooks for heartbeat. WKWebView
--   suspends background JS after ~5-10s of app backgrounding, pausing
--   setInterval. On foreground, JS resumes — heartbeat fires again,
--   last_seen_at updates. During background, the participant is a
--   ghost for up to 60s. iOS-specific Capacitor
--   App.addListener('appStateChange') hooks for precise foreground/
--   background heartbeat firing would reduce this to ~0s. Out of W9
--   web-primary scope.
--
-- Idempotency: ALTER TABLE uses IF NOT EXISTS; CREATE INDEX uses IF
-- NOT EXISTS; CREATE OR REPLACE FUNCTION. Safe to re-run.
-- ============================================================================

begin;

-- ─── 1. Add last_seen_at column ────────────────────────────────────────────
-- NOT NULL with DEFAULT now() — existing rows get the migration time as
-- their last_seen_at, immediately appearing "live." Real heartbeats start
-- bumping it as soon as the client commit ships.
alter table public.session_participants
  add column if not exists last_seen_at timestamptz not null default now();

comment on column public.session_participants.last_seen_at is
  'W9: last heartbeat timestamp. Bumped by rpc_session_heartbeat every '
  '20s from the client. Rows with last_seen_at < now() - 60s and '
  'left_at IS NULL are pruned (left_at = now()) opportunistically '
  'during any participant''s heartbeat call.';


-- ─── 2. Partial index for the prune WHERE clause ───────────────────────────
-- Filters on (session_id, last_seen_at) for active rows only. The prune
-- query in rpc_session_heartbeat is the only consumer; partial index
-- keeps the size minimal (excludes already-left rows from the index).
create index if not exists session_participants_heartbeat_idx
  on public.session_participants (session_id, last_seen_at)
  where left_at is null;


-- ─── 3. rpc_session_heartbeat ──────────────────────────────────────────────
-- Called by the client every 20 seconds from games/player.html's existing
-- Agora keepalive setInterval. SECURITY DEFINER bypasses RLS write
-- restrictions on session_participants — every authenticated participant
-- should be able to bump their own row + prune stale peers in their
-- session. Explicit is_session_participant check guards against
-- cross-session abuse.
create or replace function public.rpc_session_heartbeat(p_session_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_pruned  int;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- Authorization: caller must be an active participant in the session.
  if not public.is_session_participant(p_session_id) then
    raise exception 'not a participant in session %', p_session_id
      using errcode = '42501';
  end if;

  -- 1. Bump caller's last_seen_at. No-op (0 rows affected) if the caller
  --    is already left — the next refreshSessionState on the client will
  --    detect their own absence and route them out.
  update public.session_participants
     set last_seen_at = now()
   where session_id = p_session_id
     and user_id    = v_user_id
     and left_at   is null;

  -- 2. Opportunistic prune of stale peers in the same session. Sets
  --    left_at = now() on rows whose last_seen_at is older than the
  --    60-second threshold AND whose left_at is NULL (guard against
  --    re-pruning a row already left). Self-skip via user_id <> caller
  --    (caller's own row was just bumped to now() above, so it can't
  --    match the < now() - 60s predicate anyway — but explicit guard
  --    documents intent + protects against future code edits).
  update public.session_participants
     set left_at = now()
   where session_id   = p_session_id
     and left_at      is null
     and last_seen_at < now() - interval '60 seconds'
     and user_id      <> v_user_id;
  get diagnostics v_pruned = row_count;

  return v_pruned;
end;
$$;

grant execute on function public.rpc_session_heartbeat(uuid) to authenticated;

comment on function public.rpc_session_heartbeat(uuid) is
  'W9: bumps caller''s session_participants.last_seen_at = now() and '
  'opportunistically prunes stale peers (left_at = now() where '
  'last_seen_at < now() - 60s AND left_at IS NULL AND user_id <> caller). '
  'Returns count of pruned peer rows. Client publishes '
  'participant_role_changed when count > 0 so peer clients '
  'refreshSessionState. Concurrent heartbeats double-pruning the same '
  'stale row is idempotent via the WHERE left_at IS NULL guard. See '
  'docs/ADMISSION-MODEL-V2.md § 10 W9.';

commit;

-- ─── Verification ─────────────────────────────────────────────────────────
select 'migration 024 loaded' as status;

-- ============================================================================
-- POST-MIGRATION VERIFICATION
--
-- After applying, run these checks against prod via Supabase SQL editor:
--
-- -- (1) Column added.
-- SELECT column_name, data_type, is_nullable, column_default
--   FROM information_schema.columns
--  WHERE table_schema = 'public'
--    AND table_name   = 'session_participants'
--    AND column_name  = 'last_seen_at';
-- --   Expect: 1 row, data_type=timestamp with time zone,
-- --           is_nullable=NO, column_default=now().
--
-- -- (2) Index created.
-- SELECT indexname, indexdef
--   FROM pg_indexes
--  WHERE schemaname = 'public'
--    AND tablename  = 'session_participants'
--    AND indexname  = 'session_participants_heartbeat_idx';
-- --   Expect: 1 row, indexdef contains "WHERE (left_at IS NULL)".
--
-- -- (3) Function exists with the right signature.
-- SELECT proname, prorettype::regtype, proargnames
--   FROM pg_proc
--  WHERE proname = 'rpc_session_heartbeat';
-- --   Expect: 1 row, prorettype=integer, proargnames={p_session_id}.
--
-- -- (4) Function granted to authenticated.
-- SELECT has_function_privilege('authenticated',
--   'rpc_session_heartbeat(uuid)', 'EXECUTE');
-- --   Expect: t.
--
-- -- (5) Smoke test against a real session. Replace <session_id> with a
-- --     valid uuid for a session where you have an active participant
-- --     row.
-- SELECT rpc_session_heartbeat('<session_id>'::uuid);
-- --   Expect: integer (0 if no stale peers, >0 if some).
--
-- SELECT last_seen_at FROM session_participants
--  WHERE session_id = '<session_id>'::uuid
--    AND user_id    = auth.uid()
--    AND left_at   IS NULL;
-- --   Expect: timestamp within the last few seconds (bumped by RPC).
--
-- -- (6) Confirm the prune semantics by manually back-dating a peer
-- --     row, calling the RPC, and observing the peer's left_at gets
-- --     set. Replace <peer_user_id> with an active peer in the same
-- --     session.
-- UPDATE session_participants
--    SET last_seen_at = now() - interval '120 seconds'
--  WHERE session_id = '<session_id>'::uuid
--    AND user_id    = '<peer_user_id>'::uuid;
-- SELECT rpc_session_heartbeat('<session_id>'::uuid);
-- --   Expect: returns 1.
-- SELECT user_id, last_seen_at, left_at FROM session_participants
--  WHERE session_id = '<session_id>'::uuid
--    AND user_id    = '<peer_user_id>'::uuid;
-- --   Expect: left_at within the last few seconds (just set by prune).
-- ============================================================================
