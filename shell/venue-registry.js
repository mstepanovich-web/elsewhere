// shell/venue-registry.js — anchor-type → renderer-impl registry.
//
// Phase 2 venue abstraction infrastructure per
// `docs/PHASE-2-BUILD-SPEC.md` §5.4. The resolver
// (`shell/venue-settings.js:resolveAnchorSet`) returns resolved anchor
// records as plain data — each anchor carries a `type` and a `payload`.
// This module is the typed map that lets a renderer look up "for an
// anchor of type X, what implementation draws / runs it?".
//
// Spec §5.4 framing, verbatim: "the resolver always returns data
// (resolved anchors, each naming a type + payload); a renderer/effect
// registry maps type → implementation. One resolver, one registry, no
// per-attribute proliferation."
//
// ─── Ships DORMANT — empty by construction ──────────────────────────────
//
// Phase 2 ships this registry as a working MECHANISM with ZERO
// implementations registered. There are no `registerAnchorRenderer`
// calls inside this file. Phase 3 (karaoke onto the new model) is what
// populates the registry — per spec §5.4's "Phase-3 translation cost"
// note, karaoke's current procedural effects (`addVenueEffects3D`,
// `buildStadiumEffects3D`, `buildSpeakeasyEffects3D`, the 410-line
// `AMBIENT_PROFILES`) get translated into registry impls + venue
// anchor records. That translation is real work and belongs to
// Phase 3, not Phase 2.
//
// Until Phase 3 lands, every `getAnchorRenderer(type)` call returns
// `null` because nothing is registered. Callers must handle `null` —
// typically skip the anchor / log — see the read-path posture below.
//
// ─── Read-path posture: graceful degradation ────────────────────────────
//
// The registry sits on the render path. It never throws on a missing
// renderer — `getAnchorRenderer(type)` for an unregistered type
// returns `null`, full stop. Callers are responsible for handling
// `null` (typically: skip the anchor, optionally log). This mirrors
// `resolveAnchorSet`'s never-throw posture in `shell/venue-settings.js`.
//
// Registration validates lightly:
//   - `type` must be a non-empty string (throws otherwise — programmer
//     error, not a render-path concern).
//   - `impl` must be non-null/undefined (throws — same reasoning;
//     `unregisterAnchorRenderer` is the API for removal).
//   - `type` not in the known vocabulary → ALLOWED, with `console.warn`.
//     Spec §3.2 explicitly calls the type set extensible; a future
//     type may be registered before the CHECK constraint catches up.
//     The warn is the breadcrumb so a typo doesn't silently masquerade
//     as a legitimate new type.
//   - Re-registration of an existing type → ALLOWED (replaces), with
//     `console.warn`. Re-registration is usually accidental duplicate
//     registration. For deliberate hot-swap, call
//     `unregisterAnchorRenderer(type)` first to silence the warn.
//
// ─── Module dependencies: NONE ──────────────────────────────────────────
//
// This module does NOT depend on `window.sb`, `shell/auth.js`, or any
// other shell module. It is a pure in-memory `Map` with a registration
// API. It can be loaded in any order relative to other shell modules —
// unlike `shell/realtime.js`, `shell/preferences.js`, and
// `shell/venue-settings.js`, which all require `shell/auth.js` to land
// first (they read `window.sb`). The registry never touches Supabase.
//
// ─── Impl shape: opaque to Phase 2 ──────────────────────────────────────
//
// What an `impl` looks like — a function? an object with .start/.stop?
// a class instance? — is NOT specified by Phase 2. The renderer-API
// contract (the shape of an impl) lives with the renderers and is a
// Phase-3 concern. The registry treats impls opaquely: it stores
// whatever non-null/undefined value is registered and returns it
// verbatim on lookup. When Phase 3 settles the renderer-API contract,
// this file may gain a comment documenting the expected shape; no
// code change required.

// ─────────────────────────────────────────────────────────────────────────
// SECTION 1 — The known anchor type vocabulary
// ─────────────────────────────────────────────────────────────────────────

/**
 * Canonical anchor type vocabulary. Mirrors:
 *   - PHASE-2-BUILD-SPEC.md §3.2 (the design-level type set)
 *   - db/032 venue_anchors_type_check CHECK constraint (SQL-enforced)
 *
 * The set is extensible per spec §3.2 — adding a new type is a future
 * migration (extend the CHECK + add a registry impl + extend any
 * payload docs). The current set, in declared order:
 *   - callout       (informative overlay)
 *   - pin           (informative overlay)
 *   - spotlight     (effect, 3D)
 *   - particle      (effect, 3D/2D)
 *   - audio         (media)
 *   - video         (media)
 *   - link-hotspot  (navigation; overlaps with callout/pin + link field set per spec §3.2)
 *
 * Exported frozen so callers may iterate or validate against the
 * vocabulary without risk of mutation. `Object.freeze` is shallow but
 * adequate here — the array contents are primitives.
 */
export const ANCHOR_TYPE_VOCABULARY = Object.freeze([
  'callout',
  'pin',
  'spotlight',
  'particle',
  'audio',
  'video',
  'link-hotspot',
]);


// ─────────────────────────────────────────────────────────────────────────
// SECTION 2 — Internal store
// ─────────────────────────────────────────────────────────────────────────

/**
 * Map of anchor type → renderer impl.
 *
 * Module-private. External access is via the three exported functions
 * below (registerAnchorRenderer / getAnchorRenderer /
 * unregisterAnchorRenderer). Callers must not reach into this Map
 * directly.
 *
 * @private
 */
const registry = new Map();


// ─────────────────────────────────────────────────────────────────────────
// SECTION 3 — Registration API
// ─────────────────────────────────────────────────────────────────────────

/**
 * Register a renderer implementation for an anchor type.
 *
 * Behavior:
 *   - Stores the impl under the given type. Subsequent
 *     `getAnchorRenderer(type)` calls return this impl.
 *   - Re-registering an existing type REPLACES the previous impl and
 *     emits a console.warn (re-registration is usually accidental).
 *     For a deliberate hot-swap, call `unregisterAnchorRenderer(type)`
 *     first to silence the warn.
 *   - Registering an unknown type (not in ANCHOR_TYPE_VOCABULARY) is
 *     ALLOWED but emits a console.warn. The vocabulary is extensible
 *     per spec §3.2, so an unknown type may be a legitimate new type
 *     not yet in the CHECK constraint; the warn is the breadcrumb so
 *     a typo doesn't silently masquerade as a new type.
 *
 * Throws (programmer error, not render-path concerns):
 *   - if `type` is not a non-empty string
 *   - if `impl` is null/undefined (use unregisterAnchorRenderer to remove)
 *
 * @param {string} type   anchor type — see ANCHOR_TYPE_VOCABULARY
 * @param {*}      impl   the renderer implementation (opaque to Phase 2)
 * @returns {void}
 */
export function registerAnchorRenderer(type, impl) {
  if (typeof type !== 'string' || type === '') {
    throw new Error('registerAnchorRenderer: type must be a non-empty string');
  }
  if (impl == null) {
    throw new Error(
      'registerAnchorRenderer: impl is required (got null/undefined); ' +
      'use unregisterAnchorRenderer to remove a registration'
    );
  }
  if (!ANCHOR_TYPE_VOCABULARY.includes(type)) {
    console.warn(
      'registerAnchorRenderer: type "' + type +
      '" is not in the known anchor type vocabulary (spec §3.2 + db/032 CHECK). ' +
      'Registration accepted (the vocabulary is extensible per spec §3.2), but ' +
      'this is likely a typo. Known types: ' + ANCHOR_TYPE_VOCABULARY.join(', ')
    );
  }
  if (registry.has(type)) {
    console.warn(
      'registerAnchorRenderer: type "' + type +
      '" already has a registered impl — new registration replaces the previous one. ' +
      'Call unregisterAnchorRenderer(type) first to silence this warn on deliberate hot-swaps.'
    );
  }
  registry.set(type, impl);
}

/**
 * Look up the renderer implementation for an anchor type.
 *
 * Returns `null` when no impl is registered for the type. Callers MUST
 * handle null — typically by skipping the anchor (optionally with a
 * log). The registry never returns a fake / no-op renderer because a
 * silent no-op would hide the missing-implementation condition from
 * callers; `null` is the honest signal. Same render-path posture as
 * the resolver's never-throw degradation.
 *
 * Returns the impl verbatim — does not copy or wrap. The registry
 * treats impls opaquely (Phase 2 does not specify impl shape — that's
 * a Phase-3 renderer-API contract).
 *
 * Does NOT warn on unknown-vocabulary lookups: lookups happen on every
 * anchor render and warning would be noisy. The asymmetry with
 * registerAnchorRenderer's warn is intentional — registration is rare
 * (typically once per type per session); lookup is hot. A missing
 * registration shows up as `null` to the caller either way.
 *
 * @param {string} type   anchor type
 * @returns {*|null} the registered impl, or null if none
 */
export function getAnchorRenderer(type) {
  if (typeof type !== 'string' || type === '') return null;
  return registry.get(type) ?? null;
}

/**
 * Remove a registered renderer implementation.
 *
 * Useful for test cleanup and for deliberate hot-swaps (call
 * unregister first to silence the re-registration warn in
 * registerAnchorRenderer).
 *
 * @param {string} type   anchor type
 * @returns {boolean} true if a registration was removed; false if none existed
 */
export function unregisterAnchorRenderer(type) {
  if (typeof type !== 'string' || type === '') return false;
  return registry.delete(type);
}


// ─────────────────────────────────────────────────────────────────────────
// SECTION 4 — window.elsewhere.anchorRegistry publication
// ─────────────────────────────────────────────────────────────────────────
// Exposes the registry on window.elsewhere.anchorRegistry. Namespace
// is `anchorRegistry` (NOT `venueRegistry`) — the registry maps anchor
// types to renderers, not venues; precision over symmetry with
// `venueSettings`. Per CLAUDE.md "No build step" — inline scripts
// assume globals.

if (typeof window !== 'undefined') {
  window.elsewhere = window.elsewhere || {};
  window.elsewhere.anchorRegistry = {
    ANCHOR_TYPE_VOCABULARY,
    registerAnchorRenderer,
    getAnchorRenderer,
    unregisterAnchorRenderer,
  };
}
