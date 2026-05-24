# Elsewhere — Phase 2 Build Spec: The Venue Abstraction

**Status:** Draft for review, revision 2 (pre-implementation). This is a
structural design document, not migration or application code. It is the
Phase 2 counterpart to `docs/PHASE-1-BUILD-SPEC.md`. Revision 2 folds in
the Claude Code repo-verification consultation: the `venues.json`
reframe (§4.2), optional anchor position (§3.1), three settled open
questions (§9), and precision corrections throughout.

**Phase context.** Phase 2 per `docs/UNIFIED-APP-PLAN.md` §5: "venue
extraction — pull venue rendering out of the karaoke stage into a shared
shell renderer; make the venue registry cross-app." This spec scopes that
work, and — per the planning-chat reframe recorded in §2 below —
broadens it from a literal code-lift into the construction of a complete
cross-app **venue abstraction**.

**What Phase 2 is NOT.** Phase 2 builds the abstraction. It does **not**
rewire karaoke onto it (that is Phase 3) and does **not** integrate games
(the DEFERRED entry's parts 2–3, a later session). Karaoke's existing
inline venue code in `karaoke/stage.html` is left running and untouched.
The new venue layer ships **dormant** — built, tested in isolation, with
no live consumer until Phase 3.

---

## 1. Why this document supersedes part of the canonical Phase 2 spec

The canonical three-part Phase 2 breakdown is `docs/DEFERRED.md` "Venues
as cross-app service (games, wellness, future apps)". Its part 1 says:

> "Extract 360° panorama rendering from `karaoke/stage.html` into
> `shell/venue-renderer.js`. … **Keep karaoke's ambient effects
> separate** (that's the DEFERRED 'shell/venue-effects.js' entry)."

**This spec supersedes the "keep ambient effects separate" directive.**

Rationale: the DEFERRED entry was written in Session 5 planning
(2026-04-23), before the cross-app venue model matured. It assumed the
3D venue effects and ambient system were *karaoke-specific* and should be
left behind in karaoke when the panorama renderer was lifted out. They
are not karaoke-specific — they are **venue-specific**. A stadium's
sweeping spotlights and crowd-cheer ambience belong to *the stadium*,
not to *karaoke*; they live in `karaoke/stage.html` today only because
karaoke is the only app that currently exists. Under the cross-app
model, when games renders the stadium it should get the stadium's
spotlights and ambience, because that is what the stadium *is*.

Therefore the venue abstraction owns effects, ambient, immersion, and
informative overlays as **venue attributes**, not as karaoke code left
behind. The one-line PHASE1-NOTES IOU "Extract ambient venue effects
into `shell/venue-effects.js`" is **absorbed into this spec** rather than
remaining a separate deferred effort.

The supersession is deliberate and recorded here so a future reader who
finds the contradiction knows which document wins: **this one.** When
this spec is committed, the DEFERRED "Venues as cross-app service" entry
should gain a pointer to it.

---

## 2. The model — what a venue is

A **venue** is a 360° environment that any Elsewhere app can load. The
core insight, and the thing this whole abstraction is built around:

> **Only one thing about a venue is truly shared and never overridden:
> the 360° skybox image.** Everything else — camera framing, ambient
> sound, motion, 3D/2D effects, informative overlays, deeplinks,
> suggested costumes — is a **defaulted, per-app-overridable property.**

So a venue is: a skybox, plus a **default presentation profile**, where
every element of that profile may be overridden by the app rendering it.
Karaoke can run the stadium with its default spotlights and ambience;
games can run the *same stadium skybox* with different ambience,
different effects, different framing — because games is a different
experience over the same space.

### 2.1 The four layers

1. **The skybox layer.** The 360° background. The sole always-shared
   constant. One per venue. The background source is **typed** —
   `image` today, `video` reserved (see §8) — so a future 360°-video
   venue is not a redesign.

2. **The venue-attributes layer.** Everything else, as
   default-plus-override properties: camera framing, motion/rotation,
   ambient audio, and the **anchor set** (see §3). Resolved per-app via
   a generalized resolver (§5).

3. **The costume layer.** Costumes attach to *composited users*, not to
   sphere positions — so they are a separate concern from anchors. A
   reusable costume library; each venue carries a *suggested* costume
   list; the user may pick from the full library. Premium-gated.
   Rendering is app-owned. (§6.)

4. **The rendering layer.** How an app draws a resolved venue and what
   it composites onto it (karaoke: a singer + lyrics + tray UI; games:
   player tiles or insertion). **App-owned. Never shared.** Phase 2 does
   not build any app's rendering layer — karaoke's stays inline (Phase
   3), games' is a later session.

Phase 2 builds layers 1, 2, and 3, plus the resolver. Layer 4 is each
app's own work in its own phase.

### 2.2 Venue, variant, scene — three distinct concepts

Planning discussion surfaced that the word "venue" had been carrying
three different meanings. They must be kept separate, because only the
first is a Phase-2 entity.

- **Venue** — a reusable core 360° space: a skybox plus its default
  presentation profile. App-agnostic; knows nothing about who uses it.
  This is "venue" everywhere in this spec, and it is what Phase 2
  builds.

- **A per-app-resolved venue** (e.g. "karaoke's stadium") — *not a
  stored entity.* It is the core venue with an app's override layer
  applied, assembled at resolve time by the resolver (§5). "Karaoke's
  stadium" has no row of its own; it is `core venue ⊕ karaoke's
  overrides`, computed. Nothing to name, nothing to store.

- **Venue variant** — a *persisted, named, owned* derivative of a core
  venue: a creator branches the core stadium and saves their own
  version, and a core venue may have N such variants. This **is** a
  real first-class entity — but it is a **future** concept. Phase 2
  does **not** build venue variants. Phase 2's only obligation is not to
  *foreclose* them: because a venue id is a plain id, a future migration
  can add a `parent_venue_id` column and variants become possible with
  no redesign. Noted as forward-compat; built later.

- **Scene** — an item in a *sequenced app* (Time Travel, Worlds): such
  an app is fundamentally an ordered list of scenes. A scene *may*
  reference a venue (use it as its space) or may not (a title card, a
  pure-video interstitial). A scene is an **app-layer** concept — the
  venue layer does not know scenes exist. The dependency points one
  way: scene → venue, never back. Scenes are out of venue-layer scope
  entirely; they belong to the individual sequenced app.

The short version: **venue** = a reusable space (Phase 2). **Variant** =
a saved branch of a venue (future, not foreclosed). **Scene** = an item
in an app's sequence that optionally uses a venue (app-layer, not the
venue layer's concern).

---

## 3. The anchor system — the unified core

The single most important structural decision in this spec. Earlier
drafts treated effects, informative overlays, and deeplinks as three
separate registries. Examination of the Time Travel Studio data model
(`content-edits.json`, schema_version 5 — see §3.4) showed the truer
structure: they are **one model.**

An **anchor** is a typed element pinned to a position on the 360°
sphere, with an optional time window, an optional navigation link, and a
type-specific payload. Effects, overlays, immersion accents, media, and
deeplinks are all **anchor types** — not separate systems.

### 3.1 The anchor record — base fields

Every anchor, regardless of type, carries:

| Field | Type | Notes |
|---|---|---|
| `id` | string | Stable unique id (TTS uses `anc_xxxxxx`). Stable id is **required** — it is what the per-app override patch (§5.3) keys on. |
| `type` | enum | The anchor type — see §3.2. Selects the renderer + the payload shape. |
| `yaw_deg` | number \| null | Spatial position — degrees. Same yaw/pitch coordinate space the existing venue system already uses (`venues.json` `startYaw`/`staticYaw`, `venue-settings.js`, the karaoke camera). **No new positioning concept.** **Nullable** — see the screen-space note below. |
| `pitch_deg` | number \| null | Spatial position — degrees. Nullable, paired with `yaw_deg`. |
| `label` | string | Display/author label. May be empty. |
| `start_sec` | number \| null | Temporal window start. `null` = present from scene start. |
| `end_sec` | number \| null | Temporal window end. `null` = persists. Both null = always present. |
| `link` | object \| null | If non-null, this anchor is a navigable hotspot — see §3.3 (deeplinks). |
| `payload` | object | Type-specific fields — see §3.2. |

`yaw_deg`/`pitch_deg` + `start_sec`/`end_sec` together mean an anchor is
a *spatially-positioned, optionally-time-windowed* element. The temporal
window is first-class and proven by TTS data (both anchors and TTS
"stats objects" carry `start_sec`/`end_sec`).

**Spatial position is optional — the screen-space rule.** Most anchors
are pinned to a point on the sphere (`yaw_deg`/`pitch_deg` set). But some
venue effects are *screen-space*, not sphere-space — e.g. drifting 2D
particle overlays that float across the viewport regardless of where the
camera points. The Claude Code consultation found exactly this in
karaoke's current `AMBIENT_PROFILES`: it mixes sphere-pinned 3D effects
(a stadium spotlight at a real yaw/pitch) with full-screen 2D particle
canvases that have no sphere position at all. The rule: **`yaw_deg` and
`pitch_deg` are both nullable, and both-null means the anchor is
screen-space — rendered as a viewport overlay, not pinned to the
sphere.** A `particle` anchor with null position is a screen-space
particle layer; the same `particle` type with a position is a localized
in-scene emitter. This keeps screen-space effects inside the one unified
anchor model rather than fracturing the model into a separate
non-anchor layer.

### 3.2 The anchor type vocabulary

Phase 2 ships the abstraction with this initial type set. The set is
**extensible** — adding a type is adding a renderer + a payload shape,
not changing the model.

| Type | Category | Renders as | Payload (illustrative) |
|---|---|---|---|
| `callout` | informative overlay | text card pinned at yaw/pitch | text content, styling hint |
| `pin` | informative overlay | a marker/dot, optional label | marker style |
| `spotlight` | effect (3D) | a Three.js light in the scene | color, intensity, sweep |
| `particle` | effect (3D/2D) | a particle emitter | particle profile id, density |
| `audio` | media | a positional/ambient audio clip | clip ref, source (`tts`/`recorded`/`uploaded`), duration |
| `video` | media | a video surface / modal | clip ref, poster ref, duration |
| `link-hotspot` | navigation | a tappable region (a `callout`/`pin` whose `link` is set is equivalent) | — (uses the `link` field) |

Notes:
- `callout`/`pin` are the **informative overlay** family (item 4 in the
  planning discussion — text overlays, callouts, voice-over text).
- `spotlight`/`particle` are the **effects** family (item 1 — 3D and 2D
  immersion effects). The DEFERRED-superseded "ambient effects" land
  here.
- `audio`/`video` are **media anchors** — TTS supports `tts`,
  `recorded`, and `uploaded` audio sources and `uploaded` video.
- A `_broken` validity flag exists in TTS data; the venue layer should
  carry an equivalent so a missing asset degrades gracefully rather
  than throwing.

### 3.3 Deeplinks — `link` is an anchor property, not a separate system

Item 3 from the planning discussion ("navigate from one venue to
another — backstage at a concert venue") is **the `link` field.** An
anchor with a non-null `link` is a navigable hotspot: tapping it
navigates somewhere. TTS already reserves this exact field on every
anchor (`link`, currently always `null` in TTS data — reserved, not yet
used).

`link` has **two distinct kinds of destination**, and they are kept
distinctly named — *not* merged into a generic `target` — because they
point at two different layers of the system (per the venue/scene
distinction in §2.2):

- **`{"venue_id": "..."}`** — navigate to another *venue*. The venue
  layer **can resolve this itself** — it knows venues.
- **`{"scene_id": "..."}`** — navigate to a *scene* in a sequenced app.
  A scene is an app-layer concept (§2.2); the venue layer **cannot**
  resolve a scene id. It treats the value as **opaque** and hands it to
  the owning app, which maps the scene to its underlying venue and
  content.

They are not interchangeable: a scene id is a higher-level reference
that itself transitively references a venue. The column is `jsonb` and
accepts either shape; the resolution responsibility differs by kind —
venue-level links resolved by the venue layer, scene-level links by the
app. (A `{"type": ...}` discriminator may be added if a third link kind
ever appears; for Phase 2 the two named shapes suffice.)

Consequence for the data model: venues form a **graph** via `venue_id`
links. The link edges are anchor properties, so they live wherever the
anchor set lives — the `venue_anchors` table (§4).

### 3.4 What the anchor model is taken from — and the scope line

The anchor record above is derived from the Time Travel Studio export
format (`content-edits.json`, `schema_version: 5`): typed anchors with
`yaw_deg`/`pitch_deg`, `start_sec`/`end_sec`, `label`, `link`, and
type-specific payload; per-stop `camera {start_yaw_deg, start_pitch_deg}`
and `rotation {mode, custom_deg_per_sec}`.

**Coupling disclosure.** The venue layer's anchor base-field set is
*modeled on* TTS `schema_version: 5` — it is not dynamically bound to
it. TTS is an external side-project tool, not in `elsewhere-repo`; the
consultation correctly noted the venue layer cannot verify TTS's schema
at runtime. The venue layer therefore pins its own anchor field set as
its own canonical definition; a future TTS schema bump does **not**
auto-propagate. If a TTS import path is ever built (§7), that import is
responsible for mapping whatever TTS version it reads onto the venue
layer's pinned field set.

**Scope line — important.** The venue abstraction takes the *anchor data
model* from TTS. It does **not** absorb TTS's narration scripts, era
transitions, mode/voice sequence model, or 61-stop structure — that is
Time Travel-the-app's content model, and Time Travel is a future
greenfield app per UAP §5. The venue layer provides the anchored-element
*substrate*; an app like Time Travel is one *consumer* that supplies its
own sequence and scripts on top. Phase 2 must not let the venue
abstraction bloat into "TTS's data model."

**The full TTS inventory — what is a venue attribute and what is not.**
Planning discussion walked every TTS-derived concept through the
venue/scene test (§2.2: does it describe a *space*, or a *scene*?). The
result:

*In the venue layer* — these describe the space:
- the **anchor model** (typed anchors → `venue_anchors`);
- **camera** (default yaw/pitch/fov);
- **rotation/motion** (the `jsonb` motion attribute — §4.5);
- **ambient audio** (the `ambient` attribute);
- **text overlays** — these are *not* a separate attribute; a text
  overlay *is* a `callout`/`pin` anchor (§3.2), already inside the
  anchor system. (TTS scopes overlays by mode — that is the §3.5
  variant axis, deferred.)

*Not in the venue layer* — these are scene-level / app-level content,
not space description:
- **Stats objects** (TTS's `{universe_age, temperature, …}` records).
  A stat is information *about a moment in a sequence*, not a property
  of a space. The venue layer borrowed only their *structural lessons*
  — the `start_sec`/`end_sec` time window and the `render` discriminator
  — into the anchor model; the stats objects **themselves are not a
  venue attribute** and there is no `venue_stats` table. They belong to
  a future sequenced-app phase.
- **Narration** — per-venue text narrative and its text-to-speech
  conversion (text, voice selection, the TTS-generation pipeline). This
  is app-level content built *around* a venue, not a venue attribute.
  The venue layer offers the `audio` anchor type as an optional
  attachment point if an app wants its generated narration audio
  spatialised in the scene — but the venue layer owns no narration
  text, voice, or pipeline.
- TTS's **narration mode/voice scoping, era transitions, and 61-stop
  sequence** — the sequenced-app content model, never venue-layer.

The principle the test produced: **spatial things are venue attributes;
content things are app/scene concerns.** Every ambiguous TTS concept
sorted cleanly on that line.

### 3.5 Variant-scoping (forward-compatibility note)

TTS scopes its overlays by **mode** (fast/informative/comprehensive) —
the same stop has a different overlay set per mode. The venue layer's
anchor set is resolved per-app already (§5); the spec should ensure the
resolution mechanism is general enough that **additional variant axes**
(mode, and others) can be added later without reshaping the model.
Phase 2 implements the per-app axis; it should not *foreclose* a
per-mode axis. This is a "design the resolver generally" note, not a
"build per-mode resolution now" requirement.

---

## 4. Where venue data lives — defaults and overrides

**Decision (confirmed in planning):** venue content is editable through
an admin UI without a code deploy. That dictates the storage model.

### 4.1 Defaults live in the database

The venue's **default presentation profile for the new attributes** —
default camera, default rotation/motion, default ambient, the default
anchor set, the suggested-costume list — lives in **Supabase tables**,
editable by an admin UI. These attributes are new (they have never been
in `venues.json`); they are DB-native from the start.

Rationale: the requirement is "adjust any default item via a UI, no code
change unless it's a structural/scale change." DB-backed defaults satisfy
that; file-backed defaults would require a commit + deploy for every
content edit.

This applies to the *new* attributes only. The *existing* `venues.json`
fields (`startYaw`, `staticYaw`, etc.) keep their current behaviour —
`venues.json` baseline, `venue_defaults` admin override. §4.2 explains
why the file is not disturbed.

### 4.2 `venues.json` keeps its current fields; new attributes are DB-native

**Revision-2 correction.** Revision 1 of this spec proposed shrinking
`venues.json` to a four-field bootstrap (`id`, `name`, skybox,
`category`). The Claude Code consultation found this **breaks
`karaoke/stage.html`** and contradicts the §10 "no karaoke adoption"
non-goal: stage.html actively reads `icon`, `startYaw`, `staticYaw`,
`staticPitch`, and `soundId` from `venues.json` today (verified, with
line references, in the consultation). Dropping those fields would break
karaoke the moment Phase 2 shipped — which Phase 2 is explicitly not
allowed to do.

The reframe — and it is a reframe, not a redesign:

- **`venues.json` keeps every field its current readers use.** It is
  **not shrunk.** `id`, `name`, `icon`, `category`, `skyboxId`,
  `startYaw`, `staticYaw`, `staticPitch`, `soundId`, and the top-level
  `baseUrl`/`soundsUrl`/`categories` keys all stay exactly as they are.
  Every pre-Phase-3 reader (`karaoke/stage.html`, `karaoke/singer.html`)
  keeps working untouched. This honors the §10 non-goal.
- **The new venue attributes are DB-native from the start.** Anchors,
  ambient configuration, rotation/motion, and per-venue costume
  suggestions are *new* — they have never been in `venues.json`, so
  nothing is being moved out of the file. They are authored directly in
  the DB (UI-editable, §4.1, §7).
- **DB-backed defaults (§4.1) applies to the new attributes.** That is
  what makes them UI-editable without a deploy — the original
  requirement. The *existing* yaw/pitch attributes keep their current
  behavior unchanged: `venue_defaults` holds admin-tuned overrides,
  `venues.json` remains the baseline fallback. That fallback is
  load-bearing — CLAUDE.md documents `venues.json` as the
  DB-loss-survival baseline; keeping the file wide preserves that
  doctrine.

So the storage model is **two-tier, not "shrink the file"**: existing
attributes resolve `venue_defaults` → `venues.json` (as today); new
attributes resolve `<app>_venue_settings` patch → DB defaults, with the
thin always-available baseline being just "the venue exists and has a
skybox" (which `venues.json` already provides via `id` + `skyboxId`).
A venue still renders if Supabase is briefly unreachable — it renders as
its bare skybox with no anchors/ambient, which is the correct graceful
degradation.

No field is removed from `venues.json` in Phase 2. The file's
*long-term* shape (whether the existing yaw/pitch fields eventually
migrate fully into the DB) is a Phase-3+ question, decided when karaoke
is rewired and the file's readers change. Phase 2 leaves it alone.

### 4.3 Per-app overrides extend the existing pattern

Per-app overrides extend the **existing `<app>_venue_settings` table
pattern** (`karaoke_venue_settings` exists today for yaw/pitch;
`games_venue_settings` etc. follow). The existing resolver in
`shell/venue-settings.js` (`resolveVenueYawPitch`, a four-level chain:
per-app override → DB default → `venues.json` → fallback) is
**generalized** (§5) rather than replaced.

### 4.4 Anchor-set overrides are PATCHES, not wholesale replacement

**Decision (confirmed in planning).** Scalar attributes (ambient
choice, rotation, camera) override by replacement — the existing
scalar model. The **anchor set is a collection**, and an app's override
of it is a **patch**, not a wholesale replacement:

- An app's anchor override stores **deltas** keyed by anchor `id`:
  *add* this anchor, *suppress* that one, *modify* this one's fields.
- The resolver computes the effective anchor set as: venue default
  anchor set + app patch → effective set.

Rationale: wholesale replacement causes **drift** — if games copied the
stadium's whole anchor list to change one anchor, later improvements to
the stadium's default anchors would never reach games. Patch avoids
drift; later default changes flow through except where an app has
explicitly patched. Anchors carry stable `id`s (§3.1), so patch is
tractable. Drift-avoidance directly serves the "scalable, low-maintenance"
goal.

**Canonical patch shape (settled).** The patch is stored as one `jsonb`
column on the per-app override table, with exactly three keys:

```
{
  "add":      [ <full anchor records> ],
  "suppress": [ "<anchor_id>", ... ],
  "modify":   { "<anchor_id>": { <field overrides> } }
}
```

`add` carries whole new anchor records the app introduces; `suppress`
is a list of default-anchor ids the app hides; `modify` is keyed by
default-anchor id and carries only the fields that app changes. This
shape is **settled, not provisional** — unlike rotation/ambient (whose
consuming renderer is far off), the patch is consumed by the
**resolver**, which is the very next module built after the Phase-2
migration. The resolver must implement exactly this shape. (The `jsonb`
column itself is unconstrained at the DB level — the shape is enforced
by the resolver, not a `CHECK` constraint.)

### 4.5 New database tables (schedule for `db/032+`)

Phase 2 therefore **does** carry a schema migration — note this is a
change from the initial read of Phase 2 as "client-side only, no
migration." The DB-backed-defaults decision causes it. The migration(s)
land as `db/032` onward, following the established idempotent
numbered-migration pattern, applied to prod via Supabase SQL Editor and
recorded in `db/MIGRATIONS_APPLIED.md`.

The migration is **net-new and additive** — new tables, plus additive
columns on `venue_defaults` and `karaoke_venue_settings`. No existing
column is dropped or altered; this is not a cutover. Structural intent
(final DDL is the migration itself, reviewed before apply):

- **`venue_defaults` — extended** (additive columns; the existing four
  yaw/pitch columns untouched). New columns: a default `camera_fov`; a
  **`jsonb` `motion` column** (see below); a **`jsonb` `ambient`
  column**; and a reference to the venue's default anchor set.
- **`venue_anchors` — new table.** One row per default anchor, carrying
  the §3.1 base fields. `yaw_deg`/`pitch_deg` are **nullable** (the
  §3.1 screen-space rule). `payload` is a **`jsonb` column** (per OQ2,
  now settled). `link` is a nullable `jsonb` column (§3.3). A validity
  flag (TTS's `_broken` equivalent) is present. FK to the venue with
  **`ON DELETE RESTRICT`** — see the deletion note below.
- **`karaoke_venue_settings` — extended** (the `<app>_venue_settings`
  pattern). Additive columns for all-attribute overrides, including a
  **`jsonb` anchor-patch column** holding the §4.4 patch. Future
  `games_venue_settings` etc. follow the same column shape via
  copy-the-pattern migrations.
- **`costumes` — new table**, and **`venue_suggested_costumes` — new
  association table** (§6). `costumes` ships **empty** in Phase 2 (§6).
  `venue_suggested_costumes` is a lean association table (venue id,
  costume id, `position`) with no audit columns. Both FKs in it use
  **`ON DELETE RESTRICT`**.
- **`jsonb` is settled (OQ2)** for: anchor `payload`, the anchor patch,
  `ambient`, `motion`, and `link`. The attributes whose parameter set
  varies by type are naturally `jsonb`; the trade-off (not
  content-queryable without an expression index) is accepted.
- **`motion` is a `jsonb` column**, not a text+numeric pair. It holds
  `{type, ...params}` — `static` needs no params, `orbit` carries a
  numeric speed, a future `elliptical` carries radii + tilt — so motion
  types with differing parameter sets need no schema change. Recognized
  types now: `static`, `orbit`. Speed is always stored as a number.
- **`ON DELETE RESTRICT` on every venue FK.** Deleting a venue is
  *blocked* by the database while dependent anchors / costume
  associations exist — the admin must clear them first. Rationale:
  anchors are authored content; a venue delete must be deliberate and
  scoped, not a silent cascade. `RESTRICT` is the database-level
  backstop beneath the admin UI's confirm dialog (a UI dialog protects
  against a misclick; `RESTRICT` protects against a confirmed delete
  whose scope the admin did not realise, and holds regardless of what
  code path issues the delete).
- RLS: read paths follow the existing venue-settings read pattern
  (the consultation confirmed `venue_defaults` / `karaoke_venue_settings`
  use a public `select using (true)` read policy and an
  `is_platform_admin` write policy); writes are admin-gated (§7).
  Mutation RPCs (SECURITY DEFINER, per repo doctrine) are a **separate
  later task** — the Phase-2 migration is **schema only** (tables,
  columns, indexes, RLS, seed); it does not create the RPCs.

**Seed pattern.** Phase-2 migrations follow the established seed
convention from `db/003`: at migration time, `INSERT … ON CONFLICT DO
NOTHING` a row per venue id so defaults exist immediately. The
consultation noted `db/003` lines ~126-153 already do exactly this for
`venue_defaults`. Worth noting `db/003`'s own header comment explicitly
*anticipated* this Phase-2 extension ("venue_defaults graduates into a
unified venues table with image/sound/animation columns;
karaoke_venue_settings becomes one of many per-app override tables") —
the schema designer's original intent and this spec are aligned.

(OQ2 — `jsonb` vs normalized for the anchor payload and override patch
— is now **settled as `jsonb`**; see §9 OQ2 and the table list above.)

---

## 5. The resolver

### 5.1 Generalize, don't replace

`shell/venue-settings.js` already implements the exact pattern needed —
a fallback resolver (`per-app override → DB default → venues.json →
fallback`) — but only for yaw/pitch. Phase 2 **generalizes** it to
resolve *any* venue attribute. The existing file is the foundation; this
is a widening, not a rewrite.

**File name — settled (OQ).** The file **keeps the name
`venue-settings.js`** even though, post-generalization, it resolves all
venue attributes rather than just "settings." Renaming would touch the
file's one consumer (`karaoke/stage.html`'s `shell/` import), a karaoke
edit that brushes the §10 non-goal for no functional gain. Rename, if
wanted, happens in Phase 3 when karaoke is touched anyway.

**Per-view branching is real, not a passthrough.** The consultation
flagged that the existing resolver branches by *view* — singer-view and
audience-view fall back differently (audience pitch falls back to
`venues.json.staticPitch`; singer pitch falls through to `0` because
`venues.json` has no `startPitch` field). The generalized resolver must
preserve per-view branching, not collapse it. Generalization means a
column-name / attribute-key parameter plus a per-view DB-column map —
not a single flat lookup.

**The resolver returns resolved objects; it does not mutate.** The
consultation found that the current code path (`applyVenueSettingsOverride`
in `stage.html`) mutates the in-memory `VENUES` array *in place*,
overwriting the venue objects' `startYaw`/`staticYaw`/etc. with
DB-resolved values. That is brittle — it destroys the original
`venues.json` values and makes re-resolution impossible. The generalized
resolver MUST **return new resolved objects** and leave the source
`venues.json` data untouched, so a venue can be re-resolved (e.g. when an
override changes) without having lost its baseline.

### 5.2 Resolution for scalar attributes

For camera, rotation, ambient: the resolver returns
`per-app override → DB default → fallback`. For the *new* attributes
(ambient, rotation) there is no `venues.json` tier — they are DB-native
(§4.2) — so the chain is override → DB default → hardcoded fallback. For
the *existing* attributes (yaw/pitch) the chain keeps its `venues.json`
tier exactly as `resolveVenueYawPitch` has it today. The generalized
resolver handles both: an attribute's fallback chain is part of its
per-attribute definition.

### 5.3 Resolution for the anchor set

The resolver returns the **effective anchor set** = DB default anchor
set with the app's patch applied (add / suppress / modify by `id`, per
§4.4). The resolver output is plain data — a resolved anchor list. How
those anchors are *drawn* is the app's rendering layer (§2.1 layer 4),
not the resolver's job.

**Read-only output contract (as built).** `resolveAnchorSet` returns a
new array of new anchor objects — it never mutates its inputs. But the
copy is **shallow**: each output anchor is a fresh object, yet its
`jsonb` fields (`payload`, `link`) are reference-shared with the input
default anchors. The resolved anchor list is therefore **read-only** —
callers and renderers must not mutate the array, any anchor in it, or
any anchor's `payload`/`link`, because a mutation would corrupt the
shared default. Deep-cloning every payload on every resolve was rejected
as needless cost (the resolver itself never writes into payloads); the
read-only contract is the trade. The resolver degrades gracefully on a
malformed or stale patch — it never throws (it is on the render path) —
and emits a `console.warn` breadcrumb so authoring problems are
discoverable.

### 5.4 Effect/media anchors resolve to references, not implementations

An anchor of type `spotlight` or `particle` does not carry effect *code*
in its payload — it carries a **reference** (an effect profile id +
parameters). The actual implementation (the Three.js spotlight builder,
the particle emitter) lives in a renderer/effect module the venue layer
registers. This keeps effects **reusable across venues**: the
sweeping-spotlight implementation is authored once; any venue's anchor
can reference it with its own parameters. Same for `audio`/`video` —
the payload references an asset, not the bytes.

This is the registry idea, correctly located: the **resolver** always
returns data (resolved anchors, each naming a type + payload); a
**renderer/effect registry** maps type → implementation. One resolver,
one registry, no per-attribute proliferation.

**Mechanism vs. implementations — the Phase 2 / Phase 3 split (as
built).** The registry has two separable parts, and only one is Phase 2.
The registry *mechanism* — the `type → implementation` map, the
register / lookup / unregister API, the graceful "nothing registered"
handling — is Phase 2, shipped as `shell/venue-registry.js`. The
registry *implementations* — the actual Three.js spotlight builder, the
particle emitter, the audio player — are **Phase 3**, because they are
produced by translating karaoke's existing procedural effects, and
Phase 2 does not touch karaoke (§10). So Phase 2 ships the registry as a
working but **empty** mechanism: zero implementations registered, every
`getAnchorRenderer` call returns `null`. Phase 3 populates it. A registry
with no implementations is not an unfinished deliverable — it is the
correct Phase-2 state; the mechanism and its contents are deliberately
separate shipments.

**Phase-3 translation cost — flagged so it is not a hidden surprise.**
The consultation noted karaoke's *current* effects
(`addVenueEffects3D` → `buildStadiumEffects3D` /
`buildSpeakeasyEffects3D`) are **procedural**, not data-driven: a
hardcoded `if (venueId === 'stadium') …` chain of bespoke per-venue
functions, plus the 410-line `AMBIENT_PROFILES` object. Phase 2 ships
the *data-driven* anchor + registry model dormant — it does not touch
that procedural code. But when Phase 3 rewires karaoke onto the venue
layer, that procedural code must be **translated**: each bespoke effect
function becomes a reusable registry implementation, and each venue's
effects become anchor *records* (data) that reference it. That
translation is real work and it belongs to Phase 3's karaoke-adoption
scope — it is named here so Phase 3 sizing accounts for it rather than
discovering it.

---

## 6. Costumes

Costumes are pulled to the **Elsewhere level** — they are not a karaoke
concept. Any premium app where users are composited into the venue
(karaoke today; games and wellness later, per the rendering matrix and
UAP's premium model) can render costumes on inserted users.

Model:
- A **costume library** — every costume authored once, keyed by id. A
  registry, parallel to the effect registry. Costume assets are
  DeepAR-pipeline bundles (`.deepar` files), as karaoke's existing
  filters are.
- **Asset location — settled (OQ3).** The cross-app costume library
  lives at a new **repo-root `/costumes/` directory** — a sibling of
  `/venues/` and `/sounds/`, NOT nested under `karaoke/`. This matches
  the established repo convention (CLAUDE.md keeps `/venues/` and
  `/sounds/` at root specifically so they are shared across products);
  a karaoke-nested path would wrongly imply costumes are karaoke-owned.
  Note this is the **target** location only — karaoke's existing
  bundles stay at `karaoke/effects/` and karaoke keeps using them until
  Phase 3 rewires it. Phase 2 establishes `/costumes/` as the home of
  the cross-app library; relocating karaoke's own assets is Phase-3
  work. (The consultation also flagged that the `DEEPAR_EFFECTS` array
  is currently duplicated between `karaoke/singer.html` and
  `karaoke/stage.html` — that de-duplication is likewise Phase-3
  cleanup, not Phase 2.)
- Each venue carries a **suggested costume list** — a curated subset
  ("these costumes suit this venue": space → astronaut; tavern →
  medieval garb). This list is a **venue attribute** — defaulted per
  venue, app-overridable, exactly like the anchor set.
- The user is **never limited** to the suggested list — they may choose
  from the full library. The venue's list is curation, not a gate.

Scope boundary: the shared venue layer owns the **library** and the
**suggested-list data**. *Applying* a costume to a composited user —
the actual overlay compositing — is part of each app's **rendering
layer** (layer 4), is **premium-gated**, and is **not built in Phase
2** (no app's rendering layer is built in Phase 2). Phase 2 builds the
library + the suggested-list attribute + resolution; karaoke's costume
*rendering* already exists inline and is rewired in Phase 3.

**Venue ambient — sources and loop length (forward note).** The
`ambient` attribute is a reference to the venue's default ambient
audio. The admin-UI fast-follow (§7) is intended to let an admin set
that audio by any of: an **API-generated** sound, a **sound-effect**
generation, or an **uploaded mp3** — and to set a **loop length** — the
same capabilities the external Time Travel Studio already has for its
ambient. The `ambient` column is `jsonb` and unconstrained precisely so
it can carry whichever shape these sources need (`source`, `asset_ref`,
`prompt`, `loop_sec`, …) without a schema change. Phase 2 builds only
the column; the generation/upload UI and the question of where ambient
*audio files* physically live (a repo asset path vs. Supabase Storage)
are admin-UI-era concerns, not db/032.

**Costume-table population timing.** The Phase-2 migration creates the
`costumes` table but ships it **empty** — nothing reads the costume
library until a rendering layer exists, so there is nothing to seed it
*for* in Phase 2. Karaoke's existing costumes (the `DEEPAR_EFFECTS`
list) are seeded into the `costumes` table by a **Phase 3 migration**,
concurrent with — and in the same phase as — relocating the `.deepar`
asset files from `karaoke/effects/` to repo-root `/costumes/`. Rows and
asset files move together, in Phase 3, because that is the phase in
which karaoke starts reading costumes from the library rather than from
its inline array. Thereafter the admin-UI fast-follow (§7) is how
costume records are added and edited. So the lifecycle is: Phase 2
creates the empty table → Phase 3 seeds it (rows) alongside the asset
relocation (files) → admin UI maintains it thereafter.

(OQ3 — costume asset location — is now settled; see the bullet above.)

---

## 7. The admin UI

The DB-backed-defaults decision (§4.1) implies an **admin surface** to
edit venue defaults and per-app overrides without a deploy. This is a
real surface with real scope: editing camera/rotation/ambient,
authoring and positioning anchors, managing the costume library and
per-venue suggested lists, and editing per-app override patches.

The repo already has an admin-gated venue-tuning affordance (the "Set
View Coordinates" dialog in `karaoke/stage.html`, backed by
`venue-settings.js` and `venue_defaults`). The Phase 2 admin UI is the
generalization of that affordance to the full venue model.

**Scope decision — SETTLED (fast-follow).** The admin UI is NOT built
in Phase 2. Phase 2 ships the venue abstraction plus a **minimal
seed/import path** to get venue data into the DB; the full venue admin
UI is a tracked **fast-follow** immediately after Phase 2.

Rationale: the venue *abstraction* (data model, resolver, anchor
system) is the architectural deliverable and is independently valuable
— Phase 3 karaoke adoption depends on the abstraction, not on the UI. A
full authoring UI (anchor placement, costume management, per-app
override editing) is a large surface that, if bundled, would roughly
double Phase 2 and risk the scope creep the DEFERRED entry explicitly
warned against. The cost — a window where venue data is seeded/imported
rather than UI-edited — is acceptable: it is pre-launch, internal-only,
and a minimal import path covers it (plausibly from Time Travel Studio
exports, whose format the model already matches).

**The "minimal seed/import path" — what it actually is (as resolved).**
Phase 2 commits to a seed/import path but does not specify its form.
Investigation settled it: there is **no seed/import path to build**, and
that is the correct outcome, not a gap. Reasoning: (1) there is zero
authored data of the new attribute kinds anywhere in `elsewhere-repo` —
no anchors, no `motion`, no DB-form `ambient`, no per-venue `camera_fov`,
no `costumes` rows — so there is nothing to seed; (2) the new attribute
columns are all nullable and the resolver returns fallbacks on `null`,
so an unseeded venue renders correctly; (3) the repo already has a seed
pattern — `db/003`'s `INSERT INTO ... ON CONFLICT DO NOTHING` inside a
migration — and the "no build step" doctrine rules out new ingestion
tooling. So the seed path **is** the existing migration-`INSERT`
pattern: when authored venue data first exists (from the admin-UI
fast-follow, or from Phase 3 translating karaoke's `AMBIENT_PROFILES`
and effects into DB rows), a future migration uses that pattern to seed
it. Phase 2's deliverable here is this paragraph — the recognition that
the path already exists — not code. No `db/033` seed migration, no
import script, no placeholder.

Note: the Time Travel Studio is an **existing external authoring tool**
(a separate side project, not in `elsewhere-repo`) that already authors
exactly this anchor data. It is **not** the Elsewhere admin UI and Phase
2 does not adopt or port it — but its export format is the proven shape
the venue layer's data model matches, which means a future import path
from Studio exports is plausible. Out of scope for Phase 2; noted so the
relationship is on record.

### 7.1 Anchor scope, and the deferred `family` hint

An anchor's **scope is positional**: an anchor is venue-level because it
is a `venue_anchors` default row, and app-level because it is an entry
in an app's `anchor_patch` (§4.4). There is no `scope` flag on the
anchor and the resolver does not need one — it merges defaults with the
patch and returns the effective set regardless of "level." So the
venue-vs-app distinction requires **no decision at schema or resolver
time**; it is settled by *which table a row is authored into*.

The one place the distinction becomes a real, per-overlay editorial
call is **authoring time** — when a person (via the admin UI) creates
an overlay and the tool must write it to `venue_anchors` or to an
app patch. A space-describing overlay (a `pin` labelling a landmark)
belongs in venue defaults; an app's narrative caption (a story
`callout`) belongs in that app's patch. This is editorial judgement,
not architecture, and a wrong call is just a row in the wrong table —
movable later, no migration.

**Intended direction (deferred to the admin-UI build):** anchors will
carry an **advisory `family` hint** — `decoration` / `overlay` /
`media` — whose sole purpose is to let the authoring tool guide that
editorial call (e.g. "this is an `overlay`-family anchor in venue
defaults — confirm?"). The hint is **advisory only**: not enforced by
the schema, not consumed by the resolver. It is **not added in Phase
2** — a hint field with no consumer is speculative, and its exact shape
(a `payload` jsonb key vs. a dedicated column; the precise vocabulary)
is best fixed when the admin UI — its only consumer — is designed. The
direction is recorded here; the field is added with the admin-UI
fast-follow.

---

## 8. 360° video venues (forward-compatibility only)

Per the planning discussion (item 5), venues may later use 360° **video**
rather than a static image. Phase 2 does **not** build video venues. It
only ensures the model does not foreclose them:

- The skybox layer's background source is **typed** (`image` | `video`)
  from day one. Every venue is `image` today; the renderer switches on
  type; the `video` branch is reserved/unimplemented.
- The anchor model is **already time-aware** (`start_sec`/`end_sec`), so
  time-indexed anchors over a video skybox need no model change.

Phase 2 must not attempt to spec video rendering. The requirement is
narrow: a typed source field, so adding video later is a renderer
branch, not a data-model migration.

---

## 9. Open questions for review

These are decisions to settle during spec review (with the human)
and/or verified by the Claude Code consultation. Revision 2 records the
consultation outcome: OQ1, OQ3, OQ5 are now SETTLED; OQ4 was already
settled; OQ2 settled as `jsonb`; OQ6/OQ7 were verified. All open
questions are now closed.

- **OQ1 — `venues.json` field set. SETTLED.** Revision 1 proposed a
  4-field shrink; the consultation proved that breaks `karaoke/stage.html`
  (it reads `icon`, `startYaw`, `staticYaw`, `staticPitch`, `soundId`).
  Resolution: **`venues.json` is NOT shrunk** — it keeps every field its
  current readers use; new attributes are DB-native. See §4.2 (rewritten
  in revision 2). No bootstrap shrink occurs in Phase 2.

- **OQ2 — payload + override patch storage shape. SETTLED: `jsonb`.**
  The typed anchor `payload`, the per-app anchor patch, and likewise
  `ambient`, `motion`, and `link` are stored as `jsonb` columns, not
  normalized tables. Reasoning: each of these has a parameter set that
  varies by type (anchor payload by anchor type, motion by motion type,
  etc.) and/or is a delta set — both awkward to normalize, natural as
  `jsonb`. Accepted trade-off: `jsonb` contents are not SQL-queryable
  without an explicit expression index, which is fine here (venue rows
  are read whole, not filtered by inner fields). All 13 db/032 review
  points are now resolved; this was the last substantive one.

- **OQ3 — costume library asset location. SETTLED.** Repo-root
  `/costumes/` directory (sibling of `/venues/`, `/sounds/`), not a
  karaoke-nested path. See §6. Target location only; karaoke asset
  relocation is Phase 3.

- **OQ4 — admin UI scope. SETTLED: fast-follow.** The full venue admin
  UI is NOT in Phase 2 — see §7. Phase 2 ships the abstraction + a
  minimal seed/import path; the admin UI is a tracked fast-follow.

- **OQ5 — module structure under `shell/`. SETTLED: flat files.** The
  consultation confirmed `shell/` is flat today with **no
  subdirectory precedent** — revision 1's claim that a `shell/venue/`
  cluster "matches existing convention" was wrong. Resolution: the new
  venue modules are **flat files** following the existing pattern. No
  new subdirectory convention is introduced.

  **Module split — as actually built (supersedes the provisional
  list).** The provisional list named four files
  (`venue-bootstrap.js`, `venue-resolver.js`, `venue-anchors.js`,
  `venue-registry.js`). The split that shipped is smaller:
  - `shell/venue-settings.js` — generalized in place (kept its name,
    §5.1). Absorbed what the provisional `venue-resolver.js` *and*
    `venue-anchors.js` would have been: the generalized
    `resolveVenueAttribute`, plus `loadVenueAnchors` and
    `resolveAnchorSet`. No separate resolver or anchors file.
  - `shell/venue-registry.js` — built as named (the registry
    mechanism).
  - `venue-bootstrap.js` — **not built. Dropped from Phase 2.** The name
    came from revision 1's assumption that `venues.json` would shrink to
    a thin bootstrap manifest needing a dedicated loader. Revision 2's
    §4.2 reframe ("`venues.json` keeps every field; it is not shrunk")
    removed that motivation. Investigation confirmed no Phase-2 consumer
    needs a shell-level `venues.json` loader: the resolver receives
    `venueJson` from its caller, the registry never touches the file.
    The one genuine task in the vicinity — deduplicating the
    copy-pasted `loadVenuesManifest()` in `karaoke/stage.html` and
    `karaoke/singer.html` — requires editing karaoke and is therefore
    **Phase 3** karaoke-surface work, not Phase 2. Each follows the established dual ESM-export +
  `window.elsewhere.*` pattern, and loads after `shell/auth.js` (which
  initializes `window.sb` / `window.elsewhere`). `shell/venue-settings.js`
  is generalized **in place, keeping its name** (see §5.1).

- **OQ6 — existing venue tables. VERIFIED.** The consultation confirmed
  the current shape of `venue_defaults` and `karaoke_venue_settings`
  (column lists, public-read / `is_platform_admin`-write RLS,
  `set_updated_at` triggers) and confirmed the Phase-2 column additions
  do not collide. `db/003`'s own header anticipated this extension. See
  §4.5.

- **OQ7 — other venue-data readers. VERIFIED.** The consultation
  re-confirmed only `karaoke/stage.html` and `karaoke/singer.html` read
  `venues.json`, and only stage.html renders a panorama. No other
  surface reads venue data. Since `venues.json` is no longer being
  shrunk (OQ1), the original concern behind OQ7 is moot — but the
  verification stands on record.

- **Three.js version (new, from consultation).** `karaoke/stage.html`
  loads Three.js **r128** from cdnjs. The Phase-2 venue renderer needs
  Three.js; any page that loads a venue-renderer module must load
  Three.js first. The implementation should pin the **same r128** to
  avoid two Three.js versions in one app. Noted here so the migration /
  module spec accounts for it.
---

## 10. Explicit non-goals

To keep Phase 2 bounded:

- **No karaoke adoption.** `karaoke/stage.html` keeps its inline venue
  code, untouched, and keeps reading `venues.json` exactly as it does
  today (which is why §4.2 does not shrink the file). Rewiring karaoke
  onto the new layer — including translating its procedural effects into
  anchor data (§5.4) and relocating its `.deepar` assets (§6) — is
  Phase 3.
- **No games adoption.** The DEFERRED entry's parts 2 (games venue
  entries, `'games'` tag, session-wide selection) and 3 (DeepAR camera
  insertion in games) are a later session, and part 2 carries its own
  prerequisites (the "Games TV rendering matrix" and "Games
  `ask_proximity` revision" DEFERRED entries).
- **No app rendering layers.** Layer 4 is per-app, per-phase. Phase 2
  builds layers 1–3 + the resolver only.
- **No video venue rendering.** §8 — typed source field only.
- **No TTS content model.** §3.4 — the anchor *data model* is taken; the
  narration/era/sequence model is not.
- **No venue admin UI.** §7 / OQ4 — settled as a fast-follow. Phase 2
  ships only a minimal seed/import path, not an authoring UI.
- **No port of the Time Travel Studio.** §7 — Studio is an external
  tool; not adopted, not ported.

---

## 11. What this spec is and is not

**Is:** a structural design for the Phase 2 venue abstraction — the
four-layer model, the unified anchor system, the storage model
(DB-backed defaults for new attributes, `venues.json` retained for
existing ones, patch-style per-app overrides), the generalized resolver,
the costume model, and the resolved/open questions.

**Is not:** migration DDL, module code, or a Claude Code execution
task. Implementation is the step *after* this spec is approved.

**Where this revision sits.** Revision 1 was written, then verified by a
read-only Claude Code consultation. Revision 2 folded in that
consultation (the `venues.json` reframe — §4.2; optional anchor position
— §3.1; OQ1/OQ3/OQ5 settled; precision corrections). **Revision 3 (this
document)** folds in the planning-chat resolution of the db/032 review
and the venue/scene modelling work: the venue/variant/scene vocabulary
(§2.2); the `link` two-target model (§3.3); the full TTS inventory with
stats objects and narration explicitly placed *outside* the venue layer
(§3.4); the canonical anchor-patch shape (§4.4); rotation modelled as a
`jsonb` `motion` column and `ON DELETE RESTRICT` on venue FKs (§4.5);
and **OQ2 settled as `jsonb`** (§9). **All open questions are now
closed.** The db/032 migration is in revision (rotation → `jsonb`,
FKs → `RESTRICT`) and then DDL review; after it applies, the next
execution task is the `shell/venue-*.js` modules (the resolver first,
which consumes the §4.4 patch shape).

## 12. Disposition tasks at spec-commit time

These are bookkeeping actions to perform when this spec is committed as
`docs/PHASE-2-BUILD-SPEC.md`. They are not design work; they are
recorded here so they are not lost.

- **Supersession pointer.** The `docs/DEFERRED.md` "Venues as cross-app
  service" entry gains a pointer to this spec, and its "keep ambient
  effects separate" line is marked superseded (per §1).

- **Absorb the `venue-effects.js` IOU.** The PHASE1-NOTES one-line
  "Extract ambient venue effects into `shell/venue-effects.js`" item is
  marked absorbed-into-Phase-2 (per §1) — it is no longer a separate
  deferred effort.

- **DEFERRED cluster disposition.** The `docs/DEFERRED.md` "Venues
  integration (post-Session-5)" parent cluster has six sub-entries
  (Games TV rendering matrix; Games `ask_proximity` revision; "Potential
  participant" derived UI state; Proximity hard/soft gate; Participant
  cleanup mechanism; `rpc_session_leave` dead auto-promote branch). Each
  needs an explicit disposition tag — resolved-by-Phase-2 /
  remains-active / re-scoped. Provisional read: none are *resolved* by
  Phase 2 (they are games/proximity/participant concerns, not venue-
  abstraction concerns); the "Games TV rendering matrix" is the one most
  relevant and should be re-pointed at this spec as informing the
  eventual games rendering layer. Confirm per-item at commit time.

- **Docs to update.** `INFRA.md` (its `venues.json` description and its
  `shell/venue-settings.js` row); `ROADMAP.md` (the active "Phase 2:
  venue extraction" entry stops being a stub and references this spec);
  `CLAUDE.md` (the "Adding a venue" procedure and the `AMBIENT_PROFILES`
  note become Phase-3-era stale once karaoke is rewired — flag, do not
  rewrite, in Phase 2). All are routine close-out, not blockers.

- **iOS bundle.** Per the CLAUDE.md session-closing ritual, any Phase-2
  commit that adds web-bundle files (the new `shell/venue-*.js` modules)
  triggers the `~/sync-app.sh` + `npx cap sync ios` + Xcode rebuild
  ritual at session close.
