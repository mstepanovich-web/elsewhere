# Session Closing Methodology

Last updated: 2026-05-04

> This doc is the canonical process for closing out a work session and updating the docs consistently. Paste this at the end of any session before declaring done.

## Why this exists

Every session ships work and surfaces lessons. The Claude session ends; the lessons evaporate unless persisted in the right docs. This methodology specifies what gets persisted where, so a fresh Claude in the next session can pick up cleanly without re-discovering the structure.

Concrete failure mode this prevents: dumping per-commit forensic detail into `docs/CONTEXT.md` (the kickoff doc), making it bloated and harder for fresh Claude to grok current state. Forensic detail belongs in per-session closing logs, not the kickoff doc.

## The five core docs and what each is for

### `docs/CONTEXT.md` — Fresh-Claude kickoff doc

- **Purpose:** Pasted at the start of every new chat. Gives fresh Claude the mental model in 2 minutes.
- **Update cadence:** End of every session (Latest shipped, Active deferred items, Up next sections); rarely for mental model and doctrine.
- **Content shape:** Mental model, locked doctrine, repo layout, paragraph-level summaries with pointers to deeper docs.
- **DOES contain:** Latest shipped (paragraph + pointer to closing log); Active deferred items (categorical with pointer to DEFERRED.md); Up next (Near-term + Medium-term hard-ordered with pointer to ROADMAP.md); doc-references table.
- **DOES NOT contain:** Per-commit forensic detail; per-flow verification audit trail; full DEFERRED enumeration; full ROADMAP detail.

### `docs/ROADMAP.md` — Sequenced session plan

- **Purpose:** Single source of truth for what ships in what order across sessions.
- **Update cadence:** End of every session (Active session status); whenever new sessions are queued or completed.
- **Content shape:** Active session, Queued sessions (hard-ordered), Completed sessions (chronological history), Smaller items, Architecture notes.
- **DOES contain:** Per-session entries with why, estimated, dependencies, references to canonical docs; Active session what's-left list.
- **DOES NOT contain:** Per-commit forensic detail (that's in closing logs); strategic conversations about post-roadmap work.

### `docs/DEFERRED.md` — Deferred work inbox

- **Purpose:** Items filed to address later. Anything not in this inbox is functionally lost.
- **Update cadence:** End of every session (new items + status updates on resolved items).
- **Content shape:** Per-item entries with priority labels (High/Medium/Low/N/A), what/why/work/references.
- **DOES contain:** Bugs not fixed; polish items deferred; migration items waiting for trigger; cross-cutting items.
- **DOES NOT contain:** In-flight session work (that's in ROADMAP Active session); shipped work (that's in ROADMAP Completed sessions or closing logs).

### `CLAUDE.md` — Coding doctrine

- **Purpose:** How to write code in this repo. Locked rules.
- **Update cadence:** Rarely. Only when a doctrine becomes locked.
- **Content shape:** Doctrine bullets, end-of-session ritual checklist, locked patterns.
- **DOES contain:** Edge Function deploy flags, iOS sync ritual, migrations doctrine, the basic 5-step end-of-session checklist.
- **DOES NOT contain:** This methodology doc (kept separate so it can stand alone for paste-into-chat use); strategic plan content.

### Session-specific logs

Two flavors per major sub-part:

#### `docs/SESSION-N-PART-XX-CLOSING-LOG.md` — Forensic detail of what shipped

- **Purpose:** The audit trail of what was done, why, and how it was tested.
- **Update cadence:** Created at session/sub-part close. Mostly written-once.
- **Content shape:** Sub-part status table, "What shipped" narrative per commit, resolved investigations, hardware verification summary with pointer, Capacitor caveat, deferred items, doctrine updates, next session entry point.
- **Examples:** `docs/SESSION-5-PART-3-CLOSING-LOG.md`, `docs/SESSION-5-PART-3B-CLOSING-LOG.md`.

#### `docs/SESSION-N-PART-XX-VERIFICATION-LOG.md` — Hardware verification audit trail

- **Purpose:** Per-commit verification record (what was verified, on what device, with what result).
- **Update cadence:** Created when hardware verification happens; appended to as more rounds happen.
- **Content shape:** Header (date, pre/post-verification commits), summary, per-commit verification table (statuses: ✅ GREEN / 🟡 PARTIAL / 🟡 PENDING / 🟡 DEFERRED), test environments (devices, accounts, UIDs, API key digests if rotated), bugs surfaced and fix-forward record, migrations applied (with verification queries), Edge Function deployment record (when applicable), net assessment, operational notes.
- **Examples:** `docs/SESSION-5-PART-3A2-VERIFICATION-LOG.md`, `docs/SESSION-5-PART-3B-VERIFICATION-LOG.md`.

## The session-closing process

At the end of every session, work through this checklist in order:

### 1. Hardware verify the latest commits

Run any pending hardware verification. If anything is GREEN, note in the verification log. If anything is FAILING, fix-forward before continuing closeout. If anything is DEFERRED-by-design (e.g., environmental constraints — like 4-player Euchre with only 2 test devices), document the deferral with a clear analog and confidence framing.

### 2. Create or append to `docs/SESSION-N-PART-XX-CLOSING-LOG.md`

Capture forensic detail of what shipped:

- Sub-part status table at top (mirrors prior closing log format — see `docs/SESSION-5-PART-3-CLOSING-LOG.md` for the canonical shape)
- "What X delivered" narrative section per major track, with per-commit forensic detail (commit SHA, version stamp if applicable, what changed and why, what was preserved)
- Resolved investigations during the session (informational, no action required)
- Hardware verification summary (one paragraph + pointer to verification log)
- Capacitor caveat (current iOS bundle status; reference to CLAUDE.md ritual)
- What's deferred to next session (gate items + tracks queued)
- Doctrine updates this session
- Next session entry point (recommendation for what to pick up first)

### 3. Create or append to `docs/SESSION-N-PART-XX-VERIFICATION-LOG.md`

Capture hardware verification audit trail:

- Header with date, pre-verification commit, post-verification commits in chronological order
- Summary noting verification approach (final-gate vs verify-after-each-commit)
- Per-commit verification table with ✅ GREEN / 🟡 PARTIAL / 🟡 PENDING / 🟡 DEFERRED status, test sessions, observations
- Test environments (devices, accounts, UIDs, API key digests if rotated mid-session)
- Bugs surfaced and fix-forward record (which bug filed → which commit resolved)
- Migrations applied (with the SQL queries used for verification)
- Edge Function deployment record (when applicable; include deploy command + flags + post-deploy verification)
- Net assessment paragraph
- Operational notes (anything procedurally surprising worth flagging — e.g., API key rotation mid-session)

### 4. Update `docs/CONTEXT.md`

- **"Latest shipped" section:** replace with paragraph-level summary + pointer to the new closing log + verification log. NOT per-commit forensic detail.
- **"Active deferred items" section:** update categorical pointers to DEFERRED.md (don't enumerate items inline).
- **"Up next" section:** keep Near-term + Medium-term tiering; sync with ROADMAP.md changes.
- **Doc-references table:** add entries for the new closing log + verification log.
- **"Hardware verification status" section:** paragraph + pointer to verification log.

### 5. Update `docs/ROADMAP.md`

- **"Active session" entry:** update status line; update what's-left list if applicable. The what's-left list is the canonical tactical view — keep it in execution order with one-line descriptions and references.
- **"Queued sessions":** adjust if new dependencies surfaced.
- **"Completed sessions":** move sessions here if they fully closed.

### 6. Update `docs/DEFERRED.md`

- File new items surfaced during the session.
- Mark resolved items as **Resolved DATE in commit `SHA`** with brief inline note.
- Update partial-mitigation status for items partially addressed (use the **Partially mitigated DATE in COMMIT** pattern; don't fully close).
- For SHA references in the body that won't be known until commit lands, use `SHA-PLACEHOLDER` literal and substitute via a follow-up doc-only commit.

### 7. iOS Capacitor sync (if user-facing changes shipped)

Per CLAUDE.md "iOS Capacitor sync — session-closing ritual": run the 5-step sync chain, smoke-test natively, note bundle version in closing log.

Skip only when: docs-only commits, OR explicitly deferred with a tracked DEFERRED entry.

### 8. Final check

- Re-read `docs/CONTEXT.md` fresh-Claude-style: should grok current state in 2 minutes.
- Confirm all four docs (CONTEXT, ROADMAP, DEFERRED, CLOSING-LOG) point to each other appropriately.
- Confirm working tree is clean (no untracked artifacts beyond known persistent ones).
- Confirm local HEAD == origin/main.

## Decision framework: what goes where

When facing the question "where should this content live?":

- Is it a paragraph-level summary that fresh Claude needs to grok current state? → `docs/CONTEXT.md`
- Is it forensic detail (per-commit, architectural decisions, doctrine updates)? → CLOSING-LOG
- Is it hardware verification (test sessions, gate items, fix-forward record)? → VERIFICATION-LOG
- Is it a future work item that's not in flight? → `docs/DEFERRED.md`
- Is it a queued session or sequencing decision? → `docs/ROADMAP.md`
- Is it a coding doctrine that should govern future work? → `CLAUDE.md`
- Is it strategic / architectural context for a specific subsystem? → `docs/KARAOKE-CONTROL-MODEL.md`, `docs/GAMES-CONTROL-MODEL.md`, `docs/PHONE-AND-TV-STATE-MODEL.md`, etc.

The same content should not appear in multiple docs. Pick the canonical home, reference from elsewhere.

## Common mistakes and corrections

### Mistake: dumping per-commit forensics into CONTEXT.md "Latest shipped"

**Symptom:** CONTEXT.md grows to ~25 lines per commit; fresh-Claude paste takes 5+ minutes to grok current state.

**Correction:** Per-commit detail goes in CLOSING-LOG. CONTEXT.md "Latest shipped" should be paragraph-level summary + pointer.

**Real example:** 2026-05-04 closeout commit `0d9357b` made this mistake; restructure commit `a4f88f5` fixed it by extracting `docs/SESSION-5-PART-3B-CLOSING-LOG.md` and trimming CONTEXT.md.

### Mistake: enumerating DEFERRED items in CONTEXT.md "Active deferred items"

**Symptom:** CONTEXT.md duplicates DEFERRED.md content; updates to DEFERRED.md silently drift from CONTEXT.md.

**Correction:** CONTEXT.md surfaces categorical pointers (e.g., "Trivia Phase 2 polish — three items in DEFERRED.md"); DEFERRED.md is the source of truth for full enumeration.

### Mistake: filing items only in session logs, not in DEFERRED.md

**Symptom:** Items mentioned during a session evaporate; future Claude has no way to find them.

**Correction:** Anything not yet shipped goes in DEFERRED.md. Session logs reference DEFERRED entries; they don't replace them.

### Mistake: skipping the iOS Capacitor sync at session close

**Symptom:** iOS bundle drift compounds across sessions; eventual sync becomes a multi-week-of-changes-at-once update with attribution issues (any surfaced bug could plausibly trace back to any of dozens of commits).

**Correction:** Per CLAUDE.md ritual, run the 5-step sync chain at every session close that ships user-facing changes. Skip only for docs-only sessions, AND file a tracked DEFERRED entry naming the trigger for catch-up if deferring.

**Real example:** the iOS bundle drifted from v2.99 to v2.113 across ~3 weeks of Sessions 3a → 3b productionization → Phase 2. The 2026-05-04 session-closing commits filed a DEFERRED entry (`b2cc96e`) tracking the catch-up + formalized the ritual (`3164524`) preventing future drift.

### Mistake: declaring "we're done" without working through this checklist

**Symptom:** Items not filed in DEFERRED; CONTEXT.md not updated; ROADMAP.md drifts; next session pays the cost.

**Correction:** At "we're done," start at step 1 of the checklist. The checklist is cheap (~30-60 minutes for a productive session); skipping is expensive (every future session pays for the gap).

## Reference: today's commits as concrete examples

Today's session (2026-05-04) is a worked example of this methodology in action (mostly — the bloated initial closeout at `0d9357b` was the catalyst for this doc, and the corrective sequence follows). The session-closing sequence:

1. **Restructure commit `a4f88f5`** — created `docs/SESSION-5-PART-3B-CLOSING-LOG.md` + `docs/SESSION-5-PART-3B-VERIFICATION-LOG.md`; trimmed CONTEXT.md "Latest shipped" + "Hardware verification status" to paragraph summaries with pointers.
2. **ROADMAP restructure commit `08a22ef`** — Sessions 6→12 with hard ordering and canonical doc references.
3. **iOS Capacitor sync ritual commit `3164524`** — formalized at CLAUDE.md "End-of-session ritual" + CONTEXT.md "Locked doctrine" pointer.
4. **DEFERRED entry commit `b2cc96e`** — Session 5 closeout iOS bundle catch-up sync (filed for next session pickup).
5. **ROADMAP "Active session" expansion commit `8131547`** — explicit Session 5 what's-left list visible by name.
6. **THIS commit** — formalize the methodology itself.

Mirror this shape going forward.

## How to use this doc

At the end of any session:

1. Paste this doc into the chat
2. Tell Claude: "Apply the session-closing methodology"
3. Claude works through the checklist, asks clarifying questions where needed
4. Each step gets a small commit with a clear scope
5. Final commits land before declaring done

When the methodology evolves (new doc shape surfaces, new step needed):

- Update this doc directly
- The update IS the canonical methodology going forward
- Past sessions remain consistent with whatever methodology was in effect at their time

This doc stands alone — it's not referenced from `CLAUDE.md` or `docs/CONTEXT.md`. Mike controls when to invoke it by pasting it into the chat at session close.
