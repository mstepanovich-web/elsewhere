# Elsewhere — Execution Handoff Brief

**Purpose:** This document, together with the five unified-app planning
docs, is the kickoff for any new chat continuing the unified-app
execution work. Read this FIRST, then the planning docs.

**Last updated:** 2026-05-27 (Phase-3 / Plan B Stage A3 ship + closeout. Stage A3 — 2D-canvas particle anchor renderer + 3-kind authoring panel + db/036 4-anchor seed — shipped 2026-05-27 (implementation `e9c52e9`, mid-verification kind-gate fix `27610e4`, closeout `01fc791`). All six §8 verification checks PASS; A3 verification log at `docs/SESSION-LOGS/VENUE-ADMIN-UI-A3-VERIFICATION-LOG.md`. Stage A4 (spotlight renderer + spotlight authoring panel + stadium/disco/speakeasy spotlight translations, INCLUDING the 2 Three.js 3D builders for stadium and speakeasy) is next per `docs/VENUE-ADMIN-UI-DIRECTION.md` §7's authoritative staging. §2 enumerates the workstream's current status; §4 names the next deliverable.)

---

## 1. The three environments — read this before anything else

Work on this project happens across THREE environments. They are NOT
interchangeable. Most handoff failures come from forgetting this.

- **The planning chat** (a regular claude.ai chat — likely the one
  reading this now). Has the project context. Writes tasks, reviews
  results, makes decisions. **CANNOT read or edit the repo.** It only
  sees what is pasted into it.
- **Claude Code** (a terminal tool running in the repo). CAN read every
  file, run git, edit code. It executes tasks. It does not drive the
  project — it does what each task says.
- **The human.** Carries tasks from the planning chat to Claude Code, and
  carries Claude Code's results back to the planning chat.

**The working loop, every time:** planning chat writes a task → human
pastes it into Claude Code → Claude Code does the repo work and reports →
human pastes the result back to the planning chat → planning chat reviews
it with the human. Pushes are deliberate gates the human approves.

**The rule that prevents the most common failure:** any task that needs
to READ or EDIT the repo MUST go to Claude Code. Never write a
"check against the actual repo" or "edit file X" task for the planning
chat — the planning chat physically cannot do it and will get stuck
asking for files. If you are the planning chat and you are about to write
a task, the first question is always: WHO RECEIVES THIS — Claude Code, or
the human directly? Write accordingly.

The five planning docs are committed in the repo, so Claude Code can read
them itself. They do not need to be pasted into Claude Code.

## 2. Where the project is

The unified-app / NHHU-primary refactor. Goal: every registered user is a
first-class user of every app at a baseline tier with no TV device
required; an embed-capable TV device adds an immersive capability layer.
This refactors KARAOKE and GAMES; Wellness and Worlds are greenfield.

**Documentation phase: COMPLETE.** Five planning docs written, reviewed,
committed. Every superseded doc carries a supersession pointer. CONTEXT.md
(the general kickoff doc), INFRA.md, and CLAUDE.md were all revised to
match. No doc contains a known-false statement.

**Phase-1 execution-scope investigation: COMPLETE.** Its adopted output is
`docs/PHASE-1-BUILD-SPEC.md` (initial commit `caf647e`, amended by
`fcc42f6` for three cross-cutting pinned decisions + an S6 current-state
correction). The six open questions surfaced in §H are now closed.

**Phase-1 RPC migration: COMPLETE.** All four database migrations
are applied to prod and recorded in `db/MIGRATIONS_APPLIED.md`. The
room-keyed RPC surface (the 14 RPCs plus new `rpc_room_create`) is
the canonical implementation in prod as of 2026-05-22.

- **db/025** (schema cutover — rooms entity + session/participant
  re-anchor): committed `dddbeb6`, applied 2026-05-21.
- **db/026** (RPC batch 1 — 8 mechanical re-points + rpc_session_end
  + rpc_session_set_admission_mode): committed `9e3926e`, applied
  2026-05-22.
- **db/027** (RPC batch 2 — rpc_session_start split + new
  rpc_room_create per OQ2 (a)): committed `2465ff5`, applied
  2026-05-22.
- **db/028** (RPC batch 3 — rpc_session_leave with four-tier
  host-first succession + new `p_successor_user_id` parameter, plus
  rpc_session_reclaim_manager and rpc_session_admin_reclaim):
  committed `95dcf70`, applied 2026-05-22.
- **Forward-correction commit `c657c9f`** added `DROP FUNCTION IF
  EXISTS` statements ahead of each CREATE on the 11 renamed/re-typed
  functions across db/026/027/028. The originals used `CREATE OR
  REPLACE FUNCTION` for parameter renames and return-type changes,
  which Postgres rejects with `42P13`; without `c657c9f`, none of
  the three RPC migrations could apply. The fix landed mid-apply
  and the three migrations then applied cleanly.

Verified-live structural guarantees from the post-migration checks:
`rpc_room_create` is the sole writer of `rooms.owner_user_id`
(immutable post-creation per OQ2 (a)); `rpc_session_leave`'s tier-4
branch is the first and only writer of `rooms.ended_at` in the
system.

**Phase-1 post-work: COMPLETE.** Three additional database migrations
and the §F shell session-state cluster rework shipped 2026-05-22 →
2026-05-23 to close Phase-1's downstream gaps:

- **db/029** (`fire_promotion_push` trigger recreation with
  room-keyed payload, replacing the trigger dropped by db/025):
  committed `b0f8a47`, applied 2026-05-23. Push notification
  DELIVERY restored end-to-end.
- **db/030** (`tv_devices.can_embed` column — schema half of the
  immersive-control-layer activation predicate; self-report writer
  deferred per DEFERRED.md): committed `2ca15a8`, applied
  2026-05-23.
- **db/031** (new `rpc_room_seize` ownership-seize RPC per
  ROOM-AUTHORITY-MODEL.md "Seize authority"; functionally usable
  in prod only after the can_embed self-report writer lands):
  committed `b654f91`, applied 2026-05-23.
- **§F shell session-state cluster rework**: the ~13-site
  client-side migration enumerated in `docs/PHASE-1-BUILD-SPEC.md`
  §F. Nested `{ session, room }` cache reshape (`d790703`) + RPC
  call-site re-points (`c270800`) + version bump v2.138
  (`58b36c3`). The shell now reads the room-keyed RPC surface.
- **Phase-1.1 cleanup, iOS notification-payload audit, C2
  shell-half realtime publisher payload rename, UNIFIED-APP-PLAN
  §10 tile-badge spec**: all shipped 2026-05-23; see §4 for
  per-item commits and detail.

Phase 1 is closed. iOS bundle is current through `bf45b2c` (this
session's close).

**Post-Phase-1 / pre-Phase-2 fixups: COMPLETE.** Three deliverables landed between Phase-1 close and the Phase-2 venue work, listed in commit order:

- **Karaoke schema catch-up to the room-keyed RPC surface** (`595e004`, 2026-05-23 → 2026-05-24): `karaoke/singer.html` + `karaoke/stage.html` brought current with db/025 + db/026's column changes (stripped the stale `manager_user_id` / `room_code` / `tv_device_id` reads + re-pointed RPC call sites to the room-keyed signatures). The "schema-stale SELECTs on the four pre-Phase-3 surfaces" debt in DEFERRED.md is now **closed on the karaoke half**; the games half (`games/player.html`, `games/tv.html`) still rides Phase 4. Verification log: `docs/SESSION-LOGS/KARAOKE-SCHEMA-CATCHUP-595e004-VERIFICATION-LOG.md` (committed `964c541`). The runbook proximity-step fix landed alongside in `6c4406b`; stale legacy-mode comments superseded in `6f907b0`.
- **Items 5/6 — karaoke session-creation moved to a deliberate in-app action** (`6663ff5`, 2026-05-24): tile-tap now navigates, not creates; a new in-app karaoke info screen's click-through is the session-creation action, matching `ROOM-SESSION-MODEL.md` § "Tile-tap is navigation, not session creation." Karaoke half only — games converts in Phase 4 per UAP §5. Verification runbook + result in `7b7994b` + `b48b978`.
- **Tier 1 — web-only Immersive TV claim trigger on tv2.html** (`e33a658`, 2026-05-24): the schema half of the C1 self-report writer for `tv_devices.can_embed`. Closes the user-visible half of the C1-self-report DEFERRED entry; the camera + compositing-pipeline detection half remains active. Verification runbook + result in `d395de9` + `fae3600`.

These three were preceded by the **premium → immersive capability rename** (`11499c2`) and the **Immersive TV design model** doc + Items 5/6 / Tier 1 build specs (`5df7097`), and followed by the **UAP §5 amendment** folding session-creation UX into Phases 3 + 4 (`fef9d4d`).

**Phase 2 — the venue abstraction: COMPLETE (shipped 2026-05-24).** Phase 2 per `docs/UNIFIED-APP-PLAN.md` §5 is "venue extraction — pull venue rendering out of the karaoke stage into a shared shell renderer; make the venue registry cross-app." The Phase-2 build spec at `docs/PHASE-2-BUILD-SPEC.md` (revision 3 at close) **broadened that scope from a literal code-lift into the construction of a complete cross-app venue abstraction** — see the spec's §1 for the supersession of the original three-part DEFERRED breakdown ("Venues as cross-app service"). The abstraction shipped **dormant** — built, tested in isolation, no live consumer until Phase 3.

- **`docs/PHASE-2-BUILD-SPEC.md`** committed `0b91206` (with DEFERRED supersession + ROADMAP active-entry update).
- **db/032** (venue-abstraction schema — `venues` / `venue_anchors` / `venue_defaults` / `costumes` tables + their RLS + read RPCs; additive + dormant): committed `a254993`, applied 2026-05-24.
- **`shell/venue-settings.js` generalization** (venue attribute + anchor resolver per spec §5; replaces the prior view-coordinate-only helper): committed `d5ca112`.
- **`shell/venue-registry.js`** (anchor renderer registry mechanism per spec §5.4; `window.elsewhere.anchorRegistry.{registerAnchorRenderer, getAnchorRenderer}`): committed `a62d1e9`.
- **Phase-2 close** — spec revision 3 + ROADMAP completion: `f619a57`.

**Phase 3 — karaoke onto the new model: IN PROGRESS under Plan B.** Phase 3 per UAP §5 is "karaoke onto the new model: scanned-screen sessions; baseline players driving venues and the queue with no TV device; audience.html dissolved into baseline watcher mode." Plan B (`docs/VENUE-ADMIN-UI-DIRECTION.md` 2026-05-26 revision, `c076f12`) folds the **venue translation** (procedural `AMBIENT_PROFILES` + `addVenueEffects3D` in `karaoke/stage.html` → data-driven `venue_anchors` + reusable shell renderer impls) AND the **Part-1 admin UI** (`admin-venues.html`, manage the existing 26 venues) into Phase 3 as part of the karaoke rewire — both serving as authoring/preview infrastructure that mitigates the translation risk. Plan A (wrap-as-legacy, defer translation + admin UI to post-Phase-5; `df49366`) was reversed 2026-05-26. The **authoritative A1–A8 staging** lives in `docs/VENUE-ADMIN-UI-DIRECTION.md` §7 ("Plan B hybrid sequencing"). The A1 build spec at `docs/VENUE-ADMIN-UI-A1-BUILD-SPEC.md` (commit `cf2585c`, revised `8187c5d` + `647c31b`) covers Stages A1 + A2. Stage A3 has its own build spec at `docs/VENUE-ADMIN-UI-A3-BUILD-SPEC.md` (committed `bc8c448`, §1 amendment `716746b`).

- **Stage A1 (admin UI skeleton + venue_defaults editor + db/034 `rpc_venue_default_update`)**: committed `9cf4b70`; path bug fix `606674f`; verification log `f610039`. db/034 applied to prod 2026-05-26.
- **Stage A2 (audio renderer impl + audio anchor authoring panel + 19-venue audio seed + db/035 `rpc_venue_anchor_upsert` / `rpc_venue_anchor_delete`)**: committed `9d58a8d`; verification log + A1 row-number correction `a1a02e3`. db/035 applied to prod 2026-05-26. One-row prod hazard (hollywoodbowl anchor id divergence from seed id) resolved via SQL UPDATE before the A2 log committed.
- **Stage A3 (particle renderer + kind-discriminated authoring panel + db/036 4-anchor seed + karaoke registration tag)**: implementation `e9c52e9` (2026-05-27); mid-verification kind-gate fix `27610e4`; closeout `01fc791`; verification log `docs/SESSION-LOGS/VENUE-ADMIN-UI-A3-VERIFICATION-LOG.md`. db/036 applied to prod 2026-05-26 (all 3 §2.3 verification queries Q1–Q3 PASS first run). All six §8 verification checks (Checks 13–18) PASS. One bug caught + fixed mid-verification (preview-ended label was arming on point-cloud — eternal kind — wrongly; gated on kind in `27610e4`). One schema-state divergence (Check 15 round-trip left stadium with panel-generated UUID id; restored to seed id `anc_par_stadium` via one-row SQL UPDATE before closeout). A3 is 2D-canvas only per spec §0.2 re-staging — 3D particle paths (stadium 2000 Three.js Points + speakeasy 60 sphere meshes) defer to Stage A4. Six DEFERRED entries filed in the closeout (enumerated in §4).

Stages A4–A8 (spotlight renderer + the 2 Three.js 3D builders, remaining anchor types, AMBIENT_PROFILES retirement, per-app override editor, costume editor) are queued per Direction §7 and not yet started. Block B (the karaoke reader-path rewire that retires `karaoke/stage.html`'s inline venue code) follows A8.

The current immediate next step is named in §4.

## 3. The five planning docs — the design

All in docs/. Read all five after this brief:
- `UNIFIED-APP-PLAN.md` — umbrella: capability model, the six locked
  decisions, four-quadrant per-app breakdown, phase sequencing, open
  items (§8).
- `ROOM-SESSION-MODEL.md` — entity model: durable `rooms` + disposable
  per-app `sessions`; `session_participants` re-anchored to `room_id`.
- `ROOM-AUTHORITY-MODEL.md` — manager authority splits into room control
  (transferable) and room ownership (never transfers by succession);
  succession picks the longest continuously-present non-audience
  participant.
- `ROOM-ACCESS-INVITE-MODEL.md` — token-based invites on the dormant
  `invites` table; new Edge Function to resolve tokens.
- `HOUSEHOLD-DEVICE-PRESENCE-MODEL.md` — households, binding, presence,
  immersive-embedding rule. Supersedes PHONE-AND-TV-STATE-MODEL.md.

## 4. The immediate next step

**Phase 3 / Plan B Stages A1, A2, A3 are all shipped and verified.** db/034 + db/035 + db/036 + `admin-venues.html` (with audio + particle panels) + `shell/venue-renderers/audio.js` + `shell/venue-renderers/particle.js` + the two-line `karaoke/stage.html` registration block are live in prod. The admin UI is the working write path for `venue_defaults` edits, audio anchor authoring (19 venues), and particle anchor authoring (4 venues). All three stages verified against prod with the only bug caught (A3 Check 15) fixed mid-verification via `27610e4`. See `docs/SESSION-LOGS/VENUE-ADMIN-UI-A1-STAGE-1-VERIFICATION-LOG.md` (`f610039`), `docs/SESSION-LOGS/VENUE-ADMIN-UI-A1-STAGE-2-VERIFICATION-LOG.md` (`a1a02e3`), and `docs/SESSION-LOGS/VENUE-ADMIN-UI-A3-VERIFICATION-LOG.md` (`01fc791`) for per-check evidence.

**The immediate next step is Stage A4 per `docs/VENUE-ADMIN-UI-DIRECTION.md` §7's "Plan B hybrid sequencing".** Stage A4 is the **spotlight renderer + spotlight authoring panel + stadium/disco/speakeasy spotlight translations** vertical slice. **A4 includes the translation of the 2 Three.js 3D builders** (`buildStadiumEffects3D` + `buildSpeakeasyEffects3D` at `karaoke/stage.html:2849+`) — Three.js + canvas-2D variants likely both expressible through one spotlight type with a renderer-side mode parameter per Direction §7. A4 ALSO subsumes the 3D-particle paths (stadium 2000 Three.js Points + speakeasy 60 sphere meshes) deferred from A3 per spec §0.2 re-staging — solve the 3D rendering context once. The pattern set by A2/A3 (renderer impl in `shell/venue-renderers/<type>.js`, registered via `window.elsewhere.anchorRegistry.registerAnchorRenderer`, with a matching authoring panel + per-type seed in a new `db/037_*.sql` migration) carries forward. Stage A4 ships as its own propose-pause cycle.

**Numbering note for the next implementer.** Direction §7 calls spotlight **Stage 4**. The A3 spec refers to spotlight as "Stage A5" in ~6-8 cross-references across §§0.2, 6, 7 — this is a numbering drift relative to Direction §7's authoritative staging. The A3 spec's "A5 (spotlight + 3D builders)" should be read as "A4." Captured as a DEFERRED entry for spec correction on next touch of that file.

Stage A8 retires `AMBIENT_PROFILES` + `addVenueEffects3D` from `karaoke/stage.html` once every procedural venue has a data-driven equivalent. Block B follows: the karaoke reader-path rewire that switches `karaoke/stage.html` from its inline venue code onto the shell renderer + registry, completing the Phase-3 karaoke half.

**Six DEFERRED.md entries filed in the A3 closeout (`01fc791`):**

- **admin-venues.html has no logout / account-switch control** — non-admin sessions trap on "Not authorized" with no recourse; `window.sb.auth.signOut()` console workaround doesn't work because `window.sb` isn't reliably exposed on the bail path. Hit during A3 Check 15.
- **P1 / drifting-cloud 4th particle kind** — the drift+wrap+twinkle pattern from A3's ghost-venue cross-check (space starfield + forest fireflies); pick up when a P1 venue in the 26-venue inventory needs the kind, or when ghost-venue translation begins.
- **Venue modulator system** — A3 records modulator bindings in payloads (name + target) but drives them with built-in preview oscillators in particle.js; real registry-resolved drivers deferred. Cross-cutting (drives particles AND spotlights); design bundles with A4.
- **Particle panel validates JSON well-formedness only, not §1 schema shape** — well-formed-but-wrong-shape payloads pass the panel and reach the renderer, which degrades gracefully. Acceptable for admin-only tool; revisit if surface widens.
- **Disco `rotation_velocity` (and other seeded velocity/rate values) reads visually fast at seed value** — Check 16 finding. NOT a renderer bug (byte-faithful from procedural source); a tuning question for the post-A8 Admin UI Part 2 in-situ tuning workflow. Generalizes to festival vy, speakeasy size_growth_rate / fade_rate, stadium twinkle.
- **A3 build spec internal references to spotlight as "Stage A5" should be "Stage A4"** — documentation drift surfaced during the A3 closeout's "what's next" determination; mechanical find-and-replace pass, fold into next touch of that file.

**Still-active downstream items — tracked in `docs/DEFERRED.md`, NOT blocking Stage A4:**

- **C1 self-report half (camera + compositing-pipeline detection)** — Tier 1 (`e33a658`) closed the user-visible half of the `tv_devices.can_embed` self-report writer. The camera + compositing-pipeline detection half is not yet built; until it lands, the C5 ownership-seize RPC continues to refuse seize attempts in prod.
- **C2 surface-side completion — games half** — 9 publisher call sites in `games/player.html` still send pre-rename `session_id`. Karaoke half closed via `595e004`. Rides Phase 4 surface migration.
- **Schema-stale `sessions` SELECTs — games half** — 4 sites across `games/player.html` + `games/tv.html` reference columns dropped by db/025. Karaoke half closed via `595e004`. Resolves with Phase 4 per UAP §5.
- **Anon-grant defense-in-depth sweep** — DEFERRED entry filed in the prior doc-catch-up; ref A1 verification log `f610039` Bug 2.
- **C4 — HH-admin administrative actions without engagement transition** — future enhancement; current uniform-engagement behavior is correct for the primary use case.

**Push + prod state.** All Phase-2 + Phase-3-Plan-B-A1+A2+A3 commits pushed; `origin/main` at `01fc791` at this catch-up's start (the A3 closeout). db/034 + db/035 + db/036 applied to prod.

**Bundle hygiene.** iOS Capacitor bundle status was current through `bf45b2c` at Phase-1-close; **drift since then is the post-Phase-2 + Plan-B-A1+A2+A3 cluster, none of which touches native concerns** (push, Capacitor plugins, fullscreen). Mobile Safari has been the verification target throughout. The session-closing-ritual sync per CLAUDE.md is pending whenever the next session ships user-facing web changes that warrant native verification; the Plan-B work to date is admin-surface-only + a one-line karaoke registration tag (the karaoke reader path is untouched until Block B), so the deferred sync is intentional rather than missed. When Stage A8 / Block B land — the points that actually change `karaoke/stage.html`'s reader path — that's the natural sync trigger.

## 5. Review discipline

Propose-then-review. Claude Code proposes diffs or specs; the human and
planning chat review before anything is committed. Commits and pushes are
separate gates. Migration code is never written before its build spec is
reviewed.

## 6. Maintaining this brief

Update section 2 and section 4 at the end of each execution session, so
this brief is always a current snapshot of where the project is and what
the next step is — the same way CONTEXT.md is maintained.
