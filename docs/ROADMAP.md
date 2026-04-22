# Roadmap

High-level session pipeline so we don't lose context between sessions. Updated at the end of each session and at the start of each planning session.

---

## Active session

**Session 4.10.1 — Phone-based household pre-invites (SMS)**
- **Status:** queued, not yet started (promoted after 4.10.3 closed)
- **Estimated:** 1–2 hours
- **Why it's next:** 4.10.2 and 4.10.3 shipped their core UX work. 4.10.1 is the remaining 4.10-family follow-up. Non-blocking for current usage but needed before scaling household onboarding past direct email invites.
- **Reference:** `DEFERRED.md` → "Phone-based household pre-invites (SMS verification)"

---

## Queued sessions

> **Note on numbering:** Session numbers reflect topical relation to 4.10, not execution order. 4.10.2 and 4.10.3 shipped before 4.10.1 because they addressed user-blocking UX issues; 4.10.1 (SMS pre-invites) is a scaling concern that doesn't block current usage.

### Session 4.11 — Admin management UI

- **Why:** 4.10 ships with no household admin UI beyond pre-invite. Member roster, demote/promote, scan-approval flow, pending invites inbox all need first-class UI surfaces.
- **Estimated:** 2–3 hours
- **Depends on:** 4.10 RPCs (already shipped — `rpc_approve_household_member`, `rpc_designate_admin`)
- **Reference:** `DEFERRED.md` → "Scan-approval flow", "Pending Invitations inbox"

### Session 5 — session_participants schema

- **Why:** room codes are a hack. `session_participants` replaces them with proper session identity, fixes the games lobby fragility, the deep-link auto-manager bug, the karaoke shared-state issues. Big refactor.
- **Estimated:** 4–6 hours, possibly split across sessions
- **Depends on:** 4.11 (some admin context flows feed into session ownership)
- **Reference:** `DEFERRED.md` → "Lobby state fragility", "Games deep-link auto-manager bug", "Last Card leakage", related entries

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
