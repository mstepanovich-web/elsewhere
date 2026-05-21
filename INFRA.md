# Elsewhere Infrastructure

**Created:** 2026-04-26
**Purpose:** Single source of truth for all moving infrastructure pieces of the Elsewhere project. New contributors / future Claude sessions / future Claude Code invocations should read this first to understand what systems exist before doing infrastructure-adjacent work.

**Update protocol:** When you add, remove, or rename any infrastructure piece, update this file in the same commit. Items marked `[TODO: verify]` are unconfirmed at creation time and should be filled in when verified.

---

## Web app

- **GitHub repo:** [github.com/mstepanovich-web/elsewhere](https://github.com/mstepanovich-web/elsewhere)
- **Local path:** `/Users/michaelstepanovich/Downloads/elsewhere-repo`
- **Deploy URL:** `https://mstepanovich-web.github.io/elsewhere/`
- **Build:** Static, no compile step. HTML/CSS/JS files served as-is.
- **Deploy mechanism:** GitHub Pages auto-deploy on push to `main`. No GitHub Actions workflow (`.github/` directory does not exist) — using legacy "deploy from branch" Pages config.

### Entry points

> **Pointer (2026-05-20):** The framing of `karaoke/audience.html` as a permanent surface and of `nhhu-home.html` as an NHHU-returning-from-audience placeholder is superseded by the NHHU-primary model in [`docs/UNIFIED-APP-PLAN.md`](docs/UNIFIED-APP-PLAN.md). Under that model, audience becomes an opt-in mode within the main app (not a separate surface) and NHHU users are first-class. The table below is retained as a current-code reference; the entries it describes are the targets of the unified-app refactor, not the long-term shape.

| Path | Role |
|---|---|
| `index.html` | Elsewhere shell — post-login home, sign-in flow, badge menu, contacts/groups/household management, app launcher tiles |
| `tv2.html` | TV-side launcher: at-rest QR screen, post-handoff apps grid, navigates to active app on `launch_app` broadcast |
| `claim.html` | TV claim flow target — phone scans TV QR, lands here for confirmation |
| `nhhu-home.html` | Phase 1 placeholder Elsewhere home for NHHU users returning from audience deep links |
| `karaoke/stage.html` | Karaoke TV display — venue panorama, YouTube karaoke, lyrics, composited singer track |
| `karaoke/singer.html` | Karaoke phone — song picker, FX, mic, DeepAR face filters |
| `karaoke/audience.html` | Karaoke audience — low-latency Agora subscriber + video chat tile |
| `games/tv.html` | Games TV display |
| `games/player.html` | Games phone (also bundled in iOS app shell) |

### Shared assets

| Path | Purpose |
|---|---|
| `elsewhere-theme.css` | Single source of truth for colors / fonts / spacing / radii / z-index |
| `venues.json` | Venue metadata (id, name, icon, skybox, category, default coords) |
| `venues/*.jpg` | Equirectangular panorama backgrounds |
| `sounds/*.mp3` | Ambient audio loops per venue |
| `karaoke/effects/*.deepar` | DeepAR face filter bundles |
| `shell/auth.js` | Supabase client init, sign-in API, deep-link handler (Capacitor) |
| `shell/realtime.js` | Realtime publishers + listener wirer for the 8 `tv_device:<device_key>` events; full RPC-to-event matrix in the file header. |
| `shell/venue-settings.js` | Venue-defaults RPC helpers (admin-gated) |
| `shell/preferences.js` | User preferences storage (per-user-per-TV) |
| (inline) | Game state machines for Last Card / Trivia / Euchre are implemented inline in `games/player.html` (~3300 lines); no standalone modules. The earlier `games/engine/` directory was removed in Session 5 Part 3a.1 — see CLAUDE.md § "Games" for the inline-state-machine pattern. |

### Versioning

Every entry point renders a `v2.NN` badge (`claim.html` is the one exception — no badge yet). Convention: every commit bumps the version stamp on touched files only; commit subjects use `[v2.NN]` prefix when applicable. **Per-file badges drift independently** — they're a per-surface counter, not a project-wide version. The highest stamp at any point in time reflects the most-recently-touched surface, not a release.

To find current stamps: `grep -nE "v2\.[0-9]+" tv2.html index.html nhhu-home.html karaoke/*.html games/*.html | grep -i version`.

Highest current stamp (2026-05-20): `games/player.html` at v2.137. Lowest: `tv2.html` at v2.99.

---

## iOS shell

- **Project location:** `/Users/michaelstepanovich/Projects/elsewhere-app`
- **Tech stack:** Capacitor 8.3.1 wrapping the GitHub Pages web app (web bundle in `www/` mirrors the deployed site)
- **App ID:** `my.elsewhere`
- **App name:** `Elsewhere`
- **Capacitor config:** `capacitor.config.json` — minimal (`appId`, `appName`, `webDir: "www"`); no plugin sections
- **Supported destinations:** iPhone, iPad, Mac (Designed for iPad), Apple Vision. Destination inclusion is set in Xcode target settings, not `capacitor.config.json` — verifiable only from the Xcode project, not from the Capacitor config file.
- **Status:** Installed on Mike's iPhone today
- **Distribution:** TestFlight (active) + direct device install via Xcode signing during development. No App Store submission yet.

### Installed Capacitor plugins

From `~/Projects/elsewhere-app/package.json`:
- `@capacitor/app` ^8.1.0 — appUrlOpen events, appStateChange listener
- `@capacitor/browser` ^8.0.3
- `@capacitor/cli` ^8.3.1
- `@capacitor/core` ^8.3.1
- `@capacitor/ios` ^8.3.1
- `@supabase/supabase-js` ^2.103.3 (passed through to web bundle)

### Deep linking

- **Scheme:** `elsewhere://`
- **Configured in:** `~/Projects/elsewhere-app/ios/App/App/Info.plist` — `CFBundleURLSchemes` array
- **Handlers (in `shell/auth.js`):**
  - `elsewhere://auth/callback?code=…` — Supabase PKCE auth completion
  - `elsewhere://auth/callback#access_token=…&refresh_token=…` — Supabase implicit-flow auth
  - `elsewhere://games?room=ABC&...` — forwards to `games/player.html` preserving query string
  - `elsewhere://tv-claim?device_key=<UUID>` — TV claim flow
  - `elsewhere://tv-signin?device_key=<UUID>` — returning TV sign-in flow

### Bundled web payload

`~/Projects/elsewhere-app/www/` contains: `claim.html`, `docs/`, `elsewhere-theme.css`, `games/`, `index.html`, `karaoke/`, `shell/`, `tv2.html`, `venues.json`, `wellness/`. All major HTML entry points are bundled — including singer.html and stage.html — so iOS users access the full Elsewhere app through Capacitor, not Safari.

### Push notifications

**Status: Shipped (sandbox APNs).** Token registration, server-side trigger, and Edge Function are all live. Currently using the sandbox APNs environment (`aps-environment: development`); production environment switch is deferred until store distribution.

| Component | State |
|---|---|
| `@capacitor/push-notifications` plugin | Installed at `^8.0.3` in `~/Projects/elsewhere-app/package.json` |
| `aps-environment` entitlement | Present in `~/Projects/elsewhere-app/ios/App/App/App.entitlements` (value: `development`) |
| `UIBackgroundModes` with `remote-notification` | Present in `Info.plist` |
| `App.entitlements` file | Exists at `ios/App/App/App.entitlements` |
| `AppDelegate.swift` push handlers | Wired — `didRegisterForRemoteNotificationsWithDeviceToken` + `…DidFailToRegisterForRemoteNotifications` post to `NotificationCenter.default` for Capacitor to pick up |
| `push_subscriptions` DB table | `db/014_push_subscriptions.sql` — applied |
| Promotion push trigger | `db/015_promotion_push_trigger.sql` — Postgres trigger fires on `queued → active` promotion, posts to `send-push-notification` Edge Function with shared-secret auth |
| `send-push-notification` Edge Function | Deployed (see § Server-side functions). **Must redeploy with `--no-verify-jwt`** per CLAUDE.md doctrine |
| Apple Developer APNs Auth Key (.p8) | Generated and uploaded to Supabase secrets per `docs/SESSION-5-PART-2E0-LOG.md` |

Token registration flow: on app launch, `@capacitor/push-notifications` requests permission, registers with APNs, receives token, and writes to `push_subscriptions` (one row per device per user). Trigger reads from that table when firing.

See `docs/SESSION-5-PART-2E0-LOG.md` (token registration, sandbox cert) and `docs/SESSION-5-PART-2E2-LOG.md` (trigger architecture, `--no-verify-jwt` requirement, diagnostic via `pg_net._http_response`) for full context.

Production-environment switch (`aps-environment: production`) is deferred until App Store / TestFlight distribution work — see § Known infrastructure-related deferred items.

---

## Android shell

**None — Android users currently use the web app via mobile browser.** No `android/` directory in `~/Projects/elsewhere-app`, no Android-related Capacitor configuration. Android push notifications would require building an Android shell first.

---

## Database

- **Provider:** Supabase
- **Project URL:** `https://gbrnuxyzrlzbybvcvyzm.supabase.co` (referenced in `shell/auth.js:21` and every `db/*.sql` migration header)
- **Project ref:** `gbrnuxyzrlzbybvcvyzm`
- **Project name:** Set in the Supabase dashboard; not captured in source. The project ref (above) is the canonical identifier in code and migration headers.
- **Anon (publishable) key:** `sb_publishable_QQTDPpfpUI0NJlGawfYljw_O3d6Z9RK` (in-source at `shell/auth.js:22`, designed to be public)

### Migrations

Located in `db/` directory at repo root. Source of truth for applied state is `db/MIGRATIONS_APPLIED.md` — when in doubt, consult that file rather than this table; it's updated in the same commit that applies the migration (CLAUDE.md doctrine).

| Migration | Purpose | Status |
|---|---|---|
| `db/001_user_management_schema.sql` | `profiles` + `contacts` tables | Applied |
| `db/002_contacts_avatars.sql` | `avatar_url` on `contacts`; backing Supabase Storage bucket `contact-avatars` | Applied |
| `db/003_admin_and_venue_settings.sql` | `profiles.is_admin` + `venue_defaults` table (per-venue yaw/pitch) | Applied |
| `db/004_rename_is_admin_to_is_platform_admin.sql` | Rename `profiles.is_admin` → `profiles.is_platform_admin` | Applied |
| `db/005_front_back_venue_tuning.sql` | Split `venue_defaults` into independent front (audience view) and back (panorama view) yaw+pitch pairs | Applied |
| `db/006_household_and_tv_devices.sql` | `households`, `tv_devices`, `household_members`, `pending_household_invites` (Session 4.10) | Applied |
| `db/007_anon_tv_is_registered.sql` | Anon-callable RPC for TV registration state (tv2.html bootstrap) | Applied |
| `db/008_sessions_and_participants.sql` | Universal `sessions` + `session_participants` schema + helper auth functions | Applied |
| `db/009_session_lifecycle_rpcs.sql` | `rpc_session_start`, `rpc_session_join`, `rpc_session_leave`, `rpc_session_end` | Applied |
| `db/010_manager_mechanics_rpcs.sql` | `rpc_session_reclaim_manager`, `rpc_session_admin_reclaim` + auto-promote-on-manager-leave in `rpc_session_leave` | Applied |
| `db/011_role_and_queue_mutation_rpcs.sql` | `rpc_session_update_participant`, `rpc_session_update_queue_position`, `rpc_session_promote_self_from_queue` | Applied |
| `db/012_user_preferences.sql` | `user_preferences` table + `rpc_get_user_preference` / `rpc_set_user_preference` (per-user-per-TV K/V) | Applied |
| `db/013_karaoke_session_helpers.sql` | `rpc_karaoke_song_ended`, `rpc_session_get_participants` | Applied |
| `db/014_push_subscriptions.sql` | `push_subscriptions` table (one row per device_token × `apns_environment`) | Applied |
| `db/015_promotion_push_trigger.sql` | Postgres trigger fires `send-push-notification` Edge Function on `queued → active` promotion | Applied |
| `db/016_remove_participant.sql` | `rpc_session_remove_participant` (manager soft-removes another active participant; sets `left_at`) | Applied |
| `db/017_set_my_participation_role.sql` | `rpc_set_my_participation_role` — self-only `active ↔ audience` flip | Applied |
| `db/018_session_start_active_default.sql` | Session-start branched-default fix — manager lands as `active`, not `audience` | Applied |
| `db/019_trivia_premium_usage.sql` | `trivia_premium_usage` per-user-per-UTC-day counter (20/day rate limit for `generate-trivia` Edge Function) | Applied |
| `db/020_admission_model_v2.sql` | Admission Model v2 (W1): add `wanting_since` column to `session_participants` + relax `sessions.admission_mode` constraint | Applied |
| `db/021_session_set_admission_mode.sql` | Admission Model v2 (W2): `rpc_session_set_admission_mode` — manager stamps mode + capacity at game-start | Applied |
| `db/022_session_update_participant_wanting_since.sql` | Admission Model v2 (W4, part 1): `rpc_session_update_participant` populates `wanting_since` | Applied |
| `db/023_session_get_participants_wanting_since.sql` | Admission Model v2 (W4, part 2): `rpc_session_get_participants` returns `wanting_since` | Applied |
| `db/024_session_heartbeat.sql` | Admission Model v2 (W9): `session_participants.last_seen_at` + heartbeat RPC for implicit-leave detection | Applied |

### RLS

Enabled on all session-related tables (`sessions`, `session_participants`, `user_preferences`, `households`, `household_members`, `tv_devices`, `contacts`, `profiles`, `pending_household_invites`, `venue_defaults`, `karaoke_venue_settings`). Policies are SELECT-only for non-owners; mutations flow through SECURITY DEFINER RPCs.

### Realtime channels

- **Topic namespace:** `tv_device:<device_key>` (single topic per TV, multiplexed events)
- **Events published** (per `shell/realtime.js` header lines 32-50):
  - `session_handoff` (4.10) — phone tokens to TV
  - `launch_app` (4.10.2) — phone signals TV to navigate
  - `exit_app` (4.10.3) — phone Back-to-Elsewhere signal
  - `session_started` (Session 5 2a)
  - `manager_changed` (Session 5 2a) — `reason` ∈ {`auto_promote`, `reclaim`, `admin`}
  - `participant_role_changed` (Session 5 2a)
  - `queue_updated` (Session 5 2a) — fires only for pure queue-metadata changes (reorder, pre_selection); role transitions that affect queue composition fire `participant_role_changed` instead
  - `session_ended` (Session 5 2a) — `reason` ∈ {`user_ended`, `manager_left`}

Consumers interested in queue state should subscribe to BOTH `queue_updated` and `participant_role_changed`. RPC-to-event matrix is in the `shell/realtime.js` header — single source of truth.

---

## Auth

- **Provider:** Supabase Auth
- **Mechanisms:** Magic link only (`signInWithOtp` with `emailRedirectTo: 'elsewhere://auth/callback'`). Confirmed at `shell/auth.js:78-92`. No OAuth, no password auth.
  - `signInWithEmail(email)` — sign in existing user via OTP
  - `signUpWithEmail(email, fullName)` — create new user via OTP with `shouldCreateUser: true`
- **Session persistence:** Supabase persists session in localStorage (configured at `shell/auth.js:26-32` — `persistSession: true`, `autoRefreshToken: true`, `detectSessionInUrl: false`)
- **Deep link callback:** `elsewhere://auth/callback` — handled in `shell/auth.js:133-162` (Capacitor branch). Calls `sb.auth.exchangeCodeForSession(code)` for PKCE flow, OR `sb.auth.setSession({access_token, refresh_token})` for implicit flow.
- **Cross-page handoff (TV ← phone):** `publishSessionHandoff(device_key)` in `shell/realtime.js:86-123` — phone sends current session tokens via Supabase realtime; tv2.html receives and calls `setSession`.

---

## Server-side functions

### Supabase Edge Functions (`supabase/functions/`)

| Function | Purpose | Triggered by | Deploy flag |
|---|---|---|---|
| `send-push-notification` | Sends APNs push via Apple's HTTP/2 endpoint. Reads token + payload from request, fans out to all of the user's `push_subscriptions` rows. | Postgres trigger `db/015_promotion_push_trigger.sql` (fires on `queued → active` promotion). | **`--no-verify-jwt` REQUIRED** — trigger sends a shared secret, not a JWT. See CLAUDE.md doctrine. |
| `generate-trivia` | Generates trivia questions via Anthropic API. Server holds `ANTHROPIC_API_KEY` (Supabase secret) and adds `x-api-key` header. | `games/player.html` `triviaGenerate()` (premium path), via `sb.functions.invoke('generate-trivia', ...)`. | Default (JWT-verified). |

Both functions are Deno-based (`deno.json` per function). `supabase/config.toml` at repo root holds project-level config.

### Postgres RPCs

The bulk of server logic lives in PostgreSQL functions, mostly SECURITY DEFINER RPCs covering session lifecycle (`db/009`), manager mechanics (`db/010`), role/queue mutations (`db/011`), preferences (`db/012`), karaoke helpers (`db/013`), participant removal (`db/016`), self-role flip (`db/017`), admission model v2 (`db/020`–`db/023`), and heartbeat (`db/024`).

### Cron jobs

**None.** No `pg_cron` extension calls, no scheduled functions in any migration. The participant-cleanup deferred entry (see § Known infrastructure-related deferred items) is the canonical place a cron would land if/when added.

---

## Third-party integrations

### Agora (real-time audio + video + data channel)

- **Used in:** `karaoke/stage.html`, `karaoke/singer.html`, `karaoke/audience.html`, `tv2.html` (stream watcher), `games/tv.html`, `games/player.html`
- **App ID (in-source by design):** `b2c6543a9ed946829e6526cb68c7efc9` — defined as `AGORA_APP_ID` constant in every consumer
- **Channels:**
  - `elsewhere_<ROOM>` — karaoke (singer + audience + stage)
  - `elsewhere_g<ROOM>` — games
- **Data channel:** JSON messages over `client.sendStreamMessage` with 1KB chunking via `_chunk` envelope. See `CLAUDE.md` § "Agora data channel" for invariants.
- **Used for:** stage ↔ singer comms, lyric sync, song-end signaling, mic publish, audience video tile, costume FX changes

### YouTube IFrame API + YouTube Data API

- **Used in:** `karaoke/stage.html` (player), `karaoke/singer.html` (search)
- **API key (in-source, domain-restricted):** `AIzaSyD9hs9juo0WyUghjUgmv6Abn0ixWw1iqvM` — defined at `karaoke/singer.html:565` as `YT_API_KEY`
- **IFrame API:** loaded dynamically in `karaoke/stage.html:loadYouTubeAPI()` from `https://www.youtube.com/iframe_api`
- **Used for:** lyric video playback (stage), song search (singer)

### DeepAR (face filters + background segmentation)

- **Used in:** `karaoke/stage.html`
- **SDK:** loaded from `https://cdn.jsdelivr.net/npm/deepar/` (CDN, no version pinned in source; URL fetched at runtime)
- **Effects:** `karaoke/effects/*.deepar` files in repo, loaded from absolute GitHub Pages URL `https://mstepanovich-web.github.io/elsewhere/karaoke/effects/`
- **Used for:** AR face filters; background segmentation when DeepAR effects are active (otherwise MediaPipe fallback)

### MediaPipe (pose + face mesh + selfie segmentation)

- **Used in:** `karaoke/stage.html`
- **Bundles:** loaded from `https://cdn.jsdelivr.net/npm/@mediapipe/...` for `selfie_segmentation`, `face_mesh`, `pose`
- **Used for:** background segmentation (when DeepAR effects not active), face mesh tracking, hand-pose detection

### LRCLIB (synced lyrics)

- **Used in:** `karaoke/singer.html` (lyric fetch); stage receives lyrics via Agora
- **Endpoint:** `https://lrclib.net/api` — defined at `karaoke/singer.html:567` as `LRCLIB_URL`
- **No auth required**

### Trivia question sources

Trivia generation runs on two tiers:

- **Baseline:** OpenTDB (`https://opentdb.com/api.php`). No auth, public free API. Called from `games/player.html` at the baseline trivia-generate path (~line 4069). Returns batched questions; response-code handling at lines 4073–.
- **Premium:** Anthropic API via the `generate-trivia` Supabase Edge Function. Browser calls `sb.functions.invoke('generate-trivia', ...)` (`games/player.html:4159`); the Edge Function holds `ANTHROPIC_API_KEY` as a Supabase secret and calls `https://api.anthropic.com/v1/messages` with `x-api-key` server-side (`supabase/functions/generate-trivia/index.ts:220`). Premium calls are rate-limited per-user-per-UTC-day via `trivia_premium_usage` (`db/019`).

The original browser-direct Anthropic call (v2.108 and earlier) is preserved as a `// PHASE 2 REFERENCE` comment block in `games/player.html` lines 4019–4053 — not live code, kept for future reference if the Edge Function path is ever revisited.

**Status:** Shipped. Trivia is playable end-to-end as of Session 5 Part 3b.

### Spotify

**Not currently integrated.** No Spotify references found in source. Mentioned in some prior planning docs as a future possibility (Name That Tune game) but no code exists.

---

## Deploy / CI

### Web (GitHub Pages)

- **Trigger:** push to `main` branch
- **Mechanism:** Legacy "deploy from branch" Pages config (no GitHub Actions workflow — `.github/` directory does not exist in repo)
- **Latency:** Typically 30s-2min from push to live
- **Custom domain:** None configured; uses default `mstepanovich-web.github.io/elsewhere/`

### iOS app

- **Build tool:** Xcode (manual)
- **Sync workflow:** `npx cap sync ios` after `www/` updates → opens Xcode for build/run
- **Distribution:** TestFlight (active) + direct device install via Xcode signing during development. No App Store submission yet.
- **Auto-deploy:** None — every iOS update is a manual Xcode operation

---

## Known infrastructure-related deferred items

Snapshot as of 2026-05-20. See `docs/DEFERRED.md` for full per-item entries (Context / Options / When to pick up / Related).

| Entry | Area | Priority | Status |
|---|---|---|---|
| Configurable platform timeouts | `platform_settings` DB table + admin UI for runtime tuning | Low | Active |
| Platform admin role + UI | `platform_admins` table + dedicated admin page | Low | Active |
| Participant cleanup mechanism | Edge function or cron to sweep stale `session_participants.left_at` | Medium | Active |
| Phone proximity persistence — 10-minute inactivity expiration | localStorage timestamp + expiration check | Low | Active |
| Audience-to-NHHU conversion path (full funnel) | Sign-up flow, app downloads, game launchers | Medium | Active — partially re-framed by `docs/UNIFIED-APP-PLAN.md` (audience-as-mode); see `docs/HOUSEHOLD-DEVICE-PRESENCE-MODEL.md` |
| Audience.html migration into unified app | Replace separate `audience.html` with parameterized NHHU view in unified app | Medium | Active — see `docs/UNIFIED-APP-PLAN.md` |
| Manager Override mechanism design | Architectural decision (Karaoke Control Model § 2 Options A/B/C) | Medium | Active — partially re-framed by `docs/ROOM-AUTHORITY-MODEL.md` (manager authority = room control + ownership). The original "blocks 2e implementation" framing is past tense; 2e shipped. |
| APNs production environment switch | `aps-environment: production` + production cert in Supabase secrets + App Store / TestFlight distribution | Low | New — surfaced by Push being shipped sandbox-only |
| Push notification infrastructure | Capacitor plugin + iOS entitlements + DB push-tokens table + Edge Function | — | **Resolved in Session 5 Part 2e0/2e2.** Sandbox APNs only; production switch is the new entry above. |

For each active item, see the corresponding `### Deferred:` block in `docs/DEFERRED.md` for full context.

---

## Footer

This file is the canonical reference for Elsewhere's infrastructure surface. Update protocol: add/remove/rename any system above → update this file in the same commit.

When in doubt about whether something belongs here vs. CLAUDE.md vs. ROADMAP.md vs. session plan docs:
- **INFRA.md** — what systems exist (steady-state architecture)
- **CLAUDE.md** — coding conventions + per-system invariants
- **ROADMAP.md** — what's being worked on now / what's next
- **DEFERRED.md** — items punted until later
- **Session plans** — specific session-scope work

If this file diverges from reality, fix the file. Stale infra docs cause wasted effort and incorrect recommendations (the iOS shell context near-miss during 2e audit planning is the canonical example).
