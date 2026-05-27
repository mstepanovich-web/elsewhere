# Venue Admin UI — Stage A1 Build Spec (skeleton + venue_defaults editor + Stage 2 audio fold-in)

**Status:** Build spec. Pre-implementation. Awaits propose-pause-apply.
**Scope:** Stage 1 (admin UI skeleton + venue_defaults editor + db/034) + folded Stage 2 (audio renderer impl + audio anchor authoring + 19 audio-only venue translations + db/035). Stages 3+ (particle, spotlight, remaining types, AMBIENT_PROFILES retirement, per-app override editor, costume editor) are explicitly OUT OF SCOPE per §11.

**Source decisions (cited, not re-litigated):**
- `docs/VENUE-ADMIN-UI-DIRECTION.md` (Plan B revision, commit `c076f12`) — Decisions 1–5 + §7 hybrid sequencing.
- The A1 foundation investigation conducted 2026-05-26 (in-session findings; not a standalone doc). Provides the exact 26-venue inventory + O1/O2/O3 resolutions + the four A1-specific build questions answered.

---

## 1. The scope, plainly

Stage 1 ships a working admin surface that edits `venue_defaults` rows — the schema's per-venue base attributes (camera, motion, ambient) — backed by one new SECURITY DEFINER RPC. Stage 2 folds in: an `audio` renderer impl registered to `shell/venue-registry.js`, an audio anchor authoring panel inside the admin UI, the 19 audio-only venue anchors seeded programmatically as part of `db/035` (the sound references are fully known from `AMBIENT_PROFILES` per §2's locked inventory — hand entry would be busywork), and the two Stage-2 anchor RPCs. The admin audio panel is a management/editing surface (and the authoring tool for FUTURE new anchors — Part 2 / post-Phase-5), NOT the bulk-import mechanism for this initial port. The in-surface live preview that Plan B's mitigation argument relies on arrives with Stage 2 — Stage 1 is the skeleton, not itself the mitigation tool; Stage 1 verifies via a link out to `karaoke/stage.html?venue=<id>` per §6 / Q3a.

After Stage 2 ships, the 19 audio-only venues have seeded anchor records but `karaoke/stage.html`'s read path is **unchanged** — anchors are authored-but-dormant data. Per D8 (§4), promoting anchors to load-bearing is Stage 6's job, paired with the AMBIENT_PROFILES retirement.

---

## 2. Venue inventory — the 26 rows (locked)

The A1 foundation pass enumerated the exact 26-venue inventory by reading `venues.json` against `karaoke/stage.html`'s `AMBIENT_PROFILES` object end-to-end. Cited verbatim here; the spec does not re-derive.

| # | venue_id | category | bucket | Notes |
|---|---|---|---|---|
| 1 | `default` | (null) | NO-AMBIENT | Silent entry: `audio: null, anim: null`. Represents no-venue state. |
| 2 | `stadium` | big | PROCEDURAL | 4 sweeping spotlight beams + 400 phone-light particles + crowd-cheer brightness modulation + stadium.mp3. **Has 3D builder** `buildStadiumEffects3D` (2000 lights + 4 Three.js cone spotlights). Stages 3+. |
| 3 | `festival` | big | PROCEDURAL | 6 beat-synced lasers + strobe + confetti + festival.mp3. Stages 3+. |
| 4 | `hollywoodbowl` | big | AUDIO-ONLY | `hollywoodbowl.mp3` |
| 5 | `amphitheater` | big | AUDIO-ONLY | `amphitheater.mp3` |
| 6 | `colosseum` | big | AUDIO-ONLY | `colosseum.mp3` |
| 7 | `drivein` | big | AUDIO-ONLY | `drivein.mp3` |
| 8 | `disco` | party | PROCEDURAL | 120 mirror-ball dots + beat pulse + floor flash + disco.mp3. Stages 3+. |
| 9 | `vegas` | party | NO-AMBIENT | No `AMBIENT_PROFILES` entry. No `vegas.mp3`. Has `vegas.jpg`. See §10 OQ-V1. |
| 10 | `rooftop` | party | AUDIO-ONLY | `rooftop.mp3` |
| 11 | `broadway` | party | AUDIO-ONLY | `broadway.mp3` |
| 12 | `speakeasy` | bars | PROCEDURAL | 3 light shafts + 35 smoke wisps + speakeasy.mp3. **Has 3D builder** `buildSpeakeasyEffects3D`. Stages 3+. |
| 13 | `honkytonk` | bars | PROCEDURAL | Neon flicker + honkytonk.mp3. Stages 3+. |
| 14 | `supperclub` | bars | AUDIO-ONLY | `supperclub.mp3` |
| 15 | `cabaret` | bars | AUDIO-ONLY | `cabaret.mp3` |
| 16 | `bourbonstreet` | bars | AUDIO-ONLY | `bourbonstreet.mp3` |
| 17 | `saloon` | bars | AUDIO-ONLY | `saloon.mp3` |
| 18 | `spacestation` | fantasy | AUDIO-ONLY | `spacestation.mp3` |
| 19 | `enchantedforest` | fantasy | AUDIO-ONLY | `enchantedforest.mp3` (also `forest.mp3` exists; `soundId: "forest"` in venues.json — see §10 OQ-S1) |
| 20 | `dragonlair` | fantasy | AUDIO-ONLY | `dragonlair.mp3`. Audio-only via override of an unreachable procedural entry (see §3). |
| 21 | `kids-candy` | kids | AUDIO-ONLY | `kids-candy.mp3` |
| 22 | `kids-dino` | kids | AUDIO-ONLY | `kids-dino.mp3` |
| 23 | `kids-dino2` | kids | AUDIO-ONLY | Reuses `kids-dino.mp3` (`playAmbientMp3('kids-dino')` at line 4990). Encoded in Stage 2 via `payload.sound_id: "kids-dino"`. |
| 24 | `kids-northpole` | kids | AUDIO-ONLY | `kids-northpole.mp3` |
| 25 | `kids-princess` | kids | AUDIO-ONLY | `kids-princess.mp3` |
| 26 | `kids-winter` | kids | AUDIO-ONLY | `kids-winter.mp3` |

**Bucket totals:** PROCEDURAL = 5 (Stages 3+); AUDIO-ONLY = 19 (Stage 2 translates all); NO-AMBIENT = 2. **3D builders = 2** (stadium, speakeasy; both ride alongside their procedural counterparts).

---

## 3. Dead code in AMBIENT_PROFILES — flagged for Stage 6, not touched here

The A1 foundation pass identified **3 ghost AMBIENT_PROFILES keys** and **1 unreachable duplicate** — code paths in `karaoke/stage.html` that look like venues but are never reached:

- **`forest`** (`karaoke/stage.html:4917`) — full procedural anim (firefly particles). Unreachable: `venues.json` uses `enchantedforest`, not `forest`. The `soundId: "forest"` field references the audio asset, not the AMBIENT_PROFILES key.
- **`space`** (`karaoke/stage.html:4736`) — full procedural anim (stars + panel pulses). Unreachable: venues.json uses `spacestation`.
- **`underwater`** (`karaoke/stage.html:4953`) — full procedural anim (rising bubbles) + synthesized bubble sounds. Unreachable: no venue named `underwater` exists in venues.json.
- **`dragonlair` (duplicate)** (`karaoke/stage.html:4932`) — procedural anim (ember particles) + cave-drip sounds. Unreachable: the later audio-only override at line 4985 wins per JavaScript object-literal semantics. Only the audio-only entry executes.

Combined: roughly 125 LOC of unreachable procedural code.

**Stage 6 must PROVE these are unreachable before deleting** — not just by inspection of the `AMBIENT_PROFILES[venueId]` lookup, but by grep across the entire repo for any reference path that could reach them: string literals matching the keys (`'forest'`, `'space'`, `'underwater'`, `'dragonlair'`), function-export usage, any cached state that might preserve a procedural reference, any test fixture or seed. Only after every reference path is verified unreachable should the entries be deleted in Stage 6.

Stage 1 and Stage 2 leave these entries in place untouched. The cleanup belongs to Stage 6's `AMBIENT_PROFILES` retirement when every procedural venue has a data-driven equivalent.

---

## 4. Locked decisions

D1–D7 are cited from the A1 foundation pass. D8 is decided at spec-write time and is locked here.

- **D1 — Venue identity is the visual asset only.** `skyboxId` + the `/venues/<id>.jpg` (or future video) file, sourced from `venues.json`, shown **READ-ONLY** in the admin UI. EVERY `venue_defaults` and `karaoke_venue_settings` column is app-overridable per the schema's existing design — including `ambient`. The direction note §6 hypothesis ("ambient = likely venue-identity") is **resolved against**: ambient sound IS app-overridable per the schema, only the visual asset is fixed identity. (Resolves O1.)

- **D2 — Default state is no-app-selected.** Edit `venue_defaults` directly. The app selector itself arrives in Stage 7, not Stage 1. (Resolves O2.)

- **D3 — When an app IS selected** (Stage 7+), editing a shared param defaults to writing the app override with a one-click "edit the default instead" affordance. (Resolves O3 — for Stage 7's design.)

- **D4 — No embedded live preview in Stage 1.** Link out to `karaoke/stage.html?venue=<id>` for visual verification. Stage 1 IS the skeleton; the in-surface live preview that Plan B's mitigation argument relies on arrives at Stage 2 (with the audio renderer). The mitigation-tool argument applies to Stages 2+, not to Stage 1. (Resolves Q3a.)

- **D5 — Explicit save with dirty-state tracking.** No autosave. Warn on navigation if dirty (beforeunload). (Resolves Q3b.)

- **D6 — Surface is `admin-venues.html` at repo root.** Matches `claim.html` / `tv2.html` convention. No `admin/` subdirectory. No build step. (Resolves Q3c.)

- **D7 — db/034 ships ONE RPC.** `rpc_venue_default_update`. The two anchor RPCs (`rpc_venue_anchor_upsert`, `rpc_venue_anchor_delete`) belong to Stage 2's `db/035` migration. (Resolves Q3d for Stage 1; Stage 2 below covers its own.)

- **D8 — Stage 2 is AMBIENT_PROFILES-first; ships NO `karaoke/stage.html` read-path change.** Stage 2 seeds the 19 audio-only venues' anchor records (programmatically, via db/035 — see §7.3) and registers the audio renderer impl with the registry mechanism, but does NOT promote anchors to load-bearing in karaoke playback. The authored anchors are dormant data; karaoke continues reading from `AMBIENT_PROFILES` for the 19 audio-only venues until Stage 6 retires the AMBIENT_PROFILES path. Rationale: Stage 2's authoring + verification surface the data + UI path; switching the canonical reader is a separate decision that pairs with Stage 6's retirement, not with Stage 2's authoring. Stage 2's verification (§8.2 Check 10) compares the two paths via the audio panel's preview affordance, but does NOT switch karaoke's resolver wiring. This decision exists explicitly to prevent the Stage 2 implementation from quietly wiring a resolver and expanding scope.

---

## 5. Stage 1 — the admin surface

### 5.1 File: `admin-venues.html` (repo root)

Single static HTML file. No build step. Loads `shell/auth.js` + `shell/venue-settings.js` as ES modules (matches `tv2.html` / `claim.html` pattern). Inline JS for the rest. Uses `elsewhere-theme.css` from the GitHub Pages absolute URL per repo convention.

### 5.2 Boot sequence

1. **Auth gate.** Load `shell/auth.js`. Await `window.elsewhere.ready`. Read `window.elsewhere.getCurrentUser()`. If null, render a sign-in prompt that links to the existing magic-link flow (reuse `index.html`'s pattern). After sign-in, return to admin-venues.html.
2. **Admin gate.** Once signed in, query `profiles.is_platform_admin` for the current user (single SELECT through `window.sb`). If `false`, render a "not authorized" page (terminal — no escape to the editor). If `true`, proceed.
3. **Load venues data.**
   - Fetch `venues.json` (existing CDN pattern from `karaoke/stage.html`).
   - Call `shell/venue-settings.js:loadVenueSettings('karaoke')` to fetch `venue_defaults` + `karaoke_venue_settings` rows.
   - Build a merged venue map keyed by `venue_id`, joining venues.json identity + venue_defaults columns.
4. **Render the venue list.** See §5.3.

### 5.3 Surface layout

Two-pane layout:

**Left pane — Venue list (sidebar):**
- Grouped by `venues.json` `categories` array (Big Venues, Party & Nightlife, Bars & Lounges, Fantasy & Adventure, Kids). The `default` venue (no category) appears in its own ungrouped top section.
- Each row: icon (emoji from venues.json) + name + venue_id (mono, small) + bucket badge (PROCEDURAL / AUDIO-ONLY / NO-AMBIENT — purely informational; Stage 1 doesn't edit procedural code).
- Selecting a row populates the right pane.
- A "dirty" indicator (• or "unsaved") appears next to the row when the selected venue has unsaved changes; navigating away to a different venue triggers an explicit confirm (or auto-discards per §5.6 below — settle in implementation).

**Right pane — Venue editor:**

Header — read-only venue identity (per D1):
- `venue_id` (mono, large)
- `name`, `icon`, `category` (from venues.json)
- **Skybox preview**: `<img src="/venues/<skyboxId>.jpg">` rendered as a sphere-thumbnail or letterboxed image. If `skyboxId` is `null` (the `default` venue), show a "(no skybox)" placeholder. Read-only — not editable. The image is the visual identity.
- Footnote: "Identity attributes are sourced from `venues.json` and are not editable here."

Body — editable `venue_defaults` columns (per D1):
- `back_yaw` — numeric input (allow decimals, range visualization optional)
- `back_pitch` — numeric input
- `front_yaw` — numeric input
- `front_pitch` — numeric input
- `camera_fov` — numeric input (optional; allow clear-to-null via dedicated "clear" affordance)
- `motion` — textarea for the jsonb value. Edited AS TEXT initially (per direction note §7). Parsed on save. Invalid JSON: save button disabled + inline error.
- `ambient` — textarea for the jsonb value. Same handling as motion. Per D1 this is app-overridable; the editor at the venue_defaults level is the SHARED default that all apps inherit unless overridden.

Footer:
- "Preview in karaoke stage" link → opens `karaoke/stage.html?venue=<id>` in a new tab. Reads the current saved state from prod (not the dirty buffer).
- **Save** button (disabled when no dirty fields; enabled when ≥1 field is dirty).
- "Discard changes" button (resets the dirty buffer to the last saved state).
- Inline status row: "Saved" / "Saving..." / "Save failed: <error>" / "(unsaved changes)".

Audit:
- Show `updated_at` and `updated_by` (resolved to user display_name + email if possible) at the bottom. Read-only.

### 5.4 jsonb editing — text-area approach (Stage 1)

Per direction note §7: "jsonb columns edited as text initially." Concretely:

- `motion` and `ambient` textareas display the current jsonb formatted as pretty-printed JSON (`JSON.stringify(value, null, 2)`).
- On input, attempt to parse; if invalid, disable Save and surface a one-line error ("Invalid JSON: <message>").
- On save, send the parsed object (not the string) through the RPC.
- Empty textarea = NULL on the column.
- The schema does not validate the jsonb shape (`db/032:283-287` — "the renderer registry interprets"). Validation is the renderer's responsibility, surfaced at preview time.

This is a Stage-1 placeholder. Stage 2 introduces typed authoring for `ambient`'s audio-anchor shape via the audio anchor panel (§7.2). Later stages introduce typed authoring for `motion` (orbit speed, etc.) and other types.

### 5.5 Save semantics (D5)

- **Dirty-state tracking:** per-field, in a local map keyed by venue_id + column.
- **Save button:** disabled when no fields dirty for the selected venue. Enabled when ≥1 field is dirty.
- **On save:** build a `partial` object containing only the dirty fields. Call `rpc_venue_default_update(p_venue_id, p_partial)`. On success, update the local cached state from the RPC's RETURNING row, clear the dirty buffer for that venue, refresh `updated_at`/`updated_by`. On failure (network, RPC error, 42501, 02000): show the inline error, keep the dirty buffer intact.
- **Navigation warning:** if any venue has dirty fields, `beforeunload` fires a native browser confirm. Selecting a different venue from the sidebar while the current one is dirty also fires an inline confirm ("Discard unsaved changes to <venue>?" — Discard / Cancel).

### 5.6 Auth/admin gating reuses existing infrastructure

- `is_platform_admin` is the same gate that protects the existing "Set View Coordinates" dialog in `karaoke/stage.html`. Reuse the same query pattern.
- The RPC `rpc_venue_default_update` re-checks `is_platform_admin` server-side per defense-in-depth (per §6.4 below). The client check is the UI gate; the RPC check is the authority.

### 5.7 Out of scope for Stage 1 (deferred to later stages)

- App selector + per-app override editing (Stage 7).
- Anchor authoring (Stage 2 brings audio-anchor authoring; later stages add other types).
- `anchor_patch` editing on `karaoke_venue_settings` (Stage 7).
- Costume library + suggested-costumes editor (Stage 8).
- Live preview embedded in the admin surface (Stage 2).
- Visual/3D editing of motion (Stages 3+).
- Bulk operations across venues (deferred indefinitely; not in scope).
- Skybox image upload / replacement (Part 2 — post-Phase-5).
- Creating new venue_defaults rows. Per §6, Stage 1's RPC is UPDATE-only. All 26 venues are pre-seeded by db/003:126-152; creation is a Part 2 (new-venue) concern, post-Phase-5.

---

## 6. Stage 1 — db/034 migration

### 6.1 Scope

One new RPC: `rpc_venue_default_update`. No schema changes (the table already exists; columns already exist post-db/032). No grant changes beyond the new RPC's `GRANT EXECUTE`.

### 6.2 Function signature and update-only behavior

```sql
create function public.rpc_venue_default_update(
  p_venue_id text,
  p_partial  jsonb
)
returns public.venue_defaults
language plpgsql
security definer
set search_path = public
as $$
...
$$;
```

- `p_venue_id`: the venue to update. NOT NULL. Must reference an EXISTING row in `public.venue_defaults` — raises `02000` (`no_data_found`) if no row exists for `p_venue_id`.
- `p_partial`: a jsonb object containing 0 or more of the editable column names as keys: `back_yaw`, `back_pitch`, `front_yaw`, `front_pitch`, `camera_fov`, `motion`, `ambient`. Unknown keys raise `22023` (`invalid_parameter_value`).

**UPDATE-only, never INSERT.** All 26 venue_defaults rows are pre-seeded by db/003:126-152. The admin UI edits those existing rows; it never creates new venues. Creating new venues (Part 2 — post-Phase-5) is out of Stage 1's scope and would need a separate RPC with full schema-side seeding (skybox path, name, category, etc.) — explicitly NOT this RPC's responsibility. Eliminating the INSERT branch removes the silent-zero failure mode where an INSERT with partial yaw/pitch would default the unset NOT NULL columns to 0, mis-seeding a venue's camera. The function refuses to operate on a missing row instead.

### 6.3 Function body — behavior

```
1. Authentication: require auth.uid() != null; raise '42501' (insufficient_privilege) if null.
2. Authorization: require profiles.is_platform_admin = true for auth.uid();
   raise '42501' otherwise.
3. Validate venue_id: require p_venue_id != null and non-empty; raise '02000' otherwise.
4. Validate p_partial:
   - Reject unknown keys (raise '22023').
   - For NOT NULL columns (back_yaw, back_pitch, front_yaw, front_pitch): if the
     key is present, reject NULL values (raise '22004', null_value_not_allowed).
     Nullable columns (camera_fov, motion, ambient) accept NULL.
5. UPDATE public.venue_defaults SET ... WHERE venue_id = p_venue_id RETURNING * INTO v_row:
   - For each key present in p_partial, set the column to the jsonb value, cast to
     the column's type. Use the `p_partial ? '<col>'` test (JSONB key-exists
     operator) to distinguish "key not present" (preserve existing value) from
     "key present with NULL" (clear, where allowed).
   - Always set updated_by = auth.uid() and rely on the existing trigger
     (venue_defaults_set_updated_at) for updated_at.
6. If the UPDATE affected zero rows (NOT FOUND), the venue does not exist —
   raise '02000' with the venue_id in the message.
7. Return v_row.
```

The body must use the `jsonb ? text` key-exists operator (not just `->>` casting) because the latter returns NULL for both "key absent" and "key present with NULL value" — those have different semantics under partial-update.

### 6.4 RLS interaction

`venue_defaults` already has RLS enabled with:
- Public SELECT: `using (true)` (db/003:63-66)
- Admin WRITE: `using (is_platform_admin)` (db/004:53-55 — renamed from db/003's `is_admin`)

The new RPC is `SECURITY DEFINER` — it runs with the function owner's privileges, bypassing RLS. The function body's `is_platform_admin` check is the authoritative gate. The existing RLS policies remain in place as defense-in-depth for any direct table writes from privileged contexts.

### 6.5 Grants

```sql
grant execute on function public.rpc_venue_default_update(text, jsonb) to authenticated;
```

`anon` does NOT get execute — admin actions require sign-in (the function's own `auth.uid()` check would refuse anyway, but the grant explicitly limits attack surface).

### 6.6 Migration scaffolding (matches db/026-028 pattern)

```sql
-- ============================================================================
-- Elsewhere — Venue Admin UI Stage 1: rpc_venue_default_update
-- Migration: 034
-- Project: https://gbrnuxyzrlzbybvcvyzm.supabase.co
--
-- Single new SECURITY DEFINER RPC for admin-UI venue_defaults updates.
-- UPDATE-only (the 26 venue rows are pre-seeded by db/003:126-152;
-- creation of new venues is post-Phase-5 Part 2 work). Per
-- VENUE-ADMIN-UI-A1-BUILD-SPEC.md §6. Schema unchanged.
-- ============================================================================

begin;

drop function if exists public.rpc_venue_default_update(text, jsonb);

create function public.rpc_venue_default_update(
  p_venue_id text,
  p_partial  jsonb
)
returns public.venue_defaults
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_is_admin boolean;
  v_row public.venue_defaults;
  v_key text;
  v_known_keys text[] := ARRAY['back_yaw', 'back_pitch', 'front_yaw',
                                'front_pitch', 'camera_fov', 'motion', 'ambient'];
  v_notnull_keys text[] := ARRAY['back_yaw', 'back_pitch', 'front_yaw', 'front_pitch'];
begin
  -- 1. Auth
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- 2. Admin gate
  select is_platform_admin into v_is_admin
    from public.profiles where id = v_user_id;
  if coalesce(v_is_admin, false) = false then
    raise exception 'not a platform admin' using errcode = '42501';
  end if;

  -- 3. Validate venue_id
  if p_venue_id is null or length(p_venue_id) = 0 then
    raise exception 'venue_id required' using errcode = '02000';
  end if;

  -- 4. Validate p_partial keys
  if p_partial is not null then
    for v_key in select jsonb_object_keys(p_partial) loop
      if not (v_key = any(v_known_keys)) then
        raise exception 'unknown key in p_partial: %', v_key
          using errcode = '22023';
      end if;
      if v_key = any(v_notnull_keys) and (p_partial->>v_key) is null then
        raise exception 'cannot null NOT NULL column: %', v_key
          using errcode = '22004';
      end if;
    end loop;
  end if;

  -- 5. UPDATE only (no INSERT branch — see file header for rationale).
  --    Key-exists semantics via the `?` operator distinguish "key not present"
  --    (preserve existing column value) from "key present with NULL" (clear,
  --    where the column allows null — guarded by step 4).
  update public.venue_defaults set
    back_yaw     = case when p_partial ? 'back_yaw'     then (p_partial->>'back_yaw')::numeric     else back_yaw end,
    back_pitch   = case when p_partial ? 'back_pitch'   then (p_partial->>'back_pitch')::numeric   else back_pitch end,
    front_yaw    = case when p_partial ? 'front_yaw'    then (p_partial->>'front_yaw')::numeric    else front_yaw end,
    front_pitch  = case when p_partial ? 'front_pitch'  then (p_partial->>'front_pitch')::numeric  else front_pitch end,
    camera_fov   = case when p_partial ? 'camera_fov'   then (p_partial->>'camera_fov')::numeric   else camera_fov end,
    motion       = case when p_partial ? 'motion'       then p_partial->'motion'                   else motion end,
    ambient      = case when p_partial ? 'ambient'      then p_partial->'ambient'                  else ambient end,
    updated_by   = v_user_id
  where venue_id = p_venue_id
  returning * into v_row;

  -- 6. Verify the row existed
  if not found then
    raise exception 'venue not found: %', p_venue_id using errcode = '02000';
  end if;

  -- 7. Return the updated row
  return v_row;
end;
$$;

grant execute on function public.rpc_venue_default_update(text, jsonb) to authenticated;

comment on function public.rpc_venue_default_update(text, jsonb) is
  'UPDATE-only partial update of public.venue_defaults. is_platform_admin '
  'gate. Accepts a jsonb of column -> new-value pairs (subset of: back_yaw, '
  'back_pitch, front_yaw, front_pitch, camera_fov, motion, ambient). NOT '
  'NULL columns reject NULL values. Raises 02000 if venue_id does not '
  'exist. Per VENUE-ADMIN-UI-A1-BUILD-SPEC.md §6.';

commit;

-- ─── Verification footer ─────────────────────────────────────────────────
-- Run AFTER COMMIT:
--
-- (1) SELECT proname, prosecdef, pg_get_function_result(oid) AS returns,
--            pg_get_function_arguments(oid) AS args
--       FROM pg_proc
--      WHERE proname = 'rpc_venue_default_update';
--     Expect: 1 row, prosecdef=t, returns='public.venue_defaults',
--             args='p_venue_id text, p_partial jsonb'.
--
-- (2) SELECT has_function_privilege('authenticated',
--            'public.rpc_venue_default_update(text, jsonb)'::regprocedure,
--            'EXECUTE') AS authed;
--     Expect: authed=true.
--
-- (3) SELECT has_function_privilege('anon',
--            'public.rpc_venue_default_update(text, jsonb)'::regprocedure,
--            'EXECUTE') AS anon_authed;
--     Expect: anon_authed=false.
--
-- (4) Confirm the function body contains no INSERT statement against
--     public.venue_defaults:
--     SELECT (pg_get_functiondef(oid) ILIKE '%insert%into%venue_defaults%')
--             AS has_insert
--       FROM pg_proc
--      WHERE proname = 'rpc_venue_default_update';
--     Expect: has_insert=false. The function is UPDATE-only by construction.
-- ============================================================================
```

(The full migration text above is illustrative — the implementation pass refines the exact SQL during the build. Structural shape is what the spec commits to.)

---

## 7. Stage 2 — audio renderer + audio anchor authoring panel + 19-venue programmatic seed

Folded into this same spec as the first vertical slice through the architecture. Stage 2 lands AFTER Stage 1's verification passes; they ship as two separate commits + verifications, not bundled.

Per D8 (§4): Stage 2 ships NO `karaoke/stage.html` read-path change. The authored anchors are dormant data until Stage 6 promotes them to load-bearing.

### 7.1 Audio renderer impl

A new client-side module: `shell/venue-renderers/audio.js` (new directory). Exports a single function `audioAnchorRenderer(anchor, ctx)` that:

- Reads `anchor.payload.sound_id` (the canonical field; see §10 OQ-S1 for the venues.json `soundId` resolution).
- Reads `anchor.payload.type` (`'mp3'` for Stage 2; future types like `'tts'`, `'recorded'`, `'uploaded'` per PHASE-2-BUILD-SPEC.md §3.2 — out of scope here).
- Dispatches to `playAmbientMp3(sound_id)` (the existing infrastructure at `karaoke/stage.html` — refactor to expose it from a shared module if needed; if a quick wrap-and-call works in Stage 2, defer the refactor).
- Returns an object exposing `stop()` (so the registry mechanism can tear down the previous renderer when venue changes).

Registered at karaoke-page load time via:
```js
import { registerAnchorRenderer } from '/shell/venue-registry.js';
import { audioAnchorRenderer } from '/shell/venue-renderers/audio.js';
registerAnchorRenderer('audio', audioAnchorRenderer);
```

Registration sits in `karaoke/stage.html`'s boot section (or extracted to `shell/karaoke-init.js` if a clean location emerges during implementation). The admin-venues.html surface ALSO performs this registration so live preview (§7.4) works. **Critically (per D8): registering the renderer does NOT change which path karaoke reads from. The renderer is registered as available; AMBIENT_PROFILES remains the canonical playback source for the 19 audio-only venues until Stage 6.**

### 7.2 Audio anchor authoring panel (in admin-venues.html)

A new section in the right pane of admin-venues.html, beneath the venue_defaults editor. Visible for ALL venues (every venue can have audio anchors; for procedural venues, Stage 2's authoring still works and Stages 3+ add more anchor types beside it).

For the SELECTED venue:
- Fetch `venue_anchors` rows via `shell/venue-settings.js:loadVenueAnchors({ venue_id })` — existing helper.
- Filter to `type='audio'` for Stage 2's display (later stages add per-type tabs or a unified list).
- Render each anchor as a row with:
  - id (mono, small — readonly post-create)
  - sound_id (text input — references `/sounds/<id>.mp3`)
  - label (text input — optional, used for admin display)
  - is_broken (checkbox — set true to mark a known-missing asset)
  - **Play preview** button — invokes the audio renderer impl directly with the current row's data; **Stop** button to silence.
  - **Save** button (per-anchor, dirty-state tracked separately from the venue_defaults editor)
  - **Delete** button (with confirm)
- "Add audio anchor" button at the top of the list — opens an inline new-row editor.

For Stage 2, the panel exposes ONLY the `audio` type and ONLY the fields above. Anchor positional fields (`yaw_deg`, `pitch_deg`, `start_sec`, `end_sec`, `link`) are NOT exposed in the Stage 2 panel — ambient audio doesn't use them; later anchor types do. Sphere-pinned positional audio (a future feature) would extend the panel.

### 7.3 The 19 audio-only venue anchors — programmatic seed

Each of the 19 audio-only venues gets one new `venue_anchors` row of `type='audio'`, **seeded programmatically as part of the db/035 migration** (§7.5). The row shape per anchor:

```json
{
  "id": "anc_aud_<venue_id>",
  "venue_id": "<venue_id>",
  "type": "audio",
  "yaw_deg": null,
  "pitch_deg": null,
  "label": "Ambient",
  "start_sec": null,
  "end_sec": null,
  "link": null,
  "payload": {
    "type": "mp3",
    "sound_id": "<sound_reference>"
  },
  "is_broken": false
}
```

**Id convention:** stable, deterministic — `anc_aud_<venue_id>` (e.g., `anc_aud_hollywoodbowl`, `anc_aud_kids-dino2`). Deterministic ids make the seed idempotent under `ON CONFLICT DO NOTHING` per the established db/003 pattern.

**`sound_reference` per venue:** the venue_id for 18 of the 19 venues. For **kids-dino2**, `sound_reference` is `"kids-dino"` (the shared sound). The seed encodes this exception directly; `payload.sound_id` is independent of the venue id, supporting sound-reuse for any future shared-sound case.

**The 19 anchors are seeded programmatically via the db/035 migration's seed section — NOT hand-authored through the admin UI.** The sound references are fully known from `AMBIENT_PROFILES` (per the A1 foundation pass's locked enumeration in §2); hand-authoring 19 rows through the UI against a known data set would be busywork. The admin audio panel (§7.2) remains the management/editing surface — used for editing existing anchors, deleting them, adding NEW anchors when new venues land (a Part 2 / post-Phase-5 concern), and the play-preview affordance — but it is NOT the bulk-import path for this initial port.

Per D8 (§4), after the seed lands, `AMBIENT_PROFILES` continues to be the load-bearing path in karaoke. The seeded anchors are dormant data, exercisable only via the admin UI's preview button. Stage 6 promotes them later. Stage 2 itself does NOT touch AMBIENT_PROFILES.

### 7.4 In-surface live preview

Stage 2 adds an embedded preview affordance to admin-venues.html:
- A "Play preview" button per audio anchor, invoking the registered renderer impl directly.
- A global "Stop all preview" button to silence everything.
- Visual indicator showing which anchor is currently playing.

This is the SIMPLEST possible preview infrastructure — direct invocation of the renderer, not a full karaoke stage instance. Stage 3 (particle) and Stage 4 (spotlight) need a richer preview (a render context, a sphere, a camera) — that infrastructure builds incrementally as types are added.

The "Preview in karaoke stage" link from Stage 1 (§5.3 footer) remains as the fidelity-comparison affordance: admin previews via the audio renderer impl in-surface for quick iteration; full visual/audio verification opens karaoke/stage.html — where, per D8, karaoke still reads from AMBIENT_PROFILES. This means the in-surface preview reflects what Stage 6's eventual switchover will sound like; the karaoke-stage link reflects current production. The two should sound equivalent when the same sound file is referenced by both paths — Stage 2 verification (§8.2 Check 10) confirms this comparison.

### 7.5 Stage 2 migration — db/035 (two RPCs + 19-row audio anchor seed)

One migration file, three sections: the two anchor RPCs followed by the 19-row audio anchor seed. Mirrors db/003's established structure (table creation + seed inserts in one file). Atomic apply: RPCs and seed land together.

**Section 1 — `rpc_venue_anchor_upsert`:**

```sql
create function public.rpc_venue_anchor_upsert(
  p_id       text,
  p_venue_id text,
  p_partial  jsonb
)
returns public.venue_anchors
language plpgsql
security definer
set search_path = public
as $$
...
$$;
```

**Section 2 — `rpc_venue_anchor_delete`:**

```sql
create function public.rpc_venue_anchor_delete(p_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
...
$$;
```

Both RPCs structurally identical to `rpc_venue_default_update` (§6) — auth check, is_platform_admin gate, validate keys, key-exists semantics via the `?` operator. Type vocabulary validated against the `venue_anchors_type_check` CHECK constraint (defensive; the DB enforces it too).

The anchor RPC is `_upsert` (not `_update`) because anchors CAN be created through the admin UI — for future new venues, for re-creation after a delete (the §8.2 Check 9 round-trip), and for the future per-app override / anchor_patch UX (Stage 7). The admin UI generates a fresh `id` client-side for new anchors via the panel; the RPC INSERTs on a missing id, UPDATEs on an existing id. The initial 19 audio anchors for the existing audio-only venues are SEEDED (Section 3 below) — they exist before any UI authoring; the `_upsert` shape simply supports the panel's lifecycle operations on top of them.

The `rpc_venue_anchor_delete` body deletes by id. The schema's FK from venue_anchors to venue_defaults is `ON DELETE RESTRICT` (db/032), but that constraint guards against deleting venues with live anchors, not against deleting anchors themselves — anchor delete is unconstrained.

**Section 3 — Audio anchor seed (19 rows):**

Insert one `venue_anchors` row per audio-only venue from §2's locked inventory, following the row shape in §7.3. Use the established db/003 `INSERT ... ON CONFLICT DO NOTHING` pattern for idempotency:

```sql
insert into public.venue_anchors (
  id, venue_id, type, label, payload
) values
  ('anc_aud_hollywoodbowl',  'hollywoodbowl',  'audio', 'Ambient',
   '{"type":"mp3","sound_id":"hollywoodbowl"}'::jsonb),
  ('anc_aud_amphitheater',   'amphitheater',   'audio', 'Ambient',
   '{"type":"mp3","sound_id":"amphitheater"}'::jsonb),
  ('anc_aud_colosseum',      'colosseum',      'audio', 'Ambient',
   '{"type":"mp3","sound_id":"colosseum"}'::jsonb),
  ('anc_aud_drivein',        'drivein',        'audio', 'Ambient',
   '{"type":"mp3","sound_id":"drivein"}'::jsonb),
  ('anc_aud_rooftop',        'rooftop',        'audio', 'Ambient',
   '{"type":"mp3","sound_id":"rooftop"}'::jsonb),
  ('anc_aud_broadway',       'broadway',       'audio', 'Ambient',
   '{"type":"mp3","sound_id":"broadway"}'::jsonb),
  ('anc_aud_supperclub',     'supperclub',     'audio', 'Ambient',
   '{"type":"mp3","sound_id":"supperclub"}'::jsonb),
  ('anc_aud_cabaret',        'cabaret',        'audio', 'Ambient',
   '{"type":"mp3","sound_id":"cabaret"}'::jsonb),
  ('anc_aud_bourbonstreet',  'bourbonstreet',  'audio', 'Ambient',
   '{"type":"mp3","sound_id":"bourbonstreet"}'::jsonb),
  ('anc_aud_saloon',         'saloon',         'audio', 'Ambient',
   '{"type":"mp3","sound_id":"saloon"}'::jsonb),
  ('anc_aud_spacestation',   'spacestation',   'audio', 'Ambient',
   '{"type":"mp3","sound_id":"spacestation"}'::jsonb),
  ('anc_aud_enchantedforest','enchantedforest','audio', 'Ambient',
   '{"type":"mp3","sound_id":"enchantedforest"}'::jsonb),
  ('anc_aud_dragonlair',     'dragonlair',     'audio', 'Ambient',
   '{"type":"mp3","sound_id":"dragonlair"}'::jsonb),
  ('anc_aud_kids-candy',     'kids-candy',     'audio', 'Ambient',
   '{"type":"mp3","sound_id":"kids-candy"}'::jsonb),
  ('anc_aud_kids-dino',      'kids-dino',      'audio', 'Ambient',
   '{"type":"mp3","sound_id":"kids-dino"}'::jsonb),
  ('anc_aud_kids-dino2',     'kids-dino2',     'audio', 'Ambient',
   '{"type":"mp3","sound_id":"kids-dino"}'::jsonb),    -- shared sound
  ('anc_aud_kids-northpole', 'kids-northpole', 'audio', 'Ambient',
   '{"type":"mp3","sound_id":"kids-northpole"}'::jsonb),
  ('anc_aud_kids-princess',  'kids-princess',  'audio', 'Ambient',
   '{"type":"mp3","sound_id":"kids-princess"}'::jsonb),
  ('anc_aud_kids-winter',    'kids-winter',    'audio', 'Ambient',
   '{"type":"mp3","sound_id":"kids-winter"}'::jsonb)
on conflict (id) do nothing;
```

Per `PHASE-2-BUILD-SPEC.md` §7's "minimal seed/import path" guidance: *"the existing migration-INSERT pattern IS the path; when authored venue data first exists, a future migration uses that pattern to seed it."* The 19 audio-only venues are exactly that data — fully known from `AMBIENT_PROFILES` and ready to seed.

The `enchantedforest` row uses `sound_id = "enchantedforest"` (NOT `"forest"`) per OQ-S1's resolution in §10 — matches the AMBIENT_PROFILES entry's hardcoded `playAmbientMp3('enchantedforest')` rather than the unused `soundId: "forest"` field in venues.json.

**Migration scaffolding** matches db/034 (§6.6) — header comment block, BEGIN/COMMIT, DROP+CREATE per RPC, **REVOKE FROM PUBLIC + REVOKE FROM anon + GRANT TO authenticated per RPC** (per the Stage A1 verification log's Bug 2 doctrine: Supabase's `ALTER DEFAULT PRIVILEGES` auto-grants EXECUTE to anon, so REVOKE FROM PUBLIC alone is insufficient — REVOKE FROM anon is the load-bearing fix). The seed section follows the RPC sections, before COMMIT. Verification footer queries: 4 per RPC (existence + grants + INSERT check + REVOKE confirmation) plus 2 for the seed (count + per-venue sound_id correctness).

### 7.6 Out of scope for Stage 2

- Particle renderer impl (Stage 3).
- Spotlight renderer impl (Stage 4).
- Other anchor type renderers (Stage 5).
- AMBIENT_PROFILES retirement for the 19 audio venues (Stage 6).
- Per-app override editor (Stage 7).
- Costume editor (Stage 8).
- The 5 procedural venues (still on AMBIENT_PROFILES path; Stages 3-6 translate them).
- The 2 no-ambient venues (default, vegas; see §10 OQ-V1).
- ANY change to karaoke/stage.html's reader path (per D8 — AMBIENT_PROFILES-first stays in force).

---

## 8. Verification protocol — propose-pause-apply-verify rhythm

Mirrors the cadence used for Items 5/6, Tier 1, and 595e004. Each Stage is a separate cycle.

### 8.1 Stage 1 verification (post-apply)

Run against prod GitHub Pages + prod Supabase after db/034 is applied and admin-venues.html is deployed.

**Check 1 — Admin-only access.**
- Signed-out browser: load admin-venues.html → renders sign-in prompt, not the editor.
- Signed-in non-admin (a test user without `profiles.is_platform_admin = true`): load admin-venues.html → renders "not authorized," not the editor.
- Signed-in admin (Mike, the established test account): load admin-venues.html → renders the editor with the 26-venue list.

**Check 2 — Read-only identity display.**
- Select any venue. Confirm the read-only header shows the venue_id, name, icon, category, skybox image (or "(no skybox)" for default).
- Confirm there is no editable affordance on those fields.

**Check 3 — Edit + save flow.**
- Select `default`. Change `back_yaw` from its current value to a new value. Confirm Save button enables.
- Click Save. Confirm status changes to "Saving..." then "Saved" briefly.
- Refresh the page; confirm the saved value persists.
- Open `karaoke/stage.html?venue=default` in a new tab; confirm the new value is reflected (modulo karaoke's existing rendering — visual check).

**Check 4 — Dirty-state navigation warning.**
- Edit a venue (don't save). Try to navigate away (close tab, navigate to another URL). Browser fires native confirm.
- Cancel; confirm the editor still shows the dirty state. Save; confirm the warning no longer fires.

**Check 5 — RPC authority gate.**
- From a non-admin signed-in browser, open DevTools and call `await window.sb.rpc('rpc_venue_default_update', { p_venue_id: 'default', p_partial: { back_yaw: 999 } })`. Confirm error response with code `42501`.
- From admin browser, same call succeeds.

**Check 6 — Per-venue verification SQL.**
```sql
select venue_id, back_yaw, back_pitch, front_yaw, front_pitch, camera_fov,
       motion, ambient, updated_at, updated_by
from public.venue_defaults
where venue_id = '<edited-venue-id>';
```
Confirm the row reflects the edit; `updated_by` matches admin user UUID.

**Check 7 — Missing-row refusal (UPDATE-only behavior).**
- From admin browser, DevTools: `await window.sb.rpc('rpc_venue_default_update', { p_venue_id: 'definitely-not-a-real-venue', p_partial: { back_yaw: 1 } })`.
- Confirm error response with code `02000` ("venue not found"). Confirm no row was inserted (SELECT against venue_defaults filtered by that id returns zero rows).

Stage 1 PASSES when all 7 checks pass. Failures get diagnosed per propose-pause discipline.

### 8.2 Stage 2 verification (post-apply)

Run after db/035 + the audio renderer + admin-UI audio panel ship.

**Check 8 — Audio renderer registered.**
- Load `karaoke/stage.html`. DevTools console: `window.elsewhere.anchorRegistry.getAnchorRenderer('audio')` returns the impl (not null). The registry is exposed on `window.elsewhere.anchorRegistry` per `shell/venue-registry.js:236-239`, not as a bare `window.getAnchorRenderer` global.

**Check 9 — Seed verification + admin panel round-trip.**

The 19 audio anchors are seeded by db/035's seed section (§7.5), not hand-authored. Check 9 verifies the seed landed correctly + that the admin audio panel's create/edit/delete + preview lifecycle works on the seeded data.

**Step 1 — Verify the seed landed (SQL).**

```sql
-- (a) Total count
select count(*) from public.venue_anchors where type = 'audio';
-- Expect: 19.

-- (b) Per-venue sound_id correctness
select venue_id, payload->>'sound_id' as sound_id, label
from public.venue_anchors
where type = 'audio'
order by venue_id;
-- Expect 19 rows. For all 18 non-shared venues: sound_id = venue_id.
-- For kids-dino2 specifically: sound_id = 'kids-dino' (the shared sound).
-- label = 'Ambient' for all 19.
```

**Step 1(c) — Idempotency.** The whole db/035 file is safe to re-run: the RPC sections use `DROP FUNCTION IF EXISTS` and the seed uses `ON CONFLICT (id) DO NOTHING`. Verify by re-running db/035 in the SQL Editor a second time, then re-running (a) and (b) above; the audio-anchor count must stay at 19 and no row contents may change.

**Step 2 — Verify path equivalence on 3 venues (random selection from the 19).**

For each selected venue:
- In admin-venues.html, select the venue. The seeded audio anchor appears in the panel. Click Play preview — note what plays through the renderer.
- Open `karaoke/stage.html?venue=<id>` — note what plays through AMBIENT_PROFILES (the load-bearing path per D8).
- Confirm the two are sonically equivalent (same mp3 file, same loop, no audible difference).

For **kids-dino2** specifically, confirm both paths play kids-dino.mp3 (the seeded `sound_id = "kids-dino"` reference works on the renderer side; the existing AMBIENT_PROFILES dispatcher already handles it on the karaoke side via its `playAmbientMp3('kids-dino')` hardcode).

**Step 3 — Admin panel round-trip on ONE venue (verifies the create/edit/delete + preview path without bulk-authoring).**

- Pick one already-seeded venue (recommend hollywoodbowl — straightforward, no shared-sound case).
- In the admin panel, **delete** the seeded audio anchor for that venue. Confirm via SQL that the row is gone:
  ```sql
  select count(*) from public.venue_anchors
   where venue_id = 'hollywoodbowl' and type = 'audio';
  -- Expect: 0.
  ```
- In the admin panel, **add** a new audio anchor for the same venue with `sound_id = "hollywoodbowl"`. Click Save.
- Confirm via SQL that the row is back:
  ```sql
  select id, payload->>'sound_id' as sound_id
  from public.venue_anchors
  where venue_id = 'hollywoodbowl' and type = 'audio';
  -- Expect: 1 row, sound_id = 'hollywoodbowl'. The id will differ
  -- from the seed's anc_aud_hollywoodbowl (the admin UI generates
  -- its own id) — that's expected; sound_id is what matters for
  -- playback equivalence.
  ```
- Click Play preview on the new anchor; confirm hollywoodbowl.mp3 plays.
- End state matches the seeded state functionally (one audio anchor per venue, kids-dino2 still shares kids-dino's sound).

This one-venue round-trip validates the admin panel's create / save / delete / preview path without requiring 19 hand-authorings. The panel's lifecycle works on the seeded data; that's all Stage 2 needs to verify.

**Check 10 — RPC authority gates.**
- Non-admin calls rpc_venue_anchor_upsert → 42501.
- Non-admin calls rpc_venue_anchor_delete → 42501.

**Check 11 — D8 dormancy invariant (anchor delete unaffects karaoke).**
- During Check 9 Step 3's delete-then-recreate sequence, separately confirm karaoke playback for the round-trip venue (hollywoodbowl) is UNAFFECTED while the anchor is absent — open `karaoke/stage.html?venue=hollywoodbowl` between the delete and the recreate, and confirm hollywoodbowl.mp3 still plays through AMBIENT_PROFILES. This verifies D8's dormancy invariant (deleting a seeded anchor doesn't change karaoke because AMBIENT_PROFILES is still the load-bearing path).

**Check 12 — karaoke/stage.html read path unchanged.**
- Per D8, Stage 2 ships NO changes to karaoke/stage.html's read path.
- `git diff` between Stage-2-merge and Stage-2-merge^ on `karaoke/stage.html`: confirm zero AMBIENT_PROFILES-reader-side changes. Permitted changes are limited to the audio renderer registration (the `registerAnchorRenderer('audio', ...)` call from §7.1) — which is REGISTRATION, not a reader-path change.

Stage 2 PASSES when all 5 checks (Checks 8 through 12) pass.

### 8.3 Per-stage result log

Each stage produces a `docs/SESSION-LOGS/<stage>-VERIFICATION-LOG.md` file recording the verification run, matching the Items 5/6 / 595e004 / Tier 1 §8 pattern. Filenames:

- `docs/SESSION-LOGS/VENUE-ADMIN-UI-A1-STAGE-1-VERIFICATION-LOG.md`
- `docs/SESSION-LOGS/VENUE-ADMIN-UI-A1-STAGE-2-VERIFICATION-LOG.md`

(Names may be shortened during the log-write task; the spec doesn't lock them.)

---

## 9. Cleanup obligations

After Stage 1 + Stage 2 ship:
- Row cleanup pending from prior verifications (Tier 1 §8, Items 5/6, 595e004) — bundle a cleanup pass alongside Stage 1 / Stage 2 verification's row inventory.
- No Stage 1/Stage 2 row cleanup is itself needed beyond the authored anchors — the 19 anchors persist as the live data.
- AMBIENT_PROFILES for the 19 audio-only venues is **NOT** removed in Stage 2 — that's Stage 6's job, paired with the D8 read-path switchover.

---

## 10. Open spec-time investigations

These get resolved while writing the eventual build code (not blocking the spec, but flagged so the implementation doesn't re-discover them).

- **OQ-S1 — `soundId` field in venues.json.** Used by `enchantedforest` (`soundId: "forest"`); CLAUDE.md notes the convention. Is it actively consumed by `playAmbientMp3` or by any other client code? `grep -rn '"soundId"\|\.soundId' karaoke/ shell/ index.html tv2.html` resolves this. If consumed: Stage 2 authors `enchantedforest`'s audio anchor with `payload.sound_id = "forest"` to match the existing routing. If vestigial: author with `"enchantedforest"` and let the unused field die naturally at Stage 6. **Result lands in the Stage 2 verification log as a side finding.**

- **OQ-V1 — `vegas` no-ambient case.** Product decision: leave silent (do nothing in Stage 2; no anchor authored) OR author a vegas ambient mp3 + anchor as part of Stage 2. Recommendation: **leave silent for Stage 2.** Authoring a sound requires an asset that doesn't exist; producing one is product work, not engineering work. If a vegas ambient is later wanted, author one anchor when the asset lands.

These two are the only spec-time questions the implementation must resolve. Everything else in the spec is settled per the foundation pass + D8.

---

## 11. Non-goals (explicit)

The following are NOT in scope and must not be drawn into the Stage 1 / Stage 2 build:

- Stages 3 (particle), 4 (spotlight), 5 (remaining types), 6 (AMBIENT_PROFILES retirement + dead-code cleanup), 7 (per-app override editor), 8 (costume editor).
- Part 2 admin UI (create brand-new venues, with asset-generation pipelines).
- Creating new venue_defaults rows — Stage 1's RPC is UPDATE-only by construction.
- The 5 procedural venues' translation.
- The 2 no-ambient venues' audio authoring (per OQ-V1).
- AMBIENT_PROFILES retirement (Stage 6).
- Dead-code cleanup (Stage 6 — the 3 ghost keys + dragonlair duplicate).
- The remaining UAP §5 Phase 3 parts: scanned-screen sessions, baseline players, audience.html dissolved (Session 9). These follow Plan B's venue work per the Phase 3 scoping report's sequence.
- Phase 4 (games).
- Any rewire of `karaoke/stage.html`'s read path beyond registration of the audio renderer impl in Stage 2 — per D8.
- Migrating `shell/venue-settings.js:saveVenueDefault` from its direct-write path to use the new RPC. (A cleanup that pairs naturally with this work but isn't required for functional scope; defer to a follow-up if it doesn't fall out naturally during Stage 1 implementation.)

---

## 12. What this spec is and is not

This spec is the contract for Stage 1 + Stage 2's implementation. The propose-pause-apply-verify rhythm proceeds against it:

1. **Spec approval** — this document is the propose-pause artifact. Approved spec becomes the build target.
2. **Stage 1 implementation** — admin-venues.html + db/034. Propose the diff; apply; verify per §8.1.
3. **Stage 2 implementation** — audio renderer + admin UI panel + db/035 + the 19 authored anchors. Propose the diff; apply; verify per §8.2.

This spec is NOT:
- A design exploration. The design decisions are locked per §4 (D1-D8).
- A code-complete artifact. Implementation details (the exact RPC body, the exact admin UI component structure, the exact CSS) refine during the build pass.
- A multi-stage build. Stages 3+ get their own per-type specs when their time comes.
- A timeline commitment. Stage 1 + Stage 2 ship when they're ready; no calendar date is implied.

---

## End of spec
