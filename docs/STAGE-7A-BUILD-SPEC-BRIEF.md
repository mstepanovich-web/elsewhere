# Stage 7a Build-Spec Brief

**Purpose:** The brief Claude Code uses to author `docs/VENUE-ADMIN-UI-STAGE-7A-BUILD-SPEC.md`. NOT the spec — the locked decision set + structure + verbatim-source anchors the spec must honor. Claude Code writes the full spec from this, then PAUSES for review before any code.

**Stage:** Phase 3 / Plan B — **Stage 7a**, the *prerequisites* sub-stage of Stage 7 (the karaoke read-path switch). Stage 7 is sub-staged: **7a (prereqs, this brief) → 7b (read-path switch behind a flag) → 7c (exhaustive parity verification) → 7d (deletion of AMBIENT_PROFILES + addVenueEffects3D + the 4 dead keys + the flag).** 7a is the buildable, dormant, unit-verifiable, **irreversible-free** piece. 7b/7c/7d are their own sessions.

**Baseline commit:** `524fc40` (Stage 4.5 closeout tail — iOS deferral). origin/main `61a7c07`; 7a's closeout commit will push the 4.5-tail + 7a together (push is a separate gate). Clean tree (3 pre-existing untracked files stay untracked).

**Why 7a is safe:** Both deliverables are **additive and dormant**. The 5 audio anchors are data the live read path doesn't consult (karaoke still plays these venues' audio procedurally via `AMBIENT_PROFILES.audio()` until 7b). The modulator module is unwired infrastructure — published like the renderers were, consulted by nothing in karaoke until 7b. **7a changes NOTHING in the read path** (that's 7b). Net live-karaoke behavior change in 7a: **zero.**

**Discipline (carried from A4a/A4b/4.5, DEFERRED-d):** Specify by exact line reference, exact constant, exact source. Map real code, not prose. The two probes (modulator GSAP sources + render-loop integration) already pulled the canonical source; the spec cites it by line.

---

## §0 — Locked decisions (do not re-litigate)

| # | Decision | Resolution |
|---|----------|-----------|
| **D-scope** | 7a boundary | **Two deliverables only:** (1) `db/040` seed of 5 effect-venue audio anchors; (2) the venue modulator system as a new dormant module. NO read-path change, NO renderer behavior change in karaoke, NO deletion. 7b/7c/7d are separate sessions. |
| **D-driver** | driver build | **Pure-JS (Decision 1, locked).** Reproduce `cheerSwell`/`pulseBeat` curves with the proven `advanceTween` + scheduler pattern from overlay.js/spotlight.js. Rationale: pure-JS ease reproduction has passed the parity bar 3× (spotlight, overlay, 3D) — "pure-JS can't match GSAP" is empirically dead; tiebreaker is **one motion vocabulary** across the whole effect layer (better substrate for games/wellness/worlds to inherit) vs. introducing GSAP as a second motion system. Cost: 2 new eases — trivial. |
| **D-eases** | the 2 new eases | Add to the shared pure-JS ease table: **`power2.out = t => 1 - Math.pow(1-t, 3)`** (cubic out; stadium + disco attack) and **`power1.in = t => t * t`** (quadratic in; stadium decay). Convention matches the existing table (`power1`=quadratic, `power2`=cubic, `power3`=quartic; cf. spotlight.js `power2.in = t*t*t`, overlay.js `power1.out = 1-(1-t)²`). |
| **D-injection** | name→scalar | **ctx-threaded resolver (Decision 2, locked):** `computeModulatorTargets(modulator, elapsedMs, resolver)`. Explicit over implicit at this boundary — karaoke passes live drivers, admin passes oscillators, **visible at the call site**. Rejects the global-registry-with-silent-fallback approach (that's exactly how "prod silently used the preview oscillator" bugs happen — the class of implicit-behavior bug this workstream spent a session catching). |
| **D-guard** | loud failure | When the resolver is threaded but a driver **name does not resolve** (typo / missing driver), **`console.warn` loudly** (name + context) and **do NOT silently substitute** — in particular the karaoke resolver does **NOT** fall back to the preview oscillator. A missing modulator must be obvious, not a subtle "why does disco look off." (This guarantee is the whole point of the explicit resolver.) Post-warn return value: see §4 (recommend identity `1.0` so the effect renders un-modulated rather than crashing — the loud warn is the load-bearing non-silent signal). |
| **D-dormant** | publish dormant | The modulator module is **published dormant** (like the renderers were): loaded/registered, consulted by nothing in karaoke until 7b. The admin preview is **unchanged** (keeps `PREVIEW_OSCILLATORS`). |
| **D-audio-seed** | the 5 anchors | `anc_aud_{stadium,disco,speakeasy,festival,honkytonk}`, `payload {type:'mp3', sound_id:'<venue>'}`, `label='Ambient'`. **`sound_id == venue_id` for all 5 — confirmed** (each closure is `playAmbientMp3('<venue>')`; `playAmbientMp3` fetches `SOUNDS_BASE + venueId + '.mp3'` with no soundId remap; none carry a `soundId` in venues.json). Screen-space (yaw/pitch NULL). |
| **D-migration** | db/040 seed-only | `audio` type is already in the db/032→039 CHECK **and** the RPC `v_known_types`; db/035's RPCs are type-agnostic. So `db/040` is **SEED-ONLY** — `INSERT … ON CONFLICT (id) DO NOTHING` (the db/036/037 pattern). **NO CHECK migration, NO RPC change.** Unlike db/039. |
| **D-no-readpath** | the safety line | 7a ships nothing that changes the read path. `AMBIENT_PROFILES` + `addVenueEffects3D` remain the sole live read path through 7a. This is the property that makes 7a irreversible-free. |

---

## §1 — db/040: the 5 effect-venue audio anchor seed

**The gap this closes:** stadium/disco/speakeasy/festival/honkytonk play their ambient mp3 *inside* `AMBIENT_PROFILES.audio()` (`playAmbientMp3('<venue>')`), and db/035 seeded only the **19 audio-only** venues — so these 5 have NO audio anchor. Without this seed, 7d's deletion of `AMBIENT_PROFILES` would silence all 5.

**Source confirmation (verbatim, `karaoke/stage.html`):**
```
:4602   stadium    audio: () => { playAmbientMp3('stadium'); }
:4678   disco      audio: () => { playAmbientMp3('disco'); }
:4771   speakeasy  audio: () => { playAmbientMp3('speakeasy'); }
:4839   honkytonk  audio: () => { playAmbientMp3('honkytonk'); }
:4853   festival   audio: () => { playAmbientMp3('festival'); }
:4563   async function playAmbientMp3(venueId){ … const url = SOUNDS_BASE + venueId + '.mp3'; … }   // no soundId remap
```
The audio renderer (`shell/venue-renderers/audio.js`) fetches `SOUNDS_BASE + sound_id + '.mp3'` — identical file, so `sound_id = venue_id` for all 5 reproduces `playAmbientMp3` exactly.

**Seed (db/035 column shape + ON CONFLICT DO NOTHING):**
```sql
insert into public.venue_anchors (id, venue_id, type, label, payload) values
  ('anc_aud_stadium',   'stadium',   'audio', 'Ambient', '{"type":"mp3","sound_id":"stadium"}'::jsonb),
  ('anc_aud_disco',     'disco',     'audio', 'Ambient', '{"type":"mp3","sound_id":"disco"}'::jsonb),
  ('anc_aud_speakeasy', 'speakeasy', 'audio', 'Ambient', '{"type":"mp3","sound_id":"speakeasy"}'::jsonb),
  ('anc_aud_festival',  'festival',  'audio', 'Ambient', '{"type":"mp3","sound_id":"festival"}'::jsonb),
  ('anc_aud_honkytonk', 'honkytonk', 'audio', 'Ambient', '{"type":"mp3","sound_id":"honkytonk"}'::jsonb)
on conflict (id) do nothing;
```
yaw/pitch default NULL (screen-space, satisfies `venue_anchors_position_consistency`). Footer verification: `count(*) where type='audio'` = **24** (19 + 5); per-venue sound_id spot-check for the 5; `bad_position = 0`. Header in db/035 house style; MIGRATIONS_APPLIED.md entry only after Mike applies to prod (prod-apply-before-commit).

**Note:** the 5 effect venues now have BOTH an audio anchor (db/040) AND effect anchors (db/036–039) — the first venues to carry an audio anchor alongside effects. The 7b read-path resolves all of a venue's anchors together; this is expected, not a conflict.

---

## §2 — The venue modulator system (new module, dormant)

**New file: `shell/venue-modulators.js`** (sibling to `shell/venue-registry.js`). GSAP-free, pure-JS. Published dormant.

**What a driver is:** a **named scalar** mutated by a **scheduled, eased attack→decay tween chain**, fired on a cadence — structurally identical to the overlay.js/spotlight.js pulse-envelope-on-schedule machinery (beat scheduler + `advanceTween`). The module reuses that pattern, generalized to drive named venue-level scalars.

**The 3 drivers, 2 venues (verbatim source → pure-JS):**

- **`crowd_brightness`** (stadium, `:4625-4634`): a scalar `brightness` init `0.6`, swelling to `1.4` then decaying to `0.6`, on a randomized cadence.
- **`beat_scale`** + **`beat_brightness`** (disco, `:4692-4703`): two scalars driven by ONE tween chain — `scale` 1→1.8→1 and `brightness` 1→1.6→1 — on the 500ms beat.

**Module API (spec finalizes names):**
- `activateVenueDrivers(venueId)` — start the driver(s) for the venue (the scheduled tween chains). stadium → crowd_brightness; disco → beat_scale + beat_brightness; all others → no drivers.
- `deactivateVenueDrivers()` — stop all scheduled timers + tweens (the teardown the venue-change path will call in 7b).
- `resolveModulator(name)` — returns the current scalar for `name`, or triggers the **D-guard loud-failure** for an unknown name. This is the resolver karaoke threads in 7b.
- Published on `window.elsewhere.modulators` (the dormant-publish convention).

**The 2 new eases** go in this module's pure-JS ease table (`power2.out`, `power1.in` per D-eases), alongside the ones it needs that already exist elsewhere (`power2.in`). The module carries its own ease table (self-contained, like spotlight.js) — it does NOT import the renderers'.

**Scoping callout for review — does 7a touch the renderers?** The cleanest, safest 7a is **purely additive: db/040 + venue-modulators.js, zero edits to existing renderers or stage.html.** The `computeModulatorTargets(modulator, elapsedMs, resolver)` signature change (threading the resolver into the renderers' ctx) has its **first real consumer in 7b** (the read-path switch) and touches the admin-preview path — so the recommendation is to **land the signature change in 7b**, not 7a, keeping 7a's surface to two new files. The resolver *function* (with the D-guard) is built in 7a inside venue-modulators.js; the renderer-side ctx-threading is 7b. **If you'd rather do the behavior-preserving signature refactor in 7a** (admin passes an oscillator-wrapping resolver, behavior identical), that's defensible but adds renderer-modification to the "risk-free" sub-stage — flagged for your call. The fidelity table + drivers + resolver are 7a regardless; only the renderer-signature edit's timing is the open question.

---

## §3 — Driver fidelity table (verbatim GSAP → pure-JS, 6-decimal where needed)

The spec must carry this table; each procedural constant maps to its pure-JS reproduction.

| Driver | Init | Attack (target / dur_s / ease) | Decay (target / dur_s / ease) | Schedule | Consumer (7b) |
|--------|------|-------------------------------|-------------------------------|----------|---------------|
| `crowd_brightness` (stadium) | `0.6` | `1.4` / `0.8` / **`power2.out`** | `0.6` / `3.0` / **`power1.in`** | first `4000`ms, then `8000 + random()*8000` ms (8–16s) | stadium phone-lights alpha (× brightness) |
| `beat_scale` (disco) | `1.0` | `1.8` / `0.08` / **`power2.out`** | `1.0` / `0.35` / **`power2.in`** | every `BEAT = 60000/120 = 500`ms (first at `BEAT`) | mirror-ball dot `size = baseSize × scale` |
| `beat_brightness` (disco) | `1.0` | `1.6` / `0.08` / **`power2.out`** | `1.0` / `0.35` / **`power2.in`** | same tween as `beat_scale` (one chain drives both) | mirror-ball dot alpha (× brightness) |

**Verbatim sources to quote in the spec:**
- `crowd_brightness` — `karaoke/stage.html:4625-4634` (`crowdState`, `cheerSwell`).
- `beat_scale`/`beat_brightness` — `:4692-4703` (`beatState`, `pulseBeat`). **Note: one `gsap.to` mutates both `scale` and `brightness` in lockstep** — the pure-JS driver reproduces this as a single tween chain mutating two scalars (the multi-field `advanceTween` shape already exists in spotlight.js §2).

**Precision notes:** no irrationals (`500 = 60000/120` exact; all durations terminating). The `8000 + random()*8000` cadence is non-deterministic by design — the pure-JS driver uses the same `Math.random()*8000 + 8000`; unit-checking validates the *curve shape per fire* and that fires land in the [8s,16s] window, not exact timing.

---

## §4 — The D-guard (loud failure), spelled out

The resolver karaoke threads in 7b resolves only the live drivers. On an unknown name:
1. `console.warn` loudly, once per unique unresolved name (avoid per-frame spam), naming the driver + the venue/anchor context.
2. Return identity `1.0` (the effect renders **un-modulated** — visibly missing its pulse — rather than crashing). The loud warn is the non-silent guarantee; identity avoids a crash. **Critically: NO fallback to `PREVIEW_OSCILLATORS`** — that silent substitution is exactly the bug class D-injection exists to prevent.

(The exact post-warn return is the one small open choice in this guard — `1.0` identity is the recommendation; the spec confirms. The warn-loudly + no-silent-oscillator-fallback is locked.)

---

## §5 — Required spec sections (mirror A4a/A4b/4.5 structure)

1. **§0 Foundation recap** — the §0 locked-decision table.
2. **§1 db/040 seed** — the 5 anchors, the sound_id==venue_id confirmation (with the playAmbientMp3 + venues.json evidence), footer verification queries (count=24, per-venue sound_id, bad_position=0), MIGRATIONS_APPLIED.md.
3. **§2 venue-modulators.js** — module API (activate/deactivate/resolve + publish), the pure-JS driver implementation per the §3 fidelity table, the 2 new eases, the resolver + D-guard. The renderer-signature-change scoping callout (§2 above) resolved per your review.
4. **§3 Fidelity table** — the §3 table, each constant → reproduction, verbatim source quoted by line.
5. **§4 Verification plan** — §6 of this brief.
6. **§5 DEFERRED enumeration** — what 7a closes vs. what's explicitly 7b/7c/7d (the read-path switch, the 2D layered-canvas compositing, the renderer-signature threading if deferred, the deletion).

---

## §6 — 7a verification (zero live-path risk)

- **5 audio anchors (dormant data):** round-trip via the admin overlay/audio panel or direct RPC — author/resolve/confirm `sound_id` for each of the 5; `loadVenueAnchors({type:'audio'})` returns 24. **No live karaoke behavior change** — confirm the 5 venues still play audio via the procedural `playAmbientMp3` path (the anchors are dormant; nothing reads them).
- **Modulator drivers (unwired infra, unit-checked in isolation):** instantiate/activate a driver and sample its scalar over time (console harness), comparing to the §3 curve:
  - `crowd_brightness`: sweeps `0.6 → 1.4` over ~0.8s (power2.out shape), decays `1.4 → 0.6` over ~3.0s (power1.in shape); fires first at ~4s, then at 8–16s intervals.
  - disco beat: `scale 1 → 1.8 → 1` and `brightness 1 → 1.6 → 1` together, attack ~0.08s (power2.out) / decay ~0.35s (power2.in), every ~500ms.
  - **D-guard:** `resolveModulator('nonexistent_driver')` emits the loud `console.warn` and returns identity (no silent oscillator).
- **Zero live karaoke behavior change (the gate):** confirm `AMBIENT_PROFILES` + `addVenueEffects3D` remain the sole read path; `venue-modulators.js` is loaded-but-unconsulted; the 5 audio anchors are dormant. If 7a is purely additive (recommended), there is no edit to any existing renderer or to stage.html's read path to regress.

**Verification deploy:** localhost auth still blocked (per the 4.5 session) → the a45-style branch-deploy playbook IS available if hardware verification is wanted, but 7a's unit-checks (driver curves) + RPC round-trip may be runnable without a full branch deploy — the spec/verification decides whether a deploy is needed given 7a touches no live surface.

---

## §7 — Build-order guidance for the spec

1. `db/040` (5 audio anchors) — apply to prod, verify (count=24), THEN commit.
2. `shell/venue-modulators.js` — the 3 drivers (pure-JS, 2 new eases), activate/deactivate/resolve, D-guard, dormant publish.
3. (If signature change is scoped into 7a per review — otherwise skip to 7b) the behavior-preserving `computeModulatorTargets` resolver threading.
4. Verification: db/040 round-trip + count; driver-curve unit checks; D-guard; zero-live-change confirmation.
5. Closeout (DEFERRED enumeration + the 7b/7c/7d carry-forward + version stamps if any surface changed — note 7a likely touches NO versioned surface if purely additive).

---

## §8 — Process reminders for Claude Code

- **PAUSE after the spec.** No code until Mike approves. Propose-pause per gate thereafter.
- **The safety line (D-no-readpath):** 7a must not change the read path. If a change would touch `startAmbient` / `getProfile` / `addVenueEffects3D` / the render loop, it belongs in 7b — STOP and flag.
- **db/040 is SEED-ONLY** (audio type already in vocab) — no CHECK/RPC migration. Do NOT reproduce the db/039 vocab-extension shape.
- User applies prod migrations manually (Supabase SQL Editor); MIGRATIONS_APPLIED.md updated only after apply; session log doesn't claim db/040 shipped until applied.
- Renderers stay pure-JS (admin-venues.html has zero GSAP — confirmed). venue-modulators.js is GSAP-free too (D-driver).
- No Co-Authored-By trailer. Subject-only commits unless told otherwise.
- The 3 pre-existing untracked files stay untracked. Push is a separate gate.
- 7a is the dormant prerequisite — nothing here is irreversible. The destructive deletion is 7d, after 7c signs off.
