// shell/venue-renderers/audio.js
//
// Audio anchor renderer for the Venue Admin UI Stage 2 workstream.
// Implements playback for venue_anchors rows of type='audio' with
// payload.type='mp3'. Registered to shell/venue-registry.js's anchor
// renderer registry at module load time.
//
// Per docs/VENUE-ADMIN-UI-A1-BUILD-SPEC.md §7.1's design-fork
// resolution: option (b), wrap-and-call. This module is SELF-CONTAINED
// — its own AudioContext, GainNode, and current-source state. It does
// NOT extract or share state with karaoke/stage.html's playAmbientMp3,
// which is tightly coupled to module-scoped state inside that file.
// Both paths play the same /sounds/<id>.mp3 file from the same URL,
// so sonic output matches. Stage 6 (AMBIENT_PROFILES retirement) is
// where the paths unify: karaoke will switch to call the registry,
// the local playAmbientMp3 will be deleted, this module becomes the
// single source of truth.
//
// Per D8, importing this module does NOT change karaoke's read path.
// AMBIENT_PROFILES in karaoke/stage.html remains load-bearing until
// Stage 6. Registration of this renderer in the registry is permitted
// per spec §8.2 Check 12 — registration is not a reader-path change.

import { registerAnchorRenderer } from '../venue-registry.js';

const SOUNDS_BASE = 'https://mstepanovich-web.github.io/elsewhere/sounds/';
const DEFAULT_GAIN = 0.35;

let audioCtx       = null;
let gainNode       = null;
let currentSource  = null;
let currentSoundId = null;
let playbackGen    = 0;

function ensureCtx() {
  if (!audioCtx) {
    audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    gainNode = audioCtx.createGain();
    gainNode.gain.value = DEFAULT_GAIN;
    gainNode.connect(audioCtx.destination);
  }
  return audioCtx;
}

function stopCurrent() {
  if (currentSource) {
    try { currentSource.stop(); } catch (_) {}
    currentSource = null;
  }
  currentSoundId = null;
  playbackGen++;
}

export async function audioAnchorRenderer(anchor, _ctx) {
  const payload = anchor?.payload || {};
  const soundId = payload.sound_id;
  const type    = payload.type || 'mp3';

  if (!soundId) {
    console.warn('[audio-renderer] anchor missing payload.sound_id', anchor);
    return { stop: () => {} };
  }
  if (type !== 'mp3') {
    console.warn('[audio-renderer] unsupported payload.type:', type,
                 '(Stage 2 supports mp3 only; tts/recorded/uploaded are later types)');
    return { stop: () => {} };
  }

  if (currentSoundId === soundId && currentSource) {
    return { stop: stopCurrent };
  }

  stopCurrent();
  const myGen = ++playbackGen;
  currentSoundId = soundId;

  const ac = ensureCtx();

  try {
    const url = SOUNDS_BASE + encodeURIComponent(soundId) + '.mp3';
    const resp = await fetch(url);
    if (!resp.ok) throw new Error('HTTP ' + resp.status);
    const buf = await resp.arrayBuffer();
    if (myGen !== playbackGen) return { stop: () => {} };

    const decoded = await ac.decodeAudioData(buf);
    if (myGen !== playbackGen) return { stop: () => {} };

    const src = ac.createBufferSource();
    src.buffer = decoded;
    src.loop = true;
    src.connect(gainNode);
    src.start();
    currentSource = src;
  } catch (e) {
    console.warn('[audio-renderer] playback failed for', soundId, '—',
                 e?.message || e);
    if (myGen === playbackGen) {
      currentSoundId = null;
    }
  }

  return { stop: stopCurrent };
}

export function stopAll() {
  stopCurrent();
}

registerAnchorRenderer('audio', audioAnchorRenderer);

if (typeof window !== 'undefined') {
  window.elsewhere = window.elsewhere || {};
  window.elsewhere.audioRenderer = {
    audioAnchorRenderer,
    stopAll,
  };
}
