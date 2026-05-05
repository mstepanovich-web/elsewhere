# Roadmap

High-level session pipeline so we don't lose context between sessions. Updated at the end of each session and at the start of each planning session.

---

## Active session

**Session 5 — Universal session + participants + queue model**
- **Status:** Part 1 complete. Part 2 complete (2a-2e shipped; 2f deferred to consolidation per audience.html no-investment doctrine, closeout `1d481b4`). Part 3a shipped (3a.1 plumbing + 3a.2 manager controls). Part 3b productionization + Phase 2 shipped (v2.108 → v2.113, Edge Function + db/019, 2026-05-04). 3b proper (active/audience integration) + 3c/3d (Last Card + Euchre integration) + Parts 4-5 pending.
- **What's left in Session 5 (in order):**
  1. **v2.113 hardware verification** — gate before any new track. iPhone Safari verification of stale "(premium)" status text reset on entry + ☰ Games button removal. ~5 minutes. Reference: `docs/SESSION-5-PART-3B-VERIFICATION-LOG.md`.
  2. **iOS Capacitor sync catch-up** — sync iOS bundle from v2.99 to current (~3 weeks of drift). ~30 minutes. Reference: DEFERRED entry "Session 5 closeout — iOS bundle sync from v2.99 to current".
  3. **Trivia 3b proper** — active/audience integration per `docs/GAMES-CONTROL-MODEL.md` § 4.1: late-joiner choice screen (Active vs Audience), admission_mode dispatch in `handleMessage`'s `game-state` receiver, Skip Question manager-bar wiring (`mgr-skip` button currently only fires for Last Card). Modify-existing path per the cluster-closeout audit; ~80-120 LOC additive. Score/streak math, 4-option DOM layout, OpenTDB+Anthropic fetch helpers all preserved verbatim. Reference: `docs/GAMES-CONTROL-MODEL.md` § 4.1.
  4. **Last Card 3c** — same active/audience integration scope as Trivia 3b, applied to Last Card. Reference: `docs/GAMES-CONTROL-MODEL.md` § 4.1.
  5. **Euchre 3d** — same scope as Last Card 3c, applied to Euchre. Reference: `docs/GAMES-CONTROL-MODEL.md` § 4.1.
  6. **Part 4 — Proximity polish** (substantially absorbed into 2c per `docs/PHONE-AND-TV-STATE-MODEL.md`). Remaining: animation polish, copy refinement, edge cases (recovery from incorrect answer, multi-TV proximity reset). May collapse entirely into 2c with no new commits.
  7. **Part 5 — Multi-user end-to-end verification.** Eight verification flows requiring 2+ test accounts: multi-user karaoke (queue ordering, manager approves, host override mid-song), multi-user game (Trivia self-join), manager transfer, orphaned session reclaim, household admin force-reclaim, proximity gate, cross-app isolation, regression check (all 4.10.2 + 4.10.3 flows still work). New verification doc to be created at `docs/SESSION-5-VERIFICATION.md`. Reference: `docs/SESSION-5-PLAN.md` Part 5.
- **Estimated remaining:** 8-12 hours across 3-4 sessions. Part 3 ~6-9 hr remaining (3b/3c/3d per `docs/GAMES-CONTROL-MODEL.md` § 4.1). Part 4 ~0-1 hr (substantially absorbed into 2c). Part 5 ~2-3 hr verification with 2+ test accounts.
- **References:** `docs/SESSION-5-PLAN.md`, `docs/SESSION-5-PART-2-BREAKDOWN.md`, `docs/SESSION-5-PART-2-CLOSING-LOG.md`, `docs/SESSION-5-PART-3-AUDIT.md`, `docs/SESSION-5-PART-3-CLOSING-LOG.md`, `docs/SESSION-5-PART-3B-CLOSING-LOG.md`, `docs/GAMES-CONTROL-MODEL.md`

### Commits shipped in Session 5

**Part 1 — Schema + RPCs + shell/realtime.js extraction:**
- `253e077` — Part 1a: sessions + session_participants schema with RLS (db/008)
- `979f70d` — Part 1b.1: session lifecycle RPCs (db/009)
- `a0373e0` — Part 1b.2: manager mechanics RPCs (db/010)
- `5f60d13` — Part 1b.3: role and queue mutation RPCs (db/011)
- `9e10bf4` — Part 1c: extract realtime helpers into `shell/realtime.js`

**Part 2 — Karaoke integration:** (full commit detail in `docs/SESSION-5-PART-2-CLOSING-LOG.md`)
- 2a: realtime publishers (`d1b4edd`)
- 2b: session lifecycle wiring (`601d125`)
- 2c.1/2/3.1/3.2: home unification + active session relabeling + Back-to-Elsewhere visibility (`daa8718`, `0a3a9ea`, `e4a348e`, `5617689`)
- 2d.0/1: karaoke session helpers + stage.html session integration (`db/013` + multiple commits)
- 2e.0/1/2: push notification infrastructure + role-aware UI + self write actions (multiple commits, latest `9ec5006`/`ee7849a`)
- 2e.3.1/2: manager queue UI + manager override commands panel (multiple commits, latest `af1e468` at v2.120)
- 2f: deferred to consolidation (no commits)
- BUG fixes during 2e.3: `ce36fe5` (BUG-5 web sign-up redirect), `1b870d3` (BUG-10 realtime publish race at v2.118), `ad97ea5` (BUG-13/3/7 manager refresh + cosmetic at v2.119)
- Closeout: `1d481b4` (audience.html no-investment doctrine + 5 papercuts + closing log), `7f8f97e` (5 open bugs filed to DEFERRED)

**Part 3 — Games integration:**
- 3a prereq: `db/016_remove_participant.sql` — manager-only soft-removal RPC (`05d2cae`)
- 3a.1: session/participants plumbing — manager identity from `control_role`, agora-identity-bind protocol, γ-1 lobbyPlayers synthesis as transitional bridge (`ea89c48` at v2.100)
- 3a.2: manager controls — End Session button (`rpc_session_end` + `publishSessionEnded`); manager-as-player toggle via `rpc_session_update_participant`; Remove Player UI (`rpc_session_remove_participant`); `lobbyPlayers` + `managerIsPlayer` + γ-1 synthesis retired; `manager-player-status` Agora message retired (`8bff27b` at v2.101)

**Next up:** 3b/3c/3d — per-game admission UX (Trivia, Last Card, Euchre). Per-game state machines, queueing semantics, and late-joiner flows per `docs/GAMES-CONTROL-MODEL.md` § 3 + § 4.1. SESSION-5-PLAN.md lines 333-349's original Part 3 work breakdown is now superseded by the Control Model's sub-decomposition.

---

## Queued sessions

> **Note on numbering:** Sessions 6 → 12 are a clean integer sequence reflecting technical-first dependency ordering. Sessions 6 + 7 (formerly 4.10.1 + 4.11) renumbered 2026-05-04 to drop the 4.x topical prefix in favor of the post-Session-5 sequence. The legacy 4.x numbering is preserved in the "Completed sessions" section below for traceability against shipped work.
>
> Hard ordering Session 6 → 7 → 8 → 9 → 10 → 11 → 12: small wins first (SMS pre-invites, admin UI, Trivia premium UX), then keystone reworks (audience.html unification, cross-app venues), then user-acquisition + new app surfaces (NHHU conversion funnel, wellness app). Sessions 9 + 10 unblock Sessions 11 + 12.

### Session 6 — SMS pre-invites for household onboarding

- **Why:** Phone-based household pre-invites, needed before scaling household onboarding past direct email invites. (Was Session 4.10.1.)
- **Estimated:** 1–2 hours
- **Depends on:** nothing (orthogonal to Session 5)
- **Reference:** `docs/DEFERRED.md` → "Phone-based household pre-invites (SMS verification)"

### Session 7 — Admin management UI

- **Why:** 4.10 ships with no household admin UI beyond pre-invite. Member roster, demote/promote, scan-approval flow, pending invites inbox all need first-class UI surfaces. (Was Session 4.11.)
- **Estimated:** 2–3 hours
- **Depends on:** 4.10 RPCs (already shipped — `rpc_approve_household_member`, `rpc_designate_admin`). Session 6 (SMS pre-invites) lands first.
- **Reference:** `docs/DEFERRED.md` → "Scan-approval flow", "Pending Invitations inbox"

### Session 8 — Trivia premium UX differentiation

- **Why:** Trivia Phase 2 (shipped 2026-05-04) plumbs premium AI-generated questions but offers no functional advantage over OpenTDB beyond the "AI-generated" label. Premium needs to actually feel premium. Open design space — three candidate directions: (1) custom categories (manager types a free-form theme like "obscure prog rock"); (2) Wikipedia-aware questions (Anthropic with retrieval to current events); (3) per-user personalization (Trivia tuned to past players' interests).
- **Estimated:** TBD pending design conversation.
- **Depends on:** Nothing technically. Open design space; product conversation comes first.
- **Reference:** `docs/DEFERRED.md` → "Trivia premium polish (post-Phase 2)" (the existing 3-item polish entry surfaces some prereqs but not the differentiation work itself; this entry should be added in a future commit if differentiation work crystallizes).

### Session 9 — Audience.html unification (NHHU → HHU UI merge)

- **Why:** Current parallel UI codebases (audience.html for NHHU, singer.html/index.html for HHU) compound complexity with every feature added. Post-Session-5 work to absorb audience.html into the HHU app as a parameterized NHHU view. Same UI fabric for both populations, conditional rendering hides TV-required features.
- **Status:** Keystone for further platform work — until this lands, NHHU conversion funnel + games venues + wellness all fight against the audience-vs-singer split.
- **Estimated:** TBD pending session planning. Substantial structural work.
- **Existing precondition:** audience.html freeze in effect since Session 5 (no new features there; bug fixes only). See DEFERRED entry "Audience.html freeze".
- **Depends on:** Session 5 closure. Sessions 6-8 don't strictly block this but are smaller and ship faster.
- **References:**
  - `docs/KARAOKE-CONTROL-MODEL.md` § 5.5 "Post-Session-5 — Audience.html migration into unified app" (canonical)
  - `docs/PHONE-AND-TV-STATE-MODEL.md` line 419 (cross-reference)
  - `docs/DEFERRED.md` "Migrate audience.html into unified app as parameterized NHHU view" (line 1436)
  - `docs/DEFERRED.md` "Audience.html freeze" (line 1422, active constraint)

### Session 10 — Venues at platform level (cross-app service)

- **Why:** Venues are currently karaoke-only (`karaoke/stage.html` owns the 360° panorama renderer, `venues.json` schema, etc.). Elevating them to a platform-level cross-app service usable by Games (and future apps like wellness) is a documented post-Session-5 architectural rework.
- **Estimated:** TBD pending session planning.
- **Three-part work documented:**
  1. Extract 360° panorama rendering from `karaoke/stage.html` into `shell/venue-renderer.js` (Three.js setup, texture loading, transition UX)
  2. Games integration: each game's blockade image becomes a venue entry in `venues.json` with product tag 'games'; games pages consume the shared renderer
  3. Phase 2 follow-up: DeepAR camera insertion for player presence in games
- **Triggers** (per DEFERRED entry): either wellness app start, OR games visual parity priority. NOT urgent for Session 5; explicit "don't bundle with Session 5" guidance.
- **Depends on:** Could run parallel with Session 9, but Session 9 first means Session 10 has cleaner UI fabric to build into.
- **References:**
  - `docs/DEFERRED.md` "Venues as cross-app service (games, wellness, future apps)" (line 846, canonical)
  - `docs/DEFERRED.md` "Venues integration (post-Session-5)" parent cluster (line 897, six downstream items)

### Session 11 — Audience-to-NHHU conversion path (user-acquisition funnel)

- **Why:** Convert passive audience members into registered users. Phase 1 placeholder may ship in Session 5 (minimal Elsewhere home for NHHU returning from audience deep link, with "go back" + "explore Elsewhere" options). Full conversion funnel (sign-up, app downloads, game launchers) is post-Session-5.
- **Status:** User-acquisition strategy. Sister item to Session 9 unification — listed in same § 5.4-5.5 vicinity but distinct scope (UX/funnel work vs. structural UI rework).
- **Estimated:** TBD pending session planning.
- **Depends on:** Session 9 (unification) lands first for best funnel quality — converted NHHUs should land in the unified app, not a separate codebase. Sessions 6 + 7 (SMS pre-invites + admin UI) are also soft prerequisites for funnel quality.
- **References:**
  - `docs/KARAOKE-CONTROL-MODEL.md` § 5.4 "Post-Session-5 — Audience-to-NHHU conversion path" (canonical)
  - `docs/DEFERRED.md` "Audience-to-NHHU conversion path" (line 1408)

### Session 12 — Wellness app implementation

- **Why:** Wellness is a placeholder in the architecture today (no implementation). Adding it requires both the unified app (Session 9 — wellness needs the same UI fabric, otherwise becomes a third parallel codebase) and the platform-level venue service (Session 10 — wellness sessions need their own venue/environment system).
- **Estimated:** TBD pending session planning.
- **Depends on:** Session 9 (unification) AND Session 10 (cross-app venues). Without both, wellness becomes a third parallel UI codebase.
- **References:**
  - `docs/SESSION-5-PLAN.md` (wellness mentioned as future app; schema supports `app = 'wellness'` for future)
  - `docs/DEFERRED.md` (no dedicated wellness entry yet; this Session 12 entry is the placeholder)

---

## Completed sessions

### Session 4.10.3 — Phone back-to-Elsewhere + coordinated TV teardown

**Completed:** 2026-04-22

Shipped the reverse of 4.10.2's phone-as-remote forward loop. Phone back-tap on singer.html / player.html navigates to Elsewhere and publishes `exit_app` realtime event; TV listens on stage.html / games/tv.html and returns to apps grid. Verified end-to-end on real hardware.

**Commits (chronological):**
- `cab9a38` — docs: Session 4.10.3 plan
- `3319ce8` — docs: scope-down Part B + defer audience back-nav
- `f43369a` — Part A: exit_app realtime wiring (index.html + stage.html + games/tv.html)
- `97014c2` — docs: Part B placement + shell-load pattern
- `2c2d5fe` — Part B: singer.html back button + helpers + shell load
- `50a9f5c` — fix: viewport-fit=cover on singer.html
- `40e4f4b` — Part C: fix games/player.html Back to Home link
- `1416c52` — docs: verification doc

**DEFERRED entries that emerged:**
- Audience back-to-Elsewhere navigation (Medium) — filed during Part B scope-down
- Extract `publishExitApp` + realtime helpers into `shell/realtime.js` (Low) — filed at session-end
- Post-claim direct transition to remote-control screen (Low-medium) — filed at session-end, carried forward from 4.10.2 plan Part E

Details: `docs/SESSION-4.10.3-PLAN.md`, `docs/SESSION-4.10.3-VERIFICATION.md`

### Session 4.10.2 — Phone-as-remote UX fixes

**Completed:** 2026-04-22 (core Parts A+B+C + fixes shipped; Parts D–G superseded by 4.10.3 follow-up)

Shipped the phone-as-remote redesign: "Your TVs" picker, remote-control screen, display-only TV apps grid. Forward loop works end-to-end. Parts D–G of the original plan (TV sign-in copy rewrite, post-claim direct transition, dedicated verification doc, v3.0 → v3.1 version bump) did NOT ship — development attention shifted to 4.10.3's follow-up work addressing issues surfaced during 4.10.2 testing.

**Commits:**
- `4a331d6` — Parts A+B (phone Your TVs + remote control)
- `4372a20` — Part C (TV launch listener + display-only grid)
- `56e6e3d` — Navigation fix (phone follows TV into app)
- `7b81f70` — Await fix (phone waits for publish before navigating)

**DEFERRED entries that emerged** (now in DEFERRED.md):
- Phone back-to-Elsewhere + TV teardown (→ resolved in 4.10.3)
- Multi-phone session coordination + session manager role
- Proximity self-declaration
- Session manager inactivity + household-admin override
- Per-app role manifest
- TV sign-in screen copy implies wrong direction of action (still deferred; was Part D of original plan)

**Parts from 4.10.2 plan that remain unfinished:**
- Part D — TV sign-in copy rewrite (captured as DEFERRED entry, not yet scheduled)
- Part E — Post-claim direct transition to remote-control screen (filed as DEFERRED during 4.10.3 session-end)
- Part F — Dedicated 4.10.2 verification doc (not created; 4.10.3's doc subsumes some coverage)
- Part G — v3.0 → v3.1 version bump (never ran; current badge still v2.99 on pages that carry it)

Details: `docs/SESSION-4.10.2-PLAN.md`

---

## Smaller items to land opportunistically

Not full sessions, but worth tracking:

- **`claim.html` App Store URL:** when the iOS app is listed, swap the placeholder href. ~1-line change. Ref: `DEFERRED.md` "claim.html App Store URL placeholder".
- **Inline-script TDZ audit:** opportunistic, when next touching `index.html` / `stage.html` / etc. Ref: `DEFERRED.md` "Audit inline-script TDZ risk in other pages".
- **tv2.html render race:** post-Session-5 polish, not blocking. Ref: `DEFERRED.md` "tv2.html render race".

---

## Architecture notes

Longer-lived design context. Decisions locked in at the session they shipped; won't be revisited without explicit cause.

- **Two-Signal Doctrine** (from OverlayOS work, applies if products converge): Signal A = passthrough, Signal B = OverlayOS-generated and operable.
- **Household + TV device model:** see `SESSION-4.10-PLAN.md`. Currently shipped (six commits in Session 4.10, ending `e7952ae`). `households` + `tv_devices` + `household_members` + `pending_household_invites` tables with RLS.
- **Session handoff via Supabase realtime:** `tv_device:<device_key>` channel, `session_handoff` event. Session 4.10.2 adds `launch_app` event on the same channel (see `SESSION-4.10.2-PLAN.md`). Reuse, don't fork channels.
- **Phone is the remote; TV is the display** (Session 4.10.2, pending implementation): mental model correction. Interactive app launcher lives on phone. TV shows a display-only grid with instruction text.
