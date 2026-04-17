# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Elsewhere is a multi-device browser party app (Karaoke, Games) that pairs a TV/big-screen "host" page with phone "client" pages over Agora RTC. There is no build step — every entry point is a static HTML file served from GitHub Pages at `https://mstepanovich-web.github.io/elsewhere`.

An earlier Fashion product direction was archived on 2026-04-17 at v2.90 — see `ARCHIVE-NOTES.md` for the pipeline / restore instructions. It lives on the `archive/fashion` branch.

The repo is the deploy artifact: edits to HTML/CSS/JS files go straight to production after `git push` (GitHub Pages serves `main`).

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

`tv2.html` is the current launcher (`tv.html` is the older version, still linked from `index.html` flows). It generates the room code, renders two QRs (karaoke / games), then runs two `AgoraRTC.createClient` watchers in parallel — one per mode — and `window.location.href`s the TV to the right destination as soon as a phone joins the corresponding channel:

| Mode    | Channel suffix       | TV page                  | Phone page              |
|---------|----------------------|--------------------------|-------------------------|
| Karaoke | `elsewhere_<ROOM>`   | `stage.html`             | `singer.html`           |
| Games   | `elsewhere_g<ROOM>`  | `games/tv.html`          | `games/player.html`     |

`index.html` does its own simpler routing: width ≤ 768px → phone page, else TV page. It does not pair devices — it just opens one half of the experience.

### Agora data channel — the load-bearing detail
Both modes use the same Agora App ID (`b2c6543a9ed946829e6526cb68c7efc9`, hardcoded as `AGORA_APP_ID` in every file that needs it) and the same data-stream pattern: JSON messages over `client.sendStreamMessage`. Two things will bite you:

1. **1KB chunking.** Agora silently drops stream messages over ~1KB. Every sender chunks payloads larger than that with an `_chunk: true / id / i / n / d` envelope and every receiver reassembles them in a per-uid buffer (search for `_chunkBuf` / `audChunkBuf` / `_tvChunkBuf`). When you add a new message type, if the JSON could ever exceed ~900 bytes (e.g. full game state, hand snapshots) it MUST go through the chunked sender — see commit `f7ae144` for the regression that motivated this.
2. **`createDataStream` is not always supported.** Some Agora SDK versions (notably the live-mode one used by `singer.html` / `stage.html`) throw on `createDataStream` and the code falls back to `client.sendStreamMessage(bytes, true)` with a null `streamId`. Both call shapes exist in the codebase — don't "clean up" one into the other.

`games/engine/sync.js` is the only place this is wrapped in a class (`GameSync`). The karaoke code does it inline because it predates the wrapper.

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

### Theme system
`elsewhere-theme.css` is the single source of truth for colors, fonts, spacing, radii, z-index. Every HTML file links it (mostly via the absolute GitHub Pages URL `https://mstepanovich-web.github.io/elsewhere/elsewhere-theme.css` so the deployed pages get the live theme). New UI should reach for `var(--color-*)`, `var(--font-*)`, `var(--text-*)`, `var(--tracking-*)`, `var(--radius-*)` etc. instead of hardcoding values. Per-product overrides ride on body classes (e.g. `theme-worlds`, `theme-movies`). An unused `theme-fashion` class is still defined in the stylesheet — left in place because `archive/fashion` references it; no live page uses it.

## Conventions worth knowing

- **Versioning.** Every page renders a `v2.NN` badge (search for `v2.88` to find them all). The convention from git history is: every commit bumps the version and every page that has the badge gets updated together — feature commits use `[vX.YY]` in the subject, e.g. `feat: 'Join as manager' checkbox on join screen [v2.88]`. When you ship a change, bump every `v2.NN` string in files you touched and any peer files that share the badge.
- **No build step.** Don't introduce one. Don't add `<script type="module">` for the karaoke/audience HTML — the inline scripts assume globals. The games engines under `games/engine/` are the only ESM in the repo and are imported by the games TV/player pages.
- **The Agora App ID is in source on purpose.** Don't try to "fix" it by moving to env vars — there is no server, every client needs it. Same for `YT_API_KEY` in `singer.html` (it's domain-restricted in the Google console).
- **Debug log panels.** Most pages have a "LOG" button bottom-left/right that pops a transcript — it's the primary way users report bugs. When adding new flows, call into the existing `log()` / `tvLog()` helpers instead of `console.log` only.
