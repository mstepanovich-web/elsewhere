# Stage 7b Build-Spec Brief

**Purpose:** The brief Claude Code uses to author `docs/VENUE-ADMIN-UI-STAGE-7B-BUILD-SPEC.md`. NOT the spec — the locked decision set + structure + verbatim insertion points the spec must honor. Claude Code writes the full spec from this, then PAUSES for review before any code.

**Stage:** Phase 3 / Plan B — **Stage 7b**, the read-path switch (behind a flag) — the second sub-stage of Stage 7. Follows **7a** (prerequisites: db/040 audio anchors + venue-modulators.js, both shipped dormant, `3f6cf0f`). Precedes **7c** (exhaustive parity verification — the deletion gate) and **7d** (the irreversible deletion).

**Baseline commit:** `3f6cf0f` (7a closeout, pushed). Clean tree (3 pre-existing untracked files stay untracked).

**The 7b safety frame (state loudly in the spec):** 7b ships the data path **behind a flag, DEFAULT OFF** — the procedural path (`AMBIENT_PROFILES` / `addVenueEffects3D`) stays canonical and untouched in behavior. **NOTHING is deleted** in 7b (that's 7d). The flag **stays through 7c** so the entire data path is reversible and A/B-comparable against procedural until 7c signs off. 7b is additive + a flagged branch at each dispatch point; the procedural code paths remain intact and default-live.

**Discipline (DEFERRED-d):** exact line references, exact insertion points, verbatim source. The 7b foundation map + the procedural-layer-order verification already pulled the canonical insertion points — the spec cites them by line.

---

## §0 — Locked decisions

| # | Decision | Resolution |
|---|----------|-----------|
| **D-flag** | the toggle | **`window.elsewhere.useDataPath`**, seeded at boot from URL param **`?venuepath=data`** (absent → `false` → procedural canonical). Read at the three dispatch points. |
| **D-flag-once** | read-once-per-venue | **Read the flag ONCE at venue activation and store the chosen path for that venue's full lifecycle.** Do NOT re-read per-frame in the render loop. A mid-session flag flip must not leave a venue half-switched (procedural 2D + data-path 3D). The path is locked at venue activation, consistent until the next venue change. (The render loop reads the STORED choice, not the live flag.) |
| **D-canvas** | 2D collision | **`#ambient-stack` wrapper, one transparent canvas per 2D anchor, DOM-order z-stack, self-RAF each.** `#ambient-layer` (the single procedural canvas) kept for flag-OFF. Keeps the proven renderer contract untouched. §2. |
| **D-zorder** | per-venue layering | **The z-stack order is PER-VENUE (verified — no global family order works).** Matched to the procedural draw order (§2 table). **Encoding sub-decision (OPEN — lock at review):** (A) a `z` int on each 2D-effect anchor payload (data-driven, durable; +migration on ~9 anchors), or (B) a hardcoded `LAYER_ORDER` dispatch table from the verified order (no migration, transitional). **Recommendation: B for 7b**, A filed as deferred (durable answer when the data path goes canonical / games-venues re-layers). |
| **D-dispatch** | single entry | **`renderVenueFromAnchors(venueId)`** — resolve anchors → `getAnchorRenderer(key)` → route each by contract: `{stop}` (2D/audio) vs `{update,dispose}` (3D). The render loop's `venueEffects3D` becomes a list (single→list). §3. |
| **D-resolver** | particle.js only | The 3D modules ALREADY take `ctx.modulators` (`particle-3d.js:80-86, 221`; spotlight-3d.js same) — **no signature change for 3D**, 7b just passes `ctx.modulators`. Only `particle.js` gains the resolver param: `computeModulatorTargets(modulator, elapsedMs, resolver)` (`:94`, one call site `:584`), reading `ctx.modulators`. **Admin preview unchanged** — when `resolver`/`ctx.modulators` is absent, `computeModulatorTargets` falls back to its internal `PREVIEW_OSCILLATORS`, so admin-venues.html needs ZERO edits. §4. |
| **D-resolver-target** | optional + clean warn | `resolveModulator(name, target)` — **`target` optional** (3D calls name-only). The D-guard warn must stay clean: when `target` is present → `[venue-modulators] unresolved driver 'X' for target 'Y' — returning identity 1.0`; when **absent** → `[venue-modulators] unresolved driver 'X' — returning identity 1.0` (drop the "for target" clause, NOT "for target 'undefined'"). This is an edit to the 7a-shipped `venue-modulators.js` guard. §4. |
| **D-activation** | modulator hooks | `activateVenueDrivers(venueId)` at venue activation (data-path branch only); `tickVenueModulators(now)` in the render loop (`:4032`/`:4058`); `deactivateVenueDrivers()` in teardown. The render loop gains a `now` param. **overlay needs none** (self-drives). §5. |
| **D-no-delete** | the safety line | 7b deletes NOTHING. Procedural paths stay intact + default-live (flag OFF). The flag stays through 7c. Deletion is 7d. |

---

## §1 — The flag (`D-flag` + `D-flag-once`)

**Seed at boot** (stage.html, before any venue loads): set `window.elsewhere.useDataPath = new URLSearchParams(location.search).get('venuepath') === 'data'`.

**Read ONCE per venue, stored for the lifecycle** (`D-flag-once`): at venue activation, capture the path into a per-venue module-level variable (e.g. `activeVenuePath = window.elsewhere.useDataPath ? 'data' : 'procedural'`). All three dispatch points + the render loop consult `activeVenuePath`, NOT the live flag — so a mid-session flip only takes effect on the NEXT venue change (no half-switched venue).

**Three insertion points (verbatim):**
1. **2D/audio — `startAmbient(venueId)` (`:5014`):** after `stopAmbientAudio()` + `stopAmbientAnim()` (`:5018-5019`), branch: `if(activeVenuePath==='data') renderVenueFromAnchors2D(venueId); else { …existing getProfile().audio()/.anim()… }`.
2. **3D — `addVenueEffects3D(venueId)` (`:2858`, called `:2711`):** branch: `if(activeVenuePath==='data') renderVenueFromAnchors3D(venueId); else { …existing buildStadium/Speakeasy… }`. (Or fold both 2D+3D into one `renderVenueFromAnchors(venueId)` called from both sites — the spec picks the factoring; §3.)
3. **Render loop — `renderLoop()` (`:4018`, update at `:4032`/`:4058`):** drive the data-path 3D list + `tickVenueModulators(now)` only when `activeVenuePath==='data'`.

Default OFF; flippable rebuild-free (`?venuepath=data` or `window.elsewhere.useDataPath=true` + re-select venue); covers both paths.

---

## §2 — The 2D canvas design (`D-canvas` + `D-zorder`)

**Current (verbatim):** single `<canvas id="ambient-layer" style="position:fixed;inset:0;z-index:3;pointer-events:none;">` (`:295`); `ambientCtx` (`:4389`) draws all 2D effects; `startParticleLoop` (`:4547`) one RAF, one `clearRect`/frame (`:4551`); `stopAmbientAnim` (`:4509`) cancels + clears + opacity 0. Z-order: `pan-layer`(1) → `aud-layer`(2) → `ambient-layer`(3) → … .

**Data-path design:**
- Add `<div id="ambient-stack" style="position:fixed;inset:0;z-index:3;pointer-events:none;">` as a sibling of `#ambient-layer` (same z-slot). Flag-OFF uses `#ambient-layer`; flag-ON uses `#ambient-stack` (the other stays empty/hidden).
- On venue activation (data-path), for each 2D anchor in **per-venue layer order** (below): `createElement('canvas')` at `ambientW×ambientH`, `position:absolute;inset:0`, appended to `#ambient-stack` in ascending z (DOM order = stack order). `renderer(anchor, {canvas, modulators})` self-RAFs on its OWN canvas → no collision (no shared clear).
- Teardown (venue change / stop): each renderer's `{stop}` + `el.remove()`; empty `#ambient-stack`. (Mirrors the admin fresh-canvas + A4b/4.5 remove pattern.)

**Per-venue layer order — VERIFIED against the procedural draw order (bottom → top):**

| Venue | bottom → top | data-path anchors (2D-canvas only) |
|-------|-------------|------------------------------------|
| stadium | phone-lights → beams | particle(point-cloud, db/036) **z0** → spotlight(swept-beam-2d, db/037) **z1** |
| disco | floor-flash → mirror-ball | overlay(db/039) **z0** → particle(point-cloud, db/036) **z1** |
| speakeasy | smoke → light-shaft | particle(volumetric, db/036) **z0** → spotlight(light-shaft, db/037) **z1** |
| festival | strobe → lasers → confetti | overlay(db/039) **z0** → spotlight(pulsed-laser, db/037) **z1** → particle(directional-emitter, db/036) **z2** |
| honkytonk | (single overlay) | overlay(db/039) — no stacking |

Source lines: stadium `:4637`/`:4652`; disco one closure `:4712` (flash before dots); speakeasy `:4794`/`:4816`; festival one closure `:4894` (strobe `:4898` before lasers `:4900`) then confetti `:4913`. **No global family order exists** (stadium/speakeasy: particle BELOW spotlight; festival: particle ABOVE spotlight) — order is per-venue, must match the table.

**3D anchors are NOT in this stack** — stadium phonelights3d/beams3d + speakeasy candles/smoke3d live in `panScene` (3D-spatial depth, z-index:1 pan-layer). The 2D stack orders only the `context:"2d-canvas"` anchors.

**The z-encoding sub-decision (`D-zorder`, OPEN):** the spec implements (B) a `LAYER_ORDER = { stadium:['particle','spotlight'], disco:['overlay','particle'], speakeasy:['particle','spotlight'], festival:['overlay','spotlight','particle'] }` dispatch table (recommended for 7b) — UNLESS you lock (A) the `z`-on-payload + migration. Either way the order above is the ground truth.

---

## §3 — The dispatch (`D-dispatch`)

**`renderVenueFromAnchors(venueId)`** — the data-path replacement for `getProfile().audio()/.anim()` + `addVenueEffects3D`:
```
resolve anchors for venueId   (shell/venue-settings.js resolveAnchorSet / loadVenueAnchors — spec confirms the resolver API)
order the 2D-canvas anchors per LAYER_ORDER[venueId] (or payload.z)
handles2D = []; handles3D = []
for each anchor:
   key = anchor.payload.context === '3d-three' ? anchor.type + '-3d' : anchor.type   // the A7 lookup-key
   renderer = getAnchorRenderer(key)
   if !renderer: continue   (registry returns null for unregistered — graceful skip)
   audio       → renderer(anchor, {})                        → {stop}            → handles2D.push
   2D effect   → layered canvas → renderer(anchor, {canvas, modulators})  → {stop}            → handles2D.push
   3D effect   → renderer(anchor, {scene: panScene, modulators})          → {update, dispose} → handles3D.push
store handles3D as the render-loop list (venueEffects3D); store handles2D for teardown
```
- **2D + audio:** `{stop}` (self-RAF / Web-Audio). Torn down by `stop()`.
- **3D:** `{update, dispose}`. `venueEffects3D` becomes a **list**: render loop `:4032`/`:4058` changes `if(venueEffects3D) venueEffects3D.update()` → `for(const h of venueEffects3D) h.update()` (single→list); teardown iterates `dispose()`. 3D renderers attach to existing `panScene` (`:2709`) — camera/render unchanged.
- The spec decides whether `renderVenueFromAnchors` is one function (called from both `startAmbient` 2D + the `addVenueEffects3D` 3D site) or split 2D/3D; the audio + 2D + 3D resolution can share one anchor fetch.

---

## §4 — Resolver threading (`D-resolver` + `D-resolver-target`)

- **3D modules — NO signature change.** `particle-3d.js` already takes `ctx.modulators` ("optional function getter `(name) => number|null`", `:80-86`, `resolveModulator(ctx, binding)` `:221`); spotlight-3d.js same. 7b passes `ctx.modulators` in the §3 3D dispatch (`{scene, modulators}`). Admin preview already handles its absence (1.0 fallback) — unchanged.
- **2D `particle.js` — the deferred signature change.** `computeModulatorTargets(modulator, elapsedMs)` (`:94`), one call site `:584` (in `particleAnchorRenderer`'s frame loop). Add `resolver`: `computeModulatorTargets(modulator, elapsedMs, resolver)`, reading `resolver` from `ctx.modulators` captured in `particleAnchorRenderer(anchor, ctx)`. **Back-compat:** when `resolver` is undefined, fall back to internal `PREVIEW_OSCILLATORS` — **admin-venues.html needs ZERO edits** (it passes no `ctx.modulators`; karaoke passes the live one). spotlight.js / overlay.js reference no modulators — untouched.
- **The karaoke modulators getter:** karaoke passes `ctx.modulators = name => window.elsewhere.modulators.resolveModulator(name /* target omitted for 3D; 2D may pass it */)`. The 2D `computeModulatorTargets` HAS the binding's `target` and may pass it; the 3D `ctx.modulators(name)` calls name-only.
- **`D-resolver-target` — the guard warn fix (edit `venue-modulators.js`):** make `target` optional and keep the warn clean:
  ```js
  function resolveModulator(name, target){
    if(active && Object.prototype.hasOwnProperty.call(active.scalars, name)) return active.scalars[name];
    const where = (target === undefined || target === null) ? '' : ` for target '${target}'`;
    console.warn(`[venue-modulators] unresolved driver '${name}'${where} — returning identity 1.0`);
    return 1.0;
  }
  ```
  Present → full message; absent → drop the clause (NOT "for target 'undefined'"). The §6.2-harness expected-message check (7a) updates accordingly for the no-target case.

**Contract-shape note for the spec:** `venue-modulators.resolveModulator` never returns null (returns 1.0 + warns); `particle-3d` expects `(name)=>number|null` and only calls it when a binding exists — compatible (a real miss is a genuine misconfig worth the loud warn). The spec documents this so the two contracts are explicitly reconciled.

---

## §5 — Modulator activation (`D-activation`)

- **`activateVenueDrivers(venueId)`** → `startAmbient` at **`:5017`** (right after `currentAmbientVenue = venueId`), **data-path branch only** (procedural self-drives via GSAP — don't double-drive). No-op for venues without drivers (`VENUE_DRIVERS` has stadium + disco only).
- **`deactivateVenueDrivers()`** → `stopAmbient` (`:5049`) + the venue-change teardown (beside `stopAmbientAnim`).
- **`tickVenueModulators(now)`** → render loop at **`:4032`/`:4058`**, beside `venueEffects3D` update. **Add a `now` param:** `renderLoop()` (`:4018`) takes none today (uses `fc++`); change to `function renderLoop(now){ requestAnimationFrame(renderLoop); … }` (RAF already passes the timestamp). Gate the tick on `activeVenuePath==='data'` (it's a no-op without an active driver, but gate for cleanliness). Watch the first-call edge: if `renderLoop` is ever called directly (not via RAF) the first `now` is undefined — the spec handles (skip tick on undefined `now`).
- **overlay needs none** — self-drives its beat/stochastic clock from the payload, binds no external driver; its renderer ignores `ctx.modulators`. Only stadium (`crowd_brightness`) + disco (`beat_scale`/`beat_brightness`) activate drivers.

---

## §6 — Verification approach (7b)

7b is verified by **A/B comparison via the flag** — the data path renders alongside the still-canonical procedural path, toggled per venue:
- **Per-venue parity (flag ON vs OFF):** for every effect venue (stadium/disco/speakeasy/festival/honkytonk) + a sample of audio-only venues, load with `?venuepath=data` and without, and confirm the data path renders **the same effects at the same depth** (the §2 layer order is the high-risk check — festival's strobe-under-lasers-under-confetti especially). The 19 audio-only venues: audio plays from the data-path audio anchor.
- **Modulator behavior:** stadium phone-lights pulse with `crowd_brightness`; disco mirror-ball pulses with `beat_scale`/`beat_brightness` — both via the live drivers (not the preview oscillators), driven by the render-loop tick.
- **Flag default-OFF confirmed:** with no URL param, procedural is canonical and byte-unchanged (the branch is not taken).
- **No-delete confirmed:** `AMBIENT_PROFILES` + `addVenueEffects3D` intact and default-live.
- **The flag STAYS** after 7b — it is the mechanism 7c uses for the exhaustive deletion-gate verification, and is itself deleted only in 7d.

*(Full per-venue × per-effect parity is 7c's exhaustive job; 7b verifies the switch works end-to-end and the layering is right. 7b likely wants a branch-deploy — localhost auth still blocked — since it touches the live read path; the spec/verification confirms.)*

---

## §7 — Required spec sections + DEFERRED

**Spec sections (mirror A4b/4.5/7a):** §0 decisions · §1 flag · §2 2D canvas + per-venue layer table · §3 dispatch · §4 resolver threading + guard warn fix · §5 modulator activation · §6 verification (A/B via flag) · §7 DEFERRED.

**DEFERRED (7b closeout):**
- **`z`-on-payload migration (D-zorder option A)** — if 7b ships the hardcoded `LAYER_ORDER` table (option B), file the migration-to-data-driven-z as deferred (trigger: data path goes canonical post-7d, or games-venues needs per-venue re-layering).
- Anything 7b surfaces that isn't fixed in 7b.

**Explicitly 7c (NOT 7b):** the exhaustive parity verification (all ~33 anchors + 5 audio + modulator behavior, every venue, data vs procedural) — the deletion gate. Flag stays through 7c.

**Explicitly 7d (NOT 7b):** delete `AMBIENT_PROFILES` + `addVenueEffects3D` + the 4 dead keys (space/forest/underwater + dead-dragonlair shadowing) + the flag; the STAGE 7 SCOPING NOTE (immersive-compositing extraction) comes due.

---

## §8 — Process reminders

- **PAUSE after the spec** — no code until Mike approves. Propose-pause per gate thereafter.
- **The safety line (D-no-delete):** 7b deletes nothing; procedural stays default-live behind the OFF flag. If a change would remove procedural code, it's 7d — STOP and flag.
- **Flag DEFAULT OFF** — procedural canonical. The data path is opt-in (`?venuepath=data`) and read-once-per-venue.
- **Match the per-venue layer order (§2 table)** — it's verified against the procedural source; festival/disco diverge from any fixed family order.
- **Admin preview must keep working** — the particle.js back-compat fallback (no `ctx.modulators` → oscillators) is what keeps admin-venues.html edit-free; verify the admin panel still previews after the signature change.
- No Co-Authored-By trailer. Subject-only commits. The 3 pre-existing untracked files stay untracked. Push is a separate gate. 7b likely needs a branch-deploy (localhost auth blocked) — it touches the live read path, unlike 7a.
