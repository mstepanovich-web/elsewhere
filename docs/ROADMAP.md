# Roadmap

High-level session pipeline so we don't lose context between sessions. Updated at the end of each session and at the start of each planning session.

---

## Active session

**Session 5 — Universal session + participants + queue model**
- **Status:** Part 1 complete. Part 2 complete (2a-2e shipped; 2f deferred to consolidation per audience.html no-investment doctrine, closeout `1d481b4`). Parts 3-5 pending.
- **Estimated remaining:** 10-15 hours across 3-5 sessions. Part 3 ~8-12 hr (Games — likely needs Games Control Model doc + sub-decomposition; SESSION-5-PLAN.md's 2-3 commit estimate is under-scoped per Part 2 precedent). Part 4 ~0-1 hr (substantially absorbed into 2c). Part 5 ~2-3 hr verification with 2+ test accounts.
- **References:** `docs/SESSION-5-PLAN.md`, `docs/SESSION-5-PART-2-BREAKDOWN.md`, `docs/SESSION-5-PART-2-CLOSING-LOG.md`

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

**Next up:** Part 3 — Games integration. SESSION-5-PLAN.md § Part 3 specifies role manifests for Last Card / Trivia / Euchre and obsoleting the `?mgr=1` URL param via session_participants lookup. **Likely Part 3 prerequisites** (parallels Part 2 work): pre-implementation audit doc + Games Control Model doc + per-game sub-decomposition (3a/3b/3c). See `docs/SESSION-5-PLAN.md` lines 333-349 for the original Part 3 work breakdown.

---

## Queued sessions

> **Note on numbering:** Session numbers reflect topical relation to 4.10, not execution order. 4.10.2 and 4.10.3 shipped before 4.10.1. Session 5 is now in progress ahead of both 4.10.1 and 4.11 because its multi-user schema unblocks real multi-user apps. 4.10.1 (SMS pre-invites) and 4.11 (admin UI) remain queued behind Session 5.

### Session 4.10.1 — Phone-based household pre-invites (SMS)

- **Why:** needed before scaling household onboarding past direct email invites
- **Estimated:** 1–2 hours
- **Depends on:** nothing (orthogonal to Session 5)
- **Reference:** `DEFERRED.md` → "Phone-based household pre-invites (SMS verification)"

### Session 4.11 — Admin management UI

- **Why:** 4.10 ships with no household admin UI beyond pre-invite. Member roster, demote/promote, scan-approval flow, pending invites inbox all need first-class UI surfaces.
- **Estimated:** 2–3 hours
- **Depends on:** 4.10 RPCs (already shipped — `rpc_approve_household_member`, `rpc_designate_admin`)
- **Reference:** `DEFERRED.md` → "Scan-approval flow", "Pending Invitations inbox"

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
