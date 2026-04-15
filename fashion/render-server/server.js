/**
 * Elsewhere Fashion — Render API Server
 * Node.js / Express
 *
 * Deploy to: Railway, Render.com, or Cloudflare Workers
 * Set env vars before starting (see .env.example)
 *
 * Endpoints:
 *   POST /api/fashion/render     — kick off a render job
 *   GET  /api/fashion/status/:id — poll job status
 *   GET  /health                 — health check
 */

import express from 'express';
import cors from 'cors';
import crypto from 'crypto';
import fetch from 'node-fetch';
import FormData from 'form-data';

const app = express();
app.use(cors());
app.use(express.json({ limit: '30mb' })); // base64 images can be large

const PORT = process.env.PORT || 3001;

// ─── API Keys (set as environment variables) ───────────────────
const FASHN_API_KEY   = process.env.FASHN_API_KEY   || '';
const RUNWAY_API_KEY  = process.env.RUNWAY_API_KEY  || '';
const KLING_API_KEY   = process.env.KLING_API_KEY   || '';    // via kie.ai
const R2_ACCOUNT_ID   = process.env.R2_ACCOUNT_ID   || '';
const R2_ACCESS_KEY   = process.env.R2_ACCESS_KEY   || '';
const R2_SECRET_KEY   = process.env.R2_SECRET_KEY   || '';
const R2_BUCKET       = process.env.R2_BUCKET       || 'elsewhere-fashion';
const R2_PUBLIC_URL   = process.env.R2_PUBLIC_URL   || '';   // e.g. https://pub.elsewhere.app

// ─── In-memory job store (replace with Redis/DB for production) ─
const jobs = new Map();

// ─── Health check ───────────────────────────────────────────────
app.get('/health', (_, res) => res.json({ ok: true, ts: Date.now() }));

// ─── POST /api/fashion/render ───────────────────────────────────
app.post('/api/fashion/render', async (req, res) => {
  const { sessionId, roomCode, mode, userPhoto, garments } = req.body;

  if (!mode || !userPhoto || !garments?.length) {
    return res.status(400).json({ error: 'Missing required fields: mode, userPhoto, garments' });
  }

  const jobId = sessionId || crypto.randomUUID();
  const job = {
    jobId, mode, roomCode,
    status: 'queued',
    stage: 0, stageLabel: 'Queued...',
    stills: [], videoUrl: null,
    error: null,
    createdAt: Date.now(),
  };
  jobs.set(jobId, job);

  // Respond immediately — render happens async
  res.json({ jobId, status: 'queued' });

  // Kick off render pipeline (non-blocking)
  runRenderPipeline(job, userPhoto, garments).catch(err => {
    console.error('[render]', jobId, err);
    job.status = 'error';
    job.error = err.message;
  });
});

// ─── GET /api/fashion/status/:id ────────────────────────────────
app.get('/api/fashion/status/:id', (req, res) => {
  const job = jobs.get(req.params.id);
  if (!job) return res.status(404).json({ error: 'Job not found' });
  res.json(job);
});

// ═══════════════════════════════════════════════════════════════
//  RENDER PIPELINE
// ═══════════════════════════════════════════════════════════════

async function runRenderPipeline(job, userPhoto, garments) {
  const { mode, jobId } = job;

  function setStage(label) {
    job.stageLabel = label;
    job.stage++;
    job.status = 'rendering';
    console.log(`[render] ${jobId} stage ${job.stage}: ${label}`);
  }

  // ── Fashn.ai VTON ────────────────────────────────────────────
  async function fashnVton(userPhotoB64, garmentB64, poseHint = 'frontal') {
    setStage('Generating your look...');
    const body = {
      model_image: `data:image/jpeg;base64,${userPhotoB64}`,
      garment_image: `data:image/jpeg;base64,${garmentB64}`,
      category: 'auto',
      flat_lay: false,
      guidance_scale: 2.5,
      timesteps: 50,
      seed: Math.floor(Math.random() * 99999),
    };
    const resp = await fetch('https://api.fashn.ai/v1/run', {
      method: 'POST',
      headers: { Authorization: `Bearer ${FASHN_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!resp.ok) throw new Error('Fashn.ai error: ' + resp.status + ' ' + await resp.text());
    const { id } = await resp.json();
    return pollFashn(id);
  }

  async function pollFashn(predictionId, maxWait = 120000) {
    const start = Date.now();
    while (Date.now() - start < maxWait) {
      await sleep(3000);
      const r = await fetch(`https://api.fashn.ai/v1/status/${predictionId}`, {
        headers: { Authorization: `Bearer ${FASHN_API_KEY}` }
      });
      const data = await r.json();
      if (data.status === 'completed') return data.output[0]; // URL or base64
      if (data.status === 'failed') throw new Error('Fashn.ai failed: ' + data.error);
    }
    throw new Error('Fashn.ai timeout');
  }

  // ── Runway Gen-4 Turbo image→video ──────────────────────────
  async function runwayImgToVideo(imageUrl, promptText = 'subtle natural motion, fashion model, cinematic') {
    setStage('Adding motion...');
    const resp = await fetch('https://api.dev.runwayml.com/v1/image_to_video', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${RUNWAY_API_KEY}`,
        'Content-Type': 'application/json',
        'X-Runway-Version': '2024-11-06',
      },
      body: JSON.stringify({
        model: 'gen4_turbo',
        promptImage: imageUrl,
        promptText,
        ratio: '720:1280',
        duration: 5,
      }),
    });
    if (!resp.ok) throw new Error('Runway error: ' + resp.status);
    const { id } = await resp.json();
    return pollRunway(id);
  }

  async function pollRunway(taskId, maxWait = 300000) {
    const start = Date.now();
    while (Date.now() - start < maxWait) {
      await sleep(5000);
      const r = await fetch(`https://api.dev.runwayml.com/v1/tasks/${taskId}`, {
        headers: { Authorization: `Bearer ${RUNWAY_API_KEY}`, 'X-Runway-Version': '2024-11-06' }
      });
      const data = await r.json();
      if (data.status === 'SUCCEEDED') return data.output[0];
      if (data.status === 'FAILED') throw new Error('Runway failed: ' + data.failure);
    }
    throw new Error('Runway timeout');
  }

  // ── Kling 2.1 Pro image→video (via kie.ai) ──────────────────
  async function klingCatwalk(imageUrl) {
    setStage('Hitting the catwalk...');
    const resp = await fetch('https://api.kie.ai/api/v1/kling/video/image2video', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${KLING_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model_name: 'kling-v2-pro',
        image_url: imageUrl,
        prompt: 'fashion model walking confidently down a catwalk runway, smooth catwalk walk, full body visible, cinematic slow motion, elegant pose transitions',
        negative_prompt: 'blurry, distorted, low quality',
        cfg_scale: 0.5,
        mode: 'pro',
        duration: '5',
      }),
    });
    if (!resp.ok) throw new Error('Kling error: ' + resp.status);
    const { data } = await resp.json();
    return pollKling(data.task_id);
  }

  async function pollKling(taskId, maxWait = 360000) {
    const start = Date.now();
    while (Date.now() - start < maxWait) {
      await sleep(6000);
      const r = await fetch(`https://api.kie.ai/api/v1/kling/video/${taskId}`, {
        headers: { Authorization: `Bearer ${KLING_API_KEY}` }
      });
      const { data } = await r.json();
      if (data.task_status === 'succeed') return data.task_result.videos[0].url;
      if (data.task_status === 'failed') throw new Error('Kling failed');
    }
    throw new Error('Kling timeout');
  }

  // ── Upload to R2 ─────────────────────────────────────────────
  async function uploadToR2(url, filename) {
    // Fetch the video/image from its source URL, upload to R2
    const fileResp = await fetch(url);
    const buffer = Buffer.from(await fileResp.arrayBuffer());
    const contentType = url.includes('.mp4') ? 'video/mp4' : 'image/jpeg';

    const r2Url = `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com/${R2_BUCKET}/${filename}`;
    await fetch(r2Url, {
      method: 'PUT',
      headers: {
        'Content-Type': contentType,
        'x-amz-acl': 'public-read',
        // Note: in production use proper AWS-SigV4 signing for R2
      },
      body: buffer,
    });
    return `${R2_PUBLIC_URL}/${filename}`;
  }

  // ═══════════════════════════════════════════════════════════
  //  Mode routing
  // ═══════════════════════════════════════════════════════════

  const primaryGarment = garments[0];

  if (mode === 'image') {
    const stillUrl = await fashnVton(userPhoto, primaryGarment.base64);
    const publicUrl = await uploadToR2(stillUrl, `${jobId}-still.jpg`);
    job.stills = [publicUrl];
    job.status = 'complete';
  }

  else if (mode === 'animated_still') {
    const stillUrl = await fashnVton(userPhoto, primaryGarment.base64);
    setStage('Adding motion...');
    const videoUrl = await runwayImgToVideo(stillUrl);
    const publicUrl = await uploadToR2(videoUrl, `${jobId}-animated.mp4`);
    job.videoUrl = publicUrl;
    job.status = 'complete';
  }

  else if (mode === 'multi_angle') {
    setStage('Generating your look...');
    // 3 VTON calls in parallel (front, ¾, back) — Fashn pose hints
    const [front, quarter, back] = await Promise.all([
      fashnVton(userPhoto, primaryGarment.base64, 'frontal'),
      fashnVton(userPhoto, primaryGarment.base64, 'three_quarter'),
      fashnVton(userPhoto, primaryGarment.base64, 'back'),
    ]);
    setStage('Creating all angles...');
    const [vFront, vQuarter, vBack] = await Promise.all([
      runwayImgToVideo(front, 'subtle natural motion, fashion model front view'),
      runwayImgToVideo(quarter, 'subtle natural motion, fashion model three quarter view'),
      runwayImgToVideo(back, 'subtle natural motion, fashion model back view'),
    ]);
    setStage('Editing your video...');
    // TODO: ffmpeg stitch vFront + vQuarter + vBack
    // For now return first clip
    const publicUrl = await uploadToR2(vFront, `${jobId}-multi.mp4`);
    job.videoUrl = publicUrl;
    job.status = 'complete';
  }

  else if (mode === 'catwalk') {
    const stillUrl = await fashnVton(userPhoto, primaryGarment.base64);
    const videoUrl = await klingCatwalk(stillUrl);
    const publicUrl = await uploadToR2(videoUrl, `${jobId}-catwalk.mp4`);
    job.videoUrl = publicUrl;
    job.status = 'complete';
  }

  else if (mode === 'multi_angle_catwalk') {
    setStage('Generating your look...');
    const [front, quarter, back] = await Promise.all([
      fashnVton(userPhoto, primaryGarment.base64, 'frontal'),
      fashnVton(userPhoto, primaryGarment.base64, 'three_quarter'),
      fashnVton(userPhoto, primaryGarment.base64, 'back'),
    ]);
    setStage('Creating all angles...');
    // Angle clips + catwalk in parallel
    const [vFront, vQuarter, vBack, vCatwalk] = await Promise.all([
      runwayImgToVideo(front, 'subtle natural motion, fashion model front view'),
      runwayImgToVideo(quarter, 'subtle natural motion, fashion model three quarter view'),
      runwayImgToVideo(back, 'subtle natural motion, fashion model back view'),
      klingCatwalk(front),
    ]);
    setStage('Putting it all together...');
    // TODO: ffmpeg stitch all clips
    const publicUrl = await uploadToR2(vCatwalk, `${jobId}-full.mp4`);
    job.videoUrl = publicUrl;
    job.status = 'complete';
  }

  else {
    throw new Error('Unknown mode: ' + mode);
  }

  console.log(`[render] ${jobId} complete →`, job.videoUrl || job.stills[0]);
}

// ─── Helpers ────────────────────────────────────────────────────
function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

// ─── Start ──────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`Elsewhere Fashion Render API — port ${PORT}`);
});
