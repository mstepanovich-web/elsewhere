# Elsewhere — Execution Handoff Brief

**Purpose:** This document, together with the five unified-app planning
docs, is the kickoff for any new chat continuing the unified-app
execution work. Read this FIRST, then the planning docs.

**Last updated:** 2026-05-23 (premium-control + regular-user model documentation pass complete — see ROOM-AUTHORITY-MODEL.md / HOUSEHOLD-DEVICE-PRESENCE-MODEL.md / ROOM-SESSION-MODEL.md; §4 now points at §F shell-rework IMPLEMENTATION — the §F pre-write investigation already ran this session and is recorded inline)

---

## 1. The three environments — read this before anything else

Work on this project happens across THREE environments. They are NOT
interchangeable. Most handoff failures come from forgetting this.

- **The planning chat** (a regular claude.ai chat — likely the one
  reading this now). Has the project context. Writes tasks, reviews
  results, makes decisions. **CANNOT read or edit the repo.** It only
  sees what is pasted into it.
- **Claude Code** (a terminal tool running in the repo). CAN read every
  file, run git, edit code. It executes tasks. It does not drive the
  project — it does what each task says.
- **The human.** Carries tasks from the planning chat to Claude Code, and
  carries Claude Code's results back to the planning chat.

**The working loop, every time:** planning chat writes a task → human
pastes it into Claude Code → Claude Code does the repo work and reports →
human pastes the result back to the planning chat → planning chat reviews
it with the human. Pushes are deliberate gates the human approves.

**The rule that prevents the most common failure:** any task that needs
to READ or EDIT the repo MUST go to Claude Code. Never write a
"check against the actual repo" or "edit file X" task for the planning
chat — the planning chat physically cannot do it and will get stuck
asking for files. If you are the planning chat and you are about to write
a task, the first question is always: WHO RECEIVES THIS — Claude Code, or
the human directly? Write accordingly.

The five planning docs are committed in the repo, so Claude Code can read
them itself. They do not need to be pasted into Claude Code.

## 2. Where the project is

The unified-app / NHHU-primary refactor. Goal: every registered user is a
first-class user of every app at a baseline tier with no TV device
required; a TV device adds a premium capability layer. This refactors
KARAOKE and GAMES; Wellness and Worlds are greenfield.

**Documentation phase: COMPLETE.** Five planning docs written, reviewed,
committed. Every superseded doc carries a supersession pointer. CONTEXT.md
(the general kickoff doc), INFRA.md, and CLAUDE.md were all revised to
match. No doc contains a known-false statement.

**Phase-1 execution-scope investigation: COMPLETE.** Its adopted output is
`docs/PHASE-1-BUILD-SPEC.md` (initial commit `caf647e`, amended by
`fcc42f6` for three cross-cutting pinned decisions + an S6 current-state
correction). The six open questions surfaced in §H are now closed.

**Phase-1 RPC migration: COMPLETE.** All four database migrations
are applied to prod and recorded in `db/MIGRATIONS_APPLIED.md`. The
room-keyed RPC surface (the 14 RPCs plus new `rpc_room_create`) is
the canonical implementation in prod as of 2026-05-22.

- **db/025** (schema cutover — rooms entity + session/participant
  re-anchor): committed `dddbeb6`, applied 2026-05-21.
- **db/026** (RPC batch 1 — 8 mechanical re-points + rpc_session_end
  + rpc_session_set_admission_mode): committed `9e3926e`, applied
  2026-05-22.
- **db/027** (RPC batch 2 — rpc_session_start split + new
  rpc_room_create per OQ2 (a)): committed `2465ff5`, applied
  2026-05-22.
- **db/028** (RPC batch 3 — rpc_session_leave with four-tier
  host-first succession + new `p_successor_user_id` parameter, plus
  rpc_session_reclaim_manager and rpc_session_admin_reclaim):
  committed `95dcf70`, applied 2026-05-22.
- **Forward-correction commit `c657c9f`** added `DROP FUNCTION IF
  EXISTS` statements ahead of each CREATE on the 11 renamed/re-typed
  functions across db/026/027/028. The originals used `CREATE OR
  REPLACE FUNCTION` for parameter renames and return-type changes,
  which Postgres rejects with `42P13`; without `c657c9f`, none of
  the three RPC migrations could apply. The fix landed mid-apply
  and the three migrations then applied cleanly.

Verified-live structural guarantees from the post-migration checks:
`rpc_room_create` is the sole writer of `rooms.owner_user_id`
(immutable post-creation per OQ2 (a)); `rpc_session_leave`'s tier-4
branch is the first and only writer of `rooms.ended_at` in the
system.

The immediate next step — the §F shell session-state cluster rework
— is in §4. The §F rework is the active forcing function: the shell
still calls the OLD pre-db/026 RPC signatures and breaks at
runtime, per `docs/DEFERRED.md`'s "Phase-1 RPC migration in-flight"
entry. After §F: the `fire_promotion_push` trigger recreation
(pending an iOS-app audit on payload shape) and the Phase-1.1
compat-wrapper cleanup (drop the `is_session_*` wrappers after a
grep-confirmed zero-caller check). Then Phases 2–5 per
UNIFIED-APP-PLAN §5.

## 3. The five planning docs — the design

All in docs/. Read all five after this brief:
- `UNIFIED-APP-PLAN.md` — umbrella: capability model, the six locked
  decisions, four-quadrant per-app breakdown, phase sequencing, open
  items (§8).
- `ROOM-SESSION-MODEL.md` — entity model: durable `rooms` + disposable
  per-app `sessions`; `session_participants` re-anchored to `room_id`.
- `ROOM-AUTHORITY-MODEL.md` — manager authority splits into room control
  (transferable) and room ownership (never transfers by succession);
  succession picks the longest continuously-present non-audience
  participant.
- `ROOM-ACCESS-INVITE-MODEL.md` — token-based invites on the dormant
  `invites` table; new Edge Function to resolve tokens.
- `HOUSEHOLD-DEVICE-PRESENCE-MODEL.md` — households, binding, presence,
  premium-embedding rule. Supersedes PHONE-AND-TV-STATE-MODEL.md.

## 4. The immediate next step

**The §F shell session-state cluster rework** — the ~13-site
client-side migration enumerated in `docs/PHASE-1-BUILD-SPEC.md` §F.
Two things land in this rework: the shell's active-session state
cluster is re-pointed from "the session for the bound TV" to "the
room and its current session," and every shell call site for
`rpc_session_start`, `rpc_session_leave`,
`rpc_session_reclaim_manager`, and `rpc_session_admin_reclaim` is
switched to the new room-keyed signatures.

**The §F pre-write investigation already ran this session
(2026-05-23) and is recorded in the planning-chat transcript.** Its
findings — the §F site table has zero drift; only 4 live shell-tier
RPC call sites exist (all in `index.html`); rpc_room_create has zero
existing callers — are good as of this date and do not need to be
re-derived. The next session does NOT need to re-run the §F
investigation; it picks up at IMPLEMENTATION.

**Implementation decisions already made (during the investigation
+ planning-chat review):**

- **Cache shape: nested `{ session, room }`.** The shell's
  `_activeSessionForBoundTv` becomes `{ session: { id, app } | null,
  room: { id, controller_user_id, room_code } | null }`. Faithful
  to the room/session split; the "room exists but no session"
  state (between apps in a cross-app move) is naturally
  representable.
- **Keep `room_code` under `room`.** No current consumer reads it,
  but it's cheap to carry for future banner/QR UX.
- **Two-call session-start flow.** Where the shell today calls
  `rpc_session_start(...)`, the new flow is `rpc_room_create(...)`
  followed by `rpc_session_start({ p_room_id, ... })`. Transparent
  room-reuse: when a room already exists for the screen, the
  handler skips `rpc_room_create` and calls `rpc_session_start`
  directly against the existing `room.id`. New error path: if the
  room exists but the current user is NOT its controller, the
  handler surfaces a clean message rather than letting
  `rpc_session_start` raise `42501`.
- **`rpc_session_end` argument unchanged.** Keeps `p_session_id`
  per db/026; only the surrounding state-cluster reads change, not
  the RPC call itself.

**The model the §F rework builds against is complete and
committed.** The premium-control model (commit `c086af7`) and the
regular-user tile-navigation model (commit `8e1d24f`) are
documented across `docs/ROOM-AUTHORITY-MODEL.md`,
`docs/HOUSEHOLD-DEVICE-PRESENCE-MODEL.md`, and
`docs/ROOM-SESSION-MODEL.md`. The investigation's flag-4
question — "how does tile-tap interact with session creation and
the one-engagement prompt?" — is now resolved by
ROOM-SESSION-MODEL.md's new section "Tile-tap is navigation, not
session creation": tile-tap is freely-repeatable navigation only;
session creation is a deliberate in-app action; the
one-engagement prompt fires at session-creation/join, not at
tile-tap.

**Forcing function.** The shell still calls the OLD pre-db/026 RPC
signatures (`rpc_session_start` with 7 args including
`p_room_code`; `rpc_session_leave(p_session_id)`; reclaim RPCs
with `p_session_id` and a sessions-typed return; the 8 mechanical
RPCs filtered by `p_session_id`). All of these are runtime-broken
now that the room-keyed RPCs are live in prod — Postgres rejects
the calls because the named-argument shapes no longer exist at the
database. This is the mid-migration window recorded as
`docs/DEFERRED.md`'s "Phase-1 RPC migration in-flight — shell still
on pre-db/026 RPC signatures" entry; the §F rework is the resolving
work for the SHELL portion of that entry.

**Scope carve-out (important).** The §F rework covers the SHELL
session-state cluster only. The per-surface call sites under
`karaoke/*` and `games/*` are NOT part of §F — they ride Phase 3
(karaoke) and Phase 4 (games) of `UNIFIED-APP-PLAN.md` §5 per
PHASE-1-BUILD-SPEC.md §F's per-surface note (line 356). Those
surfaces remain on the old session-keyed signatures until their
respective phase lands; their breakage is bounded to those surfaces
and does not block the shell-level Phase-1 close.

**Tracked downstream work — already in DEFERRED.md.** Five new
entries landed this session (commit `8e1d24f`) capturing the
premium-control model's tracked future work. The §F rework does
NOT need to act on any of these — they are downstream of the shell
rework — but the next session should know they exist:

- **C1: tv_devices needs a `can_embed` column.** Required to make
  the premium-control layer's activation predicate
  runtime-enforceable.
- **C2: `shell/realtime.js` publisher payloads carry pre-room-model
  field names.** Harmless for the shell-tier subscription path
  (subscribers re-query); latent risk for Phase 3/4 surfaces that
  parse payloads.
- **C3: turn-notification depends on `fire_promotion_push` trigger
  recreation.** Cross-links to PHASE-1-BUILD-SPEC.md §D's existing
  trigger-recreation tracking.
- **C4: HH-admin administrative actions without engagement
  transition.** Future enhancement; current uniform-engagement
  behavior is correct for the primary use case.
- **C5: ownership-seize implementing RPC.** Operation fully
  specified in ROOM-AUTHORITY-MODEL.md § "Seize authority"; RPC
  not yet implemented.

**After the §F shell rework lands:**

- `fire_promotion_push` trigger recreation with room_id awareness
  (DEFERRED C3 above; the iOS payload audit is the gating step).
- Phase-1.1 compat-wrapper cleanup: drop the `is_session_*`
  wrappers after a grep-confirmed zero-caller check.

Then Phases 2–5 per UNIFIED-APP-PLAN §5.

**Deferred follow-ups (separate tasks):**

- ROADMAP.md's "Active session" still lists Session 5; the
  unified-app workstream hasn't been promoted to active-session
  status there. Structural decision worth a separate review rather
  than a hasty addendum here.
- **Per-user per-app tile-badge spec in UNIFIED-APP-PLAN.md** —
  parked from the 2026-05-23 model-documentation pass. The
  premium-control model documentation deferred the tile-badge UX
  spec to a separate UAP task; it has NOT been written into any
  doc yet and is NOT a DEFERRED.md entry. Needs its own future
  task to draft + land. Surface item for whoever picks up after
  §F.

## 5. Review discipline

Propose-then-review. Claude Code proposes diffs or specs; the human and
planning chat review before anything is committed. Commits and pushes are
separate gates. Migration code is never written before its build spec is
reviewed.

## 6. Maintaining this brief

Update section 2 and section 4 at the end of each execution session, so
this brief is always a current snapshot of where the project is and what
the next step is — the same way CONTEXT.md is maintained.
