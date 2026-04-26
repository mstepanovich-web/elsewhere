# Session 5 Handoff Brief

**Written:** 2026-04-25
**Last updated:** 2026-04-26 (Karaoke Control Model landed; 2d/2e/2f re-scoped)
**Last commit reviewed:** `4f5966f` (docs: re-scope 2d/2e/2f per Karaoke Control Model)
**Purpose:** Self-contained context for resuming Session 5 Part 2d in a fresh Claude.ai chat.
**Spec source for 2d/2e/2f:** `docs/KARAOKE-CONTROL-MODEL.md` (commit `b7d4e70`). Scope, role hierarchy, UI surfaces, and implementation mapping all live there.

---

## Current state — Session 5 Part 2 (2a, 2b, 2c all shipped; spec landed for 2d/2e/2f)

| Sub-part | Code commit | Scope |
|---|---|---|
| 2a | `d1b4edd` | 5 new publishers in `shell/realtime.js` |
| 2b | `601d125` | Session lifecycle wiring (index + tv2 + stage + games/tv) |
| 2c.1 | `daa8718` | User preferences storage (`db/012` + `shell/preferences.js`) |
| 2c.2 | `0a3a9ea` | Post-login home unification + proximity banner |
| 2c.3.1 | `e4a348e` | Active-session rendering + rejoin + cross-app switch |
| 2c.3.2 | `5617689` | Back-to-Elsewhere visibility across play-pages |

Doc commits: `2ac4a36` (2c.2), `157d920` (plan doc drift), `5e7c952` (2c.3.1), `c6f2f95` (2c.3.2).

**Spec landed 2026-04-26 (the chain that supersedes much of this brief's earlier guidance):**

| Commit | Doc | Scope |
|---|---|---|
| `b7d4e70` | `docs/KARAOKE-CONTROL-MODEL.md` | Karaoke control model spec — role hierarchy, state machine, permission matrix, UI surfaces, implementation mapping for 2d/2e/2f |
| `dc99039` | `docs/DEFERRED.md` | 7 entries from Karaoke Control Model (Q-2B, audience-to-NHHU, audience.html freeze, audience.html migration, audience venue/costume browse, audience read-only queue, Manager Override mechanism) |
| `591796b` | `docs/PHONE-AND-TV-STATE-MODEL.md` | HHU/NHHU framing + Back-to-Elsewhere universal-visibility rule + unified-app architectural direction |
| `4f5966f` | `docs/SESSION-5-PART-2-BREAKDOWN.md` | Re-scope 2d (sub-split), 2e (largest), 2f (significantly reduced) per control model |

**Next up:** Part 2d — karaoke/stage.html session integration. Re-scoped per Karaoke Control Model § 5.1: sub-split into 2d.1 (read/display, ~5 sections, ~2-2.5 hours) + 2d.2 (write/interact, may collapse since override UI moved to phone). See `docs/SESSION-5-PART-2-BREAKDOWN.md` § 2d for full scope and `docs/KARAOKE-CONTROL-MODEL.md` § 5.1 for sub-split rationale.

---

## Open decisions for 2d (post-Karaoke-Control-Model state)

The 10 open decisions originally listed in this brief have been mostly resolved by the Karaoke Control Model (commit `b7d4e70`):

| # | Decision | Status |
|---|---|---|
| 1 | Session query mechanism (URL vs. tv_device_id) | Locked: tv_device_id, URL as fallback |
| 2 | Fallback solo-mode trigger | Locked: silent fallback + log warning |
| 3 | Participant list placement on stage.html | **Resolved** — control model § 4.2: bottom-right slide-out queue panel, parity with comments panel pattern |
| 4 | Active-singer highlight | Locked: avatar ring + text label |
| 5 | Manager/host override UI surface on stage.html | **Moot** — overrides moved entirely to phone (singer.html), per control model § 4.2 |
| 6 | Non-manager visibility of override UI on stage.html | **Moot** — no override UI on stage.html under new model |
| 7 | Pre_selections loading on promotion | Locked: auto-load on role change; no re-approval (2d.2 scope) |
| 8 | End Session button behavior | **Moot for stage.html** — End Session button lives on phone (manager-initiated) |
| 9 | Realtime subscription lifecycle | Locked: bound to loaded session; tear down on session_ended / nav |
| 10 | refreshActiveSession query failure at load | Locked: silent fallback + log |

Remaining technical defaults (1, 2, 4, 7, 9, 10) will be re-verified during 2d.1's pre-implementation audit. No UX-judgment decisions remain blocking.

---

## Sub-split (post-control-model)

Superseded by Karaoke Control Model § 5.1. Quick reference:

- **2d.1 (read/display):** session load, fallback, queue panel render, realtime subscriptions, active-singer highlight, "Up Next" card, idle 360° venue tour. Read-only. ~5 sections, ~2-2.5 hours.
- **2d.2 (write/interact, may collapse):** pre-selections loading on promotion, session_ended navigation, skip/take-over reaction logic. Stage.html has no direct user-input override controls, so 2d.2 may fold into 2d.1.

Earlier estimate (4-5.5 hours total) was pre-control-model when 2d.2 included manager override UI. New estimate is closer to 2-3 hours total since manager override UI moved to phone.

---

## How to resume — paste into a fresh Claude.ai chat

Use this opener with a fresh Claude.ai review chat. Your Claude Code session can be started independently at `/Users/michaelstepanovich/Downloads/elsewhere-repo`.

````
Context: Elsewhere, Session 5 Part 2. 2a/2b/2c shipped;
Karaoke Control Model spec landed (commit b7d4e70).
Current HEAD `4f5966f`. Next is Part 2d.1 (stage.html
read/display). Full handoff details in docs/SESSION-5-HANDOFF.md.

Before kicking off 2d.1 implementation, read in order:
  1. docs/KARAOKE-CONTROL-MODEL.md (canonical spec for 2d/2e/2f)
  2. docs/SESSION-5-PART-2-BREAKDOWN.md § 2d (re-scoped scope + sub-split)
  3. docs/SESSION-5-HANDOFF.md (this brief — open-decisions resolution status)

Then:
  1. Run the pre-implementation audit for 2d.1 — same pattern as
     2c.3's audit (RPC contract verification, realtime-handler
     patterns, interim-state warnings, stage.html integration
     points). Most decisions are resolved by the control model;
     audit verifies remaining technical defaults.
  2. Propose the 2d.1 section-by-section plan. No diffs yet.

Work pattern: propose → pause for review → apply on approval.
Prior session's convention: code commits no trailer; doc commits
use `Co-Authored-By: Claude <noreply@anthropic.com>`.
````

---

## Audit findings (self-contained reference)

### Current 2d scope (post-control-model)

Superseded by control model § 5.1. See `docs/SESSION-5-PART-2-BREAKDOWN.md` § 2d for the re-scoped 2d.1 + 2d.2 sub-split.

Key change from earlier scope: manager/host override UI (venue mid-song, costume mid-song, end song button) **no longer lives on stage.html**. Per control model § 4.2, these overrides moved to the phone (singer.html, owned by Session Manager). Stage.html in 2d is read-only for user inputs; mid-song state mutations come from phone-side RPCs and reflect on stage via realtime events.

### stage.html current state (pre-2d)

- **5254 lines** (second-largest file after index.html)
- Imports `shell/auth.js` + `shell/realtime.js` + `shell/venue-settings.js` ✓
- Uses ROOM_CODE from URL `?room=` param (pre-Session-5 identifier; line 584-585)
- **Zero** `session_participants`, `pre_selections`, `participation_role`, `control_role`, `queue_position`, `rpc_session_*` references
- **2b wiring already shipped (lines 5197-5245):** `wireExitAppListener` with session-state check — stays on stage if session active, navigates to tv2.html otherwise
- **No existing realtime subscribers** beyond 2b's exit_app listener
- **No publishers called** today — stage.html is pure consumer of realtime

### Dependencies

- All upstream work complete (Part 1 RPCs + 2b + 2c)
- No cross-file changes required from 2d (2e/2f are separate sub-parts)
- 2d emits events (via publishers) that 2e/2f will consume later

### State model + karaoke control model reference

Per `docs/PHONE-AND-TV-STATE-MODEL.md` § State 3 — In active session:
- TV navigates away from tv2.html to stage.html (karaoke) or games/tv.html (games)
- Transitions: → State 2 on `session_ended`; ↔ State 3 across cross-app switch
- Active session is independent of TV inactivity timeout — session is the activity

State model is silent on app-specific UI (queue rendering, role-aware controls). Those decisions live in `docs/KARAOKE-CONTROL-MODEL.md`:
- Queue panel placement: § 4.2 (bottom-right slide-out, parity with comments panel)
- Role hierarchy + permissions: §§ 1, 3
- Stage.html UI surfaces (read-only): § 4.2
- Singer.html role-aware UI: § 4.1
- Manager Override mechanism (transport): § 2 implementation note + § 5.7 (deferred to 2e audit)

Back-to-Elsewhere visibility rule (per state model + control model § 4.4): all audience users see the button. HHU lands on post-login home; NHHU lands on placeholder Elsewhere home.

---

## Housekeeping for 2d close

When 2d.1 and 2d.2 both ship (or 2d.2 collapses and 2d.1 is the whole of 2d):
- Update `docs/SESSION-5-PART-2-BREAKDOWN.md`: mark 2d ✓ SHIPPED with sub-part SHAs, Delivered/Decisions/Watch subsections
- Update Status line: "Parts 2a, 2b, 2c, 2d complete. Part 2e next, then 2f pending."
- Consider whether `docs/SESSION-5-HANDOFF.md` should be replaced with a 2e-focused one at that point, or retired (2e is the largest sub-part remaining; a fresh handoff brief may be warranted)

---

## Quick navigation

- **Karaoke control model (spec for 2d/2e/2f):** `docs/KARAOKE-CONTROL-MODEL.md`
- State model: `docs/PHONE-AND-TV-STATE-MODEL.md`
- Active breakdown: `docs/SESSION-5-PART-2-BREAKDOWN.md`
- Session plan: `docs/SESSION-5-PLAN.md`
- DEFERRED: `docs/DEFERRED.md`
- Roadmap: `docs/ROADMAP.md`
