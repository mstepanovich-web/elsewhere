# Elsewhere — Phase 1 Build Spec

Structural plan for db/025 and the Phase-1 room/session migration,
produced by the execution-scope investigation per UNIFIED-APP-PLAN.md §8.

**Status:** Adopted (build spec; pre-implementation). The db/025 migration
is to be written against this spec. Five of the six open questions (§H)
are still open or carry recommendations; OQ6 is resolved. This is a
structural plan, not migration code — migration code is the step after
the remaining open questions are addressed.

---

## A. Verified facts (baseline state for Phase 1)

| Claim | Status | Evidence |
|---|---|---|
| No `rooms` table exists | ✓ confirmed | `grep -rn "CREATE TABLE.*rooms" db/` returns nothing |
| No `room_id` column exists on `sessions` or `session_participants` | ✓ confirmed | Only matches in the planning text being introduced |
| `room_code` already exists on `sessions` (will move to `rooms`) | ✓ confirmed | `db/008:57` — `room_code text` (nullable) |
| `rpc_session_promote_self_from_queue` is dead in live code | ✓ confirmed | Only references are documentation/comments (`shell/realtime.js:47` doc comment, db/009-011 headers). Zero live callers in HTML/JS surfaces. Safe to drop. |
| `sessions.current_state` has zero writers | ✓ confirmed | Read-only scaffolding. 4 surfaces SELECT it (games/tv.html, games/player.html, karaoke/stage.html, karaoke/singer.html) but no `UPDATE sessions SET current_state` anywhere. Confirms the plan's "dormant scaffolding" claim. |
| Latest applied migration is db/024 (2026-05-19) | ✓ confirmed | `db/MIGRATIONS_APPLIED.md` shows all 24 ✅; db/025 is next |
| `rpc_session_leave` currently selects successor by `joined_at asc` | ✓ confirmed | `db/010:302` (host-preference tier) and `db/010:315` (non-audience fallback tier) both `ORDER BY joined_at asc LIMIT 1`. The two-tier preference today (host first, then non-audience) was the input for the now-adopted three-tier hierarchy in ROOM-AUTHORITY-MODEL.md. |
| `rpc_session_end` currently sweeps participants | ✓ confirmed | `db/009:344-348` — `update session_participants set left_at = now() where session_id = p_session_id and left_at is null` |
| db/015's `trg_fire_promotion_push` trigger function reads `NEW.session_id` | **MISSED by the original investigation; surfaced during db/025 drafting** | `db/015:60-64` — `fire_promotion_push()` builds the Edge Function payload as `jsonb_build_object('user_id', NEW.user_id, 'type', 'promotion', 'session_id', NEW.session_id)`. The original sweep did not classify trigger function bodies as a separate dependency category and so did not flag this. See the methodology note immediately below. db/025 will explicitly drop the trigger and its backing function (see §C step 4); recreation is tracked in §D. |

**Methodology note (post-hoc).** The original sweep audited RPC function bodies (catalogued in §D) and grepped SQL files for column-name references — it did NOT audit trigger function bodies as a separate category. plpgsql bodies aren't eagerly schema-validated: a function referencing a now-missing column compiles fine and fails only at first runtime call. The db/026-onward work should re-audit plpgsql trigger and function bodies if further column drops are planned.

---

## B. The final `rooms` table schema

Per UNIFIED-APP-PLAN §6 amendment + ROOM-AUTHORITY-MODEL + ROOM-SESSION-MODEL.

```sql
create table if not exists public.rooms (
  id                  uuid        primary key default gen_random_uuid(),
  room_code           text        not null,
  controller_user_id  uuid        not null references auth.users(id),
  owner_user_id       uuid        not null references auth.users(id),
  screen_ref          uuid        references public.tv_devices(id) on delete set null,
  created_at          timestamptz not null default now(),
  last_activity_at    timestamptz not null default now(),
  ended_at            timestamptz
);
```

**Field rationale:**

- `id` — surrogate PK (matches existing surrogate-PK pattern in sessions/profiles).
- `room_code` — moves up from `sessions`. Generated once at room creation; stable for the room's life. **NOT NULL** per ROOM-SESSION-MODEL "Generated once when the room is created and stable." A uniqueness invariant on active rooms is recommended — see OQ1.
- `controller_user_id` **NOT NULL** — current room controller (operational authority). Mutates on succession / explicit transfer / reclaim. The new home of what `sessions.manager_user_id` denormalized.
- `owner_user_id` **NOT NULL** — original convener (personal authority). **Never mutates** by any reclaim or succession RPC. Phase-1 RPCs MUST treat this column as read-only after room creation.
- `screen_ref` **NULLABLE** with `ON DELETE SET NULL` — the screen the room is bound to. NULL for a scanned/unclaimed screen or no-screen room. Per ROOM-SESSION-MODEL: "may point to a claimed household TV, or be null for a scanned/unclaimed screen, or be null for a room with no screen at all." `ON DELETE SET NULL` means deleting a TV device doesn't cascade-end its rooms — the rooms become screenless.
- `created_at` / `last_activity_at` / `ended_at` — lifecycle timestamps, paralleling sessions.

**Indexes:**

```sql
-- room_code lookup (invite resolution, scanned-screen attach, debug)
create index if not exists rooms_room_code_idx on public.rooms(room_code);

-- screen_ref → room resolution (tv2.html / shell asks "what room is on this TV?")
-- Partial: only active rooms with a non-null screen
create unique index if not exists rooms_one_active_per_screen
  on public.rooms(screen_ref)
  where screen_ref is not null and ended_at is null;
```

The partial unique on `rooms_one_active_per_screen` mirrors `sessions_one_active_per_tv` from db/008 — at most one active room can be bound to a given screen at a time.

---

## C. db/025 migration plan

Clean-slate cutover per UNIFIED-APP-PLAN §6. Existing session data is ephemeral and pre-launch — clearing it is safe.

Follows the existing numbered idempotent migration pattern (db/008 / db/020 / db/024 style).

**Migration structure (11 steps):**

1. **Header comment block** — purpose, scope, idempotency notes, post-migration verification queries (per the db/020/024 footer convention).

2. **Clear ephemeral session state** (the cutover pre-step):
   ```sql
   delete from public.session_participants;
   delete from public.sessions;
   ```
   Order matters: participants first (FK to sessions), sessions second. The db/015 promotion-push trigger is participation-role-transition gated; mass delete won't fire it.

3. **Drop the dead RPC:**
   ```sql
   drop function if exists public.rpc_session_promote_self_from_queue(uuid);
   ```
   Per §A: zero live callers; retired since admission-model v2.

4. **Drop the `fire_promotion_push` trigger and function:**
   ```sql
   drop trigger if exists trg_fire_promotion_push on public.session_participants;
   drop function if exists public.fire_promotion_push();
   ```
   The function body (db/015) reads `NEW.session_id`, which step 7 below removes. Because plpgsql function bodies are not eagerly validated against the schema (see §A's methodology note), a function left referencing a dropped column would silently survive the column drop and fail at the first matching UPDATE. Explicit drop is the safer posture. Recreation with room_id awareness is tracked in §D as a separate worklist item — it is NOT one of the 14 RPCs.

5. **Create `rooms` table** (schema from §B above), including:
   - Two indexes (`rooms_room_code_idx`, `rooms_one_active_per_screen`).
   - `alter table public.rooms enable row level security`.
   - SELECT policy: room participants OR (if screen_ref not null) household members of the TV's household — mirrors the existing sessions SELECT pattern. Write policies: none (mutations via SECURITY DEFINER RPCs only).

6. **Add `room_id` to `sessions`** + drop columns moving to room:
   ```sql
   drop index if exists public.sessions_one_active_per_tv;

   alter table public.sessions
     add column room_id uuid not null references public.rooms(id) on delete cascade,
     drop column tv_device_id,
     drop column manager_user_id,
     drop column room_code;

   create unique index if not exists sessions_one_active_per_room
     on public.sessions(room_id) where ended_at is null;
   ```
   The `not null` is safe because step 2 emptied the table. New invariant: at most one active session per room.

7. **Re-anchor `session_participants`** (the row-shape freeze + FK swap):
   ```sql
   alter table public.session_participants
     add column room_id uuid not null references public.rooms(id) on delete cascade,
     drop column session_id;
   ```
   Then re-create the four session-scoped indexes as room-scoped (see §E3 — 4 indexes re-key, not 5; the user-scoped index stays). Specifically:
   - Drop `session_participants_one_manager`, `session_participants_one_active_per_user`, `session_participants_queue_idx`, `session_participants_heartbeat_idx`.
   - Create the room-keyed equivalents (same predicates, same column structure, just `room_id` instead of `session_id`).
   - Leave `session_participants_user_idx` (on `user_id`) untouched.

8. **Create new RLS helpers** (SECURITY DEFINER, paralleling db/008's pattern):
   ```sql
   is_room_participant(p_room_id uuid)
   is_room_tv_household_member(p_room_id uuid)
   is_room_tv_household_admin(p_room_id uuid)
   ```
   Last two resolve through `rooms.screen_ref` → `tv_devices` → `household_members`. Returns false when `screen_ref IS NULL`.

9. **Update SELECT policies on `sessions` and `session_participants`** to read against the new helpers, room_id-keyed.

10. **Compatibility wrappers** for the session-keyed helpers, so any reader that still references them works during the RPC migration:
    ```sql
    create or replace function public.is_session_participant(p_session_id uuid)
    returns boolean ... as $$
      select public.is_room_participant(
        (select room_id from public.sessions where id = p_session_id)
      );
    $$;
    ```
    Same pattern for the other two. Wrappers can be dropped in a later cleanup once all callers are migrated.

11. **Verification queries** in the migration footer (matching db/020/024 style):
    ```sql
    -- 1. SELECT count(*) FROM rooms;                   -- expect 0
    -- 2. \d sessions                                   -- room_id present, tv_device_id/manager_user_id/room_code absent
    -- 3. \d session_participants                       -- room_id present, session_id absent
    -- 4. \d+ rooms                                     -- two indexes + RLS enabled
    -- 5. SELECT proname FROM pg_proc WHERE proname LIKE 'is_room%';  -- 3 rows
    -- 6. SELECT 1 FROM pg_proc WHERE proname='rpc_session_promote_self_from_queue';  -- 0 rows
    -- 7. SELECT 1 FROM pg_proc WHERE proname='fire_promotion_push';  -- 0 rows
    -- 8. SELECT 1 FROM pg_trigger WHERE tgname='trg_fire_promotion_push';  -- 0 rows
    ```

---

## D. Verified RPC migration worklist

### Cross-cutting decisions (pinned)

**Activity-timestamp target.** Every RPC in this worklist that bumps an activity timestamp MUST bump `rooms.last_activity_at` — this is the timestamp the reclaim RPCs' 10-minute inactivity gate reads (see the semantic table's `rpc_session_reclaim_manager` row). If the activity-bumping RPCs bumped only `sessions.last_activity_at`, the reclaim gate would read a timestamp nothing updates and would misfire. The activity-bumping RPCs SHOULD also continue to bump `sessions.last_activity_at` so the session-level timestamp stays meaningful for per-session reporting, but the `rooms` bump is required and the `sessions` bump is recommended-not-required. Applies to every activity-bumping RPC in the worklist — mechanical: `rpc_session_join`, `rpc_session_update_participant`, `rpc_session_update_queue_position`, `rpc_session_remove_participant`, `rpc_session_set_my_participation_role`, `rpc_karaoke_song_ended`; semantic: `rpc_session_start`, `rpc_session_end`, `rpc_session_leave`, `rpc_session_reclaim_manager`, `rpc_session_admin_reclaim`, `rpc_session_set_admission_mode`. The two read-only / non-bumping RPCs (`rpc_session_get_participants`, `rpc_session_heartbeat`) are not affected. `rpc_room_create` sets `rooms.last_activity_at` via the column default at row creation; no explicit bump needed.

### Mechanical re-pointing (8) — no logic change

Each takes a session_id today, filters on it, no business logic ties to session identity beyond the filter. Re-point parameter `p_session_id` → `p_room_id`; re-point `where session_id =` → `where room_id =`. Auth gate changes from `is_session_participant(p_session_id)` to `is_room_participant(p_room_id)`.

| RPC | File | Verified behavior |
|---|---|---|
| `rpc_session_join` | db/009 | Inserts a session_participants row; auth via `is_tv_household_member(v_session.tv_device_id)`. Re-point: insert with room_id, auth via `is_room_tv_household_member(p_room_id)`. (The join semantics — re-join via this RPC raises, role changes go through update_participant — are preserved.) |
| `rpc_session_update_participant` | db/011 + db/022 | Mutates role / queue_position / pre_selections / wanting_since on a participant row. Filter is `session_id, user_id`. Re-point both. |
| `rpc_session_update_queue_position` | db/011 | Reorders queue. Filter on session_id. Re-point. |
| `rpc_session_remove_participant` | db/016 | Manager soft-removes another participant via `left_at = now()`. Filter on session_id + target user. Re-point. |
| `rpc_session_set_my_participation_role` | db/017 | Self-only `active ↔ audience` flip on own row. Filter on session_id + auth.uid(). Re-point. |
| `rpc_session_get_participants` | db/013 + db/023 | Returns participants with wanting_since. Filter on session_id. Re-point + update RETURNS TABLE doc. |
| `rpc_session_heartbeat` | db/024 | Bumps caller's `last_seen_at` + prunes peers stale beyond 60s. Filter on session_id; auth via `is_session_participant`. Re-point both. The prune horizon (60s) is unchanged. |
| `rpc_karaoke_song_ended` | db/013 | Karaoke-specific helper. Filter on session_id. Re-point. **FOR UPDATE lock target (pinned):** the rewrite locks the current session under the room — `SELECT * FROM public.sessions WHERE room_id = p_room_id AND ended_at IS NULL FOR UPDATE` — because song-end is a session-scoped event and the session is the correct serialization granularity. Locking the room row instead would serialize all room operations unnecessarily; locking nothing would let two concurrent stage.html tabs both try to demote the same active singer. |

### Semantic (6) — logic changes at the room/session boundary

| RPC | File | Required change beyond re-pointing |
|---|---|---|
| `rpc_session_start` | db/009 + db/018 | **Largest change.** Must split into room-resolution + session-creation. Recommended shape (OQ2): keep `rpc_session_start` as session-creation-only; require caller to pass `p_room_id` (room must already exist). Add a new `rpc_room_create` for fresh-room creation. Branched participation_role default (games='active' / else='audience' from db/018) is preserved unchanged. |
| `rpc_session_end` | db/009 | **Participant sweep must STOP.** Currently sets `left_at = now()` on all active participants. Per the room/session split, ending a session no longer ends membership in the room. New body: set `ended_at` + `last_activity_at` only; DO NOT touch session_participants. (Room ending — which DOES sweep — is a separate Phase-5 concern.) |
| `rpc_session_leave` | db/010 | **Three changes.** (1) Re-point all session_id filters → room_id. (2) Add a new optional parameter `p_successor_user_id uuid` (default null) to support the tier-1 named-successor path. (3) Rewrite successor selection per ROOM-AUTHORITY-MODEL.md's three-tier hierarchy: **(Tier 1)** if `p_successor_user_id` is non-null and resolves to an eligible active room participant (`left_at IS NULL`, not the leaver), promote them; **(Tier 2)** else if any active host (`control_role = 'host'`, `left_at IS NULL`, not the leaver) is present, promote the longest continuously-present host (by `joined_at asc LIMIT 1`); **(Tier 3)** else promote the longest continuously-present non-audience participant (`participation_role IN ('active', 'queued')`, `left_at IS NULL`, not the leaver, by `joined_at asc LIMIT 1`). The `joined_at asc` ordering is correct for "longest continuously-present" because per the existing row-creation contract (`db/008:114-116`), a rejoin gets a new row with a new `joined_at` — the column captures the participant's current unbroken stint. If no tier matches, end the session (mark all participants left, set `ended_at`) per ROOM-AUTHORITY-MODEL.md's empty-room rule. **Critical: this RPC transfers room CONTROL only — it must NOT touch `rooms.owner_user_id`.** |
| `rpc_session_reclaim_manager` | db/010 | **Control transfer only.** Re-point session_id → room_id. Update `rooms.controller_user_id` (not the dropped `sessions.manager_user_id`). MUST NOT touch `rooms.owner_user_id`. The inactivity gate (10-min) and household-member authorization survive unchanged. |
| `rpc_session_admin_reclaim` | db/010 | **Control transfer only.** Re-point. Updates `rooms.controller_user_id`; never `rooms.owner_user_id`. The household-admin gate survives unchanged. |
| `rpc_session_set_admission_mode` | db/021 | **Stays session-scoped — cleanest of the six.** `admission_mode` is per-game (W1/W2 from ADMISSION-MODEL-V2.md) — a session property, not a room property. The RPC's filter stays `session_id`. Only change: the manager-authorization check, currently via `session_participants.control_role = 'manager'` filtered by `session_id`, becomes a lookup through `sessions.room_id → rooms.controller_user_id`. |

**Total: 8 mechanical + 6 semantic = 14 distinct RPCs.** Matches the plan's "~14."

The promote_self_from_queue drop brings the count of pre-existing session RPCs from 15 → 14; all 14 migrate to room-keyed.

### `rpc_room_create` — pinned implementation pattern (OQ2 (a) corollary)

The new `rpc_room_create` introduced by the `rpc_session_start` split (semantic table, OQ2 (a)) needs an explicit pattern for room_code generation, because `rooms.room_code` carries the partial UNIQUE index `rooms_one_active_per_code` (active room codes are unique; ended rooms may reuse). A naive single INSERT can collide and raise SQLSTATE `23505` if two managers generate the same code concurrently, or if the generated code matches an existing active room's code.

**Pattern:** generate a candidate `room_code` → attempt the INSERT → on `23505` (unique_violation) catch and retry with a fresh code → bounded retry (≤ 5 attempts). If all attempts collide, raise a clear error rather than looping unbounded or failing silently. Implementation lands in db/027.

**Room_code format:** not pinned in this spec. Length, character set, and case are open. Settle the format when `rpc_room_create` is written and document the choice in db/027's header. The legacy `sessions.room_code` (now dropped) used a 4–6 character pattern per CLAUDE.md; carrying that convention forward is the obvious default unless there's a specific reason to change.

### Additional tracked work: `fire_promotion_push` trigger recreation

Beyond the 14 RPCs above, the db/026-onward work tracks one additional
item from §A's MISSED row: re-create the `fire_promotion_push` trigger
and its backing function (both dropped in db/025 step 4) with room_id
awareness, once a payload-shape decision is made.

| Item | Where it lands | Required work |
|---|---|---|
| `fire_promotion_push()` function + `trg_fire_promotion_push` trigger | A new migration in db/026 onward (not one of the 14 RPCs) | Recreate the function and trigger. Trigger condition (`OLD.participation_role = 'queued' AND NEW.participation_role = 'active'` on `session_participants` AFTER UPDATE) is unchanged. Function body's `jsonb_build_object` payload changes per the open sub-question below. Until this lands, queued→active promotion push notifications do NOT fire — karaoke users whose iOS app is backgrounded do not receive the "you're up" push; foreground UI is unaffected (the realtime broadcast still drives it). |

**Open sub-question (decision needed before recreation).** What does the
push payload carry?

- **(a)** `room_id` only — drop `session_id` entirely. Cleanest for the
  new model. Breaking change for any iOS-side consumer that reads
  `data.session_id`.
- **(b)** Both `session_id` and `room_id`. `session_id` resolved at
  trigger time via `select id from public.sessions where room_id = NEW.room_id and ended_at is null`.
  Backward-compatible for the iOS app; slight extra query cost per push.
- **(c)** `session_id` only (same lookup as (b)). Preserves the current
  contract exactly; defers the iOS-side modernization.

The decision requires auditing how `~/Projects/elsewhere-app/` (the
out-of-repo Capacitor iOS app) uses `data.session_id` from the APNs
payload — whether it routes the user somewhere based on it, or just
shows the notification text. That audit is not schema-only work and is
out of this spec's scope. Defer the recreation until the iOS audit
lands.

---

## E. Pinned shapes

### E1. Current `sessions` table (the source-of-truth before db/025)

From db/008 + db/020:

| Column | Type | Nullable | Notes |
|---|---|---|---|
| id | uuid PK | NO | `default gen_random_uuid()` |
| tv_device_id | uuid | NO | FK → `tv_devices(id)` ON DELETE CASCADE. **Dropped in db/025** (moves to `rooms.screen_ref`, nullable). |
| app | text | NO | CHECK in `('karaoke','games','wellness')`. Preserved. |
| manager_user_id | uuid | NO | FK → `auth.users(id)`. **Dropped in db/025** (moves to `rooms.controller_user_id`). |
| started_at | timestamptz | NO | default `now()`. Preserved. |
| last_activity_at | timestamptz | NO | default `now()`. Preserved. |
| room_code | text | YES | **Dropped in db/025** (moves to `rooms.room_code`, NOT NULL). |
| current_state | jsonb | NO | default `'{}'::jsonb`. **Confirmed dormant; zero writers.** Per UNIFIED-APP-PLAN: "the room/session refactor need not migrate it." Recommend keeping the column on sessions in Phase 1 — see OQ3. |
| admission_mode | text | YES (after db/020) | CHECK allows NULL OR `('open','gated')`. Preserved. |
| capacity | int | YES | Preserved. |
| ask_proximity | boolean | NO | default false. Preserved. |
| turn_completion | text | NO | CHECK in `('app_declared','indefinite')` default `'indefinite'`. Preserved. |
| ended_at | timestamptz | YES | Preserved. |
| **room_id** *(NEW in db/025)* | **uuid** | **NO** | FK → `rooms(id)` ON DELETE CASCADE. |

Existing index `sessions_one_active_per_tv` → dropped. Replaced by `sessions_one_active_per_room`.

### E2. Current `session_participants` table (the frozen row shape)

From db/008 + db/020 + db/024:

| Column | Type | Nullable | Notes |
|---|---|---|---|
| id | uuid PK | NO | default `gen_random_uuid()` |
| session_id | uuid | NO | FK → `sessions(id)` ON DELETE CASCADE. **Replaced by room_id in db/025.** |
| user_id | uuid | NO | FK → `auth.users(id)` ON DELETE CASCADE |
| control_role | text | NO | CHECK in `('manager','host','none')` default `'none'`. `'host'` retained — see ROOM-AUTHORITY-MODEL.md "The host role" for the dormancy rationale. |
| participation_role | text | NO | CHECK in `('active','queued','audience')` default `'audience'` |
| pre_selections | jsonb | NO | default `'{}'::jsonb` |
| queue_position | int | YES | |
| joined_at | timestamptz | NO | default `now()`. Represents start of current unbroken stint (new row on each rejoin). |
| left_at | timestamptz | YES | |
| wanting_since | timestamptz | YES | (added db/020) |
| last_seen_at | timestamptz | NO | default `now()`. (added db/024) |
| **room_id** *(NEW in db/025)* | **uuid** | **NO** | FK → `rooms(id)` ON DELETE CASCADE — replaces `session_id` |

### E3. The five indexes on session_participants (re-keying scope)

| Index | Columns | Predicate | Phase-1 action |
|---|---|---|---|
| `session_participants_one_manager` | `(session_id)` UNIQUE | `WHERE control_role='manager' AND left_at IS NULL` | **Re-key to `(room_id)`** |
| `session_participants_one_active_per_user` | `(session_id, user_id)` UNIQUE | `WHERE left_at IS NULL` | **Re-key to `(room_id, user_id)`** |
| `session_participants_user_idx` | `(user_id)` | (none) | **No change** — already user-scoped, not session-scoped |
| `session_participants_queue_idx` | `(session_id, queue_position)` | `WHERE queue_position IS NOT NULL AND left_at IS NULL` | **Re-key to `(room_id, queue_position)`** |
| `session_participants_heartbeat_idx` | `(session_id, last_seen_at)` | `WHERE left_at IS NULL` | **Re-key to `(room_id, last_seen_at)`** |

**Doc-vs-repo nuance:** ROOM-SESSION-MODEL.md says "the five indexes re-key from session-scoped to room-scoped." Strictly, **4 of the 5 are session-scoped and re-key; one (`session_participants_user_idx`) is purely user-scoped and stays as-is.** The semantic intent of the plan is unchanged; this is a wording precision the build spec captures so no one accidentally re-creates the user_idx with room_id, breaking the "list my active rooms" query.

### E4. Current dormant `invites` table (rename target — NOT touched in db/025)

From db/001:249–266:

| Column | Type | Nullable | Notes |
|---|---|---|---|
| id | uuid PK | NO | default `gen_random_uuid()` |
| account_id | uuid | NO | FK → `profiles(id)` ON DELETE CASCADE |
| contact_id | uuid | YES | FK → `contacts(id)` ON DELETE CASCADE |
| **session_type** | text | NO | **Rename target → `app`** per ROOM-ACCESS-INVITE-MODEL §6 |
| room_code | text | NO | Already room-stable; no change |
| token | text | NO | UNIQUE |
| sent_via | text | YES | |
| created_at | timestamptz | NO | default `now()` |
| expires_at | timestamptz | NO | default `now() + interval '7 days'` |
| used_at | timestamptz | YES | (single-use marker) |

Plus 1 index (`invites_account_id_idx`) and 4 RLS policies (owner can SELECT/INSERT/UPDATE/DELETE).

**Phase-1 status:** This table is DORMANT and stays dormant through db/025. The `session_type → app` rename + the resolution Edge Function ship as a SEPARATE migration after Phase 1 lands — per UNIFIED-APP-PLAN §5: *"the invite schema and Edge Function after Phase 1."*

---

## F. Shell session-state cluster — the ~13 sites

Per UNIFIED-APP-PLAN §6: *"roughly 13 sites in the shell's active-session state cluster re-point from 'session for the bound TV' to 'room and its current session.'"*

**Confirmed live cluster (in `index.html`):**

| Surface | Lines | Role |
|---|---|---|
| `_activeSessionForBoundTv` module variable | 2443 | Single-room shape: `{ id, app, room_code, manager_user_id } \| null` |
| `getActiveSession()` accessor | 2449–2451 | Public reader |
| `refreshActiveSession()` | 2465–2499 | Queries `sessions` by `tv_device_id`, updates state, re-renders tiles |
| Clear-on-sign-out | 2422 | `_activeSessionForBoundTv = null` |
| Clear-on-no-TV | 2473 | Same |
| Active-session realtime subscription | 2501+ | Subscribes to `tv_device:<device_key>` channel; refreshes on `session_started` / `session_ended` events |
| Tile-relabeling reader | 2312 (and surrounds) | Reads `getActiveSession()` to decide tile labels |
| Mode-dispatch reader | 2924 | Reads `getActiveSession()` to decide post-tap navigation |
| Additional `sessions` queries by `tv_device_id` | 3148, 2480 | Direct `.from('sessions').eq('tv_device_id', ...)` |

**Phase-1 transformation:**

- Cache shape: `{ session: {...} | null, room: {...} | null }` — or a flatter shape where the room is the primary state and session is a sub-resource.
- Query path: `.from('rooms').eq('screen_ref', ctx.tv_device_id).is('ended_at', null)` to find the room; then `.from('sessions').eq('room_id', room.id).is('ended_at', null)` to find its current session.
- Realtime events `session_started` / `session_ended` may want sibling `room_*` events if room lifecycle becomes user-observable; that's a Phase-5 concern. For Phase 1, the existing session events still fire and `refreshActiveSession` re-queries through the room indirection.

**Additional readers of `.from('sessions')` across surfaces** (out of strict shell scope but pinned):
- `games/tv.html:1321, 1385`
- `games/player.html:2753`
- `karaoke/stage.html:5410, 5756`
- `karaoke/singer.html:749, 2290`

Per UNIFIED-APP-PLAN §5 — karaoke is Phase 3, games is Phase 4. These per-surface site updates ride those phases, not Phase 1.

**RPC signature breakage from db/027 (heads-up for the shell rework).** When db/027 lands, `rpc_session_start`'s signature changes from 7 args (db/018) to 6 args:

- **Dropped:** `p_tv_device_id` and `p_room_code`. Both columns are gone from `sessions` (db/025); the screen reference now lives on `rooms.screen_ref` and the room code on `rooms.room_code`. The bound-TV and code information moves to `rpc_room_create` (db/027).
- **Added:** `p_room_id uuid` (required, no default) — the existing room to start a session under.
- **Unchanged:** `p_app`, `p_admission_mode`, `p_capacity`, `p_ask_proximity`, `p_turn_completion`.

Every existing client call site that passes the old 7-arg signature breaks at runtime once db/027 is applied. The Supabase JS client rejects unknown named arguments (Postgres raises on the wrong argument name), so the failure mode is a clear error rather than a silent mismatch. **Known call site:** `index.html:3141` (passes `p_room_code: room`). Any other surface that calls `rpc_session_start` with the old shape also breaks; locate them with `grep -rn "rpc_session_start" index.html tv2.html karaoke/ games/`.

The new client flow is a two-call sequence:

1. `sb.rpc('rpc_room_create', { p_screen_ref })` — create the durable room. `p_screen_ref` is the bound TV's `tv_devices.id`, or `null` for a screenless room. Returns the new `rooms` row including `id` and the generated `room_code`.
2. `sb.rpc('rpc_session_start', { p_room_id, p_app, p_admission_mode, p_capacity, p_ask_proximity, p_turn_completion })` — create a session under the new room. The convener was already seated by `rpc_room_create`; this call applies the branched per-app `participation_role` default to the controller's existing row (no new participant insert).

The transient breakage between db/027 applying and the shell rework landing is the same expected migration-window behavior the build spec's cutover framing covers — session and participant data is ephemeral and pre-launch, no real users exposed. The shell rework — when it picks up the ~13 sites described above — resolves it by switching every `rpc_session_start` caller to the two-call flow.

---

## G. Partial-scaffolding confirmation, with an honest scope note

**Confirmed clean slate, for the rooms entity itself.** No partial
implementation of the rooms entity exists:

- `grep -rn "CREATE TABLE.*rooms" db/` → 0 matches
- `grep -rn "room_id" db/` → 0 matches outside this investigation
- `grep -rn "controller_user_id\|owner_user_id\|screen_ref" db/ shell/ games/ karaoke/ index.html tv2.html` → 0 matches anywhere
- `room_code` exists on `sessions` (db/008) and `invites` (db/001), but those are the legacy / dormant homes that the migration moves away from / re-uses — not scaffolding for the new model.

So db/025 is a true greenfield migration with respect to the rooms
entity.

**Scope of the broader dependency sweep was incomplete by one item.**
The dependency sweep also aimed to catalog every reference to the four
columns db/025 drops (`session_participants.session_id`,
`sessions.tv_device_id`, `sessions.manager_user_id`,
`sessions.room_code`). It surveyed RPC function bodies (catalogued in
§D) and used SQL column-name grep — but it did NOT audit trigger
function bodies as a separate category. That gap surfaced db/015's
`fire_promotion_push` only during db/025's drafting, after this spec
was already committed. The MISSED row in §A and the
additional-tracked-work subsection in §D close the gap; §C step 4
folds the explicit trigger+function drop into the migration. A future
reader should calibrate trust in this spec accordingly: the
rooms-entity scaffolding claim above is solid; the broader
column-reference coverage was incomplete by the one trigger above and
is now closed.

---

## H. Open questions

OQ1–OQ5 carry recommendations or are open as noted. OQ6 is resolved.

1. **`rooms.room_code` uniqueness.** Should there be a UNIQUE constraint on `room_code` (globally? among non-ended rooms only?), or only an index for lookup? ROOM-ACCESS-INVITE-MODEL.md treats `room_code` as the key the invites table joins on, which implies room codes need to be unambiguously resolvable. Recommendation: UNIQUE among non-ended rooms (`UNIQUE on (room_code) WHERE ended_at IS NULL`) — historical (ended) rooms can reuse codes. **Decision needed.**

2. **`rpc_session_start` split shape.** The plan says "split room-resolution from session-creation" but leaves the RPC surface shape to execution. Two options:
   - **(a)** Keep `rpc_session_start` as session-creation-only; require caller to pass `p_room_id`. Add a new `rpc_room_create` for fresh-room creation. **Recommended** — cleaner separation; matches how rooms are durable while sessions churn.
   - **(b)** Make `rpc_session_start` auto-create the room if `p_room_id` is null. Convenient for first-call cases but conflates lifecycles.
   **Decision needed.** Recommend (a).

3. **`sessions.current_state` — keep or drop in db/025.** Zero writers confirmed. Dropping is clean but adds a column-removal to the migration with no payoff if a future app wants to use it. Keeping is cheap. Plan §6 explicitly says "the room/session refactor need not migrate it." Recommend: keep. **Confirm.**

4. **Compat wrapper lifetime for `is_session_*` helpers.** Wrappers added in step 9 are useful during the RPC migration if any RPC's body inadvertently still references the session-keyed helper. They could be dropped at the end of db/025 itself if every RPC body is rewritten in-migration, or kept and dropped in a follow-up cleanup. Recommend: keep through Phase 1; drop in a Phase 1.1 cleanup once we've confirmed nothing in shell or other RPCs reads them.

5. **Doc-vs-repo nuance: "five indexes" wording.** Flagged in §E3 — 4 of 5 indexes re-key, not all 5. Not a model error; just precision wording. **No decision needed; flagged for awareness.**

6. **`rpc_session_leave` succession tiers — RESOLVED.** The original investigation read ROOM-AUTHORITY-MODEL.md as a single-tier rule and proposed dropping the host preference. The succession refinement committed 2026-05-21 to ROOM-AUTHORITY-MODEL.md establishes a three-tier hierarchy instead: (1) named successor (explicit-departure-only), (2) present host (tier 2 always beats tier 3; multi-host tiebreak by longest continuously-present), (3) longest continuously-present non-audience participant. The host tier is KEPT, and `rpc_session_leave` gains a new optional `p_successor_user_id` parameter for tier 1. See §D's `rpc_session_leave` row for the migration scope.

---

## I. What this spec is and is not

**Is:** a reviewable structural plan for db/025 — the rooms table shape, the migration steps, the RPC worklist with verified classification, the pinned column lists and indexes, and the open questions.

**Is not:** SQL code for db/025. Migration code is the step after the remaining open questions (OQ1–OQ4) are addressed.

**Next concrete actions after open-questions resolution:**
1. Resolve OQ1–OQ4 in §H (OQ5 is awareness-only; OQ6 resolved).
2. Write db/025 against this spec, following the established idempotent migration pattern.
3. Apply to prod via Supabase SQL Editor; update `db/MIGRATIONS_APPLIED.md` per CLAUDE.md doctrine.
4. Then begin the 14-RPC migration (likely a series of CREATE-OR-REPLACE migrations in db/026 onward to keep each commit reviewable). The new `rpc_session_leave` signature picks up `p_successor_user_id` and the three-tier successor logic in that RPC's migration.
