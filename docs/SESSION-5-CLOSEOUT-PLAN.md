# Session 5 Closeout Plan

**Created:** 2026-05-13
**Purpose:** Execution plan for the final stretch of Session 5. The week-of
view across what's likely 3-4 chat sessions. Cross-session continuity doc:
any new chat can read this + CONTEXT.md and know where we are.

**Status field at the top of each day:** update at end of each chat session
that touches the plan. Use `⏳ Not started` / `🟡 In progress` / `✅ Done` /
`🟡 Deferred (note)`.

## Framing

Session 5 has been the active session since mid-April. The discipline this
week is closing it, not extending it. Everything tempting on the post-
Session-5 board (premium UX differentiation, audience unification, venues,
wellness) is locked behind Session 5's close and will be available once
Session 5 is actually done. No detours.

Five working days of plan, but the work spans chat sessions, not calendar
days. If we slip, we slip — but we slip *forward through the same ordered
list*, not sideways into post-Session-5 work.

## Locked decision: Path A (finish Session 5 hard)

At end-of-Part-3 (Trivia + Last Card + Euchre 3b/3c/3d all shipped), the
fork is:
- **Path A — Part 5 verification immediately.** Closes Session 5 formally
  before any post-Session-5 work starts.
- **Path B — Take a small post-Session-5 win (Session 6 SMS pre-invites)
  first, then come back to Part 5.**

**Path A is locked.** Rationale: verification debt compounds the same way
bundle drift does. Part 5 catches "Session 5 introduced a regression"
before more work stacks on top. Session 6 stays orthogonal and gets picked
up cleanly once Session 5 is closed.

## The plan

### Day 1 — v2.113 hardware verification + iOS Capacitor sync + start Trivia 3b proper

**Status:** ⏳ Not started

**Morning:**
1. iPhone Safari verification of v2.113 polish items (stale "(premium)"
   status text reset on entry, ☰ Games button removal). Mark v2.113 ✅
   GREEN in `docs/SESSION-5-PART-3B-VERIFICATION-LOG.md`. ~5 min.
2. iOS Capacitor sync catch-up: bundle v2.99 → v2.113. ~30 min. Reference
   DEFERRED entry "Session 5 closeout — iOS bundle sync from v2.99 to
   current". Done now while verification context is fresh; doing it later
   means compounding drift with every 3b/3c/3d commit.

**Afternoon:**
3. Start Trivia 3b proper. Per `docs/GAMES-CONTROL-MODEL.md` § 4.1:
   late-joiner choice screen (Active vs Audience), `admission_mode`
   dispatch in `handleMessage`'s `game-state` receiver, Skip Question
   manager-bar wiring (`mgr-skip` currently only fires for Last Card).
   Plan as 2-3 small section commits, not one big one. Hardware verify
   each before the next.

**Risks:**
- Trivia 3b could be larger than ROADMAP's ~80-120 LOC estimate. The
  late-joiner choice screen is new UI surface, not just wiring. If it
  grows, Days 1-2 stretch and Last Card/Euchre slip. That's fine — the
  order stays, the calendar adjusts.
- Hardware verification of new code on iOS Safari can surface URL-routing
  or state-handling quirks (precedent: `e97dc94` premium URL routing gap).
  Buffer time.

### Day 2 — Finish Trivia 3b proper + start Last Card 3c

**Status:** ⏳ Not started

1. Any fix-forwards from Day 1 hardware testing of Trivia 3b.
2. Trivia 3b closeout pass: DEFERRED.md updates, append to
   `docs/SESSION-5-PART-3B-CLOSING-LOG.md` (or new sub-part log if scope
   warrants).
3. If Trivia 3b finishes cleanly by mid-day: start Last Card 3c. Same
   scope shape as Trivia 3b, applied to Last Card. Should be faster — the
   pattern is now established.

### Day 3 — Last Card 3c + start Euchre 3d

**Status:** ⏳ Not started

1. Last Card 3c finish + closeout.
2. Start Euchre 3d. Same scope as Last Card 3c. Euchre wrinkle: uses
   `manager_approved_batch` admission rather than `self_join` or
   `wait_for_next`, so the late-joiner UI is "manager will approve you
   next hand" — distinctive enough to deserve careful UX thought. Most
   distinctive UX of the three games.

### Day 4 — Euchre 3d finish; Part 4 pass; prep Part 5

**Status:** ⏳ Not started

1. Euchre 3d wraps. Session 5 Part 3 is now done across all three games.
2. Part 4 (proximity polish) — substantially absorbed into 2c per
   `docs/PHONE-AND-TV-STATE-MODEL.md`. Likely 0-commit pass; document if
   that holds.
3. Prep Part 5: create `docs/SESSION-5-VERIFICATION.md` skeleton, line up
   the 8 verification flows, confirm 2+ test accounts ready.

### Day 5 — Part 5 verification + Session 5 formal close

**Status:** ⏳ Not started

1. Run the 8 Part 5 verification flows per `docs/SESSION-5-PLAN.md` Part 5:
   multi-user karaoke (queue ordering, manager approves, host override
   mid-song), multi-user game (Trivia self-join), manager transfer,
   orphaned session reclaim, household admin force-reclaim, proximity
   gate, cross-app isolation, regression check (all 4.10.2 + 4.10.3 flows
   still work).
2. Last fix-forwards from anything verification surfaces.
3. Comprehensive Session 5 closeout: closing log covering the whole arc
   (Parts 1-5), DEFERRED.md final pass, CONTEXT.md "Latest shipped"
   updated, ROADMAP.md moves Session 5 from "Active" to "Completed".
4. End of week: Session 5 formally done.

**Risk:** Part 5 with only 2 real test accounts may be insufficient for
some flows (multi-user karaoke queue, capacity overflow ideally want 3-4
accounts). If we can't get there, document the gap honestly in
`docs/SESSION-5-VERIFICATION.md` rather than fake-pass.

## What this plan explicitly is NOT

- **Not Session 8 (Trivia premium UX differentiation).** Most tempting,
  most expensive in focus debt. Open design space, TBD estimate. Save it
  for when Session 5 is closed and the design conversation can have its
  full attention.
- **Not Session 9 (audience.html unification).** Keystone rework. Needs
  dedicated session, not a backfill.
- **Not Session 10 (venues at platform level).** Cross-app service work.
  Same reason.

## Cross-session continuity

When picking up mid-plan in a new chat:
1. Paste CONTEXT.md (kickoff per SESSION-START-METHODOLOGY).
2. Paste this doc.
3. State which day's status is currently 🟡 In progress and what was the
   last verified state.

When closing a chat session that advanced this plan:
1. Update Status field on the day(s) touched.
2. Update CONTEXT.md "Latest shipped" per SESSION-CLOSING-METHODOLOGY.
3. Update ROADMAP.md if any items shifted.

## Reference

- `docs/CONTEXT.md` — current state at any moment
- `docs/ROADMAP.md` — long-term sequencing; this doc is the Session 5
  closeout execution
- `docs/GAMES-CONTROL-MODEL.md` § 4.1 — Trivia/LastCard/Euchre 3b scope
- `docs/SESSION-5-PLAN.md` Part 5 — verification flows
- `docs/SESSION-5-PART-3B-CLOSING-LOG.md` — most recent shipped detail
- `docs/SESSION-5-PART-3B-VERIFICATION-LOG.md` — v2.113 gate
- DEFERRED entry "Session 5 closeout — iOS bundle sync from v2.99 to
  current" — Day 1 sync task
