// shell/venue-settings.js — two-level venue property resolution.
//
// Venue properties flow through two layers:
//   1. venue_defaults (DB)             — canonical per-venue values, shared
//                                        across every product that renders
//                                        the venue.
//   2. <app>_venue_settings (DB)       — per-app overrides. NULL on a
//                                        column means "inherit from default."
//
// Callers pass an app name ('karaoke', 'wellness', ...) and get back both
// the raw rows and a resolved map { venueId: { yaw, pitch, ... } } ready
// to apply to the local venue list.
//
// See PHASE1-NOTES "Venue property override pattern" for the decision
// that motivates this module. See db/003_admin_and_venue_settings.sql for
// the tables + RLS policies. Depends on window.sb (Supabase client from
// shell/auth.js) — load this module AFTER shell/auth.js.

/**
 * Fetch venue_defaults + per-app overrides and return a resolved map.
 * @param {string} app  The app name — currently 'karaoke'.
 * @returns {Promise<{defaults: Object[], overrides: Object[], resolved: Object}>}
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

  const defaults  = defaultsRes.data  || [];
  const overrides = overridesRes.data || [];
  const overrideByVenue = {};
  overrides.forEach(o => { overrideByVenue[o.venue_id] = o; });

  const resolved = {};
  defaults.forEach(d => {
    const o = overrideByVenue[d.venue_id] || null;
    resolved[d.venue_id] = {
      yaw:   resolveVenueProperty(d, o, 'yaw'),
      pitch: resolveVenueProperty(d, o, 'pitch'),
    };
  });
  return { defaults, overrides, resolved };
}

/**
 * Resolve a single property. Non-null override wins; else default.
 * Generalizes to any property — callers pass 'yaw', 'pitch', or future
 * additions like 'sound', 'anim'.
 */
export function resolveVenueProperty(defaults, overrides, propertyName) {
  const overrideKey = propertyName + '_override';
  const v = overrides?.[overrideKey];
  return v !== null && v !== undefined ? v : defaults?.[propertyName];
}

/**
 * Upsert a row in venue_defaults. Pass yaw/pitch as numbers.
 */
export async function saveVenueDefault(venueId, { yaw, pitch }) {
  const sb = window.sb;
  const user = window.elsewhere?.getCurrentUser?.();
  const payload = {
    venue_id: venueId,
    yaw, pitch,
    updated_by: user?.id || null,
  };
  const { error } = await sb.from('venue_defaults').upsert(payload, { onConflict: 'venue_id' });
  if (error) throw error;
}

/**
 * Upsert a row in <app>_venue_settings. yaw/pitch may be numbers OR null
 * (null means "use the default"). Delete when both are null so we don't
 * keep empty override rows around.
 */
export async function saveVenueOverride(app, venueId, { yaw, pitch }) {
  const sb = window.sb;
  const user = window.elsewhere?.getCurrentUser?.();
  const table = app + '_venue_settings';
  if (yaw === null && pitch === null) {
    const { error } = await sb.from(table).delete().eq('venue_id', venueId);
    if (error) throw error;
    return;
  }
  const payload = {
    venue_id: venueId,
    yaw_override:   yaw,
    pitch_override: pitch,
    updated_by: user?.id || null,
  };
  const { error } = await sb.from(table).upsert(payload, { onConflict: 'venue_id' });
  if (error) throw error;
}

// Expose on window.elsewhere for non-module callers (inline scripts in
// karaoke/*.html all assume globals — see CLAUDE.md "No build step").
if (typeof window !== 'undefined') {
  window.elsewhere = window.elsewhere || {};
  window.elsewhere.venueSettings = {
    loadVenueSettings,
    resolveVenueProperty,
    saveVenueDefault,
    saveVenueOverride,
  };
}
