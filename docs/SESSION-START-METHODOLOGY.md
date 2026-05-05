# Session Start Methodology

Last updated: 2026-05-04

> This doc is the canonical process for kicking off a work session with a fresh Claude. Paste this into the chat at session start to orient Claude before any work begins. Companion to `docs/SESSION-CLOSING-METHODOLOGY.md` (which closes out a session).

## Why this exists

The doc structure is comprehensive but pull-based — Claude reads nothing unless told. Without an explicit kickoff, Claude pattern-matches to vague training-data assumptions about Elsewhere, gets the model wrong, and the first 30 minutes of every session is spent on context correction instead of work.

Concrete failure modes this prevents:

- Claude assuming wrong things about the user model (audience vocabulary trap, HHU eligibility, Way 1 / Way 2 dual-mode)
- Claude proposing work that's already shipped (because Latest shipped wasn't read)
- Claude proposing work that's deferred for good reason (because DEFERRED.md wasn't read)
- Claude inventing a Session 6 that doesn't match ROADMAP.md (because ROADMAP.md wasn't read)
- Claude skipping CLAUDE.md doctrine and shipping with wrong patterns (Edge Function deploy flags, iOS sync ritual, migrations doctrine)

## The minimum viable kickoff (always paste)

Two docs go into every chat at session start, regardless of scenario:

1. `docs/CONTEXT.md` — project mental model, latest shipped, active deferred items, up next, doc-references table. ~5KB.
2. `docs/ROADMAP.md` — sequenced session plan with hard ordering and per-session canonical-doc references. ~10KB.

Combined: ~15KB of paste, ~3 minutes of Claude reading time. This gets a fresh Claude to "I understand Elsewhere and I know what's queued and why" before any work begins.

## Scenario-specific doc additions

Beyond the minimum, add docs based on what today's work involves:

### Scenario 1: Continuing yesterday's work (most common)

Add the most recent closing log + verification log:

- `docs/SESSION-N-PART-XX-CLOSING-LOG.md` (latest)
- `docs/SESSION-N-PART-XX-VERIFICATION-LOG.md` (latest)

These provide forensic detail of what shipped most recently and what's pending verification. As of 2026-05-04 the latest pair is `docs/SESSION-5-PART-3B-CLOSING-LOG.md` + `docs/SESSION-5-PART-3B-VERIFICATION-LOG.md`.

### Scenario 2: Starting a new track

Add the canonical doc for that track per ROADMAP.md's session entry. Common cases:

- Trivia 3b proper / Last Card 3c / Euchre 3d → `docs/GAMES-CONTROL-MODEL.md` § 4.1
- Session 6 (SMS pre-invites) → `docs/DEFERRED.md` entry "Phone-based household pre-invites"
- Session 9 (audience.html unification) → `docs/KARAOKE-CONTROL-MODEL.md` § 5.5
- Session 10 (venues at platform level) → `docs/DEFERRED.md` entry "Venues as cross-app service"
- Session 12 (wellness app implementation) → `docs/SESSION-5-PLAN.md` (wellness placeholder mention) + relevant control model docs

ROADMAP.md's per-session entries name the canonical doc. Read ROADMAP.md first, then fetch the named doc.

### Scenario 3: Triaging / planning

Add `docs/DEFERRED.md` (the deferred work inbox, ~30-40KB). Heavyweight but it's the source of truth for backlog. Worth it when deciding what to do today.

## The kickoff template

Copy the block below into chat at session start. Fill in today's task, paste the docs in the marked positions:

```
Continuing Elsewhere development. Project context below.

Today's task: [one sentence describing what you want to work on, e.g., "Hardware verify v2.113 on iPhone Safari, then start Trivia 3b proper"]

Before doing any work:
1. Read this CONTEXT.md and ROADMAP.md to grok current state.
2. Read CLAUDE.md from the repo for coding doctrine (Edge Function deploy flags, iOS sync ritual, migrations doctrine, etc.).
3. If today's task involves a specific track, read the canonical doc named in ROADMAP.md for that session.

[paste docs/CONTEXT.md]

---

[paste docs/ROADMAP.md]

---

[optional: paste latest closing log + verification log if continuing yesterday's work]

---

[optional: paste docs/DEFERRED.md if triaging / planning]
```

## Why "Read CLAUDE.md" is an instruction, not a paste

CLAUDE.md is large (~hundreds of lines of doctrine — Edge Function deploy flags, iOS Capacitor sync ritual, migrations doctrine, end-of-session ritual, etc.). Pasting it every time would 4x the kickoff size. Instead, instruct Claude to read it from the repo (via the Read tool) before doing any code work. The instruction is enforcement: Claude actually fetches and reads the file.

This is the same pattern as `docs/SESSION-CLOSING-METHODOLOGY.md`'s "Read [these docs] in step N" instructions — a directive backed by a tool call, not a content paste.

## Common failure modes and corrections

### Failure: starting code work before reading docs

**Symptom:** Claude proposes a fix or feature that contradicts shipped doctrine, deferred items, or current architectural decisions.

**Correction:** when Claude proposes anything before confirming it's read CONTEXT.md, ROADMAP.md, and (for code) CLAUDE.md, push back: "Have you read CONTEXT.md and CLAUDE.md? What do they say about [the relevant doctrine]?"

### Failure: Claude doesn't know what shipped most recently

**Symptom:** Claude proposes work that's already done or proposes a different approach than what shipped.

**Correction:** paste the latest CLOSING-LOG + VERIFICATION-LOG into the kickoff. Don't rely on CONTEXT.md's "Latest shipped" paragraph alone — it's a summary, not the forensic detail.

### Failure: Claude invents Session 6 / 7 / etc. without checking ROADMAP.md

**Symptom:** Claude proposes a different post-Session-5 ordering than what's documented in ROADMAP.md (e.g., starts wellness work without checking that Sessions 9 + 10 are prerequisites).

**Correction:** ROADMAP.md is canonical for queued sessions. If Claude's proposal doesn't match, ask: "Does this match ROADMAP.md's hard ordering? What does Session 9 say about its prerequisites for Session 12?"

### Failure: Claude doesn't apply CLAUDE.md doctrine

**Symptom:** Claude proposes deploying an Edge Function with the wrong `--no-verify-jwt` flag, or skips the iOS Capacitor sync ritual at session close.

**Correction:** when Claude proposes any deploy or session-closing action, ask: "What does CLAUDE.md say about [Edge Function flags / iOS sync ritual / migrations / etc.]?" If Claude hasn't read CLAUDE.md, that's the gap.

### Failure: Claude doesn't grasp the audience vocabulary trap

**Symptom:** Claude refers to "audience" without disambiguating between schema-state `'audience'` (database enum value, includes Available Singers + actual non-singing audience) and surface-label "Audience" (UI role, watching only, can't sing).

**Correction:** this is in CONTEXT.md "Critical vocabulary trap" section. If Claude conflates them, paste the relevant CONTEXT.md section back and ask Claude to re-read.

## How this doc evolves

When the kickoff process needs to change (new doc shape surfaces, new step needed, new failure mode worth documenting):

- Update this doc directly
- The update IS the canonical methodology going forward
- Past sessions remain consistent with whatever methodology was in effect at their time

## Companion doc

This doc handles session start. Its mirror is `docs/SESSION-CLOSING-METHODOLOGY.md`, which handles session close. Together they bracket the work session: paste this at start, paste the companion at close.

Both docs stand alone — they're not referenced from `CLAUDE.md` or `docs/CONTEXT.md`. Mike controls when to invoke each by pasting into chat at the appropriate boundary.
