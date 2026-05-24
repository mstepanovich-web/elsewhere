// shell/venue-settings.js — venue attribute resolver and helpers.
//
// Original role (db/003 + db/005 era): two-level venue view-coordinate
// resolver — yaw/pitch only, per view (singer / audience), with a
// four-level fallback chain.
//
// Phase 2 generalization (per `docs/PHASE-2-BUILD-SPEC.md` §5): the resolver
// widens to handle ANY venue attribute — yaw/pitch (legacy, per-view, with
// venues.json fallback), camera_fov / motion / ambient (Phase-2 new,
// non-per-view, DB-native, no venues.json fallback), and the anchor set
// (a collection that resolves via a jsonb patch, not a scalar override).
// The existing 4 exports keep their signatures and observable behavior
// exactly — karaoke's 7 callsites in karaoke/stage.html continue to work
// bit-for-bit unchanged (no karaoke rewire — spec §10 non-goal).
//
// Planning-chat review (2026-05-24) folded in three refinements to the
// anchor-set resolver: (1) an `add` whose id collides with an un-suppressed
// default REPLACES that default (anchor ids are the patch's primary key;
// duplicate-id outputs are malformed); (2) malformed/stale patches emit
// console.warn breadcrumbs (modify-id-not-in-defaults, add-missing-id, add
// duplicate-id-within-list, add-collides-with-default) so the underlying
// authoring problem is discoverable — but never throws (the resolver sits
// on the render path); (3) the read-only contract on the returned array
// is explicit: callers must not mutate output anchors or their jsonb
// payload/link fields (shallow-copied; payloads are reference-shared with
// inputs).
//
// ─── Fallback chains (the per-attribute, per-view truth table) ──────────
//
//   yaw (per-view; venues.json fallback)
//     singer:   overrides.singer_yaw_override     → defaults.back_yaw   → venueJson.startYaw   → 0
//     audience: overrides.audience_yaw_override   → defaults.front_yaw  → venueJson.staticYaw  → 0
//
//   pitch (per-view; venues.json fallback for audience only)
//     singer:   overrides.singer_pitch_override   → defaults.back_pitch                         → 0
//     audience: overrides.audience_pitch_override → defaults.front_pitch → venueJson.staticPitch → 0
//
//   camera_fov / motion / ambient (Phase-2 non-per-view; DB-native, no venues.json)
//     overrides.<attribute>_override → defaults.<attribute> → null
//
//   The chains for yaw/pitch are encoded EXACTLY as the original
//   resolveVenueYawPitch implemented them. Backwards-compat is enforced
//   by construction: resolveVenueYawPitch is now a thin wrapper that
//   composes two resolveVenueAttribute calls; the per-view config table
//   (VENUE_ATTRIBUTES below) carries the same DB-column names, the same
//   venues.json keys, and the same `0` fallbacks.
//
// ─── Anchor-set resolution ──────────────────────────────────────────────
//
// The anchor set is a collection, not a scalar — resolved by APPLYING A
// PATCH to a default list, not by override. Patch shape per spec §4.4:
//   { "add": [<anchor records>], "suppress": ["<id>", ...], "modify": { "<id>": {<fields>} } }
// The new resolveAnchorSet() applies this patch to a default-anchor
// array (rows from venue_anchors), returning a new array. Pure function;
// never mutates inputs; handles every empty/null combination without
// throwing.
//
// ─── Dormancy ───────────────────────────────────────────────────────────
//
// `venue_anchors` is empty in prod (db/032 ships dormant per spec §10).
// `karaoke_venue_settings.anchor_patch` is empty too. The anchor resolver
// is built and reasoned-through but not yet integration-tested against
// live rows — the empty-input case (defaults [] + patch null) is handled
// correctly by construction (returns []). Live testing follows once the
// admin UI / authoring path populates real rows.
//
// ─── Module load order ──────────────────────────────────────────────────
//
// Depends on window.sb (Supabase client from shell/auth.js) — load this
// module AFTER shell/auth.js.

// ─────────────────────────────────────────────────────────────────────────
// SECTION 1 — Existing exports (preserved bit-for-bit)
// ─────────────────────────────────────────────────────────────────────────

/**
 * Fetch venue_defaults + per-app override rows. Returns the raw row
 * arrays — callers iterate and resolve per venue per view via
 * resolveVenueYawPitch() (or, post-Phase-2, resolveVenueAttribute()).
 *
 * The existing select('*') automatically picks up db/032's new columns
 * on both tables (venue_defaults.camera_fov / motion / ambient;
 * karaoke_venue_settings.camera_fov_override / motion_override /
 * ambient_override / anchor_patch). Callers that want them just read
 * the new keys on the returned row objects.
 *
 * @param {string} app  The app name — 'karaoke' today.
 * @returns {Promise<{defaults: Object[], overrides: Object[]}>}
 */
export async function loadVenueSettings(app = 'karaoke') {
  const sb = window.sb;
  if (!sb) throw new Error('window.sb not initialized — load shell/auth.js first');

  const overrideTable = app + '_venue_settings';
  const [defaultsRes, overridesRes] = await Promise.all([
    sb.from('venue_defaults').select('*'),
    sb.from(overrideTable).select('*'),
  ]);
  if (defaultsRes.error)  throw defaultsRes.error;
  if (overridesRes.error) throw overridesRes.error;

  return {
    defaults:  defaultsRes.data  || [],
    overrides: overridesRes.data || [],
  };
}

/**
 * Resolve yaw + pitch for one venue in one view. Null-coalescing chain:
 * per-app override → global default → venues.json fallback → 0.
 *
 * Pitch fallback differs per view:
 *   - singer view has no venues.json pitch field, so falls through to 0
 *   - audience view uses staticPitch from venues.json
 *
 * Phase-2 implementation note: this function is preserved bit-for-bit
 * for backwards-compatibility (karaoke/stage.html has 4 callsites). The
 * body is now a thin wrapper over resolveVenueAttribute(), but every
 * observable behavior (including the throw-on-unknown-view error
 * message) is identical to the pre-Phase-2 implementation.
 *
 * @param {Object|null} defaults    row from venue_defaults for this venue,
 *                                  or null. Has columns
 *                                  front_yaw/front_pitch/back_yaw/back_pitch.
 * @param {Object|null} overrides   row from <app>_venue_settings for this
 *                                  venue, or null. Has columns
 *                                  singer_{yaw,pitch}_override and
 *                                  audience_{yaw,pitch}_override.
 * @param {'singer'|'audience'} view
 * @param {Object|null} venueJson   the venue entry from venues.json (has
 *                                  startYaw / staticYaw / staticPitch).
 * @returns {{ yaw: number, pitch: number }}
 */
export function resolveVenueYawPitch(defaults, overrides, view, venueJson) {
  // View check preserves the exact pre-Phase-2 error message. Required
  // before delegating because resolveVenueAttribute's own message differs
  // slightly, and bit-for-bit observable equivalence includes errors.
  if (view !== 'singer' && view !== 'audience') {
    throw new Error('resolveVenueYawPitch: unknown view ' + view);
  }
  return {
    yaw:   resolveVenueAttribute(defaults, overrides, 'yaw',   view, venueJson),
    pitch: resolveVenueAttribute(defaults, overrides, 'pitch', view, venueJson),
  };
}

/**
 * Partial upsert of venue_defaults. `partial` contains any subset of
 * the table's columns (yaw/pitch pairs from db/003+005, or any of the
 * Phase-2 attributes camera_fov / motion / ambient from db/032).
 * Unspecified columns retain their current values (Postgres ON CONFLICT
 * DO UPDATE only touches columns named in the payload).
 *
 * Typical call sites (existing):
 *   - audience-view save: saveVenueDefault(id, { front_yaw: y, front_pitch: p })
 *   - singer-view save:   saveVenueDefault(id, { back_yaw:  y, back_pitch:  p })
 * Phase-2 call sites (admin UI / future):
 *   - saveVenueDefault(id, { camera_fov: 80 })
 *   - saveVenueDefault(id, { motion: { type: 'orbit', deg_per_sec: 1.5 } })
 *   - saveVenueDefault(id, { ambient: { audio: { type: 'mp3', sound_id: 'stadium' } } })
 */
export async function saveVenueDefault(venueId, partial) {
  const sb = window.sb;
  const user = window.elsewhere?.getCurrentUser?.();
  const payload = { venue_id: venueId, ...partial, updated_by: user?.id || null };
  const { error } = await sb.from('venue_defaults').upsert(payload, { onConflict: 'venue_id' });
  if (error) throw error;
}

/**
 * Partial upsert of <app>_venue_settings. `partial` contains any subset
 * of the override columns — singer_{yaw,pitch}_override /
 * audience_{yaw,pitch}_override (db/005), or the Phase-2
 * camera_fov_override / motion_override / ambient_override /
 * anchor_patch (db/032). NULL on a column clears the override (NULL
 * resolves as "inherit default").
 *
 * Typical call sites (existing):
 *   - audience-view save: saveVenueOverride('karaoke', id,
 *                           { audience_yaw_override: y,
 *                             audience_pitch_override: p })
 *   - singer-view save:   saveVenueOverride('karaoke', id,
 *                           { singer_yaw_override: y,
 *                             singer_pitch_override: p })
 *   - "Use default" clears: { audience_yaw_override: null,
 *                             audience_pitch_override: null }
 * Phase-2 call sites (admin UI / future):
 *   - saveVenueOverride('karaoke', id, { camera_fov_override: 70 })
 *   - saveVenueOverride('karaoke', id, { anchor_patch: { add: [...], suppress: [...] } })
 */
export async function saveVenueOverride(app, venueId, partial) {
  const sb = window.sb;
  const user = window.elsewhere?.getCurrentUser?.();
  const table = app + '_venue_settings';
  const payload = { venue_id: venueId, ...partial, updated_by: user?.id || null };
  const { error } = await sb.from(table).upsert(payload, { onConflict: 'venue_id' });
  if (error) throw error;
}


// ─────────────────────────────────────────────────────────────────────────
// SECTION 2 — Phase 2 generalized resolver
// ─────────────────────────────────────────────────────────────────────────

/**
 * Per-attribute fallback-chain configuration. Each attribute declares
 * either:
 *   - perView: true  + chains: { singer: <chain>, audience: <chain> }
 *   - perView: false + chain:  <chain>
 *
 * A <chain> is { overrideKey, defaultKey, venueJsonKey, fallback }. The
 * resolver walks override → default → venuesJson → fallback with `??`
 * semantics (null/undefined fall through; 0/false/'' stop the walk).
 * Any chain key set to null skips that layer.
 *
 * The yaw/pitch entries encode the exact pre-Phase-2 chains — DO NOT
 * change them without re-verifying resolveVenueYawPitch's bit-for-bit
 * backwards-compat.
 *
 * @private
 */
const VENUE_ATTRIBUTES = {
  // Per-view scalar attributes (legacy yaw/pitch).
  yaw: {
    perView: true,
    chains: {
      singer:   { overrideKey: 'singer_yaw_override',   defaultKey: 'back_yaw',   venueJsonKey: 'startYaw',  fallback: 0 },
      audience: { overrideKey: 'audience_yaw_override', defaultKey: 'front_yaw',  venueJsonKey: 'staticYaw', fallback: 0 },
    },
  },
  pitch: {
    perView: true,
    chains: {
      // Singer pitch has NO venues.json tier — venues.json has no startPitch field.
      singer:   { overrideKey: 'singer_pitch_override',   defaultKey: 'back_pitch',  venueJsonKey: null,         fallback: 0 },
      audience: { overrideKey: 'audience_pitch_override', defaultKey: 'front_pitch', venueJsonKey: 'staticPitch', fallback: 0 },
    },
  },
  // Phase-2 non-per-view scalar attributes (db/032). DB-native, no venues.json tier.
  camera_fov: {
    perView: false,
    chain: { overrideKey: 'camera_fov_override', defaultKey: 'camera_fov', venueJsonKey: null, fallback: null },
  },
  motion: {
    perView: false,
    chain: { overrideKey: 'motion_override', defaultKey: 'motion', venueJsonKey: null, fallback: null },
  },
  ambient: {
    perView: false,
    chain: { overrideKey: 'ambient_override', defaultKey: 'ambient', venueJsonKey: null, fallback: null },
  },
};

/**
 * Walk one fallback chain. Returns the first non-null/undefined value
 * found among override → default → venuesJson, or chain.fallback if
 * none of the layers have a value.
 *
 * @private
 */
function walkChain(chain, overrides, defaults, venueJson) {
  if (chain.overrideKey != null) {
    const v = overrides?.[chain.overrideKey];
    if (v != null) return v;
  }
  if (chain.defaultKey != null) {
    const v = defaults?.[chain.defaultKey];
    if (v != null) return v;
  }
  if (chain.venueJsonKey != null) {
    const v = venueJson?.[chain.venueJsonKey];
    if (v != null) return v;
  }
  return chain.fallback;
}

/**
 * Generalized scalar venue-attribute resolver (Phase-2 spec §5.1, §5.2).
 *
 * Walks the per-attribute fallback chain: per-app override → DB default
 * → venues.json (when applicable) → declared fallback. Per-view branching
 * applies to attributes that declare it (yaw, pitch — legacy); non-per-view
 * attributes (camera_fov, motion, ambient — Phase-2) ignore the `view`
 * argument.
 *
 * Return type varies by attribute:
 *   - yaw / pitch / camera_fov: number (or 0/null fallback)
 *   - motion / ambient: jsonb object (or null fallback)
 *
 * @param {Object|null} defaults       row from venue_defaults, or null
 * @param {Object|null} overrides      row from <app>_venue_settings, or null
 * @param {string}      attributeKey   one of: 'yaw', 'pitch', 'camera_fov', 'motion', 'ambient'
 * @param {'singer'|'audience'|null|undefined} view  required for per-view attributes; ignored otherwise
 * @param {Object|null} venueJson      venues.json entry; consulted only when the attribute has a venuesJsonKey
 * @returns {*} resolved value
 */
export function resolveVenueAttribute(defaults, overrides, attributeKey, view, venueJson) {
  const config = VENUE_ATTRIBUTES[attributeKey];
  if (!config) {
    throw new Error('resolveVenueAttribute: unknown attribute "' + attributeKey + '"');
  }

  let chain;
  if (config.perView) {
    if (view !== 'singer' && view !== 'audience') {
      throw new Error(
        'resolveVenueAttribute: attribute "' + attributeKey +
        '" is per-view; expected view "singer" or "audience", got: ' + view
      );
    }
    chain = config.chains[view];
  } else {
    // view is ignored for non-per-view attributes — silent rather than throw,
    // so a caller resolving multiple attributes in a loop can pass the same view
    // to all without per-attribute branching.
    chain = config.chain;
  }

  return walkChain(chain, overrides, defaults, venueJson);
}


// ─────────────────────────────────────────────────────────────────────────
// SECTION 3 — Phase 2 anchor-set load + resolve
// ─────────────────────────────────────────────────────────────────────────

/**
 * Fetch venue_anchors rows. Sibling to loadVenueSettings — anchors are
 * per-venue content (one row per default anchor), not per-app settings,
 * so they get their own loader rather than widening loadVenueSettings.
 * Karaoke's existing consumer doesn't read anchors today; not bundling
 * them into loadVenueSettings means karaoke's per-startup network cost
 * doesn't change.
 *
 * Optional filters narrow the fetch SQL-side. Empty filters = all rows.
 *
 * @param {{venueId?: string, type?: string}} [filters]  optional narrowing
 * @returns {Promise<Object[]>} array of venue_anchors rows; empty if none
 */
export async function loadVenueAnchors(filters = {}) {
  const sb = window.sb;
  if (!sb) throw new Error('window.sb not initialized — load shell/auth.js first');

  let query = sb.from('venue_anchors').select('*');
  if (filters.venueId) query = query.eq('venue_id', filters.venueId);
  if (filters.type)    query = query.eq('type', filters.type);

  const { data, error } = await query;
  if (error) throw error;
  return data || [];
}

/**
 * Apply an anchor patch to a default anchor list (Phase-2 spec §5.3,
 * patch shape per §4.4).
 *
 * Patch shape:
 *   { "add":      [<anchor records>],
 *     "suppress": ["<id>", ...],
 *     "modify":   { "<id>": {<field overrides>} } }
 *
 * Returns a NEW array of NEW anchor objects (shallow copies — see
 * read-only contract below). Inputs are never mutated.
 *
 * RESOLVED-ORDER CONTRACT:
 *   1. Default anchors in their original order — filtered (suppress) and
 *      modified (modify) — make up the first portion of the result.
 *   2. When an `add` whose id collides with an un-suppressed default
 *      appears, the add REPLACES the default AT THE DEFAULT'S POSITION
 *      (it does not move to the end). Anchor ids are the patch's primary
 *      key; an add is the more specific intent.
 *   3. Non-colliding adds are appended at the end, in their original
 *      first-appearance order.
 *
 * READ-ONLY CONTRACT FOR THE RETURNED ARRAY:
 *   The resolved anchor list is read-only. Callers and renderers MUST NOT
 *   mutate:
 *     - the outer array,
 *     - any anchor object in it,
 *     - any jsonb field on those anchors (notably `payload` and `link`).
 *   Output anchors are SHALLOW copies of inputs — the jsonb fields
 *   (`payload`, `link`) are REFERENCE-SHARED with the input default
 *   anchors. Mutating a payload on an output anchor would corrupt the
 *   input data and any other resolved-set view of the same anchor.
 *   Treat the output as immutable.
 *
 * Empty/null handling — never throws:
 *   - defaultAnchors null/undefined → treated as []
 *   - patch null/undefined → returns shallow copies of defaultAnchors
 *   - patch.add missing/null → no additions
 *   - patch.suppress missing/null → no suppressions
 *   - patch.modify missing/null → no modifications
 *   - suppress id not in defaults → ignored silently (a no-op suppress
 *     is benign; no warning).
 *
 * Malformed-patch warnings — degrade gracefully, emit console.warn:
 *   - modify id not in defaults → modify skipped; console.warn (likely
 *     stale patch — discoverability matters).
 *   - add entry missing an `id` → entry skipped; console.warn.
 *   - patch.add contains multiple entries with the same id → last entry
 *     wins (replaces the earlier at its position-of-first-appearance);
 *     console.warn.
 *   - add id collides with an un-suppressed default → add REPLACES the
 *     default at the default's position; console.warn. The default's
 *     modify (if any) is implicitly overridden by the replace.
 *
 * Posture: the resolver sits on the render path. It must never throw on
 * a malformed or stale patch — always returns a valid array. Warnings
 * are the breadcrumb that surfaces the underlying authoring problem so
 * it can be discovered and fixed.
 *
 * @param {Object[]|null} defaultAnchors  rows from venue_anchors for one venue
 * @param {Object|null}   patch            anchor_patch jsonb value (or null)
 * @returns {Object[]} effective anchor list (read-only — see contract above)
 */
export function resolveAnchorSet(defaultAnchors, patch) {
  const defaults = Array.isArray(defaultAnchors) ? defaultAnchors : [];

  if (patch == null) {
    return defaults.map(a => ({ ...a }));
  }

  const suppressIds = Array.isArray(patch.suppress) ? new Set(patch.suppress) : new Set();
  const modifyMap = (patch.modify && typeof patch.modify === 'object' && !Array.isArray(patch.modify))
    ? patch.modify
    : {};
  const addList = Array.isArray(patch.add) ? patch.add : [];

  // Index adds by id; last-write-wins within the add list. Warn on
  // duplicates (malformed patch) and on missing ids (anchors are keyed
  // by id — an add without one is malformed).
  const addById = new Map();
  for (const added of addList) {
    if (!added || typeof added !== 'object' || added.id == null) {
      console.warn('resolveAnchorSet: patch.add entry missing id — skipped.');
      continue;
    }
    if (addById.has(added.id)) {
      console.warn(
        'resolveAnchorSet: patch.add contains multiple entries with id "' + added.id +
        '" — the later entry replaces the earlier (malformed patch).'
      );
    }
    addById.set(added.id, added);
  }

  // Build a set of default ids for stale-modify detection.
  const defaultIds = new Set(defaults.map(a => a.id));

  // Walk defaults: skip suppressed; if an add collides with this default's
  // id, REPLACE (the add is the more specific intent); else apply modify
  // (if any) and copy.
  const placedAddIds = new Set();
  const out = [];
  for (const anchor of defaults) {
    if (suppressIds.has(anchor.id)) continue;

    if (addById.has(anchor.id)) {
      console.warn(
        'resolveAnchorSet: patch.add and default anchor share id "' + anchor.id +
        '" — add replaces default (malformed patch; add is the more specific intent).'
      );
      out.push({ ...addById.get(anchor.id) });
      placedAddIds.add(anchor.id);
      continue;
    }

    const modifyFields = modifyMap[anchor.id];
    if (modifyFields && typeof modifyFields === 'object' && !Array.isArray(modifyFields)) {
      out.push({ ...anchor, ...modifyFields });
    } else {
      out.push({ ...anchor });
    }
  }

  // Warn on stale modifies — modify-id targets no existing default. The
  // modify is silently skipped (already, because we never matched it
  // during the defaults walk above); this loop exists purely to surface
  // the staleness as a discoverable breadcrumb.
  for (const modifyId of Object.keys(modifyMap)) {
    if (!defaultIds.has(modifyId)) {
      console.warn(
        'resolveAnchorSet: patch.modify targets id "' + modifyId +
        '" but no default anchor with that id exists (likely a stale patch).'
      );
    }
  }

  // Append non-colliding adds at the end, in original-first-appearance
  // order. Adds whose ids already replaced a default are already in `out`
  // at the default's position; skip them here.
  const emittedAddIds = new Set();
  for (const added of addList) {
    if (!added || typeof added !== 'object' || added.id == null) continue;
    if (emittedAddIds.has(added.id)) continue;          // duplicate in add list — warn was emitted above
    emittedAddIds.add(added.id);
    if (placedAddIds.has(added.id)) continue;           // already placed as a replacement
    out.push({ ...addById.get(added.id) });
  }

  return out;
}


// ─────────────────────────────────────────────────────────────────────────
// SECTION 4 — window.elsewhere.venueSettings publication
// ─────────────────────────────────────────────────────────────────────────
// Exposes both the legacy exports (karaoke/stage.html consumes via this
// namespace) and the new Phase-2 exports (no live consumer yet — Phase 3
// karaoke rewire + Phase 4 games adoption pick them up).
// Per CLAUDE.md "No build step" — inline scripts assume globals.

if (typeof window !== 'undefined') {
  window.elsewhere = window.elsewhere || {};
  window.elsewhere.venueSettings = {
    // Legacy exports — preserved bit-for-bit; karaoke depends on these.
    loadVenueSettings,
    resolveVenueYawPitch,
    saveVenueDefault,
    saveVenueOverride,
    // Phase-2 additions (dormant; no live consumer yet).
    resolveVenueAttribute,
    loadVenueAnchors,
    resolveAnchorSet,
  };
}
