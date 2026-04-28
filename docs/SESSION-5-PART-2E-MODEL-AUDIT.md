# Session 5 Part 2e — Model Audit: participation_role Semantics

**Created:** 2026-04-27 (after shipping 2e.0 + 2e.1, commit `714c677`).
**Purpose:** Surface the gap between the four conceptual karaoke roles documented in `docs/KARAOKE-CONTROL-MODEL.md` and the three enum values in `db/008`'s `participation_role` check constraint. Frame the trade-offs of leaving the schema alone vs. splitting `'audience'` into eligibility-aware values. Lock the decisions needed before any 2e.2/2e.3 work that depends on the resolution.
**Scope:** Cross-cutting across the platform schema (db/008–013), all three apps that share it (karaoke, games, planned wellness), the Elsewhere shell (`shell/auth.js`, `index.html`), and the karaoke surfaces (`singer.html`, `stage.html`, `audience.html`).
**Out of scope:** Any code change. This document only enumerates evidence, frames choices, and recommends. Implementation belongs to a future session.
**Anchored to:** `docs/PHONE-AND-TV-STATE-MODEL.md` for HHU/HHM/NHHU/proximity definitions, and `docs/KARAOKE-CONTROL-MODEL.md` for the four-role karaoke vocabulary.
**Format:** Mirrors `docs/SESSION-5-PART-2E-AUDIT.md` — audit areas, hard blockers, caveats, decisions to lock, phase plan, effort.

---

## TL;DR

1. The `participation_role` enum (`'active'`, `'queued'`, `'audience'`) is **karaoke-shaped vocabulary that the schema labels universal**. Karaoke uses it fully; games/player.html does not call any of the participation RPCs and uses its own Agora-broadcast lobby model; wellness is unimplemented. The "universal" claim in db/008:8 is aspirational, not earned.

2. `'audience'` is **load-bearing for two genuinely different concepts** — Available Singer not queued (HHU + at-home + has-TV; can self-promote to `'queued'`) and pure Audience (NHHU, or HHU not at home, or no TV) — and the existing resolution (`docs/KARAOKE-CONTROL-MODEL.md`:42–49) is **eligibility computed client-side from `participation_role × HHU × proximity × has_tv_device`**. Singer.html 1.5 (commit `714c677`) shipped without that derivation: every `participation_role='audience'` row currently renders the "👁  Watching from the audience" banner, which is **wrong for the Available-Singer-not-queued subset**.

3. Two paths are credible. Either (A) honor the existing client-side eligibility doctrine and **fix singer.html 1.5** to compute eligibility before rendering, leaving the schema untouched; or (B) **split `'audience'` at the schema level** into eligibility-aware values (`'eligible'`/`'ineligible'`, or some equivalent naming). (A) is small (a few hours), local to singer.html, and consistent with the four-role mapping doc. (B) is large (DB migration + 7 SQL touch points + 4 JS RPC sites + every reader), introduces server-side state that has to be kept fresh under proximity changes, and forces a per-app naming choice for a schema that doesn't actually unify across apps anyway.

4. **Recommendation: do (A). Fix the singer-side render to derive eligibility from the existing client-side primitives, then document the doctrine in db/008's header so the next reviewer doesn't propose splitting again.** Defer (B) until a second app actually demands eligibility-as-server-state (probably never; see Area 4).

5. The hardest decision is not naming — it is whether eligibility belongs on the participant row at all. Once it lives in the DB, **mid-session proximity flips** (which the system supports today via the Proximity Settings menu) become participant-row mutations with all the attendant questions: what happens to the queue position, how does the manager react, and what does push notification do for someone who just became ineligible. The client-side derivation sidesteps all of that.

---

## Area 1 — The current model, in plain English

### What the schema says

`db/008_sessions_and_participants.sql:84–98` declares two role columns on `session_participants`:

```sql
control_role       text not null check (control_role in ('manager', 'host', 'none')) default 'none',
participation_role text not null check (participation_role in ('active', 'queued', 'audience')) default 'audience',
```

The header at db/008:6–9 calls this the "universal session + participants schema" and asserts that "all apps — karaoke, games, future wellness — share this schema." `db/008:44` enforces the union: `app text not null check (app in ('karaoke', 'games', 'wellness'))`.

The column comment at db/008:121–129 reinforces the universality: "control_role and participation_role are orthogonal axes — see docs/SESSION-5-PLAN.md Architecture Decision 3." The `pre_selections` jsonb column is described as a generic platform concept whose schema each app defines independently — but `participation_role` itself has a fixed enum, the same for every app.

### What the apps actually do

**Karaoke** is the only app that uses the enum semantically. Singer.html (commit `714c677`) drives all of `screen-home`'s role-aware banner from `currentMyRow.participation_role`. Stage.html (lines 5050–5535 in current `main`) renders the queue panel by filtering and sorting `currentParticipants` on `participation_role === 'queued'`, and the active-singer card on `participation_role === 'active'`. Db/013's `rpc_karaoke_song_ended` (lines 130–155) demotes the active singer to `'audience'` and clears `queue_position`. Db/011's `rpc_session_update_participant` (lines 145–187) is the mutation surface for promotion / demotion / self-queueing. These three SQL files (009, 011, 013) plus the two karaoke HTML files exhaust the karaoke read/write paths.

**Games** does not use the enum at all. `games/player.html:831` defines its own per-player object with `{status: 'active'|'queue'}`. Lines 993, 1205, 1529 use that field for capacity gating ("if active count < playerLimit, set status active else queue") and pure-Agora broadcast — not for any DB participation_role write or read. The pure-function game engines (`games/engine/last-card.js`, `games/engine/trivia.js`, `games/engine/sync.js`) make no reference to participation_role anywhere; the term is karaoke vocabulary that hasn't reached games. Most importantly, the games tile on `index.html` does call `rpc_session_join` (via the shared Way 2 path at index.html:3083), which writes `participation_role='audience'` for any non-manager joining a games session — but **nobody reads that row in games player UI**. The DB row is dead state.

**Wellness** has no implementation. `wellness/README.md` is a five-line placeholder. `docs/SESSION-5-PLAN.md:208` mentions `ask_proximity: true` for wellness in passing, and line 133 sketches `'wait_for_next'` admission mode (yoga-class-cohort batch admit) as a candidate. There is no role manifest, no participant schema, and no RPC contract for wellness.

### What the docs say

`docs/KARAOKE-CONTROL-MODEL.md:23–47` is the authoritative four-role karaoke vocabulary:

| Karaoke UI label | `participation_role` | Additional client-side conditions |
|---|---|---|
| Active Singer | `active` | (none) |
| Queued (sub-state of Available Singer) | `queued` | HHU + at-home + has TV device |
| Available Singer (not queued) | `audience` | HHU + at-home + has TV device |
| Audience | `audience` | NHHU, OR HHU not at home, OR no TV device |

And `docs/KARAOKE-CONTROL-MODEL.md:49` makes the doctrine explicit:

> Eligibility (the "Available Singer" vs "Audience" distinction) is **a client-side, self-only derivation**. Each user computes their own eligibility for their own UI. No cross-user eligibility check is ever required because Session Manager only promotes from queue, and queue entry is self-gated by eligibility at the moment a user taps "Add to Queue."

`docs/SESSION-5-PART-2D-AUDIT.md:39` echoes the same: eligibility is HHU + at-home + has-TV-device, computed client-side, self-only. No server primitive computes it.

### Plain-English summary

The schema is a karaoke vocabulary in universal clothing. The "universal" framing is honest about intent — the *table layout* (sessions + participants + manager + queue_position + pre_selections) really does generalize — but the **enum values** are karaoke's. Games leaves the row inert; wellness will define its own semantics on arrival. Karaoke is the single user, and within karaoke the four-role surface vocabulary is mapped to the three-value enum at the client, with eligibility computed locally from independent primitives. The model is internally consistent, but the column name "participation_role" plus the universal framing primes new reviewers to assume the enum should be expanded rather than that the karaoke UI should compute richer state on top of it.

---

## Area 2 — The audience overload problem

### Where `'audience'` is set

Every site where the schema or RPCs assign `participation_role = 'audience'`:

1. **db/008:93** — column default. Any direct INSERT that omits `participation_role` lands at `'audience'`. (RLS blocks direct INSERT, so this is reached only via the security-definer RPCs below.)
2. **db/009:107–113** — `rpc_session_start` inserts the manager's own initial participant row with `(control_role, participation_role) = ('manager', 'audience')`. Comment at line 107: "they haven't committed to being an active participant yet." This is the manager's own inert default until they queue or take stage.
3. **db/009:141** — `rpc_session_join`'s `p_participation_role` parameter defaults to `'audience'`. Anyone who joins without overriding lands on this value. All four real callers do default through it: index.html:2921 (`handleSameAppRejoin`), index.html:3085 (`handleTvRemoteTileTap` R4 fallback), singer.html:678 (Way 1 `doJoin`), and the stage's own claim flow does not call this at all (TV claims its own session via different paths).
4. **db/010:129, 218** — `rpc_session_promote_to_manager` and `rpc_session_reclaim_manager` insert the new manager's row with `participation_role='audience'` if no row exists.
5. **db/013:144** — `rpc_karaoke_song_ended` sets `participation_role='audience'` and `queue_position=NULL` when demoting the active singer at song end. Same value used for "the just-finished singer" and "someone who never queued."
6. **db/011:157–159** — `rpc_session_update_participant`'s self-transition rules permit `audience↔queued` and `active→audience`. Only manager/host can set `'active'`.

### Where `'audience'` is read

1. **karaoke/singer.html:1897** (post-1.5) — `else if (role === 'audience') banner.textContent = '👁  Watching from the audience'`. **This is the bug.** The 1.5 implementation reads only `participation_role`, not the eligibility derivation. Every Available Singer (HHU + at-home + has-TV who hasn't queued yet) sees the watching-only banner, which is incorrect per `docs/KARAOKE-CONTROL-MODEL.md:46`.
2. **karaoke/stage.html** — the queue panel (lines 5466–5535 in current `main`) renders only `'active'` and `'queued'` rows; everyone else is invisible to the panel. There is no UI distinction between Available Singer and Audience on the TV today, which is intentional per the role model — the TV doesn't need to know who's eligible to sing because it doesn't render audience tiles.
3. **karaoke/audience.html** — does not subscribe to participants at all. It uses Agora `setClientRole('audience')` (the Agora SDK concept, completely unrelated) to consume the stage's video stream. The page is a frozen surface per `docs/INFRA.md` and `docs/KARAOKE-CONTROL-MODEL.md:5` — no Session 5 participation work.
4. **db/013:rpc_karaoke_song_ended** — finds the active singer by `participation_role='active'` (no read of `'audience'`), demotes by setting `'audience'`. The "find the next" logic (db/011:rpc_session_promote_self_from_queue, lines 395–417) reads `'queued'`, not `'audience'`.

### The conflation, in code

The conflation is most visible in three places:

- **db/009:113** sets the manager to `'audience'` to mean "in the session but not committed yet." Most managers are HHU-at-home-with-TV, so they're Available Singers, not Audience proper. The manager's first-time experience would be: open karaoke, become the manager, see (in singer.html) "👁  Watching from the audience" — wrong-tone, wrong-action-set.
- **db/013:144** sets the just-finished singer to `'audience'` after their song. Per `docs/KARAOKE-CONTROL-MODEL.md:151`, this is intentional — they "transition to Available Singer (no queue entry — they can re-queue if they want another turn)." The schema value is `'audience'`; the surface meaning is Available Singer; the singer.html banner currently calls them watching-only. Same bug, same root cause.
- **index.html:3085** (R4 fallback for active-session collision) and **index.html:2921** (`handleSameAppRejoin`) both pass `p_participation_role: 'audience'`. The intended meaning is "rejoin the session in a non-active default state," but the same value is reached via Way 1 (singer.html:678) where the user might be NHHU, not at home, or have no TV device — and the row is the same.

### Is the conflation a bug, intentional, or load-bearing?

**Intentional and load-bearing in the schema**, **a presentation bug in singer.html 1.5**.

The schema's intent — per `docs/KARAOKE-CONTROL-MODEL.md:42–49` — is exactly that one DB value ("not active, not queued") covers the full population of "anyone not currently performing or waiting to perform," and the four-role UI vocabulary is computed at the client. This is a deliberate design. The argument for it: every transition into and out of `'audience'` is symmetric in the DB regardless of whether the user is HHU or NHHU. The promotion path (queue → active) only ever pulls from `'queued'`, never directly from `'audience'`. So the DB has no use for the distinction; only the UI does.

The singer.html 1.5 ship missed the eligibility-derivation step. That's a fix in 1 file, not a schema problem.

The genuine schema-level question is whether to **promote** the conflation from "deliberate platform simplification" to "bug requiring split." That depends on whether anything in the system other than the karaoke UI ever needs to distinguish — which is the subject of Areas 3 and 4.

---

## Area 3 — Eligibility primitives

### What eligibility means today

Per `docs/SESSION-5-PART-2D-AUDIT.md:39` and `docs/KARAOKE-CONTROL-MODEL.md:46–49`, **eligibility for karaoke = HHU + at-home (proximity-yes) + has-TV-device**. All three are required; missing any one drops the user to the "Audience" surface label.

### Primitive 1 — HHU status (server-authoritative)

`db/008:166–186` defines `is_tv_household_member(p_tv_device_id uuid) returns boolean`. Three-table join: `tv_devices → households → household_members where hm.user_id = auth.uid()`. SECURITY DEFINER. Used by `rpc_session_start` (db/009:81) as a hard gate — a non-HHU cannot start a session — and by RLS policies (db/008:258, 279) for read access.

`db/008:189–210` defines `is_session_tv_household_member(p_session_id uuid)` — same join with one more hop through `sessions`. Used by RLS and by db/013's `rpc_session_get_participants` auth gate (db/013:210–216).

**Freshness:** evaluated on every RPC call. Authoritative. No caching. The latency is whatever a single PostgREST roundtrip costs (low single-digit ms in the same region).

**Client mirror:** `shell/auth.js:69–76` defines `window.elsewhere.isLikelyHouseholdMember()`:

```js
isLikelyHouseholdMember: () => {
  if (!currentUser) return false;
  try {
    return !!sessionStorage.getItem('elsewhere.active_tv.device_key');
  } catch (_) {
    return false;
  }
}
```

This is the heuristic the in-page code uses without making an RPC call. The comment at auth.js:60–67 explicitly flags it as a heuristic, not RPC-verified, and notes that future swap to the strict server check is intended.

The sessionStorage key `elsewhere.active_tv.device_key` is set by index.html's TV-claim post-route, `handleTvRemoteTileTap()` (around index.html:3088, 3114), and `handleSameAppRejoin()` (index.html:2940). It is *not* set on Way 1 paths (typing the room code on singer.html), so an HHU who deep-links via QR scan straight to singer.html will read as `false` from the heuristic until the next time they pass through the home shell. This is a known gap in the heuristic.

### Primitive 2 — Proximity (user-self-declared)

Despite the name, proximity in this codebase is **not a sensor signal**. There is no Bluetooth, no geolocation, no WiFi-fingerprint. It is a banner question: "Are you at home?"

- **DB column:** `sessions.ask_proximity boolean` (db/008:57). App-manifest snapshot at session-start time. Karaoke and wellness are `ask_proximity: true`, games is `false`.
- **Persisted preference:** `user_preferences(user_id, tv_device_id, preference_key='proximity_prompt_dismissed', preference_value=jsonb_bool)` (db/012:38–46, key constant at db/012:50). Set when the user picks "Don't ask again." Read at banner-firing time.
- **Per-session answer:** sessionStorage key `elsewhere.proximity.<tv_device_id>` (index.html:2016, 2018, 2023–2027). Values `'yes'` / `'no'`. Read by `getProximityAnswer()` (index.html:2023). Set by `handleProximityYes()` (index.html:2167), `handleProximityNo()` (index.html:2186), `handleProximityDontShowAgain()` (index.html:2198), `handleSameAppRejoin()` (index.html:2940), `handleTvRemoteTileTap()` (index.html:3088, 3114).
- **Banner firing rule (4-condition AND):** documented in `docs/PHONE-AND-TV-STATE-MODEL.md:188–204`. User authenticated + HHU + post-login home (not inside an app) + not previously dismissed for this TV + not yet answered for this TV-connection-session.
- **Mid-session changes:** the Proximity Settings menu (index.html:2554–2605) lets the user toggle their answer. Not currently propagated to the participant row — it's pure sessionStorage state read by the home tile renderer.

**Freshness:** sessionStorage is per browser tab session. Cleared on tab close. Re-prompted on next TV-connection unless dismissed permanently. **Not** shared with other devices, not in the DB, not visible to the manager or stage.

### Primitive 3 — has-TV-device

The TV existence signal. An NHHU who is in a household's session but whose phone has no record of a TV-device has nowhere to send "take stage" intents to. In practice this is collapsed into the HHU heuristic (NHHU = no TV record on their device) and not separately computed.

### How eligibility composes

```
eligible :=  isLikelyHouseholdMember()  AND  getProximityAnswer(tv_device_id) === 'yes'
```

The `has-TV-device` term reduces to `isLikelyHouseholdMember()` because the only way to be a household member is to have been bound to a TV device in this session.

Eligibility is **never** computed on the server today. There is no SQL function, no RPC parameter, no column. The `sessions.ask_proximity` flag is *snapshotted* but not *enforced*: if it's `true`, the home tile UI renders the banner; if the user ignores it, the manifest still says `true` but the join still proceeds. Server-side enforcement would require sending the proximity answer up with `rpc_session_join`, and the current contract does not include that parameter.

### Latency / freshness summary

| Primitive | Source | Latency | Stale-safe? |
|---|---|---|---|
| HHU (authoritative) | server, `is_tv_household_member()` | ~ms / RPC | Yes — household_members rarely changes |
| HHU (heuristic, in-page) | sessionStorage `active_tv.device_key` | instant | Stale on Way 1 (deep-link) until next home pass |
| Proximity answer | sessionStorage per tab | instant | Stale across tabs / devices / refreshes |
| Proximity dismissed | DB `user_preferences` | ~ms / RPC | Persistent across devices |
| has-TV-device | derived from HHU | n/a | n/a |

The asymmetry matters: HHU is server-authoritative, proximity is per-tab transient. Putting eligibility on the participant row would mean either (a) treating sessionStorage as the source of truth (write-through to the DB on every banner answer), (b) lifting proximity to the DB as a per-(user, tv) preference (much more durable, but loses the per-session rebound that the banner UX depends on), or (c) computing eligibility once at join time and never updating (mid-session proximity flips become impossible, breaking the existing Proximity Settings menu's contract).

---

## Area 4 — Universal vs app-specific roles

### The schema's universality claim

`db/008:6–9` is unambiguous:

> Session 5 Part 1a. Adds the universal session + participants schema that replaces ad-hoc per-app coordination... All apps — karaoke, games, future wellness — share this schema.

The check constraint at db/008:44 makes the union a hard invariant: only `'karaoke'`, `'games'`, `'wellness'` are valid app values.

### Karaoke fits the enum

The four-role karaoke vocabulary (Active Singer / Queued / Available Singer / Audience) maps to `(active, queued, audience, audience)` with one client-side branch on eligibility. Everything in the queue model — FIFO ordering by `queue_position`, single-active invariant via `session_participants_one_manager` and capacity check at db/011:175–186 — is karaoke's, and karaoke uses it directly. The fit is good.

### Games does not fit the enum and does not use it

Three independent pieces of evidence:

1. `games/player.html:831` defines a parallel `lobbyPlayers` map with its own `status: 'active' | 'queue'` field, transmitted via Agora data-channel and read by player.html itself. None of this state flows through `session_participants`.
2. Searches for `'audience'`, `'active'`, `'queued'` as string-compares against `participation_role` in `games/player.html`, `games/tv.html`, and `games/engine/*.js` return zero hits. The DB row exists (because index.html:3083 calls `rpc_session_join('audience')` for game-tile taps), but the row is **never read** by any games code path.
3. The semantic mismatch is structural. Karaoke's `'queued'` means *next-in-line for one shared resource (the stage)*; games' `'queue'` means *waiting for a player slot to free up under capacity*. These look similar but model different things. Last-card or trivia players in `'queue'` status are not waiting for "their turn"; they're waiting for a seat. Promoting from queue is **automatic on capacity drop** for games and **manager- or self-action** for karaoke. The two queues are unrelated machines.

If we tried to make games use the platform queue (db/011's promotion semantics), we'd lose the capacity-driven auto-promotion that games actually wants. Or we'd have to layer it back as app-specific logic on top, at which point the universal framing buys nothing.

### Wellness is hypothetical

`wellness/README.md` is a placeholder. `docs/SESSION-5-PLAN.md:131–133` mentions `'wait_for_next'` admission mode (cohort batch admission) as a candidate for wellness — distinct from karaoke's `'manager_approved_single'`. Even if wellness adopted the existing enum, the meaning of `'queued'` for a yoga class ("waiting for the next class to start") is different again from karaoke's. The platform's `queue_position` integer doesn't encode "which cohort" — it would have to be reinterpreted.

### Verdict on universality

The **table** generalizes (one row per user per session, control_role and participation_role as orthogonal axes, pre_selections jsonb for per-app state). The **enum values** are karaoke's. Other apps either ignore them (games today) or would re-interpret them with a different surface model (wellness when it ships).

This has consequences for any proposed split of `'audience'`. **Karaoke needs eligibility distinction; games has its own queue model that wouldn't benefit from it; wellness might or might not.** Adding `'eligible'`/`'ineligible'` (or any equivalent split) to the platform enum forces a karaoke-shaped vocabulary even further onto apps that don't share karaoke's semantics, in exchange for fixing a problem that already has a documented client-side solution (`docs/KARAOKE-CONTROL-MODEL.md:49`).

---

## Area 5 — Migration impact (if `'audience'` is split)

This area assumes the most aggressive option: replace the single `'audience'` enum value with a pair like `'eligible'` / `'ineligible'` (or any equivalent pair). Naming is its own decision, locked separately. This area enumerates *what changes* under that hypothesis, regardless of names. Names placeholder: `E` for the at-home-eligible value, `I` for the watching-only value.

### Category map

For each touch point, the table notes whether it becomes `E`, `I`, both (depending on context), or is a comment/log only.

#### A — SQL string literals (participation_role values)

| File:line | Current value | Becomes | Notes |
|---|---|---|---|
| db/008:93 (column default) | `'audience'` | `E` (?) | Default must be one of the two. Picking `E` means "default is eligible" — fine for managers (HHU). Picking `I` means non-eligible — wrong for the common case. **Default should be `E` if anything** but see Decision 7 (whether default is even meaningful or RPC-only). |
| db/009:107–113 (manager init in `rpc_session_start`) | `'audience'` | `E` | Manager is HHU-at-home (otherwise `is_tv_household_member` would have rejected the call). Always eligible. |
| db/009:141 (`rpc_session_join` parameter default) | `'audience'` | (none — param removed?) | Caller must specify. See Decision 6 — RPC contract change. |
| db/010:129, 218 (manager init in promote/reclaim) | `'audience'` | `E` | Same as 009:107–113. Always HHU. |
| db/011:157–159 (self-transition rules) | three rules involving `'audience'` | `E↔queued`, `active→E` | Self-transitions only meaningful for eligible users. An ineligible user (NHHU or not-at-home) should not be able to self-queue. The third rule (`active→audience`) is "step off stage voluntarily" — only the active singer hits this, who is by construction eligible. So it stays `active→E`. |
| db/013:144 (song-end demotion) | `'audience'` | `E` | The just-finished singer was in `'active'`, which requires eligibility. Stays eligible after song end. |

So six of the seven SQL sites become `E` cleanly. Site (a) — db/008:93 — is the column default and is only reached via direct INSERT, which RLS blocks, so the default is dead in practice. Pick `E` defensively.

The hard one is **db/009:141** (the `rpc_session_join` default). Today, four caller sites pass `'audience'` and get a single semantics. Under the split, they'd need to pass `E` or `I` based on the calling user's eligibility. That's a contract change documented in Area 6.

#### B — JS RPC string literals (callers of rpc_session_join with `'audience'`)

| File:line | Caller path | Becomes |
|---|---|---|
| index.html:2921 (`handleSameAppRejoin`) | Way 2 same-app rejoin | `E` if `getProximityAnswer === 'yes'`, else `I` |
| index.html:3085 (`handleTvRemoteTileTap` R4) | Way 2 cross-app collision | same as above |
| singer.html:678 (Way 1 doJoin) | QR / typed room code | `E` if `isLikelyHouseholdMember && getProximityAnswer === 'yes'`, else `I` |
| (potential games path index.html:3083) | Games tile tap | `E` for HHU regardless of proximity (games doesn't ask). `I` for NHHU. **Or** `E` always since games doesn't read participation_role. |

These are the four sites where the code has to compute the eligibility decision before calling the RPC. The decision logic differs per path because each path has different signals available:

- Way 2 paths read `getProximityAnswer(tv_device_id)` from sessionStorage (already in scope at the call sites).
- Way 1 path on singer.html does not read proximity today at all. It would have to either (a) require it and break Way 1 for users who haven't been through the home shell, or (b) default to `I` (audience-only) for any Way 1 user who can't prove eligibility, which contradicts the existing Way 1 design where deep-linked HHUs sing fine.

This is the migration's structural cost: **eligibility decision-making must be lifted out of the singer-side render and into every join-time call site.** Currently it's deferred to render-time and only computed for self-display. Lifting it up requires every joiner to commit to a value at session-join time, which means every call site needs the eligibility primitives in scope.

#### C — JS read-side string literals

| File:line | Read | Becomes |
|---|---|---|
| singer.html:1897 (1.5 banner branch) | `role === 'audience'` | branches on `role === I` (watching banner) and `role === E` (Available Singer banner — different copy) |

Just one read site. Stage.html does not branch on `'audience'` at all; it implicitly groups all non-active/non-queued rows together for non-rendering purposes.

#### D — Comments, logs, doc strings

204 markdown matches across `docs/` per the audience-string-sweep. Most are trivially updateable: the word "audience" in prose stays as "audience" where it means the conceptual role, and is replaced with `eligible` / `ineligible` only in places that cite the enum value literally. This is grep-and-replace work, not engineering.

The four-role karaoke vocabulary table at `docs/KARAOKE-CONTROL-MODEL.md:42–47` becomes a three-row table (Active Singer / Queued / Eligible / Ineligible — directly enum-mapped) with the eligibility-derivation language removed from line 49.

#### Summary count

- 7 SQL string-literal sites that must change.
- 4 JS RPC-call-site sites that must compute eligibility before calling.
- 1 JS read site (singer.html banner) that must branch.
- 1 DB migration to alter the check constraint (and potentially backfill existing data — but at the time of this audit, all existing rows are dev/test data and we are still pre-launch; backfill is trivially `update set participation_role = 'eligible' where participation_role = 'audience'`).
- ~6–10 doc files with substantive paragraphs to rewrite (KARAOKE-CONTROL-MODEL, PHONE-AND-TV-STATE-MODEL, SESSION-5-PART-2-BREAKDOWN, the existing 2E-AUDIT, the 2D-AUDIT, ROADMAP, INDEX).

### Stage.html — what changes?

Stage.html does not currently distinguish Eligible from Audience. The queue panel renders `'queued'` rows; the active card renders `'active'`; everyone else is invisible to the panel. Whether stage.html *should* distinguish is a separate decision (see Decisions to Lock).

If the decision is "no, stage doesn't care," then stage.html requires zero edits — it continues to filter on `'queued'` and `'active'`. The split is invisible to it.

If the decision is "yes, stage shows a viewer count or eligible-but-not-queued list," then stage.html needs new rendering logic plus the realtime sub already gets the data. Cost: small (an extra section in the queue panel), but a real UX decision about whether the TV should reveal who-could-sing-but-hasn't.

### Audience.html — what changes?

`karaoke/audience.html` is a frozen surface (`docs/INFRA.md`, `docs/KARAOKE-CONTROL-MODEL.md:5`). It does not subscribe to participants. It is not affected by any participation_role enum change. The Agora `setClientRole('audience')` call at audience.html:410 is the Agora SDK concept and is unaffected.

---

## Area 6 — RPC contract changes

If we split `'audience'` into `E` / `I`:

### `rpc_session_join` (db/009:131–217)

- **Parameter signature:** the `p_participation_role text default 'audience'` default cannot remain. The DB cannot infer eligibility — it doesn't know proximity. Two options:
  - Drop the default. Every caller specifies `E` or `I`. (4 caller sites updated.)
  - Take a new parameter `p_eligible boolean` and derive the role server-side. Default to one of the two — say, `false` (ineligible) so the safer surface is the default. Callers who know eligibility pass `true`.
- **Authorization:** today, the RPC requires `is_tv_household_member` (db/009:167). NHHUs get a hard reject. Under the split, NHHUs can still join — but they must land on `I`. This is a behavior change: today, NHHU `rpc_session_join` calls fail; under the split, they should succeed with `participation_role=I`. This requires removing the household-member gate from `rpc_session_join`, which has cascading RLS effects. (The gate is currently load-bearing for "you can't join other households' sessions." Removing it would let any authenticated user join any session as `I`. That's probably fine — they can do that already via audience.html — but it's worth flagging.)

Alternative: keep the household-member gate, accept that `rpc_session_join` is HHU-only as it is today, and route NHHU join through a separate path (`rpc_session_join_audience` or similar) that lands them at `I`. This bifurcates the RPC surface but preserves the existing security boundary.

### `rpc_session_update_participant` (db/011:65–232)

- **Self-transition rules at db/011:156–159** must be updated. The three rules become:
  - `E → queued`: ALLOW (self-queue from at-home eligible state)
  - `queued → E`: ALLOW (self-leave the queue back to eligible-but-not-queued)
  - `active → E`: ALLOW (step off stage; assumes the active singer was eligible, which they are by construction)
  - `I → queued`: **explicit DENY** with a clear error message ("not eligible to queue from audience-only role"). Currently this would have been allowed under `audience → queued` because the schema didn't distinguish.
  - `queued → I`, `active → I`: probably DENY for self. An eligibility flip mid-session should not be a participant-row mutation initiated by the user — it should be a manager/host action or an explicit "I'm leaving home" workflow with its own RPC.
- **Mid-session eligibility flip:** if the user toggles their proximity answer mid-session via the existing Proximity Settings menu, what happens? Today: nothing in the DB changes; only their local sessionStorage flips. Under the split: either nothing changes (eligibility is captured at join time and never updates) — which makes the menu inconsistent with the DB — or the toggle issues an `rpc_session_update_participant` to flip `E ↔ I`. The latter raises real questions: a queued user who flips to ineligible should have their queue position cleared; a manager who flips ineligible should still be the manager (control_role is orthogonal); what does push notification do for someone who flipped ineligible mid-session? See Decisions to Lock.

### `rpc_session_get_participants` (db/013:185–242)

The returned table includes `participation_role`. Under the split, that column now returns `'eligible' | 'ineligible' | 'queued' | 'active'`. Consumers must update their reads (single site: singer.html:1897 in karaoke; stage.html doesn't read `'audience'`). No structural change to the function.

### `rpc_session_start` (db/009:54–128)

The manager's initial row at line 113 currently writes `'audience'`. Under the split, write `E`. The manager is by construction HHU (gate at line 81), and since they just opened the home tile to start a session and answered the proximity prompt, they're at-home. Eligibility is implicit.

### `rpc_karaoke_song_ended` (db/013:130–155)

The demotion at line 144 currently sets `'audience'`. Under the split, set `E`. The just-finished singer was active, which requires eligibility, so they stay eligible. (If their proximity flipped between song start and song end, that's a separate concern handled by the eligibility-flip path above.)

### Summary of RPC changes

- `rpc_session_join`: parameter default change OR signature change (extra `p_eligible` arg). Possibly auth gate change.
- `rpc_session_update_participant`: self-transition rule expansion. Capacity check unchanged.
- `rpc_session_get_participants`: no structural change (consumers update reads).
- `rpc_session_start`: trivial substitution.
- `rpc_session_promote_to_manager` / `rpc_session_reclaim_manager` (db/010): trivial substitution.
- `rpc_karaoke_song_ended`: trivial substitution.

Plus a new RPC if we decide to model eligibility flips: `rpc_session_set_eligibility(session_id, eligible boolean)` that updates the caller's own row and applies the queue-clearing side effect. Or pin eligibility at join and leave it.

---

## Hard Blockers

### B1 — Mid-session proximity flip semantics are undefined

**Severity:** Specification-level blocker for any schema-side eligibility model.

**Symptom:** The Proximity Settings menu in index.html:2554–2605 lets users toggle their answer at any time. Today this is a sessionStorage-only flip with no server effect. If eligibility moves to the participant row, the toggle either becomes a no-op (the menu lies about its effect) or it issues an RPC, with all the cascading questions in Area 6. There is no design today for what happens to a queued user who becomes ineligible — does their queue position vanish? Does the manager get notified? Does their pre-selection clear?

**Resolution required:** Decision 6. Until this is locked, a schema split is a half-built model with surprise behaviors waiting at the first proximity toggle.

### B2 — Way 1 deep-link eligibility computation has no proximity signal

**Severity:** Functional blocker for Way 1 if eligibility is committed at join time.

**Symptom:** singer.html's `doJoin()` runs after a QR scan (the user never passes through the home shell) or a typed room code. The sessionStorage proximity key is set only by the home shell (via index.html's banner handlers and `handleTvRemoteTileTap` / `handleSameAppRejoin`). On a clean Way 1 deep link, `getProximityAnswer(tv_device_id)` returns null. There is no fallback today — Way 1 just doesn't ask.

If eligibility is committed at join time, Way 1 must either (a) trigger the proximity banner inside karaoke/singer.html (significant UX redesign — the banner is currently home-shell-only), (b) default Way 1 users to `I` (which breaks the common case of an HHU singing from a deep-linked QR), or (c) default Way 1 users to `E` (which lets NHHUs deep-link to singer.html and self-queue, breaking the security model).

**Resolution required:** if we go with the schema split, the design for Way 1 eligibility-at-join-time must be locked first.

### B3 — Production data is ahead of dev — verify before migrating

**Severity:** Operational — small but real.

**Symptom:** Pre-launch but the deployed Pages site has been used by the developer's own household for testing. Some `participation_role='audience'` rows likely exist. A migration that alters the check constraint must either drop and recreate (briefly disallowing the column under load — but no live load exists) or use `alter table … drop constraint … ; alter table … add constraint …` with a backfill in between.

**Resolution:** confirm that all existing `'audience'` rows are migrate-to-`E`-safe (they should be; at present, all callers either pass `'audience'` for HHU users via Way 2 paths, or via Way 1 where the user almost certainly is an HHU since unauthenticated NHHUs can't pass `is_tv_household_member`). The mass UPDATE is single-statement.

---

## Caveats

### C1 — Naming "eligibility" is a karaoke metaphor

The word **eligible** describes "able to perform" in karaoke. For games, it would describe "able to play this hand." For wellness (cohort-batch class), it would describe "in this class cohort." These are different things. Lifting "eligibility" into the platform vocabulary inherits the karaoke meaning into apps that don't share it. The user's own example (audience splits into eligible / ineligible) is shaped by karaoke; it does not generalize cleanly.

This pushes back on (B). If we split, the names should be karaoke-flavored, and the platform comment should acknowledge the karaoke origin. Or the names should be aggressively neutral (`'present'` / `'remote'`, `'in_set'` / `'observer'`) and the platform claim of universality should be retired in favor of "karaoke-shaped, used as-is by other apps with their own semantics."

### C2 — Push notification scope changes under the split

The 2e.0 push infrastructure is wired to `rpc_register_push_token` and the planned 2e.2 work fires a push on `'queued' → 'active'` transition. Under the split, ineligible (`I`) users should never receive that push — they can't be promoted. This is currently enforced naturally (an `I` user can never reach `'queued'`), but a server-side push trigger that filters by `'queued'` works correctly without further changes. Worth verifying when 2e.2 ships.

### C3 — Stage.html implicit "everyone else is audience" assumption

Stage.html's queue panel renders `'queued'` rows and the active card renders `'active'`. The implicit complement — "everyone else is audience-or-eligible, render nothing" — is fine today. If a future feature adds a viewer-count or eligible-list to the TV, it would need to explicitly distinguish. Worth noting when scoping any future stage UI.

### C4 — The 1.5 banner bug exists regardless of which path we take

Whether we go (A) keep schema, fix client-side rendering or (B) split schema, both paths require fixing singer.html:1881–1891 to render the right banner for each surface label. Under (A), the fix is "compute eligibility from primitives, branch on the result." Under (B), the fix is "branch on the now-distinct enum value." The amount of UI code change is similar; the difference is upstream of the render.

### C5 — Manager's initial state is currently `'audience'` — UX-visible bug

`rpc_session_start` (db/009:113) writes `(control_role, participation_role) = ('manager', 'audience')`. The manager is invariably HHU-at-home. Singer.html 1.5's banner reads `role === 'audience'` and shows "👁  Watching from the audience" — but the manager, freshly minted, sees this banner and the wrong call-to-action. This is the most visible single instance of the conflation today and should be the first thing fixed regardless of which path we take.

---

## Decisions to lock at next-session-start

Mirroring the existing 2E-AUDIT format. Each decision frames real options A/B/C with implications and a recommendation.

### Decision 1 — Schema-split vs. client-side derivation

**Question:** Do we add new enum values to `participation_role`, or fix the issue at the client?

| Option | Approach | Implications |
|---|---|---|
| **A — Keep schema, fix client** | Honor `docs/KARAOKE-CONTROL-MODEL.md:49`. Add an `isEligible()` helper to singer.html that reads HHU + proximity primitives. Branch the banner on `isEligible() && currentMyRow.participation_role === 'audience'` for "Available Singer (not queued)" vs the watching-only banner. Document the doctrine in db/008's header so reviewers don't propose splitting again. | Smallest change. Local to singer.html. Preserves the platform schema's app-agnostic intent. Doesn't touch Way 1 join semantics. ~2 hr |
| **B — Schema split with two values** | Replace `'audience'` with `E` and `I`. Update 7 SQL sites + 4 JS RPC call sites + 1 JS read site + 1 column default + auth gates. Migration. New transition rules. | Largest change. Solves the conflation at the source. Forces every joiner to commit to a value at join time. New semantics for mid-session proximity flips. ~12–16 hr including DB migration. |
| **C — Add a separate eligibility column** | Keep `participation_role` as-is (`'active', 'queued', 'audience'`). Add `session_participants.eligibility text not null default 'eligible' check (eligibility in ('eligible','ineligible'))`. Computed at join time, mutable via a new RPC. Singer.html branches on the new column. | Avoids touching the existing enum (safer migration). Adds a new column to keep in sync. Two columns to reason about for transitions. Same Way-1 / proximity-flip semantic questions as (B). ~10 hr. |
| **D — App-defined extra roles in pre_selections** | Keep schema as-is. Karaoke writes `pre_selections.eligibility = 'eligible'/'ineligible'` at join time. Reads at render. Other apps ignore. | No DB migration. Karaoke-only. But pre_selections is meant for app-specific *content* (song, venue, costume), not roles. Misuses the column's intent. ~3 hr. |

**Recommendation: A.** The four-role karaoke vocabulary already maps cleanly to the three-value enum via client-side derivation, the doctrine is documented, and games/wellness analysis (Area 4) shows the "universal" framing of the enum is already aspirational — adding more values doesn't make it more universal, it just spreads karaoke vocabulary further. The 1.5 bug is a render bug, not a schema bug. Fix it in the right layer.

If the user disagrees and wants the schema to express the distinction explicitly, **C** is the safer migration than **B** — adding a column is reversible, expanding an enum across half the SQL surface less so. **D** is a hack and should be ruled out.

### Decision 2 — Naming (only if Decision 1 = B or C)

**Question:** What do we call the two states?

| Option | Names | Implications |
|---|---|---|
| **A — `'eligible'` / `'ineligible'`** | Eligibility-centric. | Karaoke metaphor. Reads naturally for "able to sing." Less natural for games / wellness if they ever adopt. |
| **B — `'present'` / `'remote'`** | Physical-location-centric. | Decouples from any app's role semantics. But "remote" is misleading — an NHHU at the venue isn't remote, they just can't sing. |
| **C — `'available'` / `'audience'`** | Karaoke surface vocabulary. | Reuses the four-role doc's language. "Available" matches "Available Singer." But "audience" overlaps the page name `audience.html` and Agora's `setClientRole('audience')`, deepening existing terminology confusion. |
| **D — `'singer'` / `'observer'`** | Role-action-centric. | Most karaoke-flavored. Doesn't generalize. |
| **E — `'in_set'` / `'observer'`** | Aggressively neutral. | "In_set" is awkward; nobody would propose this twice. Pass. |

**Recommendation: A** if Decision 1 is B/C. The karaoke flavor is honest about the metaphor's origin, the DB header can document it, and other apps can either adopt or ignore. **C** is tempting for vocabulary alignment but the audience-overload problem in audience.html / setClientRole / DOM ids would persist (the singular word "audience" does too much work in this codebase already).

### Decision 3 — Where eligibility is computed

**Question:** Where does eligibility live, regardless of whether Decision 1 = A, B, or C?

| Option | Approach | Implications |
|---|---|---|
| **A — Client-side, self-only (existing)** | Each phone computes its own eligibility from local primitives (sessionStorage proximity + HHU heuristic + has-TV). Used only for self-display and self-queue gating. | Status quo per `docs/KARAOKE-CONTROL-MODEL.md:49`. Cheap, fast, decentralized. Doesn't survive page reload without re-running the home shell (Way 1 gap). |
| **B — Server-side, snapshotted at join** | Phone passes proximity answer to `rpc_session_join`. Server computes eligibility from HHU (server-known) + proximity (passed from client) and writes to participant row. Mutable via separate RPC. | Authoritative. Survives reloads. Adds a parameter to the join RPC. Mid-session changes need a new RPC. |
| **C — Server-side, derived continuously** | Eligibility is a SQL view computing HHU at query time + reading a per-(user, tv) proximity preference from a new DB column (replacing sessionStorage). | Most server-driven. Most invasive — changes proximity from per-session-tab UX to per-(user, tv) durable preference, breaking the existing banner re-prompt UX. |

**Recommendation: A** if Decision 1 = A. **B** if Decision 1 = B/C. **C** is overkill — the proximity UX is intentionally per-tab-session.

### Decision 4 — Mid-session eligibility flips

**Question:** What happens when a user toggles proximity mid-session?

| Option | Approach | Implications |
|---|---|---|
| **A — No DB effect (status quo)** | sessionStorage flip only. Banner re-renders. Manager and stage unaware. | Current behavior. Inconsistent if Decision 1 = B/C, because the DB no longer tracks the local truth. |
| **B — DB-flip via new RPC, queue-cleared on becoming ineligible** | Toggle issues `rpc_session_set_eligibility`. If queued and flipped to ineligible, queue_position cleared and manager notified via realtime event. | Most expressive. Many edge cases — what if the user is the active singer? What if they're the manager? |
| **C — Forbid mid-session flips (lock at join)** | Proximity Settings menu becomes disabled for active sessions. User must leave and rejoin to change. | Simplest server-side semantics. UX regression — the Proximity Settings menu currently works mid-session. |

**Recommendation: A** if Decision 1 = A (no schema change, no inconsistency). **B** if Decision 1 = B/C and we want fidelity. **C** if Decision 1 = B/C and we want simplicity over fidelity.

### Decision 5 — Whether stage.html distinguishes eligible from audience

**Question:** Does the TV care?

| Option | Approach | Implications |
|---|---|---|
| **A — No, stage stays as today** | Renders `'queued'` and `'active'` only. Eligible-but-not-queued and audience are both invisible to the TV. | Status quo. Zero stage.html changes. |
| **B — Yes, show viewer count** | TV shows "5 watching" or similar. Distinguishes eligible-not-queued from pure audience optionally. | Adds a small UI element. Opens design questions (privacy: "do I want my name visible on the TV as someone who could sing?"). |
| **C — Yes, show eligible-list** | TV shows the avatars of users who could sing but haven't queued. Manager can tap to "nudge" them. | Significantly more UI. Introduces a soft social pressure mechanic. |

**Recommendation: A.** Adding viewer state to the TV is a separate UX project. Not a Session 5 concern.

### Decision 6 — Default `participation_role` on `rpc_session_join` (only if Decision 1 = B/C)

**Question:** What's the default for callers who don't specify?

| Option | Approach | Implications |
|---|---|---|
| **A — Drop the default** | Caller must specify. | Forces every site to make the decision. Slightly more verbose; safer. |
| **B — Default to `I`** | Safer surface. Callers who know eligibility upgrade. | Reasonable — `I` is the lower-privilege state. |
| **C — Default to `E`** | Convenience for Way 2 paths where eligibility is implied. | Risky for Way 1 deep links from NHHUs. |

**Recommendation: A.** With four call sites, the cost of explicitness is small.

### Decision 7 — Whether `rpc_session_join` accepts NHHUs at all (only if Decision 1 = B/C)

**Question:** Today the RPC has a hard HHU gate (db/009:167). Under the split, NHHUs can theoretically join as `I`. Do we let them?

| Option | Approach | Implications |
|---|---|---|
| **A — Keep HHU gate; route NHHU through audience.html only** | NHHUs use audience.html (no participation_role row). HHU only for `rpc_session_join`. | Status quo for security boundary. Audience.html is the NHHU surface; it doesn't need a participant row. |
| **B — Drop HHU gate; NHHUs join as `I`** | NHHUs get a participant row. Singer.html could be opened by NHHUs (with `I` role). | Breaks the existing assumption that singer.html is HHU-only. Increases attack surface. |
| **C — Bifurcate RPCs: `rpc_session_join` HHU-only, `rpc_session_join_audience` NHHU-allowed** | Two paths. Each preserves its own security boundary. | Most flexible. Most surface area. |

**Recommendation: A.** NHHUs are well-served by audience.html today. There's no demand for them to have a `session_participants` row. Don't build it.

### Decision 8 — Document doctrine in DB header (regardless of path)

**Question:** Should db/008's header explicitly call out the karaoke-shaped vocabulary and the eligibility-derivation pattern?

**Recommendation: yes, always.** Whatever Decision 1 lands, db/008's introductory comment should be updated to reflect reality:

- If Decision 1 = A: add a paragraph saying "the `'audience'` value covers both watching-only and eligible-but-not-queued; per-app surface vocabulary derives finer states client-side."
- If Decision 1 = B/C: replace the universal-framing language with "this enum is karaoke-shaped; other apps either ignore it (games) or reinterpret it with their own semantics (wellness)."

This is the lowest-cost intervention and prevents the next reviewer from re-asking the same question.

---

## Phase plan recommendation

The phase plan depends on Decision 1.

### If Decision 1 = A (recommended)

**Phase 2e.1.1 — Eligibility helper + singer.html banner fix (~1.5 hr)**

- Add an `isEligible()` helper in singer.html that reads `window.elsewhere.isLikelyHouseholdMember()` and `sessionStorage.getItem('elsewhere.proximity.<tv_device_id>') === 'yes'`.
- Branch `renderSessionUI()`'s `'audience'` arm: if eligible, render the "You can sing — Add to Queue" banner; else render the existing "👁 Watching from the audience" banner.
- For Way 1 deep-links where proximity is null, fall back to the conservative "watching" banner with a "Set proximity" link that takes the user to the home shell (or pops the banner inline). Lock the inline approach if it's cheap.

**Phase 2e.1.2 — DB doctrine doc update (~30 min)**

- Update db/008:6–9 header to note the karaoke-shaped enum + client-side eligibility derivation.
- Update `docs/KARAOKE-CONTROL-MODEL.md` if any line drifted out of date.

**Phase 2e.1.3 — Manager initial-state UX touchup (~30 min)**

- Verify and document that when a manager starts a session, their banner shows the right surface label. The fix from 2e.1.1 covers this — manager is HHU-at-home (gate at db/009:81), so `isEligible()` returns true, so they see the Available-Singer banner. Confirm on device.

**Total under (A): ~2.5 hr.** 2e.2 and 2e.3 proceed as originally scoped in `docs/SESSION-5-PART-2E-AUDIT.md`.

### If Decision 1 = B (schema split with new enum values)

**Phase 2e.M.1 — DB migration (~3 hr)**

- New migration `db/014_eligibility_role_split.sql`.
- `alter table session_participants drop constraint participation_role_check;`
- `update session_participants set participation_role = 'eligible' where participation_role = 'audience';` (verify all existing rows are HHU first; pre-launch this is safe).
- `alter table session_participants add constraint participation_role_check check (participation_role in ('active', 'queued', 'eligible', 'ineligible'));`
- Update `rpc_session_start`, `rpc_session_join`, `rpc_session_update_participant` (transition rules), `rpc_karaoke_song_ended`, `rpc_session_promote_to_manager`, `rpc_session_reclaim_manager`. Six SQL functions touched. New RPC `rpc_session_set_eligibility` if Decision 4 = B.
- Verify in Supabase Studio.

**Phase 2e.M.2 — Caller updates (~3 hr)**

- index.html:2921, 3085: compute eligibility before calling `rpc_session_join`. Way 2 has the proximity answer in scope.
- singer.html:678: compute eligibility before calling. Way 1 either fails closed (default `I`), triggers the proximity banner inline, or rebounds through home. Lock approach via Decision 4.
- singer.html:1897: branch the banner on the new enum values.
- Stage.html: zero changes if Decision 5 = A.

**Phase 2e.M.3 — Doc updates (~2 hr)**

- KARAOKE-CONTROL-MODEL: rewrite the four-role mapping table to be schema-direct.
- PHONE-AND-TV-STATE-MODEL: update Modes A/B/C language if it overlaps.
- SESSION-5-PART-2-BREAKDOWN, SESSION-5-PART-2D-AUDIT, SESSION-5-PART-2E-AUDIT: scrub for `'audience'` literals.
- DEFERRED.md: any deferred items that depend on the old enum get re-scoped.

**Phase 2e.M.4 — Mid-session flip RPC + proximity menu wiring (~3 hr; only if Decision 4 = B)**

- New `rpc_session_set_eligibility(session_id, eligible boolean)`.
- Hook the existing Proximity Settings toggle in index.html to call it when there's an active session.
- Handle queue-clearing side effect.
- Wire realtime event for the manager.

**Phase 2e.M.5 — Verification (~2 hr)**

- All four caller paths exercised on device.
- Way 1 / Way 2 / mid-session-flip / NHHU edge cases.

**Total under (B): ~13 hr** (without Phase 4) or ~16 hr (with Phase 4 if Decision 4 = B).

This phase plan precedes 2e.2 (self-write) and 2e.3 (manager) as originally scoped. The total Session 5 Part 2e budget rises from the original 8–11 hr to roughly 21–27 hr if (B) is chosen.

### If Decision 1 = C (separate column)

Roughly 70% of (B)'s effort. The migration is additive (new column with a default), no enum-altering, and the call-site updates have a similar shape but each writes to a separate column rather than overloading `participation_role`. Saves ~3 hr vs (B).

---

## Estimated Effort

| Path | Effort | Where the time goes |
|---|---|---|
| **A — keep schema, fix client** | **2–3 hr** | Singer-side helper, banner branch, DB header doc update |
| **B — split schema** | **13–16 hr** | Migration, six RPCs touched, four JS sites, doc rewrites, optional mid-session-flip plumbing |
| **C — separate column** | **9–11 hr** | Migration is smaller; call-site updates similar; doc rewrites lighter |
| **D — pre_selections hack** | **3 hr** | Misuses the column. Don't. |

**Comparable shipped scope:** 2e.0 was ~2-3 hr (push infrastructure). 2e.1 was ~3-4 hr (read-only role-aware UI). 2d.1 was ~5–6 hr (8 sections). Path A is cheapest and on-budget for the existing 2e total. Path B more than doubles the 2e session.

---

## Summary table

| Concern | Path A (recommended) | Path B (schema split) |
|---|---|---|
| 1.5 banner bug | fixed in singer.html | fixed via enum split |
| db/009:113 manager-init UX | fixed by client derivation | fixed by writing `E` |
| Way 1 deep-link eligibility | works as today (client-derived) | needs Decision 6 redesign |
| Mid-session proximity flip | works as today (sessionStorage only) | needs Decision 4 design |
| games/player.html | unaffected (doesn't read enum) | unaffected (doesn't read enum) |
| wellness future | unaffected | constrained by karaoke-flavored split |
| Documentation drift | one paragraph in db/008 | doc rewrites in 6+ files |
| Migration risk | none | low (single mass UPDATE pre-launch) |
| Reviewer-doctrine clarity | docstring resolves it | resolved by schema |
| Effort | ~2.5 hr | ~13-16 hr |

The audit recommends Path A. Path B is credible but expensive for a problem that has a documented client-side solution and that no other app demands.
