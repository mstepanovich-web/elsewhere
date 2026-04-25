# Session 5 Handoff Brief

**Written:** 2026-04-25
**Last commit reviewed:** `c6f2f95` (docs: mark 2c.3.2 shipped; close 2c block)
**Purpose:** Self-contained context for resuming Session 5 Part 2d in a fresh Claude.ai chat.

---

## Current state — Session 5 Part 2 (2a, 2b, 2c all shipped)

| Sub-part | Code commit | Scope |
|---|---|---|
| 2a | `d1b4edd` | 5 new publishers in `shell/realtime.js` |
| 2b | `601d125` | Session lifecycle wiring (index + tv2 + stage + games/tv) |
| 2c.1 | `daa8718` | User preferences storage (`db/012` + `shell/preferences.js`) |
| 2c.2 | `0a3a9ea` | Post-login home unification + proximity banner |
| 2c.3.1 | `e4a348e` | Active-session rendering + rejoin + cross-app switch |
| 2c.3.2 | `5617689` | Back-to-Elsewhere visibility across play-pages |

Doc commits: `2ac4a36` (2c.2), `157d920` (plan doc drift), `5e7c952` (2c.3.1), `c6f2f95` (2c.3.2).

**Next up:** Part 2d — karaoke/stage.html full session integration. Recommend split into 2d.1 (read/display) + 2d.2 (write/interact).

---

## Open decisions for 2d (from audit; my leans noted)

| # | Decision | Lean |
|---|---|---|
| 1 | Session query mechanism: URL `?room=` vs. tv_device_id query | **tv_device_id**, URL as fallback |
| 2 | Fallback solo-mode trigger | Silent fallback + log warning |
| 3 | Participant list placement on stage.html | **Needs UX call** — overlay corner vs. bottom strip vs. side panel |
| 4 | Active-singer highlight | Avatar ring + text label |
| 5 | Manager/host override UI surface | **Needs UX call** — new buttons near admin gear vs. "Session" menu |
| 6 | Non-manager visibility of override UI | Hidden (per 2c.3.2 precedent) |
| 7 | Pre_selections loading on promotion | Auto-load on role change; no re-approval |
| 8 | End Session button behavior | RPC + publish + explicit navigate |
| 9 | Realtime subscription lifecycle | Bound to loaded session; tear down on session_ended / nav |
| 10 | refreshActiveSession query failure at load | Fall back to solo mode + log |

**Three (3, 5, 6) involve UX judgment, not purely technical defaults. May warrant a design pass before 2d.1 starts.**

---

## Sub-split recommendation (from audit)

**2d.1 — Read + display (session-aware stage)**
- Scope: session load, fallback, participant list DOM/CSS, realtime subscription, active-singer highlight. Read-only.
- Estimate: ~350-500 lines added, 5 sections, ~2-2.5 hours
- Standalone-verifiable: start session from phone, see queue populate on TV

**2d.2 — Interact (manager/host override + pre_selections replay)**
- Scope: override UI + RPC wiring (`rpc_session_update_participant`, `rpc_session_end`) + pre_selections load on promotion + End Session flow
- Estimate: ~250-450 lines added, 4-5 sections, ~2-3 hours

**Natural seam:** read-only vs. read-write. Total ~4-5.5 hours across both sub-parts.

---

## How to resume — paste into a fresh Claude.ai chat

Use this opener with a fresh Claude.ai review chat. Your Claude Code session can be started independently at `/Users/michaelstepanovich/Downloads/elsewhere-repo`.

````
Context: Elsewhere, Session 5 Part 2. 2a/2b/2c all shipped;
current HEAD `c6f2f95`. Next is Part 2d (karaoke/stage.html
full session integration). Full handoff details in
docs/SESSION-5-HANDOFF.md.

Before kicking off 2d.1 implementation, I need to lock the
10 open decisions from the audit (see § "Open decisions for 2d"
in the handoff brief). Three of them (DECISION-3 participant
list placement, DECISION-5 override UI surface, DECISION-6
non-manager visibility) involve UX judgment — worth a design
pass before coding.

Read docs/SESSION-5-HANDOFF.md and docs/SESSION-5-PART-2-BREAKDOWN.md
§ 2d. Then:
  1. Walk me through each of the 10 decisions with
     recommendations. For DECISION-3 and DECISION-5, explore
     2-3 design options each with tradeoffs.
  2. Once all 10 are locked, run the pre-implementation audit
     for 2d.1 (same pattern as 2c.3's audit — RPC contract
     verification, realtime-handler patterns, interim-state
     warnings).
  3. Propose the 2d.1 section-by-section plan. No diffs yet.

Work pattern: propose → pause for review → apply on approval.
Prior session's convention: code commits no trailer; doc commits
use `Co-Authored-By: Claude <noreply@anthropic.com>`.
````

---

## Audit findings (self-contained reference)

### Current 2d scope from BREAKDOWN.md § 2d

- Read active session on load via `sessions` query filtered by `tv_device_id`
- Graceful fallback to pre-Session-5 solo mode if no session (dev/legacy only)
- Query + render participant list with queue positions, active singer highlighted
- Subscribe to `participant_role_changed`, `queue_updated`, `session_ended`
- On singer promotion (queued → active): load newly-promoted user's `pre_selections` (song, venue, costume) as initial stage state
- Manager/host override UI: change venue mid-song, change costume mid-song, end song button

**Locked decisions (already in BREAKDOWN):**
- Venue/costume overrides mid-song update TV state, NOT active singer's `pre_selections`
- End song button sends active singer to audience, not queued

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

### State model reference

Per `docs/PHONE-AND-TV-STATE-MODEL.md` § State 3 — In active session:
- TV navigates away from tv2.html to stage.html (karaoke) or games/tv.html (games)
- Transitions: → State 2 on `session_ended`; ↔ State 3 across cross-app switch
- Active session is independent of TV inactivity timeout — session is the activity

State model is silent on app-specific UI (queue rendering, override surfaces). Those are karaoke-app decisions owned by 2d.

---

## Housekeeping for 2d close

When 2d.1 and 2d.2 both ship:
- Update `docs/SESSION-5-PART-2-BREAKDOWN.md`: mark 2d ✓ SHIPPED with sub-part SHAs, Delivered/Decisions/Watch subsections
- Update Status line: "Parts 2a, 2b, 2c, 2d complete. Part 2e next, then 2f pending."
- Consider whether `docs/SESSION-5-HANDOFF.md` should be replaced with a 2e-focused one at that point, or retired

---

## Quick navigation

- State model: `docs/PHONE-AND-TV-STATE-MODEL.md`
- Active breakdown: `docs/SESSION-5-PART-2-BREAKDOWN.md`
- Session plan: `docs/SESSION-5-PLAN.md`
- DEFERRED: `docs/DEFERRED.md`
- Roadmap: `docs/ROADMAP.md`
