# Elsewhere — Execution Handoff Brief

**Purpose:** This document, together with the five unified-app planning
docs, is the kickoff for any new chat continuing the unified-app
execution work. Read this FIRST, then the planning docs.

**Last updated:** 2026-05-21 (Phase-1 migration in progress: db/025 applied; db/026 + db/027 committed-not-applied; db/028 next — see §2 and §4)

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

**Phase-1 migration: in progress.**

- **db/025** (schema cutover — rooms entity + session/participant
  re-anchor): committed `dddbeb6`, **applied to prod** 2026-05-21,
  recorded in `db/MIGRATIONS_APPLIED.md` (`0843168` flip commit).
- **db/026** (RPC batch 1 — 10 of 14 session-keyed RPCs to room-keyed;
  the 8 mechanical re-points + rpc_session_end +
  rpc_session_set_admission_mode): committed + pushed `9e3926e`.
  **Written, not yet applied.**
- **db/027** (RPC batch 2 — rpc_session_start split + new
  rpc_room_create; the OQ2 (a) shape): committed + pushed `2465ff5`.
  Same commit added the §F amendment recording the rpc_session_start
  client signature breakage + a DEFERRED.md entry tracking the shell
  rework needed. **Written, not yet applied.**
- **db/028** (RPC batch 3 — rpc_session_leave with three-tier
  succession + new `p_successor_user_id` parameter, plus
  rpc_session_reclaim_manager and rpc_session_admin_reclaim):
  **next, not started.** See §4.

After db/028 lands and applies, the immediate-after work is: apply
db/026/027/028 to prod + update `db/MIGRATIONS_APPLIED.md`; the §F
shell session-state cluster rework (resolves the rpc_session_start
client-breakage transient from db/027); the `fire_promotion_push`
trigger recreation (pending an iOS-app audit on payload shape); and
the Phase-1.1 compat-wrapper cleanup (drop the `is_session_*`
wrappers after a grep-confirmed zero-caller check). Then Phases 2–5
per UNIFIED-APP-PLAN §5.

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

Write db/028 — the third and final Phase-1 RPC migration batch.
Three RPCs land:

- **rpc_session_leave** — re-point to room-keyed, plus three-tier
  succession (named successor → present host → longest-present
  non-audience), with a new optional `p_successor_user_id uuid`
  parameter for tier 1. See ROOM-AUTHORITY-MODEL.md for the model
  and PHASE-1-BUILD-SPEC.md §D's `rpc_session_leave` row for the
  migration scope.
- **rpc_session_reclaim_manager** — re-point to room-keyed; updates
  `rooms.controller_user_id` (NOT `rooms.owner_user_id`, which is
  immutable post-creation per the OQ2 structural guarantee).
- **rpc_session_admin_reclaim** — same shape as reclaim_manager but
  household-admin gate instead of inactivity gate.

**Recommend an investigate-first round before writing**, same
pattern as db/027 used. db/027's pre-write investigation surfaced
the convener-seating gap and the controller-only branched-default
scope; both were resolved in advance instead of mid-write. db/028's
risk surface is comparable — the three-tier succession is the
largest model-vs-RPC translation in the workstream, and the
manager-alone / empty-room branch reaches into Phase-5 territory
(room-ending) that the build spec only sketches. Worth
investigating in advance:

- Three-tier succession SQL shape (named successor as a new
  parameter; host vs. non-audience tie-breakers via `joined_at`
  + the row-existence contract).
- Auth/write target for both reclaim RPCs
  (`rooms.controller_user_id`, with the
  `session_participants.control_role` mirror).
- The "no eligible successor → room ends" branch — what exactly
  sets `rooms.ended_at`?

The investigate-then-write rhythm proven by db/027 is the right
discipline here. db/028 is the last RPC migration in the Phase-1
arc; missing a model detail at the end is worse than at the
beginning because there's no fourth batch to absorb a correction.

**After db/028 commits, the immediate-after work:**

- Apply db/026 + db/027 + db/028 to prod (Supabase SQL Editor),
  updating `db/MIGRATIONS_APPLIED.md` for each.
- §F shell session-state cluster rework (Phase-1-scope client-side
  migration; the rpc_session_start signature breakage from db/027
  is the most concrete forcing function — see DEFERRED.md entry).
- `fire_promotion_push` trigger recreation with room_id awareness
  (pending an iOS-app audit on data.session_id payload usage —
  tracked in PHASE-1-BUILD-SPEC.md §D's "Additional tracked work").
- Phase-1.1 compat-wrapper cleanup: drop the `is_session_*`
  wrappers after a grep-confirmed zero-caller check.

Then Phases 2–5 per UNIFIED-APP-PLAN §5.

**Deferred follow-up (separate task):** ROADMAP.md's "Active
session" still lists Session 5; the unified-app workstream
hasn't been promoted to active-session status there. Structural
decision, worth a separate review rather than a hasty addendum
here.

## 5. Review discipline

Propose-then-review. Claude Code proposes diffs or specs; the human and
planning chat review before anything is committed. Commits and pushes are
separate gates. Migration code is never written before its build spec is
reviewed.

## 6. Maintaining this brief

Update section 2 and section 4 at the end of each execution session, so
this brief is always a current snapshot of where the project is and what
the next step is — the same way CONTEXT.md is maintained.
