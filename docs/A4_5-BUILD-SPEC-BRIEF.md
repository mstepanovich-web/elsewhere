# Stage 4.5 (Overlay) Build-Spec Brief

**Purpose:** This is the brief Claude Code uses to author `docs/VENUE-ADMIN-UI-A4.5-BUILD-SPEC.md`. It is NOT the spec itself — it is the locked decision set + structure + the verbatim-source anchors the spec must honor. Claude Code writes the full spec from this, then pauses for review before any code.

**Stage:** Phase 3 / Plan B — Venue Admin UI **Stage 4.5** (the `overlay` anchor type: screen-space visual overlays — disco floor-flash + festival strobe + honkytonk neon-tint translated; new `overlay.js` 2D-canvas renderer; overlay authoring panel; db/039 vocab-extension + seed). A standalone stage in the Direction §7 pipeline, sibling to Stage 4 (A4a/A4b), NOT a sub-stage of it.

**Baseline commit:** `1fc2552` (A4b closeout — the "6 DEFERRED entries" commit). Clean tree (3 pre-existing untracked files stay untracked).

**Discipline carried from A4a/A4b (DEFERRED-d):** Specify by exact line reference, exact constant, exact RPC signature, exact DOM selector. Map real code, not prose. The foundation pass already pulled the three verbatim source blocks (§2 below) — the spec maps each procedural constant to a payload field, it does not re-describe in prose.

**File-naming note:** This brief is `A4_5-BUILD-SPEC-BRIEF.md` (underscore, not bare dot) to parallel `A4B-BUILD-SPEC-BRIEF.md` while avoiding the chat-autolink `.5` artifact. The eventual full spec is `VENUE-ADMIN-UI-A4.5-BUILD-SPEC.md`. The Direction doc §7 calls the stage "Stage 4.5"; db/037's seed note calls it "Stage A4.5" — same stage. The user may rename either file at review; flag if a different convention is wanted.

---

## §0 — Locked decisions (do not re-litigate in the spec)

| # | Decision | Resolution |
|---|----------|-----------|
| **D-scope** | venue coverage | **Three-venue.** disco floor-flash + festival strobe + honkytonk neon-tint. Rationale (for the record): honkytonk's neon must be translated before Stage 7 can delete `AMBIENT_PROFILES` regardless — it's when-not-whether. Doing it in 4.5 designs the overlay modulator contract ONCE (covering beat-sync AND stochastic-flicker classes) instead of shipping beat-only and reopening the contract later. The added surface is bounded and fully characterized by the §2 source read. |
| **D-type** | new anchor type | **New `overlay` anchor type.** Follows the established **"type-in-DB, kind-in-payload"** pattern (the A4b carry-forward note): per-effect variation is a `payload.kind` field, NOT separate DB types. Screen-space — both `yaw_deg` and `pitch_deg` NULL (like every 2D-canvas anchor: audio/particle/spotlight-2D), satisfying db/032's `venue_anchors_position_consistency` CHECK. |
| **D-kinds** | kind vocabulary | **TWO kinds: `solid-fill` and `gradient-fill`.** Kind discriminates the **paint shape only** (solid color vs. linear-gradient-with-stops). Festival strobe + honkytonk neon **share `solid-fill`**, differing only in their `modulator` sub-object. Disco floor-flash is `gradient-fill`. Argument in §3.1 — this is argued from payload-contract cleanliness, not asserted. |
| **D-modulator** | the load-bearing contract | **ONE modulator contract, discriminated by `modulator.type` ∈ {`beat`, `stochastic`}.** The modulator answers WHEN-and-to-WHAT-TARGET; it is orthogonal to kind/region/fill and to the envelope. Both classes expressible from day one. Full shape in §3.2. This is the design that justified three-venue scope — §3.2 is the section that must be gotten right. |
| **D-envelope** | alpha trajectory per event | **Discriminated by `envelope.shape` ∈ {`pulse`, `hold`}** (reserve `static` for a future constant overlay). `pulse` = attack→peak→decay (disco, festival). `hold` = instant set, value persists until next event (honkytonk — no envelope). Ease is a value that supports **explicit-ease** (disco `power3.out`/`power2.in`), **default-ease** (festival — GSAP default `power1.out`, represented by the sentinel `"default"`), and **none/instant** (honkytonk `hold` carries no ease). Full shape in §3.3. |
| **D-region** | overlay extent | **Normalized bounds `region: {x, y, w, h}` in 0–1**, full-canvas `{0,0,1,1}` as the default/degenerate case. Disco = `{0, 0.6, 1, 0.4}` (bottom 40%). Festival + honkytonk = full-canvas. Polygon regions (named in Direction §7) are OUT of 4.5 — no effect uses them; deferred. |
| **D-fill** | paint discriminator | **Discriminated shape, keyed by `kind`.** `solid-fill` → `{ color: "r,g,b" }` (alpha supplied entirely by modulator×envelope — the RGB fragment carries no alpha). `gradient-fill` → `{ direction, stops: [{pos, color, alpha_scale}, …] }`, gradient axis spanning the region. Disco = vertical 2-stop pink→purple. Radial/arbitrary-direction gradients deferred (only vertical is exercised). |
| **D-migration** | db/039, two-place change | **Extend db/032 `venue_anchors_type_check` by EXACTLY ONE value (`'overlay'`) via DROP+CREATE** per the constraint's own documented doctrine (db/032:248-253). **CRITICAL second place: also extend `v_known_types` in db/035's `rpc_venue_anchor_upsert`** (db/035:93-94) — the RPC mirrors the CHECK vocabulary and will reject overlay upserts (errcode 22023) if not updated. **Both places, one migration (db/039).** Do NOT touch `spotlight-3d`/`particle-3d` — those are registry-key-only per A4b's design (confirmed in the foundation pass; they are NOT DB types and never enter the CHECK). |
| **D-renderer** | new module, 2D context | **New `shell/venue-renderers/overlay.js`** (sibling pattern). **2D-canvas, NOT WebGL** — these are `c.fillRect` / `c.createLinearGradient` 2D-canvas fills. This is the **A3/A4a 2D-canvas preview path**, NOT the A4b Three.js path. The admin preview reuses the existing bounded 2D-canvas preview infra (Play/Replay/Stop) — **no new WebGL surface, no Three.js**. Renderer contract = **`{ stop }` (2D self-RAF)**, matching A3/A4a 2D modules (per A4b D-contract: 2D = renderer-owns-RAF). |
| **D-self-contained** | modulators need no external scalars | **Overlay modulators are fully self-contained** — the beat clock derives from `payload.bpm`; the stochastic flicker runs its own RNG + frame counter. Neither depends on an external venue scalar (unlike particle's `crowd_brightness`). Consequence: overlay's renderer needs **no preview-oscillator heuristic**, and overlay adds **ZERO names to A7's driver-registry inventory**. Note this as a property in the spec — overlay is more self-sufficient than particle/spotlight. |
| **D-panel** | authoring panel | **Single-anchor-per-venue** (each of the 3 venues has exactly ONE overlay anchor). Inherits the **post-A4b standardized panel pattern** (`.anchor-row-actions`, per-row Stop, hide/show kind-switch — NOT re-render). PREVENT-style: `+ Add overlay anchor` hidden when count ≥ 1 (matches A2/A3; A4b's multi-anchor anchor-list was driven by speakeasy's 2 spotlight anchors — overlay has no such case). Built **correct-by-construction** to the standard; see §3.5 FLAG re: panel-polish DEFERREDs. |
| **D-dormancy** | D8 posture continues | **AMBIENT_PROFILES-first.** The 3 seeded overlay anchors are **dormant data**; `karaoke/stage.html` keeps reading `AMBIENT_PROFILES` until Stage 7 promotes anchors to load-bearing. 4.5 ships the data + renderer + panel; the read-path switch is Stage 7. One registration-only `<script>` tag for `overlay.js` in `karaoke/stage.html` (no version bump per the A2/A3/A4a registration-only precedent) + the real consumer tag in `admin-venues.html`. |

---

## §1 — The three anchors (db/039 seed)

| Anchor id | type | payload.kind | modulator.type | envelope.shape | region | notes |
|-----------|------|--------------|----------------|----------------|--------|-------|
| `anc_ovl_disco_floorflash` | overlay | `gradient-fill` | `beat` | `pulse` | `{0, 0.6, 1, 0.4}` | bottom-40% vertical pink→purple gradient, every beat, +½-beat phase |
| `anc_ovl_festival_strobe` | overlay | `solid-fill` | `beat` | `pulse` | `{0,0,1,1}` | full-canvas white, every 4th beat (downbeat), default-ease |
| `anc_ovl_honkytonk_neon` | overlay | `solid-fill` | `stochastic` | `hold` | `{0,0,1,1}` | full-canvas amber tint, random flicker between two held states |

- **Id convention:** `anc_ovl_<venue>_<effect>` — `ovl` is the 3-letter type abbrev (parallels `aud`/`par`/`spot`) + descriptive effect suffix (parallels A4b's `anc_spot_stadium_beams3d`). *The user's prompt named these `anc_overlay_<...>`; recommend `anc_ovl_` for abbrev consistency with audio/particle/spotlight seeds — flag for confirmation at review.*
- `label` for all three: `'Overlay'` (parallels `'Ambient'`/`'Particles'`/`'Spotlights'`).
- All three: `yaw_deg = NULL`, `pitch_deg = NULL` (screen-space, D-type).
- Seed via `INSERT … ON CONFLICT (id) DO NOTHING` (the db/035–037 idempotent pattern).
- Spec must derive each payload's full field set by quoting the §2 verbatim source and mapping every procedural constant to a payload key — the payload-vs-source fidelity table (§4 item 3). 6-decimal precision where a value is non-terminating (note: `60000/128 = 468.75` is exact; the three effects contain no irrationals — but the precision rule stands for any derived ms value the spec chooses to store).

---

## §2 — Verbatim source anchors (the spec MUST quote these by line)

All at `karaoke/stage.html` @ `1fc2552`. Each venue's `anim()` also contains effects already claimed by earlier stages (disco mirror-ball = db/036 particle; festival lasers = db/037 spotlight, festival confetti = db/036 particle). **Only the overlay-class fragment is in 4.5 scope** — isolated below.

### 2a. Disco floor-flash — `karaoke/stage.html:4700-4721` (inside `disco.anim()`)

```javascript
// beat clock (shared with mirror-ball, line 4676): BPM = 120, BEAT = 60000/120 = 500ms

// Floor flash on beat
const flashState = { alpha: 0 };
function flashBeat(){
  if(currentAmbientVenue !== 'disco') return;
  gsap.to(flashState, {
    alpha: 0.18, duration: 0.05, ease: 'power3.out',
    onComplete: ()=> gsap.to(flashState, { alpha: 0, duration: 0.4, ease: 'power2.in' })
  });
  setTimeout(flashBeat, BEAT);
}
setTimeout(flashBeat, BEAT * 0.5); // offset by half beat
// …draw (4715-4721):
if(flashState.alpha > 0){
  const fg = c.createLinearGradient(0, ambientH*0.6, 0, ambientH);
  fg.addColorStop(0, `rgba(255,180,255,${flashState.alpha})`);
  fg.addColorStop(1, `rgba(120,80,255,${flashState.alpha*0.5})`);
  c.fillStyle = fg; c.fillRect(0, ambientH*0.6, ambientW, ambientH*0.4);
}
```
**Constants → fields:** BPM 120; first trigger `BEAT*0.5` then every `BEAT`; peak_alpha 0.18; attack 0.05s `power3.out`; decay to 0 over 0.4s `power2.in`; rest_alpha 0; region `{0, 0.6, 1, 0.4}`; gradient vertical (region top→bottom), stop@0 `(255,180,255)` alpha_scale 1.0, stop@1 `(120,80,255)` alpha_scale 0.5.

### 2b. Festival strobe — `karaoke/stage.html:4873-4893` (inside `festival.anim()`)

```javascript
// beat clock (shared with lasers, line 4851): BPM = 128, BEAT = 60000/128 = 468.75ms

// Strobe flash on every 4th beat (downbeat)
const strobe = { alpha: 0 };
let beatCount = 0;
function strobePulse(){
  if(currentAmbientVenue !== 'festival') return;
  beatCount++;
  if(beatCount % 4 === 0){
    gsap.to(strobe, {
      alpha: 0.25, duration: 0.04,
      onComplete:()=> gsap.to(strobe, { alpha: 0, duration: 0.2 })
    });
  }
  setTimeout(strobePulse, BEAT);
}
setTimeout(strobePulse, BEAT);
// …draw (4892-4893):
if(strobe.alpha>0){ c.fillStyle=`rgba(255,255,255,${strobe.alpha})`; c.fillRect(0,0,ambientW,ambientH); }
```
**Constants → fields:** BPM 128 (BEAT 468.75ms); schedule ticks every beat from `t=BEAT`, fires when `beatCount % 4 === 0` → first fire at beat 4, then every 4th (interval_beats 4, first_trigger_beats 4); peak_alpha 0.25; attack 0.04s **no ease → GSAP default `power1.out`** (the sentinel `"default"`); decay to 0 over 0.2s **default ease**; rest_alpha 0; region full; solid color `(255,255,255)`.

### 2c. Honkytonk neon-tint — `karaoke/stage.html:4837-4842` (inside `honkytonk.anim()`)

```javascript
// Neon sign flicker only — removed amber dust particles
let neonAlpha=1, neonTimer=0;
spawnParticles({ count:1, spawn(){ return {
  update(){ neonTimer++; if(neonTimer>180&&Math.random()<0.02){ neonAlpha=Math.random()<0.3?0.3:1; neonTimer=0; } },
  draw(c){ c.fillStyle=`rgba(255,100,50,${neonAlpha*0.04})`; c.fillRect(0,0,ambientW,ambientH); },
  _eternal:true, alive(){ return true; }
}; } });
```
**Constants → fields:** stochastic — `cooldown_frames` 180 (`neonTimer>180`), `change_probability` 0.02 (`Math.random()<0.02`), `low_state_probability` 0.3 (`Math.random()<0.3`), `states` `[0.3, 1.0]` (the two `neonAlpha` values), `initial_state` 1.0 (`neonAlpha=1`); `alpha_scale` 0.04 (`neonAlpha*0.04` → actual alpha ∈ {0.012, 0.04}); envelope `hold` (instant swap, value persists); region full; solid color `(255,100,50)`. **Fidelity caveat: frame-rate-dependent** (per-frame trial, cooldown counted in frames) — the renderer reproduces it frame-for-frame; preserved deliberately (see DEFERRED §4 item 9).

---

## §3 — The overlay payload contract (the load-bearing design)

> This is Stage 4.5's equivalent of A4b's §3 panel-pattern section — the part the spec must get exactly right. The contract is **four orthogonal axes** that compose: **kind** (paint shape) × **region** (where) × **fill** (what color) × **modulator** (when + target) × **envelope** (how alpha moves per event). The whole point of three-venue scope is that all three effects fall out of one composition.

### 3.1 D-kinds — why two kinds, festival+honkytonk shared (argued)

The naive split is "one kind per effect" or "kind names region+fill together" (e.g. the prompt's tentative `gradient-rect` / `solid-fullscreen`). Both are wrong for contract cleanliness:

- **Region is orthogonal (D-region):** a normalized-bounds field. Baking "rect"/"fullscreen" into the kind name conflicts with region being a free `{x,y,w,h}` — a solid fill can occupy a sub-rect, a gradient can be full-canvas. The names would lie.
- **Modulator is orthogonal (D-modulator):** if kind discriminated the modulator too, we'd get combinatorial kind names (`solid-fullscreen-beat`, `solid-fullscreen-stochastic`, …) and the modulator contract — the thing that justified three-venue scope — would smear across kind strings instead of living in one clean sub-object.

So **`kind` discriminates ONLY the paint shape** the renderer's draw branch needs: solid color vs. linear-gradient-with-stops. That yields exactly two kinds. **Festival and honkytonk share `solid-fill`** and differ purely in their `modulator` (beat-divisor vs. stochastic) — which is the cleanest possible proof that the modulator axis is carrying the variation, not the kind axis. Disco is the only `gradient-fill`. The renderer dispatches on `kind` for *painting* and on `modulator.type` for *timing* — two independent, single-responsibility dispatches.

### 3.2 D-modulator — ONE contract, two classes (the crux)

The modulator emits a sequence of **events** over time; each event carries a **target alpha**. It is the WHEN + WHAT-TARGET axis. Discriminated by `modulator.type`:

```
modulator (type: "beat"):
  bpm                 number     // 120 (disco), 128 (festival)
  first_trigger_beats number     // 0.5 (disco), 4 (festival) — beats from t0 to first event
  interval_beats      number     // 1 (disco, every beat), 4 (festival, every 4th)
  target_alpha        number     // 0.18 (disco), 0.25 (festival) — constant peak per event
  // event times = { (first_trigger_beats + k*interval_beats) * (60000/bpm) ms : k = 0,1,2,… }
  // chosen over phase_offset+divisor because it maps 1:1 to the source's
  //   setTimeout(BEAT*offset) … setTimeout(BEAT*interval) structure — exactly faithful,
  //   incl. festival's "first downbeat at beat 4" (no spurious t=0 pulse).

modulator (type: "stochastic"):
  cooldown_frames        number  // 180 — min frames between possible state changes
  change_probability     number  // 0.02 — per-frame P(change) once cooldown elapsed
  states                 [number,number]  // [0.3, 1.0] — the two normalized state multipliers
  low_state_probability  number  // 0.3 — P(states[0]) when a change fires; else states[1]
  initial_state          number  // 1.0
  alpha_scale            number  // 0.04 — actual target = chosen_state * alpha_scale
  // each frame: cooldown++; if cooldown ≥ cooldown_frames AND rand() < change_probability:
  //   target = (rand() < low_state_probability ? states[0] : states[1]) * alpha_scale; cooldown = 0
```

**The unification:** both types produce `(event_time, target_alpha)` pairs. `beat` produces them on a deterministic clock with a constant target; `stochastic` produces them on an RNG-gated frame counter with a weighted-random target. The renderer's modulator stage is identical downstream — it hands the target to the envelope. (For `beat`, `target_alpha` is a literal field; for `stochastic`, the target is computed from `states`/`alpha_scale` — the spec must state that `stochastic` carries its targets in `states`, not in a `target_alpha` scalar.)

### 3.3 D-envelope — HOW alpha moves per event

The envelope shapes actual alpha relative to an event's target. Discriminated by `envelope.shape`:

```
envelope (shape: "pulse"):     // disco, festival
  attack: { duration_sec, ease }   // rise rest_alpha → target_alpha
  decay:  { duration_sec, ease }   // fall target_alpha → rest_alpha
  rest_alpha   number              // 0 for both (overlay invisible between pulses)
  // ease ∈ { explicit GSAP-equivalent name | "default" }
  //   disco:    attack 0.05s "power3.out",  decay 0.4s "power2.in"
  //   festival: attack 0.04s "default",     decay 0.2s "default"   ("default" → power1.out)

envelope (shape: "hold"):      // honkytonk
  // no attack/decay, no ease. On each event, alpha jumps instantly to target and
  // persists until the next event. (initial alpha = initial_state * alpha_scale.)

// reserve (not in 4.5): shape "static" for a future constant (non-modulated) overlay.
```

**Ease representability (the D-envelope requirement):** the `ease` value covers all three cases — **explicit** (`"power3.out"`, `"power2.in"`), **default** (`"default"`, which the renderer resolves to GSAP's default `power1.out`), and **none/instant** (the `hold` shape simply has no ease). The renderer's pure-JS ease table already has `power3.out` + `power2.in` from A4a; it must **add `power1.out`** (A4a shipped `power1.inOut`, not `power1.out`) to resolve `"default"`. Note this one-function addition in the spec.

### 3.4 D-region + D-fill

```
region: { x, y, w, h }   // normalized 0–1; default {0,0,1,1}. Renderer maps to
                         //   c.fillRect(x*W, y*H, w*W, h*H). disco {0,0.6,1,0.4}.

fill (kind "solid-fill"):    { color: "r,g,b" }   // RGB only; alpha from modulator×envelope
fill (kind "gradient-fill"): { direction: "vertical",   // only vertical exercised (4.5)
                               stops: [ { pos, color: "r,g,b", alpha_scale }, … ] }
  // gradient axis spans the region's extent along `direction`. Renderer builds
  //   createLinearGradient over the region's vertical extent; each stop's effective
  //   alpha = current_envelope_alpha * stop.alpha_scale.
  //   disco: stops [ {pos:0, "255,180,255", alpha_scale:1.0}, {pos:1, "120,80,255", alpha_scale:0.5} ]
```

### 3.5 Panel — inherits the standardized pattern; DEFERRED-flag

Overlay's authoring panel is the **fourth** anchor panel. It must be born conforming to the **post-A4b standardized pattern** (`.anchor-row-actions` container, per-row `⏹ Stop`, `▶ Play preview` / `↻ Replay` tokens, `data-status`, hide/show on kind-switch — not re-render). Per-kind form: `kind` selector swaps `solid-fill` ⇄ `gradient-fill` sections; `modulator.type` selector swaps `beat` ⇄ `stochastic` sections; `envelope.shape` selector swaps `pulse` ⇄ `hold` sections. Single-anchor-per-venue (D-panel): `+ Add` hidden at count ≥ 1.

**FLAG (panel-polish DEFERREDs):** the foundation pass noted three earlier-filed DEFERREDs living in this panel code path — `kind-switch re-renders / A3 uses hide-show` (DEFERRED.md:5017), `button styling + Stop-all placement` (5061), `missing per-row Stop` (5100). **A4b's D-standardize was scoped to close exactly these against the audio/particle/spotlight panels.** 4.5 does **not** re-open them — overlay's panel is built correct-by-construction to the standard. The spec's foundation pass should **verify A4b's closeout status** of 5017/5061/5100: if A4b confirmed them closed, overlay simply inherits; if any is still open against the *other* panels, that residual stays with the admin-UI-polish pass — overlay does not inherit broken behavior regardless. Do not let 4.5 absorb the other panels' historical debt.

---

## §4 — Required spec sections (mirror A4a/A4b spec structure)

1. **§0 Foundation recap** — the §0 locked-decision table + the §1 three-anchor table.
2. **§1 Kind vocabulary** — the two kinds (`solid-fill`, `gradient-fill`), each `type:"overlay"`. Map each to its source effect. State the festival+honkytonk shared-kind decision (§3.1) explicitly.
3. **§2 Payload schema + fidelity table** — the full four-axis contract (§3.2–3.4). **Payload-vs-source fidelity table:** one row per procedural constant (every alpha, duration, ease, BPM, beat-divisor, the honkytonk 180-frame cooldown / 0.02 probability / 0.3 low-state / [0.3,1.0] states / 0.04 scale) → its payload field. 6-decimal precision where a stored value is non-terminating.
4. **§3 Renderer design** — `overlay.js`, 2D-canvas, `{ stop }` self-RAF (D-renderer). The two-axis dispatch (kind→paint, modulator.type→timing). The beat scheduler + pulse-envelope with pure-JS eases (reuse A4a's `power3.out`/`power2.in`; **add `power1.out` for `"default"`**). The stochastic per-frame trial (frame counter + RNG, faithful to source). The `hold` envelope. State that overlay needs **no preview oscillator** (D-self-contained) — modulators self-drive.
5. **§4 Registry + script tags** — register `overlay.js` against anchor `type:"overlay"` (single-context `2d-canvas`; no `payload.context` branch needed — overlay is 2D-only). Script tag added to BOTH `admin-venues.html` (consumer) AND `karaoke/stage.html` (registration-only, no version bump — A2/A3/A4a precedent). Enumerate both locations (the A4a Check-21 lesson).
6. **§5 Overlay authoring panel** (D-panel + §3.5) — per-kind / per-modulator / per-envelope form sections; single-anchor PREVENT; standardized `.anchor-row-actions` + per-row Stop + hide/show kind-switch. Bounded 2D-canvas preview (reuse A3/A4a infra — **no WebGL**). `state.overlayAnchorDirty` Set + `beforeunload`/`venueHasAnyDirty`/`discardAllForVenue` extension (the A3/A4a dirty-tracking pattern). Version stamp bump on `admin-venues.html` (next in its sequence).
7. **§6 db/039 migration** — THREE sections, one transactional file (mirrors db/035's structure): **(1)** `ALTER TABLE … DROP CONSTRAINT venue_anchors_type_check; ADD CONSTRAINT … CHECK (type IN (… 8 values incl 'overlay'))`; **(2)** `CREATE OR REPLACE FUNCTION rpc_venue_anchor_upsert` with `'overlay'` added to `v_known_types` — **the spec must reproduce the FULL current function body** (verify db/035 is still the canonical definition — no migration after 035 redefined it; the foundation pass confirmed 036/037/038 are seed-only and 034 is `venue_default_update`) and re-state the REVOKE-FROM-PUBLIC + REVOKE-FROM-anon + GRANT-TO-authenticated grant block (CREATE OR REPLACE preserves grants, but re-state per the db/035 Bug-2 doctrine — belt-and-suspenders); **(3)** seed the 3 overlay anchors `INSERT … ON CONFLICT DO NOTHING`. Footer verification queries: CHECK vocabulary now includes `overlay`; RPC `v_known_types` includes `overlay` (functional test: a non-admin overlay upsert fails on the admin gate, an admin overlay upsert succeeds); 3 overlay rows present with correct kind/modulator-type per row. **MIGRATIONS_APPLIED.md entry** + the prod-apply-before-commit doctrine (user applies manually in Supabase SQL Editor; Claude Code never applies to prod).
8. **§7 Verification plan** — each of the 3 venues renders **visually identically** to its procedural ancestor (the §7 standard; admin live preview is the iteration loop). **Dual-modulator behaviors explicitly confirmed:** beat-sync — disco's every-beat ½-beat-offset cadence + festival's every-4th-beat downbeat cadence at the correct BPMs; stochastic — honkytonk's flicker *statistics* (can't be pixel-identical: RNG) — verify cooldown ≥ 180 frames between changes, ~30% low-state selection, two actual-alpha states {0.012, 0.04}, initial 0.04. Round-trip (author → save → reload → re-render). D8 dormancy (karaoke read-path unchanged — all 3 effects still procedural via AMBIENT_PROFILES). RPC authority gate (overlay upsert is admin-only).
9. **§8 DEFERRED enumeration** — what 4.5 closes vs. what stays (§5 of this brief).

---

## §5 — DEFERRED enumeration (what closes, what stays)

**Closes in 4.5:**
- The `overlay`-type scheduling gap — A3 spec §0.3's "future callout/overlay type" was named-but-unscheduled; the **overlay** half lands here (the **callout** half stays Stage 5).
- disco floor-flash + festival strobe translation (Direction §7 named targets).
- honkytonk neon-tint translation — was an implicit **Stage-7 blocker** (AMBIENT_PROFILES can't be deleted with an un-translated honkytonk effect); now unblocked.

**Stays (carry forward / new):**
- **callout / pin / video / link-hotspot** types → Stage 5 (unchanged).
- **Stage 7 read-path switch** — overlay anchors ship DORMANT; karaoke keeps reading AMBIENT_PROFILES (D-dormancy / D8). The visual-identity verification at Stage 7's switch is the first prod exercise of the data-driven overlay path.
- **honkytonk stochastic frame-rate dependence** (new DEFERRED) — the source counts cooldown in frames (≈60fps assumption); the renderer reproduces it frame-for-frame. If Stage 7's read-path or a low-fps device makes the cadence visibly drift, convert `cooldown_frames` → a time basis then. Tracked, deliberate, not fixed in 4.5.
- **gradient generality** (new DEFERRED) — only `direction:"vertical"`, 2-stop, linear is exercised. Radial / arbitrary-direction / N-stop generalization deferred until a venue needs it.
- **polygon overlays** (new DEFERRED) — Direction §7 named "gradient/rectangle/polygon"; no effect uses polygon. Region is rect-only in 4.5; polygon deferred until needed.
- **panel-polish historical DEFERREDs** (5017 / 5061 / 5100) — NOT 4.5's to close; A4b's D-standardize covered them against the other three panels. Overlay builds correct-by-construction (§3.5). Any residual stays with the admin-UI-polish pass.
- **`spotlight-3d` / `particle-3d` registry-key extension** (DEFERRED.md:5228) — explicitly **untouched** by 4.5 (registry-key-only, not DB types; confirmed). 4.5 adds exactly one DB type (`overlay`).
- **venue modulator system (Stage 7)** — overlay adds **nothing** to A7's driver inventory (D-self-contained); its modulators self-drive. Note in the closeout that overlay is the one anchor type that does not feed A7's driver registry.

---

## §6 — Process reminders for Claude Code

- Propose-pause per gate. No file edits / commits during spec-authoring. **PAUSE after delivering the full spec** — planning chat reviews before any code.
- Verify every call shape against the REAL RPC signature (`rpc_venue_anchor_upsert` = 3-arg `p_id, p_venue_id, p_partial`) and every DOM class against the REAL selector (`.anchor-row-actions`, `.anchor-status`). This is DEFERRED-d; do not regress to prose.
- **db/039 is a vocab-extension migration, not seed-only** — it MUST touch both the CHECK constraint AND `v_known_types`. A seed-only file (the 036/037 shape) would leave the RPC rejecting overlay upserts. This is the single most important correctness point in the migration.
- User applies prod migrations manually (Supabase SQL Editor). Claude Code never applies to prod. MIGRATIONS_APPLIED.md updated only after apply.
- No Co-Authored-By trailer. Subject-only commits unless told otherwise.
- The three pre-existing untracked files stay untracked.
- iOS sync at session close only if user-facing web bundle changed (overlay.js + admin-venues.html + stage.html tag qualify — but the dormant data path means no karaoke behavior change; treat per the end-of-session ritual).
```
