# Elsewhere docs/

This directory holds the project's accumulated documentation: control models,
session logs, audits, plans, and the kickoff context.

## For new chats with Claude

**Always start a new chat by pasting `CONTEXT.md`.**

```bash
cat ~/Downloads/elsewhere-repo/docs/CONTEXT.md | pbcopy
```

Then paste into the new chat as the first message, followed by a one-line
description of today's task.

`CONTEXT.md` is the single source of truth for the project's mental model,
doctrine, current state, and pointers to deeper docs. Without it, every new
chat reconstructs the model from scratch and drifts.

For complex multi-domain tasks, append the relevant deeper doc(s). See "Doc
Bundle Recipes" below.

## Doc Bundle Recipes

Match the task to a recipe and paste the resulting bundle. CONTEXT.md is
always included — it's the foundation. The other docs add task-specific
depth.

### Default (most tasks)

When in doubt, this is enough:

```bash
cat ~/Downloads/elsewhere-repo/docs/CONTEXT.md | pbcopy
```

Use for: small fixes, conventions questions, navigation, "what's the state
of X?", anything where Claude needs the mental model but not deep specs.

### Karaoke session work — manager UI, queue management, role transitions

For 2e.3 and any subsequent karaoke session work that touches roles,
queues, manager actions, or singer.html surfaces:

```bash
cat ~/Downloads/elsewhere-repo/docs/CONTEXT.md \
    ~/Downloads/elsewhere-repo/docs/SESSION-5-PART-2E-AUDIT.md \
    ~/Downloads/elsewhere-repo/docs/KARAOKE-CONTROL-MODEL.md \
    ~/Downloads/elsewhere-repo/docs/SESSION-5-PART-2E2-LOG.md \
    | pbcopy
```

Why these four:
- **CONTEXT.md** — mental model + doctrine + current state
- **SESSION-5-PART-2E-AUDIT.md** — phase spec (2e.0 through 2e.3 scope)
- **KARAOKE-CONTROL-MODEL.md** — § 4.x role rendering rules, § 5.2 work item list
- **SESSION-5-PART-2E2-LOG.md** — what shipped, what's broken, what's pending (especially TV app-launch realtime issue, direct-SQL-doesn't-publish gotcha)

### Push notification debugging

For anything touching APNs, push tokens, the trigger, or the Edge Function:

```bash
cat ~/Downloads/elsewhere-repo/docs/CONTEXT.md \
    ~/Downloads/elsewhere-repo/docs/SESSION-5-PART-2E0-LOG.md \
    ~/Downloads/elsewhere-repo/docs/SESSION-5-PART-2E2-LOG.md \
    | pbcopy
```

Why these three:
- **CONTEXT.md** — architecture overview including APNs and Edge Function pieces
- **SESSION-5-PART-2E0-LOG.md** — push token registration model, sandbox cert details, original auth model
- **SESSION-5-PART-2E2-LOG.md** — full trigger architecture, auth-handshake recovery, `--no-verify-jwt` requirement, `pg_net._http_response` diagnostic

### Games work — Trivia, Last Card, Euchre, new game

For touching `games/` or adding a new game:

```bash
cat ~/Downloads/elsewhere-repo/docs/CONTEXT.md \
    ~/Downloads/elsewhere-repo/docs/ROADMAP.md \
    ~/Downloads/elsewhere-repo/docs/DEFERRED.md \
    | pbcopy
```

Plus any games-specific session log if one exists.

(There's no canonical "games control model" doc yet — if games work expands,
consider creating one.)

### Adding a new app or surface — Wellness, Room Mode, etc.

For high-level architectural work or starting a new product surface:

```bash
cat ~/Downloads/elsewhere-repo/docs/CONTEXT.md \
    ~/Downloads/elsewhere-repo/docs/ROADMAP.md \
    ~/Downloads/elsewhere-repo/docs/SESSION-5-PART-2-BREAKDOWN.md \
    ~/Downloads/elsewhere-repo/docs/PHONE-AND-TV-STATE-MODEL.md \
    | pbcopy
```

Why:
- **CONTEXT.md** — architecture overview
- **ROADMAP.md** — long-term plan, where new apps fit
- **SESSION-5-PART-2-BREAKDOWN.md** — broader Session-5 context, multi-app patterns
- **PHONE-AND-TV-STATE-MODEL.md** — claim/registration/presence patterns, useful for any new surface

### Picking up a session mid-thread (rare)

If you're resuming work on something specific that's actively in flight
and the most recent session log is the canonical state:

```bash
cat ~/Downloads/elsewhere-repo/docs/CONTEXT.md \
    ~/Downloads/elsewhere-repo/docs/SESSION-5-PART-2E2-LOG.md \
    | pbcopy
```

Replace the session log filename with whichever is the most recent.

### Roadmap or planning question

For questions like "what's after Session 5?" or "when is feature X coming?":

```bash
cat ~/Downloads/elsewhere-repo/docs/CONTEXT.md \
    ~/Downloads/elsewhere-repo/docs/ROADMAP.md \
    ~/Downloads/elsewhere-repo/docs/DEFERRED.md \
    | pbcopy
```

CLAUDE.md doctrine: roadmap questions get answered from these docs, not
from estimation. If the question can't be answered from them, it's a real
gap to surface.

---

## Doc inventory

### Always-current
- `CONTEXT.md` — The kickoff doc. Mental model + doctrine + current state. Update at end of every session.

### Models (stable)
- `KARAOKE-CONTROL-MODEL.md` — Roles, transitions, surfaces for karaoke
- `PHONE-AND-TV-STATE-MODEL.md` — Claim, registration, presence
- `KARAOKE-FUNCTION-AUDIT.md` — Function-level audit of singer.html
- `INDEX.md` — Doc index
- `ROADMAP.md` — Long-term plan

### Plans (per session)
- `SESSION-5-PLAN.md` — Session 5 master plan
- `SESSION-5-HANDOFF.md` — Handoff between sub-sessions
- `SESSION-5-PART-2-BREAKDOWN.md` — Part 2 sub-phases
- `SESSION-5-PART-2D-AUDIT.md` — Part 2d audit
- `SESSION-5-PART-2E-AUDIT.md` — Part 2e audit
- `SESSION-5-PART-2E-MODEL-AUDIT.md` — Eligibility model decisions
- `SESSION-4.10-PLAN.md`, `SESSION-4.10.2-PLAN.md`, `SESSION-4.10.3-PLAN.md` — Session 4 plans
- `SESSION-4.10.3-VERIFICATION.md` — Session 4.10.3 verification
- `PART-E-VERIFICATION.md` — Part E verification

### Session logs (append-only)
- `SESSION-5-PART-2E0-LOG.md` — Push infrastructure shipped
- `SESSION-5-PART-2E2-LOG.md` — Self-write actions + push trigger
- (future) `SESSION-5-PART-2E3-LOG.md` — Manager UI

### Misc
- `DEFERRED.md` — Backlog of deferred items

## When to update what

| File | Updated when |
|---|---|
| `CONTEXT.md` mental-model section | A core architectural fact changes (rare) |
| `CONTEXT.md` doctrine section | A new locked decision is made |
| `CONTEXT.md` current-state section | End of every session |
| `CONTEXT.md` doc-pointer table | A new doc is added or a session log lands |
| Session log (new file) | Created at end of every session |
| `DEFERRED.md` | When something gets surfaced but deferred |
| Model docs | When the model itself changes (rare) |
| Plan docs | When plans change (or close at end of session) |
| `docs/README.md` bundle recipes | When a new task type emerges that needs its own bundle |
