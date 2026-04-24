# NEXT-SESSION.md

Paste-ready prompt book for starting the next Elsewhere session. Lives at the repo root so it's always findable — no remembering "where did I put my how-to-get-going notes."

- [docs/ROADMAP.md](./docs/ROADMAP.md) — current session pipeline
- [docs/DEFERRED.md](./docs/DEFERRED.md) — backlog of deferred items

---

## Current state — Session 5 in progress

As of commit `a48258e` (2026-04-23):

- **Active:** Session 5 — Universal session + participants + queue model. Part 1 complete (schema + RPCs + `shell/realtime.js` extraction). Part 2a complete (realtime event publishers). Parts 2b–2f and 3–5 pending.
- **Next up:** Part 2b — session lifecycle wiring.
- **Hydration for the next session:** Read `docs/SESSION-5-PLAN.md` (commit `2b40313`) for architecture decisions, `docs/SESSION-5-PART-2-BREAKDOWN.md` for Part 2 sub-part scope and locked decisions, and this file's later sections for working conventions. All design decisions are locked — start Part 2b directly.
- **Key references:**
  - `docs/SESSION-5-PLAN.md` — architecture decisions
  - `docs/SESSION-5-PART-2-BREAKDOWN.md` — Part 2 sub-part scope + locked decisions + "do not relitigate" list
  - `db/008`–`db/011` — schema and RPC surface (all applied in Supabase)
  - `shell/realtime.js` — publisher/listener surface including Part 2a's 5 new event publishers
- See `docs/ROADMAP.md` § Active session for the per-Part commit manifest.

---

## Architectural decisions locked (for future-session context)

Read-only guardrails — don't relitigate without strong cause.

- **Phone-as-remote model:** interactive app launcher lives on phone, not TV. TV apps grid is display-only (subtitle: "Use your phone to select an app"). See `docs/SESSION-4.10.2-PLAN.md`.
- **n=1 skip:** users with a single claimed TV auto-route past the picker into remote-control mode. Multi-TV users get the picker. Same pattern used for post-claim auto-route. See 4.10.2 plan Decision 5.
- **Single realtime channel:** `session_handoff`, `launch_app`, `exit_app` all live on `tv_device:<device_key>`. Session 5 adds more events to the same channel. Don't fork channels for new event types.
- **Await-before-navigate:** when phone publishes a realtime event before navigating via `location.href`, await the publish. Fire-and-forget drops the handshake before it completes. See commit `7b81f70`.
- **sessionStorage bridge:** cross-page device_key context uses `elsewhere.active_tv.device_key` sessionStorage. Established in 4.10.3 Part A; reused by 4.10.2 Part E follow-up.
- **In-app pages need shell/auth.js:** any page that publishes or subscribes to realtime events needs `window.sb`. Added incrementally (games/tv.html in 4.10.3 Part A; singer.html in Part B). See 4.10.3 plan Decision 8.
- **Phase 1 tolerates manual-recovery seams:** realtime failures, orphaned sessions, etc. Don't build heartbeat/reconnect layers unless customer testing surfaces real pain.

---

## Working conventions

These aren't captured in ROADMAP or DEFERRED — they're how we work together. Preserve across sessions.

- **Review-partner split:** Claude Code proposes → user pastes proposals to Claude.ai chat for review → user approves with "1" in Claude Code (never "2"). See section 3 below for the Claude.ai chat context prompt.
- **Plans before code for new sessions:** every X.Y.Z session gets a `docs/SESSION-X.Y.Z-PLAN.md` with Goal, Scope, Architecture decisions (all resolved explicitly), Parts breakdown. See section 2 below for the plan-creation prompt.
- **Small standalone commits:** one commit per logical unit (Part A, bug fix, doc update). Don't batch semantic changes with mechanical ones (version bumps, etc.).
- **Show diffs before applying:** propose as diff in chat first, apply only after explicit approval. "Yes-all-edits for this session" is acceptable shorthand for pre-approved multi-edit work.
- **~/sync-app.sh after every phone/TV-page change:** pushes changes into the iOS Capacitor wrapper at `~/Projects/elsewhere-app`. Xcode rebuild + kill/reopen on device needed to test changes on iPhone.
- **Flag before fabricating:** if a dependency, file, or behavior doesn't exist the way a plan assumes, stop and flag. Don't guess; don't add a "drive-by fix" that isn't real.
- **Close DEFERRED entries on pickup:** when a deferred item ships, update its Status line to "Completed in Session X.Y" in place. Don't delete — completed items are useful history.

---

## 1. Start the next queued session (Claude Code)

Paste this into a fresh Claude Code session when you're ready to pick up work:

```
Read docs/ROADMAP.md and identify the Active session. Then:

1. Check roadmap freshness — compare `git log -1 --format=%H docs/ROADMAP.md` against `git log -1 --format=%H` on main. If ROADMAP.md wasn't updated within 2-3 commits of HEAD, flag before continuing.

2. If the Active session has a docs/SESSION-X.X.X-PLAN.md file, read it. Confirm scope, Parts breakdown, and which Part is next (git log will show what's shipped; Parts not yet committed are the next work).

3. If no plan file exists, tell me and offer to create one using the process in NEXT-SESSION.md section 2.

4. Read docs/DEFERRED.md and surface any entries relevant to the Active session's scope. Ask whether to promote, keep deferred, or re-scope.

5. Propose a starting point — one concrete Part or task. Don't start coding yet. I'll approve or redirect.

Work pattern we've been using:
- Propose changes as diffs before writing
- One file at a time, pause for review
- Sequential Part commits, not batched
- I approve each tool prompt individually

Confirm you've read the plan + roadmap state before proposing a start.
```

---

## 2. Create a session plan when none exists (Claude Code)

Paste when ROADMAP.md's Active session has no plan file yet:

```
The Active session per docs/ROADMAP.md has no docs/SESSION-X.Y.Z-PLAN.md yet. Create one.

Use docs/SESSION-4.10.2-PLAN.md as the structural template. Sections: Goal, Scope (in/out, with DEFERRED refs), Architecture decisions (each one answered explicitly — no open questions), Data model, Parts breakdown (A/B/C... each a pause-point), Verification approach, Deferred items likely to emerge, Open questions for implementation (should resolve to "None" after you decide everything), Related existing architecture.

Process:
1. Read docs/ROADMAP.md to get the session's "Why" line and estimated scope.
2. Read every docs/DEFERRED.md entry that ROADMAP references for this session, plus any adjacent entries you'd fold in.
3. Make architecture decisions concretely. If a decision has tradeoffs, pick one with rationale — don't punt to "TBD" or "decide during implementation."
4. Draft the plan. Show it to me before writing the file. To show before writing: produce the full plan text in your response message, not as a Write call yet. I'll approve explicitly before you call the Write tool.
5. For any DEFERRED entries that get folded into this session's scope, mark them as "Folded into Session X.Y.Z scope" with strikethrough + preservation note — don't delete history.

No code yet. This is planning only.
```

---

## 3. Catch up a Claude.ai chat (review partner)

Paste into a fresh Claude.ai (web UI) chat when starting a new review partner for the session:

```
Context: I'm working on a project called Elsewhere in parallel across two tools. In Claude Code (CLI) I have the repo open and an agent actively proposing diffs. Here (Claude.ai chat) you're my review partner — I paste Claude Code's proposed changes/plans to you before I approve them, and you check the work.

Repo: https://github.com/mstepanovich-web/elsewhere
Branch: main
As of NEXT-SESSION.md being authored, most recent commit was 8e493ce. This will drift; check main for current state when I ask.

Your job in this chat:
- When I paste a proposed diff, code, or plan from Claude Code, review it against the active plan + common-sense correctness. Flag bugs, scope creep, plan divergence, or risky choices before I approve.
- Workflow pattern: Claude Code proposes → I paste here → you review → I hit 1 (approve) in Claude Code, never 2 (reject).
- Review for bugs, scope creep, plan divergence, and risky choices. Don't nitpick style.

When I ask you to check against a plan or backlog entry, I'll either paste the relevant doc contents directly into chat, or give you the raw GitHub URL (raw.githubusercontent.com/...) which you can web_fetch. The GitHub URL pattern for main branch is:
https://raw.githubusercontent.com/mstepanovich-web/elsewhere/main/<path>
Don't assume you've read the docs — ask me to paste them if needed.

Wait for me to paste the first proposal.
```

---

## Session-end ritual

Before the final session commit, update docs/ROADMAP.md:

1. Move the completed session from **Active session** to a new **## Completed sessions** section at the bottom (create the section if it doesn't exist). Preserve the entry with a completion date and final commit SHA.
2. Promote the top entry from **Queued sessions** into **Active session**.
3. If new deferred items emerged, confirm they're captured in docs/DEFERRED.md before closing the session.
4. Commit all roadmap + DEFERRED updates as part of the session's final commit (usually the Part G version-bump commit or equivalent closing commit). Don't leave them dangling for the next session to discover.

---

## Open items for Session 5 closeout

When Session 5 fully closes (after Parts 2–5 ship), update `docs/ROADMAP.md` to include a "Future work / Triggered" section referencing:

- DEFERRED `087923a` — Venues as cross-app service (trigger: wellness app start OR games visual parity priority)
- Other DEFERRED entries that are architecture (not bugs) worth surfacing at ROADMAP level

Rationale: DEFERRED is archaeology; ROADMAP is where next work gets planned. Converting persistent-architecture DEFERRED entries to ROADMAP pointers at session close ensures they surface when planning next sessions.
