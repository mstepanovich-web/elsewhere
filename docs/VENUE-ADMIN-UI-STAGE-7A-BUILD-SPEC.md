# Venue Admin UI — Stage 7a Build Spec: prerequisites (audio anchors + venue modulator system)

**Status:** Spec for review, pre-implementation. Authored from `docs/STAGE-7A-BUILD-SPEC-BRIEF.md` (approved, all decisions locked). This is the build spec; Claude Code implements from it **after** review — PAUSE at the end.

**Stage:** Phase 3 / Plan B — **Stage 7a**, the prerequisites sub-stage of Stage 7. Stage 7 is sub-staged **7a → 7b → 7c → 7d**:
- **7a (this spec):** db/040 audio-anchor seed + the venue modulator system. **Purely additive, dormant, zero edits to running code.**
- **7b:** read-path switch behind a flag (data path alongside procedural) — the `computeModulatorTargets` signature change + the 2D layered-canvas integration land here.
- **7c:** exhaustive parity verification (all ~33 anchors + 5 audio + modulator behavior) — the deletion gate.
- **7d:** deletion of `AMBIENT_PROFILES` + `addVenueEffects3D` + the 4 dead keys + the flag; the compositing-extraction note comes due.

**Baseline commit:** `524fc40`. Clean tree (3 pre-existing untracked files stay untracked). Push is a separate gate.

**The 7a invariant (the property that makes it deploy-free and irreversible-free):** 7a ships **two new files and nothing else** — `db/040_effect_venue_audio_seed.sql` and `shell/venue-modulators.js`. **No existing file is modified.** The 5 audio anchors are dormant data (karaoke keeps playing these venues' audio procedurally via `AMBIENT_PROFILES.audio()`); the modulator module is consulted by nothing in karaoke until 7b. Net live-karaoke behavior change: **zero.**

**Discipline (DEFERRED-d):** exact line references, exact constants, verbatim source. Map real code, not prose.

---

## §0 — Locked decisions

| # | Decision | Resolution |
|---|----------|-----------|
| **D-scope** | 7a boundary | Two new files only: `db/040` (5 audio anchors) + `shell/venue-modulators.js` (modulator system). NO read-path change, NO renderer edit, NO deletion. |
| **D-additive** | the 7a invariant | **No existing file is modified.** This is what lets 7a ship without a deploy-verify cycle — there is no running code to regress. |
| **D-driver** | driver build | **Pure-JS** — reproduce `cheerSwell`/`pulseBeat` with the `advanceTween` + scheduler pattern from overlay.js/spotlight.js. One motion vocabulary across the effect layer. |
| **D-eases** | 2 new eases | `power2.out = t => 1 - Math.pow(1 - t, 3)` (cubic out); `power1.in = t => t * t` (quadratic in). Plus `power2.in = t => t * t * t` (already the convention, needed by disco decay). Self-contained in this module. |
| **D-injection** | resolver | `resolveModulator(name, target)` is **built in this module in 7a** (so it exists + is unit-testable) but is **NOT threaded into the renderers' `computeModulatorTargets` until 7b.** The signature change `computeModulatorTargets(modulator, elapsedMs, resolver)` is **7b's first move**, right before the read-path wire. (Ruling: keep 7a's "nothing existing modified" property absolute.) |
| **D-guard** | loud failure | On an unresolved driver name: **`console.warn`, loud + specific, on EVERY unresolved call** (not throttled — a missing driver must be impossible to ignore), naming **both the driver name AND the target**, then return identity `1.0`. The **warn is the load-bearing signal**; the return's only job is "stay deterministic, don't crash." **NO fallback to preview oscillators.** Exact format §4. |
| **D-lockstep** | disco | `beat_scale` + `beat_brightness` are **NOT two independent drivers** — they are two scalars driven by ONE `gsap.to` chain in lockstep (verbatim `:4692-4703`). The pure-JS reproduction MUST be **one scheduler firing one attack→decay that updates both scalars together** (the multi-field `advanceTween`), NOT two schedulers (which could desync — a subtle parity bug). Disco is **one driver emitting two named scalars from a single clock.** |
| **D-dormant** | publish dormant | Module published on `window.elsewhere.modulators`, consulted by nothing in karaoke until 7b. Admin preview unchanged (keeps `PREVIEW_OSCILLATORS`). |
| **D-audio-seed** | the 5 anchors | `anc_aud_{stadium,disco,speakeasy,festival,honkytonk}`, `payload {type:'mp3', sound_id:'<venue>'}`, `label='Ambient'`, yaw/pitch NULL. **`sound_id == venue_id` for all 5 — confirmed verbatim** (§1). |
| **D-migration** | db/040 | **SEED-ONLY.** `audio` type already in the CHECK + RPC `v_known_types`; db/035 RPCs are type-agnostic. `INSERT … ON CONFLICT (id) DO NOTHING`. **NO CHECK migration, NO RPC change.** |

---

## §1 — The 5 effect-venue audio anchors

**The gap:** stadium/disco/speakeasy/festival/honkytonk play their ambient mp3 *inside* `AMBIENT_PROFILES.audio()`; db/035 seeded only the 19 *audio-only* venues. These 5 have no audio anchor — so 7d's deletion of `AMBIENT_PROFILES` would silence them. 7a seeds them now (dormant), closing the gap before the destructive stage.

**`sound_id == venue_id` confirmation (verbatim, `karaoke/stage.html`):**
```
:4602  stadium    audio: () => { playAmbientMp3('stadium'); }
:4678  disco      audio: () => { playAmbientMp3('disco'); }
:4771  speakeasy  audio: () => { playAmbientMp3('speakeasy'); }
:4839  honkytonk  audio: () => { playAmbientMp3('honkytonk'); }
:4853  festival   audio: () => { playAmbientMp3('festival'); }
:4563  async function playAmbientMp3(venueId){ … const url = SOUNDS_BASE + venueId + '.mp3'; … }
```
`playAmbientMp3` uses `venueId` directly to build the URL — **no soundId remap** — and none of the 5 carry a `soundId` in venues.json (verified). The audio renderer (`shell/venue-renderers/audio.js`) fetches `SOUNDS_BASE + sound_id + '.mp3'`, identical file. Therefore `sound_id = venue_id` for all 5 reproduces `playAmbientMp3` byte-for-byte. **No exception** (unlike db/035's kids-dino2 / enchantedforest cases).

**Anchor records (the db/040 seed content):**

| id | venue_id | type | label | payload |
|----|----------|------|-------|---------|
| `anc_aud_stadium` | stadium | audio | Ambient | `{"type":"mp3","sound_id":"stadium"}` |
| `anc_aud_disco` | disco | audio | Ambient | `{"type":"mp3","sound_id":"disco"}` |
| `anc_aud_speakeasy` | speakeasy | audio | Ambient | `{"type":"mp3","sound_id":"speakeasy"}` |
| `anc_aud_festival` | festival | audio | Ambient | `{"type":"mp3","sound_id":"festival"}` |
| `anc_aud_honkytonk` | honkytonk | audio | Ambient | `{"type":"mp3","sound_id":"honkytonk"}` |

All `yaw_deg`/`pitch_deg` NULL (screen-space; satisfies `venue_anchors_position_consistency`). The DDL is §5.

**Multi-anchor note:** these 5 venues now carry an audio anchor *alongside* their effect anchors (db/036–039) — the first venues to do so. The 7b resolver fetches all of a venue's anchors together; this is expected (a venue's full anchor set = audio + effects), not a conflict. The audio renderer and the effect renderers operate on independent surfaces (Web Audio vs canvas/scene).

---

## §2 — The venue modulator system: `shell/venue-modulators.js`

**New module, sibling to `shell/venue-registry.js`.** Pure-JS, GSAP-free (the renderers + admin preview have no GSAP; one motion vocabulary). Self-contained ease table + tween primitive + per-venue driver definitions + the activate/tick/deactivate lifecycle + the resolver + the D-guard. Published dormant on `window.elsewhere.modulators`.

### §2.1 Ease table + tween primitive

Self-contained (does NOT import the renderers'). Carries the three eases the drivers need:
```js
const EASE_FNS = {
  'power2.out': t => 1 - Math.pow(1 - t, 3),   // NEW — cubic out (stadium + disco attack)
  'power1.in':  t => t * t,                     // NEW — quadratic in (stadium decay)
  'power2.in':  t => t * t * t,                 // cubic in (disco decay) — same as spotlight.js convention
};
function easeOf(name){ const fn = EASE_FNS[name]; if(!fn){ console.warn(`[venue-modulators] unknown ease "${name}", using linear`); return t=>t; } return fn; }
```

**Multi-field tween** (the spotlight.js §2 `advanceTween` shape — REQUIRED for D-lockstep). One tween mutates N named scalars with one shared eased `t`:
```js
// tween = { fields:[{name,start,target}], start_ms, dur_ms, ease, on_complete }
function advanceTween(state, now){
  const tw = state.tween; if(!tw) return;
  const elapsed = now - tw.start_ms;
  const t = elapsed <= 0 ? 0 : elapsed >= tw.dur_ms ? 1 : elapsed / tw.dur_ms;
  const e = easeOf(tw.ease)(t);
  for(const f of tw.fields){ state.scalars[f.name] = f.start + (f.target - f.start) * e; }  // ALL fields, one t — lockstep
  if(t >= 1){ state.tween = null; if(tw.on_complete) tw.on_complete(now); }   // pass `now` — single-clock handoff (see §2.3 fix)
}
```

### §2.2 Driver definitions (per venue)

```js
// Each venue's driver: the scalars it emits, the attack/decay envelope, and the cadence.
// stadium = 1 scalar; disco = 2 scalars from ONE tween (D-lockstep). All other venues: no drivers.
const VENUE_DRIVERS = {
  stadium: {
    fields: [{ name: 'crowd_brightness', rest: 0.6, peak: 1.4 }],
    init:   { crowd_brightness: 0.6 },
    attack: { dur_sec: 0.8,  ease: 'power2.out' },
    decay:  { dur_sec: 3.0,  ease: 'power1.in'  },
    first_ms: 4000,
    interval_ms: () => 8000 + Math.random() * 8000,   // randomized 8–16s, per source
  },
  disco: {
    fields: [
      { name: 'beat_scale',      rest: 1.0, peak: 1.8 },
      { name: 'beat_brightness', rest: 1.0, peak: 1.6 },
    ],
    init:   { beat_scale: 1.0, beat_brightness: 1.0 },
    attack: { dur_sec: 0.08, ease: 'power2.out' },
    decay:  { dur_sec: 0.35, ease: 'power2.in'  },
    first_ms: 500,                 // BEAT = 60000/120 = 500
    interval_ms: () => 500,
  },
};
```

### §2.3 Lifecycle — tick-driven (no setTimeout)

Tick-driven (the 7b render loop calls `tickVenueModulators(now)` per frame, like it calls `venueEffects3D.update()` — see the render-loop probe). Tick handles BOTH scheduling and tween advance, so the driver is **deterministic given `now`** (unit-testable without real timers). Scheduling fires on cadence **regardless of in-flight tween**, and a new attack starts from the *current* scalar values (gsap.to-from-current semantics — the source's `gsap.to` overrides any running tween).

```js
let active = null;   // { venueId, def, scalars, tween, activatedAt, nextFireMs }

function activateVenueDrivers(venueId){
  deactivateVenueDrivers();
  const def = VENUE_DRIVERS[venueId];
  active = { venueId, def: def || null, scalars: def ? { ...def.init } : {}, tween: null, activatedAt: null, nextFireMs: null };
}

function deactivateVenueDrivers(){ active = null; }

function tickVenueModulators(now){
  if(!active || !active.def) return;                 // venue has no drivers
  if(active.activatedAt === null){ active.activatedAt = now; active.nextFireMs = now + active.def.first_ms; }
  if(now >= active.nextFireMs){                        // fire on cadence regardless of in-flight tween
    startAttack(now);
    active.nextFireMs = now + active.def.interval_ms();
  }
  advanceTween(active, now);
}

function startAttack(now){
  const d = active.def;
  active.tween = {
    fields: d.fields.map(f => ({ name: f.name, start: active.scalars[f.name], target: f.peak })),  // start = CURRENT (from-current)
    start_ms: now, dur_ms: d.attack.dur_sec * 1000, ease: d.attack.ease,
    on_complete: (completedNow) => {        // receives the SAME tick `now` that completed the attack
      active.tween = {
        fields: d.fields.map(f => ({ name: f.name, start: active.scalars[f.name], target: f.rest })),
        start_ms: completedNow, dur_ms: d.decay.dur_sec * 1000, ease: d.decay.ease, on_complete: null,
      };
    },
  };
}
```
*(**Single-clock handoff (clock-leak fix):** `advanceTween` calls `tw.on_complete(now)` with the tick's `now`; the decay tween stamps `start_ms: completedNow` — the SAME `now` that completed the attack. The decay must NOT call `performance.now()` independently — that would be a second clock, breaking the tick-driven determinism (unit tests can't control `performance.now()`) and, live, starting the decay from wall-clock instead of the render-loop `now` (a small skew — the same two-clocks-where-there-should-be-one class the disco lockstep eliminates, reintroduced at the attack→decay handoff). Everything clocks off the single `now` threaded through `tickVenueModulators(now) → advanceTween(now) → on_complete(now)`. Using `completedNow` (the tick time at completion, frame-quantized) also matches GSAP's onComplete-fires-on-frame behavior, so it's both deterministic AND parity-faithful.)*

*(**D-lockstep made concrete:** the one tween chain mutating both disco scalars in `startAttack`/`advanceTween` is the lockstep guarantee — exactly one `active.tween`, one `start_ms`, one `t`, two fields; no second tween, no second clock.)*

### §2.4 The resolver + publication

```js
function resolveModulator(name, target){
  if(active && Object.prototype.hasOwnProperty.call(active.scalars, name)){
    return active.scalars[name];
  }
  // D-guard — §4. Loud, specific, EVERY unresolved call. No silent oscillator fallback.
  console.warn(`[venue-modulators] unresolved driver '${name}' for target '${target}' — returning identity 1.0`);
  return 1.0;
}

if(typeof window !== 'undefined'){
  window.elsewhere = window.elsewhere || {};
  window.elsewhere.modulators = { activateVenueDrivers, deactivateVenueDrivers, tickVenueModulators, resolveModulator };
}
```

**No karaoke consumer in 7a.** `activateVenueDrivers` / `tickVenueModulators` are called by nothing in stage.html yet (7b wires them into `startAmbient` + the render loop). `resolveModulator` is threaded into the renderers in 7b. In 7a the module is loaded (a `<script type="module">` tag may be added to admin-venues.html and/or stage.html for the dormant-publish, OR the module ships unreferenced and 7b adds the tag — **see the open item below**).

> **Open item for review — does 7a add the `<script>` tag, or ship the file unreferenced?** Adding a registration `<script type="module" src="shell/venue-modulators.js">` to `karaoke/stage.html` would technically modify an existing file, nicking the D-additive invariant. Options: **(a)** ship `venue-modulators.js` with NO tag in 7a (pure additive — the module exists in the repo, loaded by nobody; 7b adds the tag when it wires the consumer), unit-tested in 7a via direct `import()` in the console; **(b)** add the registration tag in 7a (parallels the renderer dormant-publish precedent, but is one edit to stage.html). **Recommendation: (a)** — keep 7a's two-new-files-only invariant absolute; the unit-check imports the module directly. Confirm at review.

---

## §3 — Driver fidelity table (verbatim GSAP → pure-JS, 6-decimal where needed)

Every procedural constant → its pure-JS reproduction. Source: `karaoke/stage.html` @ `524fc40`.

| Driver | Source (verbatim) | Init | Attack | Decay | Cadence |
|--------|-------------------|------|--------|-------|---------|
| `crowd_brightness` (stadium) | `:4625-4634` `crowdState`/`cheerSwell` | `0.600000` | → `1.400000`, `0.800000`s, `power2.out` | → `0.600000`, `3.000000`s, `power1.in` | first `4000`ms, then `8000 + random()*8000`ms |
| `beat_scale` (disco) | `:4692-4703` `beatState`/`pulseBeat` | `1.000000` | → `1.800000`, `0.080000`s, `power2.out` | → `1.000000`, `0.350000`s, `power2.in` | every `500`ms (`60000/120`), first at `500`ms |
| `beat_brightness` (disco) | same `gsap.to` as `beat_scale` (LOCKSTEP) | `1.000000` | → `1.600000`, `0.080000`s, `power2.out` | → `1.000000`, `0.350000`s, `power2.in` | same tween/clock as `beat_scale` |

**Verbatim source blocks the spec quotes:**

`crowd_brightness` — `:4625-4634`:
```js
const crowdState = { brightness: 0.6 };
function cheerSwell(){
  if(currentAmbientVenue !== 'stadium') return;
  gsap.to(crowdState, { brightness: 1.4, duration: 0.8, ease:'power2.out',
    onComplete:()=> gsap.to(crowdState, { brightness: 0.6, duration: 3, ease:'power1.in' }) });
  setTimeout(cheerSwell, 8000 + Math.random()*8000);
}
setTimeout(cheerSwell, 4000);
```

`beat_scale` + `beat_brightness` — `:4692-4703`:
```js
const beatState = { scale: 1, brightness: 1 };
function pulseBeat(){
  if(currentAmbientVenue !== 'disco') return;
  gsap.to(beatState, { scale: 1.8, brightness: 1.6, duration: 0.08, ease: 'power2.out',
    onComplete: ()=> gsap.to(beatState, { scale: 1, brightness: 1, duration: 0.35, ease: 'power2.in' }) });
  setTimeout(pulseBeat, BEAT);   // BEAT = 500
}
setTimeout(pulseBeat, BEAT);
```

**Precision:** no irrationals (`500 = 60000/120` exact; all durations terminating). The 6-decimal column is the canonical representation for the spec's mapping table. The stadium cadence `8000 + random()*8000` is **non-deterministic by design** — the pure-JS driver uses the same `Math.random()*8000 + 8000`; verification (§6) validates the curve shape per fire and that fires land in [8s,16s], not exact wall-clock timing.

**The lockstep guarantee made concrete (D-lockstep):** the disco source's single `gsap.to(beatState, {scale:…, brightness:…})` mutates both scalars on one tween. The reproduction's `startAttack` builds ONE `active.tween` with two `fields` (`beat_scale`, `beat_brightness`); `advanceTween` applies one eased `t` to both. There is no second scheduler and no second tween — scale and brightness are mathematically guaranteed to move together.

---

## §4 — The D-guard spec

`resolveModulator(name, target)` resolves only the active venue's live scalars. On an unknown name:

1. **Warn — loud, specific, every unresolved call** (NOT throttled). Format, verbatim:
   ```
   [venue-modulators] unresolved driver '<name>' for target '<target>' — returning identity 1.0
   ```
   Names **both** the unresolved driver AND the target it was for. Every call warns — a missing driver in the 7b read path fires per-frame, which is the intended "impossible to ignore" property (a missing driver is a bug to fix immediately, not live with).
2. **Return identity `1.0`** — deterministic, non-crashing. The effect renders **un-modulated** (visibly missing its pulse, so you can still see *which* effect on *which* venue is wrong), while the console names exactly what failed. Returning `0` is rejected: it would vanish the effect, discarding the "see the effect" diagnostic half and risking misreading the effect itself as broken.
3. **NO fallback to `PREVIEW_OSCILLATORS`** — silent substitution is the exact bug class D-injection exists to prevent ("prod silently used the preview oscillator"). The karaoke resolver knows only live drivers; a miss is loud, never papered over.

**Why the warn, not the return, is load-bearing:** the return value's job is "stay deterministic, don't crash" (identity 1.0); the warn's job is "make the failure obvious" (loud, specific, every call). The two are split deliberately.

---

## §5 — db/040 migration (seed-only)

`db/040_effect_venue_audio_seed.sql`. Header in db/035 house style. **Seed-only — no RPC, no CHECK change** (audio type already in vocab; db/035 RPCs type-agnostic). One transactional block:

```sql
begin;

-- 5 effect-venue audio anchors. These venues play their ambient mp3 procedurally
-- inside AMBIENT_PROFILES.audio() (playAmbientMp3('<venue>')); db/035 seeded only
-- the 19 audio-only venues, so these 5 had no audio anchor. sound_id == venue_id
-- for all 5 (confirmed: playAmbientMp3 fetches SOUNDS_BASE + venueId + '.mp3' with
-- no remap; none carry a soundId in venues.json). Dormant in 7a — karaoke keeps
-- playing them procedurally until 7b's read-path switch. db/035/036/037 idempotent
-- ON CONFLICT DO NOTHING pattern. Screen-space (yaw/pitch default NULL).
insert into public.venue_anchors (id, venue_id, type, label, payload) values
  ('anc_aud_stadium',   'stadium',   'audio', 'Ambient', '{"type":"mp3","sound_id":"stadium"}'::jsonb),
  ('anc_aud_disco',     'disco',     'audio', 'Ambient', '{"type":"mp3","sound_id":"disco"}'::jsonb),
  ('anc_aud_speakeasy', 'speakeasy', 'audio', 'Ambient', '{"type":"mp3","sound_id":"speakeasy"}'::jsonb),
  ('anc_aud_festival',  'festival',  'audio', 'Ambient', '{"type":"mp3","sound_id":"festival"}'::jsonb),
  ('anc_aud_honkytonk', 'honkytonk', 'audio', 'Ambient', '{"type":"mp3","sound_id":"honkytonk"}'::jsonb)
on conflict (id) do nothing;

commit;
```

**Footer verification queries (run after manual prod apply):**
1. `select count(*) as audio_count from public.venue_anchors where type='audio';` → **24** (19 + 5).
2. `select venue_id, payload->>'sound_id' as sound_id, label from public.venue_anchors where id like 'anc_aud_%' and venue_id in ('stadium','disco','speakeasy','festival','honkytonk') order by venue_id;` → 5 rows, `sound_id == venue_id`, `label='Ambient'`.
3. `select count(*) as bad_position from public.venue_anchors where id like 'anc_aud_%' and (yaw_deg is not null or pitch_deg is not null);` → **0**.

**MIGRATIONS_APPLIED.md** row added only after Mike applies to prod (prod-apply-before-commit). The session log does not claim db/040 shipped until applied.

---

## §6 — Verification (all isolation-verifiable, zero live-karaoke change)

### §6.1 db/040 audio anchors (dormant data)
- After prod apply: footer queries §5 (count=24, per-venue sound_id, bad_position=0).
- Resolve round-trip: `loadVenueAnchors({ venueId:'stadium', type:'audio' })` (and the other 4) returns the seeded anchor with `sound_id` correct. Admin audio panel shows the anchor for each of the 5.
- **Zero live change:** load each of the 5 venues in karaoke (procedural path) — audio still plays via `playAmbientMp3`. The anchors are dormant; nothing reads them. (Karaoke is unchanged because no karaoke file was edited — D-additive.)

### §6.2 Modulator drivers (unwired infra, unit-checked in isolation)
Console harness (e.g. `const m = await import('/shell/venue-modulators.js')` against the deployed file, or a tiny test page) — activate a driver, drive synthetic `now`, sample scalars:

- **`crowd_brightness` (stadium):** `activateVenueDrivers('stadium')`; tick from `t=0`. At ~`4000`ms a fire starts; sample shows `crowd_brightness` rising `0.6 → 1.4` over `0.8`s (power2.out shape — fast then easing in to peak), then `1.4 → 0.6` over `3.0`s (power1.in shape — slow start). Subsequent fires land `8000–16000`ms apart.
- **disco beat (LOCKSTEP):** `activateVenueDrivers('disco')`; tick. Every `500`ms a fire: `beat_scale 1 → 1.8` AND `beat_brightness 1 → 1.6` together over `0.08`s (power2.out), then both back to `1` over `0.35`s (power2.in). **Lockstep check:** at every sampled `now`, `(beat_scale − 1)/0.8 === (beat_brightness − 1)/0.6` (both driven by the same eased `t`) — they are mathematically proportional because one tween drives both. This is the D-lockstep regression sentinel.
- **D-guard:** `resolveModulator('nope', 'alpha')` → emits exactly `[venue-modulators] unresolved driver 'nope' for target 'alpha' — returning identity 1.0` and returns `1.0`. Repeated calls warn every time (not throttled). `resolveModulator('crowd_brightness','alpha')` with stadium active returns the live scalar (no warn).
- **deactivate:** `deactivateVenueDrivers()` → `tickVenueModulators(now)` is a no-op; `resolveModulator('crowd_brightness','alpha')` now warns (no active driver) — confirms teardown.

### §6.3 The zero-live-change gate
- `git status` after 7a: only two new files (`db/040…sql`, `shell/venue-modulators.js`) + the MIGRATIONS_APPLIED.md row + this spec/brief/closeout docs. **No diff to any `.html` or existing `.js`.** (If the §2.4 open item resolves to "add the script tag," that one stage.html line is the sole exception — flagged at review.)
- Confirm `AMBIENT_PROFILES` + `addVenueEffects3D` remain the sole read path; `venue-modulators.js` is loaded-by-nobody (or registration-only).

**Deploy:** because 7a edits no running surface, hardware verification is optional — the §6.2 unit-checks run against the module file directly (console `import()`), and §6.1 is RPC round-trip. A branch deploy (the a45-style playbook) is available if a live admin-panel check of the 5 audio anchors is wanted, but is not required by 7a's surface.

---

## §7 — DEFERRED enumeration

**Closes in 7a:**
- The 5 effect-venue audio-anchor coverage gap (stadium/disco/speakeasy/festival/honkytonk now have dormant audio anchors — 7d's deletion won't silence them).
- The venue modulator system exists, pure-JS, unit-verified — the 3 drivers (crowd_brightness, beat_scale, beat_brightness) reproduced from verbatim source.

**Explicitly 7b (NOT 7a):**
- The `computeModulatorTargets(modulator, elapsedMs, resolver)` **signature change + ctx-threading** into the renderers (D-injection — built in 7a, threaded in 7b).
- The **read-path switch** (`startAmbient`/`getProfile`/`addVenueEffects3D` → resolver-driven anchor rendering), behind a flag.
- The **2D layered-canvas-per-anchor** integration (the canvas-clear collision the render-loop probe found — disco's 2 / festival's 3 2D effects can't share one ambient canvas with per-renderer full clears; resolution: one layered canvas per 2D anchor, keeping the proven renderer contract untouched).
- Wiring `tickVenueModulators(now)` into the render loop (`:4032`/`:4058`) + `activateVenueDrivers(venueId)` into `startAmbient` + `deactivateVenueDrivers()` into the venue-change teardown.

**7c:** exhaustive parity verification (all ~33 anchors + 5 audio + modulator behavior, every venue, data-path vs procedural) — the deletion gate; flag stays so the whole phase is reversible.

**7d:** delete `AMBIENT_PROFILES` + `addVenueEffects3D` + the 4 dead keys (space/forest/underwater + dead-dragonlair, preserving the live dragonlair venue) + the flag. The STAGE 7 SCOPING NOTE (immersive-compositing extraction) comes due.

**Carry-forward note:** the D-guard's per-frame warn-on-every-unresolved-call is intentional; if 7b/7c finds it floods the console enough to obscure *other* diagnostics, a once-per-(name,target,venue) throttle is the refinement — but the locked default is every-call, and a real miss should be fixed fast, not throttled.

---

## §8 — Build order + process reminders

**Build order:**
1. `db/040` (5 audio anchors) — apply to prod, run footer verification (count=24), THEN commit.
2. `shell/venue-modulators.js` — ease table (+2 new eases), multi-field `advanceTween`, `VENUE_DRIVERS`, activate/tick/deactivate, `resolveModulator` + D-guard, dormant publish.
3. Verification: §6.1 (audio round-trip + count + zero-live-change), §6.2 (driver-curve unit checks + lockstep proportionality + D-guard), §6.3 (the no-diff gate).
4. Closeout: DEFERRED enumeration, the 7b/7c/7d carry-forward, the §2.4 script-tag resolution recorded. **No version stamp** if 7a is purely additive (no versioned surface touched).

**Process:**
- **PAUSE after this spec** — no code until Mike approves.
- **The safety line (D-additive / D-no-readpath):** if any change would touch `startAmbient`/`getProfile`/`addVenueEffects3D`/the render loop/`computeModulatorTargets`, it is 7b — STOP and flag. 7a is two new files.
- **db/040 is SEED-ONLY** — do NOT reproduce the db/039 vocab-extension shape.
- User applies prod migrations manually; MIGRATIONS_APPLIED.md updated only after apply.
- `venue-modulators.js` is GSAP-free pure-JS (admin + renderers have no GSAP).
- No Co-Authored-By trailer. Subject-only commits. The 3 pre-existing untracked files stay untracked. Push is a separate gate.
- 7a is the dormant prerequisite — nothing irreversible. The deletion is 7d.
