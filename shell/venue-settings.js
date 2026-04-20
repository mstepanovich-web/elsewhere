// shell/venue-settings.js — two-level venue view-coordinate resolver.
//
// Venue view tuning splits into two independent pairs, one per view:
//
//   singer / panorama view   ← looks out from the stage
//   audience view            ← faces the stage
//
// Each view has its own { yaw, pitch } pair, and each pair resolves
// through two layers:
//
//   1. venue_defaults (DB)          — canonical per-venue values,
//                                     shared across every product.
//                                     Columns: front_* (audience),
//                                     back_* (singer).
//   2. <app>_venue_settings (DB)    — per-app overrides, NULL = inherit.
//                                     Columns: audience_{yaw,pitch}_override
//                                     and singer_{yaw,pitch}_override.
//
// Final fallback is the venue entry from venues.json (startYaw,
// staticYaw, staticPitch). The caller passes that venue object in; the
// resolver doesn't look it up.
//
// See PHASE1-NOTES "Venue property override pattern" for the decision
// context and db/005_front_back_venue_tuning.sql for the schema.
// Depends on window.sb (Supabase client from shell/auth.js) — load this
// module AFTER shell/auth.js.

/**
 * Fetch venue_defaults + per-app override rows. Returns the raw row
 * arrays — callers iterate and resolve per venue per view via
 * resolveVenueYawPitch().
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
  if (view === 'singer') {
    return {
      yaw:   overrides?.singer_yaw_override   ?? defaults?.back_yaw   ?? venueJson?.startYaw ?? 0,
      pitch: overrides?.singer_pitch_override ?? defaults?.back_pitch ?? 0,
    };
  }
  if (view === 'audience') {
    return {
      yaw:   overrides?.audience_yaw_override   ?? defaults?.front_yaw   ?? venueJson?.staticYaw   ?? 0,
      pitch: overrides?.audience_pitch_override ?? defaults?.front_pitch ?? venueJson?.staticPitch ?? 0,
    };
  }
  throw new Error('resolveVenueYawPitch: unknown view ' + view);
}

/**
 * Partial upsert of venue_defaults. `partial` contains any subset of
 * front_yaw / front_pitch / back_yaw / back_pitch. Unspecified columns
 * retain their current values (Postgres ON CONFLICT DO UPDATE only
 * touches columns named in the payload).
 *
 * Typical call sites:
 *   - audience-view save: saveVenueDefault(id, { front_yaw: y, front_pitch: p })
 *   - singer-view save:   saveVenueDefault(id, { back_yaw:  y, back_pitch:  p })
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
 * of singer_{yaw,pitch}_override / audience_{yaw,pitch}_override.
 * Passing null for an override column clears it (row stays in place —
 * NULL resolves as "inherit default" anyway, so all-NULL rows are
 * functionally equivalent to no row).
 *
 * Typical call sites:
 *   - audience-view save: saveVenueOverride('karaoke', id,
 *                           { audience_yaw_override: y,
 *                             audience_pitch_override: p })
 *   - singer-view save:   saveVenueOverride('karaoke', id,
 *                           { singer_yaw_override: y,
 *                             singer_pitch_override: p })
 *   - "Use default" clears: { audience_yaw_override: null,
 *                             audience_pitch_override: null }
 */
export async function saveVenueOverride(app, venueId, partial) {
  const sb = window.sb;
  const user = window.elsewhere?.getCurrentUser?.();
  const table = app + '_venue_settings';
  const payload = { venue_id: venueId, ...partial, updated_by: user?.id || null };
  const { error } = await sb.from(table).upsert(payload, { onConflict: 'venue_id' });
  if (error) throw error;
}

// Expose on window.elsewhere for non-module callers (inline scripts in
// karaoke/*.html all assume globals per CLAUDE.md "No build step").
if (typeof window !== 'undefined') {
  window.elsewhere = window.elsewhere || {};
  window.elsewhere.venueSettings = {
    loadVenueSettings,
    resolveVenueYawPitch,
    saveVenueDefault,
    saveVenueOverride,
  };
}
