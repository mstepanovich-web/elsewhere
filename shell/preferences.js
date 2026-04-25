// shell/preferences.js — per-user-per-TV preferences helper.
//
// Wraps rpc_get_user_preference / rpc_set_user_preference (db/012). Returns
// raw JSONB values from reads; callers apply application-level defaults
// when the read is null.
//
// Depends on window.sb (Supabase client from shell/auth.js). Load this
// module AFTER shell/auth.js. realtime.js and preferences.js are sibling
// modules — both depend on auth.js providing window.sb. Load order
// between realtime.js and preferences.js is not significant for
// correctness, only for readability of the script tag list.
//
// Exposed as ESM exports AND on window.elsewhere.preferences for inline-
// script callers (matches venue-settings.js convention; CLAUDE.md "No
// build step" requires inline scripts to use globals).

/**
 * Read a preference value. Returns the JSONB value as a plain JS value,
 * or null when no row exists for (user, tv_device_id, preference_key).
 *
 * Caller cannot distinguish "no row exists" from "row exists with explicit
 * JSONB null value" — both return null. For 2c.1's
 * proximity_prompt_dismissed use case, both are treated as "use
 * application default (false)." Future preferences that need to
 * distinguish those cases should use a different helper that returns the
 * full row (or surface the row's existence separately).
 *
 * @param {string|null} tv_device_id  TV-scoped key, or null for user-global preference
 * @param {string} preference_key     Stable string identifying the preference
 * @returns {Promise<any|null>}       JSONB value or null
 */
export async function getUserPreference(tv_device_id, preference_key) {
  const sb = window.sb;
  if (!sb) throw new Error('window.sb not initialized — load shell/auth.js first');

  const { data, error } = await sb.rpc('rpc_get_user_preference', {
    p_tv_device_id:   tv_device_id,
    p_preference_key: preference_key,
  });
  if (error) throw error;
  return data;
}

/**
 * Upsert a preference. Returns the full user_preferences row from the RPC
 * (id, user_id, tv_device_id, preference_key, preference_value, created_at,
 * updated_at). Callers extract whatever fields they need.
 *
 * @param {string|null} tv_device_id   TV-scoped, or null for user-global
 * @param {string} preference_key      Stable string
 * @param {any} preference_value       Anything serializable to JSONB
 * @returns {Promise<Object>}          The user_preferences row
 */
export async function setUserPreference(tv_device_id, preference_key, preference_value) {
  const sb = window.sb;
  if (!sb) throw new Error('window.sb not initialized — load shell/auth.js first');

  const { data, error } = await sb.rpc('rpc_set_user_preference', {
    p_tv_device_id:     tv_device_id,
    p_preference_key:   preference_key,
    p_preference_value: preference_value,
  });
  if (error) throw error;
  return data;
}

// Expose on window.elsewhere for non-module callers (inline scripts in
// karaoke/*.html, games/*.html, index.html assume globals per CLAUDE.md
// "No build step"). Matches venue-settings.js convention.
if (typeof window !== 'undefined') {
  window.elsewhere = window.elsewhere || {};
  window.elsewhere.preferences = {
    getUserPreference,
    setUserPreference,
  };
}
