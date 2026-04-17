# Archived Features

## Fashion (archived April 17, 2026 at v2.90)

**Branch:** `archive/fashion`
**To restore:** `git checkout archive/fashion`

### What it was

A separate product direction focused on AI-generated fashion try-on and short-form video, sharing the Elsewhere brand and room-code pairing model but otherwise independent of the karaoke/games core.

- `fashion/stylist.html` — phone client. Walked users through four steps: pick a mode (still image, animated still, multi-angle video, catwalk, multi-angle catwalk), upload a photo of themselves, pick one or more garments, kick off a render.
- `fashion/display.html` — TV client. Subscribed to the room's fashion Agora channel and displayed the rendered still or video.
- `fashion/audience.html` — optional third role for spectators.
- `fashion/render-server/` — Node/Express service hosting the ML pipeline. Not deployed automatically — lived alongside the static site but ran as a separate Railway/Render.com service (see the commented header in `server.js`).

### Pipeline

```
user photo + garment(s) → Fashn.ai virtual try-on (VTON)
                        → optional Runway Gen-4 Turbo image-to-video (subtle motion)
                          OR Kling 2.1 Pro image-to-video (full catwalk walk)
                        → Cloudflare R2 upload (public bucket)
                        → URL returned to the client
```

Render jobs were tracked in an in-memory `Map` keyed by `jobId`, with status polled via `GET /api/fashion/status/:id`. Stages surfaced friendly labels ("Generating your look...", "Adding motion...", "Hitting the catwalk...", "Putting it all together...").

### TODOs at time of archive

- `multi_angle` and `multi_angle_catwalk` modes generated front / three-quarter / back clips in parallel but **ffmpeg stitching was never implemented** — both modes returned only the first clip rather than a stitched composite. Look for `// TODO: ffmpeg stitch` in `fashion/render-server/server.js`.
- In-memory job store is fine for demo / solo dev but **needs Redis or a real database** for multi-instance deployment — the comment is in `server.js` line 37.
- R2 upload currently uses a naive PUT without AWS-SigV4 signing; production would need the standard signing flow.

### Environment variables the render server expected

| Var              | Purpose                                  |
|------------------|------------------------------------------|
| `FASHN_API_KEY`  | Fashn.ai VTON API auth                   |
| `RUNWAY_API_KEY` | Runway Gen-4 Turbo video generation      |
| `KLING_API_KEY`  | Kling 2.1 Pro via kie.ai (catwalk video) |
| `R2_ACCOUNT_ID`  | Cloudflare R2 account                    |
| `R2_ACCESS_KEY`  | R2 S3-compatible access key              |
| `R2_SECRET_KEY`  | R2 S3-compatible secret key              |
| `R2_BUCKET`      | R2 bucket name (default `elsewhere-fashion`) |
| `R2_PUBLIC_URL`  | Public base URL for the R2 bucket        |

Keys were never committed to the repo — all read from env at startup.

### Reason for archive

Product focus shifted to karaoke + games. Other Elsewhere offerings closer in model to karaoke — meditation, social yoga — are planned next. Fashion's reliance on a server-side ML pipeline (and its paid API dependencies) diverged too far from the static-site + Agora architecture the rest of the product shares. Re-evaluation deferred indefinitely; no date in mind.
