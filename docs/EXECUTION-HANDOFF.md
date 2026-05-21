# Elsewhere — Execution Handoff Brief

**Purpose:** This document, together with the five unified-app planning
docs, is the kickoff for any new chat continuing the unified-app
execution work. Read this FIRST, then the planning docs.

**Last updated:** 2026-05-21 (execution phase starting; Phase 1 not yet
begun)

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

**Execution phase: STARTING. Phase 1 not yet begun.**

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

Per UNIFIED-APP-PLAN.md §8: before db/025 (the Phase-1 migration) is
written, the Phase-1 execution-scope investigation must be re-run against
the final five-doc design and the actual current repo. The original
investigation predates the manager controller/owner split, so it is
stale.

This investigation is a CLAUDE CODE task (it reads the repo). Its output
is a reviewable build spec — the final `rooms` schema (with BOTH a
controller and an owner reference, per §6), the db/025 migration plan,
and the verified RPC migration worklist (including the rpc_session_leave
succession-logic change). It does NOT write migration code. Migration
code is the step after, once the spec is reviewed.

## 5. Review discipline

Propose-then-review. Claude Code proposes diffs or specs; the human and
planning chat review before anything is committed. Commits and pushes are
separate gates. Migration code is never written before its build spec is
reviewed.

## 6. Maintaining this brief

Update section 2 and section 4 at the end of each execution session, so
this brief is always a current snapshot of where the project is and what
the next step is — the same way CONTEXT.md is maintained.
