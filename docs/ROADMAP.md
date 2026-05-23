# Roadmap

High-level session pipeline so we don't lose context between sessions. Updated at the end of each session and at the start of each planning session.

---

## Active session

**Unified-app workstream — Phase 2: venue extraction (UAP §5)**

Phase 1 of the unified-app refactor (the room/session foundation) shipped 2026-05-21 → 2026-05-23 — see "Unified-app workstream — Phase 1: Room/session foundation" in the Completed section below for full commits + verified-prod state. Phases 3, 4, 5 (karaoke onto the new model, games conformance, rooms/groups/cross-app movement) follow per `docs/UNIFIED-APP-PLAN.md` §5. This active entry is Phase 2: pull venue rendering out of the karaoke stage into a shared shell renderer and make the venue registry cross-app.

- **Status:** Active. Prerequisite for "navigate venues" being a baseline experience in any app. Per UAP §5, Phase 2 "can overlap Phase 1" — fully unblocked now that Phase 1 is closed.
- **Estimated:** TBD pending session planning.
- **Three-part work** (per `docs/DEFERRED.md` "Venues as cross-app service (games, wellness, future apps)", line ~846 — the canonical entry):
  1. Extract 360° panorama rendering from `karaoke/stage.html` into `shell/venue-renderer.js` (Three.js setup, texture loading, transition UX). Keep karaoke's ambient effects separate (DEFERRED `shell/venue-effects.js` entry).
  2. Games integration: each game's blockade image becomes a venue entry in `venues.json` with product tag `'games'`; session-wide venue selection; games pages consume the shared renderer.
  3. Phase-2 follow-up: DeepAR camera insertion for player/participant presence in games (same technique karaoke uses for singers).
- **Trigger** (per the DEFERRED entry): either wellness app start, OR games visual parity priority. Not blocking the workstream's gating — Phases 3 and 4 depend on Phase 1 (done); Phase 3 additionally depends on Phase 2.
- **References:** `docs/UNIFIED-APP-PLAN.md` §5 Phase 2 + the four companion model docs; `docs/EXECUTION-HANDOFF.md` §4 (operator-facing brief, refreshed each session); `docs/DEFERRED.md` "Venues as cross-app service" (canonical, line ~846) + "Venues integration (post-Session-5)" parent cluster (line ~897).

---

## Queued sessions

> **Note on numbering:** Sessions 6 → 12 are a clean integer sequence reflecting technical-first dependency ordering. Sessions 6 + 7 (formerly 4.10.1 + 4.11) renumbered 2026-05-04 to drop the 4.x topical prefix in favor of the post-Session-5 sequence. The legacy 4.x numbering is preserved in the "Completed sessions" section below for traceability against shipped work.
>
> Session 10 (Venues at platform level) is now the active entry above as UAP §5 Phase 2 — its body is no longer in this queue; the active entry holds the working detail. Sessions 9, 11, 12 carry one-line cross-ref notes mapping each to its UAP §5 phase (9 → Phase 3 karaoke; 11 → Phase 3+ funnel; 12 → post-Phase-5 "then wellness/worlds"). Hard ordering for the remaining queue: 6 → 7 → 8 (small wins first — SMS pre-invites, admin UI, Trivia premium UX); 9 + 11 + 12 sequenced per their UAP phase dependencies.

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

> **UAP §5 phase mapping:** Phase 3 (karaoke onto the new model). Tracked under the active unified-app workstream — see Active section above.

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

### Session 11 — Audience-to-NHHU conversion path (user-acquisition funnel)

> **UAP §5 phase mapping:** Phase 3+ (sister UX/funnel layer to karaoke surface work). Tracked under the active unified-app workstream — see Active section above.

- **Why:** Convert passive audience members into registered users. Phase 1 placeholder may ship in Session 5 (minimal Elsewhere home for NHHU returning from audience deep link, with "go back" + "explore Elsewhere" options). Full conversion funnel (sign-up, app downloads, game launchers) is post-Session-5.
- **Status:** User-acquisition strategy. Sister item to Session 9 unification — listed in same § 5.4-5.5 vicinity but distinct scope (UX/funnel work vs. structural UI rework).
- **Estimated:** TBD pending session planning.
- **Depends on:** Session 9 (unification) lands first for best funnel quality — converted NHHUs should land in the unified app, not a separate codebase. Sessions 6 + 7 (SMS pre-invites + admin UI) are also soft prerequisites for funnel quality.
- **References:**
  - `docs/KARAOKE-CONTROL-MODEL.md` § 5.4 "Post-Session-5 — Audience-to-NHHU conversion path" (canonical)
  - `docs/DEFERRED.md` "Audience-to-NHHU conversion path" (line 1408)

### Session 12 — Wellness app implementation

> **UAP §5 phase mapping:** post-Phase-5 ("then — wellness and worlds, built greenfield against the finished model"). Tracked under the active unified-app workstream — see Active section above.

- **Why:** Wellness is a placeholder in the architecture today (no implementation). Adding it requires both the unified app (Session 9 — wellness needs the same UI fabric, otherwise becomes a third parallel codebase) and the platform-level venue service (Session 10 — wellness sessions need their own venue/environment system).
- **Estimated:** TBD pending session planning.
- **Depends on:** Session 9 (unification) AND Session 10 (cross-app venues). Without both, wellness becomes a third parallel UI codebase.
- **References:**
  - `docs/SESSION-5-PLAN.md` (wellness mentioned as future app; schema supports `app = 'wellness'` for future)
  - `docs/DEFERRED.md` (no dedicated wellness entry yet; this Session 12 entry is the placeholder)

---

## Completed sessions

### Unified-app workstream — Phase 1: Room/session foundation

**Completed:** 2026-05-21 → 2026-05-23 (db/025-031 applied to prod; §F shell rework + Phase-1 post-work shipped; 10 commits pushed in the closing push)

Shipped the keystone of the unified-app refactor: a `rooms` entity that durably persists across app switches; `sessions` demoted to per-app instances under a room; `session_participants` re-anchored from `session_id` to `room_id`; the 14 RPCs re-keyed plus new `rpc_room_create`; the shell session-state cluster re-pointed from "the session for the bound TV" to "the room and its current session"; plus closing-out post-work: push-trigger recreation (db/029), premium-control-layer schema column (db/030), ownership-seize RPC (db/031), realtime publisher field-name rename (shell half), and the per-user per-app tile-badge spec (UAP §10).

Architectural significance: Phase 1 is the keystone for UAP §5's remaining phases. Phases 3 (karaoke surface migration) and 5 (rooms/groups/cross-app movement) depend on Phase 1 directly. Phase 2 (venue extraction) can run independently and is now the active session.

**Commits (chronological):**

- `dddbeb6` — db/025 schema cutover (rooms entity + session/participant re-anchor)
- `9e3926e` — db/026 RPC batch 1 (8 mechanical re-points + session_end + set_admission_mode)
- `2465ff5` — db/027 RPC batch 2 (rpc_session_start split + new rpc_room_create per OQ2 (a))
- `95dcf70` — db/028 RPC batch 3 (rpc_session_leave four-tier succession + reclaim RPCs)
- `c657c9f` — forward-correction: DROP FUNCTION ahead of CREATE OR REPLACE for 11 renamed/re-typed functions
- `409676b`, `4bd0829`, `da87d26` — db/026 / db/027 / db/028 apply bookkeeping
- `d790703` — §F Part 2: nested {session, room} cache reshape
- `c270800` — §F Part 1: re-point shell RPC call sites to room-keyed signatures
- `58b36c3` — version bump v2.138
- `daeff0b` — Phase-1.1 dead-code cleanup (generateRoomCode removed; is_session_* wrapper drop deferred)
- `5eb8258` — iOS notification-payload audit (DEFERRED record)
- `b0f8a47` + `89a629e` — db/029 fire_promotion_push recreation + Edge Function payload update
- `2ca15a8` + `fd553ac` — db/030 tv_devices.can_embed column (schema half)
- `b654f91` + `cbd2783` — db/031 rpc_room_seize ownership-seize RPC
- `a5ed589` — C2 shell-half realtime publisher payload rename (4 shell sites; 18 surface sites deferred to Phase 3/4)
- `bf45b2c` — UNIFIED-APP-PLAN §10 tile-badge spec + PHONE-AND-TV-STATE-MODEL.md supersession pointer

All 7 db migrations (db/025-031) applied to prod via Supabase SQL Editor; recorded in `db/MIGRATIONS_APPLIED.md`. iOS bundle synced through `bf45b2c` (this session's close); Xcode rebuild outstanding as normal deferred step.

**DEFERRED entries that emerged:** C1 self-report writer (the writer half of `tv_devices.can_embed`; blocked on compositing pipeline not yet existing as code); C2 surface-side completion (18 publisher call sites in singer/stage/player still send `session_id`); schema-stale `sessions` SELECTs on the four pre-Phase-3 surfaces (7 sites reference dropped columns); C4 HH-admin administrative actions without engagement transition; publishParticipantRoleChanged contract drift / latent `payload.user_id` always undefined; publishManagerChanged dead publisher (zero callers); push-notification tap-routing (`// TODO 2e.1+`) unbuilt; low-prominence room-code-entry UI affordance.

**Details:** `docs/UNIFIED-APP-PLAN.md` (workstream design); `docs/PHASE-1-BUILD-SPEC.md` (Phase 1 detailed spec + verified RPC migration worklist); `docs/EXECUTION-HANDOFF.md` §2 (Phase 1 + post-work status) + §4 (the current-and-next state); four companion model docs (`docs/ROOM-SESSION-MODEL.md`, `docs/ROOM-AUTHORITY-MODEL.md`, `docs/HOUSEHOLD-DEVICE-PRESENCE-MODEL.md`, `docs/ROOM-ACCESS-INVITE-MODEL.md`); `db/MIGRATIONS_APPLIED.md` rows for db/025-031.

### Session 5 — Universal session + participants + queue model

**Completed:** 2026-05-19 (Parts 1, 2, 3a, 3b, 3c W1-W10 shipped; Part 5 verification superseded — see "Workstream pivot" below)

Shipped the universal session + participants + queue model: `sessions` table with RLS and lifecycle RPCs (Part 1); karaoke integration with realtime publishers, session lifecycle wiring, home unification, push notification infrastructure, manager queue UI (Part 2); games integration with manager controls, End Session, Remove Player (Part 3a); Trivia productionization with Edge Function + db/019 premium gating (Part 3b — internally called "Trivia Phase 2", not to be confused with UAP §5's Phase 2); admission_model_v2 §10 W1-W10 (schema migration, per-game manifest + admission stamping, dispatcher refactor, Pause + Leave UI, heartbeat + server-side prune, Last Card UX polish, dead-code sweep) — Part 3c.

**Commits (Part 1 — Schema + RPCs + shell/realtime.js extraction):**
- `253e077` — Part 1a: sessions + session_participants schema with RLS (db/008)
- `979f70d` — Part 1b.1: session lifecycle RPCs (db/009)
- `a0373e0` — Part 1b.2: manager mechanics RPCs (db/010)
- `5f60d13` — Part 1b.3: role and queue mutation RPCs (db/011)
- `9e10bf4` — Part 1c: extract realtime helpers into `shell/realtime.js`

**Commits (Part 2 — Karaoke integration):** full detail in `docs/SESSION-5-PART-2-CLOSING-LOG.md`. Key milestones: 2a realtime publishers (`d1b4edd`), 2b session lifecycle wiring (`601d125`), 2c home unification + active-session relabeling + Back-to-Elsewhere (`daa8718`, `0a3a9ea`, `e4a348e`, `5617689`), 2d karaoke session helpers + stage.html session integration (`db/013` + multiple commits), 2e push notification infrastructure + role-aware UI + self write actions + manager queue UI (multiple commits, latest `af1e468` at v2.120). 2f deferred to consolidation per audience.html no-investment doctrine. BUG fixes during 2e.3: `ce36fe5` (BUG-5), `1b870d3` (BUG-10 at v2.118), `ad97ea5` (BUG-13/3/7 at v2.119). Closeout: `1d481b4` (5 papercuts + closing log), `7f8f97e` (5 open bugs filed to DEFERRED).

**Commits (Part 3a — Games integration):**
- `05d2cae` — db/016 manager-only soft-removal RPC
- `ea89c48` — Part 3a.1 session/participants plumbing (v2.100)
- `8bff27b` — Part 3a.2 manager controls (v2.101)

**Commits (Part 3b — Trivia productionization + premium opt-in via Edge Function):** full detail in `docs/SESSION-5-PART-3B-CLOSING-LOG.md`. v2.108 → v2.113, Edge Function + db/019, shipped 2026-05-04.

**Commits (Part 3c — `admission_model_v2` §10, W1-W10):** full detail in `docs/SESSION-5-PART-3C-CLOSING-LOG.md`. W1-W6 ended at `cef155c` v2.121 (pre-2026-05-18). W7 `68e8ee9` v2.122. W8 `b6898ea` → `2432d86` v2.123 → v2.131 (9 commits). W9 `02cdc08` (db/024) + `a1273df` + `5c1f97f` v2.132 + `6b12290` v2.133. W10 `014c738` → `a7dd71a` v2.134 → v2.137 + tv `v2.101` (4 commits).

**Workstream pivot.** Part 5 verification (multi-user end-to-end testing) was not run as a discrete Session-5 closeout. The work pivoted directly to the unified-app workstream's Phase 1 schema rework on 2026-05-21 (see "Unified-app workstream — Phase 1" above). Phase 1 entirely subsumes the Session-5 participant model by introducing the `rooms` entity and re-anchoring `session_participants` to `room_id`. The Session-5 schema (`session_participants` keyed by `session_id`) is therefore superseded; the data was cleared as a clean-slate migration pre-step (acceptable since pre-launch + ephemeral data).

**DEFERRED entries that emerged:** many across all parts; see per-part closing logs for specific entries. The §10 W10 Cleanup tasks (APP_MANIFEST shrink, doc supersession edits, CLOSEOUT-PLAN restructure, DEFERRED mark-obsolete sweep) remain tracked as `docs/DEFERRED.md` "admission_model_v2 §10 W10 cleanup tasks".

**Details:** `docs/SESSION-5-PLAN.md`, `docs/SESSION-5-PART-2-BREAKDOWN.md`, `docs/SESSION-5-PART-2-CLOSING-LOG.md`, `docs/SESSION-5-PART-3-AUDIT.md`, `docs/SESSION-5-PART-3-CLOSING-LOG.md`, `docs/SESSION-5-PART-3B-CLOSING-LOG.md`, `docs/SESSION-5-PART-3C-CLOSING-LOG.md`, `docs/ADMISSION-MODEL-V2.md`, `docs/GAMES-CONTROL-MODEL.md`, `docs/SESSION-5-CLOSEOUT-PLAN.md` (the never-executed verification plan).

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
