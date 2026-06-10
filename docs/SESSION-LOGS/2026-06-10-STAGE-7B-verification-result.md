# Venue Admin UI Stage 7b — Verification Result Log

**Spec:** `docs/VENUE-ADMIN-UI-STAGE-7B-BUILD-SPEC.md` (foundation brief at `docs/STAGE-7B-BUILD-SPEC-BRIEF.md`)

**Workstream:** Phase 3 / Plan B — **Stage 7b**, the karaoke read-path switch behind a flag — the second sub-stage of Stage 7. Follows 7a (`3f6cf0f`, prerequisites: db/040 audio anchors + venue-modulators.js, dormant). Adds the data-driven venue read path alongside the procedural one, **behind a flag DEFAULT-OFF**, so the procedural path (`AMBIENT_PROFILES` / `addVenueEffects3D`) stays canonical and byte-unchanged for all default visitors. **Nothing deleted** (that is 7d); the flag **stays through 7c**. Precedes 7c (exhaustive parity verification — the deletion gate) and 7d (the irreversible deletion + the compositing-extraction note).

**Commits in this stage (chronological on `main`):**
- `fafbfae` — `feat(venue-admin): Stage 7b — karaoke read-path switch behind a flag [v2.103]` (all gates 1–6 + the particle.js signature change + the venue-modulators.js guard-warn fix + version bump)
- `<closeout>` — `docs(venue-admin): Stage 7b closeout — verification log + 7a-spec dual-case warn note + DEFERRED` (this commit)

**Prod-apply state:**
- **No migration this stage.** Stage 7b is code-only (the data path's anchors — db/036–040 — were already applied in their stages; 7a's db/040 closed the audio gap). The flag is default-OFF, so prod behavior is byte-identical for real visitors.
- Verification via the **`7b-verify` GitHub Pages branch-deploy** (built 2026-06-10; source reverted to main at closeout). Unlike 7a (which touched no live surface and needed no deploy), 7b modifies the live read path (`karaoke/stage.html`), so the branch-deploy A/B was required. The safety profile mirrored 4.5's but was even stronger: 4.5's verify build behaved identically because the data was dormant; **7b-verify behaves identically for default visitors because the flag is OFF** — the procedural code path is reached unchanged, and only `?venuepath=data` sessions exercised the new path.
- iOS Capacitor resync remains deferred (the 4.5+7b tracked entry; 7b is flag-default-OFF → zero iOS-facing change; the real trigger is 7d). See Carry-over.

---

## Outcome — full A/B verification PASS, 0 bugs in code

A clean run. No bugs in the shipped code, no triage commits. The build proceeded gate-by-gate (1→6) with propose-pause at each; two issues were caught **in-build before they shipped** (a stray trailing comment on a "byte-unchanged" procedural line at gate 4, and the resolver-shape reconciliation surfaced at the foundation map) and resolved in place.

### Cluster 1 — Safety (default = procedural, byte-identical)

**C1.1 — Default URL is procedural, byte-identical.** The bare `karaoke/stage.html` (no `?venuepath=data`) renders every venue exactly as today. `activeVenuePath === 'procedural'` → both flag branches (`startAmbient`, `addVenueEffects3D`) and the render-loop data arm are skipped; `renderVenueFromAnchors2D/3D`, `activateVenueDrivers`, `tickVenueModulators` are never called; `dataPath*Handles` stay `[]`. Default visitors are unaffected. **PASS** ✓

### Cluster 2 — A/B parity (`?venuepath=data` vs procedural), all 5 effect venues

**C2.1 — festival (the high-risk depth case).** `overlay → spotlight → particle` (strobe under lasers under confetti) — depth correct, matching the cited `LAYER_ORDER`. The case a fixed family order would have broken renders identically to procedural. **PASS** ✓

**C2.2 — stadium (modulator + dual-contract 3D).** Phone-lights **pulse** via the live `crowd_brightness` driver (not the preview oscillator); 2D phone-lights + beams on the layered stack, 3D phone-lights + cones in `panScene` (the 2D `{stop}` + 3D `{update,dispose}` dual-contract dispatch both driven correctly). **PASS** ✓

**C2.3 — disco (lockstep modulator + depth).** Mirror-ball **pulses** via `beat_scale`/`beat_brightness` in lockstep; floor-flash under the dots (overlay→particle depth). **PASS** ✓

**C2.4 — speakeasy (2D + 3D).** Smoke + light-shaft (2D stack) + candles + smoke (3D `panScene`) all render. **PASS** ✓

**C2.5 — honkytonk (stochastic overlay).** Amber neon tint via the stochastic overlay renderer. **PASS** ✓

**C2.6 — audio parity.** Each venue plays the same mp3 as procedural — the data branch resolves the audio anchor → `audio.js` renderer → `SOUNDS_BASE + sound_id + '.mp3'`, and `sound_id === venue_id` (incl. the 5 effect-venue audio anchors from db/040), so the file is identical to `playAmbientMp3('<venue>')`. No venue went silent. **PASS** ✓

### Cluster 3 — Mechanics + regression

**C3.1 — Teardown (leak check).** Cycling venues both directions: `document.getElementById('ambient-stack').childElementCount` returns to 0 after leaving a data venue; no orphaned/stacked canvases; no doubled audio. The teardown symmetry (both teardowns run every change, idempotent; proc→data outgoing 3D disposed in the data branch; data-3D self-clear guards same-venue rebuild) holds across all transitions. **PASS** ✓

**C3.2 — Console silent.** No `[venue-modulators] unresolved driver …` warns in normal operation — every binding resolves to a live driver. The D-guard is armed but quiet (as it should be when correctly configured). **PASS** ✓

**C3.3 — 🚨 Admin regression (the hard gate).** admin-venues.html particle preview **still animates** via the `PREVIEW_OSCILLATORS` fallback — the gate-5 `computeModulatorTargets(modulator, elapsedMs, resolver)` signature change did NOT break the working path. (Admin passes no `ctx.modulators` → `resolver` undefined → the original oscillator expression, byte-identical.) This is the one edit on a live working path; it is verified intact. **PASS** ✓

---

## Bugs caught this stage

**None in code.** No triage commits. (Two in-build catches, pre-ship: the gate-4 stray comment on the procedural render-loop line — reverted so the line is byte-identical; and the resolver-shape reconciliation between the `(name, target)` 2D contract and the `(name)` 3D contract — resolved via the optional-`target` guard-warn fix.)

---

## Test artifacts — inventory

- **No DB writes** — 7b is code-only; the A/B exercised existing anchors (db/036–040) read-only. Nothing to revert.
- **`7b-verify` branch** — pushed at `fafbfae`; Pages source pointed at it for the A/B, reverted to main at closeout; branch retained until closeout, deletable after.
- **Other tables/anchors** — untouched.
- **admin-venues.html** — NOT modified (the back-compat fallback kept the admin surface edit-free; confirmed in the diff and by C3.3).

---

## Conclusion

Stage 7b ships clean. Full A/B verification PASS; zero bugs in code; zero triage commits; default-OFF byte-identical for all real visitors.

7b delivered (`fafbfae`), gate by gate:

1. **The flag** — `window.elsewhere.useDataPath` from `?venuepath=data`, default OFF; `activeVenuePath` captured ONCE at `initVenueMode` (the single venue-init entry that fires both the 2D/audio and async 3D arms → both agree on one path → no half-switch).
2. **2D canvas collision resolution** — `#ambient-stack` wrapper + `makeStackCanvas` (one transparent canvas per 2D anchor, self-RAF each, no shared-clear collision) + `teardownDataPath`.
3. **2D/audio dispatch** — `LAYER_ORDER` (per-venue, **cited to source lines**, the eventual migration's source-of-truth for D-zorder option A) + `renderVenueFromAnchors2D` (canonical Phase-2 resolution: `loadVenueAnchors` → `resolveAnchorSet` with the karaoke `anchor_patch`; audio anchors + layered 2D canvases ordered by `LAYER_ORDER`).
4. **3D dispatch + render-loop data arm** — `renderVenueFromAnchors3D` (3D anchors → `panScene`, `{update,dispose}` → `dataPath3DHandles`) + the render-loop data arm (procedural line byte-unchanged; the modulator tick gated on the data path AND a no-op without active drivers, off the render loop's own `now` so driver-clock == render-clock).
5. **Resolver threading** — `particle.js` `computeModulatorTargets` gains an optional `resolver` (back-compatible: absent → `PREVIEW_OSCILLATORS`, admin edit-free); the 3D modules already had `ctx.modulators` (no signature change). The `venue-modulators.js` D-guard warn gained the dual-case clean message (target optional).
6. **Flag branches wired live** — `startAmbient` + `addVenueEffects3D` early-return data branches (procedural arms verbatim); teardown symmetry leak-free across all four transitions.

Per the safety frame: **the procedural path stays canonical and default-live**; nothing was deleted; the flag stays through 7c.

### DEFERRED / doc updates at closeout

- **7a spec §4 (D-guard) updated** — folded in the dual-case warn-message note (the gate-5 deferral): `target` is now optional, the warn drops the "for target" clause when absent (no `'undefined'`), and the §6.2 harness assertion covers both cases (re-run GREEN at gate 5). Recorded in `docs/VENUE-ADMIN-UI-STAGE-7A-BUILD-SPEC.md` §4 rather than churning the closed spec elsewhere.
- **iOS Capacitor resync** — the 4.5 DEFERRED entry extended to cover 7b (same flag-default-OFF logic; the real iOS trigger is 7d). See Carry-over.
- **D-zorder option A (`z`-on-payload migration)** — remains deferred (filed in the 7b spec §7); `LAYER_ORDER` is the migration's source-of-truth. Trigger: data path canonical post-7d, or games-venues needing per-venue re-layering.
- No new bugs/backlog generated — 7b is a clean implementation of an approved spec.

### Next — Stage 7c (the deletion gate)

7b made the data path exercisable and A/B-verified the switch works. 7c is the **exhaustive** parity pass that gates the irreversible 7d:
- All ~33 seeded anchors + the 5 effect-venue audio + modulator behavior, **every** venue, data-path vs procedural, side-by-side via the flag (7b verified the mechanism + the high-risk cases; 7c is the complete sweep).
- **The flag STAYS through 7c** — it is the A/B mechanism the deletion gate depends on. 7c is reversible by construction.
- 7c is the sign-off: 7d does not proceed until 7c confirms every venue renders identically through the data path.

### Then — Stage 7d (irreversible)

Delete `AMBIENT_PROFILES` + `addVenueEffects3D` + the 4 dead keys (space/forest/underwater + the dead-dragonlair shadowed entry, preserving the live dragonlair venue) + the flag (`window.elsewhere.useDataPath` / `activeVenuePath` / the early-return branches) + the `#ambient-layer`-vs-`#ambient-stack` duality + `LAYER_ORDER` (→ `payload.z` per the B→A path). ~−1500 LOC. The STAGE 7 SCOPING NOTE (extract immersive compositing as an app-neutral Layer-4 capability) comes due. **iOS sync becomes mandatory at 7d close** (the data path becomes the only path → renderers load-bearing for all visitors → native confirmation required).

### Carry-over into next session

- **iOS Capacitor resync** — deferred (4.5 + 7b; flag-default-OFF → zero iOS-facing change; mandatory at 7d). The DEFERRED entry is updated with the 7d trigger.
- **`7b-verify` branch** — retained through closeout (Pages reverting to main); deletable once main has 7b.
- **The D-guard every-call warn** — intentional; throttle only if 7c finds it floods (locked default: every-call). It was silent in the 7b A/B (all bindings resolved).

---

## End of log
