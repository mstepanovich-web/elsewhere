# Elsewhere — Project Context

> This document is the kickoff for any new chat. Pasted at the start, it
> gives a fresh Claude the mental model, conventions, and current state
> needed to work productively without re-reading every doc in the repo.
>
> Read top-to-bottom. Pointers to deeper docs are at the end.

Last updated: 2026-05-21 (Phase-1 unified-app migration progress addendum: db/025 applied 2026-05-21; db/026 + db/027 committed+pushed-not-applied; db/028 next. See "Current state" → "Other context" bullets and "Up next" item 1. Prior 2026-05-20 update — unified-app planning docs commit + model-section revisions — is unchanged.)

---

## What Elsewhere is

Elsewhere is a multi-device living-room platform for shared experiences. The TV is the centerpiece (something the household watches together); phones in the room are controllers, performers, and audience devices. Today's app catalog: **Karaoke** (live, primary), **Games** (Last Card / Trivia / Euchre, in progress), **Wellness** (placeholder).

The product is built around a few core ideas:

- **The TV is the stage.** The TV runs `tv2.html` (idle launcher) or one of the per-app TV surfaces (e.g. `karaoke/stage.html` during karaoke). It is a passive display that reacts to phones in the room.
- **Phones are controllers and participants.** Each phone in a household runs its own surface. For karaoke, that's `karaoke/singer.html` for active/queued/audience users.
- **Users, devices, and households.** Every registered user is a first-class user of every app — no TV device required. An embed-capable TV device adds the immersive capability (camera compositing into the venue) but is not a participation gate. Households exist but do not gate participation; the full model is in `docs/UNIFIED-APP-PLAN.md` and `docs/HOUSEHOLD-DEVICE-PRESENCE-MODEL.md`.
- **Real-time everything.** State changes propagate via Supabase Realtime channels. The TV, the phones, and the manager all see the same state in <2 seconds.

---

## Apps and surfaces

### Karaoke (live)
- **TV surface:** `karaoke/stage.html` — shows lyrics, video background (DeepAR), Agora voice routing, idle screen between songs
- **Phone surface:** `karaoke/singer.html` — every phone runs this; rendering is role-aware
- **`karaoke/audience.html`** — the current separate audience surface. In the unified-app model this is dissolved into a baseline watcher mode within the main app; see `docs/UNIFIED-APP-PLAN.md`.

### Games (in progress)
- **TV surface:** `games/games.html`
- **Phone surface:** `games/...` per-game surfaces

### Wellness (placeholder)
- **TV surface:** `wellness/...` — coming soon

### Shell (the meta-app)
- **TV idle:** `tv2.html` — the launcher between apps
- **Phone home:** `index.html` — household home, app picker, proximity prompt
- **Sign-in / claim flow:** `claim.html`

---

## The "Way 1 / Way 2" distinction (karaoke-specific)

Karaoke can run two ways and code paths preserve both:

- **Way 1 (legacy single-singer):** No `session_participants` row exists. The phone is the singer; everything is local-state. `currentMyRow` is null. Used as a fallback and for testing.
- **Way 2 (multi-user session):** Real `session_participants` rows exist. Each phone has a `participation_role` (audience / queued / active) and a `control_role` (member / manager). All today's role-aware UI is conditional on Way 2 state being present.

Code in `singer.html` checks `currentMyRow` for null and falls back to Way 1 if so. This dual-mode means we can iterate on Way 2 without breaking single-user testing.

---

## Roles

Every `session_participant` row has two role columns:

### `participation_role`
What the user IS doing in the session, right now:
- `audience` — opt-in watcher mode, reversible (see "The 'audience' model" below)
- `queued` — has signed up to sing; waiting their turn
- `active` — currently singing (or about to)

State machine: `audience → queued → active → audience` (cycle); `queued → audience` (leave queue); manager can force any transition.

### `control_role`
The `control_role` distinguishes a `member` (acts on their own row only) from a `manager` (acts on any row). In the unified-app model, manager authority belongs to the ROOM, not the session, and splits into room control (operational authority — queue, admit/remove, drive the screen — fully transferable) and room ownership (the personal binding to the convener's saved rooms — never transfers by succession). One room has one manager at a time. See `docs/ROOM-AUTHORITY-MODEL.md`.

---

## The "audience" model

"Audience" is a participation MODE, not a class of user. Any user can choose to watch rather than play (`participation_role = 'audience'`) and can leave that mode again — it is opt-in and reversible. There is no separate class of "audience users" and no separate audience surface in the target model: `karaoke/audience.html` is being dissolved into a baseline-tier watcher mode inside the main app.

(Historical note: earlier docs describe an "audience vocabulary trap" — schema-state `'audience'` vs. a surface-label "Audience" for a distinct can't-participate population. The unified-app model removes that distinction. See `docs/UNIFIED-APP-PLAN.md` and `docs/HOUSEHOLD-DEVICE-PRESENCE-MODEL.md`.)

---

## Baseline and immersive (the capability model)

Every registered Elsewhere user is a full, primary user of every app at the BASELINE tier — with no TV device required. Non-household users (NHHU) are first-class users, not a degraded or secondary case.

IMMERSIVE is a single optional capability on top of baseline: being camera-composited into the venue (with costume overlays). It is derived, not stored — there is no account-level entitlement. Immersive activates when a user is connected to a TV device whose `tv_devices.can_embed` is true AND has declared presence at that device. It is a property of the user's physical situation, not of the user's account, and is not gated by household membership.

This supersedes the earlier "HHU + at-home + has-TV = primary; everyone else is secondary" doctrine. The full model is in `docs/UNIFIED-APP-PLAN.md` and `docs/HOUSEHOLD-DEVICE-PRESENCE-MODEL.md`.

---

## Architecture

### Web bundle on GitHub Pages
The repo is served at `https://mstepanovich-web.github.io/elsewhere/`. Every push to main deploys within ~60 seconds. Phones in Mobile Safari and the Capacitor iOS app load this bundle.

### Capacitor iOS shell
`~/Projects/elsewhere-app/` contains a Capacitor 8.3.1 iOS app. Its bundled web payload is `~/Projects/elsewhere-app/www/` which gets copied (via `npx cap sync ios`) into `ios/App/App/public/`. The iOS app loads from this bundled payload, not from GitHub Pages.

To update what runs in the iOS app:
1. `rsync` from repo to `~/Projects/elsewhere-app/www/` (with appropriate excludes)
2. `npx cap sync ios`
3. Xcode rebuild + install on phone

Sync only when you need to test something native (push notifications, Capacitor plugins, fullscreen). Otherwise iterate in Mobile Safari against GitHub Pages.

### Supabase backend
Project: `gbrnuxyzrlzbybvcvyzm`

- **Auth:** Supabase magic-link OTP. Sign-in via emailed link; iOS app uses `elsewhere://auth/callback` deep link, web uses GitHub Pages URL.
- **Database:** Postgres with RLS. Migrations in `db/`. RPCs do most of the writes.
- **Realtime:** broadcast channels per device (e.g., `tv_device:<device_key>`). Listeners on phone, TV, and audience all subscribe to the same channel.
- **Edge Functions:** in `supabase/functions/`. Currently: `send-push-notification`.
- **Vault:** `vault.decrypted_secrets` for trigger-side secrets like `edge_fn_url` and `service_role_key`.
- **pg_net:** enabled. Used by Postgres triggers to call Edge Functions async.

### Agora (voice/video)
Used for in-session mic + video. Channel name = `elsewhere_<room_code>`. Singer publishes mic; stage subscribes. Manager Override (planned in 2e.3) will have the manager join as host.

### DeepAR (v2.01)
Background segmentation on `singer.html` and `stage.html`. Replaces MediaPipe (was v1). Uses `rootPath` CDN + `background_segmentation` slot. AR filters work via `drawSinger(deepARCanvas, mask)`.

### APNs (push notifications)
Apple Push for the Capacitor app. Token registration on app launch (handled by `@capacitor/push-notifications`). Service-side fires through Edge Function `send-push-notification`. Currently sandbox-only.

---

## Locked doctrine

Things we don't re-litigate:

- **Observed misbehavior gets checked against `docs/DEFERRED.md` before being treated as a new bug.** Many "weird" behaviors on current surfaces are tracked debt with a known resolution phase — re-investigating one wastes a chat session. Grep DEFERRED.md for the affected surface, the visible symptom (e.g. "legacy mode", "audience", "manager UI hidden", a specific column name), or the relevant table/RPC before opening an investigation. See also the "Known-degraded surfaces" note in Current state.
- **The unified-app model is now authoritative for the user/role/audience model.** Baseline vs. immersive capability, audience-as-mode, the room/session split, and room authority are defined in the five planning docs (`docs/UNIFIED-APP-PLAN.md` and its four companions). Where this doctrine list and the planning docs disagree, the planning docs win.
- **Way 1 / Way 2 dual-mode:** every singer.html change preserves Way 1 fallback.
- **`control_role` vs `participation_role`:** they're orthogonal axes, never collapsed. A manager can be queued. A member can be active.
- **RPCs publish realtime; direct SQL UPDATEs do not.** All client-side mutations go through RPCs (`rpc_session_update_participant`, etc.) which broadcast `participant_role_changed` events. Direct SQL is for testing/admin only and connected clients won't react.
- **Back-to-Elsewhere pill (← Elsewhere) is the canonical exit** from any app surface. No redundant Home tile, no breadcrumbs, no other exit.
- **`sounds/ui/`** for application UI sounds (notifications, transitions). `sounds/` root is for venue ambient.
- **Absolute URLs for asset paths** in deployed-pages code (e.g., `https://mstepanovich-web.github.io/elsewhere/sounds/ui/take-stage.mp3`). GitHub Pages rewrites can break relative paths.
- **Edge Function `send-push-notification` deploys MUST include `--no-verify-jwt`.** Without it, the Postgres trigger's bearer token gets rejected by Supabase's edge gateway. See 2e.2 log known issues for the full story.
- **Vault secret `service_role_key`** is now a misnomer (it holds `PROMOTION_TRIGGER_SECRET`, not the service role JWT). Name kept for db/015 SQL backward compat.
- **iOS bundle drift is acceptable mid-session.** Sync only when testing native concerns (push, plugins).
- **iOS Capacitor sync at session close.** Any session that ships user-facing web bundle changes ends with `npx cap sync ios` + Xcode rebuild + install verification on a real iOS device. See CLAUDE.md "iOS Capacitor sync — session-closing ritual" for the full chain.
- **TextEdit will mangle code files.** Always use a real editor (Cursor, VS Code, etc.) or `pbcopy` from terminal.
- **Chat-display autolinks `.md`/`.ts`/`.sql` filenames** as `[name](http://name)` — purely visual, real filesystem is clean. Use `ls | cat` to verify if uncertain.

---

## Repo layout

```
elsewhere-repo/
├── index.html             # Phone home (household app picker)
├── tv2.html               # TV idle launcher
├── claim.html             # Sign-in + TV claim flow
├── elsewhere-theme.css    # Design tokens (colors, fonts, spacing)
├── karaoke/
│   ├── singer.html        # Phone surface (active/queued/audience)
│   ├── stage.html         # TV surface during karaoke
│   ├── audience.html      # Out-of-home audience surface
│   └── ...
├── games/                 # Per-game surfaces
├── wellness/              # Coming soon
├── shell/                 # Cross-app modules (realtime, auth, etc.)
├── sounds/                # Venue ambient audio
│   └── ui/                # App-level UI sounds
├── venues/                # Venue background images
├── db/                    # Postgres migrations
│   └── 015_promotion_push_trigger.sql
├── supabase/
│   └── functions/
│       └── send-push-notification/
├── docs/                  # Audit docs, plans, session logs
└── CLAUDE.md              # Coding doctrine for Claude assistants
```

Don't put server-side dirs (`db/`, `supabase/`) into the iOS bundle — they're not needed and add weight.

---

## Versioning

- **`singer.html` has its own version stamp** (currently `v2.110`). Bumped per session.
- **Other surfaces have independent stamps** (e.g., shell `v2.99`).
- **Sessions are numbered like `5-2e-2`** = Session 5, Part 2e (sub-phase), iteration 2.
- **Commits are tagged with the section** like `karaoke(2e.2): foundation helper [v2.104]`.

---

## Current state (May 2026)

### Known-degraded surfaces (do not file as new bugs)

The four pre-Phase-3 surfaces — `karaoke/singer.html`, `karaoke/stage.html`, `games/player.html`, `games/tv.html` — carry stale `sessions` SELECTs that reference columns dropped by db/025 (`manager_user_id`, `room_code`, `tv_device_id`). When exercised against prod they 400, `refreshSessionState()` falls into legacy mode, and `currentMyRow` stays null — manager UI hidden, control roles unrecognized, the page looks like a passive "audience" surface even for the actual manager. This is **known tracked debt, NOT a regression** — see `docs/DEFERRED.md` "schema-stale sessions SELECTs/filters on the four pre-Phase-3 surfaces". Resolves in Phase 3 (karaoke surfaces) and Phase 4 (games surfaces) of UNIFIED-APP-PLAN §5, paired with the C2 surface-side completion. Until those phases land, degraded-mode rendering on these surfaces is expected; do not file as new bugs.

### Latest shipped: admission_model_v2 W7-W10 — games admission implementation (2026-05-18 → 2026-05-19)
- `games/player.html` at `v2.137` on `origin/main`; `games/tv.html` at `v2.101`
- 18 commits across two days implementing `admission_model_v2` §10 work-packages W7-W10 (W1-W6 shipped earlier). **W7** retired the vestigial Last Card `managerNextRound` path. **W8** (9 commits) shipped Pause + Leave UI on game surfaces and, beyond its §10 scope, restructured the manager / player control surfaces into app-level singleton bars and refactored Trivia routing. **W9** added implicit-leave detection — `db/024` (`last_seen_at` + `rpc_session_heartbeat` with server-side prune) plus a client heartbeat bundled into the existing 20s keepalive. **W10** shipped issue fixes + Last Card UX polish (top-strip card color, double-tap to play, un-mirrored opponent initials) + the W5 dead-code sweep + 12 new DEFERRED entries. Full forensic detail, deviations vs §10, and hardware-verification status: `docs/SESSION-5-PART-3C-CLOSING-LOG.md`.

### Recent shipped: Trivia productionization + Trivia Phase 2 premium opt-in (2026-05-04)
Made Trivia playable end-to-end for the first time (OpenTDB swap replacing the broken browser-direct Anthropic call) and added premium AI-generated questions via a Supabase Edge Function (`generate-trivia` + `db/019`, 20/user/UTC-day). `games/player.html` v2.108 → v2.113. Full detail: `docs/SESSION-5-PART-3B-CLOSING-LOG.md` + `docs/SESSION-5-PART-3B-VERIFICATION-LOG.md`. The 2026-05-03 active/audience UX cluster that preceded it is covered in `docs/SESSION-5-PART-3-CLOSING-LOG.md`.

### Other context
- Migrations tracker shipped 2026-05-02 (`97f1e83`). All 20 migrations listed in `db/MIGRATIONS_APPLIED.md`; db/015 verified ✅ 2026-05-03; db/017, db/018, db/019 all flipped to ✅ same-day as application.
- `db/016_remove_participant.sql` applied to prod 2026-05-02
- `db/019_trivia_premium_usage.sql` applied to prod 2026-05-04 (`8d70473` flip commit)
- `db/024` (`session_participants.last_seen_at` + `rpc_session_heartbeat` with server-side prune) applied to prod 2026-05-19 (`a1273df` flip commit)
- `db/025` (Phase-1 rooms schema + session re-anchor — the unified-app workstream's schema cutover) applied to prod 2026-05-21 (`0843168` flip commit)
- `db/026` (Phase-1 RPC batch 1 — 10 of 14 session-keyed RPCs to room-keyed) committed+pushed `9e3926e`. NOT yet applied.
- `db/027` (Phase-1 RPC batch 2 — rpc_session_start split + new rpc_room_create) committed+pushed `2465ff5`. NOT yet applied. Includes the §F amendment + DEFERRED.md entry tracking the shell rework triggered by the rpc_session_start signature change.
- `db/028` (Phase-1 RPC batch 3 — rpc_session_leave + reclaim RPCs) NOT yet started.
- iOS Capacitor bundle still at v2.99 (pre-3a.1) — sync deferred until next Capacitor-relevant work; Mobile Safari is the verification target per CLAUDE.md doctrine
- One existing Edge Function deployed: `send-push-notification`. Trivia Phase 2 added a second: `generate-trivia`.
- See `docs/SESSION-5-PART-3-CLOSING-LOG.md`, `docs/SESSION-5-PART-3A2-VERIFICATION-LOG.md`, and `docs/GAMES-CONTROL-MODEL.md` § 2.4 + § 4.1 for full details

### Hardware verification status
Most W7-W10 commits are operationally verified through hardware use across the 2026-05-18 → 2026-05-19 sessions, even where individual commit bodies say "static review only" (that phrase reflects the per-commit gate at commit time, before the verification round). `db/024` is verified on prod (`a1273df`; static schema checks + manual prune smoke test + 42501 auth-gate rejection). Outstanding: the W10/cleanup Game Over regression check (low risk — the dead-block null-ref hazard was explicitly handled in the showGameOver knock-on cleanup), and the opponent camera-video black-screen failure surfaced during W10/last-card-polish verification (filed in `docs/DEFERRED.md`). Per-commit detail: `docs/SESSION-5-PART-3C-CLOSING-LOG.md` "Hardware verification status".

### Active deferred items

admission_model_v2 W7-W10 (filed 2026-05-18 → 2026-05-19) — 13 entries in `docs/DEFERRED.md`: 12 from the W10 cleanup commit `a7dd71a` (games UX/architecture papercuts, realtime-reliability items, the opponent camera-video black-screen bug, iOS heartbeat app-lifecycle hooks) plus "admission_model_v2 §10 W10 cleanup tasks" (the four §10-defined cleanup tasks — `APP_MANIFEST` shrink + doc supersession edits — that the W10 label did not actually deliver).

Trivia Phase 2 (filed 2026-05-04, partially mitigated in v2.112) — three polish items in `docs/DEFERRED.md` "Trivia premium polish (post-Phase 2)" entry: lobby card subtitle dynamism, usage indicator UI (partially mitigated by toggle subtext mentioning the 20/day limit), "(premium)" status text styling.

Trivia integration (Session 5 Part 3b) — pre-existing entry in `docs/DEFERRED.md`, status updated 2026-05-04. Active/audience integration scope (late-joiner choice screen, admission_mode dispatch, Skip Question wiring) still pending. Anthropic-fragility sub-concerns ✅ resolved in Trivia Phase 2.

URL-param routing gap on iOS Safari (filed + resolved 2026-05-04 in `e97dc94`).

Carried from earlier sessions:
- TV2 doesn't recover active session on cold load (Games-side analog of existing 2e.2 entry; needs bootstrap query + broadcast delivery audit)
- Cosmetic: wrong log message on `session_ended` navigation path (diagnosability only, low priority)
- Latent: `karaoke/singer.html` doJoin missing `publishParticipantRoleChanged` (same gap fixed in games/player.html v2.103, mild symptom in karaoke)
- Production APNs cert + entitlement flip (carried from 2e.0)
- Failed-token cleanup on APNs 410 BadDeviceToken (carried from 2e.0)
- Custom confirm-modal styling (papercut from 2c.2 / 2c.3 / 2e.2 §4)
- Pre-existing JS error at `singer.html:645` (`stat-w` element missing)
- **Working-tree artifacts**: empty 0-byte files `-H` and `-d` in repo root, persisted across the 2026-05-04 session. Likely from a malformed shell command (cURL flag-parsing mishap or earlier `git commit -m "$(cat <<EOF...)"` quote failure). Not in any commit; safe to `rm -- '-H' '-d'` when convenient.

Active/audience cluster (closed 2026-05-03, kept here for closure-trail):
- ~~GAMES-CONTROL-MODEL.md spec gap on lobby-state participation~~ — **Resolved 2026-05-02 in `410ccc1`**.
- ~~Default `participation_role` for self-join is `'audience'` instead of `'active'`~~ — **Resolved 2026-05-03** via the v2.104 → v2.105 → Cluster Commit 2.6 chain.
- ~~No participant-side "I'm playing in this game" toggle~~ — **Resolved 2026-05-03 in `ae276f7`**.
- ~~Manager lobby view doesn't differentiate active vs audience~~ — **Resolved 2026-05-03 in `ae276f7`**.
- ~~No tracking of which `db/*.sql` migrations have been applied to production~~ — **Resolved 2026-05-02 in `97f1e83`**.

### Up next

Near-term:
1. **Unified-app / NHHU-primary — planning COMPLETE; Phase-1 migration in progress.** The design is captured in five docs in `docs/`: UNIFIED-APP-PLAN.md (umbrella), ROOM-SESSION-MODEL.md, ROOM-AUTHORITY-MODEL.md, ROOM-ACCESS-INVITE-MODEL.md, HOUSEHOLD-DEVICE-PRESENCE-MODEL.md. Phase-1 execution: schema migration db/025 applied (2026-05-21); RPC batches db/026 (`9e3926e`) and db/027 (`2465ff5`) committed+pushed, not yet applied; db/028 (rpc_session_leave + reclaim RPCs) is the next batch to write. See `docs/EXECUTION-HANDOFF.md` for the per-migration handoff brief.
2. **Part 5 verification** — multi-user end-to-end testing of Session 5 flows; requires 2+ test accounts.

> The previous near-term tier ("Trivia 3b proper / Last Card 3c / Euchre 3d") is superseded — `admission_model_v2` §9.6 restructured per-game integration into the W1-W10 work-packages, now shipped (see Latest shipped).

Medium-term (post-Session-5, hard-ordered):
4. **Session 6** — SMS pre-invites for household onboarding (~1-2 hr; was Session 4.10.1)
5. **Session 7** — Admin management UI (~2-3 hr; was Session 4.11)
6. **Session 8** — Trivia premium UX differentiation
7. **Session 9** — Audience.html unification (NHHU → HHU UI merge) (keystone)
8. **Session 10** — Venues at platform level (cross-app service)
9. **Session 11** — Audience-to-NHHU conversion path (user-acquisition funnel)
10. **Session 12** — Wellness app implementation

See `docs/ROADMAP.md` for each session's why, estimate, dependencies, and canonical doc references.

Cleanup: remove the working-tree `-H` and `-d` artifact files. One-line `rm`. Filed in deferred items above.

---

## Where to look for deeper context

If a topic comes up that needs more than what's in this document, point Claude to the right doc:

| Topic | Doc |
|---|---|
| Unified-app / NHHU-primary planning (umbrella — read first) | `docs/UNIFIED-APP-PLAN.md` |
| Room / session / group entity model | `docs/ROOM-SESSION-MODEL.md` |
| Manager authority — room control + room ownership | `docs/ROOM-AUTHORITY-MODEL.md` |
| Room-access / invite model (token-based, Edge Function) | `docs/ROOM-ACCESS-INVITE-MODEL.md` |
| Households, TV devices, binding, presence, immersive capability | `docs/HOUSEHOLD-DEVICE-PRESENCE-MODEL.md` |
| Karaoke roles, transitions, surfaces, role-aware rendering — **partially superseded by `docs/UNIFIED-APP-PLAN.md` / `docs/ROOM-AUTHORITY-MODEL.md` / `docs/HOUSEHOLD-DEVICE-PRESENCE-MODEL.md`** | `docs/KARAOKE-CONTROL-MODEL.md` |
| Games roles + state machines + admission modes — **partially superseded by `docs/UNIFIED-APP-PLAN.md` / `docs/ROOM-AUTHORITY-MODEL.md` / `docs/ROOM-SESSION-MODEL.md`** | `docs/GAMES-CONTROL-MODEL.md` |
| Phone + TV state model (claim, registration, presence) — **superseded by `docs/HOUSEHOLD-DEVICE-PRESENCE-MODEL.md`** | `docs/PHONE-AND-TV-STATE-MODEL.md` |
| Long-term roadmap | `docs/ROADMAP.md` |
| admission_model_v2 W7-W10 forensic detail (2026-05-18 → 2026-05-19) | `docs/SESSION-5-PART-3C-CLOSING-LOG.md` |
| admission_model_v2 canonical design (two-mode/three-role/game-room) — **partially superseded by `docs/ROOM-SESSION-MODEL.md` / `docs/UNIFIED-APP-PLAN.md`** | `docs/ADMISSION-MODEL-V2.md` |
| 2026-05-04 Trivia productionization + Phase 2 forensic detail | `docs/SESSION-5-PART-3B-CLOSING-LOG.md` |
| 2026-05-04 hardware verification audit trail | `docs/SESSION-5-PART-3B-VERIFICATION-LOG.md` |
| 2026-05-03 active/audience cluster forensic detail | `docs/SESSION-5-PART-3-CLOSING-LOG.md` |
| 2026-05-02/03 active/audience cluster verification trail | `docs/SESSION-5-PART-3A2-VERIFICATION-LOG.md` |
| Most recent karaoke session details (full debug history) | `docs/SESSION-5-PART-2E2-LOG.md` |
| Session 5 plan and breakdown | `docs/SESSION-5-PLAN.md`, `docs/SESSION-5-PART-2-BREAKDOWN.md` |
| 2e phase audit (where 2e.0 / 2e.1 / 2e.2 / 2e.3 came from) | `docs/SESSION-5-PART-2E-AUDIT.md` |
| Eligibility model decisions | `docs/SESSION-5-PART-2E-MODEL-AUDIT.md` |
| Doctrinal coding rules for Claude | `CLAUDE.md` |
| Deferred items not yet scheduled | `docs/DEFERRED.md` |
| Doc index | `docs/INDEX.md` |

---

## Working style

A few patterns that have worked well in past sessions:

- **Read-before-write.** Before extending a helper or modifying a function, read its current implementation. Catches bugs from misremembered behavior.
- **Section commits.** Multi-part work ships as multiple small commits, one per section, with explicit version bumps.
- **Honest commit messages.** Third `-m` says what was actually verified (static review only / browser tested / real-device tested), never claims more.
- **Static checks aren't tests.** Grep + line-count checks tell you the code landed; only runtime exercises verify behavior.
- **For new tools/hosts** (like Supabase Edge Functions, pg_net): verify env-var assumptions before relying on them. Don't trust historic behavior across product migrations.
- **Mobile Safari first, Xcode last.** Most iteration happens against GitHub Pages from Mobile Safari. Sync to iOS only when testing native concerns (push, plugins, fullscreen).
- **Approval dialogs are review gates.** Each Claude Code dialog is a chance to catch issues — read the diff carefully, don't auto-approve.

---

## How to use this document

When starting a new chat:

```bash
cat ~/Downloads/elsewhere-repo/docs/CONTEXT.md | pbcopy
```

Then paste into the new chat with a one-line task description:

```
Continuing Elsewhere development. Project context:

<paste CONTEXT.md contents>

Today: <what you want to work on>
```

For complex tasks that touch deeper context, append the relevant doc(s):

```bash
cat ~/Downloads/elsewhere-repo/docs/CONTEXT.md \
    ~/Downloads/elsewhere-repo/docs/KARAOKE-CONTROL-MODEL.md \
    ~/Downloads/elsewhere-repo/docs/SESSION-5-PART-2E2-LOG.md \
    | pbcopy
```

When this document drifts from reality:

- Mental model, doctrine, repo layout — update these only when something fundamental changes
- Current state, latest session, up next — update at the end of every session as part of session-log shipping

---

## End of context
