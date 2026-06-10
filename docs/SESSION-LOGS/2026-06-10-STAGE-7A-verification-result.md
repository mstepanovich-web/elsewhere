# Venue Admin UI Stage 7a — Verification Result Log

**Spec:** `docs/VENUE-ADMIN-UI-STAGE-7A-BUILD-SPEC.md` (foundation brief at `docs/STAGE-7A-BUILD-SPEC-BRIEF.md`)

**Workstream:** Phase 3 / Plan B — **Stage 7a**, the *prerequisites* sub-stage of Stage 7 (the karaoke read-path switch). Stage 7 is sub-staged **7a → 7b → 7c → 7d** because the mapping pass found prerequisite BUILD work hidden inside it (a modulator system + 5 missing audio anchors), a live-read-path rewire with two dispatch systems + two renderer contracts, and an irreversible final deletion. 7a is the buildable, dormant, unit-verifiable, **irreversible-free** piece — pulled out front so the high-risk 7b/7c/7d operate on a de-risked base. 7a delivers: the venue modulator system (3 drivers reproduced pure-JS from verbatim source) + a db/040 seed of the 5 effect-venue audio anchors. **Both ship DORMANT; zero live karaoke behavior change.**

**Commits in this stage (chronological on `main`):**
- `524fc40` — `docs(venue-admin): file iOS Capacitor resync deferral (Stage 4.5 closeout tail)` (pre-7a tail, carried in this push)
- `<foundation>` — `feat(venue-admin): Stage 7a foundation — db/040 effect-venue audio seed (applied) + venue modulator system + spec + brief` (db/040 + venue-modulators.js + spec + brief + MIGRATIONS_APPLIED row)
- `<closeout>` — `docs(venue-admin): Stage 7a closeout — verification log` (this commit)

**Prod-apply state:**
- db/040 applied via Supabase SQL Editor 2026-06-10. The 5 effect-venue audio anchors (`anc_aud_{stadium,disco,speakeasy,festival,honkytonk}`) are present in `public.venue_anchors`, `sound_id == venue_id`, screen-space (yaw/pitch NULL). All 3 footer verification queries passed on first run.
- **No deploy / no Pages branch-switch needed.** Stage 7a modified no running surface — it shipped two NEW files (`db/040_effect_venue_audio_seed.sql`, `shell/venue-modulators.js`) and nothing else. Verification ran offline (the modulator unit harness via `node` against the real module) + RPC-layer (the db/040 footer queries). The a45-style branch-deploy playbook remains available for any future stage that touches a live surface; 7a did not.
- iOS Capacitor resync remains deferred (the 4.5 tracked entry; D8 dormancy + admin not in the iOS bundle = no iOS-facing change; trigger = next functional iOS-relevant change).

---

## Outcome — 7a fully verified, 0 bugs in code

A clean run. No bugs in the shipped code, no triage commits. Two issues were caught **in spec review before any code** (a clock-leak in the decay handoff + an ease-exponent-consistency confirm) and resolved in the spec — see "Caught in review" below. The implementation then passed verification on first run.

### Cluster 1 — db/040 audio anchors (dormant data)

**C1.1 — Seed count + correctness.** `count(*) where type='audio'` returned **24** (19 audio-only from db/035 + the 5 new effect-venue anchors). The 5 rows each returned `sound_id == venue_id`, `payload_type='mp3'`, `label='Ambient'`. `bad_position = 0` (all screen-space). **PASS** ✓

**C1.2 — `sound_id == venue_id` provenance.** Confirmed verbatim before seeding: each of the 5 closures is `playAmbientMp3('<venue>')` (`:4602/4678/4771/4839/4853`); `playAmbientMp3(venueId)` builds `SOUNDS_BASE + venueId + '.mp3'` with no soundId remap (`:4563`); none of the 5 carry a `soundId` in venues.json. The audio renderer fetches `SOUNDS_BASE + sound_id + '.mp3'` — identical file. No exception (unlike db/035's kids-dino2 / enchantedforest). **PASS** ✓

**C1.3 — Zero live change.** db/040 modified no karaoke file; the 5 anchors are dormant data. The 5 venues still play audio via the procedural `playAmbientMp3` path (nothing reads the anchors until 7b). **PASS** ✓

### Cluster 2 — The venue modulator system (`shell/venue-modulators.js`, unwired infra, unit-checked in isolation)

The §6.2 harness imported the **real module** (copied to `.mjs` so node loads it as a true ES module) and drove it with synthetic `now` values:

**C2.1 — `crowd_brightness` curve-shape per fire (stadium).** All 6 sample points exact: pre-fire `0.600000`; attack t=0 `0.600000`; mid-attack (t=0.5, `power2.out`) `1.300000` (= 0.6 + 0.8·0.875); peak `1.400000`; mid-decay (t=0.5, `power1.in`) `1.200000` (= 1.4 − 0.8·0.25); rest `0.600000`. The `power2.out` attack + `power1.in` decay shapes are byte-exact to the verbatim `cheerSwell`. (Cadence is the non-deterministic 8–16s, so this validates curve-shape-per-fire per spec §3/§6.2.) **PASS** ✓

**C2.2 — Disco LOCKSTEP sentinel (full beat cycle).** `(beat_scale−1)/0.8 === (beat_brightness−1)/0.6` to <1e-12 at **every** sample across attack/peak/decay/rest: `1.700/1.525` mid-attack, `1.800/1.600` peak, both `1.000/1.000` at rest. The two scalars are mathematically incapable of desync — one tween, one `t`, two fields (D-lockstep made concrete). **PASS** ✓

**C2.3 — D-guard.** Unresolved name → returns `1` (identity, deterministic, no crash). **2 calls → 2 warns** (every unresolved call, not throttled). Message **byte-exact** to spec: `[venue-modulators] unresolved driver 'nonexistent_driver' for target 'alpha' — returning identity 1.0`. Live driver present → resolves, **0 warns**. **Cross-venue miss** (disco active, asking stadium's `crowd_brightness`) → `1.0` + 1 warn — confirms **no silent oscillator/cross-venue fallback** (the exact bug class D-injection exists to prevent). **PASS** ✓

**C2.4 — Single-clock handoff.** Offline check confirmed the chained decay tween stamps `start_ms` = the tick `now` that completed the attack (`80` in the test), NOT a `performance.now()` value. The clock-leak fix holds — the whole chain (`tick → advanceTween → on_complete → decay start_ms`) runs off one `now`, restoring tick-driven determinism. **PASS** ✓

**C2.5 — Ease exponent consistency.** Grep across the effect layer: `power2.in` is byte-identical (`t*t*t`) in spotlight.js, overlay.js, AND venue-modulators.js; `power3.out` identical where defined; the two new eases (`power2.out = 1-(1-t)³`, `power1.in = t²`) follow the same per-N convention (power1=quad, power2=cubic, power3=quartic). One definition of each ease name across the whole layer. **PASS** ✓

---

## Caught in review (before code)

Two issues surfaced during spec review and were fixed in the spec before the module was written — no production code ever carried them:

1. **Clock leak in the decay handoff.** The draft `startAttack`'s `on_complete` stamped the decay tween's `start_ms` with `performance.now()` — a second clock, breaking the tick-driven determinism (the whole reason for the caller-ticked model) and, live, starting the decay from wall-clock instead of the render-loop `now` (a small skew — the same "two clocks where there should be one" class the disco lockstep eliminates, reintroduced at the attack→decay handoff). Fix: thread the tick `now` through `advanceTween(state, now) → on_complete(now) → decay start_ms = completedNow`. Bonus: `completedNow` (frame-quantized tick time) also matches GSAP's onComplete-fires-on-frame behavior, so the fix is deterministic AND parity-faithful. Verified by C2.4.

2. **Ease exponent confirm.** Verified exponent-for-exponent that the new module's eases share one definition with the existing modules (C2.5). The whole point of pure-JS — one motion vocabulary — now empirically confirmed, not assumed.

---

## Bugs caught this stage

**None in code.** No triage commits. (The two items above were spec-review catches, pre-code.)

---

## Test artifacts — row inventory

- **db/040 seed (5 rows):** `anc_aud_{stadium,disco,speakeasy,festival,honkytonk}` inserted, dormant, no edits to revert (no round-trip mutation was needed — the count + per-row sound_id + position queries are read-only).
- **Modulator harness:** ran entirely offline against the module file (`node`), no DB writes, no live-surface interaction. Nothing to clean up.
- **Other tables / anchors:** untouched. venue_defaults / karaoke_venue_settings / costumes / the db/035–039 anchors all unchanged.

---

## Conclusion

Stage 7a ships clean. All cluster checks PASS; zero bugs in code; zero triage commits; zero live karaoke behavior change.

7a delivered:

- **`shell/venue-modulators.js`** (new, dormant, unreferenced) — the venue modulator system. Pure-JS (GSAP-free; the renderers + admin preview have no GSAP; one motion vocabulary across the effect layer). Three drivers across two venues, reproduced byte-faithful from verbatim source: `crowd_brightness` (stadium cheer-swell, `:4625-4634`) and `beat_scale` + `beat_brightness` (disco beat-pulse, `:4692-4703`). **Disco is ONE driver emitting two scalars from a single lockstep tween** — they cannot desync (C2.2). **Tick-driven, single-clock** (`tickVenueModulators(now)` advances both schedule and tween off one `now`; the attack→decay handoff threads the same `now`) — deterministic, and in 7b the driver-clock == render-clock. Two new eases added (`power2.out`, `power1.in`), exponent-consistent with the layer (C2.5). The resolver `resolveModulator(name, target)` + the **D-guard** (loud + specific warn on every unresolved call, identity 1.0 return, NO oscillator fallback) are built here so they're unit-testable in isolation; the renderer-side ctx-threading is 7b.
- **`db/040_effect_venue_audio_seed.sql`** (applied prod 2026-06-10) — 5 effect-venue audio anchors, closing the coverage gap that would otherwise have let 7d's deletion silence stadium/disco/speakeasy/festival/honkytonk. Seed-only (audio type already in vocab). Dormant.

Per spec D-additive: **Stage 7a modified NO existing file.** The module ships unreferenced (no `<script>` tag — unlike the renderer dormant-publish, whose tags actually register into the registry; this module has no equivalent registration to justify a tag now). 7b adds the tag with the first consumer. This is the property that let 7a ship without a deploy-verify cycle: there is no running code to regress.

### DEFERRED entries filed at closeout

**None.** Stage 7a generated no new backlog items — it's a clean prerequisite build. The two open items are stage hand-offs (tracked in spec §7), not DEFERRED entries: (a) the `<script>` tag + `computeModulatorTargets` signature change are 7b's first moves; (b) the D-guard's every-call warn is intentional — if 7b/7c finds it floods the console enough to obscure other diagnostics, a once-per-(name,target,venue) throttle is the refinement, but the locked default is every-call.

### Next — Stage 7b (the read-path switch, behind a flag)

7a de-risked the base; 7b is the first stage that touches the live read path — and it stays reversible (flag, nothing deleted). Hand-off from the render-loop + modulator probes:

- **The signature change first:** `computeModulatorTargets(modulator, elapsedMs, resolver)` — thread `resolveModulator` (karaoke passes live drivers; admin keeps oscillators). Behavior-preserving for the admin preview. Then add the `<script>` tag for venue-modulators.js.
- **The read-path switch, behind a flag:** replace `getProfile(venueId).audio()/.anim()` + `addVenueEffects3D(venueId)` with resolver-driven anchor rendering, toggleable so the data path runs A/B alongside the procedural path. Wire `activateVenueDrivers(venueId)` into `startAmbient`, `tickVenueModulators(now)` into the render loop (`:4032`/`:4058`, exactly where `venueEffects3D.update()` lives — driver-clock == render-clock), `deactivateVenueDrivers()` into the venue-change teardown.
- **2D canvas-clear collision (resolution noted now for 7b):** a venue with multiple 2D effects (disco = 2, **festival = 3**: confetti particle + lasers spotlight-2D + strobe overlay) can't share one ambient canvas — each renderer's per-frame full `clearRect` wipes the others. Resolution: **one layered canvas per 2D anchor** (stacked transparent canvases), keeping the proven renderer contract untouched. The alternative (a compositing loop without per-renderer clears) would change the verified renderers — rejected.
- **Two renderer contracts to drive:** 2D `{stop}` (self-RAF, one layered canvas per anchor) replaces `startParticleLoop`/`spawnParticles`; 3D `{update,dispose}` (caller-driven, iterated at `:4032`/`:4058`) replaces `addVenueEffects3D`/`venueEffects3D` — a single→list change.

### Then — 7c (the deletion gate) and 7d (the irreversible deletion)

- **7c:** exhaustive parity verification — all ~33 seeded anchors + 5 audio + modulator behavior, every venue, data-path vs procedural, side-by-side via the flag. **The flag STAYS through 7c** so the entire phase is reversible — this is the safety spine. 7c is the gate: 7d does not proceed until 7c signs off.
- **7d (irreversible, last):** delete `AMBIENT_PROFILES` + `addVenueEffects3D` + the **4 dead keys** (space/forest/underwater — true ghosts with no venue in venues.json; + **dead-dragonlair** — the multi-line synth-drip entry at `:4943` shadowed by the live compact `playAmbientMp3('dragonlair')` entry at `:4995`, JS keeping the last → the first is dead code; the dragonlair *venue* is real and must keep rendering via its live entry → its db/035 audio anchor) + the 7b flag. ~−1500 LOC. The **STAGE 7 SCOPING NOTE** (Direction §7) comes due: extract immersive compositing as an app-neutral Layer-4 capability at this rewire rather than re-inlining it karaoke-specifically (UAP §2's "one capability"; avoids the build-twice trap when games-venues lands).

### Carry-over into next session

- **iOS Capacitor resync** — still deferred (the 4.5 tracked entry; trigger = next functional iOS-relevant change; 7a added no iOS-facing change).
- **The D-guard every-call warn** — intentional; throttle only if 7b/7c shows it floods (locked default: every-call).
- **The 7b flag mechanism** — its exact shape (URL param / localStorage / a const toggle) is a 7b design decision; whatever it is, it must let 7c run a true side-by-side and must be deletable in 7d.

---

## End of log
