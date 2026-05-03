# Elsewhere — Project Context

> This document is the kickoff for any new chat. Pasted at the start, it
> gives a fresh Claude the mental model, conventions, and current state
> needed to work productively without re-reading every doc in the repo.
>
> Read top-to-bottom. Pointers to deeper docs are at the end.

Last updated: 2026-05-03 (active/audience UX cluster fully closed — spec + migrations + default-role fix + shell rejoin bypass + toggle UI + roster sectioning + lock-on-start all shipped and hardware-verified through cluster Commit 4 [v2.106 games] plus adjacent Last Card game-end race fix [v2.107 games])

---

## What Elsewhere is

Elsewhere is a multi-device living-room platform for shared experiences. The TV is the centerpiece (something the household watches together); phones in the room are controllers, performers, and audience devices. Today's app catalog: **Karaoke** (live, primary), **Games** (Last Card / Trivia / Euchre, in progress), **Wellness** (placeholder).

The product is built around a few core ideas:

- **The TV is the stage.** The TV runs `tv2.html` (idle launcher) or one of the per-app TV surfaces (e.g. `karaoke/stage.html` during karaoke). It is a passive display that reacts to phones in the room.
- **Phones are controllers and participants.** Each phone in a household runs its own surface. For karaoke, that's `karaoke/singer.html` for active/queued/audience users.
- **Households, not just devices.** Devices belong to households; sessions belong to households; participants are users in those households. This is the "HHU" (household user) model.
- **Real-time everything.** State changes propagate via Supabase Realtime channels. The TV, the phones, and the manager all see the same state in <2 seconds.

---

## Apps and surfaces

### Karaoke (live)
- **TV surface:** `karaoke/stage.html` — shows lyrics, video background (DeepAR), Agora voice routing, idle screen between songs
- **Phone surface:** `karaoke/singer.html` — every phone runs this; rendering is role-aware
- **Audience surface:** `karaoke/audience.html` — for non-household users (out-of-home guests)

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
- `audience` — watching, may or may not be eligible to sing
- `queued` — has signed up to sing; waiting their turn
- `active` — currently singing (or about to)

State machine: `audience → queued → active → audience` (cycle); `queued → audience` (leave queue); manager can force any transition.

### `control_role`
What the user CAN DO administratively:
- `member` — can act on their own row only
- `manager` — can act on any row in the session (queue management, force-promote, skip, take over)

The manager is set when the session is created; usually whoever started the session. Per session, exactly one manager.

---

## ⚠️ Critical vocabulary trap: "audience"

**The word "audience" means two different things in karaoke and they get conflated constantly.** Read this before any task that involves manager actions, queue management, or rendering decisions on singer.html. Re-read it any time a discussion casually says "audience user" — that phrase is almost always ambiguous.

There are two distinct meanings:

### Schema-state `'audience'` (database value)

`session_participants.participation_role = 'audience'` — a database enum value meaning "this user is in the session but is neither the active singer nor in the queue." It is a state, not a role label.

Users with this schema state include both:

- **Available Singers who haven't queued yet** — HHU + at home + has TV device. Eligible to sing. Hasn't tapped Add to Queue. Surface-label: "Available Singer (not queued)."
- **Actual non-singing audience members** — NHHU, OR HHU not at home, OR HHU without a TV device. Cannot sing. Surface-label: "Audience."

The schema does not distinguish these two populations because the underlying queue/promotion logic doesn't need to. Eligibility is computed client-side at the moment of action (Add to Queue, Start Song, etc.).

### Surface-label "Audience" (UI role)

A karaoke UI role meaning "watching only, cannot sing." Lives on `audience.html`. Applied to NHHU users, or HHU users not at home, or HHU users without a TV device. **These users have no path to the queue, no path to active, and the manager UI cannot promote them.**

### What this means for manager UI work (2e.3 and beyond)

When the audit, model doc, or session logs say things like "force-promote an audience user" or "promote from audience" — they are *always* talking about the schema-state, never the surface label. The user being acted on is an Available Singer in disguise (HHU at home with a TV device whose `participation_role` happens to be `'audience'` because they haven't queued yet).

The manager UI on singer.html only operates on rows in `session_participants`. Surface-label Audience users on `audience.html` don't appear in that table in any actionable way (audience.html is a frozen surface in Session 5 — see KARAOKE-CONTROL-MODEL § 4.3). So there is no path by which a manager could force-promote a "can't sing" user; the schema makes this impossible by construction.

### Reading rule

- See `'audience'` in code voice or schema discussion (backticks, `participation_role = 'audience'`, "schema-state audience") → **schema state**. Includes both populations. Manager UI can act on these rows.
- See "Audience" capitalized as a UI role label (in role tables, surface vocabulary, UX copy) → **surface label**. Watching-only users on audience.html. Manager UI cannot act on them.
- When in doubt, the four-role table in KARAOKE-CONTROL-MODEL.md § 1 is canonical. Refer back.

If you find yourself thinking "but audience users can't sing — why is the manager promoting them?" — the language tripped you. Re-read it as the schema state.

---

## HHU eligibility (the doctrinal rule)

`singer.html` surface is **HHU-eligible by construction**. Anyone who reaches singer.html is a household member and is eligible to sing. The not-eligible branch in `singer.html` is dead code — if a non-eligible user ever reaches that surface, the bug is in routing (they should have gone to `audience.html`), not in render. Never write code in singer.html that handles the not-eligible case as a real surface; flag it as dead instead.

(This was locked in 2e.1's model audit, Path A.)

This doctrine is what makes the vocabulary trap above resolve cleanly in practice: every row the manager UI sees on singer.html with `participation_role = 'audience'` is, by construction, an Available Singer (eligible). The other population (Surface-label Audience) doesn't reach this surface.

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

- **HHU-eligibility on singer.html:** see above.
- **Way 1 / Way 2 dual-mode:** every singer.html change preserves Way 1 fallback.
- **`control_role` vs `participation_role`:** they're orthogonal axes, never collapsed. A manager can be queued. A member can be active.
- **Schema-state `'audience'` ≠ Surface-label "Audience":** see vocabulary-trap section above. Manager UI acts only on the schema state.
- **RPCs publish realtime; direct SQL UPDATEs do not.** All client-side mutations go through RPCs (`rpc_session_update_participant`, etc.) which broadcast `participant_role_changed` events. Direct SQL is for testing/admin only and connected clients won't react.
- **Back-to-Elsewhere pill (← Elsewhere) is the canonical exit** from any app surface. No redundant Home tile, no breadcrumbs, no other exit.
- **`sounds/ui/`** for application UI sounds (notifications, transitions). `sounds/` root is for venue ambient.
- **Absolute URLs for asset paths** in deployed-pages code (e.g., `https://mstepanovich-web.github.io/elsewhere/sounds/ui/take-stage.mp3`). GitHub Pages rewrites can break relative paths.
- **Edge Function `send-push-notification` deploys MUST include `--no-verify-jwt`.** Without it, the Postgres trigger's bearer token gets rejected by Supabase's edge gateway. See 2e.2 log known issues for the full story.
- **Vault secret `service_role_key`** is now a misnomer (it holds `PROMOTION_TRIGGER_SECRET`, not the service role JWT). Name kept for db/015 SQL backward compat.
- **iOS bundle drift is acceptable mid-session.** Sync only when testing native concerns (push, plugins).
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

### Latest shipped: Active/audience UX cluster (fully closed) + Last Card game-end race fix
- `games/player.html` at `v2.107` on `origin/main`; `index.html` at `v2.101` (shell rejoin bypass fix)
- 3a foundation chain (3a.1 plumbing → 3a.2 manager controls → 3a.2 hardware verification + fix-forward): see `docs/SESSION-5-PART-3-CLOSING-LOG.md` and `docs/SESSION-5-PART-3A2-VERIFICATION-LOG.md`
- 3a.2 hardware-verified on iPhone Safari + laptop Chrome 2026-05-02: 4/6 gate items fully green; 2/6 partial for environmental + feature-gap reasons (not regressions)
- Two 3a.2 fix-forward commits 2026-05-02:
  - `b5e1af2` (v2.102) — `publishSessionEnded` reused-channel pattern (BUG-10 redux)
  - `7dde17c` (v2.103) — `doJoin` publishes `participant_role_changed` (manager roster propagation on rejoin)
- Active/audience UX cluster (started 2026-05-02, fully closed 2026-05-03 — all 4 commits shipped + verified):
  - Spec amendment: `410ccc1` — GAMES-CONTROL-MODEL.md § 2.4 cluster (§ 2.4.1–§ 2.4.6 NEW: manager-bar buttons, manager toggle, participant toggle, default role at lobby join, manager visibility split, lock-on-start) + § 1 audience definition extended for lobby-state opt-out path
  - Migration db/017: `8c83b35` — `db/017_set_my_participation_role.sql` (self-only RPC for participant active↔audience flip); applied to prod at `b1a8e4a`
  - Default role fix (PARTIAL): `754d0a8` (v2.104) — `doJoin` caller-side override to `'active'` for non-manager fresh joins per § 2.4.4. Hardware verification 2026-05-02 revealed two bypass paths the partial fix didn't cover: (i) the manager path (`rpc_session_start` in db/009 hardcoded `'audience'` regardless of app); (ii) the rejoin/refresh path (doJoin's 23505 catch swallowed all already-a-participant cases without examining role).
  - Default role fix (FULL except shell rejoin path): v2.105 (2026-05-02) — completes § 2.4.4 implementation for the manager path and the games/player.html doJoin path. Migration `db/018_session_start_active_default.sql` branches `rpc_session_start`'s manager insert on `p_app` ('games' → 'active'; 'karaoke' and other → 'audience' preserving karaoke schema-state semantics per `docs/KARAOKE-CONTROL-MODEL.md` § 1). doJoin restructured from join-then-handle-23505 to check-then-conditionally-join via `refreshSessionState` — eliminates 23505 as the every-refresh path; preserves participant toggle state across refresh. Hardware test session KMGGL8 on 2026-05-02 verified the manager path AND doJoin restructure GREEN, but surfaced a third bypass: non-manager joining via the shell home-screen Games tile routes through `index.html` `handleSameAppRejoin` which hardcoded `'audience'` and didn't publish `participant_role_changed`. That bypass closed in cluster Commit 2.6 below.
  - Shell rejoin bypass fix (cluster Commit 2.6): `8825a08` (v2.101 index.html stamp, 2026-05-03) — closes the third bypass. Two prongs in `index.html`: (1) branch the role on `app` at both shell `rpc_session_join` call sites; (2) add `publishParticipantRoleChanged` after each successful join so the manager's roster updates within 1-2s without manual refresh. Hardware-verified GREEN 2026-05-03 against DMZS4G + U97XUQ.
  - Commit 4 (toggle UI + roster sectioning + lock-on-start): `ae276f7` (v2.106 games/player.html, 2026-05-03) — participant "I'm playing in this game" toggle UI (per § 2.4.3, calls `rpc_session_set_my_participation_role` from db/017) + lobby roster sectioning into PLAYING (N) / WATCHING (M) headers (per § 2.4.5) + lock-on-start wiring (per § 2.4.6, `applyToggleLockState()` called from renderRoster + goToGameRoom + watchFromLobby). All 6 verification tests GREEN against test sessions 8DSSXK / SU8RMJ / BVBZ39 / PQ6T3I / TBFJJH on 2026-05-03.
- **Adjacent fix surfaced during Commit 4 verification:** Last Card game-end broadcast race — `6ce533b` (v2.107 games/player.html, 2026-05-03). Manager's End Game broadcast `game-over` correctly, but non-manager's tab-visibility-change recovery code fired `request-state` ~1s later, manager's still-warm `gameInProgress=true` state responded with `game-state phase:playing`, non-manager's game-state handler unconditionally re-rendered Last Card and clobbered the screen-gameover transition. Two-line fix: (1) `managerEndGame` sets `gameInProgress=false` before broadcasting; (2) `game-state` receiver early-returns when `gameInProgress` is false. Hardware-verified GREEN against TBFJJH rematch flow on 2026-05-03.
- Migrations tracker shipped 2026-05-02: `97f1e83` — `db/MIGRATIONS_APPLIED.md` checklist + CLAUDE.md doctrine ("a migration committed to repo is NOT shipped until applied to prod"). All 18 migrations listed; db/015 verified ✅ 2026-05-03 (`07ff37d`); db/017 + db/018 both flipped to ✅ same-day after manual prod application.
- `db/016_remove_participant.sql` applied to prod 2026-05-02 (manual application via Supabase SQL Editor mid 3a.2 verification)
- iOS Capacitor bundle still at v2.99 (pre-3a.1) — sync deferred until next Capacitor-relevant work; Mobile Safari is the verification target per CLAUDE.md doctrine
- See `docs/SESSION-5-PART-3-CLOSING-LOG.md`, `docs/SESSION-5-PART-3A2-VERIFICATION-LOG.md`, and `docs/GAMES-CONTROL-MODEL.md` § 2.4 for full details

### Hardware verification status
- **v2.102 + v2.103 fix-forward** — verified green 2026-05-02 against fresh test environment.
- **v2.104 default-role fix — superseded by v2.105.** Original v2.104 verification plan is moot.
- **v2.105 default-role fix (full except shell rejoin) — partially verified at v2.105 (KMGGL8 surfaced third bypass), then re-verified GREEN 2026-05-03 (DMZS4G) as part of Cluster Commit 2.6's regression smoke.**
- **Cluster Commit 2.6 (v2.101 index.html stamp) — verified GREEN 2026-05-03** against DMZS4G + U97XUQ. All 4 verification steps passed.
- **Cluster Commit 4 (v2.106 games/player.html stamp) — verified GREEN 2026-05-03.** All 6 tests passed against 8DSSXK / SU8RMJ / BVBZ39 / PQ6T3I / TBFJJH (the post-rematch verification room used post-v2.107 deploy). Lock-on-start re-enable half required the v2.107 Last Card race fix to verify; once landed, the rematch flow returned both devices to lobby with toggles correctly enabled and original help text restored.
- **Last Card game-end race fix (v2.107 games/player.html) — verified GREEN 2026-05-03** against TBFJJH rematch flow (Mike → Start New Game → End Game → Play Again Same Players → both devices return to lobby cleanly, no spontaneous re-render to Last Card).

### Active deferred items

Active/audience UX cluster (started 2026-05-02, fully closed 2026-05-03 — all entries resolved):
- ~~GAMES-CONTROL-MODEL.md spec gap on lobby-state participation~~ — **Resolved 2026-05-02 in `410ccc1`** (§ 2.4 cluster amendment + § 1 audience extension).
- ~~Default `participation_role` for self-join is `'audience'` instead of `'active'`~~ — **Resolved 2026-05-03** via the v2.104 → v2.105 → Cluster Commit 2.6 (`8825a08`, v2.101 index.html) chain; closeout commit `c77cc74`.
- ~~No participant-side "I'm playing in this game" toggle~~ — **Resolved 2026-05-03 in `ae276f7`** (cluster Commit 4, v2.106 games/player.html).
- ~~Manager lobby view doesn't differentiate active vs audience~~ — **Resolved 2026-05-03 in `ae276f7`** (cluster Commit 4, v2.106 games/player.html).

Other 3a.2-era items (filed 2026-05-02):
- ~~No tracking of which `db/*.sql` migrations have been applied to production~~ — **Resolved 2026-05-02 in `97f1e83`** (`db/MIGRATIONS_APPLIED.md` checklist + CLAUDE.md doctrine).
- TV2 doesn't recover active session on cold load (and doesn't navigate when phone starts game) — Games-side analog of existing 2e.2 entry; needs bootstrap query + broadcast delivery audit
- Cosmetic: wrong log message on `session_ended` navigation path — diagnosability only, low priority
- Latent: `karaoke/singer.html` doJoin missing `publishParticipantRoleChanged` — same gap fixed in games/player.html v2.103, mild symptom in karaoke

Carried from earlier sessions:
- Production APNs cert + entitlement flip (carried from 2e.0)
- Failed-token cleanup on APNs 410 BadDeviceToken (carried from 2e.0)
- Custom confirm-modal styling (papercut from 2c.2 / 2c.3 / 2e.2 §4)
- Pre-existing JS error at `singer.html:645` (`stat-w` element missing)

### Up next: Session 5 Part 3b — Trivia integration
Active/audience cluster is closed. Next track is Trivia integration per `docs/GAMES-CONTROL-MODEL.md` § 4.1:
- Trivia uses `self_join` admission, late-joiner choice screen (Active vs Audience), manager controls (Reveal/Next/Skip) routed through `control_role` check.
- See `docs/SESSION-5-PART-3-CLOSING-LOG.md` § "Up next" for the full plan.

---

## Where to look for deeper context

If a topic comes up that needs more than what's in this document, point Claude to the right doc:

| Topic | Doc |
|---|---|
| Karaoke roles, transitions, surfaces, role-aware rendering | `docs/KARAOKE-CONTROL-MODEL.md` |
| Phone + TV state model (claim, registration, presence) | `docs/PHONE-AND-TV-STATE-MODEL.md` |
| Long-term roadmap | `docs/ROADMAP.md` |
| Most recent session details (full debug history of last work) | `docs/SESSION-5-PART-2E2-LOG.md` |
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
