# Venue Admin UI — Stage 7b Build Spec: the read-path switch (behind a flag)

**Status:** Spec for review, pre-implementation. Authored from `docs/STAGE-7B-BUILD-SPEC-BRIEF.md` (approved; all decisions locked incl. D-zorder=B). Implements after review — PAUSE at the end.

**Stage:** Phase 3 / Plan B — **Stage 7b**, the read-path switch behind a flag. Follows 7a (`3f6cf0f`, prerequisites dormant). Precedes 7c (exhaustive parity verification — the deletion gate) and 7d (the irreversible deletion + the compositing-extraction note).

**Baseline commit:** `3f6cf0f`. Clean tree (3 pre-existing untracked files stay untracked).

**The 7b safety frame (load-bearing):** 7b adds the data path **behind a flag, DEFAULT OFF**. With the flag off, the procedural path (`AMBIENT_PROFILES` / `addVenueEffects3D`) is **byte-unchanged in behavior** and default-live. **7b DELETES NOTHING** (that's 7d). The flag **stays through 7c** so the data path is reversible and A/B-comparable against procedural until 7c signs off. Every change in 7b is either additive (new functions, new `#ambient-stack` DOM, new dispatch) or a flag-gated branch that leaves the procedural arm intact.

**Discipline (DEFERRED-d):** exact insertion points, verbatim source, no prose where a line reference exists.

---

## §0 — Locked decisions

| # | Decision | Resolution |
|---|----------|-----------|
| **D-flag** | toggle | `window.elsewhere.useDataPath`, seeded at boot from `?venuepath=data` (absent → false → procedural). |
| **D-flag-once** | read-once | Captured ONCE at venue-change entry into `activeVenuePath` ('data'\|'procedural'); all dispatch points + the render loop read the STORED value, never the live flag. No mid-session half-switch. §1. |
| **D-canvas** | 2D collision | `#ambient-stack` wrapper + one transparent canvas per 2D anchor, self-RAF each. `#ambient-layer` kept for flag-OFF. §2. |
| **D-zorder** | per-venue order | **B (locked):** a hardcoded `LAYER_ORDER` table, per-venue, matched to the verified procedural draw order, **each entry citing its source line** (auditable). A (`z` on payload) is deferred — and `LAYER_ORDER` IS the eventual migration's source-of-truth (post-7d: table values → `anchor.payload.z`). §2. |
| **D-dispatch** | single entry | `renderVenueFromAnchors*` resolves anchors → `getAnchorRenderer(key)` → routes `{stop}` (2D/audio, layered canvas) vs `{update,dispose}` (3D, panScene). A **separate** `dataPath3DHandles` list — the procedural `venueEffects3D` single-object is left untouched (flag-OFF byte-unchanged). §3. |
| **D-resolver** | particle.js only | 3D modules already take `ctx.modulators` — no signature change. Only `particle.js` `computeModulatorTargets` gains a `resolver` param (`:94`, call `:584`); absent → `PREVIEW_OSCILLATORS` (admin edit-free). §4. |
| **D-resolver-target** | clean warn | `resolveModulator(name, target)` — `target` optional; warn drops the "for target" clause when absent (never `'undefined'`). Edit to 7a's `venue-modulators.js`. §4. |
| **D-activation** | modulator hooks | `activateVenueDrivers` at venue activation (data branch); `tickVenueModulators(now)` in the render loop; `deactivateVenueDrivers` in teardown. `renderLoop` gains `now`. overlay needs none. §5. |
| **D-no-delete** | safety line | 7b deletes nothing; procedural stays default-live behind the OFF flag; the flag stays through 7c. |

---

## §1 — The flag (`D-flag` + `D-flag-once`)

**Boot seed** (stage.html, early — before any venue loads):
```js
window.elsewhere = window.elsewhere || {};
window.elsewhere.useDataPath = new URLSearchParams(location.search).get('venuepath') === 'data';
```

**Capture once per venue change** (`D-flag-once`): a module-level `let activeVenuePath = 'procedural';`, set at the **single venue-change entry**. The spec author confirms `initVenueMode` (the function containing `startAmbient(selectedVenueId)` at `:764` + `:788`) is that entry — it both starts the ambient and triggers the panorama build (→ `addVenueEffects3D` at `:2711`). Set at the TOP of `initVenueMode`, before any branching:
```js
activeVenuePath = window.elsewhere?.useDataPath ? 'data' : 'procedural';
```
Both the 2D/audio dispatch (`startAmbient`) and the later async 3D dispatch (`addVenueEffects3D`, fired from the texture-load callback) read this same captured value — so a mid-session flag flip cannot half-switch a venue (it takes effect on the NEXT venue change). The render loop also reads `activeVenuePath`, never the live flag.

**The three branch points (verbatim insertion):**
1. **`startAmbient(venueId)` (`:5014`)** — after the teardown calls (`:5018-5019`):
   ```js
   if(activeVenuePath === 'data'){ activateVenueDrivers(venueId); renderVenueFromAnchors2D(venueId); return; }
   // …existing procedural getProfile().audio()/.anim()… unchanged…
   ```
2. **`addVenueEffects3D(venueId)` (`:2858`, called `:2711`)** — at the top:
   ```js
   if(activeVenuePath === 'data'){ renderVenueFromAnchors3D(venueId); return; }
   // …existing buildStadiumEffects3D / buildSpeakeasyEffects3D… unchanged…
   ```
3. **`renderLoop()` (`:4018`, update at `:4032`/`:4058`)** — §3 (the data-path 3D list iteration + the modulator tick), gated on `activeVenuePath === 'data'`.

Procedural arms are untouched (flag-OFF byte-unchanged). The `return` after the data branch is what leaves the procedural code intact-but-unreached when on.

---

## §2 — The 2D canvas design (`D-canvas` + `D-zorder`)

**Current (verbatim):** `<canvas id="ambient-layer" style="position:fixed;inset:0;z-index:3;pointer-events:none;">` (`:295`); `ambientCtx` (`:4389`); `startParticleLoop` one RAF + one `clearRect`/frame (`:4547`/`:4551`); `stopAmbientAnim` cancels + clears + opacity 0 (`:4509`).

**Data-path DOM:** add a sibling wrapper (next to `#ambient-layer`, same z-slot):
```html
<div id="ambient-stack" style="position:fixed;inset:0;z-index:3;pointer-events:none;"></div>
```
Flag-OFF renders on `#ambient-layer` (unchanged); flag-ON stacks per-anchor canvases in `#ambient-stack`. The other stays empty.

**Per-anchor canvas lifecycle (data-path):**
- *Create* (in `renderVenueFromAnchors2D`): for each 2D anchor in `LAYER_ORDER[venueId]` order, `const c = document.createElement('canvas'); c.width = ambientW; c.height = ambientH; c.style.cssText = 'position:absolute;inset:0;'; document.getElementById('ambient-stack').appendChild(c);` then `handles.push(renderer(anchor, { canvas: c, modulators: karaokeModulators }))`. DOM append order = stack order (ascending z = later-drawn-on-top, matching the procedural draw order).
- *Destroy* (in `teardownDataPath`, called at the next venue change): each handle's `stop()`, then `document.getElementById('ambient-stack').replaceChildren()`.

**`LAYER_ORDER` — VERIFIED, CITED, per-venue (bottom → top):**
```js
// Per-venue 2D-canvas layer order, bottom → top. VERIFIED against the procedural
// draw order (spawnParticles call order = particles[] order = draw order = depth).
// Each entry cites the source line(s) proving the order — this table IS the
// eventual migration's source-of-truth (DEFERRED A: post-7d → anchor.payload.z).
// There is NO global family order: stadium/speakeasy put particle BELOW spotlight,
// but festival puts particle ABOVE spotlight — so order is per-venue.
const LAYER_ORDER = {
  // phone-lights (particle) spawnParticles :4637  BEFORE  beams (spotlight) spawnParticles :4652  → particle below
  stadium:   ['particle', 'spotlight'],
  // floor-flash (overlay) draw :4715  BEFORE  mirror-ball (particle) draw :4722  (one closure :4712) → overlay below
  disco:     ['overlay', 'particle'],
  // smoke (particle) spawnParticles :4794  BEFORE  light-shaft (spotlight) spawnParticles :4816  → particle below
  speakeasy: ['particle', 'spotlight'],
  // strobe (overlay) draw :4898  BEFORE  lasers (spotlight) draw :4900  (closure :4894);  confetti (particle) spawnParticles :4913  AFTER → overlay < spotlight < particle
  festival:  ['overlay', 'spotlight', 'particle'],
  // single overlay anchor — no stacking
  honkytonk: ['overlay'],
};
```
The dispatch orders a venue's 2D anchors by `LAYER_ORDER[venueId].indexOf(anchor.type)`. **Each venue has at most one 2D anchor per type** (verified: stadium's particle-2D + spotlight-2D are one each; the 3D particle/spotlight are `context:'3d-three'`, routed to panScene, NOT in this stack) — so ordering by `type` is unambiguous. (If a future venue carries two 2D anchors of the same type, this needs a tiebreak — note as a guard, not a 7b case.)

**3D anchors are NOT in the 2D stack** — stadium phonelights3d/beams3d + speakeasy candles/smoke3d are `context:'3d-three'`, rendered into `panScene` (z-index:1 pan-layer, 3D-spatial depth). §3 routes them.

---

## §3 — The dispatch (`D-dispatch`)

The data-path replacement for `getProfile().audio()/.anim()` (2D/audio) + `addVenueEffects3D` (3D). Split 2D/3D because the two procedural sites fire at different times (startAmbient immediately; addVenueEffects3D from the async texture-load callback), but they share one anchor resolution.

**Shared resolution + one karaoke modulators getter:**
```js
// ONE getter passed as ctx.modulators to BOTH 2D and 3D renderers. (name, target):
// 2D's computeModulatorTargets passes both; 3D's ctx.modulators(name) passes name-only
// (target undefined → the clean warn drops the clause per D-resolver-target).
const karaokeModulators = (name, target) => window.elsewhere.modulators.resolveModulator(name, target);
let dataPath2DHandles = [];   // {stop} — audio + 2D
let dataPath3DHandles = [];   // {update, dispose} — 3D
```

**2D + audio** (from `startAmbient` data branch):
```js
async function renderVenueFromAnchors2D(venueId){
  const anchors = await resolveVenueAnchors(venueId);   // spec confirms the shell/venue-settings.js API (resolveAnchorSet / loadVenueAnchors)
  const order = LAYER_ORDER[venueId] || [];
  // audio anchors (no canvas)
  for(const a of anchors.filter(x => x.type === 'audio')){
    const r = getAnchorRenderer('audio'); if(!r) continue;
    dataPath2DHandles.push(r(a, {}));
  }
  // 2D-canvas effects, ordered by LAYER_ORDER, one layered canvas each
  const twoD = anchors
    .filter(x => x.type !== 'audio' && x.payload?.context !== '3d-three')
    .sort((a,b) => order.indexOf(a.type) - order.indexOf(b.type));
  for(const a of twoD){
    const r = getAnchorRenderer(a.type); if(!r) continue;     // null = unregistered → skip (graceful)
    const c = makeStackCanvas();                              // create + append to #ambient-stack
    dataPath2DHandles.push(r(a, { canvas: c, modulators: karaokeModulators }));
  }
}
```

**3D** (from `addVenueEffects3D` data branch):
```js
async function renderVenueFromAnchors3D(venueId){
  const anchors = await resolveVenueAnchors(venueId);
  for(const a of anchors.filter(x => x.payload?.context === '3d-three')){
    const key = a.type + '-3d';                               // the A7 lookup-key (spotlight-3d / particle-3d)
    const r = getAnchorRenderer(key); if(!r) continue;
    dataPath3DHandles.push(r(a, { scene: panScene, modulators: karaokeModulators }));   // {update, dispose}
  }
}
```

**Render loop (`:4018`)** — procedural arm UNCHANGED; data arm added (mutually exclusive by which path populated which variable — flag-OFF leaves `dataPath3DHandles` empty and `venueEffects3D` set; flag-ON the reverse):
```js
function renderLoop(now){
  requestAnimationFrame(renderLoop); fc++;
  …
  if(venueEffects3D) venueEffects3D.update();                 // procedural single-object (flag-OFF) — UNCHANGED, both :4032 + :4058
  for(const h of dataPath3DHandles) h.update();               // data-path 3D list (empty when flag-OFF)
  if(activeVenuePath === 'data' && now !== undefined) tickVenueModulators(now);   // §5
  …
}
```
*(Note: the procedural `venueEffects3D` single-object is NOT overloaded into a list — D-no-delete keeps the procedural arm byte-unchanged. The data-path 3D handles live in the separate `dataPath3DHandles`.)*

**Teardown** (`teardownDataPath`, called at venue change — see §5 for the exact hook points):
```js
function teardownDataPath(){
  for(const h of dataPath2DHandles) try{ h.stop?.(); }catch(_){}
  dataPath2DHandles = [];
  document.getElementById('ambient-stack').replaceChildren();
  for(const h of dataPath3DHandles) try{ h.dispose?.(); }catch(_){}
  dataPath3DHandles = [];
  window.elsewhere.modulators.deactivateVenueDrivers();
}
```

The spec confirms `resolveVenueAnchors` (the exact `shell/venue-settings.js` resolver entry — `resolveAnchorSet` per the Phase-2 design, or `loadVenueAnchors`) and whether one fetch can be shared between the 2D + 3D calls (cache per venueId to avoid a double fetch).

---

## §4 — Resolver threading (`D-resolver` + `D-resolver-target`)

**3D modules — no signature change.** `particle-3d.js` takes `ctx.modulators` (`:80-86`, `resolveModulator(ctx, binding)` `:221`); spotlight-3d.js same. 7b passes `{ scene, modulators: karaokeModulators }` (§3). Admin preview passes no `ctx.modulators` → their internal 1.0 fallback (unchanged).

**`particle.js` — the deferred signature change** (`:94` def, `:584` call):
```js
// :94 — add resolver; absent → PREVIEW_OSCILLATORS (admin edit-free)
function computeModulatorTargets(modulator, elapsedMs, resolver) {
  const targets = { alpha: 1.0, size: 1.0 };
  if (!modulator) return targets;
  const bindings = Array.isArray(modulator) ? modulator : [modulator];
  for (const b of bindings) {
    if (!b || !b.name || !b.target) continue;
    targets[b.target] = resolver
      ? resolver(b.name, b.target)                                    // karaoke — live driver
      : (PREVIEW_OSCILLATORS[b.name] || DEFAULT_OSCILLATOR)(elapsedMs); // admin preview — oscillator
  }
  return targets;
}
// :584 — pass ctx.modulators (captured in particleAnchorRenderer(anchor, ctx))
const mods = computeModulatorTargets(payload.modulator, elapsed, ctx.modulators);
```
`particleAnchorRenderer(anchor, ctx)` captures `ctx.modulators` (undefined in admin preview → oscillator fallback; the karaoke getter in karaoke). **admin-venues.html needs ZERO edits** — it passes no `ctx.modulators`, so the admin preview keeps using `PREVIEW_OSCILLATORS`. `spotlight.js` / `overlay.js` bind no modulators — untouched.

**`venue-modulators.js` guard warn fix (`D-resolver-target`):**
```js
function resolveModulator(name, target){
  if(active && Object.prototype.hasOwnProperty.call(active.scalars, name)) return active.scalars[name];
  const where = (target === undefined || target === null) ? '' : ` for target '${target}'`;
  console.warn(`[venue-modulators] unresolved driver '${name}'${where} — returning identity 1.0`);
  return 1.0;
}
```
Present → `…driver 'X' for target 'Y' — returning identity 1.0`; absent → `…driver 'X' — returning identity 1.0` (never `'undefined'`). **Update the 7a §6.2 harness's expected-message assertion** to cover both the with-target and no-target cases.

**Contract reconciliation (document in spec):** `resolveModulator` never returns null (returns 1.0 + warns); `particle-3d` expects `(name)=>number|null` but only calls `ctx.modulators` when a binding exists, so a real miss is a genuine misconfiguration worth the loud warn. The two contracts are compatible; the spec states this explicitly.

---

## §5 — Modulator activation (`D-activation`)

- **`activateVenueDrivers(venueId)`** → `startAmbient` data branch (`:5014`, the §1.1 insertion). Stadium activates `crowd_brightness`; disco activates `beat_scale`/`beat_brightness`; every other venue is a no-op (`VENUE_DRIVERS` has only those two). Procedural branch does NOT call it (procedural self-drives via GSAP — no double-drive).
- **`tickVenueModulators(now)`** → render loop (§3), gated on `activeVenuePath==='data' && now !== undefined`. **`renderLoop` gains a `now` param** — `function renderLoop(now){ requestAnimationFrame(renderLoop); … }` (RAF already passes the timestamp; today's `renderLoop()` ignores it and uses `fc++`). First-call edge: if ever invoked directly (not via RAF) `now` is undefined → the `now !== undefined` guard skips the tick that frame (harmless).
- **`deactivateVenueDrivers()`** → inside `teardownDataPath` (§3), which is called at the venue-change teardown. **Teardown hook points:** `startAmbient` (`:5018-5019`, before re-dispatch) calls `teardownDataPath()` when the outgoing path was data (symmetric with the procedural `stopAmbientAudio()`/`stopAmbientAnim()`); `stopAmbient` (`:5049`) likewise. The spec maps the exact teardown insertion so the previous venue's data-path handles (2D stop + 3D dispose + drivers off + stack cleared) are released before the next venue activates.
- **overlay needs none** — self-drives its beat/stochastic clock from the payload; binds no external driver; its renderer ignores `ctx.modulators`.

---

## §6 — Verification (A/B via the flag)

7b is verified by toggling the flag per venue and comparing the data path against the still-canonical procedural path:

- **Per-venue parity (flag ON `?venuepath=data` vs OFF):** for each effect venue (stadium/disco/speakeasy/festival/honkytonk), confirm the data path renders the **same effects at the same depth**. The **layer order is the high-risk check** — festival's **strobe-under-lasers-under-confetti** and disco's **floor-flash-under-mirror-ball** are where a wrong order shows (the whole reason for the cited `LAYER_ORDER`). Sample audio-only venues: audio plays from the data-path audio anchor (incl. the db/040 effect-venue audio anchors for the 5).
- **Modulator behavior (live drivers, not oscillators):** stadium phone-lights pulse with `crowd_brightness`; disco mirror-ball pulses with `beat_scale`/`beat_brightness` — driven by the render-loop `tickVenueModulators`, resolved through the threaded `karaokeModulators`. Confirm the D-guard fires (loud, clean) if a binding is misconfigured.
- **Flag default-OFF byte-unchanged:** no URL param → procedural canonical, the data branches unreached (`activeVenuePath==='procedural'`), `dataPath3DHandles` empty.
- **No half-switch (`D-flag-once`):** flip `window.elsewhere.useDataPath` mid-session WITHOUT changing venue → the current venue stays fully on its activation-time path; only the next venue change switches.
- **Admin preview still works:** after the particle.js signature change, the admin-venues.html particle preview still animates (oscillator fallback, no `ctx.modulators`) — the edit-free back-compat.
- **No-delete + flag-stays:** `AMBIENT_PROFILES` + `addVenueEffects3D` intact and default-live; the flag persists for 7c.

**Deploy:** 7b touches the live read path (`stage.html`), so verification likely needs the branch-deploy playbook (localhost auth still blocked) — a `7b-verify` branch, Pages-source switch, A/B both `?venuepath=data` and default. The spec/verification confirms; this is unlike 7a (which touched no live surface).

---

## §7 — DEFERRED

**Filed at 7b closeout:**
- **D-zorder option A — `z`-on-payload migration.** 7b ships the hardcoded `LAYER_ORDER` table (B). File the migration-to-data-driven-`z` as deferred. **Explicit B→A path:** `LAYER_ORDER` IS the migration's source-of-truth — post-7d, when the data path goes canonical, migrate each table value into `anchor.payload.z` (the dispatch table becomes the seed; `renderVenueFromAnchors2D` then sorts by `payload.z` instead of `LAYER_ORDER.indexOf(type)`, and the table is deleted). Trigger: data path canonical post-7d, or games-venues needing per-venue re-layering.
- Anything 7b surfaces during build/verification not fixed in 7b.

**Explicitly 7c (NOT 7b):** exhaustive parity verification — all ~33 anchors + 5 audio + modulator behavior, every venue, data vs procedural, side-by-side via the flag. The deletion gate; flag stays.

**Explicitly 7d (NOT 7b):** delete `AMBIENT_PROFILES` + `addVenueEffects3D` + the 4 dead keys (space/forest/underwater + the dead-dragonlair shadowed entry, preserving the live dragonlair venue) + the flag + the `#ambient-layer`-vs-`#ambient-stack` duality + `LAYER_ORDER` (→ payload.z per the B→A path). The STAGE 7 SCOPING NOTE (immersive-compositing extraction) comes due.

---

## §8 — Required spec sections + build order + process

**Spec sections (mirror 7a):** §0 decisions · §1 flag (boot + flag-once) · §2 2D canvas + cited LAYER_ORDER · §3 dispatch (2D/3D split, render-loop, teardown) · §4 resolver threading + guard warn fix · §5 modulator activation · §6 verification (A/B) · §7 DEFERRED.

**Build order (suggested):**
1. Boot flag seed + `activeVenuePath` capture in `initVenueMode` (no behavior change yet — data path not built).
2. `#ambient-stack` DOM + `makeStackCanvas` + `teardownDataPath`.
3. `LAYER_ORDER` (cited) + `renderVenueFromAnchors2D` (audio + 2D).
4. `renderVenueFromAnchors3D` + the render-loop data arm + `renderLoop(now)`.
5. particle.js signature change + `venue-modulators.js` guard warn fix + the 7a harness assertion update.
6. The flag branches at `startAmbient` / `addVenueEffects3D` (wire it live, default OFF).
7. Verification (A/B via branch-deploy).

**Process:**
- **PAUSE after this spec** — no code until Mike approves.
- **The safety line (D-no-delete):** 7b deletes nothing; procedural stays default-live behind the OFF flag. If a change would remove procedural code, it's 7d — STOP and flag.
- **Match the cited LAYER_ORDER** — verified against source; festival/disco diverge from any fixed family order. Keep the source-line citations inline (auditability is B's justification).
- **Admin preview must stay edit-free + working** — the particle.js back-compat fallback is what guarantees it; verify the admin particle preview still animates post-change.
- **Flag DEFAULT OFF**, read-once-per-venue. No Co-Authored-By. Subject-only commits. The 3 pre-existing untracked files stay untracked. Push + branch-deploy are separate gates.
