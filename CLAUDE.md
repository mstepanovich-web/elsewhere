# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Elsewhere is a multi-device browser party app (Karaoke, Fashion try-on, Games) that pairs a TV/big-screen "host" page with phone "client" pages over Agora RTC. There is no build step — every entry point is a static HTML file served from GitHub Pages at `https://mstepanovich-web.github.io/elsewhere`. The only Node code is the optional Fashion render server in `fashion/render-server/`.

The repo is the deploy artifact: edits to HTML/CSS/JS files go straight to production after `git push` (GitHub Pages serves `main`).

## Commands

There is no test suite, linter, or bundler. To work locally:

```bash
# Static site — serve the repo root over HTTPS (Agora SDK refuses file:// and http:// on phones)
npx http-server . -S -C cert.pem -K key.pem -p 8443
# or just push to main and load https://mstepanovich-web.github.io/elsewhere/<page>.html on the device

# Fashion render server (only when working on /api/fashion/*)
cd fashion/render-server
npm install
npm run dev   # node --watch server.js  — needs FASHN_API_KEY, RUNWAY_API_KEY, KLING_API_KEY, R2_* env vars
```

When testing on a phone you must hit the deployed HTTPS URL (or a tunneled HTTPS dev server) — the Agora `AgoraRTC_N` SDK throws `SDK not loaded` on insecure origins, and singer/audience/stylist all bail out with that exact error string.

## Architecture

### Device pairing model
Each "session" is a 4–6 character room code, generated on the TV. Phones discover the TV by scanning a QR that points to a phone URL with `?code=ROOM`. Pairing is detected via Agora `user-joined` on a per-mode channel (no signaling server).

`tv2.html` is the current launcher (`tv.html` is the older version, still linked from `index.html` flows). It generates the room code, renders three QRs (karaoke / fashion / games), then runs three `AgoraRTC.createClient` watchers in parallel — one per mode — and `window.location.href`s the TV to the right destination as soon as a phone joins the corresponding channel:

| Mode    | Channel suffix       | TV page                  | Phone page              |
|---------|----------------------|--------------------------|-------------------------|
| Karaoke | `elsewhere_<ROOM>`   | `stage.html`             | `singer.html`           |
| Games   | `elsewhere_g<ROOM>`  | `games/tv.html`          | `games/player.html`     |
| Fashion | `elsewhere_f<ROOM>`  | `fashion/display.html`   | `fashion/stylist.html`  |

`index.html` does its own simpler routing: width ≤ 768px → phone page, else TV page. It does not pair devices — it just opens one half of the experience.

### Agora data channel — the load-bearing detail
All three modes use the same Agora App ID (`b2c6543a9ed946829e6526cb68c7efc9`, hardcoded as `AGORA_APP_ID` in every file that needs it) and the same data-stream pattern: JSON messages over `client.sendStreamMessage`. Two things will bite you:

1. **1KB chunking.** Agora silently drops stream messages over ~1KB. Every sender chunks payloads larger than that with an `_chunk: true / id / i / n / d` envelope and every receiver reassembles them in a per-uid buffer (search for `_chunkBuf` / `audChunkBuf` / `_tvChunkBuf`). When you add a new message type, if the JSON could ever exceed ~900 bytes (e.g. full game state, hand snapshots) it MUST go through the chunked sender — see commit `f7ae144` for the regression that motivated this.
2. **`createDataStream` is not always supported.** Some Agora SDK versions (notably the live-mode one used by `singer.html` / `stage.html`) throw on `createDataStream` and the code falls back to `client.sendStreamMessage(bytes, true)` with a null `streamId`. Both call shapes exist in the codebase — don't "clean up" one into the other.

`games/engine/sync.js` is the only place this is wrapped in a class (`GameSync`). The karaoke and fashion code do it inline because they predate the wrapper.

### Karaoke (stage / singer / audience)
- `stage.html` (TV, ~4.8k lines) is the central renderer: it owns the venue background, pulls YouTube karaoke videos via the YouTube Data API (`YT_API_KEY` is in-source), fetches synced lyrics from `lrclib.net`, and publishes a composited camera track to Agora as the singer's avatar.
- `singer.html` is the phone — picks songs, controls FX (reverb / echo / boost / DeepAR face filters), publishes mic audio.
- `audience.html` is a third role that subscribes to the stage stream as low-latency Agora audience and can also publish a video-chat tile back.
- DeepAR effects load from `https://cdn.jsdelivr.net/npm/deepar/` (built-ins) and from `https://mstepanovich-web.github.io/elsewhere/effects/` (the local `effects/*.deepar` files in this repo). New effects = drop the `.deepar` file in `effects/` and add an entry to the `DEEPAR_EFFECTS` array in `singer.html`.
- Venue images live in `venues/` and matching ambient audio in `sounds/` — the filenames must match (`saloon.jpg` ↔ `saloon.mp3`). Both lists are wired up in `stage.html`'s `AMBIENT_PROFILES` (see commit `94f3873` — a stray entry outside that object will silently break venue selection).

### Games (last-card / trivia / euchre)
- `games/tv.html` is the lobby + board renderer. `games/player.html` is the phone (with controls, the manager bar, and per-player camera tiles).
- `games/engine/last-card.js` and `games/engine/trivia.js` are pure-function game engines: `createGame(...)`, `applyMove(state, action) → newState`. State is plain JSON, designed to be sent verbatim over Agora. Euchre is implemented inline in `games/player.html` and `games/tv.html` (no engine module yet, despite being listed in `GAME_INFO`).
- `games/engine/sync.js` is the wrapper class new game code should use. The existing TV/player files predate it and use Agora directly.
- Trivia hits the Anthropic API directly from the browser (`generateQuestions` in `trivia.js`). There is no auth header in that fetch — if you're touching this, the manager's API key has to be supplied somewhere or the call will 401. Don't add a hard-coded server key.
- The "manager" role (one player per room) is the only one allowed to start/end games and select the next game; it's chosen by the `?mgr=1` URL param or a checkbox on the join screen.

### Fashion
- `fashion/stylist.html` (phone) walks the user through mode → photo → garment(s) → render.
- `fashion/display.html` (TV) shows the result.
- `fashion/render-server/server.js` is a separate Express service the stylist POSTs to (`window.ELSEWHERE_RENDER_API` overrides the default `https://render.elsewhere.app/api/fashion/render`). It runs a multi-stage pipeline per `mode`: Fashn.ai virtual try-on → optional Runway Gen-4 Turbo image-to-video or Kling 2.1 Pro catwalk → upload to Cloudflare R2. Jobs live in an in-memory `Map` — the comment notes Redis/DB is needed for real production.
- `multi_angle` and `multi_angle_catwalk` modes have `// TODO: ffmpeg stitch …` — they currently return only the first clip rather than a stitched composite.

### Theme system
`elsewhere-theme.css` is the single source of truth for colors, fonts, spacing, radii, z-index. Every HTML file links it (mostly via the absolute GitHub Pages URL `https://mstepanovich-web.github.io/elsewhere/elsewhere-theme.css` so the deployed pages get the live theme). New UI should reach for `var(--color-*)`, `var(--font-*)`, `var(--text-*)`, `var(--tracking-*)`, `var(--radius-*)` etc. instead of hardcoding values. Per-product overrides ride on body classes: `theme-fashion`, `theme-worlds`, `theme-movies`.

## Conventions worth knowing

- **Versioning.** Every page renders a `v2.NN` badge (search for `v2.88` to find them all). The convention from git history is: every commit bumps the version and every page that has the badge gets updated together — feature commits use `[vX.YY]` in the subject, e.g. `feat: 'Join as manager' checkbox on join screen [v2.88]`. When you ship a change, bump every `v2.NN` string in files you touched and any peer files that share the badge.
- **No build step.** Don't introduce one. Don't add `<script type="module">` for the karaoke/audience HTML — the inline scripts assume globals. The games engines under `games/engine/` are the only ESM in the repo and are imported by the games TV/player pages.
- **The Agora App ID is in source on purpose.** Don't try to "fix" it by moving to env vars — there is no server, every client needs it. Same for `YT_API_KEY` in `singer.html` (it's domain-restricted in the Google console).
- **Debug log panels.** Most pages have a "LOG" button bottom-left/right that pops a transcript — it's the primary way users report bugs. When adding new flows, call into the existing `log()` / `tvLog()` helpers instead of `console.log` only.
