-- ============================================================================
-- Elsewhere — Venue Admin UI Stage 7a: effect-venue audio anchor seed
-- Migration: 040
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- First migration in Stage 7a (the prerequisites sub-stage of Stage 7, the
-- karaoke read-path switch) per docs/VENUE-ADMIN-UI-STAGE-7A-BUILD-SPEC.md §5.
--
-- SEED-ONLY migration: no RPCs created, NO CHECK constraint change. The
-- `audio` anchor type is already in the db/032 → db/039 venue_anchors_type_check
-- CHECK constraint AND in db/035's rpc_venue_anchor_upsert v_known_types; db/035's
-- RPCs are type-agnostic. So this migration only inserts rows (the db/035/036/037
-- INSERT ... ON CONFLICT (id) DO NOTHING idempotent pattern). Do NOT confuse with
-- db/039's vocab-extension shape — there is no DROP+CREATE CONSTRAINT and no
-- CREATE OR REPLACE FUNCTION here.
--
-- The gap this closes:
--   The 5 EFFECT venues (stadium, disco, speakeasy, festival, honkytonk) play
--   their ambient mp3 PROCEDURALLY, inside AMBIENT_PROFILES.audio() —
--   `playAmbientMp3('<venue>')` at karaoke/stage.html:4602/4678/4771/4839/4853.
--   db/035 seeded audio anchors for only the 19 AUDIO-ONLY venues (the effect
--   venues were excluded because their audio lives in AMBIENT_PROFILES). So these
--   5 have no audio anchor — and Stage 7d's deletion of AMBIENT_PROFILES would
--   silence them. Stage 7a seeds them now (DORMANT) to close the gap before the
--   destructive stage.
--
-- sound_id == venue_id for all 5 — CONFIRMED verbatim:
--   • each closure is `playAmbientMp3('<venue>')` (no soundId argument);
--   • `playAmbientMp3(venueId)` (karaoke/stage.html:4563) builds the URL as
--     `SOUNDS_BASE + venueId + '.mp3'` — NO soundId remap;
--   • none of the 5 carry a `soundId` field in venues.json.
--   The audio renderer (shell/venue-renderers/audio.js) fetches
--   `SOUNDS_BASE + sound_id + '.mp3'` — identical file. So sound_id=venue_id
--   reproduces playAmbientMp3 byte-for-byte. No exception here (unlike db/035's
--   kids-dino2 → 'kids-dino' and enchantedforest → 'enchantedforest' cases).
--
-- DORMANT per Stage 7a (D-additive / D-no-readpath): these 5 anchors are data
-- only. karaoke/stage.html keeps playing the 5 venues' audio via the procedural
-- playAmbientMp3 path until Stage 7b's read-path switch. This migration adds no
-- reader-path change and no surface file is modified by Stage 7a.
--
-- Position consistency: all 5 have yaw_deg=NULL and pitch_deg=NULL (screen-space
-- / non-positional, like every audio anchor) — satisfies db/032's
-- venue_anchors_position_consistency CHECK ((yaw_deg IS NULL) = (pitch_deg IS NULL)).
--
-- Note: these 5 venues now carry an audio anchor ALONGSIDE their effect anchors
-- (db/036–039) — the first venues to do so. The Stage 7b resolver fetches all of
-- a venue's anchors together (audio + effects); this is expected, not a conflict
-- (Web Audio and the canvas/scene renderers operate on independent surfaces).
--
-- Companion docs:
--   • docs/VENUE-ADMIN-UI-STAGE-7A-BUILD-SPEC.md §1, §5 — the binding spec.
--   • docs/STAGE-7A-BUILD-SPEC-BRIEF.md — the foundation brief (locked decisions).
--   • db/035_audio_anchor_rpcs_and_seed.sql — the audio anchor seed pattern +
--     the type-agnostic RPCs this migration relies on (no new functions needed).
--   • karaoke/stage.html:4602/4678/4771/4839/4853 — the 5 procedural audio
--     closures; :4563 playAmbientMp3 (the no-remap URL construction).
-- ============================================================================


begin;


-- ─── Effect-venue audio anchor seed (5 rows) ─────────────────────────────────
-- One row per effect venue. Deterministic ids `anc_aud_<venue>`. Column shape +
-- ON CONFLICT DO NOTHING idempotency match db/035's audio seed. yaw_deg/pitch_deg
-- default NULL (screen-space); is_broken defaults false; link/start_sec/end_sec
-- NULL. Payload carries the audio-internal discriminator type='mp3' + sound_id
-- (the anchor `type` column is 'audio').
insert into public.venue_anchors (
  id, venue_id, type, label, payload
) values
  ('anc_aud_stadium',   'stadium',   'audio', 'Ambient',
   '{"type":"mp3","sound_id":"stadium"}'::jsonb),
  ('anc_aud_disco',     'disco',     'audio', 'Ambient',
   '{"type":"mp3","sound_id":"disco"}'::jsonb),
  ('anc_aud_speakeasy', 'speakeasy', 'audio', 'Ambient',
   '{"type":"mp3","sound_id":"speakeasy"}'::jsonb),
  ('anc_aud_festival',  'festival',  'audio', 'Ambient',
   '{"type":"mp3","sound_id":"festival"}'::jsonb),
  ('anc_aud_honkytonk', 'honkytonk', 'audio', 'Ambient',
   '{"type":"mp3","sound_id":"honkytonk"}'::jsonb)
on conflict (id) do nothing;


commit;


-- ============================================================================
-- Verification queries (run AFTER COMMIT in Supabase SQL Editor)
-- ============================================================================

-- (1) Total audio anchor count: 19 (db/035) + 5 (this migration) = 24.
select count(*) as audio_count from public.venue_anchors where type = 'audio';
-- Expect: audio_count = 24.

-- (2) The 5 new effect-venue audio anchors: sound_id == venue_id, label='Ambient'.
select venue_id, payload->>'sound_id' as sound_id, payload->>'type' as payload_type, label
  from public.venue_anchors
 where id in ('anc_aud_stadium','anc_aud_disco','anc_aud_speakeasy','anc_aud_festival','anc_aud_honkytonk')
 order by venue_id;
-- Expect: 5 rows. For each: sound_id = venue_id, payload_type='mp3', label='Ambient'.
--   disco/disco, festival/festival, honkytonk/honkytonk, speakeasy/speakeasy, stadium/stadium.

-- (3) Position consistency: all 5 are screen-space (both NULL).
select count(*) as bad_position from public.venue_anchors
 where id like 'anc_aud_%'
   and venue_id in ('stadium','disco','speakeasy','festival','honkytonk')
   and (yaw_deg is not null or pitch_deg is not null);
-- Expect: bad_position = 0.
-- ============================================================================
