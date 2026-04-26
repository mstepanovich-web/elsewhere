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
| `shell/realtime.js` | Realtime publishers (`publishLaunchApp`, `publishExitApp`, `publishSessionStarted`, etc.) + `wireExitAppListener` |
| `shell/venue-settings.js` | Venue-defaults RPC helpers (admin-gated) |
| `shell/preferences.js` | User preferences storage (per-user-per-TV) |
| `games/engine/last-card.js`, `trivia.js`, `sync.js` | Pure-function game engines (only ESM modules in repo) |

### Versioning

Every page renders a `v2.NN` badge. Convention: every commit bumps the version on touched files; commit subjects use `[v2.NN]` prefix for feature commits. Current version (post-2d.1 work): `v2.100`.

---

## iOS shell

- **Project location:** `/Users/michaelstepanovich/Projects/elsewhere-app`
- **Tech stack:** Capacitor 8.3.1 wrapping the GitHub Pages web app (web bundle in `www/` mirrors the deployed site)
- **App ID:** `my.elsewhere`
- **App name:** `Elsewhere`
- **Capacitor config:** `capacitor.config.json` — minimal (`appId`, `appName`, `webDir: "www"`); no plugin sections
- **Supported destinations:** iPhone, iPad, Mac (Designed for iPad), Apple Vision [TODO: verify Vision availability in current app config]
- **Status:** Installed on Mike's iPhone today
- **Distribution:** [TODO: verify — TestFlight? Direct install via Xcode? App Store?]

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

### Push notification support

**Status: NOT enabled.** Capacitor + APNs is feasible but no infrastructure currently exists.

| Component | Status |
|---|---|
| `@capacitor/push-notifications` plugin | Not installed |
| `aps-environment` entitlement in Info.plist | Not present |
| `UIBackgroundModes` array | Not present |
| `.entitlements` file | Does not exist |
| `AppDelegate.swift` push handlers | None — no `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`, no UNUserNotificationCenter setup |
| Apple Developer APNs Auth Key (.p8) | [TODO: verify — likely exists since app ships, but key file location and ownership unconfirmed] |

Push enablement would require new work: install plugin, enable Xcode capabilities, wire AppDelegate, create DB push-tokens table, build Supabase Edge Function that calls APNs. See `docs/SESSION-5-PART-2E-AUDIT.md` § Area 4 + Decision 4 for full feasibility analysis (~6-8 hour effort).

---

## Android shell

**None — Android users currently use the web app via mobile browser.** No `android/` directory in `~/Projects/elsewhere-app`, no Android-related Capacitor configuration. Android push notifications would require building an Android shell first.

---

## Database

- **Provider:** Supabase
- **Project URL:** `https://gbrnuxyzrlzbybvcvyzm.supabase.co` (referenced in `shell/auth.js:21` and every `db/*.sql` migration header)
- **Project ref:** `gbrnuxyzrlzbybvcvyzm`
- **Project name:** [TODO: verify — only the URL ref is captured in source]
- **Anon (publishable) key:** `sb_publishable_QQTDPpfpUI0NJlGawfYljw_O3d6Z9RK` (in-source at `shell/auth.js:22`, designed to be public)

### Migrations

Located in `db/` directory at repo root. Applied state as of HEAD `cc1f425`:

| Migration | Purpose | Status |
|---|---|---|
| `db/001_user_management_schema.sql` | `profiles`, `contacts` tables | Applied |
| `db/002_contacts_avatars.sql` | Avatar URL on `contacts` | Applied |
| `db/003_admin_and_venue_settings.sql` | `is_admin` + `venue_defaults` | Applied |
| `db/004_rename_is_admin_to_is_platform_admin.sql` | Column rename | Applied |
| `db/005_front_back_venue_tuning.sql` | Venue back-yaw/pitch | Applied |
| `db/006_household_and_tv_devices.sql` | `households`, `tv_devices`, `household_members`, `pending_household_invites` | Applied |
| `db/007_anon_tv_is_registered.sql` | Anon RPC for tv2.html bootstrap | Applied |
| `db/008_sessions_and_participants.sql` | `sessions`, `session_participants`, helper auth functions | Applied |
| `db/009_session_lifecycle_rpcs.sql` | `rpc_session_start`, `rpc_session_end`, `rpc_session_join`, `rpc_session_leave` | Applied |
| `db/010_manager_mechanics_rpcs.sql` | `rpc_session_reclaim_manager`, `rpc_session_admin_reclaim` | Applied |
| `db/011_role_and_queue_mutation_rpcs.sql` | `rpc_session_update_participant`, `rpc_session_update_queue_position`, `rpc_session_promote_self_from_queue` | Applied |
| `db/012_user_preferences.sql` | `user_preferences` + `rpc_get/set_user_preference` | Applied |
| `db/013_karaoke_session_helpers.sql` | `rpc_karaoke_song_ended`, `rpc_session_get_participants` | **Pending manual application** to Supabase as of HEAD `cc1f425` |

### RLS

Enabled on all session-related tables (`sessions`, `session_participants`, `user_preferences`, `households`, `household_members`, `tv_devices`, `contacts`, `profiles`, `pending_household_invites`, `venue_defaults`, `karaoke_venue_settings`). Policies are SELECT-only for non-owners; mutations flow through SECURITY DEFINER RPCs.

### Realtime channels

- **Topic namespace:** `tv_device:<device_key>` (single topic, multiplexed events)
- **Events published** (per `shell/realtime.js` header lines 29-47):
  - `session_handoff` (4.10) — phone tokens to TV
  - `launch_app` (4.10.2) — phone signals TV to navigate
  - `exit_app` (4.10.3) — phone Back-to-Elsewhere signal
  - `session_started` (Session 5 2a)
  - `manager_changed` (Session 5 2a)
  - `participant_role_changed` (Session 5 2a)
  - `queue_updated` (Session 5 2a)
  - `session_ended` (Session 5 2a)

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

- **Supabase Edge Functions:** **None.** No `supabase/` directory exists in the repo, no edge function references in any source file.
- **Cron jobs:** **None.** No `pg_cron` extension calls, no scheduled functions in any migration.

All server logic today lives in PostgreSQL functions (RPCs in `db/009`–`db/013`). Edge functions would be net-new infrastructure.

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

### Anthropic API (trivia question generation)

- **Used in:** `games/engine/trivia.js:52`
- **Endpoint:** `https://api.anthropic.com/v1/messages`
- **Auth:** ⚠️ No auth header in the fetch call — call would 401 without manual key supply. Per `CLAUDE.md`: "if you're touching this, the manager's API key has to be supplied somewhere or the call will 401. Don't add a hard-coded server key."
- **Status:** Trivia game has limited use until auth path is settled

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
- **Distribution:** [TODO: verify — likely TestFlight or direct device install via Xcode signing; App Store submission status unconfirmed]
- **Auto-deploy:** None — every iOS update is a manual Xcode operation

---

## Known infrastructure-related deferred items

Pulled from `docs/DEFERRED.md` (HEAD `cc1f425`). Items here are infrastructure scaffolding rather than feature work:

| Entry | Area | Priority |
|---|---|---|
| Configurable platform timeouts | `platform_settings` DB table + admin UI for runtime tuning | Low |
| Platform admin role + UI | `platform_admins` table + dedicated admin page | Low |
| Participant cleanup mechanism | Edge function or cron to sweep stale `session_participants.left_at` | Medium |
| Phone proximity persistence — 10-minute inactivity expiration | localStorage timestamp + expiration check | Low |
| Audience-to-NHHU conversion path (full funnel) | Sign-up flow, app downloads, game launchers | Medium |
| Audience.html migration into unified app | Replace separate audience.html with parameterized NHHU view in unified app | Medium |
| Manager Override mechanism design | Architectural decision (Karaoke Control Model § 2 Options A/B/C) | High (blocks 2e implementation) |
| Push notification infrastructure | Capacitor `@capacitor/push-notifications` + iOS entitlements + DB push-tokens table + Supabase Edge Function | Medium (decision in 2e audit Decision 4) |

For each item, see the corresponding `### Deferred:` block in `docs/DEFERRED.md` for full context.

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
