# Elsewhere — Docs Index

This is an index of all docs in this directory. New Claude sessions: read this first, then fetch the docs relevant to your task. Update this file when adding/removing/renaming docs.

Reading order for orientation in any active Session 5 work:
1. [ROADMAP.md](./ROADMAP.md) — current pipeline, where work stands
2. [SESSION-5-HANDOFF.md](./SESSION-5-HANDOFF.md) — resumable handoff brief
3. [PHONE-AND-TV-STATE-MODEL.md](./PHONE-AND-TV-STATE-MODEL.md) + [KARAOKE-CONTROL-MODEL.md](./KARAOKE-CONTROL-MODEL.md) — canonical specs

---

## Active session — Session 5 (Universal session + participants + queue)

| Doc | Purpose | Last updated |
|---|---|---|
| [SESSION-5-HANDOFF.md](./SESSION-5-HANDOFF.md) | Self-contained handoff brief for resuming Session 5 Part 2d in a fresh chat. Status table, open-decisions resolution, resume opener. | `15f1ff3` 2026-04-25 |
| [SESSION-5-PART-2-BREAKDOWN.md](./SESSION-5-PART-2-BREAKDOWN.md) | Sub-part-by-sub-part scope for Session 5 Part 2 (Karaoke integration). 2a–2c shipped; 2d/2e/2f re-scoped per Karaoke Control Model. | `4f5966f` 2026-04-25 |
| [SESSION-5-PLAN.md](./SESSION-5-PLAN.md) | Parent design doc for Session 5 — universal session/participants/queue schema replacing ad-hoc room codes. Part 1 of 5 complete; Part 2 in progress. | `5b7fe26` 2026-04-24 |
| [ROADMAP.md](./ROADMAP.md) | High-level session pipeline so context isn't lost between sessions. **NOTE: as of `cdc36be`, last updated `05be73f` 2026-04-23 — drifted; needs refresh.** | `05be73f` 2026-04-23 |

## Platform model and specs (canonical references)

| Doc | Purpose | Last updated |
|---|---|---|
| [PHONE-AND-TV-STATE-MODEL.md](./PHONE-AND-TV-STATE-MODEL.md) | Canonical reference for phone/TV behavior across user contexts. Defines HHU/NHHU/HHM, Modes A/B/C, TV state machine, proximity model, Back-to-Elsewhere rule. Wins on conflicts. | `591796b` 2026-04-25 |
| [KARAOKE-CONTROL-MODEL.md](./KARAOKE-CONTROL-MODEL.md) | Karaoke-specific spec: role hierarchy (Session Manager, Active Singer, Available Singer, Audience), state machine, permission matrix, UI surfaces, implementation mapping for Session 5 Part 2d/2e/2f. | `b7d4e70` 2026-04-25 |

## Reference / audit

| Doc | Purpose | Last updated |
|---|---|---|
| [KARAOKE-FUNCTION-AUDIT.md](./KARAOKE-FUNCTION-AUDIT.md) | Pure-description inventory of `karaoke/singer.html` and `karaoke/stage.html` functionality (pre-2d, single-singer model). Used as input to the Karaoke Control Model spec work. No recommendations. | `4886241` 2026-04-25 |

## Backlog

| Doc | Purpose | Last updated |
|---|---|---|
| [DEFERRED.md](./DEFERRED.md) | Single canonical place for every item deferred across sessions. Append-only. Read at session start to surface relevant items before planning. | `dc99039` 2026-04-25 |

## Historical / completed session plans

| Doc | Purpose | Status | Last updated |
|---|---|---|---|
| [SESSION-4.10-PLAN.md](./SESSION-4.10-PLAN.md) | Plan for the household + TV device registration model (Parts A–E). Shipped through v2.99. Replaced the `?dev=1` email+password bridge with proper auth. | Shipped | `38e9d3e` 2026-04-21 |
| [SESSION-4.10.2-PLAN.md](./SESSION-4.10.2-PLAN.md) | Plan for the phone-as-remote UX fix (forward path: phone tile-tap → TV navigates to app). Shipped. | Shipped | `1b94907` 2026-04-21 |
| [SESSION-4.10.3-PLAN.md](./SESSION-4.10.3-PLAN.md) | Plan for phone Back-to-Elsewhere + coordinated TV teardown (reverse path of 4.10.2). audience.html scope deferred to Session 5. Shipped through Part C. | Shipped (audience deferred at the time) | `97014c2` 2026-04-22 |
| [SESSION-4.10.3-VERIFICATION.md](./SESSION-4.10.3-VERIFICATION.md) | End-to-end verification record for Session 4.10.3 commits. Hardware-tested through commit `40e4f4b`. | Verified | `1416c52` 2026-04-22 |
| [PART-E-VERIFICATION.md](./PART-E-VERIFICATION.md) | End-to-end verification record for Session 4.10's household + TV claim flow. PARTIAL verdict — Flows 1, 2, 5 PASS; Flows 3, 4 deferred. | Partial — Flows 3/4 in DEFERRED | `e7952ae` 2026-04-21 |

---

## How to update this index

When you **add** a doc to `docs/`:
- Add a row to the appropriate category table
- Include filename (linked), one-line purpose extracted from the doc itself (don't paraphrase), last-update commit + date
- If the new doc's category doesn't fit, add a new category section

When you **rename** a doc:
- Update the filename + link in this index
- If the doc's purpose/scope changed materially, refresh the one-liner

When you **archive or supersede** a doc:
- Move its row to "Historical / completed session plans" and update Status column
- Add a brief note in the Status column explaining what supersedes it (or what it shipped)

When you **delete** a doc:
- Remove its row from this index
- Verify nothing else in the docs cross-references it

Keep entries to one line each. This file is a navigation aid, not a summary doc — full content lives in each doc.
