# Elsewhere — Project Context

> This document is the kickoff for any new chat. Pasted at the start, it
> gives a fresh Claude the mental model, conventions, and current state
> needed to work productively without re-reading every doc in the repo.
>
> Read top-to-bottom. Pointers to deeper docs are at the end.

Last updated: 2026-05-04 (Trivia productionization + Trivia Phase 2 premium opt-in fully shipped — OpenTDB swap + polish [v2.108 → v2.110], generate-trivia Edge Function + db/019 migration deployed and cURL-verified, browser-side premium opt-in wiring [v2.111 → v2.113] with hidden URL easter-egg + in-UI toggle on Trivia info screen + Anthropic Sonnet 4.6 model bump. Trivia is now playable end-to-end for the first time)

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

### Latest shipped: Trivia productionization + Trivia Phase 2 premium opt-in (2026-05-04)
- `games/player.html` at `v2.113` on `origin/main`; `index.html` at `v2.101` (unchanged from 2026-05-03)
- Two tracks shipped today, six commits + Edge Function deploy + db/019 migration to prod:

**Track 1 — Trivia productionization** (made Trivia actually playable for the first time):
- `bc99f13` (v2.108) — Euchre auto-end Bugs A + B fix. Pre-existing race shape analogous to v2.107's Last Card race; surfaced by static audit. Manager-side `gameInProgress=false` set before broadcast in `euEndHand` auto-end branch + `send({type:'game-over', scores})` added inside the 3-second celebration `setTimeout`. Verification deferred (4-player Euchre setup impractical with 2 devices).
- `046d374` (v2.109) — OpenTDB swap. Replaced broken Anthropic-direct `triviaGenerate` (401'd in production per CLAUDE.md doctrine line 140 — no auth header) with `https://opentdb.com/api.php` calls. CATEGORIES array gets `otdbId` field per entry; Food card relabeled to Art (no OpenTDB Food category); 11th "Anything" card added. Anthropic browser-direct path preserved as `// PHASE 2 REFERENCE` comment block (lines 2857–2882). Hardware-verified GREEN against TBFJJH (Movies+Easy, 10 questions, 863 vs 285 final scores) — first-ever working end-to-end Trivia round.
- `4c3a612` (v2.110) — four polish fixes surfaced during the v2.109 verification round: auto-reveal grace period (2s after all submit, idempotent vs manual Reveal/Next via `clearTimeout(_autoRevealTimer)` at top of both); non-manager local timer countdown helper (`startNonManagerTimer`/`stopNonManagerTimer`, 1-second tick, syncs to manager broadcast); progress indicator "Question X of 10" via new `.trivia-progress` CSS class; wrong-answer styling (red border + red-faint background mirroring existing `.trivia-opt.correct` symmetry, repurposed `.trivia-opt.wrong` from `opacity: .4`). Hardware-verified GREEN.

**Track 2 — Trivia Phase 2** (premium AI-generated questions via Anthropic):
- `c4af15c` (Phase 2 Commit A, server-side only) — `supabase/functions/generate-trivia/index.ts` Edge Function (292 LOC) + `db/019_trivia_premium_usage.sql` migration. Trust boundary: Edge Function holds server-side `ANTHROPIC_API_KEY`, validates caller JWT via `supabase.auth.getUser`, enforces 20/user/UTC-day rate limit (composite PK `(user_id, day)`, RLS-enabled-no-policies for service-role-bypass-only access), calls Anthropic with Sonnet 4.6 (`claude-sonnet-4-6` per `https://platform.claude.com/docs/en/docs/about-claude/models/overview` 2026-05-04 — alias and API ID identical, no dated suffix exists). Filter pattern for malformed questions: drop bad ones, ship batch if ≥5 valid remain. **DEPLOY DOCTRINE: WITHOUT --no-verify-jwt flag** (opposite of send-push-notification's pattern; documented inline with explicit ✅/❌ block). cURL-verified GREEN post-deploy. Doubles as the Sonnet 4 deprecation bump (Sonnet 4 retiring 2026-06-15).
- `8d70473` (docs) — db/019 row in `db/MIGRATIONS_APPLIED.md` flipped from ❓ to ✅ after manual SQL Editor application + three-query verification (table exists, RLS enabled, 0 policies).
- `7f1c99c` (Phase 2 Commit B, v2.111) — browser-side premium opt-in wiring. URL-param easter-egg (`?premium=1` → localStorage `elsewhere-trivia-premium=1`, sticky; `?premium=0` clears) + `triviaGenerate` branching (premium path → `window.sb.functions.invoke('generate-trivia')` → `transformPremiumQuestions` defensive validator; on any error → `showToast('Premium unavailable, using free questions')` → silent OpenTDB fallback). Premium gating requires both `isPremiumTrivia()` true AND `getCurrentUser()?.id` non-null. Dynamic subtitle override in `selectGame` for premium-on. OpenTDB code extracted into `fetchOpenTdbQuestions(cat, diff, amount)` helper for reuse.
- `8abbf6e` (docs) — DEFERRED.md SHA substitution for Phase 2 Commit B reference in the Trivia 3b entry.
- `e97dc94` (v2.112) — Trivia premium UI toggle. Replaces URL `?premium=1` easter-egg as primary activation path (URL preserved as backup). Hardware testing surfaced that the URL param gets stripped during session routing on iOS Safari before `isPremiumTrivia()` runs. New in-UI toggle on the Trivia info screen (between info-sub and info-desc): `.premium-row` + `.premium-toggle` CSS mirrors the existing `.camera-opt` + `.camera-toggle` pattern with gold instead of green for `.on`. Label "Premium Questions" / subtext "AI-generated, higher quality · 20/day limit" — limit mention partially mitigates the surprise-429 concern from polish entry's item #2. `togglePremium` writes localStorage immediately, flips pill `.on` class, calls `applyPremiumSubtitle` (extracted from Commit B inline override) for in-place subtitle update. Static HTML with `display:none` initial; selectGame trivia branch sets `display:flex`, syncs pill state from localStorage, calls `applyPremiumSubtitle`.
- `b068c2c` (v2.113) — two small polish fixes: (1) reset stale `trivia-gen-status` textContent on entry to Trivia info screen (was: stale "✓ 10 questions ready! (premium)" persisted across navigation); (2) removed redundant ☰ Games button from manager-bar — added at v2.49 (`ceff8cd`, 2026-04-15) during original Games-mode rewrite, never updated to match the proper End Session / Switch Game / Remove Player semantics introduced at v2.101 (`8825a08`, 2026-04-30). Footgun with no documented use case (no confirm, no broadcast, leaves manager and players out of sync). `goToLobby()` itself preserved (called from 6 other sites: back-link, doJoin routing, switch-game receive, managerSwitchGame, managerEndSession fallback, function definition).

#### Resolved investigations from today (informational, no action required):
- **Reveal feature** (manual override for v2.110 auto-reveal). Confirmed earns its place: handles cases where a player never submits (auto-reveal's all-submitted check won't fire) and where the manager wants to skip ahead before all submissions arrive. Reveal at v2.45 (`147fc9c`, 2026-04-15) plus auto-reveal at v2.110 (`4c3a612`, 2026-05-04) form the complete reveal lifecycle.
- **Games vs Switch Game** distinction. ☰ Games removed in v2.113 as redundant pre-existing artifact (see commit `b068c2c` notes above). Switch Game retained as the proper "leave the current game" affordance.
- **URL `?premium=1` routing gap on iOS Safari**. Resolved by in-UI toggle in v2.112 (`e97dc94`). Query param gets stripped during session routing before `isPremiumTrivia()` runs. URL backup path preserved unchanged for compatibility with bookmarks / muscle memory.

### Recent shipped: Active/audience UX cluster (fully closed 2026-05-03)
Historical context for yesterday's work; details preserved here for archaeological reference. The cluster shipped spec + migrations + default-role fix + shell rejoin bypass + toggle UI + roster sectioning + lock-on-start across cluster Commits 2 → 4 (v2.104 → v2.106 games/player.html + v2.101 index.html), plus adjacent Last Card game-end race fix (v2.107). All 6 verification tests GREEN against test sessions 8DSSXK / SU8RMJ / BVBZ39 / PQ6T3I / TBFJJH. Closeout at `4215387` (2026-05-03). Three pre-Trivia productionization fix-forwards: `b5e1af2` (v2.102, `publishSessionEnded` reused-channel BUG-10 redux), `7dde17c` (v2.103, `doJoin` `participant_role_changed` publish), and `6ce533b` (v2.107, Last Card game-end broadcast race). Spec amendment at `410ccc1` (GAMES-CONTROL-MODEL.md § 2.4 + § 1). Migrations: `db/017` (`8c83b35` + applied at `b1a8e4a`), `db/018` (with v2.105). See `docs/SESSION-5-PART-3-CLOSING-LOG.md` and `docs/SESSION-5-PART-3A2-VERIFICATION-LOG.md` for full cluster details.

### Other context
- Migrations tracker shipped 2026-05-02 (`97f1e83`). All 19 migrations listed in `db/MIGRATIONS_APPLIED.md`; db/015 verified ✅ 2026-05-03; db/017, db/018, db/019 all flipped to ✅ same-day as application.
- `db/016_remove_participant.sql` applied to prod 2026-05-02
- `db/019_trivia_premium_usage.sql` applied to prod 2026-05-04 (`8d70473` flip commit)
- iOS Capacitor bundle still at v2.99 (pre-3a.1) — sync deferred until next Capacitor-relevant work; Mobile Safari is the verification target per CLAUDE.md doctrine
- One existing Edge Function deployed: `send-push-notification`. Trivia Phase 2 added a second: `generate-trivia`.
- See `docs/SESSION-5-PART-3-CLOSING-LOG.md`, `docs/SESSION-5-PART-3A2-VERIFICATION-LOG.md`, and `docs/GAMES-CONTROL-MODEL.md` § 2.4 + § 4.1 for full details

### Hardware verification status
- **All 2026-05-04 commits verified GREEN** on iPhone Safari (Mike) + Mac Chrome (Michael):
  - v2.109 (OpenTDB swap) — TBFJJH, Movies+Easy, 10 questions to completion
  - v2.110 (Trivia polish) — verified all four polish fixes (auto-reveal, non-manager timer, progress indicator, wrong-answer styling)
  - v2.111 (premium opt-in via URL) — partial: surfaced URL routing gap on iOS Safari, leading directly to v2.112
  - v2.112 (premium UI toggle) — verified toggle works end-to-end (subtitle update, status text "(premium)" suffix, toggle state survives navigation)
  - v2.113 (polish) — pending iPhone Safari hardware verification of stale-status reset + ☰ Games removal
- **v2.108 (Euchre auto-end fix) — verification deferred.** 4-player Euchre setup impractical with 2 devices; bug shape and fix shape are exact analogs of the v2.107 Last Card race which verified GREEN, so confidence is high by analogy. See DEFERRED entry "Euchre auto-end path" (resolved status with the v2.108 SHA).
- **All 2026-05-03 active/audience cluster commits** — verified GREEN earlier (see "Recent shipped" sub-section above for cluster verification record).

### Active deferred items

Trivia Phase 2 polish (filed 2026-05-04 in Commit B, partially mitigated in v2.112):
- **Lobby card subtitle dynamism** (`games/player.html` line 403). Hardcoded HTML "AI-generated questions · 2–20 players" inaccurate when premium is OFF. Visible only briefly during game selection; low-impact polish.
- **Usage indicator UI** ("you've used N/20 today"). Would let users see daily premium quota approaching the limit instead of getting a surprise 429. Partially mitigated 2026-05-04 in v2.112 (toggle subtext mentions "20/day limit" upfront); full dynamic counter implementation still deferred. Requires uncommenting the read policy in db/019, applying it, plus a `getRemainingPremiumQuota()` helper.
- **"(premium)" status text styling**. Inline format may feel cluttered; consider a small badge / chip near the status text, or dropping the suffix in favor of the dynamic subtitle as the sole signal.

URL-param routing gap on iOS Safari (filed + resolved 2026-05-04):
- ~~URL `?premium=1` mechanism gets stripped during session routing before `isPremiumTrivia()` runs~~ — **Resolved 2026-05-04 in `e97dc94`** (v2.112) by in-UI toggle. URL backup path preserved.

Trivia integration (Session 5 Part 3b) — pre-existing entry, status updated 2026-05-04:
- Active/audience integration scope (late-joiner choice screen, admission_mode dispatch, Skip Question manager-bar wiring) still pending.
- Anthropic-fragility sub-concerns ✅ resolved in Trivia Phase 2 (Edge Function + Sonnet 4.6 model bump). The "preserve Anthropic call verbatim" sentiment now refers to the `// PHASE 2 REFERENCE` comment block at games/player.html lines 2857–2882, not live code.

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
Three tracks queued, no formal sequencing yet:
1. **Premium UX differentiation** — ways for the premium path to actually feel different from OpenTDB beyond just "AI-generated". Custom categories (manager types a free-form theme like "obscure prog rock"), Wikipedia-aware questions (Anthropic with retrieval to current events), per-user personalization (Trivia tuned to past players' interests). Open design space; nothing committed. The current premium path returns OpenTDB-shaped questions with no inherent quality signal, so this is where the "premium" framing earns its keep.
2. **Trivia 3b proper** — active/audience integration per `docs/GAMES-CONTROL-MODEL.md` § 4.1: late-joiner choice screen (Active vs Audience), admission_mode dispatch in `handleMessage`'s `game-state` receiver, Skip Question manager-bar wiring (currently absent — `mgr-skip` button exists but only fires for Last Card). Modify-existing path per the cluster-closeout audit. Score/streak math, 4-option DOM layout, OpenTDB+Anthropic fetch helpers all preserved verbatim.
3. **Cleanup**: remove the working-tree `-H` and `-d` artifact files. One-line `rm`. Filed in deferred items above.

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
