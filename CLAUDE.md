# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Session-start orientation

At the start of any session, read these docs in order for current context:

- **`docs/ROADMAP.md`** — current session pipeline, active work, queued sessions. Points at the active `SESSION-X.X.X-PLAN.md` if one exists.
- **`docs/DEFERRED.md`** — backlog items, append-only. Check for items relevant to the session's scope before planning so they can be promoted or re-scoped.
- **`docs/SESSION-X.X.X-PLAN.md`** — individual session plans, created at the start of each planning session. The active one is named in `ROADMAP.md` under "Active session".

Both `ROADMAP.md` and `DEFERRED.md` are updated at the end of each session. To check freshness, compare `git log -1 --format=%H docs/ROADMAP.md` against `git log -1 --format=%H` on main. If ROADMAP.md wasn't updated in the most recent feature commit or within 2-3 commits of it, flag to the user that the roadmap may be out of date before acting on it.

## What this repo is

Elsewhere is a multi-device browser party app (Karaoke, Games) that pairs a TV/big-screen "host" page with phone "client" pages over Agora RTC. There is no build step — every entry point is a static HTML file served from GitHub Pages at `https://mstepanovich-web.github.io/elsewhere`.

An earlier Fashion product direction was archived on 2026-04-17 at v2.90 — see `ARCHIVE-NOTES.md` for the pipeline / restore instructions. It lives on the `archive/fashion` branch.

The repo is the deploy artifact: edits to HTML/CSS/JS files go straight to production after `git push` (GitHub Pages serves `main`).

## Repo layout

```
tv2.html                  # launcher — renders room-code QRs, watches Agora, forwards to the right TV page
elsewhere-theme.css       # single source of truth for colors/fonts/spacing/radii/z-index
karaoke/
  stage.html              # TV (venue background, YouTube karaoke, lyrics, composited singer track)
  singer.html             # phone (song picker, FX, mic, DeepAR face filters)
  audience.html           # optional third role (low-latency audience + video-chat tile)
  effects/*.deepar        # DeepAR effect bundles (load via absolute GitHub Pages URL)
games/
  tv.html                 # lobby + board
  player.html             # phone (controls, manager bar, per-player tiles; also the iOS-app payload)
  engine/                 # ESM modules — last-card.js, trivia.js, sync.js
venues/  *.jpg            # panorama backgrounds (shared across products — keep at root)
sounds/  *.mp3            # matching ambient audio for each venue (shared)
db/       *.sql           # Supabase schema migrations (Path B)
```

A Phase 1 Path B restructure (commit `[v2.93]`) moved the karaoke pages into `karaoke/` and deleted the orphaned root `index.html` + stale `tv.html`. `venues/` and `sounds/` stayed at the root on purpose so future products (e.g. wellness) can share them.

## Commands

There is no test suite, linter, or bundler. To work locally:

```bash
# Static site — serve the repo root over HTTPS (Agora SDK refuses file:// and http:// on phones)
npx http-server . -S -C cert.pem -K key.pem -p 8443
# or just push to main and load https://mstepanovich-web.github.io/elsewhere/<page>.html on the device
```

When testing on a phone you must hit the deployed HTTPS URL (or a tunneled HTTPS dev server) — the Agora `AgoraRTC_N` SDK throws `SDK not loaded` on insecure origins, and singer/audience both bail out with that exact error string.

## Architecture

### Device pairing model
Each "session" is a 4–6 character room code, generated on the TV. Phones discover the TV by scanning a QR that points to a phone URL with `?code=ROOM`. Pairing is detected via Agora `user-joined` on a per-mode channel (no signaling server).

`tv2.html` is the only launcher. It generates the room code, renders two QRs (karaoke / games), then runs two `AgoraRTC.createClient` watchers in parallel — one per mode — and `window.location.href`s the TV to the right destination as soon as a phone joins the corresponding channel:

| Mode    | Channel suffix       | TV page                  | Phone page                |
|---------|----------------------|--------------------------|---------------------------|
| Karaoke | `elsewhere_<ROOM>`   | `karaoke/stage.html`     | `karaoke/singer.html`     |
| Games   | `elsewhere_g<ROOM>`  | `games/tv.html`          | `games/player.html`       |

A new top-level `index.html` / Elsewhere shell is planned in Path B Session 2; there is currently no root-level entry page, so device pairing always starts from `tv2.html`.

### Agora data channel — the load-bearing detail
Both modes use the same Agora App ID (`b2c6543a9ed946829e6526cb68c7efc9`, hardcoded as `AGORA_APP_ID` in every file that needs it) and the same data-stream pattern: JSON messages over `client.sendStreamMessage`. Two things will bite you:

1. **1KB chunking.** Agora silently drops stream messages over ~1KB. Every sender chunks payloads larger than that with an `_chunk: true / id / i / n / d` envelope and every receiver reassembles them in a per-uid buffer (search for `_chunkBuf` / `audChunkBuf` / `_tvChunkBuf`). When you add a new message type, if the JSON could ever exceed ~900 bytes (e.g. full game state, hand snapshots) it MUST go through the chunked sender — see commit `f7ae144` for the regression that motivated this.
2. **`createDataStream` is not always supported.** Some Agora SDK versions (notably the live-mode one used by `karaoke/singer.html` / `karaoke/stage.html`) throw on `createDataStream` and the code falls back to `client.sendStreamMessage(bytes, true)` with a null `streamId`. Both call shapes exist in the codebase — don't "clean up" one into the other.

`games/engine/sync.js` is the only place this is wrapped in a class (`GameSync`). The karaoke code does it inline because it predates the wrapper.

### Karaoke (stage / singer / audience)
All karaoke HTML lives under `karaoke/`. The DeepAR effect bundles live at `karaoke/effects/`.
- `karaoke/stage.html` (TV, ~4.8k lines) is the central renderer: it owns the venue background, pulls YouTube karaoke videos via the YouTube Data API (`YT_API_KEY` is in-source), fetches synced lyrics from `lrclib.net`, and publishes a composited camera track to Agora as the singer's avatar.
- `karaoke/singer.html` is the phone — picks songs, controls FX (reverb / echo / boost / DeepAR face filters), publishes mic audio.
- `karaoke/audience.html` is a third role that subscribes to the stage stream as low-latency Agora audience and can also publish a video-chat tile back.
- DeepAR effects load from `https://cdn.jsdelivr.net/npm/deepar/` (built-ins) and from `https://mstepanovich-web.github.io/elsewhere/karaoke/effects/` (the local `karaoke/effects/*.deepar` files in this repo). New effects = drop the `.deepar` file in `karaoke/effects/` and add an entry to the `DEEPAR_EFFECTS` array in `karaoke/singer.html` (and in `karaoke/stage.html`'s matching list).
- Venue images live in `venues/` and matching ambient audio in `sounds/` — both stay at repo root so they can be shared across products. Filenames follow the `{id}.jpg` / `{id}.mp3` convention, with `enchantedforest` → `forest.mp3` as the one exception (handled via `soundId` in the manifest). Venue metadata is declared once in `venues.json` and fetched at boot by both `karaoke/stage.html` and `karaoke/singer.html`. Ambient audio + animation hooks remain wired up in `karaoke/stage.html`'s `AMBIENT_PROFILES` (see commit `94f3873` — a stray entry outside that object will silently break venue selection).

### Adding a venue

Venue metadata lives in `/venues.json` at the repo root — single source of truth for karaoke stage + singer, and for any future venue-consuming product (wellness, Room Mode, etc.). To add a new venue:

1. Drop the equirectangular panorama image in `venues/` — name it `{id}.jpg` (e.g. `venues/tavern.jpg`). Filename stem becomes the venue id.
2. Drop the ambient audio loop in `sounds/` — same stem by default: `sounds/tavern.mp3`. If you're reusing a sound from another venue, set `soundId` in the JSON entry to point at the existing file stem (e.g. `"soundId": "forest"` for `sounds/forest.mp3`).
3. Add an entry to `venues.json`'s `venues[]` array:
   ```json
   { "id": "tavern", "name": "Medieval Tavern", "icon": "🍺", "skyboxId": "tavern", "category": "bars", "startYaw": 0, "staticYaw": 0, "staticPitch": 0 }
   ```
   - `id`: must match the filename stem in `venues/`
   - `skyboxId`: usually equals `id`; set explicitly so a future rename doesn't break the venue
   - `category`: one of the category ids declared in `venues.json`'s `categories[]` — any venue with an unknown category is orphaned from the picker (silent, no error)
   - `startYaw` / `staticYaw` / `staticPitch`: start at `0, 0, 0` — the admin-only "Set View Coordinates" dialog in karaoke/stage.html tunes them from there and persists to Supabase (`venue_defaults` table). Session-6 scope; JSON values act as Phase-1 baseline and survive DB loss
4. For any Three.js ambient animation (spotlights, particles), also add an entry to `AMBIENT_PROFILES` in `karaoke/stage.html`. Audio-only venues work without an `AMBIENT_PROFILES` entry (just file naming).
5. No code edits beyond the JSON. Singer + stage pickers auto-refresh on next page load; new venue appears in its category.

Phantom/aspirational venues don't stay in the JSON — if there's no `.jpg` in `venues/`, the texture load fails and the picker shows a broken entry. Clean up unused entries promptly.

### Games (last-card / trivia / euchre)
- `games/tv.html` is the lobby + board renderer. `games/player.html` is the phone (with controls, the manager bar, and per-player camera tiles).
- `games/engine/last-card.js` and `games/engine/trivia.js` are pure-function game engines: `createGame(...)`, `applyMove(state, action) → newState`. State is plain JSON, designed to be sent verbatim over Agora. Euchre is implemented inline in `games/player.html` and `games/tv.html` (no engine module yet, despite being listed in `GAME_INFO`).
- `games/engine/sync.js` is the wrapper class new game code should use. The existing TV/player files predate it and use Agora directly.
- Trivia hits the Anthropic API directly from the browser (`generateQuestions` in `trivia.js`). There is no auth header in that fetch — if you're touching this, the manager's API key has to be supplied somewhere or the call will 401. Don't add a hard-coded server key.
- The "manager" role (one player per room) is the only one allowed to start/end games and select the next game; it's chosen by the `?mgr=1` URL param or a checkbox on the join screen.

### Theme system
`elsewhere-theme.css` is the single source of truth for colors, fonts, spacing, radii, z-index. Every HTML file links it (mostly via the absolute GitHub Pages URL `https://mstepanovich-web.github.io/elsewhere/elsewhere-theme.css` so the deployed pages get the live theme). New UI should reach for `var(--color-*)`, `var(--font-*)`, `var(--text-*)`, `var(--tracking-*)`, `var(--radius-*)` etc. instead of hardcoding values. Per-product overrides ride on body classes (e.g. `theme-worlds`, `theme-movies`). An unused `theme-fashion` class is still defined in the stylesheet — left in place because `archive/fashion` references it; no live page uses it.

## Doctrine

- **`participation_role` enum overload is intentional.** The schema (`db/008`) defines `participation_role` as `'active'` / `'queued'` / `'audience'`. The `'audience'` value is overloaded by surface: on `karaoke/singer.html` it means "Available Singer (not queued)"; on `karaoke/audience.html` it means "watching only." The schema doesn't distinguish because eligibility (HHU + at-home + has-TV) is enforced **upstream** by the Elsewhere shell's gate on the Karaoke tile — never stored in the DB. By the time a user has a `participation_role` row, eligibility is implicit from the path that got them there. See `docs/SESSION-5-PART-2E-MODEL-AUDIT.md` for the full audit and `docs/KARAOKE-CONTROL-MODEL.md:42-49` for the canonical four-role mapping. **Future reviewers who see the audience-overload should fix the surface render, not split the enum.**

- **Roadmap and post-Session-5 plans are in the docs, not in Claude's head.** The unified-app migration (audience.html absorbed into HHU app), audience-to-NHHU conversion path, cross-app venue rendering module, and games venue integration are all documented in `docs/DEFERRED.md` and `docs/KARAOKE-CONTROL-MODEL.md` § 5.4-5.5. Future Claudes asked "what's after 2e" or "what's the post-Session-5 plan" should READ THESE DOCS FIRST and surface what's documented, not estimate from first principles. The work is already broken down — find it.

## Conventions worth knowing

- **Versioning.** Every page renders a `v2.NN` badge (search for `v2.88` to find them all). The convention from git history is: every commit bumps the version and every page that has the badge gets updated together — feature commits use `[vX.YY]` in the subject, e.g. `feat: 'Join as manager' checkbox on join screen [v2.88]`. When you ship a change, bump every `v2.NN` string in files you touched and any peer files that share the badge.
- **No build step.** Don't introduce one. Don't add `<script type="module">` for the karaoke/audience HTML — the inline scripts assume globals. The games engines under `games/engine/` are the only ESM in the repo and are imported by the games TV/player pages.
- **The Agora App ID is in source on purpose.** Don't try to "fix" it by moving to env vars — there is no server, every client needs it. Same for `YT_API_KEY` in `karaoke/singer.html` (it's domain-restricted in the Google console).
- **Debug log panels.** Most pages have a "LOG" button bottom-left/right that pops a transcript — it's the primary way users report bugs. When adding new flows, call into the existing `log()` / `tvLog()` helpers instead of `console.log` only.
