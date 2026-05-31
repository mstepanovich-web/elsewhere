# Session A4b verification pause — state snapshot

Written mid-verification of Stage A4b before session close. Resumption
context for the next planning chat / Claude Code session. Not a session
log — the proper closeout log lands when A4b verification completes and
the branch merges to main.

---

## 1. Verification in-flight state

### 1.1 Where the work sits

Branch `a4b-verify` at HEAD `42c501e`, ahead of `main` by 2 commits:

- `42c501e` — fix(venue-admin): A4b verification — escape backtick trap in renderSpotlightAnchorRowHTML comment block
- `995b0e7` — wip(venue-admin): Stage A4b verification branch — 3D venue effects + Three.js admin preview + 2D panel standardization

`db/038_3d_anchor_seed.sql` is a separate earlier commit (`48b7b38`) already on main and **applied to prod**. The 4 A4b seed anchors exist in `venue_anchors`:

- `anc_spot_stadium_beams3d` (spotlight / swept-beam-3d)
- `anc_spot_speakeasy_candles` (spotlight / point-light)
- `anc_par_stadium_phonelights3d` (particle / point-cloud-3d)
- `anc_par_speakeasy_smoke3d` (particle / volumetric-3d)

### 1.2 Deploy state

GitHub Pages is **currently serving `a4b-verify`** (legacy branch-source build, switched via PUT `/repos/.../pages` using `gh api`). Build commit `42c501e5`, completed 53s. Deploy URL: https://mstepanovich-web.github.io/elsewhere/admin-venues.html.

**Closeout task:** revert Pages source to `main` via the same `gh api` path. Tracked as task #18.

### 1.3 What was verified

- **Deploy live with A4b code** — confirmed via marker grep (`spotlight-3d.js` / `particle-3d.js` script tags at admin-venues.html:52-53 in served bytes; 13 additional renderer-comment references).
- **L2984 backtick fix** — applied, committed, deployed, byte-verified against local.

### 1.4 What was NOT verified (resume from here)

Cluster 1 was interrupted at C1.1 by the spotlight-panel crash on stadium. Per `docs/SESSION-A4B-VERIFICATION-PAUSE.md` task list:

- **C1.1 — Renderer registration (in_progress)** — three console expressions queued but not yet run.
- **C1.2 — db/038 seed visible in stadium + speakeasy** — pending.
- **C1.3 — Per-kind preview render × 4 3D anchors** — pending.
- **C1.4 — WebGL context teardown / leak loop** — pending.
- **C1.5 — RPC gate refuses non-admin** — pending.
- **C1.6 — D8 dormancy on karaoke/stage.html** — pending.
- **All of Cluster 2** (C2.1 through C2.7, including the 🚨 8c volumetric velocity_range fix verification) — pending.

### 1.5 The L2984 triage finding

Stadium's spotlight panel crashed on load with `TypeError: kind is not a function`. Root cause: unescaped backticks (U+0060) at admin-venues.html:2984 inside an HTML comment inside the outer template literal of `renderSpotlightAnchorRowHTML` (2D row renderer, defined at L2964). The JS lexer closed the outer template literal at the first backtick, parsed the rest of the comment as `.fld - kind\`...\`(...)` — a binary subtraction with the right operand being a tagged template literal where `kind` (the string function parameter) was treated as the tag function. Runtime threw on every 2D spotlight anchor render.

**Symptom**: any venue with a 2D spotlight anchor was broken; A4b verification surfaced it because stadium has BOTH `anc_spot_stadium` (2D, A4a) AND `anc_spot_stadium_beams3d` (3D, A4b). PostgREST returned them in id.asc order, so the 2D anchor was hit first, crashed the forEach, blocked the 3D anchor from rendering.

**Pre-existing Gate 8a regression** — the comment was introduced during A4a's panel-standardization retrofit and shipped to prod because A4a verification didn't load a venue with a 2D spotlight anchor after 8a landed. Fix is targeted (two backticks → single quotes, matching the L3252 comment style); audit confirmed sole instance in the file.

### 1.6 DEFERRED items surfaced (file at closeout)

Six items for `docs/DEFERRED.md` at the A4b closeout commit:

1. **A4a verification protocol gap.** Gate 8a panel standardization shipped without exercising 2D spotlight rendering. The L2984 backtick trap was discoverable on any venue with a 2D spotlight (stadium, festival, speakeasy/light-shaft) but A4a verification didn't load one. Mitigation: include "load each venue × each anchor type" as a baseline in future verification protocols, and run it after any panel-standardization or comment-block edit.
2. **Registry vocabulary extension.** `shell/venue-registry.js:165` warns that `'spotlight-3d'` and `'particle-3d'` are not in the known anchor type vocabulary (spec §3.2 + db/032 CHECK). Registration accepted per Gate 5's distinct-keys revision but warning fires on every load. Two options: (a) extend the known-types list in venue-registry.js to include the `-3d`-suffixed registry keys, or (b) accept the warning permanently as part of the registry-key / DB-type split. Decision needed before A7 hits the same vocabulary boundary on the read-path switch.
3. **Pages-deploy-via-API path validated for future verification cycles.** Same `gh api -X PUT /repos/.../pages` + `POST /pages/builds` + poll workflow used here is reusable. Worth documenting as a verified-branch-deploy pattern in CLAUDE.md or a sibling doc — saves manual web-UI clicks on every verification cycle.
4. **Cross-context canvas contamination (3D-Play-then-2D-Play, order-dependent).** A4b verification surfaced an order-dependent bug where playing a 3D spotlight preview, then a 2D spotlight preview on the same panel, made `getContext('2d')` return null on the 2D canvas. **Three plausible mechanisms ruled out by static analysis:**
   - `spotlight.js` canvas acquisition — uses `ctx.canvas` only, no document lookups (handleSweptBeam2d L328, handlePulsedLaser L502, handleLightShaft L688). The renderer can't grab the wrong canvas.
   - `stopAllOther3dPreviews` teardown chain — `st.canvasEl` references in `state.spotlight3dPreviewState` / `state.particle3dPreviewState` are exclusively freshly-created 3D canvases set by `onPlaySpotlight3dPreview` / `onPlayParticle3dPreview`. No code path stores a 2D canvas in those Maps; teardown only touches 3D canvases.
   - Three.js r128 `WebGLRenderer` source — zero `querySelector` / `getElementsByTagName` / `getElementById` calls in the minified bundle (verified by `curl` + `grep`). Constructor uses `parameters.canvas` if provided, otherwise creates a fresh canvas via `createElementNS`. Internal helper canvases (`xt` for texture image conversion, `P` for texture resizing) are held module-level and never inserted into page DOM.

   **Mike's DOM diagnostic confirmed scoping is correct:** before-Play and after-3D-Stop runs both show the 2D canvas under `anc_spot_stadium` with its 2D class, untouched by the 3D path. The 3D path never reaches the 2D canvas at the DOM level.

   **Working hypothesis (unverified):** Chrome's hardware-accelerated 2D canvas implementation (Skia GL backend) shares GPU resource accounting with WebGL contexts. Prior WebGL allocation can cause subsequent `getContext('2d')` calls to be refused under GPU pressure even after the WebGL context is disposed. Order-dependency (3D Play first → 2D Play fails) is the documented fingerprint of this class of bugs in Chrome's canvas implementation.

   **Mitigations applied in commit X (A4b triage):**
   - Fresh-canvas-per-Play lifecycle on all four preview handlers (3D handlers from Fix 1-redo, 2D handlers from this commit), so each `getContext('2d')` call happens on a fresh DOM element with no prior history.
   - `willReadFrequently: true` on every 2D `getContext` call in `spotlight.js` and `particle.js`, hinting Chrome to use software/CPU backing for the 2D canvas instead of Skia GL — directly counters the GPU pressure mechanism.

   Mitigations are sufficient for the symptom. Root cause is browser-internal and not fixable from JS. **Future work:** if this re-emerges (especially during the unified-app migration when these canvases get touched differently), in-browser debugging with `chrome://gpu-internals` exposed could confirm the GPU resource-pressure mechanism directly. Filing for awareness.

5. **C1.5 verification (RPC gate non-admin refuse) — deferred.** A4b modified zero auth/gate code (verified by grep: the modified files are `admin-venues.html` lifecycle handlers + CSS + 2 renderer module `getContext` lines, none in `shell/auth.js` or `admin-venues.html`'s boot/gate section at L1171+). Risk of A4b breaking the platform-admin gate is effectively zero. Verification not run due to sign-out friction (admin-venues.html has no sign-out affordance, see UX bundle below). Acceptable per the no-touched-code reasoning. Re-verify at next session that involves auth-adjacent changes.

6. **A4b verification UX bundle (4 findings).** Surfaced during Cluster 2 testing. None block A4b; all worth filing for the admin-UI polish workstream.
   - **`'ok'` vs `'success'` class drift on Save success status.** `showAnchorStatus(anchorId, 'Saved', kind)` accepts a `kind` class. CSS defines `.anchor-status.error` (red, `#e07e7e`) and `.anchor-status.success` (gold, `var(--color-gold)`) only. Five save handlers exist; three pass `'success'` correctly (audio L1938, particle 2D L2728, particle 3D L4741), but BOTH spotlight handlers pass `'ok'` (A4a 2D L3719, A4b 3D L4641). `.anchor-status.ok` has no CSS rule, so the success text falls back to `var(--color-text-faint)` — visually distinct from the gold success state of the other panels. **Fix is trivial:** `'ok'` → `'success'` at L3719 + L4641. Held during A4b triage to keep the focused commit clean. File at closeout.
   - **Stop-button location inconsistency.** The per-row ■ Stop button position relative to ▶ Play / ↻ Replay / Save differs between panels (audio Stop is at the row-top-right outside `.anchor-row-actions`; spotlight 2D / particle 2D / 3D have Stop in the action row alongside Save). The audio panel's Stop predates the canonical `.anchor-row-actions` pattern. Worth a panel-standardization unification pass post-A4b.
   - **No sign-out affordance on admin-venues.html.** The admin badge is the only header element; no logout link. To switch accounts, admin must navigate to a different Elsewhere surface (the shell `index.html`) and sign out from there. Minor friction for the admin's own workflow; significant friction for any future "verify as non-admin" testing cycle (see DEFERRED item 5 above). Trivial addition — sign-out link near the admin badge.
   - **Save-differs: behaviorally inconsistent save flow across panels.** Mike noted that save behavior visually differs across panels in ways beyond the `'ok'`/`'success'` class drift — exact behavior delta worth documenting more precisely the next time a save sequence is exercised side-by-side across audio + particle + spotlight. Pending more detailed repro from the next verification cycle; recording here as a pointer.

### 1.7 Closeout sequence when verification passes

Per task list (#14 → #18, plus #20 for the vocabulary-extension DEFERRED entry):

1. Bump `admin-venues.html` L645 `v2.139 → v2.140` and `karaoke/stage.html` L457 + L614 `v2.101 → v2.102`.
2. Amend wip commit `995b0e7` to include `docs/A4B-BUILD-SPEC-BRIEF.md` (Mike's call; ruling already made — the brief is part of the A4b workstream). Force-with-lease push. (`PHASE-2-CONSULTATION-WRAPPER.md` and `files.zip` stay untracked.) The triage commit `42c501e` may either stay separate or fold in — call at closeout.
3. Merge `a4b-verify` → `main` with `--no-ff` to preserve branch history. Reword merge subject to: `feat(venue-admin): Stage A4b — 3D venue effects + Three.js admin preview + 2D panel standardization`. Proper body capturing Gate 7a-REDO schema rebuild, Gate 8c velocity_range production-bug fix, gate sequence 2–8c, version bumps, db/038 already on main via 48b7b38, plus the L2984 triage finding. **No `Co-Authored-By` trailer** per CLAUDE.md doctrine.
4. Push main.
5. Switch GitHub Pages source back to `main` via `gh api -X PUT /repos/.../pages` (`{"source":{"branch":"main","path":"/"}}`).
6. `~/sync-app.sh` + `npx cap sync ios` + iOS native rebuild — closes the iOS bundle drift that's been deferred throughout A4b (Capacitor bundle was stale at v2.99).
7. Write `docs/SESSION-A4B-CLOSING-LOG.md` per `docs/SESSION-5-PART-3-CLOSING-LOG.md` precedent. Append the three DEFERRED entries above to `docs/DEFERRED.md`.
8. Update `docs/ROADMAP.md` Active section: A4b status from "next deliverable" to shipped (with commit refs); next deliverable is whichever A-stage is sequenced after A4b (see §2.6 below).

---

## 2. Phase-3 status snapshot

Grounded in `docs/VENUE-ADMIN-UI-DIRECTION.md` §7 (the A1–A8 staging) and `docs/ROADMAP.md` Active/Queued sections. Where a doc doesn't name something explicitly, this section says so.

### 2.1 What each A-stage covers (one line per stage)

Per Direction §7:

- **A1 — Admin UI skeleton + `venue_defaults` editor.** Single page (`admin-venues.html`); reads all venues; edits `venue_defaults` columns (camera_fov, motion jsonb, ambient jsonb, the 4 yaw/pitch columns); SECURITY DEFINER RPCs gated by `is_platform_admin`; no anchor editing yet.
- **A2 — `audio` renderer impl + audio anchor authoring panel + 19-venue programmatic seed.** First vertical slice through the architecture (UI → DB → registry → renderer → karaoke); validates the end-to-end pattern against the easiest type.
- **A3 — `particle` renderer impl + particle authoring panel + ~4 venues translated.** Highest-risk structural decision (per-sub-shape kind discrimination: `point-cloud`, `directional-emitter`, `volumetric`); the admin UI's live preview makes the iteration tractable. Spec §0.2 deferred 3D particle paths to A4b.
- **A4 — `spotlight` renderer impl + spotlight authoring panel + stadium/festival/speakeasy spotlights.** Includes translation of the 2 Three.js 3D builders. **Sub-staged 2026-05-27:**
  - **A4a — 2D-canvas spotlight only.** 3 kinds (`swept-beam-2d`, `pulsed-laser`, `light-shaft`); 3 anchors; GSAP-equivalent motion via pure-JS ease functions.
  - **A4b — 3D spotlight + 3D particle extension + new Three.js admin preview surface.** 4 anchors (`swept-beam-3d`, `point-light`, `point-cloud-3d`, `volumetric-3d`); admin-venues.html gains Three.js preview infrastructure; per spec D-twinkle the phone-lights point-cloud uses a custom per-vertex-phase ShaderMaterial.
- **A4.5 — `overlay` renderer impl + overlay authoring panel + disco floor-flash + festival strobe.** New anchor type for screen-space visual overlays (gradient/rectangle/polygon) that aren't directional light sources, informative markers, or particulate matter. Adding `'overlay'` to `db/032`'s `venue_anchors_type_check` is part of this stage's migration. **(Direction §7 lists this as Stage 4.5, between A4 and A5 — Mike's question asked about A1–A8 inclusive but I'm calling out A4.5 explicitly to avoid an off-by-one.)**
- **A5 — Remaining types (`callout`, `pin`, `video`, `link-hotspot`) + leftover venues.** Long tail; ships per opportunity.
- **A6 — Per-app override editor (`anchor_patch` UX).** Karaoke-specific override surface from `karaoke_venue_settings`. Direction §7 notes A6 is "lower priority than Stages 1–5/7; ships in any order after Stage 1."
- **A7 — Switch karaoke to data-driven path; retire `AMBIENT_PROFILES` + `addVenueEffects3D`; implement venue modulator system.** Three-part stage (see §2.4 below).
- **A8 — Costume library + suggested-costumes editor.** Consumes the Phase-3 costume seed migration described in `PHASE-2-BUILD-SPEC.md` §6 (seed `costumes` from existing `DEEPAR_EFFECTS` + relocate `.deepar` files from `karaoke/effects/` to `/costumes/`). Ships when karaoke's costume rendering is rewired.

**Doc-naming note:** `CLAUDE.md` references "A1–A9 staging" in the A4b spec preamble. Direction §7 names stages A1, A2, A3, A4 (with A4a + A4b), A4.5, A5, A6, A7, A8 — no A9. Mike's question asked A1–A8; reporting what Direction §7 explicitly names.

### 2.2 Which A-stages have shipped (with commit refs)

Sourced from `git log` on admin-venues.html / shell/venue-renderers/ and from ROADMAP.md's Active section status list:

| Stage | Status | Implementation | Mid-verification fixes | Closeout | Migration |
|---|---|---|---|---|---|
| A1 | ✓ Shipped 2026-05-26 | `9cf4b70` | `606674f` (path fix) | `f610039` (verification log) | `db/034` |
| A2 | ✓ Shipped 2026-05-26 | `9d58a8d` | — | `a1a02e3` (verification log) | `db/035` |
| A3 | ✓ Shipped 2026-05-27 | `e9c52e9` | `27610e4` (Check 15 kind-gate) | `01fc791` | `db/036` |
| A4a | ✓ Shipped 2026-05-27 | `f167ec6` | `0b2dec0` (Check 19) + `2056a72` (Check 21) | `21991e8` | `db/037` |
| A4b | **In verification on branch `a4b-verify`** | `995b0e7` (wip) | `42c501e` (L2984 triage) | not yet | `db/038` (already on main via `48b7b38`, applied to prod) |
| A4.5 | Not shipped | — | — | — | — |
| A5 | Not shipped | — | — | — | — |
| A6 | Not shipped | — | — | — | — |
| A7 | Not shipped | — | — | — | — |
| A8 | Not shipped | — | — | — | — |

`db/034`–`db/037` applied to prod 2026-05-26/27 (per ROADMAP active section); `db/038` applied prior to A4b verification per Mike's session intro.

### 2.3 Where A4b sits

A4b is the **second sub-stage of Stage 4** (spotlight). Currently mid-verification on branch `a4b-verify`. Implementation complete + L2984 triage fix landed. Once the verification clusters pass, A4b becomes the **5th A-stage to ship** (after A1, A2, A3, A4a — counting A4a/b as discrete shippable units; Stage 4 the umbrella closes when A4b lands).

In Direction §7's sequencing, A4b's completion closes the "venues that need 3D effects" half of the translation arc (stadium + speakeasy). With A4b shipped, the 2D-canvas path covers audio/particle/spotlight across the 19 audio-only + 4 particle + 3 spotlight venues, and the Three.js path covers the 2 venues that need 3D renderers. The next translation work (A4.5 overlay) addresses 2 venues that don't fit existing types (disco floor-flash + festival strobe).

### 2.4 Block B scope (Stage A7 part 1)

Per Direction §7 explicit text (lines 437–449): **Block B is part of Stage 7, NOT a separate downstream stage.** Earlier docs that referenced "Block B" as separate are superseded by Direction §7.

A7 is a three-part stage, in order:

1. **(Block B) Switch karaoke's read path** to consult the registry-resolved renderer instead of the procedural closures. Concretely: replace `karaoke/stage.html`'s consultation of `AMBIENT_PROFILES` + `addVenueEffects3D` with calls to `getAnchorRenderer(anchorType)` from `shell/venue-registry.js` per anchor on the venue's resolved anchor list (from `loadVenueAnchors` + `resolveAnchorSet`). Must work for every shipped anchor type — audio, particle (2D + 3D), spotlight (2D + 3D), overlay (if A4.5 shipped before A7), and whichever of A5's types ship before A7.
2. **Verify every venue renders visually identically** through the data-driven path before any procedural code is removed. Spec §7 names this explicitly as a gate before step 3.
3. **Delete `AMBIENT_PROFILES`** (including the 4 ghost venue keys — `space`, `forest`, `underwater`, `dead-dragonlair` — which Direction §7 calls "dead procedural code with no live consumers") **and `addVenueEffects3D`** in the same pass.

A7 also implements the **venue modulator system** — the real registry-resolved drivers (e.g. `crowd_brightness`) that replace `particle.js` + `spotlight.js`'s preview-oscillator heuristics. The dormant A-stages (A2–A4b) don't need real drivers; the canonical read-path does.

Direction §7 estimates **~−1500 LOC from `stage.html`** when A7 lands.

**A4b spec D8 + dormant contract:** every renderer impl from A2 onward ships dormant. `karaoke/stage.html` continues consulting the procedural path until A7's read-path switch in step 1. The registry is populated as A-stages ship but isn't read by karaoke until A7.

### 2.5 Other Phase-3 work — in flight, shipped, or pending (separate from A-stages)

Sourced from ROADMAP.md Queued section + UAP §5 phase mappings. ROADMAP.md explicitly names these as Phase-3 or Phase-3+ aligned:

- **Phase 1 (room/session foundation)** — ✓ **Shipped** 2026-05-21 → 2026-05-23. Keystone for Phase 3/4/5. ROADMAP Completed section names commits `dddbeb6` (db/025), `9e3926e` (db/026), `2465ff5` (db/027), `95dcf70` (db/028), `c657c9f` (forward-correction).
- **Phase 2 (venue abstraction)** — ✓ **Shipped** 2026-05-24. Data layer + resolver + registry mechanism in three architectural layers. Commits `a254993` (db/032), `0b91206` (spec + bookkeeping), `d5ca112` (venue-settings.js), `a62d1e9` (venue-registry.js). Ships dormant; Phase 3 populates the registry (which is the A-stages' active work).
- **Session 9 — Audience.html unification (NHHU → HHU UI merge)** — **Queued**. ROADMAP marks this with UAP §5 phase mapping: **Phase 3** (karaoke onto the new model). Described as "keystone for further platform work — until this lands, NHHU conversion funnel + games venues + wellness all fight against the audience-vs-singer split." Depends on Session 5 closure; Sessions 6–8 don't strictly block but ship faster. Canonical scope: `docs/KARAOKE-CONTROL-MODEL.md` §5.5.
- **Session 11 — Audience-to-NHHU conversion path (user-acquisition funnel)** — **Queued**. UAP §5 phase mapping: **Phase 3+** (sister UX/funnel layer). Depends on Session 9 landing first. Canonical scope: `docs/KARAOKE-CONTROL-MODEL.md` §5.4.
- **§12 bullets 3–4 (DEFERRED cluster disposition + INFRA.md / CLAUDE.md updates)** — described in PHASE-2-BUILD-SPEC.md §12 as **riding with Phase 3** because they describe karaoke operational behavior, which only changes when Phase 3 rewires karaoke (i.e., A7).
- **Sessions 6 (SMS pre-invites), 7 (Admin management UI), 8 (Trivia premium UX)** — queued, but ROADMAP does NOT map these to a UAP §5 phase. Direction §7 doesn't name them either. They're orthogonal to Phase 3's venue/karaoke arc.

**Doc-naming note:** ROADMAP describes the A-stages as Phase 3's "venue admin UI Part 1 + venue translation." Block B (A7) is the karaoke-half of Phase 3. Sessions 9 + 11 are post-A-stages Phase-3 work. The docs do NOT explicitly enumerate any in-flight Phase 3 work besides the A-stages — Sessions 9 and 11 are queued, not in flight. **If there's additional Phase 3 work in flight that isn't named in ROADMAP/Direction/UAP §5, this snapshot would miss it** — flagging per Mike's "don't infer" instruction.

### 2.6 Remaining work to finish Phase 3 after A4b lands

Per Direction §7 + ROADMAP, after A4b ships:

**A-stage remainders:**

- **A4.5 — overlay renderer + panel + db migration extending the type vocabulary.** Disco floor-flash + festival strobe. Forcing function: A3's foundation pass surfaced disco floor-flash has no home in the existing vocabulary; A4 surfaced festival's strobe in the same shape.
- **A5 — remaining types** (`callout`, `pin`, `video`, `link-hotspot`) + leftover venues. Direction §7 calls this "long tail; ships per opportunity" — does not require all 4 to ship before A7.
- **A6 — per-app override editor.** Direction §7: "Lower priority than Stages 1–5/7; ships in any order after Stage 1." Could land before or after A7.
- **A7 — Block B + visual-equivalence verification + `AMBIENT_PROFILES`/`addVenueEffects3D` retirement + venue modulator system.** The critical-path stage. Depends on every procedural venue having a data-driven equivalent — so A4.5 (if there are unrendered procedural overlays) and any A5 types karaoke depends on must ship first.
- **A8 — costume library + suggested-costumes editor.** Ships when karaoke's costume rendering is rewired. Direction §7 implies this can ride alongside or after A7.

**Phase-3 non-A-stage remainders:**

- **Session 9** (audience.html unification) — after the A-stages.
- **Session 11** (audience-to-NHHU conversion funnel) — after Session 9.
- **§12 bullets 3–4** — ride with Phase 3, dispose when A7 lands.

**Sequencing — what Direction §7 says explicitly:**

- A1 → A2 → A3 → A4 → (translation arc continues) is the locked sequence for the translation work.
- A6 + A8 are flexible (can ship in any order after their dependencies).
- A7 is the critical path. Its preconditions: every procedural venue has a data-driven equivalent that renders visually identically.

**What Direction §7 does NOT say:**

- Whether A4.5 is strictly required before A7 (Direction §7 names A4.5 as scheduled but doesn't lock its sequencing against A7).
- Whether A5 is required before A7 (the "remaining types" language suggests these can ride past A7 if karaoke doesn't depend on them — most of `callout`/`pin`/`video`/`link-hotspot` would be additive surfaces, not karaoke-blocking).
- Estimated effort or absolute calendar dates per stage. ROADMAP marks each as "TBD per stage. Each A-stage is its own propose-pause cycle."

**Net:** Phase 3 closes when A7 ships its three parts. The "after A4b" backlog inside Phase 3 is, at minimum: A4.5 (if karaoke depends on overlay rendering) + A7 three-part + Sessions 9 + 11 + §12 bullets 3–4. A6 and A8 and A5 may ride either inside Phase 3 or alongside/after, per their explicit sequencing flexibility.

---

## End of pause doc
