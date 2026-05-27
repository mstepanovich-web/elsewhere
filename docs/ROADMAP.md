# Roadmap

High-level session pipeline so we don't lose context between sessions. Updated at the end of each session and at the start of each planning session.

---

## Active session

**Venue admin UI Part 1 + venue translation — Phase 3 scope, Plan B (UAP §5 / spec §7)**

Phase 2 of the unified-app refactor (the venue abstraction's data layer + resolver + anchor renderer registry mechanism) shipped 2026-05-24 — see "Unified-app workstream — Phase 2: Venue abstraction" in the Completed section below for full commits + verified-prod state. Phases 3, 4, 5 follow per `docs/UNIFIED-APP-PLAN.md` §5. The active entry combines the **Part 1 admin UI (manage the existing 26 venues)** with the **venue translation** (procedural `AMBIENT_PROFILES` + `addVenueEffects3D` → data-driven `venue_anchors` + reusable renderer impls per `docs/VENUE-ADMIN-UI-DIRECTION.md` §7's hybrid sequencing). Part 2 (create brand-new venues, with asset-generation pipelines) remains post-Phase-5 per VENUE-ADMIN-UI-DIRECTION.md §3 / Decision 2.

- **Authoritative direction:** `docs/VENUE-ADMIN-UI-DIRECTION.md` (Plan B revision, 2026-05-26, `c076f12`). Reverses the earlier wrap-as-legacy framing recorded in `df49366`; see that note's status header for the rationale.
- **Authoritative build spec:** `docs/VENUE-ADMIN-UI-A1-BUILD-SPEC.md` (committed `cf2585c`, revised `8187c5d` + `647c31b`). §7 is the canonical A1–A8 staging — the per-stage breakdown supersedes the loose "per-type addenda follow" placeholder this bullet used to carry. PHASE-2-BUILD-SPEC.md §7 (the original admin-UI scope decision) and VENUE-ADMIN-UI-DIRECTION.md §7 (the Plan-B sequencing) remain authoritative for the higher-level direction.
- **Sequencing — locked by Plan B:** admin UI skeleton first, then per-type vertical slices that build renderer impl + UI panel + translate the venues that use that type. Audio first (19 venues), particle next (~6 venues), spotlight after (3 venues + 3D builders). `AMBIENT_PROFILES` + `addVenueEffects3D` retire from `karaoke/stage.html` once every procedural venue has a data-driven equivalent that renders visually identically. Block B follows — the karaoke reader-path rewire that switches `karaoke/stage.html` onto the shell renderer + registry, completing the Phase-3 karaoke half. Detail in VENUE-ADMIN-UI-A1-BUILD-SPEC.md §7.
- **Status:** **In progress.** Stage A1 (admin UI skeleton + `venue_defaults` editor + db/034 `rpc_venue_default_update`) shipped 2026-05-26 — commits `9cf4b70` + path fix `606674f`; verification log `f610039`. Stage A2 (audio renderer impl `shell/venue-renderers/audio.js` + audio anchor authoring panel + 19-venue audio seed + db/035 `rpc_venue_anchor_upsert` / `rpc_venue_anchor_delete`) shipped 2026-05-26 — commit `9d58a8d`; verification log + A1 row-number correction `a1a02e3`. db/034 + db/035 applied to prod 2026-05-26. Stage A3 (particle renderer + particle anchor authoring panel + particle-venue translations) is the next deliverable.
- **Estimated:** TBD per stage. Each A-stage is its own propose-pause cycle.
- **Scope clarification:** the admin UI is the authoring/preview tool that mitigates the venue-translation risk per Plan B. The karaoke reader-path rewire (Block B) — the actual switch of `karaoke/stage.html` from inline venue code onto `shell/venue-registry`'s registered renderers — is staged separately, AFTER A8 (`AMBIENT_PROFILES` + `addVenueEffects3D` retirement). Games venue integration remains Phase 4.
- **Trigger for next stage:** continue per Plan-B sequencing. Stage A3 brief drafted at next planning-chat session.
- **References:** `docs/VENUE-ADMIN-UI-DIRECTION.md` (Plan B direction); `docs/VENUE-ADMIN-UI-A1-BUILD-SPEC.md` §7 (the A1–A8 staging); `docs/PHASE-2-BUILD-SPEC.md` §3-§7 (the data model + original admin UI scope); `db/032_venue_abstraction_schema.sql` (the tables); `db/034_venue_default_update_rpc.sql` + `db/035_audio_anchor_rpcs_and_seed.sql` (the per-stage RPC migrations shipped to date); `shell/venue-settings.js` (the resolver the UI reads + writes through); `shell/venue-registry.js` (the registry the renderer impls are registered against); `shell/venue-renderers/audio.js` (Stage A2's renderer impl — the pattern Stage A3 mirrors); `docs/SESSION-LOGS/VENUE-ADMIN-UI-A1-STAGE-1-VERIFICATION-LOG.md` + `docs/SESSION-LOGS/VENUE-ADMIN-UI-A1-STAGE-2-VERIFICATION-LOG.md` (the per-stage verification record).

---

## Queued sessions

> **Note on numbering:** Sessions 6 → 12 are a clean integer sequence reflecting technical-first dependency ordering. Sessions 6 + 7 (formerly 4.10.1 + 4.11) renumbered 2026-05-04 to drop the 4.x topical prefix in favor of the post-Session-5 sequence. The legacy 4.x numbering is preserved in the "Completed sessions" section below for traceability against shipped work.
>
> Session 10's content (Venues at platform level) is now in the Completed section as the "Unified-app workstream — Phase 2: Venue abstraction" entry — its body is no longer in this queue; the Completed entry holds the working detail. Sessions 9, 11, 12 carry one-line cross-ref notes mapping each to its UAP §5 phase (9 → Phase 3 karaoke; 11 → Phase 3+ funnel; 12 → post-Phase-5 "then wellness/worlds"). Hard ordering for the remaining queue: 6 → 7 → 8 (small wins first — SMS pre-invites, admin UI, Trivia premium UX); 9 + 11 + 12 sequenced per their UAP phase dependencies.

### Session 6 — SMS pre-invites for household onboarding

- **Why:** Phone-based household pre-invites, needed before scaling household onboarding past direct email invites. (Was Session 4.10.1.)
- **Estimated:** 1–2 hours
- **Depends on:** nothing (orthogonal to Session 5)
- **Reference:** `docs/DEFERRED.md` → "Phone-based household pre-invites (SMS verification)"

### Session 7 — Admin management UI

- **Why:** 4.10 ships with no household admin UI beyond pre-invite. Member roster, demote/promote, scan-approval flow, pending invites inbox all need first-class UI surfaces. (Was Session 4.11.)
- **Estimated:** 2–3 hours
- **Depends on:** 4.10 RPCs (already shipped — `rpc_approve_household_member`, `rpc_designate_admin`). Session 6 (SMS pre-invites) lands first.
- **Reference:** `docs/DEFERRED.md` → "Scan-approval flow", "Pending Invitations inbox"

### Session 8 — Trivia premium UX differentiation

- **Why:** Trivia Phase 2 (shipped 2026-05-04) plumbs premium AI-generated questions but offers no functional advantage over OpenTDB beyond the "AI-generated" label. Premium needs to actually feel premium. Open design space — three candidate directions: (1) custom categories (manager types a free-form theme like "obscure prog rock"); (2) Wikipedia-aware questions (Anthropic with retrieval to current events); (3) per-user personalization (Trivia tuned to past players' interests).
- **Estimated:** TBD pending design conversation.
- **Depends on:** Nothing technically. Open design space; product conversation comes first.
- **Reference:** `docs/DEFERRED.md` → "Trivia premium polish (post-Phase 2)" (the existing 3-item polish entry surfaces some prereqs but not the differentiation work itself; this entry should be added in a future commit if differentiation work crystallizes).

### Session 9 — Audience.html unification (NHHU → HHU UI merge)

> **UAP §5 phase mapping:** Phase 3 (karaoke onto the new model). Phase 1 and Phase 2 of the workstream are complete; the immediate next Phase-3 work is the Part 1 venue admin UI + venue translation (Active section above) per Plan B; Session 9 (audience.html dissolved) follows that as the next Phase-3 piece. **Spec §12 bullets 3 (DEFERRED cluster 6-sub-entry disposition) and 4 (INFRA.md / CLAUDE.md updates) ride with Phase 3** — both describe karaoke operational behavior, which only changes when Phase 3 rewires karaoke. They remain tracked in spec §12.

- **Why:** Current parallel UI codebases (audience.html for NHHU, singer.html/index.html for HHU) compound complexity with every feature added. Post-Session-5 work to absorb audience.html into the HHU app as a parameterized NHHU view. Same UI fabric for both populations, conditional rendering hides TV-required features.
- **Status:** Keystone for further platform work — until this lands, NHHU conversion funnel + games venues + wellness all fight against the audience-vs-singer split.
- **Estimated:** TBD pending session planning. Substantial structural work.
- **Existing precondition:** audience.html freeze in effect since Session 5 (no new features there; bug fixes only). See DEFERRED entry "Audience.html freeze".
- **Depends on:** Session 5 closure. Sessions 6-8 don't strictly block this but are smaller and ship faster.
- **References:**
  - `docs/KARAOKE-CONTROL-MODEL.md` § 5.5 "Post-Session-5 — Audience.html migration into unified app" (canonical)
  - `docs/PHONE-AND-TV-STATE-MODEL.md` line 419 (cross-reference)
  - `docs/DEFERRED.md` "Migrate audience.html into unified app as parameterized NHHU view" (line 1436)
  - `docs/DEFERRED.md` "Audience.html freeze" (line 1422, active constraint)

### Session 11 — Audience-to-NHHU conversion path (user-acquisition funnel)

> **UAP §5 phase mapping:** Phase 3+ (sister UX/funnel layer to karaoke surface work). Phase 1 and Phase 2 of the workstream are complete; the immediate next Phase-3 work is the Part 1 venue admin UI + venue translation (Active section above) per Plan B; Session 11 lands after Session 9 (audience.html dissolved). This work rides with Phase 3.

- **Why:** Convert passive audience members into registered users. Phase 1 placeholder may ship in Session 5 (minimal Elsewhere home for NHHU returning from audience deep link, with "go back" + "explore Elsewhere" options). Full conversion funnel (sign-up, app downloads, game launchers) is post-Session-5.
- **Status:** User-acquisition strategy. Sister item to Session 9 unification — listed in same § 5.4-5.5 vicinity but distinct scope (UX/funnel work vs. structural UI rework).
- **Estimated:** TBD pending session planning.
- **Depends on:** Session 9 (unification) lands first for best funnel quality — converted NHHUs should land in the unified app, not a separate codebase. Sessions 6 + 7 (SMS pre-invites + admin UI) are also soft prerequisites for funnel quality.
- **References:**
  - `docs/KARAOKE-CONTROL-MODEL.md` § 5.4 "Post-Session-5 — Audience-to-NHHU conversion path" (canonical)
  - `docs/DEFERRED.md` "Audience-to-NHHU conversion path" (line 1408)

### Session 12 — Wellness app implementation

> **UAP §5 phase mapping:** post-Phase-5 ("then — wellness and worlds, built greenfield against the finished model"). Phase 1 and Phase 2 of the workstream are complete (see Completed section); the immediate next step is the venue admin UI fast-follow (Active section above); Phases 3, 4, 5 follow before this post-Phase-5 work begins.

- **Why:** Wellness is a placeholder in the architecture today (no implementation). Adding it requires both the unified app (Session 9 — wellness needs the same UI fabric, otherwise becomes a third parallel codebase) and the platform-level venue service (Session 10 — wellness sessions need their own venue/environment system).
- **Estimated:** TBD pending session planning.
- **Depends on:** Session 9 (unification) AND Session 10 (cross-app venues). Without both, wellness becomes a third parallel UI codebase.
- **References:**
  - `docs/SESSION-5-PLAN.md` (wellness mentioned as future app; schema supports `app = 'wellness'` for future)
  - `docs/DEFERRED.md` (no dedicated wellness entry yet; this Session 12 entry is the placeholder)

---

## Completed sessions

### Unified-app workstream — Phase 2: Venue abstraction

**Completed:** 2026-05-24 (db/032 schema applied to prod 2026-05-24; spec + bookkeeping commits + two shell-module commits all pushed 2026-05-24; close-out docs commit lands the phase)

Shipped the venue abstraction — a complete cross-app venue layer per `docs/PHASE-2-BUILD-SPEC.md`. Build is in three architectural layers (data, resolver, renderer-registry mechanism) plus docs. Per spec §10, Phase 2 ships DORMANT — no live consumer of the new exports, karaoke not rewired (Phase 3), games not integrated (Phase 4), no app rendering layers built.

What shipped:

- **Data layer.** db/032 venue-abstraction schema migration. Extended `venue_defaults` and `karaoke_venue_settings` with the Phase-2 default/override columns (`camera_fov`, `motion`, `ambient`, `anchor_patch`). Created three new tables: `venue_anchors` (typed anchor records per spec §3.1), `costumes` (cross-app library, records only), `venue_suggested_costumes` (venue→costume association). All new tables empty. Applied to prod 2026-05-24 via Supabase SQL Editor; recorded in `db/MIGRATIONS_APPLIED.md`. Two design decisions in the migration header: motion modeled as jsonb (varying parameter sets per motion type — `static`/`orbit`/future `elliptical`), and all three authored-content FKs use ON DELETE RESTRICT (blocking venue/costume deletes that would silently destroy authored content). All 12 footer verification queries passed.
- **Resolver.** `shell/venue-settings.js` generalized from a yaw/pitch-only resolver into a per-attribute-and-anchor-set resolver. 4 legacy exports preserved bit-for-bit (karaoke's 7 callsites in `karaoke/stage.html` continue to work unchanged); 3 new exports widen the capability: `resolveVenueAttribute` (scalar resolver handling per-view legacy attributes AND non-per-view Phase-2 attributes via a per-attribute config table), `loadVenueAnchors` (sibling loader for `venue_anchors` rows; not a widening of `loadVenueSettings`), `resolveAnchorSet` (pure function applying the §4.4 patch shape to a default anchor list, with `console.warn` breadcrumbs on malformed/stale patches and a documented read-only contract on the returned array).
- **Anchor renderer registry mechanism.** `shell/venue-registry.js` new file. 4 exports: `ANCHOR_TYPE_VOCABULARY` (frozen 7-type list per spec §3.2 / db/032 CHECK), `registerAnchorRenderer`, `getAnchorRenderer`, `unregisterAnchorRenderer`. Pure in-memory `Map`; no `window.sb` / no `shell/auth.js` dependency (loads in any order). Ships EMPTY with zero implementations registered — Phase 3 populates it (translation work explicitly named in spec §5.4 "Phase-3 translation cost"). `getAnchorRenderer` returns `null` on missing (no fake no-op renderer); callers handle null on the render path.
- **Docs.** `docs/PHASE-2-BUILD-SPEC.md` committed and revised through to the close-out version (all open questions closed); DEFERRED "Venues as cross-app service" entry gained a supersession-by-spec notice; the PHASE1-NOTES `venue-effects.js` IOU marked absorbed-into-Phase-2.

**Commits (chronological):**

- `a254993` — feat(phase-2): db/032 add venue-abstraction schema — Phase 2 §4.5 (additive, dormant). Schema migration + apply-row in one commit (single-session write+apply).
- `0b91206` — docs: commit PHASE-2-BUILD-SPEC + §12 bookkeeping (DEFERRED supersession, ROADMAP active-entry update). The spec, plus §12 bullet-1/2 disposition tasks (DEFERRED notice + IOU absorbed + ROADMAP active-entry initialization).
- `d5ca112` — feat(phase-2): generalize shell/venue-settings.js — venue attribute + anchor resolver (§5). The resolver generalization, 4 legacy exports preserved bit-for-bit, 3 new exports.
- `a62d1e9` — feat(phase-2): add shell/venue-registry.js — anchor renderer registry mechanism (§5.4). New file, ships empty, no dependencies.

(Plus the close-out docs commit that this entry lands in — records Phase 2 as completed and rotates ROADMAP's active entry to the venue admin UI fast-follow.)

**Phase 2 scope items resolved without code:**

- **`shell/venue-bootstrap.js` — DROPPED, not built.** The Revision-1 plan to shrink `venues.json` into a thin bootstrap was reversed in Revision 2 (the "venues.json keeps every field its current readers use" reframe, spec §4.2). With venues.json un-shrunk and no Phase-2 consumer that loads it from a shell module, a bootstrap loader had nothing to do. Decision recorded in spec OQ5. The duplicated `loadVenuesManifest()` between `karaoke/stage.html` and `karaoke/singer.html` is real Phase-3 dedup work (consolidating it requires touching karaoke, which Phase 2's §10 non-goal forbids).
- **`shell/venue-anchors.js` — folded into `shell/venue-settings.js`.** The anchor loader (`loadVenueAnchors`) and the anchor-set resolver (`resolveAnchorSet`) ship inside `venue-settings.js` rather than as a separate file. Same module conventions, fewer files, single import path for the venue-data primitives.
- **Seed/import path (spec §7) — document-only.** No code, no db/033, no placeholder migration. The investigation found: zero authored data of the new attribute kinds exists in the repo today; the established seed pattern is db/003's literal `INSERT INTO ... ON CONFLICT DO NOTHING` inside a migration (the precedent that IS the path when authored data exists); the repo has zero ingestion tooling and CLAUDE.md doctrine rules out adding any; Time Travel Studio is external to elsewhere-repo and Phase 2 explicitly does not adopt it (spec §10). The "minimal seed/import path" is the recognition: the existing migration-INSERT pattern IS the path; it materializes when authored data exists (from the admin UI or Phase 3 translation).

**DEFERRED entries that emerged or were modified:**

- `docs/DEFERRED.md` "Venues as cross-app service (games, wellness, future apps)" — gained a supersession-by-spec notice at the top of its body; kept in active list because the spec is now the authority for design, but the entry's three-part work breakdown remains useful historical reference.
- PHASE1-NOTES migrated section "Extract ambient venue effects into shell/venue-effects.js" IOU — marked `[x] Absorbed into Phase 2`.

**Next:** venue admin UI (fast-follow per spec §7) — see Active section above for the placeholder entry. Phase 3 (karaoke onto the new model) follows the admin UI per the current sequencing lean; the §12 bullet-3 (DEFERRED cluster sub-entry disposition) and bullet-4 (INFRA.md / CLAUDE.md updates) ride with Phase 3 — see Session 9 entry below.

**Details:** `docs/PHASE-2-BUILD-SPEC.md` (the spec); `docs/UNIFIED-APP-PLAN.md` §5 Phase 2 (workstream framing); `db/032_venue_abstraction_schema.sql`; `shell/venue-settings.js`; `shell/venue-registry.js`; `db/MIGRATIONS_APPLIED.md` row for db/032.

### Unified-app workstream — Phase 1: Room/session foundation

**Completed:** 2026-05-21 → 2026-05-23 (db/025-031 applied to prod; §F shell rework + Phase-1 post-work shipped; 10 commits pushed in the closing push)

Shipped the keystone of the unified-app refactor: a `rooms` entity that durably persists across app switches; `sessions` demoted to per-app instances under a room; `session_participants` re-anchored from `session_id` to `room_id`; the 14 RPCs re-keyed plus new `rpc_room_create`; the shell session-state cluster re-pointed from "the session for the bound TV" to "the room and its current session"; plus closing-out post-work: push-trigger recreation (db/029), immersive-control-layer schema column (db/030), ownership-seize RPC (db/031), realtime publisher field-name rename (shell half), and the per-user per-app tile-badge spec (UAP §10).

Architectural significance: Phase 1 is the keystone for UAP §5's remaining phases. Phases 3 (karaoke surface migration) and 5 (rooms/groups/cross-app movement) depend on Phase 1 directly. Phase 2 (venue extraction) can run independently and is now the active session.

**Commits (chronological):**

- `dddbeb6` — db/025 schema cutover (rooms entity + session/participant re-anchor)
- `9e3926e` — db/026 RPC batch 1 (8 mechanical re-points + session_end + set_admission_mode)
- `2465ff5` — db/027 RPC batch 2 (rpc_session_start split + new rpc_room_create per OQ2 (a))
- `95dcf70` — db/028 RPC batch 3 (rpc_session_leave four-tier succession + reclaim RPCs)
- `c657c9f` — forward-correction: DROP FUNCTION ahead of CREATE OR REPLACE for 11 renamed/re-typed functions
- `409676b`, `4bd0829`, `da87d26` — db/026 / db/027 / db/028 apply bookkeeping
- `d790703` — §F Part 2: nested {session, room} cache reshape
- `c270800` — §F Part 1: re-point shell RPC call sites to room-keyed signatures
- `58b36c3` — version bump v2.138
- `daeff0b` — Phase-1.1 dead-code cleanup (generateRoomCode removed; is_session_* wrapper drop deferred)
- `5eb8258` — iOS notification-payload audit (DEFERRED record)
- `b0f8a47` + `89a629e` — db/029 fire_promotion_push recreation + Edge Function payload update
- `2ca15a8` + `fd553ac` — db/030 tv_devices.can_embed column (schema half)
- `b654f91` + `cbd2783` — db/031 rpc_room_seize ownership-seize RPC
- `a5ed589` — C2 shell-half realtime publisher payload rename (4 shell sites; 18 surface sites deferred to Phase 3/4)
- `bf45b2c` — UNIFIED-APP-PLAN §10 tile-badge spec + PHONE-AND-TV-STATE-MODEL.md supersession pointer

All 7 db migrations (db/025-031) applied to prod via Supabase SQL Editor; recorded in `db/MIGRATIONS_APPLIED.md`. iOS bundle synced through `bf45b2c` (this session's close); Xcode rebuild outstanding as normal deferred step.

**DEFERRED entries that emerged:** C1 self-report writer (the writer half of `tv_devices.can_embed`; blocked on compositing pipeline not yet existing as code); C2 surface-side completion (18 publisher call sites in singer/stage/player still send `session_id`); schema-stale `sessions` SELECTs on the four pre-Phase-3 surfaces (7 sites reference dropped columns); C4 HH-admin administrative actions without engagement transition; publishParticipantRoleChanged contract drift / latent `payload.user_id` always undefined; publishManagerChanged dead publisher (zero callers); push-notification tap-routing (`// TODO 2e.1+`) unbuilt; low-prominence room-code-entry UI affordance.

**Details:** `docs/UNIFIED-APP-PLAN.md` (workstream design); `docs/PHASE-1-BUILD-SPEC.md` (Phase 1 detailed spec + verified RPC migration worklist); `docs/EXECUTION-HANDOFF.md` §2 (Phase 1 + post-work status) + §4 (the current-and-next state); four companion model docs (`docs/ROOM-SESSION-MODEL.md`, `docs/ROOM-AUTHORITY-MODEL.md`, `docs/HOUSEHOLD-DEVICE-PRESENCE-MODEL.md`, `docs/ROOM-ACCESS-INVITE-MODEL.md`); `db/MIGRATIONS_APPLIED.md` rows for db/025-031.

### Session 5 — Universal session + participants + queue model

**Completed:** 2026-05-19 (Parts 1, 2, 3a, 3b, 3c W1-W10 shipped; Part 5 verification superseded — see "Workstream pivot" below)

Shipped the universal session + participants + queue model: `sessions` table with RLS and lifecycle RPCs (Part 1); karaoke integration with realtime publishers, session lifecycle wiring, home unification, push notification infrastructure, manager queue UI (Part 2); games integration with manager controls, End Session, Remove Player (Part 3a); Trivia productionization with Edge Function + db/019 premium gating (Part 3b — internally called "Trivia Phase 2", not to be confused with UAP §5's Phase 2); admission_model_v2 §10 W1-W10 (schema migration, per-game manifest + admission stamping, dispatcher refactor, Pause + Leave UI, heartbeat + server-side prune, Last Card UX polish, dead-code sweep) — Part 3c.

**Commits (Part 1 — Schema + RPCs + shell/realtime.js extraction):**
- `253e077` — Part 1a: sessions + session_participants schema with RLS (db/008)
- `979f70d` — Part 1b.1: session lifecycle RPCs (db/009)
- `a0373e0` — Part 1b.2: manager mechanics RPCs (db/010)
- `5f60d13` — Part 1b.3: role and queue mutation RPCs (db/011)
- `9e10bf4` — Part 1c: extract realtime helpers into `shell/realtime.js`

**Commits (Part 2 — Karaoke integration):** full detail in `docs/SESSION-5-PART-2-CLOSING-LOG.md`. Key milestones: 2a realtime publishers (`d1b4edd`), 2b session lifecycle wiring (`601d125`), 2c home unification + active-session relabeling + Back-to-Elsewhere (`daa8718`, `0a3a9ea`, `e4a348e`, `5617689`), 2d karaoke session helpers + stage.html session integration (`db/013` + multiple commits), 2e push notification infrastructure + role-aware UI + self write actions + manager queue UI (multiple commits, latest `af1e468` at v2.120). 2f deferred to consolidation per audience.html no-investment doctrine. BUG fixes during 2e.3: `ce36fe5` (BUG-5), `1b870d3` (BUG-10 at v2.118), `ad97ea5` (BUG-13/3/7 at v2.119). Closeout: `1d481b4` (5 papercuts + closing log), `7f8f97e` (5 open bugs filed to DEFERRED).

**Commits (Part 3a — Games integration):**
- `05d2cae` — db/016 manager-only soft-removal RPC
- `ea89c48` — Part 3a.1 session/participants plumbing (v2.100)
- `8bff27b` — Part 3a.2 manager controls (v2.101)

**Commits (Part 3b — Trivia productionization + premium opt-in via Edge Function):** full detail in `docs/SESSION-5-PART-3B-CLOSING-LOG.md`. v2.108 → v2.113, Edge Function + db/019, shipped 2026-05-04.

**Commits (Part 3c — `admission_model_v2` §10, W1-W10):** full detail in `docs/SESSION-5-PART-3C-CLOSING-LOG.md`. W1-W6 ended at `cef155c` v2.121 (pre-2026-05-18). W7 `68e8ee9` v2.122. W8 `b6898ea` → `2432d86` v2.123 → v2.131 (9 commits). W9 `02cdc08` (db/024) + `a1273df` + `5c1f97f` v2.132 + `6b12290` v2.133. W10 `014c738` → `a7dd71a` v2.134 → v2.137 + tv `v2.101` (4 commits).

**Workstream pivot.** Part 5 verification (multi-user end-to-end testing) was not run as a discrete Session-5 closeout. The work pivoted directly to the unified-app workstream's Phase 1 schema rework on 2026-05-21 (see "Unified-app workstream — Phase 1" above). Phase 1 entirely subsumes the Session-5 participant model by introducing the `rooms` entity and re-anchoring `session_participants` to `room_id`. The Session-5 schema (`session_participants` keyed by `session_id`) is therefore superseded; the data was cleared as a clean-slate migration pre-step (acceptable since pre-launch + ephemeral data).

**DEFERRED entries that emerged:** many across all parts; see per-part closing logs for specific entries. The §10 W10 Cleanup tasks (APP_MANIFEST shrink, doc supersession edits, CLOSEOUT-PLAN restructure, DEFERRED mark-obsolete sweep) remain tracked as `docs/DEFERRED.md` "admission_model_v2 §10 W10 cleanup tasks".

**Details:** `docs/SESSION-5-PLAN.md`, `docs/SESSION-5-PART-2-BREAKDOWN.md`, `docs/SESSION-5-PART-2-CLOSING-LOG.md`, `docs/SESSION-5-PART-3-AUDIT.md`, `docs/SESSION-5-PART-3-CLOSING-LOG.md`, `docs/SESSION-5-PART-3B-CLOSING-LOG.md`, `docs/SESSION-5-PART-3C-CLOSING-LOG.md`, `docs/ADMISSION-MODEL-V2.md`, `docs/GAMES-CONTROL-MODEL.md`, `docs/SESSION-5-CLOSEOUT-PLAN.md` (the never-executed verification plan).

### Session 4.10.3 — Phone back-to-Elsewhere + coordinated TV teardown

**Completed:** 2026-04-22

Shipped the reverse of 4.10.2's phone-as-remote forward loop. Phone back-tap on singer.html / player.html navigates to Elsewhere and publishes `exit_app` realtime event; TV listens on stage.html / games/tv.html and returns to apps grid. Verified end-to-end on real hardware.

**Commits (chronological):**
- `cab9a38` — docs: Session 4.10.3 plan
- `3319ce8` — docs: scope-down Part B + defer audience back-nav
- `f43369a` — Part A: exit_app realtime wiring (index.html + stage.html + games/tv.html)
- `97014c2` — docs: Part B placement + shell-load pattern
- `2c2d5fe` — Part B: singer.html back button + helpers + shell load
- `50a9f5c` — fix: viewport-fit=cover on singer.html
- `40e4f4b` — Part C: fix games/player.html Back to Home link
- `1416c52` — docs: verification doc

**DEFERRED entries that emerged:**
- Audience back-to-Elsewhere navigation (Medium) — filed during Part B scope-down
- Extract `publishExitApp` + realtime helpers into `shell/realtime.js` (Low) — filed at session-end
- Post-claim direct transition to remote-control screen (Low-medium) — filed at session-end, carried forward from 4.10.2 plan Part E

Details: `docs/SESSION-4.10.3-PLAN.md`, `docs/SESSION-4.10.3-VERIFICATION.md`

### Session 4.10.2 — Phone-as-remote UX fixes

**Completed:** 2026-04-22 (core Parts A+B+C + fixes shipped; Parts D–G superseded by 4.10.3 follow-up)

Shipped the phone-as-remote redesign: "Your TVs" picker, remote-control screen, display-only TV apps grid. Forward loop works end-to-end. Parts D–G of the original plan (TV sign-in copy rewrite, post-claim direct transition, dedicated verification doc, v3.0 → v3.1 version bump) did NOT ship — development attention shifted to 4.10.3's follow-up work addressing issues surfaced during 4.10.2 testing.

**Commits:**
- `4a331d6` — Parts A+B (phone Your TVs + remote control)
- `4372a20` — Part C (TV launch listener + display-only grid)
- `56e6e3d` — Navigation fix (phone follows TV into app)
- `7b81f70` — Await fix (phone waits for publish before navigating)

**DEFERRED entries that emerged** (now in DEFERRED.md):
- Phone back-to-Elsewhere + TV teardown (→ resolved in 4.10.3)
- Multi-phone session coordination + session manager role
- Proximity self-declaration
- Session manager inactivity + household-admin override
- Per-app role manifest
- TV sign-in screen copy implies wrong direction of action (still deferred; was Part D of original plan)

**Parts from 4.10.2 plan that remain unfinished:**
- Part D — TV sign-in copy rewrite (captured as DEFERRED entry, not yet scheduled)
- Part E — Post-claim direct transition to remote-control screen (filed as DEFERRED during 4.10.3 session-end)
- Part F — Dedicated 4.10.2 verification doc (not created; 4.10.3's doc subsumes some coverage)
- Part G — v3.0 → v3.1 version bump (never ran; current badge still v2.99 on pages that carry it)

Details: `docs/SESSION-4.10.2-PLAN.md`

---

## Smaller items to land opportunistically

Not full sessions, but worth tracking:

- **`claim.html` App Store URL:** when the iOS app is listed, swap the placeholder href. ~1-line change. Ref: `DEFERRED.md` "claim.html App Store URL placeholder".
- **Inline-script TDZ audit:** opportunistic, when next touching `index.html` / `stage.html` / etc. Ref: `DEFERRED.md` "Audit inline-script TDZ risk in other pages".
- **tv2.html render race:** post-Session-5 polish, not blocking. Ref: `DEFERRED.md` "tv2.html render race".

---

## Architecture notes

Longer-lived design context. Decisions locked in at the session they shipped; won't be revisited without explicit cause.

- **Two-Signal Doctrine** (from OverlayOS work, applies if products converge): Signal A = passthrough, Signal B = OverlayOS-generated and operable.
- **Household + TV device model:** see `SESSION-4.10-PLAN.md`. Currently shipped (six commits in Session 4.10, ending `e7952ae`). `households` + `tv_devices` + `household_members` + `pending_household_invites` tables with RLS.
- **Session handoff via Supabase realtime:** `tv_device:<device_key>` channel, `session_handoff` event. Session 4.10.2 adds `launch_app` event on the same channel (see `SESSION-4.10.2-PLAN.md`). Reuse, don't fork channels.
- **Phone is the remote; TV is the display** (Session 4.10.2, pending implementation): mental model correction. Interactive app launcher lives on phone. TV shows a display-only grid with instruction text.
