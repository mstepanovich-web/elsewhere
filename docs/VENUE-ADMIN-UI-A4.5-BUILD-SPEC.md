# Venue Admin UI — Stage 4.5 Build Spec: the `overlay` anchor type

**Status:** Spec for review, pre-implementation. Authored from `docs/A4_5-BUILD-SPEC-BRIEF.md` (approved). This is a structural + implementation spec, not code. Claude Code implements from this **after** review — PAUSE at the end.

**Stage:** Phase 3 / Plan B — Venue Admin UI **Stage 4.5**. Standalone stage in `docs/VENUE-ADMIN-UI-DIRECTION.md` §7, sibling to Stage 4 (A4a/A4b), NOT a sub-stage of it.

**Baseline commit:** `1fc2552` (A4b closeout). Clean tree (3 pre-existing untracked files stay untracked).

**Deliverable.** A new `overlay` anchor type for screen-space visual overlays, with three venues translated from their procedural ancestors: **disco floor-flash**, **festival strobe**, **honkytonk neon-tint**. Ships: `db/039` (vocab extension + RPC update + 3-anchor seed), `shell/venue-renderers/overlay.js` (new 2D-canvas renderer), an overlay authoring panel in `admin-venues.html`, and one registration `<script>` tag in `karaoke/stage.html`. Ships **DORMANT** (D8 — karaoke keeps reading `AMBIENT_PROFILES` until Stage 7).

**Discipline (DEFERRED-d, carried from A4a/A4b).** Specify by exact line reference, exact constant, exact RPC signature, exact DOM selector. Map real code, not prose. Before writing any renderer or panel code, the implementer reads `shell/venue-renderers/particle.js` + `spotlight.js` (the 2D-canvas renderer contract) and the particle/spotlight panels in `admin-venues.html` (the canonical panel pattern) and matches them by name.

---

## §0 — Locked decisions (do not re-litigate)

| # | Decision | Resolution |
|---|----------|-----------|
| **D-scope** | venue coverage | **Three-venue:** disco floor-flash + festival strobe + honkytonk neon-tint. honkytonk's neon must be translated before Stage 7 can delete `AMBIENT_PROFILES` regardless (when-not-whether); doing it here designs the modulator contract once across both beat-sync AND stochastic-flicker classes. |
| **D-type** | new anchor type | New **`overlay`** type. "Type-in-DB, kind-in-payload" — per-effect variation is `payload.kind`, NOT separate DB types. Screen-space: `yaw_deg`/`pitch_deg` both NULL (satisfies db/032 `venue_anchors_position_consistency`). |
| **D-kinds** | kind vocabulary | **Two kinds: `solid-fill`, `gradient-fill`.** Kind discriminates **paint shape only**. Festival + honkytonk **share `solid-fill`**, differing only in `modulator`. Disco is `gradient-fill`. Argued in §1.1. |
| **D-modulator** | the keystone | **One contract, `modulator.type ∈ {beat, stochastic}`,** emitting `(event_time, target_alpha)` events. Orthogonal to kind/region/fill/envelope. Both classes from day one. §2.2. |
| **D-envelope** | alpha trajectory | `envelope.shape ∈ {pulse, hold}` (`static` reserved). Ease supports explicit / `"default"` (→ `power1.out`) / none (`hold` has no ease). §2.3. |
| **D-region** | extent | Normalized `region:{x,y,w,h}` 0–1, full-canvas `{0,0,1,1}` default. Polygon regions OUT (deferred). |
| **D-fill** | paint discriminator | Discriminated by `kind`. `solid-fill`→`{color}` (RGB only). `gradient-fill`→`{direction, stops[]}`. Vertical only; radial/N-arbitrary deferred. |
| **D-migration** | db/039, two places | Extend db/032 `venue_anchors_type_check` by exactly one value (`'overlay'`) via DROP+CREATE, **AND** extend `v_known_types` in db/035's `rpc_venue_anchor_upsert` (CREATE OR REPLACE, full body). Both in one migration. **The correctness keystone.** §7. Do NOT touch `spotlight-3d`/`particle-3d` (registry-key-only, not DB types). |
| **D-renderer** | new module, 2D | New `shell/venue-renderers/overlay.js`, **2D-canvas not WebGL**, `{ stop }` self-RAF (A3/A4a path). Reuses the existing 2D preview infra; no Three.js, no new WebGL surface. §3. |
| **D-self-contained** | no external scalars | Modulators self-drive (beat clock from `bpm`; stochastic RNG + frame counter). No preview oscillator needed. **Adds ZERO names to A7's driver-registry inventory.** §3.4. |
| **D-panel** | authoring panel | **Single-anchor-per-venue** (each of 3 venues has 1 overlay anchor). PREVENT: `+ Add` hidden at count ≥ 1 (A2/A3 pattern). Built correct-by-construction to the post-A4b standardized panel pattern. §6. |
| **D-framerate** | honkytonk timing | **Preserve frame-counting** (`cooldown_frames` + per-frame probability) for visual parity with the procedural ancestor. Wall-clock normalization deferred. Argued in §2.4. |
| **D-dormancy** | D8 posture | Anchors ship DORMANT data; karaoke reads `AMBIENT_PROFILES` until Stage 7. Registration-only `<script>` in `karaoke/stage.html` (no version bump); real consumer tag in `admin-venues.html` (version bump). |

---

## §1 — Kind vocabulary

Two kinds, both `type:"overlay"`, both `payload.context` implicitly `"2d-canvas"` (overlay is 2D-only — no `3d-three` branch, unlike spotlight/particle).

| Kind | Paint | Venue(s) | Source effect |
|------|-------|----------|---------------|
| `gradient-fill` | linear gradient (N stops) over the region | disco | floor-flash |
| `solid-fill` | single RGB fill over the region | festival, honkytonk | strobe, neon-tint |

### 1.1 Why two kinds, festival+honkytonk shared (argued)

`kind` discriminates **only the paint operation** the renderer's draw branch performs — `c.createLinearGradient(...)` + N `addColorStop` vs. a single `c.fillStyle = "rgba(...)"`. It does **not** encode region or modulator, because:

- **Region is orthogonal (D-region):** a free normalized `{x,y,w,h}`. Baking "rect"/"fullscreen" into a kind name (the brief's tentative `gradient-rect`/`solid-fullscreen`) would lie — a solid fill can occupy a sub-rect; a gradient can be full-canvas. The names would constrain nothing real.
- **Modulator is orthogonal (D-modulator):** if kind encoded the modulator, festival and honkytonk — identical paint, different timing — would need different kinds, and the kind space would multiply combinatorially (`solid-beat`, `solid-stochastic`, …). The modulator contract (the thing that justified three-venue scope) would smear across kind strings instead of living in one sub-object.

So festival and honkytonk **share `solid-fill`** and differ purely in `modulator.type` — which is the cleanest possible demonstration that the modulator axis carries the variation. The renderer does two independent single-responsibility dispatches: **on `kind`** (paint) and **on `modulator.type`** (timing).

---

## §2 — Payload schemas + payload-vs-source fidelity

All three payloads below are the **exact** db/039 seed content. Every field traces to a verbatim source constant (§2.5 fidelity table). The schema is five orthogonal axes that compose: `kind` × `region` × `fill` × `modulator` × `envelope`.

### 2.1 The three anchor payloads (verbatim seed content)

> **Payload excludes the anchor `type`.** The `payload` jsonb carries only `kind`/`region`/`fill`/`modulator`/`envelope` — the anchor `type` (`'overlay'`) is the table **column**, never duplicated inside payload. This matches db/035's audio-seed convention (column `type='audio'`; the payload's own `"type":"mp3"` is a payload-internal format discriminator, not the anchor type). The payload's internal discriminators are `kind`, `modulator.type`, and `envelope.shape`.

**`anc_ovl_disco_floorflash`** — `gradient-fill` / `beat` / `pulse`:
```json
{
  "kind": "gradient-fill",
  "region": { "x": 0, "y": 0.6, "w": 1, "h": 0.4 },
  "fill": {
    "direction": "vertical",
    "stops": [
      { "pos": 0, "color": "255,180,255", "alpha_scale": 1.0 },
      { "pos": 1, "color": "120,80,255",  "alpha_scale": 0.5 }
    ]
  },
  "modulator": { "type": "beat", "bpm": 120, "first_trigger_beats": 0.5, "interval_beats": 1, "target_alpha": 0.18 },
  "envelope":  { "shape": "pulse", "rest_alpha": 0,
                 "attack": { "duration_sec": 0.05, "ease": "power3.out" },
                 "decay":  { "duration_sec": 0.4,  "ease": "power2.in" } }
}
```

**`anc_ovl_festival_strobe`** — `solid-fill` / `beat` / `pulse`:
```json
{
  "kind": "solid-fill",
  "region": { "x": 0, "y": 0, "w": 1, "h": 1 },
  "fill": { "color": "255,255,255" },
  "modulator": { "type": "beat", "bpm": 128, "first_trigger_beats": 4, "interval_beats": 4, "target_alpha": 0.25 },
  "envelope":  { "shape": "pulse", "rest_alpha": 0,
                 "attack": { "duration_sec": 0.04, "ease": "default" },
                 "decay":  { "duration_sec": 0.2,  "ease": "default" } }
}
```

**`anc_ovl_honkytonk_neon`** — `solid-fill` / `stochastic` / `hold`:
```json
{
  "kind": "solid-fill",
  "region": { "x": 0, "y": 0, "w": 1, "h": 1 },
  "fill": { "color": "255,100,50" },
  "modulator": { "type": "stochastic", "cooldown_frames": 180, "change_probability": 0.02,
                 "states": [0.3, 1.0], "low_state_probability": 0.3, "initial_state": 1.0, "alpha_scale": 0.04 },
  "envelope":  { "shape": "hold" }
}
```

Seed row metadata for all three: `label='Overlay'`, `yaw_deg=NULL`, `pitch_deg=NULL`, `start_sec=NULL`, `end_sec=NULL`, `link=NULL`, `is_broken=false`.

### 2.2 The modulator contract (D-modulator — the keystone)

The modulator is the **WHEN + WHAT-TARGET** axis. It emits a sequence of events `(event_time, target_alpha)`; the envelope (§2.3) consumes each event. Discriminated by `modulator.type`:

```
beat:
  bpm                 number   // beats per minute → beat_ms = 60000 / bpm
  first_trigger_beats number   // beats from t0 to the FIRST event
  interval_beats      number   // beats between events
  target_alpha        number   // constant peak per event
  // event times (ms from renderer start) = { (first_trigger_beats + k*interval_beats) * beat_ms : k=0,1,2,… }
  // each event carries target_alpha (constant). beat_ms is derived, NOT stored (6-decimal at runtime: 128→468.75).

stochastic:
  cooldown_frames        number          // min FRAMES between possible state changes
  change_probability     number          // per-frame P(change) once cooldown elapsed
  states                 [number,number] // the two normalized state multipliers
  low_state_probability  number          // P(states[0]) when a change fires; else states[1]
  initial_state          number          // starting multiplier
  alpha_scale            number          // actual target = chosen_state * alpha_scale
  // per frame: cooldown++; if cooldown ≥ cooldown_frames AND rand() < change_probability:
  //   target = (rand() < low_state_probability ? states[0] : states[1]) * alpha_scale; cooldown = 0
  // each state change is an "event" carrying target = chosen_state * alpha_scale.
```

**The unification:** both produce `(event_time, target_alpha)` pairs; downstream is identical. `beat` is a deterministic clock with a constant target (`target_alpha` literal). `stochastic` is an RNG-gated frame counter with a computed target (`chosen_state * alpha_scale`). The renderer's modulator stage hands the target to the envelope and never branches further on type after computing the event.

> **Design choice — `first_trigger_beats`/`interval_beats` over `phase_offset`/`divisor`.** This maps 1:1 to the source's `setTimeout(BEAT*offset)` … `setTimeout(BEAT*interval)` structure and reproduces festival's "first downbeat at beat 4, no spurious t=0 pulse" exactly (festival: `first=4, interval=4` → events at beats 4,8,12; disco: `first=0.5, interval=1` → 0.5,1.5,2.5). A `phase_offset+divisor` form would emit a spurious t=0 event for festival or require an ugly `phase_offset=4`.

### 2.3 The envelope contract (D-envelope)

The envelope shapes actual alpha relative to an event's `target_alpha`. Discriminated by `envelope.shape`:

```
pulse:                          // disco, festival
  rest_alpha  number            // resting alpha between events (0 for both — overlay invisible at rest)
  attack: { duration_sec, ease } // rise rest_alpha → target_alpha
  decay:  { duration_sec, ease } // fall target_alpha → rest_alpha
  // ease ∈ { explicit GSAP-equivalent name | "default" }

hold:                           // honkytonk
  // no attack/decay/ease. On each event, alpha jumps INSTANTLY to target and persists
  // until the next event. Initial alpha = (stochastic) initial_state * alpha_scale.

static:  // RESERVED — not used in 4.5. A future constant (non-modulated) overlay.
```

**Ease representability (the D-envelope requirement, all three cases):**
- **explicit** — disco `attack:"power3.out"`, `decay:"power2.in"`.
- **default** — festival uses GSAP with no `ease` key → GSAP default **`power1.out`**. Represented by the sentinel string `"default"`; the renderer resolves `"default"` → `power1.out`. (This is the explicit "default vs named" distinction the brief required: `"default"` is a first-class representable value, not the absence of a field.)
- **none/instant** — honkytonk `hold` carries no ease at all.

**Renderer ease table:** A4a's `spotlight.js` already implements `power3.out`, `power2.in`, `power1.inOut`, `sine.inOut` as pure-JS. overlay.js needs `power3.out` + `power2.in` (reuse/port) and must **ADD `power1.out`** (A4a shipped `power1.inOut`, NOT `power1.out`) to resolve `"default"`. Formula: `power1.out(t) = 1 - (1 - t)*(1 - t)` (GSAP `Power1.easeOut`). Verify against A4a's pure-JS ease names verbatim when porting.

### 2.4 Honkytonk frame-rate dependence (D-framerate — resolved, argued)

The honkytonk source is **frame-counted**: `neonTimer++` per frame, `neonTimer>180` cooldown, `Math.random()<0.02` per-frame trial. This is inherently frame-rate-coupled (180 frames ≈ 3.0s @ 60fps; ≈ 6.0s @ 30fps). Two options:

- **(A) Preserve frame-counting** — `overlay.js` runs the trial once per RAF tick, exactly as the source does. **CHOSEN.**
- **(B) Normalize to wall-clock** — convert `cooldown_frames` → ms, run the trial on a time delta. Rejected for 4.5.

**Argument for (A):**
1. **The §8 verification bar is "renders visually identically to its procedural ancestor."** The ancestor *is* frame-counted. On any given device, a frame-counted reproduction matches the ancestor's cadence frame-for-frame; a wall-clock version would *diverge* from the ancestor on that same device whenever fps ≠ the assumed rate — i.e., (B) **fails the parity bar by construction.**
2. **(B) is not actually more principled.** Converting 180 frames → a duration requires assuming a frame rate (60fps → 3000ms). That *bakes in* the 60fps assumption while losing fidelity to the ancestor — worst of both.
3. **The coupling is bounded and benign.** This is a slow ambient tint flicker (~3s cooldown), not a beat-locked element. At 30fps it flickers half as often — an aesthetic difference, not a broken effect. Nothing downstream depends on its exact cadence.
4. **The real fix belongs to Stage 7**, when the read-path becomes load-bearing and runs on arbitrary devices/refresh rates side-by-side with live karaoke. Normalizing now optimizes a dormant data path against a hypothetical.

**Filed as DEFERRED** (§9): "honkytonk stochastic time-normalization," trigger = Stage 7 read-path adoption OR observed low-fps drift.

### 2.5 Payload-vs-source fidelity table (6-decimal where non-terminating)

Every procedural constant → payload field. Source = `karaoke/stage.html` @ `1fc2552` (§ verbatim blocks in the brief; lines below).

| Venue | Source (line) | Constant | Payload field | Value |
|-------|--------------|----------|---------------|-------|
| disco | 4676 | `BPM = 120` | `modulator.bpm` | 120 |
| disco | 4710 | `setTimeout(flashBeat, BEAT*0.5)` | `modulator.first_trigger_beats` | 0.5 |
| disco | 4708 | `setTimeout(flashBeat, BEAT)` | `modulator.interval_beats` | 1 |
| disco | 4705 | `alpha: 0.18` | `modulator.target_alpha` | 0.18 |
| disco | 4705 | `duration: 0.05, ease:'power3.out'` | `envelope.attack` | `{0.05, "power3.out"}` |
| disco | 4706 | `alpha: 0, duration: 0.4, ease:'power2.in'` | `envelope.decay` + `rest_alpha` | `{0.4, "power2.in"}`, rest 0 |
| disco | 4717 | `createLinearGradient(0, ambientH*0.6, 0, ambientH)` | `region` + `fill.direction` | `{0,0.6,1,0.4}`, vertical |
| disco | 4718 | `addColorStop(0,'rgba(255,180,255,α)')` | `fill.stops[0]` | `{0, "255,180,255", 1.0}` |
| disco | 4719 | `addColorStop(1,'rgba(120,80,255,α*0.5)')` | `fill.stops[1]` | `{1, "120,80,255", 0.5}` |
| festival | 4851 | `BPM = 128` | `modulator.bpm` | 128 (beat_ms 468.75) |
| festival | 4887,4879 | `setTimeout(strobePulse, BEAT)` + `beatCount%4===0` | `first_trigger_beats`,`interval_beats` | 4, 4 |
| festival | 4881 | `alpha: 0.25` | `modulator.target_alpha` | 0.25 |
| festival | 4881 | `duration: 0.04` (no ease) | `envelope.attack` | `{0.04, "default"}` |
| festival | 4882 | `alpha: 0, duration: 0.2` (no ease) | `envelope.decay` + `rest_alpha` | `{0.2, "default"}`, rest 0 |
| festival | 4893 | `fillStyle='rgba(255,255,255,α)'`, full `fillRect` | `fill.color` + `region` | `"255,255,255"`, `{0,0,1,1}` |
| honkytonk | 4839 | `neonTimer>180` | `modulator.cooldown_frames` | 180 |
| honkytonk | 4839 | `Math.random()<0.02` | `modulator.change_probability` | 0.02 |
| honkytonk | 4839 | `Math.random()<0.3 ? 0.3 : 1` | `states` + `low_state_probability` | `[0.3,1.0]`, 0.3 |
| honkytonk | 4837 | `let neonAlpha=1` | `modulator.initial_state` | 1.0 |
| honkytonk | 4840 | `neonAlpha*0.04` | `modulator.alpha_scale` | 0.04 |
| honkytonk | 4840 | `fillStyle='rgba(255,100,50,…)'`, full `fillRect` | `fill.color` + `region` | `"255,100,50"`, `{0,0,1,1}` |

*No irrational values arise (128→468.75 is exact). The 6-decimal rule applies to any runtime-derived ms value the renderer computes; none need storing in the payload.*

---

## §3 — Renderer design: `shell/venue-renderers/overlay.js`

**New file, sibling to `audio.js` / `particle.js` / `spotlight.js`.** 2D-canvas, self-RAF, `{ stop }` contract (D-renderer). Before writing, read `particle.js` + `spotlight.js` to match the exact registration call and the exact render-function signature + `ctx` shape they consume. overlay.js conforms to that contract — it does NOT invent a new one.

> **Correction (verified against source at build time):** renderers register by `import { registerAnchorRenderer } from '../venue-registry.js'` and call `registerAnchorRenderer('overlay', overlayAnchorRenderer)` at module load — NOT by reaching into `window.elsewhere.anchorRegistry` (that global is the *published API mirror* `venue-registry.js` exposes for non-module consumers, not the self-registration path). The render signature is `renderer(anchor, ctx)` → `{ stop }`, with the canvas at `ctx.canvas` (`canvas.getContext('2d', { willReadFrequently: true })` per the A4b GPU-triage). Each renderer also publishes itself on `window.elsewhere.<type>Renderer` (e.g. `window.elsewhere.overlayRenderer.overlayAnchorRenderer`) — that is the handle the admin preview calls. The earlier `window.elsewhere.anchorRegistry` wording in this spec (§4, §8, §10) is superseded by this note.

### 3.1 Module shape
- Self-contained state per render call: the beat scheduler / stochastic RNG state, current alpha, the active envelope tween (for `pulse`), a RAF handle.
- Registers against anchor `type: "overlay"` at module load (matching the audio/particle/spotlight registration idiom).
- Render entry returns `{ stop }`. `stop()` cancels the RAF, clears scheduled beat timers, and is idempotent (A4a precedent — Stop on every exit path).
- Single context only: overlay is `2d-canvas`. No `payload.context` dispatch (cf. A4b's 2d/3d split — N/A here).

### 3.2 Two-axis dispatch
- **Paint dispatch on `payload.kind`:** `solid-fill` → `c.fillStyle = "rgba(R,G,B,α)"`; `c.fillRect(region→px)`. `gradient-fill` → `c.createLinearGradient` over the region's vertical extent, `addColorStop(pos, "rgba(R,G,B, α*alpha_scale)")` per stop, fill the region rect. Region maps `{x,y,w,h}` → `c.fillRect(x*W, y*H, w*W, h*H)` where W/H are the canvas dims (preview: the bounded preview canvas; karaoke read-path at Stage 7: `ambientW`/`ambientH`).
- **Timing dispatch on `payload.modulator.type`:** `beat` runs the scheduler (§2.2) firing pulse envelopes; `stochastic` runs the per-frame trial (§2.4) doing instant `hold` sets. The current alpha feeds the paint each frame.

### 3.3 Envelope evaluation
- `pulse`: on each beat event, start an attack tween (rest→target over `attack.duration_sec` via `ease`), then a decay tween (target→rest over `decay.duration_sec` via `ease`). Pure-JS ease functions (§2.3); `"default"` → `power1.out`. Tween elapsed-time tracking matches A4a's `spotlight.js` per-tween pattern (port it; do not reinvent). Overlapping events: a new attack supersedes an in-flight decay (matches the source — each beat re-fires `gsap.to`).
- `hold`: alpha is a held scalar set instantly on each stochastic event; no interpolation. Initialize to `initial_state * alpha_scale`.

### 3.4 No preview oscillator (D-self-contained)
Unlike `particle.js`/`spotlight.js`, overlay.js needs **no built-in preview oscillator** for external modulators (no `crowd_brightness`-style scalar). The beat clock derives entirely from `payload.bpm`; the stochastic flicker runs its own `Math.random()` + frame counter. State this explicitly in the module header. Consequence carried to §9: overlay contributes **zero** modulator names to Stage 7's driver registry.

---

## §4 — Registry + script tags

- **Register** overlay.js against `type:"overlay"` via `import { registerAnchorRenderer } from '../venue-registry.js'` → `registerAnchorRenderer('overlay', overlayAnchorRenderer)` at module load, and publish `window.elsewhere.overlayRenderer = { overlayAnchorRenderer }` for the admin preview (the §3 correction note). **Note:** `registerAnchorRenderer` emits a one-time `console.warn` because `'overlay'` is not yet in `venue-registry.js`'s `ANCHOR_TYPE_VOCABULARY` array (still the original 7) — the registry explicitly ALLOWS unknown types (vocabulary is extensible) and the warn is harmless. Adding `'overlay'` to that frozen array in `venue-registry.js` is an optional one-line cleanup to silence it (same situation as any post-db/032 type); not required for 4.5 to function.
- **Script tags — BOTH locations** (the A4a Check-21 lesson; enumerate both):
  1. `admin-venues.html` — `<script type="module" src="shell/venue-renderers/overlay.js"></script>` (the real consumer — preview path). Place alongside the existing audio/particle/spotlight renderer tags.
  2. `karaoke/stage.html` — `<script type="module" src="../shell/venue-renderers/overlay.js"></script>` (**registration-only**, not a read-path change per D8 and the A2/A3/A4a precedent). **No version bump on `karaoke/stage.html`** (registration-only precedent). Place alongside the existing renderer tags (currently audio/particle/spotlight at the top of the file).

---

## §5 — Preview surface

**Reuses the existing 2D-canvas preview infra — NO WebGL, NO Three.js** (D-renderer; this is the A3/A4a path, explicitly NOT the A4b Three.js preview surface).

- Bounded 2D-canvas preview element in the overlay panel (mirror the particle/spotlight 2D preview box: a fixed-aspect bordered canvas). The overlay composites over a neutral/representative backdrop so the alpha is visible (match how particle/spotlight previews present — read the existing markup for the backdrop treatment).
- **Play / Replay / Stop** per the canonical per-row affordances (§6). Play → call overlay.js render(ctx) with the preview canvas + the form's reconstructed payload; Stop → call the returned `{stop}`.
- **Self-driving previews:** because modulators are self-contained (D-self-contained), the preview animates correctly with no oscillator wiring — the beat clock and stochastic RNG run from the payload directly. A `beat` preview pulses on its BPM; a `stochastic` preview flickers on its RNG.
- **Soft-timeout note:** unlike A3's respawn:false particle previews (which needed an "ended — Replay" timeout), overlay effects are **continuous/eternal** (all three source effects are `_eternal:true` loops). No soft-timeout needed; Stop is the only terminator. (Confirm against the particle panel's timeout logic so the overlay panel simply omits it rather than copying it.)

---

## §6 — Overlay authoring panel (`admin-venues.html`)

**Single-anchor-per-venue (D-panel).** Each of the 3 venues has exactly one overlay anchor. PREVENT additional: `+ Add overlay anchor` hidden when count ≥ 1 (the A2/A3 pattern; A4b's multi-anchor anchor-list was driven by speakeasy's 2 spotlight anchors — overlay has no such case, so do NOT inherit the anchor-list complexity).

### 6.1 Form structure — three nested discriminated sections
The panel form swaps sections via the **hide/show** pattern (NOT re-render — see §6.3), three independent selectors:
1. **`kind` selector** (`solid-fill` ⇄ `gradient-fill`) — swaps the fill section: `solid-fill` shows a single color field; `gradient-fill` shows direction + a stops editor (per-stop pos/color/alpha_scale).
2. **`modulator.type` selector** (`beat` ⇄ `stochastic`) — swaps the modulator section: `beat` shows bpm/first_trigger_beats/interval_beats/target_alpha; `stochastic` shows cooldown_frames/change_probability/states/low_state_probability/initial_state/alpha_scale.
3. **`envelope.shape` selector** (`pulse` ⇄ `hold`) — swaps the envelope section: `pulse` shows rest_alpha + attack{duration,ease} + decay{duration,ease} (ease as a select including a literal **"default"** option, plus power3.out/power2.in/etc.); `hold` shows nothing (no envelope params).
4. **`region` fields** — always visible: x/y/w/h (0–1), defaulting to `{0,0,1,1}`.

Payload is **reconstructed from form state at preview/save time** (the A3 full-payload-replace pattern via `p_partial.payload`, not field-level patching). Light validation: numeric ranges (alpha/pos/region ∈ [0,1]; probabilities ∈ [0,1]); the renderer degrades gracefully on shape errors (A3 precedent — validate well-formedness, not deep schema shape).

### 6.2 Standardized affordances (correct-by-construction)
Born conforming to the **post-A4b standardized pattern**: `.anchor-row-actions` container; tokens `▶ Play preview` / `↻ Replay` (U+21BB) / `⏹ Stop` (U+23F9) / `Save` / (`Cancel` if pending else `Delete`); `<div class="anchor-status" data-status></div>`; `.anchor-status` styling (`'success'`→gold, `'error'`→#e07e7e — note the A4b-surfaced `'ok'`→`'success'` class-name correctness; use `'success'`). Per-row Stop state machine (Idle: Play visible, Replay+Stop hidden → Playing: Play hidden, Replay+Stop visible → Stop: → Idle).

Dirty tracking: `state.overlayAnchorDirty` Set (the A3/A4a `particleAnchorDirty`/`spotlightAnchorDirty` Set idiom — inline `.add(...)`); extend `beforeunload` + `venueHasAnyDirty` + `discardAllForVenue` to include it. `loadAndRenderOverlayPanel` called from the venue-selection callback alongside the audio/particle/spotlight panel loaders.

**Version stamp:** bump `admin-venues.html`'s `v2.NN` to the next in its sequence (A4b shipped `v2.140`; overlay → `v2.141`). Bump only `admin-venues.html` (the surface touched); `karaoke/stage.html` is registration-only (no bump, §4).

### 6.3 FLAG — inherited panel-polish DEFERREDs (RESOLVED status, do not assume closed)

Three earlier-filed DEFERREDs live in this panel-rendering path. **Current status in `docs/DEFERRED.md`: all three still `Status: Deferred` — NOT marked completed.** The A4b verification result (`docs/SESSION-LOGS/2026-05-31-A4b-verification-result.md` C2.1, lines 192/214) shows A4b *substantially advanced but did not fully close* them, and the statuses were never updated (a CLAUDE.md item-4 bookkeeping slip):

| DEFERRED | What A4b did | Residual (still open) |
|----------|-------------|----------------------|
| 5017 — spotlight kind-switch re-renders (A3 hide/show) | A4b panel restructure intended hide/show; **not independently confirmed shipped** for the kind-switch | treat as open; overlay uses hide/show from the start (§6.1) |
| 5061 — button styling + Stop-all placement | per-row Stop added; **button theming + Stop-all relocation deferred** to a "panel-standardization unification pass" (suggested Stage 6) | open |
| 5100 — missing per-row Stop | per-row Stop now on all preview-capable rows **except the audio panel** (kept A2 panel-level stop-all) | audio-panel per-row Stop still open |

**Implication for 4.5:** the overlay panel inherits the same panel-rendering path, so these can re-surface. **The spec does not assume they are resolved.** 4.5's job is **not** to fix the other panels — overlay is built correct-by-construction (hide/show kind-switch, per-row Stop, themed buttons) so it adds **no new** debt. The residuals against audio/particle/spotlight stay with the future "panel-standardization unification pass" (Stage 6 candidate per the A4b verification doc). **Bookkeeping action at 4.5 closeout (not implementation):** note in the session log that 5017/5061/5100 remain `Deferred` with partial A4b progress, so the next reader isn't misled by stale statuses. Do not retroactively edit their statuses in this stage (they belong to the unification pass that actually closes them).

---

## §7 — db/039 migration (the correctness keystone)

**One transactional file, THREE sections** (mirrors db/035's RPC+seed structure). `db/039_overlay_anchor_vocab_and_seed.sql`.

### Section 1 — extend the CHECK vocabulary (DROP + CREATE)
Per db/032:248-253's own documented doctrine ("extend via DROP+CREATE CONSTRAINT"):
```sql
alter table public.venue_anchors drop constraint venue_anchors_type_check;
alter table public.venue_anchors add constraint venue_anchors_type_check
  check (type in ('callout','pin','spotlight','particle','audio','video','link-hotspot','overlay'));
```
Exactly one new value (`'overlay'`). The DROP+ADD validates existing rows — all current rows carry valid types, so ADD succeeds. (Do NOT add `spotlight-3d`/`particle-3d` — registry-key-only per A4b, never DB types.)

### Section 2 — extend the RPC vocabulary (CREATE OR REPLACE, full body) ⚠️ THE KEYSTONE
`db/035`'s `rpc_venue_anchor_upsert` carries `v_known_types` (db/035:93-94) as a verbatim mirror of the CHECK vocabulary. It **rejects** any type not in that array (errcode 22023, db/035:131-136). If only the CHECK is widened, overlay upserts from the admin panel will fail at the RPC. **Both must change in this migration.**

- **Verify first:** confirm db/035 is still the canonical definition of `rpc_venue_anchor_upsert` (the foundation pass confirmed: 036/037/038 are seed-only, 034 is `venue_default_update` — none redefine it; re-verify at write time with `grep -rn "function.*rpc_venue_anchor_upsert" db/`).
- **CREATE OR REPLACE the FULL function body** from db/035 (you cannot partially alter a function body), changing only:
  ```sql
  v_known_types text[] := array['callout','pin','spotlight','particle',
                                'audio','video','link-hotspot','overlay'];
  ```
- **Re-state the grant block** after the function (CREATE OR REPLACE preserves grants, but re-state per db/035's Bug-2 doctrine — belt-and-suspenders): `revoke ... from public; revoke ... from anon; grant execute ... to authenticated;` for `rpc_venue_anchor_upsert(text,text,jsonb)`. (`rpc_venue_anchor_delete` is type-agnostic — untouched.)

### Section 3 — seed the 3 overlay anchors
`INSERT … ON CONFLICT (id) DO NOTHING` (the db/035–037 idempotent pattern), one row per §2.1 payload, deterministic ids `anc_ovl_{venue}_{effect}`, `label='Overlay'`, `yaw_deg=NULL`, `pitch_deg=NULL`.

### Footer verification queries (run against prod after manual apply)
1. CHECK now admits overlay: `select 'overlay' = any(...)` via `pg_get_constraintdef` of `venue_anchors_type_check` includes `'overlay'`.
2. RPC vocab includes overlay: `pg_get_functiondef('public.rpc_venue_anchor_upsert(text,text,jsonb)'::regprocedure)` contains `'overlay'`.
3. Grant surface intact: `has_function_privilege('authenticated', …, 'EXECUTE')` = true; `has_function_privilege('anon', …)` = false.
4. Seed present: `select count(*) from venue_anchors where type='overlay'` = 3; per-venue id/kind/modulator-type spot-check (disco gradient-fill/beat, festival solid-fill/beat, honkytonk solid-fill/stochastic).
5. Functional gate (optional, via client): a non-admin overlay upsert raises the admin gate (42501); an admin overlay upsert succeeds (proves CHECK+RPC both admit overlay end-to-end).

**MIGRATIONS_APPLIED.md:** add the db/039 row **only after** Mike applies it manually in Supabase SQL Editor (the prod-apply-before-commit doctrine; Claude Code never applies to prod). The session log must not claim db/039 shipped until the table row exists.

---

## §8 — Verification plan

The §7-of-Direction standard: **each translated venue renders visually identically to its procedural ancestor.** Admin live preview is the iteration loop; manual visual comparison is the PASS criterion.

### 8.1 Per-venue visual parity (the core gate)
For each of disco / festival / honkytonk: load the venue's overlay anchor in the admin preview, Play, and compare against the procedural ancestor (the live `AMBIENT_PROFILES` effect in `karaoke/stage.html` on the same venue — open both). Confirm:
- **disco:** bottom-40% pink→purple gradient flash on **every beat** (120 BPM, half-beat offset), attack snappy (~50ms) / decay slow (~400ms), peak alpha ~0.18.
- **festival:** full-screen white strobe on **every 4th beat** (downbeat, 128 BPM), attack ~40ms / decay ~200ms, peak ~0.25 — and that it does NOT fire on the off-downbeats.
- **honkytonk:** full-screen amber tint, always faintly present, **random flicker** between the two held states. Stochastic ⇒ not pixel-identical to the ancestor; verify the **behavior/statistics** instead (§8.2).

### 8.2 Dual-modulator behavior confirmation (the thing three-venue scope bought)
- **beat class:** disco's every-beat cadence and festival's every-4th-beat cadence are correct at their respective BPMs (count pulses against a metronome / frame timing). Phase offsets correct (disco ½-beat; festival first pulse on beat 4).
- **stochastic class:** honkytonk — cooldown ≥ 180 frames observed between state changes; ~30% of changes select the low state (0.3); the two actual alphas are {0.012, 0.04}; initial alpha 0.04. (Behavioral, not pixel.)

### 8.3 Mechanics
- **Round-trip:** author → Save (RPC upsert succeeds) → reload panel → values persisted → re-Play renders identically.
- **Renderer registration:** `overlay.js` registered on `window.elsewhere.anchorRegistry` under `overlay` (console check); script tags present in BOTH `admin-venues.html` and `karaoke/stage.html`.
- **D8 dormancy:** karaoke read-path unchanged — all three effects still render via `AMBIENT_PROFILES`/procedural closures; the seeded anchors are dormant (load a venue in real karaoke, confirm no behavior change).
- **RPC authority gate:** overlay upsert is admin-only (non-admin → 42501).
- **Panel standardization (correct-by-construction):** overlay panel uses `.anchor-row-actions`, per-row Stop, hide/show kind-switch, themed buttons, `data-status`. (Does NOT re-verify the other panels — that's the unification pass, §6.3.)

---

## §9 — DEFERRED enumeration

**Closes in 4.5:**
- The `overlay`-type scheduling gap — A3 spec §0.3's named-but-unscheduled "future callout/overlay type": the **overlay** half lands (the **callout** half stays Stage 5).
- disco floor-flash + festival strobe translation (Direction §7 named targets).
- honkytonk neon-tint translation — removes an implicit **Stage-7 blocker** (`AMBIENT_PROFILES` can't be deleted with an un-translated honkytonk effect).

**Stays / new (file at closeout):**
- **NEW — honkytonk stochastic time-normalization** (D-framerate). 4.5 preserves frame-counting for ancestor parity; convert `cooldown_frames` → wall-clock if Stage 7's read-path / low-fps devices show visible cadence drift. Trigger: Stage 7 adoption or observed drift. Priority: low.
- **NEW — gradient generality.** Only `direction:"vertical"`, 2-stop, linear is exercised. Radial / arbitrary-direction / N-stop generalization deferred until a venue needs it. Priority: low.
- **NEW — polygon overlay regions.** Direction §7 named "gradient/rectangle/polygon"; no effect uses polygon. Region is rect-only in 4.5. Deferred until needed. Priority: low.
- **CARRY — panel-standardization unification pass** (existing 5017 / 5061 / 5100, §6.3). NOT 4.5's to close; overlay builds correct-by-construction. Residuals (audio per-row Stop; button theming; Stop-all placement; kind-switch hide/show confirmation) stay for the unification pass (Stage 6 candidate per the A4b verification doc). 4.5 closeout: note their stale-`Deferred` status so the next reader isn't misled.
- **CARRY — `spotlight-3d`/`particle-3d` registry-key extension** (5228). Untouched by 4.5 (registry-key-only, not DB types). 4.5 adds exactly one DB type (`overlay`).
- **STRUCTURAL — Stage 7 read-path switch.** Overlay anchors ship DORMANT; karaoke reads `AMBIENT_PROFILES` until Stage 7 (D8). Stage 7's switch is the first prod exercise of the data-driven overlay path; visual-identity verification there is the final gate (Direction §7).
- **NOTE — overlay adds ZERO to A7's driver registry** (D-self-contained). Unlike particle (`crowd_brightness`) / spotlight, overlay's modulators self-drive. Record in the closeout that overlay is the one anchor type so far that does not feed Stage 7's modulator/driver inventory.

---

## §10 — Process reminders for Claude Code

- **PAUSE after this spec is reviewed.** No code, no file edits, no commits until Mike approves the spec. Propose-pause per gate thereafter.
- Verify every call shape against REAL source: `rpc_venue_anchor_upsert` = 3-arg `(p_id, p_venue_id, p_partial)`; `window.elsewhere.anchorRegistry`; `.anchor-row-actions` / `.anchor-status`; A4a's pure-JS ease names verbatim. This is DEFERRED-d — do not interpret prose.
- **db/039 is a vocab-extension migration, not seed-only.** It MUST touch the CHECK constraint AND `v_known_types`, in one file. A seed-only file (the 036/037 shape) leaves the RPC rejecting overlay upserts. Single most important correctness point.
- User applies prod migrations manually (Supabase SQL Editor). MIGRATIONS_APPLIED.md updated only after apply. The session log must not claim db/039 shipped until applied.
- No Co-Authored-By trailer. Subject-only commits unless told otherwise.
- Build order (suggested; spec-author may refine): (1) db/039 → apply to prod → verify → commit; (2) `overlay.js` renderer (incl. `power1.out` ease); (3) registry + script tags (both locations); (4) overlay authoring panel (correct-by-construction standardized); (5) preview wiring; (6) verification (§8); (7) closeout (DEFERRED §9 + the stale-status note + version stamps).
- iOS sync at session close per the ritual if `overlay.js` + `admin-venues.html` + the stage.html tag ship (web-bundle change) — though the dormant data path means no karaoke behavior change; treat per the end-of-session ritual.
- The 3 pre-existing untracked files stay untracked.
```
