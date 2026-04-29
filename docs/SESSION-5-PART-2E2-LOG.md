# Session 5 Part 2e.2 — Self Write Actions on singer.html (Log)

Date: April 28, 2026
Status: SHIPPED end-to-end. Code on origin/main; migration applied; edge function deployed. Real-device end-to-end push test pending (architecture verified, components individually verified).
Spec sources:
- docs/SESSION-5-PART-2E-AUDIT.md (locked decisions appendix)
- docs/SESSION-5-PART-2E-MODEL-AUDIT.md (eligibility-derivation Path A, landed in 2e.1)
- docs/KARAOKE-CONTROL-MODEL.md § 4.1 (singer.html UI surfaces) + § 5.2 (work item list)

---

## Goal

Add self-write actions to karaoke/singer.html so each phone can act on its own session_participants row: queue a song, update queued song, leave the queue, and respond to promotion-to-active. Plus close the loop on push notifications by wiring the actual server-side trigger and notification synthesis (2e.0 shipped infrastructure-only with no notification ever fired).

After 2e.2, every role-aware UI affordance from KARAOKE-CONTROL-MODEL § 4.1 that relates to self-action is wired end-to-end. Manager queue-management UI (cross-user actions) remains 2e.3.

---

## What shipped

### Sections delivered

| § | Commit | Scope |
|---|---|---|
| 1 | 0f51407 | Foundation: doSelfRoleUpdate helper for own-row mutations |
| 2 | 0b9563c | Role-aware screen-home tile rendering + ⌂ Home tile removed |
| 3 | (in arc) | Primary CTA dispatch through doSelfRoleUpdate |
| 4 | (in arc) | Wire Leave Queue handler (queued → audience) |
| 5 | ad867a7 | Suppress TV signals for non-Active roles + inline venue thumbnails |
| -  | eb6e7f4 | Audio asset (sounds/ui/take-stage.mp3) |
| 6a | 64b87e3 | Take Stage modal DOM + audio + vibration |
| 6b | 9ec5006 | Promotion push trigger + edge fn service-role branch + client modal hookup |

Versioning arc: v2.103 (post 2e.1) → v2.104 (§1) → v2.105 (§2) → v2.106 (§3) → v2.107 (§4) → v2.108 (§5) → v2.109 (§6a) → v2.110 (§6b).

### Server-side ops applied

- Migration db/015_promotion_push_trigger.sql applied via Supabase Dashboard SQL Editor (returned `migration 015 loaded`)
- Edge function send-push-notification redeployed via `supabase functions deploy` from local repo
- pg_net extension enabled (was available, version 0.20.0, off-by-default)
- Vault secrets `edge_fn_url` and `service_role_key` (legacy JWT) set via `vault.create_secret` in dashboard SQL editor before §6b's first run

---

## Architecture summary

### Self-write helper

`doSelfRoleUpdate({participation_role?, pre_selections?})` wraps `rpc_session_update_participant` for the caller's own row. Two important properties learned during §1:

1. The DB RPC REPLACES `pre_selections`, does not merge. Helper merges client-side at the top level so callers can update one of `{song, venue, costume}` without clobbering the others.
2. The RPC's parameter for the target user is `p_user_id`, not `p_target_user_id`. Same column reused for self vs. cross-user mutations.

### Role-aware rendering on screen-home

Same DOM, conditional render. Branches:

| Role | Primary CTA |
|---|---|
| Active (pre-song) | ▶ Start Performance |
| Queued | ✏️ Update My Song + 🚪 Leave Queue link |
| Audience eligible, queue empty + no active singer | ▶ Start Song (becomes active immediately) |
| Audience eligible, queue or active singer | ➕ Add to Queue |
| Audience not eligible | (no CTA — browse-only) |
| Way 1 fallback (no session) | legacy ▶ Start Performance behavior |

`handleHomePrimaryCTA()` dispatches by role + state. Way 1 fallback preserved throughout — no `currentMyRow` means legacy single-singer behavior, no DB writes.

### Signal suppression

`roleAllowsStageSignals()` gate added in §5. Returns `true` for Active Singer (or Way 1 fallback), `false` otherwise. Wraps 18 sendToStage callsites (browse/preview signals: tv-search, song-select, set-venue, set-deepar-effect, toggle-accessory, mic-connected, etc.). 21 sendToStage callsites remain unwrapped — 18 performance signals (only reachable from active code paths anyway: start-countdown, lyrics-*, perf-screen pan/zoom, song-ended) plus 3 deliberate stage-altering features (video-chat ×2, home-toggle-comments).

mic-connected was the most subtle catch — it told stage.html "I'm the singer, hide idle panel," which was wrong for queued/audience users publishing mic. Wrapped.

Inline venue thumbnails added to the venue picker tile grid (uses existing `venues/{id}.jpg`, `object-fit: cover`, 60px tall). Applies to all roles. DeepAR effects already had emoji thumbnails from existing `DEEPAR_EFFECTS[]` data — no new asset work needed (originally feared but disproven during §5 read step).

### Take Stage modal

Full-screen overlay (`#take-stage-modal`) with:
- 🎤 emoji + role display name + "YOU'RE UP!" headline + tap-to-confirm button
- `takeStageAudio` element pre-loaded from absolute GitHub Pages URL
- `navigator.vibrate([200, 100, 200, 100, 400])` on appear
- Idempotent against double-show
- `window.showTakeStageModal({display_name, user_id})` exposed for console testing

Modal dismisses to screen-home where §2's role-aware logic shows ▶ Start Performance, then existing flow runs.

### Promotion push trigger (§6b)

Postgres-side: `db/015_promotion_push_trigger.sql` adds `pg_net` extension, `fire_promotion_push()` SECURITY DEFINER function, and trigger on `session_participants` UPDATE. Tightened WHEN clause:

```sql
when (OLD.participation_role = 'queued' AND NEW.participation_role = 'active')
```

Self-initiated `audience → active` (§3 Start Song path) does not push — the user just tapped the button on their own phone. Manager force-promote in 2e.3 will route through `queued → active` for queued users (which is correct — push them) and `audience → active` for audience users (which is correct — don't push them, the manager just yanked them up).

The trigger reads two values from Supabase Vault: `edge_fn_url` (the function endpoint) and `service_role_key` (legacy JWT). Both must be set before the trigger fires; missing secrets emit a `raise warning` and skip silently. Trigger uses `pg_net.http_post` (async; returns immediately, request queued and sent off-loop).

Edge function side: header comment updated to document the dual auth model. New service-role auth branch checks `Bearer === serviceRoleKey`; if true, skips JWT user verification. For service-role calls with `body.type === "promotion"`, function synthesizes canonical title ("You're up!") and body ("Tap to take the stage") so the SQL caller can stay minimal — no notification copy in plpgsql. Existing user-JWT path preserved (still requires explicit title/body).

Client side: `handleParticipantRoleChanged` extended. Realtime payload from `shell/realtime.js:25` is `{session_id, user_id, control_role, participation_role}` — no `old_role` field. Client captures `currentMyRow?.participation_role` as the local "before" state, awaits `refreshSessionState()`, then compares. If own user transitioned `queued → active`:
- Foreground (`document.visibilityState === 'visible'`): fire `showTakeStageModal()` directly.
- Background: set `sessionStorage['elsewhere.missed-promotion']` flag. Server-side push trigger handles the actual notification.

`visibilitychange` handler is the safety net: on hidden→visible, if flag is set, re-query session state and fire modal if still active. If skipped while away (e.g., manager promoted someone else, current user no longer active), silently skip — no modal, no toast.

---

## Decisions locked along the way

### Path A from model audit, applied in §1's banner branch (carried in from 2e.1)

The 2e.1 model audit Path A — eligibility-derived banner, no schema change — is the assumed baseline. 2e.2's role-aware rendering builds on top: `participation_role === 'audience' AND eligible` is the "Available Singer not queued" surface; `participation_role === 'audience' AND NOT eligible` is the watching-only surface. CLAUDE.md doctrine (singer.html surface is HHU-eligible by construction) means the not-eligible branch is dead code on this surface — implementation goes eligible-only and flags the dead branch. If audience-not-eligible ever reaches singer.html, the right answer is a routing decision (kick to audience.html), not a render branch.

### Audience-not-eligible: browse-only

Audience users on screen-home see no commit CTA but the action grid stays clickable. They can browse Find Song / Venues / Costume for fun (no commit, no queue). Mic / Video Chat / Invite stay functional. §5's signal suppression naturally extends to them via `roleAllowsStageSignals()` returning false.

### ⌂ Home tile removed in §2

The legacy ⌂ Home tile in screen-home navigated to `tv2.html` (the Agora launcher), pre-dating the Elsewhere shell. Per Session 5 doctrine, Back-to-Elsewhere pill (← Elsewhere, top-right) is the canonical exit. The ⌂ Home tile was the redundant Leave button the audit referenced. Deleted; pill remains.

### Section split for §6

§6a (modal DOM + audio + vibration) and §6b (realtime hookup + push trigger) shipped as separate commits. Console-testability of §6a in isolation made the split valuable — caught a stale comment (the "fires before §6b realtime" comment) before it became wrong, and verified DOM/audio/vibration work before any realtime plumbing was touched.

### Push origin: server-side trigger (Option C)

Original framing was Option (a) self-pushes-self vs. Option (b) manager-pushes-promotee. Both were client-dependent and would fail when JS wasn't running on the relevant device — exactly the case push is supposed to solve. Option (c) — Postgres trigger on row UPDATE fires `pg_net.http_post` to edge function — was bulletproof and turned out to be cheaper than (b) once `pg_net` was confirmed available. Path B (manager-fires) discarded; Path C (trigger) shipped.

### Audio asset location: sounds/ui/

Application-level UI sounds (notifications, transitions, alerts) belong centrally, not buried inside per-app folders. New convention: `sounds/ui/take-stage.mp3` for the chime. Future application sounds (error chimes, transition stings) go there. Venue ambient audio stays at `sounds/` root to match `venues.json`'s implicit convention. CLAUDE.md repo-layout note should pick this up next time it's edited.

### F1 — Payload-shape adaptation in §6b

Realtime payload doesn't carry `old_role`. Client captures `currentMyRow?.participation_role` as the local before-state, awaits `refreshSessionState()`, then compares. The comparison correctly fires for own queued→active, doesn't fire for own audience→active, and is a no-op for events about other users.

### F2 — Edge function generates canonical promotion text

When trigger calls with `body.type === 'promotion'`, edge function synthesizes title "You're up!" and body "Tap to take the stage" rather than embedding copy in plpgsql. Notification copy stays in the layer closest to the user; future i18n / localization lives in one place. SQL stays narrow and uniform — every trigger payload is `{user_id, type, session_id}`.

### F3 — Trigger WHEN tightened to queued→active only

Original plan was "any → active." Tightened to `OLD = 'queued' AND NEW = 'active'`. Self-initiated audience→active (the §3 Start Song path) now does not fire push — the user just tapped the button. Manager force-promote in 2e.3 routes correctly through queued→active for queued users.

### F4 — Commit message accuracy

Multiple iterations to keep commit messages honest about what was actually verified. Static review claims call out "no browser testing" or "static review only" when accurate. The commit message describes code state, not future Supabase-side actions (apply, deploy, etc. happen separately and are noted as such).

---

## What's pending

### Real-device end-to-end push test

Not done in-session. Architecture verified piece-by-piece:
- Migration applied (trigger and function exist, queryable from `pg_trigger` / `pg_proc`)
- Edge function redeployed (Code tab shows new auth model + service-role branch + type='promotion' synthesis)
- Vault secrets readable (`select name from vault.decrypted_secrets where name in ('edge_fn_url','service_role_key')` returns both)
- Modal verified end-to-end via browser console (§6a)

The full chain — queue, manager-promotes-via-SQL, APNs receives, modal fires — has not been observed. Spec'd test plan:

1. Phone A: sign in, claim TV, tap Karaoke
2. Pick a song, Add to Queue (banner shows "Queued — #1 of 1")
3. SQL editor: `update session_participants set participation_role = 'active' where session_id = '<id>' and user_id = '<id>';`
4. Test 1 (foreground): modal + audio + vibration; LOG `§6b: own promotion received foregrounded → modal`
5. Test 2 (background): lock screen, run same UPDATE. APNs notification, tap to foreground, modal via visibilitychange path

If any step fails: function logs at dashboard → Edge Functions → send-push-notification → Logs; Postgres trigger errors at dashboard → Logs → Postgres.

### Production APNs cert

2e.0 shipped sandbox-only (development environment). Production cert and `aps-environment = production` flip is still pending. Not 2e.2 scope. Carried forward from 2e.0.

### Failed-token cleanup

When APNs returns 410 BadDeviceToken, the row in `push_subscriptions` should be deleted. TODO comment in index.ts persists. Not blocking 2e.2; will surface as latent failed sends in the Logs tab over time.

---

## Known issues (not 2e.2 bugs)

### Carried from 2c.2

- Proximity banner Yes/No buttons unresponsive (existing 2c.2 issue, surfaced in 2e.0 log)
- "Don't ask again" should be a checkbox not a link (2c.2)

### Carried from 2e.0

- Sandbox-only APNs cert
- TV picker shows for n>=2 households (intentional, from Session 4.10.2)

### New surfacings during 2e.2

- 5-tile action grid leaves an orphan tile in row 3 col 1 (after ⌂ Home removal). Visual; not functional. Polish for unified-app migration post-Session-5.
- Native confirm() in §4's leave-queue dialog uses [OK]/[Cancel] vs spec's [Continue]/[Cancel] — same papercut as 2c.2/2c.3. Custom modal still deferred.
- DEFERRED item from 2e.2: nothing logged. (Originally planned to file "Generate per-effect thumbnails for karaoke/effects/" but `DEEPAR_EFFECTS[]` already has emoji thumbnails so no DEFERRED entry was needed.)

---

## Lessons learned

### Chat-display autolinking is real, persistent, and bites at copy-paste time

Filenames with `.md` / `.ts` / `.sql` extensions in chat output get rendered as `[filename](http://filename)` by the chat client, and that markdown link syntax persists through copy-paste into terminal commands. Bash then fails on the brackets. Multiple iterations of bundle creation, commit messages, and grep commands hit this throughout the session.

Mitigations that worked:
- Build paths from variables in shell (`EXT=md`, then `cat ... | sed "s/__EXT__/$EXT/"`)
- Use `pbcopy` from terminal directly, bypass chat copy-paste entirely
- Drop file paths from commit messages where possible; reference by SHA only
- Verify the dialog text before approving every dialog with a path in it

Cost ~15-20 minutes total across the session. Pattern recognition got faster but corrupted commands kept slipping through approval dialogs.

### Reading the helper before extending broke a real bug in §4

§4's spec said "pass `pre_selections: {}` to clear the column on leave." Claude Code's pre-implementation read of §1's `doSelfRoleUpdate` helper revealed that the helper merges client-side, so `{}` evaluates to `{...existing, ...{}}` = existing. The intended clear would have been a no-op write. Caught before commit, fixed by simply omitting the `pre_selections` key (which makes the helper skip the merge branch entirely, leaving the DB column unchanged). Better UX too — local `selectedVideo` stays so re-queueing the same song is one tap.

The lesson: helpers added in earlier sections are easy to misremember by the time later sections call them. Reading the implementation before each extension is cheap insurance.

### Static checks aren't tests; commit messages should reflect what was actually verified

Several times Claude Code drafted "Tested in browser: ..." in a commit message when only static grep checks had run. Caught and corrected each time. New default: third `-m` says "Static review only" or "Verified in browser: <specific paths>" — never claim verification of paths that weren't actually exercised.

### Supabase API key model has migrated; legacy JWT still works for existing functions

The new `sb_publishable_*` / `sb_secret_*` key format was introduced; legacy `service_role` JWT is still available under "Legacy anon, service_role API keys" tab. The edge function's `Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")` returns the legacy JWT, so the trigger's Vault secret must be the legacy JWT to match. New-format keys would break the comparison. Worth noting if Supabase ever forces the migration — edge function would need an update to accept either format.

### CLI deploy worked despite earlier fragility

`supabase functions deploy send-push-notification` worked first try on the §6b deploy, despite earlier session friction with `supabase status` / `supabase projects`. CLI auth was apparently still good from a previous session. Worth trying CLI before assuming dashboard-only path.

### Single-script HTML files at 2200+ lines work, but section reading discipline matters

singer.html is 2412 lines after 2e.2 (was 2210 entering the session). Every section's read step explicitly named the lines, IDs, function names being touched. No accidental cross-section regressions. The grep-for-line-numbers + cite-the-anchors pattern scaled fine for the size of file.

---

## File inventory

New (committed in 9ec5006):
- db/015_promotion_push_trigger.sql

Modified across the 7 §-commits (singer.html lifecycle):
- karaoke/singer.html (every section)
- supabase/functions/send-push-notification/index.ts (only §6b)

New asset (committed in eb6e7f4):
- sounds/ui/take-stage.mp3 (65 KB, MPEG layer III, 256 kbps, 44.1 kHz; sourced from universfield-new-notification-057-494255 on Pixabay)

Server-side ops (not in repo):
- pg_net extension enabled in Supabase project gbrnuxyzrlzbybvcvyzm
- Vault secrets created: edge_fn_url, service_role_key
- Edge function send-push-notification redeployed with §6b changes

iOS shell unchanged this session. ~/Projects/elsewhere-app rsync + cap sync not needed since web bundle changes are live on GitHub Pages and the app loads the bundled web payload from a prior 2e.0 sync. Real-device test will exercise that bundle; if any §6a/§6b client behavior fails, an rsync + cap sync + Xcode rebuild will be needed to refresh the iOS bundle.

---

## Commits

In chronological order (newest last):

```
0f51407  karaoke(2e.2): foundation — doSelfRoleUpdate helper for own-row mutations [v2.104]
0b9563c  karaoke(2e.2): role-aware screen-home tile rendering [v2.105]
[s3]     karaoke(2e.2): wire primary CTA dispatch through doSelfRoleUpdate [v2.106]
[s4]     karaoke(2e.2): wire Leave Queue handler [v2.107]
ad867a7  karaoke(2e.2): suppress TV signals for non-Active roles + venue thumbnails [v2.108]
eb6e7f4  assets: add take-stage notification chime for karaoke promotion modal
64b87e3  karaoke(2e.2): Take Stage modal DOM + audio + vibration [v2.109]
9ec5006  karaoke(2e.2): promotion push trigger + edge fn service-role + client modal hookup [v2.110]
```

(SHAs for §3 and §4 not captured in chat scrollback; ad867a7 was on origin before the audio asset commit so they're between 0b9563c and ad867a7.)

All eight pushed to origin/main.

---

## Next session: 2e.3

Per the original 2e audit phase plan, 2e.3 is Session Manager queue management UI plus Manager Override mechanism (Option B from the audit — manager phone joins Agora as host with mic-mute discipline). Estimated 3-4 hours, 5-6 sections.

Expected scope:
- Conditional manager-view UI on singer.html when `control_role === 'manager'`
- Queue management actions: reorder, force-promote, skip current, take over
- RPCs: `rpc_session_update_participant` (cross-user — manager can mutate others' rows), `rpc_session_update_queue_position`
- Manager Override mechanism: manager joins Agora as host, sends mid-song commands directly via existing sendToStage path
- Decide manager force-promote behavior re: push trigger (currently manager force-promote on a queued user fires push correctly; force-promote on an audience user does not — which is correct per spec but worth re-verifying once the UI exists)

Carry-forward to 2e.3:
- Production APNs cert + entitlement flip
- Failed-token cleanup (TODO from 2e.0, still TODO)
- Custom confirm-modal styling (papercut across 2c.2 / 2c.3 / 2e.2 §4)

---

## End of log
