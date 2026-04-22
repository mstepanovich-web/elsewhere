# Roadmap

High-level session pipeline so we don't lose context between sessions. Updated at the end of each session and at the start of each planning session.

---

## Active session

**Session 4.10.2 — Phone-as-remote UX fixes**
- **Status:** Parts A+B+C shipped + navigation/await fixes landed. Phone-as-remote verified working end-to-end on real hardware. Parts D–G (sign-in copy rewrite, post-claim transition, verification doc, PHASE1-NOTES + version bump) remain.
- **Estimated:** 1.5–2 hours
- **Includes:** phone-as-remote redesign + TV sign-in screen copy rewrite
- **Why it's next:** Session 4.10 verified end-to-end (see `PART-E-VERIFICATION.md`) but exposed three coupled UX failures that block real customer usability. Smaller follow-up session to resolve.

### Commits shipped in 4.10.2

- `4a331d6` — Parts A+B (phone Your TVs + remote control)
- `4372a20` — Part C (TV launch listener + display-only grid)
- `56e6e3d` — Navigation fix (phone follows TV into app)
- `7b81f70` — Await fix (phone waits for publish before navigating)

### Deferred items that emerged during 4.10.2

Five High-priority DEFERRED entries captured during design discussion + testing. All feed into Session 5's multi-user + session-manager work:

- Phone back-to-Elsewhere + TV teardown
- Multi-phone session coordination + session manager role
- Proximity self-declaration
- Session manager inactivity + household-admin override
- Per-app role manifest

See `docs/DEFERRED.md` for full entries.

---

## Queued sessions

> **Note on numbering:** Session numbers reflect topical relation to 4.10, not execution order. 4.10.2 ships before 4.10.1 because 4.10.2 fixes user-blocking UX issues surfaced in 4.10's verification, while 4.10.1 (SMS pre-invites) is a scaling concern that doesn't block current usage.

### Session 4.10.1 — Phone-based household pre-invites (SMS)

- **Why:** needed before scaling household onboarding past direct email invites
- **Estimated:** 1–2 hours
- **Depends on:** nothing (orthogonal to 4.10.2 — can swap order if needed)
- **Reference:** `DEFERRED.md` → "Phone-based household pre-invites (SMS verification)"

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
