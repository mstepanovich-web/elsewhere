# Venue Admin UI — Direction Note

**Status:** Pre-spec direction, not a build spec. Captures decisions for
the future Venue Admin UI work so the eventual spec starts from them
rather than re-deriving them. Nothing is built or scheduled by this
document.

**Sequencing:** Post-Phase-5. This document records the decision to
DEFER the Venue Admin UI past its earlier "Phase-2 fast-follow / before
Phase 3" position in ROADMAP.md. Karaoke onto the venue model
(Phase 3) proceeds without the admin UI via the wrap-as-legacy escape
hatch described in §2.

**Companion docs:** Builds on `docs/PHASE-2-BUILD-SPEC.md` §7 (the
original admin-UI scope sketch) and on the schema settled in
`db/032_venue_abstraction_schema.sql`. Does not supersede §7 — it
records the post-Phase-5 framing for what an eventual §7-style spec
would settle.

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

## 2. Decision 1 — Venue migration approach: wrap-as-legacy, defer real
translation to post-Phase-5

**Venue inventory and what migrates how.** Of the 26 total venues in
`venues.json`:

- **~23 have `AMBIENT_PROFILES` entries** in `karaoke/stage.html:4584–4994`,
  split into:
  - **10 venues with bespoke procedural effect code** — wrapped as
    legacy renderers in this approach. The 10 are: `default`, `stadium`,
    `disco`, `space`, `speakeasy`, `honkytonk`, `festival`, `forest`,
    `dragonlair`, `underwater`. Two of these — `stadium` and `speakeasy`
    — also have separate 3D effect builders
    (`buildStadiumEffects3D` / `buildSpeakeasyEffects3D` in
    `karaoke/stage.html:2856–2940`); those 3D builders are wrapped the
    same way as the `anim()` functions, not as additional venues.
  - **13 audio-only entries** with `anim: null` and just
    `playAmbientMp3('<venue>')` — mechanical SQL migration.
- **~3 venues have no `AMBIENT_PROFILES` entry at all** — the
  `AMBIENT_PROFILES[venueId] || null` fallback at line 4998 returns
  null silently.

So: **10 + 13 + ~3 = 26.** The 10 and the 13 are disjoint sets; stadium
and speakeasy are members of the 10, not a separate group.

Phase 3 adopts the venue model via two paths, neither of which requires
the admin UI:

- **The 10 procedural effect venues.** Wrapped as-is — the bespoke
  `AMBIENT_PROFILES[venueId].anim()` functions and the 3D effect
  builders for stadium and speakeasy stay as live JavaScript, registered
  to the renderer registry (`shell/venue-registry.js`) as single per-venue
  "legacy" implementations. **Visual fidelity is bit-for-bit
  preserved.** No payload contracts are baked in; no anchor records are
  authored. The procedural code keeps running; the registry mechanism
  becomes the dispatch surface but the contents are still procedural
  underneath.

- **The 13 audio-only entries.** Migrate mechanically via a single SQL
  migration that inserts 13 `venue_anchors` rows of `type='audio'`,
  one per venue, with a stable minimal payload shape
  (`{file: 'venueX'}` or similar — exact shape settled by the migration
  author against the renderer impl). This is the only data-driven
  portion of Phase 3's venue work.

The ~3 venues with no `AMBIENT_PROFILES` entry require no migration —
they have no procedural code to wrap and no audio to translate. They
remain "silent" under the venue layer just as they are silent today.

**Post-Phase-5 translation work** — the real procedural-to-data
translation, where each anim function decomposes into reusable
renderer impls + parameterized anchor records — is paired with the
admin UI. Authoring those records with a working preview affordance is
the lower-risk path; authoring them by hand without one risks baking
in premature payload contracts (the risk surfaced in this session's
read).

**What this commits to:**
- Phase 3 ships karaoke functionally on the new venue layer.
- The 10 procedural effect venues (two of which — stadium and
  speakeasy — also have 3D effect builders wrapped the same way)
  remain on procedural code behind the registry.
- The renderer-API contract (per
  `shell/venue-registry.js:63–72`, deliberately unspecified in Phase 2)
  is settled post-Phase-5 by the admin UI's authoring pass, not by
  Phase 3.

**What this defers:**
- The reusable-renderer-impl decomposition (concerns the 10
  procedural venues).
- The per-venue payload-shape decisions.
- The visual-iteration loop that would have been the admin UI's value
  for those decisions.

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

When the post-Phase-5 translation converts the 10 procedural effect
venues from wrapped legacy renderers into data + reusable renderer
impls, **the existing parameter values carry over into the authored
anchor records.** Beam counts, sweep timings, GSAP easing curves,
particle counts, hue values, alpha ranges, audio file references —
all of these are already in the procedural code and become the
starting values for the migrated records.

**Migrated venues come over pre-populated and visually identical** to
their procedural ancestors, by construction. The admin UI then becomes
the surface for iterating those values against the renderer impls
that took over from the procedural functions.

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

## 7. Open items for the eventual spec

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

- **O5 — Migration affordance for the 10 procedural venues.** When the
  post-Phase-5 admin UI authors records that supersede the wrapped
  legacy renderers, does the wrapping wrapper retire automatically
  per venue (cutover), or stay in place as a fallback (parallel
  authoring), or get a per-venue toggle? Decision lands with the
  admin UI's own integration story, not in this direction note.

- **O6 — Costume library authoring** is part of Part (a) per
  PHASE-2-BUILD-SPEC.md §7 but not detailed in this direction note;
  the spec inherits §7's framing on the costume library + the
  per-venue suggested-costume list.

---

## 8. References + dependencies

- `docs/PHASE-2-BUILD-SPEC.md` §7 — the original Phase-2-fast-follow
  scope sketch for the admin UI. This direction note builds on §7
  rather than superseding it; §7's surface description ("editing
  camera/motion/ambient, authoring and positioning anchors, managing
  the costume library and per-venue suggested lists, and editing
  per-app override patches") remains the working scope for Part (a).
- `docs/PHASE-2-BUILD-SPEC.md` §5.4 "Phase-3 translation cost" — the
  procedural-to-data translation flagged for Phase 3, now deferred to
  post-Phase-5 via Decision 1's wrap-as-legacy escape hatch.
- `docs/UNIFIED-APP-PLAN.md` §5 — phase sequencing authority. **No
  UAP §5 amendment is required for this direction note.** UAP §5
  governs the numbered phases of the unified-app workstream
  (Phase 0 → Phase 5, then wellness/worlds greenfield). The Venue
  Admin UI is not a numbered phase — it has been a Phase-2
  fast-follow in ROADMAP framing, and this note reclassifies it to
  post-Phase-5 work. Both positions sit *outside* §5's named-phase
  scope, so neither the previous framing nor this deferral touches
  §5's text. (Contrast with the earlier propose-pause amendment that
  added Items 5/6 to §5's Phase 3 and Phase 4 entries: that
  amendment WAS required because Items 5/6 are named scope WITHIN
  Phase 3 and Phase 4. This note has no analogous edit to make.)
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
- ROADMAP.md (current Active section) — the venue admin UI is
  currently described there as Phase-2 fast-follow / pre-Phase-3.
  This direction note implies a ROADMAP edit (move it from Active
  to post-Phase-5); that edit is OUT OF SCOPE for this document and
  ships separately.

---

## 9. Implications worth flagging

- **ROADMAP.md Active section needs updating.** Currently lists the
  Venue admin UI as Phase-2 fast-follow with a "before Phase 3 karaoke
  rewire" lean. Once this direction note is committed, the ROADMAP
  Active section should move to "Phase 3 — karaoke onto the new
  model" (with the wrap-as-legacy approach noted) and the admin UI
  moves to a post-Phase-5 Queued or Future entry. That edit is a
  separate propose-pause doc-edit task.

- **Phase 3's karaoke build spec gains a new bullet.** When written,
  the Phase 3 karaoke build spec must explicitly call out the
  wrap-as-legacy approach for the 10 procedural venues + the
  mechanical migration for the 13 audio-only entries, AND must NOT
  attempt the data-driven translation for the procedural venues.
  Calling that out in the spec prevents a future Phase-3 author from
  re-discovering the translation cost and accidentally taking it on.

- **No db migration is implied by this direction note.** The schema
  in db/032 is already settled and applied; nothing in this document
  requires schema change. The admin UI eventually authors against
  the existing schema.

- **No code change is implied by this direction note.** Pre-spec
  planning artifact only.

---

## End of direction note
