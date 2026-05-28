# Venue Admin UI — Direction Note

> **REVISED 2026-05-26 — Plan B.** This note was originally written
> 2026-05-25 (commit `df49366`) recording a "wrap-as-legacy, defer real
> translation + admin UI to post-Phase-5" plan. The repo owner has
> reversed that direction. **Plan B is now in force:** the procedural
> venues are translated into data-driven `venue_anchors` + reusable
> renderer impls as part of Phase 3, and the Part 1 admin UI is built
> NOW (not deferred), serving as the authoring/preview tool that
> mitigates the translation risk. Decisions 2 (admin UI split — Part 1
> first, Part 2 post-Phase-5), 3 (pre-population), 4 (new-venue UI
> scope sketch), and 5 (single UI / app selector / base+override model)
> remain in force. Decision 1 is rewritten in §2 to record Plan B. §7
> is new — the Plan B hybrid sequencing for the build.

**Status:** Pre-spec direction, not a build spec. Captures decisions
for the Venue Admin UI work so the eventual build spec starts from
them rather than re-deriving them. Nothing is built or scheduled by
this document.

**Sequencing:** Part 1 (manage the existing 26 venues) is now Phase-3
scope, built as the authoring/preview tool that mitigates the venue
translation risk per Plan B. Part 2 (create brand-new venues, with
asset generation) remains post-Phase-5 per Decision 2 / §3.

**Companion docs:** Builds on `docs/PHASE-2-BUILD-SPEC.md` §7 (the
original admin-UI scope sketch) and on the schema settled in
`db/032_venue_abstraction_schema.sql`. Does not supersede §7 — extends
it with the Plan B sequencing.

---

## 1. Context — what this document is and isn't

The Venue Admin UI was previously sequenced as a Phase-2 fast-follow,
ahead of Phase 3's karaoke venue rewire (`docs/ROADMAP.md` Active
section, dated 2026-05-24 onward). The rationale at the time:
authoring the Phase-3 karaoke venue translation by hand — without a UI
to iterate against — was named as the larger of the two risks
(`docs/PHASE-2-BUILD-SPEC.md` §5.4 "Phase-3 translation cost"; the
risk read recorded in this session's diagnostic).

A subsequent risk read surfaced an escape hatch: Phase 3 karaoke can
adopt the venue model **without** authoring per-venue anchor records
+ payload contracts for the 10 procedural effect venues. The procedural
code is wrapped as legacy renderer implementations, preserving visual
fidelity bit-for-bit. The data-driven translation — and the admin UI
that authors against it — both move to post-Phase-5.

This document records the planning decisions that make that
sequencing coherent. It is intentionally pre-spec: it does not enumerate
columns or specify RPCs or commit to a particular component tree. It
records the *shape* of decisions a future spec author starts from.

**Not in this document:**
- Detailed UI component tree, RPC surface, validation rules — Phase-7-or-later
  spec writes these.
- An execution timeline beyond "post-Phase-5."
- Any commitment to who owns or builds the work.

---

## 2. Decision 1 — Venue migration approach: real translation now,
admin UI as the authoring/preview tool

**Venue inventory and what migrates how.** Of the 26 total venues in
`venues.json`:

- **~10 venues with bespoke procedural effect code** in
  `karaoke/stage.html:4584–4994`'s `AMBIENT_PROFILES`, plus the 2
  Three.js 3D effect builders for `stadium` and `speakeasy` in
  `karaoke/stage.html:2848–2940`. These are translated into reusable
  renderer impls registered via
  `shell/venue-registry.js:registerAnchorRenderer(type, impl)`, plus
  per-venue `venue_anchors` rows that reference those impls with
  parameters. Each bespoke `anim()` function decomposes into one or
  more typed anchors (`spotlight`, `particle`, `audio`, etc. per the
  vocabulary in `db/032_venue_abstraction_schema.sql:254–258`).

- **~13 audio-only `AMBIENT_PROFILES` entries** (with `anim: null` and
  just `playAmbientMp3('<venue>')`). Migrate mechanically via a SQL
  seed migration: one `venue_anchors` row of `type='audio'` per venue,
  plus one shared `audio` renderer impl. This is the simplest type and
  the first vertical slice (§7).

- **~3 venues with no `AMBIENT_PROFILES` entry at all.** The
  `AMBIENT_PROFILES[venueId] || null` fallback at line 4998 returns
  null silently. No migration needed — they remain silent under the
  venue layer.

**Inventory is approximate; exact per-venue classification to be
locked by the Stage 1 build spec.** The bucket sizes above are from a
quick `AMBIENT_PROFILES` + `venues.json` scan. An awk classification
during the Phase 3 scoping pass suggested ~9 procedural rather than
~10 and ~2 audio-only rather than ~13 — a delta large enough to
matter for sizing. The Phase 3 scoping report's §6 flag 4 named this
gap and asked for *"a one-pass enumeration during A1 spec-writing to
lock the exact count and the per-venue type list"*; the Stage 1 build
spec (§7) performs that pass. The three buckets are believed disjoint
— stadium and speakeasy are members of the procedural set, with
their 3D effect builders riding alongside the canvas-2D anim functions
rather than as additional venues — and disjointness is confirmed by
the same enumeration. The 26-venue total in `venues.json` is exact
(31 `id` entries minus 5 category ids).

**The translation runs through the admin UI, not around it.** The
Part 1 admin UI (per Decision 2 / §3) is built FIRST as the
authoring/preview surface; the procedural-to-data translation then
proceeds per type, with each venue authored as `venue_anchors` rows
via the UI rather than via SQL or seed migrations. The UI provides:

- A read/write surface for `venue_defaults`, `venue_anchors`,
  per-app `<app>_venue_settings`, and `venue_suggested_costumes`
  (per Decision 2 / §3).
- A live-preview affordance so each venue's translated rendering can
  be compared visually against its procedural ancestor.
- Per-type authoring forms keyed to each registered renderer impl
  (so payload shapes settle empirically as each impl is built).

The hybrid sequencing for this work — admin UI skeleton first, then
per-type vertical slices that build a renderer impl + its UI panel
+ translate the venues that use that type — is recorded in §7.

**Why this is the mitigation, not the risk.** The risk in the
translation is the per-type payload STRUCTURE (which knobs a renderer
exposes, what the `payload` jsonb shape is, what's shared vs.
per-venue) — see Decision 3 / §4. Authoring those structures by hand
without a visual feedback loop risks baking in premature contracts;
authoring them THROUGH the admin UI keeps the iteration loop tight
and the resulting payload shapes empirical against real venue data.
The admin UI is the IDE for the translation work, not a downstream
consumer of it.

**What this commits to:**

- Phase 3 ships karaoke on the new venue layer with **real**
  data-driven anchor records, not wrapped procedural code.
- The Part 1 admin UI ships as Phase-3 scope, before / during /
  alongside the translation per §7.
- `AMBIENT_PROFILES` and `addVenueEffects3D` are retired from
  `karaoke/stage.html` once every procedural venue has a data-driven
  equivalent that renders visually identically.
- The renderer-API contract (per
  `shell/venue-registry.js:63–72`, deliberately unspecified in Phase
  2) is settled empirically across §7's per-type stages, not by a
  speculative spec.

**What this does NOT commit to:**

- The Part 2 admin UI (create brand-new venues, with asset generation
  pipelines per Decision 4 / §5) — remains post-Phase-5.
- A specific per-type payload schema. Each type's `payload` shape is
  settled in its own per-type build spec (§7's Stages 3–5).
- A specific component tree, validation rules, or RPC surface for the
  admin UI itself. Those land in the admin-UI build spec, written
  next.

---

## 3. Decision 2 — Admin UI split into two parts; manage-existing first

The eventual admin UI splits into two distinct build artifacts:

**(a) Manage the existing 26 venues.** Built FIRST (post-Phase-5).
Scoped to the known set of 26 venues in `venues.json` — not speculative
future venues. Surfaces editing of:
- venue_defaults attributes (`camera_fov`, `motion` jsonb, `ambient`
  jsonb, `start_yaw_deg`, `static_yaw_deg`, `static_pitch_deg`)
- venue_anchors records (the per-anchor type/position/payload edit
  surface)
- karaoke_venue_settings per-venue overrides (camera_fov_override,
  motion_override, ambient_override, anchor_patch)
- venue_suggested_costumes per-venue lists

**(b) Create brand-new venues.** Built LATER, separate spec.
Includes the asset-generation pipeline (Decision 4 / §5).

**Rationale.** Fitting the parameter structure to a known fixed set of
26 venues is low-risk in a way that designing for arbitrary future
venues is not. Part (a) is built against reality — the 26 existing
venues' actual data — rather than against a guess about what future
venues will need. Real use of (a) reveals where the parameter set is
inadequate or wrong-shaped; the (b) spec is written from that
experience rather than from speculation. This matches the
`docs/PHASE-2-BUILD-SPEC.md` ethos of "ship the mechanism, then learn
from data" rather than "spec the data model exhaustively first."

This split also bounds the post-Phase-5 critical-path work: (a) ships
faster because its scope is fixed; (b) lands when there's a real
forcing function for a new venue.

---

## 4. Decision 3 — Pre-population: existing values carry over; structure
is the risk, not values

When the Phase-3 translation converts the 10 procedural effect venues
from `AMBIENT_PROFILES` / `addVenueEffects3D` code into data + reusable
renderer impls (§7), **the existing parameter values carry over into
the authored anchor records.** Beam counts, sweep timings, GSAP easing curves,
particle counts, hue values, alpha ranges, audio file references —
all of these are already in the procedural code and become the
starting values for the migrated records.

**Migrated venues come over pre-populated and visually identical** to
their procedural ancestors, by construction — the admin UI's live
preview (Decision 1 / §2) is the verification surface. After initial
authoring, the admin UI continues as the surface for iterating those
values against the renderer impls.

**The risk in the translation is NOT the values** — those are already
written and observable in the live procedural code. **The risk is the
parameter STRUCTURE** — which knobs a renderer impl exposes, what the
payload jsonb shape is per anchor type, what's a shared parameter
across venues versus what's a per-venue knob. Decision 2's scope-to-26
keeps the structural decisions empirical: parameter shapes are designed
to fit the values 26 known venues actually use, not to anticipate every
possible future venue.

When a renderer impl is decomposed (e.g., the 4-beam spotlight choreography
in stadium), the values come from the procedural code; the structure
decision is "what parameterization makes this reusable in other
venues?" — and that's the iteration the admin UI supports.

---

## 5. Decision 4 — New-venue UI (part b) scope sketch

Part (b)'s scope, as currently understood (refined by the eventual
spec):

- **Skybox generation.** Blockade Labs API integration: prompt input,
  Generate, preview, "request another" (re-roll with same prompt or
  a variation), compare-to-previous (side-by-side preview of the
  current candidate against the previous one to support
  iteration-by-comparison), select-and-bind (commits the chosen image
  as the venue's skybox). The selected image lands at `/venues/{id}.jpg`
  per the convention in `CLAUDE.md`'s "Adding a venue" section.

- **Ambient sound generation.** ElevenLabs API integration (or
  equivalent): prompt input, generate ambient track, listen, adjust
  (prompt refinement / parameter tweaks), re-request, select from
  multiple candidates. The selected track lands at `/sounds/{id}.mp3`
  per the same convention.

- **Starting orientation.** start_yaw / static_yaw / static_pitch
  values for the venue's 360° sphere. UI affordance: live-preview
  drag-to-position with the rendered skybox visible (the existing
  "Set View Coordinates" pattern referenced in CLAUDE.md, lifted out
  of stage.html into the admin UI).

- **Karaoke singer-view yaw/pitch.** The per-app karaoke override
  values for where the singer is composited into the venue. Per
  Decision 5, this is an app-overridable parameter — the new-venue UI
  authors a default + the karaoke override.

**FLAG for the eventual spec — investigate Time Travel Studio reuse
before rebuilding.** The Blockade Labs skybox-generation tooling
already exists in some form inside the Time Travel Studio surface.
Before writing the spec for part (b)'s skybox-generation flow, audit
what's reusable from the Studio's existing tooling: prompt UI patterns,
API integration code, candidate-management state machine,
preview-and-compare affordance. Rebuilding from scratch may be
wasteful; reusing requires understanding the Studio's coupling
constraints first. This is investigation work, not spec work — and
investigation precedes spec for part (b).

---

## 6. Decision 5 — App-specific parameters: ONE admin UI with an app
selector, not per-app admin UIs

**Architecture decision: a single Venue Admin UI surface, with an app
selector at the top.** Selecting an app (e.g. karaoke) reveals
parameters for that app in addition to the shared venue parameters.

**Why one UI, not per-app UIs:**
- The schema already implements a base-plus-override model:
  `venue_defaults` holds shared venue identity + base attributes;
  `karaoke_venue_settings` holds per-app overrides + `anchor_patch`
  (per `db/032_venue_abstraction_schema.sql` "Design decision 2",
  lines 78–93). Future apps add `games_venue_settings`,
  `wellness_venue_settings` etc. with the same column shape.
- Authoring per-app overrides is a function of "look at the shared
  default, decide whether to override for this app." That's
  fundamentally a two-pane comparison surface, not two separate UIs.
- Separate per-app UIs would duplicate the venue-edit affordances for
  every shared parameter, and force the author to context-switch to
  see the relationship between default and override.

**UI behavior implied by this architecture:**

- The app selector is global to the surface. Default state could be
  "no app selected" (show only shared venue_defaults parameters) or
  "karaoke" (the only app with overrides defined at this point); spec
  decides.

- **Editing a SHARED parameter prompts:** "change the venue default
  (writes `venue_defaults`), or just the {app} override (writes
  `{app}_venue_settings`)?" — a small modal or inline disambiguation.
  This is the disambiguation the admin makes constantly; it deserves
  ergonomic UI treatment, not buried-in-a-menu treatment. Defaulting
  to "override" (lower-risk choice — doesn't change the venue's
  identity for other apps) seems right but the spec settles it.

- **Editing an app-only parameter** (e.g., karaoke's singer-view
  yaw/pitch) does not prompt — the parameter is by construction
  app-scoped, only the override target exists.

- **Some parameters are venue-IDENTITY level and NOT
  app-overridable.** The clearest example: the **skybox image**. A
  venue's skybox image defines what the venue *is* — swapping the
  skybox would make it a different venue. So no app can override the
  skybox; it appears read-only in any app-context view. Other
  candidates for venue-identity-level (not exhaustive — the spec
  decides): venue name, venue id, category, primary `soundId`
  attribution. Anything in the venues.json bootstrap shape is
  potentially venue-identity-level by virtue of being the
  app-agnostic descriptor of the venue.

- **OPEN for the spec — the per-parameter list:** for each parameter
  in `venue_defaults` + `karaoke_venue_settings` (and future
  `<app>_venue_settings` tables), enumerate which is
  venue-identity-only vs which is app-overridable. This is a
  deliberate decision to make against the actual schema columns at
  spec-writing time, not to guess in this direction note.

**App-only parameters that have already been named:**
- karaoke singer-view yaw/pitch (per Decision 4 §5)
- karaoke `anchor_patch` (the per-app delta against default anchors,
  per db/032's Design Decision 2)

**Shared parameters:**
- skybox image (venue-identity, NOT app-overridable)
- ambient audio file (likely venue-identity, but the spec can revisit
  if a venue's audio is per-app overridable)
- start_yaw_deg, static_yaw_deg, static_pitch_deg (`venue_defaults`)
- camera_fov, motion, ambient jsonb (`venue_defaults` — with explicit
  per-app override columns already in `karaoke_venue_settings`)
- venue_suggested_costumes (per `db/032` — author at venue-default
  level; per-app overrides via the future `app_suggested_costumes`
  pattern, not yet built)

The mapping above is the working hypothesis. The spec confirms
against the schema rows that actually exist at spec time.

---

## 7. Plan B hybrid sequencing — admin UI skeleton first, then
per-type vertical slices

The translation arc (Decision 1 / §2) and the admin UI build (Decision
2 / §3) interleave per anchor type. Sequencing is:

**Stage 1 — Admin UI skeleton + `venue_defaults` editor.** Single page
(`admin-venues.html` or similar, no build step per CLAUDE.md). Reads
all venues, edits `venue_defaults` columns (`camera_fov`, `motion`
jsonb, `ambient` jsonb, the 4 existing yaw/pitch columns). Backed by
new SECURITY DEFINER RPCs in a new migration (`db/034`-ish), gated by
`is_platform_admin`. No anchor editing yet; jsonb columns edited as
text initially. **First shippable: admin can edit existing venue
defaults via UI instead of "Set View Coordinates" + SQL.**

**Stage 2 — `audio` renderer impl + audio anchor authoring panel +
13 audio-only venues translated.** First vertical slice with real data
flowing UI → DB → registry → renderer → karaoke. Validates the
end-to-end architecture against the easiest type.

**Stage 3 — `particle` renderer impl + particle authoring panel +
~6 venues' particle effects translated.** Highest-risk structural
decision lives here — the particle vocabulary may need per-sub-shape
discrimination (`point-cloud`, `emitter`, `directional-rain`). The
admin UI's live preview makes the iteration tractable.

**Stage 4 — `spotlight` renderer impl + spotlight authoring panel +
stadium/festival/speakeasy spotlights translated.** Includes the
translation of the 2 Three.js 3D builders for stadium and speakeasy.
Three.js + canvas-2D variants both expressible through one spotlight
type with a renderer-side mode parameter (the `payload.context` field
introduced in A3). Also absorbs the 3D particle paths deferred from
A3's spec §0.2 re-staging (stadium 2000 THREE.Points phone-lights +
speakeasy 60 sphere-mesh smoke) — the 3D rendering context is solved
once by whoever is already in the Three.js builders. **Note:** the
original §7 text named stadium/disco/speakeasy; A3's foundation pass
clarified that disco's only spotlight-shaped effect is the floor-flash,
which is overlay-class (not spotlight) — see Stage 4.5. Festival's
lasers are in scope; festival's downbeat strobe is overlay-class and
defers to Stage 4.5.

**Sub-staged into A4a + A4b (2026-05-27).** Stage 4 was sub-staged in
planning chat 2026-05-27 because A4 surface is 1.5–2× A3's; the 3D
preview is genuinely new architectural territory (`admin-venues.html`
has zero Three.js code today); sub-staging isolates the 3D-preview-
surface risk to A4b so 2D spotlights can ship on the A3 precedent.

- **Stage A4a — 2D-canvas spotlight only. ✓ Shipped 2026-05-27.** Three
  kinds (`swept-beam-2d`, `pulsed-laser`, `light-shaft`); three
  anchors (stadium 4-beam count:4; festival 6-laser count:6; speakeasy
  3-shaft count:3); PERMIT multi-anchor rule per spec §4.5 / D2 (diverges
  from A2/A3 PREVENT). GSAP-equivalent motion via 4 pure-JS ease
  functions (`power1.inOut`, `power2.in`, `power3.out`, `sine.inOut`).
  Spec `docs/VENUE-ADMIN-UI-A4A-BUILD-SPEC.md`; verification log
  `docs/SESSION-LOGS/2026-05-27-A4a-verification-result.md`; migration
  `db/037_spotlight_anchor_seed.sql`.
- **Stage A4b — 3D spotlight + 3D particle extension + new Three.js
  admin preview surface. Queued.** Stadium 4 cone meshes + speakeasy
  40 candle Points as new spotlight kinds (`swept-beam-3d`,
  `point-light` — siblings to A4a's 2D kinds, not branches). Stadium
  2000 phone-lights + speakeasy 60 sphere-mesh smoke as 3D particle
  paths (extends `particle.js` or introduces sibling kinds
  `point-cloud-3d` / `volumetric-3d` — A4b spec decides). New Three.js
  preview surface in `admin-venues.html` (scaffolding: scene + camera
  + renderer + RAF loop — admin-venues.html currently has zero
  Three.js). A4b ships as its own propose-pause cycle.

**Stage 4.5 — `overlay` renderer impl + overlay authoring panel +
disco floor-flash + festival strobe translated.** A new anchor type
for screen-space visual overlays that aren't directional light
sources, informative markers, or particulate matter. Covers
gradient/rectangle/polygon screen overlays modulated by venue
scalars. The forcing function: A3's foundation pass surfaced that
disco's floor-flash has no home in the existing type vocabulary
(A3 spec §0.3 named "future callout/overlay type" but did not
schedule it); A4 surfaces festival's strobe in the same shape.
Stage 4.5 schedules that type explicitly. Adding `overlay` to the
db/032 vocabulary CHECK constraint is part of this stage's migration.

**Stage 5 — Remaining types** (`callout`, `pin`, `video`,
`link-hotspot`) + leftover venues. Long tail; ships per opportunity.

**Stage 6 — Per-app override editor (`anchor_patch` UX).** The
karaoke-specific override surface from `karaoke_venue_settings`. Lower
priority than Stages 1–5/7; ships in any order after Stage 1.

**Stage 7 — Switch karaoke to the data-driven path; retire
`AMBIENT_PROFILES` + `addVenueEffects3D` from `karaoke/stage.html`;
implement the venue modulator system.** Three-part stage, in order:
(1) switch karaoke's read path to consult the registry-resolved
renderer instead of the procedural closures (this is what earlier
docs referred to as "Block B" — it is part of Stage 7, not a separate
downstream stage); (2) verify every venue renders visually identically
through the data-driven path before any procedural code is removed;
(3) delete `AMBIENT_PROFILES` (including the 4 ghost venue keys —
space, forest, underwater, dead-dragonlair — which are dead procedural
code with no live consumers) and `addVenueEffects3D` in the same pass.
This stage also implements the venue modulator system — the real
registry-resolved drivers that replace particle.js + spotlight.js's
preview-oscillator heuristics, which the dormant stages don't need but
the canonical read-path does. Net ~−1500 LOC from `stage.html`.

**Stage 8 — Costume library + suggested-costumes editor.** Consumes
the Phase-3 costume seed migration described in
`PHASE-2-BUILD-SPEC.md` §6 (the migration that seeds `costumes` from
the existing `DEEPAR_EFFECTS` list + relocates `.deepar` files from
`karaoke/effects/` to `/costumes/`). Ships when karaoke's costume
rendering is rewired.

**Each stage is a propose-pause build cycle.** Stage 1 has its own
build spec (written first, citing this note as the direction).
Stages 2–4 each get a per-type addendum or mini-spec — the renderer
impl + its payload contract + the UI panel + the per-venue
translations all live in one document per type. Stages 5–8 are
lighter; each is a propose-pause when its time comes.

**Verification per stage.** Each translated venue must render visually
identically to its procedural ancestor (Stage 6's deletion is the
final verification). The admin UI's live preview is the iteration
loop; manual visual comparison + spot-checks are the PASS criteria.

---

## 8. Open items for the eventual spec

Items deliberately not settled here. The spec answers each by
inspecting the schema and live data at spec-writing time:

- **O1 — Per-parameter venue-identity vs. app-overridable enumeration.**
  See Decision 5 final bullet. Decided against the actual schema
  columns of `venue_defaults`, `karaoke_venue_settings`, and any
  future-`<app>_venue_settings` tables.

- **O2 — App-selector default state.** No-app-selected (shared-only
  view) vs. karaoke-selected (only app with overrides today).

- **O3 — Shared-parameter edit disambiguation default.** Default-to-override
  or default-to-venue-default. Per Decision 5 the working assumption
  is default-to-override (lower-risk), but the spec confirms.

- **O4 — Time Travel Studio reuse audit.** See Decision 4's FLAG. An
  investigation precedes part (b)'s spec; this direction doesn't
  prejudge the outcome.

- **O5 — Per-stage verification protocol.** §7 says each translated
  venue must render visually identically. What constitutes acceptable
  "identical" — pixel-comparison, frame-rate-equivalent, human
  spot-check? Decision lands per-type with the renderer-impl build
  spec.

- **O6 — Costume library authoring** is part of Part (a) per
  PHASE-2-BUILD-SPEC.md §7 but not detailed in this direction note;
  the spec inherits §7's framing on the costume library + the
  per-venue suggested-costume list.

---

## 9. References + dependencies

- `docs/PHASE-2-BUILD-SPEC.md` §7 — the original Phase-2-fast-follow
  scope sketch for the admin UI. This direction note builds on §7
  rather than superseding it; §7's surface description ("editing
  camera/motion/ambient, authoring and positioning anchors, managing
  the costume library and per-venue suggested lists, and editing
  per-app override patches") remains the working scope for Part (a).
- `docs/PHASE-2-BUILD-SPEC.md` §5.4 "Phase-3 translation cost" — the
  procedural-to-data translation flagged for Phase 3. Plan B (this
  note's revised Decision 1 / §2) executes that translation in Phase
  3 via the §7 hybrid sequencing, through the admin UI.
- `docs/UNIFIED-APP-PLAN.md` §5 — phase sequencing authority. **No
  UAP §5 amendment is required for this direction note's revised
  Plan B framing.** UAP §5 governs the numbered phases; the Venue
  Admin UI is not a numbered phase, and the venue translation work
  itself is implicit in *"Phase 3 — karaoke onto the new model"*
  (made explicit by `PHASE-2-BUILD-SPEC.md` §5.4 "Phase-3 translation
  cost"). Plan B doesn't add a new phase or rename an existing one;
  it sequences work within Phase 3's existing scope.
- `db/032_venue_abstraction_schema.sql` — the schema this UI edits.
  Especially "Design decision 2" (per-app overrides via
  `<app>_venue_settings`) and the `venue_anchors` payload comment
  (lines 283–287) on the unspecified per-type payload shape.
- `shell/venue-settings.js` — the resolver + save helpers the UI
  reads and writes through.
- `shell/venue-registry.js` — the registry the UI does NOT touch
  directly (renderer impls are Phase 3 / post-Phase-5 code work).
- `karaoke/stage.html:4584–4994` — `AMBIENT_PROFILES` (the procedural
  source for the 10 effect venues + the 13 audio-only entries; ~3
  venues are silent — see §2).
- `karaoke/stage.html:2848–2940` — `addVenueEffects3D` + the two 3D
  builders (`buildStadiumEffects3D` and `buildSpeakeasyEffects3D`,
  one each for the two of the 10 procedural venues that have 3D
  effects).
- `venues.json` — the 26-venue inventory Part (a) scopes against.
- `CLAUDE.md` "Adding a venue" — the file-naming / folder convention
  Part (b)'s asset-generation pipeline targets.
- ROADMAP.md (Active section) — the venue admin UI is described as
  Phase-2 fast-follow with a "before Phase 3 karaoke rewire" sequencing
  lean. Plan B locks that lean and reframes it as Phase-3 scope
  (the admin UI mitigates Phase 3's translation risk). A small
  companion ROADMAP edit lands with this revision; see §10 below.

---

## 10. Implications worth flagging

- **ROADMAP.md Active section updates lightly.** The existing entry
  ("Venue admin UI — Phase 2 fast-follow") is already Plan-B-shaped:
  it sequences admin UI before Phase 3 karaoke rewire and names the
  translation as Phase 3 scope. The companion edit (proposed
  alongside this revision) drops the "(revisitable)" hedge from the
  sequencing lean, explicitly names Plan B, and cross-references this
  note's §7 sequencing.

- **The first admin-UI build spec is the next deliverable.** It
  covers Stage 1 + folds in Stage 2 (audio renderer + 13 audio-only
  venues as the first vertical slice). Stages 3–5 get per-type
  addenda. The build spec cites this note as the direction it
  executes against.

- **No db migration is implied by this direction note.** Plan B's
  migrations are scheduled per stage (`db/034` for Stage 1's admin
  RPCs, possibly a small audio-seed migration in Stage 2, no further
  schema migrations expected — db/032's existing tables cover the
  full venue model).

- **No code change is implied by this direction note.** Pre-spec
  planning artifact only.

- **The `df49366` history is preserved as background.** The
  wrap-as-legacy reasoning recorded in that commit's version of §2 is
  a useful counterfactual for future readers asking "why didn't we
  defer the admin UI?" — the answer is in `git show df49366`. The
  reversal rationale is in this note's status header.

---

## End of direction note
