# Session 5 Part 2e.2 — Self Write Actions on singer.html (Log)

Date: April 28, 2026
Status: SHIPPED end-to-end. Verified on real iPhone (Capacitor app v2.110). Real APNs push → backgrounded device → notification tap → foreground recovery → modal — full chain working.
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
| 2 | 0b9563c | Role-aware screen-home tile rendering + Home tile removed |
| 3 | df5a002 | Primary CTA dispatch through doSelfRoleUpdate |
| 4 | 66db4fb | Wire Leave Queue handler (queued → audience) |
| 5 | ad867a7 | Suppress TV signals for non-Active roles + inline venue thumbnails |
| -  | eb6e7f4 | Audio asset (sounds/ui/take-stage.mp3) |
| 6a | 64b87e3 | Take Stage modal DOM + audio + vibration |
| 6b | 9ec5006 | Promotion push trigger + edge fn service-role branch + client modal hookup |
| 6b-fix | ee7849a | Switch §6b trigger auth to PROMOTION_TRIGGER_SECRET (post-verification fix) |

Versioning arc: v2.103 (post 2e.1) → v2.104 (§1) → v2.105 (§2) → v2.106 (§3) → v2.107 (§4) → v2.108 (§5) → v2.109 (§6a) → v2.110 (§6b). The §6b-fix commit (ee7849a) edited the Edge Function only — no version bump (function carries no v2.NN badge).

### Server-side ops applied

- Migration db/015_promotion_push_trigger.sql applied via Supabase Dashboard SQL Editor (returned `migration 015 loaded`)
- Edge function send-push-notification redeployed multiple times via `supabase functions deploy` from local repo. Final deploy used `--no-verify-jwt` flag (REQUIRED — see Known issues)
- pg_net extension enabled (was available, version 0.20.0, off-by-default)
- Vault secret `edge_fn_url` set to the Edge Function URL
- Vault secret `service_role_key` (legacy name, kept for db/015 SQL compatibility) holds the shared trigger secret. Initially populated with the legacy service_role JWT; later updated to `PROMOTION_TRIGGER_SECRET` value (a 32-byte hex random string) to fix the auth handshake — see Verification phase
- `PROMOTION_TRIGGER_SECRET` set as Edge Function env var via `supabase secrets set`

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
| Active (pre-song) | Start Performance |
| Queued | Update My Song + Leave Queue link |
| Audience eligible, queue empty + no active singer | Start Song (becomes active immediately) |
| Audience eligible, queue or active singer | Add to Queue |
| Audience not eligible | (no CTA — browse-only) |
| Way 1 fallback (no session) | legacy Start Performance behavior |

`handleHomePrimaryCTA()` dispatches by role + state. Way 1 fallback preserved throughout — no `currentMyRow` means legacy single-singer behavior, no DB writes.

### Signal suppression

`roleAllowsStageSignals()` gate added in §5. Returns `true` for Active Singer (or Way 1 fallback), `false` otherwise. Wraps 18 sendToStage callsites (browse/preview signals: tv-search, song-select, set-venue, set-deepar-effect, toggle-accessory, mic-connected, etc.). 21 sendToStage callsites remain unwrapped — 18 performance signals (only reachable from active code paths anyway: start-countdown, lyrics-*, perf-screen pan/zoom, song-ended) plus 3 deliberate stage-altering features (video-chat ×2, home-toggle-comments).

mic-connected was the most subtle catch — it told stage.html "I'm the singer, hide idle panel," which was wrong for queued/audience users publishing mic. Wrapped.

Inline venue thumbnails added to the venue picker tile grid (uses existing `venues/{id}.jpg`, `object-fit: cover`, 60px tall). Applies to all roles. DeepAR effects already had emoji thumbnails from existing `DEEPAR_EFFECTS[]` data — no new asset work needed (originally feared but disproven during §5 read step).

### Take Stage modal

Full-screen overlay (`#take-stage-modal`) with:
- Microphone emoji + role display name + "YOU'RE UP!" headline + tap-to-confirm button
- `takeStageAudio` element pre-loaded from absolute GitHub Pages URL
- `navigator.vibrate([200, 100, 200, 100, 400])` on appear
- Idempotent against double-show
- `window.showTakeStageModal({display_name, user_id})` exposed for console testing

Modal dismisses to screen-home where §2's role-aware logic shows Start Performance, then existing flow runs.

### Promotion push trigger (§6b)

Postgres-side: `db/015_promotion_push_trigger.sql` adds `pg_net` extension, `fire_promotion_push()` SECURITY DEFINER function, and trigger on `session_participants` UPDATE. Tightened WHEN clause:

```sql
when (OLD.participation_role = 'queued' AND NEW.participation_role = 'active')
```

Self-initiated `audience → active` (§3 Start Song path) does not push — the user just tapped the button on their own phone. Manager force-promote in 2e.3 will route through `queued → active` for queued users (which is correct — push them) and `audience → active` for audience users (which is correct — don't push them, the manager just yanked them up).

The trigger reads two values from Supabase Vault: `edge_fn_url` (the function endpoint) and `service_role_key` (the shared trigger secret — see auth-handshake decision below). Both must be set before the trigger fires; missing secrets emit a `raise warning` and skip silently. Trigger uses `pg_net.http_post` (async; returns immediately, request queued and sent off-loop).

Edge function side: header comment updated to document the dual auth model. Service-role auth branch checks `Bearer === <shared trigger secret>`; if true, skips JWT user verification. For service-role calls with `body.type === "promotion"`, function synthesizes canonical title ("You're up!") and body ("Tap to take the stage") so the SQL caller can stay minimal — no notification copy in plpgsql. Existing user-JWT path preserved (still requires explicit title/body).

Client side: `handleParticipantRoleChanged` extended. Realtime payload from `shell/realtime.js:25` is `{session_id, user_id, control_role, participation_role}` — no `old_role` field. Client captures `currentMyRow?.participation_role` as the local "before" state, awaits `refreshSessionState()`, then compares. If own user transitioned `queued → active`:
- Foreground (`document.visibilityState === 'visible'`): fire `showTakeStageModal()` directly.
- Background: set `sessionStorage['elsewhere.missed-promotion']` flag. Server-side push trigger handles the actual notification.

`visibilitychange` handler is the safety net: on hidden→visible, if flag is set, re-query session state and fire modal if still active. If skipped while away (e.g., manager promoted someone else, current user no longer active), silently skip — no modal, no toast.

---

## Decisions locked along the way

### Path A from model audit, applied in §1's banner branch (carried in from 2e.1)

The 2e.1 model audit Path A — eligibility-derived banner, no schema change — is the assumed baseline. 2e.2's role-aware rendering builds on top: `participation_role === 'audience' AND eligible` is the "Available Singer not queued" surface; `participation_role === 'audience' AND NOT eligible` is the watching-only surface. CLAUDE.md doctrine (singer.html surface is HHU-eligible by construction) means the not-eligible branch is dead code on this surface — implementation goes eligible-only and flags the dead branch.

### Audience-not-eligible: browse-only

Audience users on screen-home see no commit CTA but the action grid stays clickable. They can browse Find Song / Venues / Costume for fun (no commit, no queue). Mic / Video Chat / Invite stay functional. §5's signal suppression naturally extends to them via `roleAllowsStageSignals()` returning false.

### Home tile removed in §2

The legacy Home tile in screen-home navigated to `tv2.html` (the Agora launcher), pre-dating the Elsewhere shell. Per Session 5 doctrine, Back-to-Elsewhere pill (top-right) is the canonical exit. The Home tile was the redundant Leave button the audit referenced. Deleted; pill remains.

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

### Auth-handshake refactor (post-verification, ee7849a)

Original §6b assumed `Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")` in the Edge Function would return the legacy `service_role` JWT — same value we put in vault for the trigger to send. This assumption was wrong: Supabase has migrated to a new key model and auto-provisions that env var to the new `sb_secret_...` format, which does NOT match the legacy JWT.

Discovered via `net._http_response` table during real-device testing: trigger fired correctly, pg_net delivered the request, but the Edge Function returned 401 `{"error":"invalid token"}` because `isServiceRole` was false (legacy JWT in `Bearer` header didn't match `sb_secret_...` from env var).

Initial recovery attempt: put the new `sb_secret_...` key in vault. Failed differently — Supabase's edge gateway rejected with `UNAUTHORIZED_INVALID_JWT_FORMAT` because the gateway requires JWT-formatted bearer tokens before handing off to function code.

Final resolution:
1. Generate a purpose-specific shared secret: `openssl rand -hex 32` (64-char hex).
2. Set as Edge Function env var: `supabase secrets set PROMOTION_TRIGGER_SECRET=<value>`.
3. Update vault `service_role_key` to that same value (kept the vault name for db/015 backward compatibility — would have been a SQL change otherwise).
4. Patch Edge Function index.ts to compare `authHeader` against `Deno.env.get("PROMOTION_TRIGGER_SECRET")` instead of `SUPABASE_SERVICE_ROLE_KEY`.
5. Redeploy with `--no-verify-jwt` flag so the gateway doesn't reject the non-JWT bearer; function code does the actual auth check.

The shared-secret design is cleaner anyway: purpose-specific (only valid for THIS function), rotatable independently of the project's service role, and decouples §6b from Supabase's evolving key formats. The cost was an extra deploy step requirement (see Known issues).

---

## Verification phase (real-device end-to-end)

### Build pipeline

After §6b commit + auth-handshake fix:
- `rsync ~/Downloads/elsewhere-repo/ ~/Projects/elsewhere-app/www/` with excludes for `.git`, `node_modules`, `docs`, `db`, `supabase`, `.DS_Store`, `*.pem`, `*.crt`, `*.key`. ~70MB transferred (mostly venue images already present, just a few changed files; rsync's incremental transfer worked correctly).
- `npx cap sync ios` succeeded in <500ms; 3 plugins detected (App, Browser, PushNotifications).
- Xcode build + install on iPhone (60). Old v2.99 build was already on the phone; build replaced it cleanly.
- Phone showed v2.110 in singer.html badge; confirmed via grep on `~/Projects/elsewhere-app/www/karaoke/singer.html` (returned `2` for `v2.110` matches — at lines 208 and 218 as expected).

Note on shell version: `index.html` still shows v2.99 because the shell wasn't touched in 2e.2. Different surfaces have independent version stamps. Today's work bumped only singer.html.

### Test 1 — foreground promotion (modal + realtime hookup)

Phone joined session 51225fd2 as audience. SQL UPDATE moved phone to queued — phone refreshed within 2 seconds, banner changed to "Queued — #1 of 1", CTA changed to "Update My Song" + "Leave Queue" link, crown emoji rendered (manager indicator). §2 + §3 + §4 affordances all rendered correctly.

SQL UPDATE then moved phone queued→active. Phone DID eventually refresh (LOG showed `my role=active`) but NO §6b modal fired. Investigation revealed: direct SQL UPDATEs on `session_participants` do NOT trigger realtime broadcasts. The realtime publish path runs inside RPCs (e.g., `rpc_session_update_participant`), not at the table level. Direct UPDATEs bypass the RPC entirely.

The audience→queued event we did receive was apparently a coincidence with a heartbeat refresh, not a true realtime publish. This is consistent with the design but worth knowing for future test patterns: real client realtime testing requires real client actions or RPC calls, not raw SQL.

So Test 1 verified §1, §2, §3, §4, and the modal DOM (via separate browser console call earlier in the session), but did NOT exercise the §6b realtime → modal path. That path requires either a real client write (e.g., manager UI in 2e.3 calling the RPC) or further test infrastructure.

### Test 2 — backgrounded promotion + APNs push (full §6b chain)

This is the test that mattered. Reset phone to queued. Locked iPhone screen (app in background). Ran SQL UPDATE queued→active.

Result: real APNs notification banner appeared on lock screen: **"You're up! / Tap to take the stage"**. Tapped it. iPhone unlocked, app foregrounded, visibilitychange handler ran, queried session state, saw active, fired modal. Modal rendered with audio chime + vibration + tap-to-confirm. Tapped modal — dismissed to screen-home with "Start Performance" CTA visible.

`net._http_response` confirmed: `status_code=200`, content `{"sent":1,"failed":0,"details":[{"device_token":"A3499EBA...","status":200,"apns_id":"..."}]}`.

The full §6b chain works end-to-end:
1. SQL UPDATE queued→active
2. Postgres trigger `trg_fire_promotion_push` fires
3. `pg_net.http_post` calls Edge Function with `Bearer <PROMOTION_TRIGGER_SECRET>`
4. Gateway lets the bearer through (because of `--no-verify-jwt`)
5. Edge Function recognizes service-role auth via `PROMOTION_TRIGGER_SECRET` env match
6. Function reads token from `push_subscriptions`
7. Function signs APNs JWT + sends notification
8. APNs accepts, status 200, apns_id assigned
9. iPhone receives notification banner
10. User taps notification → app foregrounds
11. Client `visibilitychange` handler clears flag, re-queries state, sees active, fires modal

This is the actual user-facing scenario: someone's phone is in their pocket while playing the round, manager promotes them next, push notification fires, they tap to come up. Verified working.

---

## What's pending

### Production APNs cert

2e.0 shipped sandbox-only (development environment). Production cert and `aps-environment = production` flip is still pending. Not 2e.2 scope. Carried forward from 2e.0.

### Failed-token cleanup

When APNs returns 410 BadDeviceToken, the row in `push_subscriptions` should be deleted. TODO comment in index.ts persists. Not blocking 2e.2; will surface as latent failed sends in the Logs tab over time.

---

## Known issues (some new in 2e.2)

### Carried from earlier sessions
- Proximity banner Yes/No buttons unresponsive (existing 2c.2 issue)
- "Don't ask again" should be a checkbox not a link (2c.2)
- Sandbox-only APNs cert (carried from 2e.0)
- TV picker shows for n>=2 households (intentional, from Session 4.10.2)

### New surfacings during 2e.2

#### Edge Function deploys must include `--no-verify-jwt`

The trigger sends a non-JWT bearer (the shared secret). Without `--no-verify-jwt`, Supabase's edge gateway rejects the call before it reaches function code with `UNAUTHORIZED_INVALID_JWT_FORMAT`. Future deploys of `send-push-notification` MUST include this flag:

```bash
supabase functions deploy send-push-notification --no-verify-jwt
```

A vanilla `supabase functions deploy send-push-notification` will silently re-enable JWT verification at the gateway level, breaking the trigger.

This is a real footgun. Worth adding to CLAUDE.md and/or wrapping in a script (`scripts/deploy-push-fn.sh`). Filed as DEFERRED.

#### TV's app-launch realtime not reaching tv2.html

During 2e.2 testing, phone tapping Karaoke from the household home did NOT navigate the TV from `tv2.html` (idle launcher) to `karaoke/stage.html`. Phone's realtime publish presumably fired (downstream effects worked: phone joined session, mic published, push token registered) but the TV's listener didn't pick it up. TV LOG showed `realtime: subscribed` and `state: authed + registered → apps` (waiting at launcher) but no app-launch event received.

Possible causes: phone never fired the publish (less likely — would have other downstream effects), TV not subscribed to the right channel, channel name mismatch, or §5's `roleAllowsStageSignals()` accidentally suppressed something it shouldn't have. Worth investigating in 2e.3 prep — though the test we ran sidestepped this entirely (joined session via QR/code path; TV being stuck at launcher didn't block the push test).

#### Direct SQL UPDATEs do not publish realtime events

The 2e.1 realtime work added publish hooks inside the RPCs (`rpc_session_update_participant` etc.), not at the table level. So direct SQL UPDATEs on `session_participants` succeed but the `participant_role_changed` event never publishes — connected clients don't refresh. This is fine for production (real client actions go through RPCs) but means manual testing with raw SQL UPDATEs cannot fully exercise client realtime handlers.

For 2e.3 test patterns: prefer RPC calls over raw SQL when testing flows that involve client realtime reactions. Or build a test helper that wraps the RPCs.

#### Pre-existing JS error at singer.html:645

Xcode console captured an error during the v2.99 (pre-2e.2) bundle's startup: `TypeError: null is not an object (evaluating 'document.getElementById("stat-w").textContent=n')` at line 645:40. The `stat-w` element didn't exist in the DOM at the time the code ran. Pre-existing in v2.99-ish; possibly fixed by 2e.2's DOM changes (didn't reproduce in v2.110), possibly still latent. Worth a quick grep + audit when next touching singer.html.

#### Cosmetic / latent

- 5-tile action grid leaves an orphan tile in row 3 col 1 (after Home tile removal). Visual; not functional. Polish for unified-app migration post-Session-5.
- Native confirm() in §4's leave-queue dialog uses [OK]/[Cancel] vs spec's [Continue]/[Cancel] — same papercut as 2c.2/2c.3. Custom modal still deferred.

---

## Lessons learned

### Chat-display autolinking is a display artifact, not real corruption

Chat client renders filenames with `.md`, `.ts`, `.sql` extensions as `[name](http://name)` markdown autolinks. These are PURELY visual in the chat window. The actual filesystem and git always had clean filenames. This bit us for ~10 minutes mid-session when terminal output pasted into chat looked corrupted; verifying via `ls | cat` and a direct screenshot of Terminal proved the corruption was confined to chat display.

Mitigations that worked:
- Build paths from variables in shell (`F=~/path/to/file.md; ls "$F"`)
- Use `pbcopy` from terminal directly (clipboard preserves bytes correctly)
- Drop file paths from commit messages where possible; reference by SHA only
- Trust the screenshot of your real Terminal more than the rendering in chat

Cost ~10-15 min total before recognition. Pattern recognition got faster but corrupted commands still slipped through approval dialogs occasionally.

### Reading the helper before extending broke a real bug in §4

§4's spec said "pass `pre_selections: {}` to clear the column on leave." Claude Code's pre-implementation read of §1's `doSelfRoleUpdate` helper revealed that the helper merges client-side, so `{}` evaluates to `{...existing, ...{}}` = existing. The intended clear would have been a no-op write. Caught before commit, fixed by simply omitting the `pre_selections` key. Better UX too — local `selectedVideo` stays so re-queueing the same song is one tap.

The lesson: helpers added in earlier sections are easy to misremember by the time later sections call them. Reading the implementation before each extension is cheap insurance.

### Static checks aren't tests; commit messages should reflect what was actually verified

Several times Claude Code drafted "Tested in browser: ..." in a commit message when only static grep checks had run. Caught and corrected each time. New default: third `-m` says "Static review only" or "Verified in browser: <specific paths>" — never claim verification of paths that weren't actually exercised.

### Don't trust env-var assumptions about Supabase-managed keys

`Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")` historically returned the legacy `service_role` JWT. Since Supabase's key model migration, it auto-resolves to the new `sb_secret_...` format. We assumed continuity and didn't verify until the function 401'd in production. Diagnosis required walking through three failure modes: legacy JWT (mismatched env), new sb_secret (gateway rejection), and finally a purpose-specific shared secret with `--no-verify-jwt`.

For future Supabase-managed env vars: dump the actual value from inside the function (carefully — log only first/last 8 chars) before assuming what it returns. Or skip the question entirely by using purpose-specific secrets you control.

### `supabase functions deploy` worked despite earlier session friction

CLI deploys worked first try on every attempt despite earlier 2e.0/2e.1 friction with `supabase status` / `supabase projects`. CLI auth was good for the whole session. Worth trying CLI before assuming dashboard-only path.

### Single-script HTML files at 2400+ lines work, but section reading discipline matters

singer.html is 2412 lines after 2e.2 (was 2210 entering the session). Every section's read step explicitly named the lines, IDs, function names being touched. No accidental cross-section regressions. The grep-for-line-numbers + cite-the-anchors pattern scaled fine for the size of file.

### `pg_net._http_response` is the smoking-gun diagnostic for trigger-to-function calls

During the auth-handshake debugging, `select * from net._http_response order by id desc` was the single most useful diagnostic. It shows status codes, response bodies, and timestamps for every pg_net request. Knowing this exists and how to read it dramatically shortened the debug loop. Worth keeping in a doc'd library of common diagnostics.

---

## File inventory

Migrations:
- db/015_promotion_push_trigger.sql (NEW, in 9ec5006)

Functions:
- supabase/functions/send-push-notification/index.ts (MODIFIED, in 9ec5006 and ee7849a)

Karaoke:
- karaoke/singer.html (MODIFIED across all 7 §-commits)

Assets:
- sounds/ui/take-stage.mp3 (NEW, in eb6e7f4; 65 KB MP3; sourced from Pixabay)

Server-side ops (not in repo):
- pg_net extension enabled in Supabase project gbrnuxyzrlzbybvcvyzm
- Vault secrets created: edge_fn_url, service_role_key (latter holds shared trigger secret, not the JWT after auth-handshake fix)
- Edge Function env var set: PROMOTION_TRIGGER_SECRET
- Edge function send-push-notification redeployed with --no-verify-jwt flag

iOS shell now in sync (rsync + cap sync + Xcode rebuild + install on iPhone, v2.110 verified):
- ~/Projects/elsewhere-app/www/ (rsynced with appropriate excludes)
- ~/Projects/elsewhere-app/ios/App/App/public/ (cap sync target)

---

## Key file paths

- Repo: `~/Downloads/elsewhere-repo`
- iOS shell: `~/Projects/elsewhere-app`
- Audio asset: `~/Downloads/elsewhere-repo/sounds/ui/take-stage.mp3`
- Migration: `~/Downloads/elsewhere-repo/db/015_promotion_push_trigger.sql`
- Edge function: `~/Downloads/elsewhere-repo/supabase/functions/send-push-notification/index.ts`
- Singer page: `~/Downloads/elsewhere-repo/karaoke/singer.html` (~2412 lines, v2.110)
- GitHub Pages: `https://mstepanovich-web.github.io/elsewhere/`
- Supabase Dashboard: `https://supabase.com/dashboard/project/gbrnuxyzrlzbybvcvyzm`

---

## Commits

In chronological order:

```
0f51407  karaoke(2e.2): foundation — doSelfRoleUpdate helper for own-row mutations [v2.104]
0b9563c  karaoke(2e.2): role-aware screen-home tile rendering [v2.105]
df5a002  karaoke(2e.2): wire primary CTA dispatch through doSelfRoleUpdate [v2.106]
66db4fb  karaoke(2e.2): wire Leave Queue handler [v2.107]
ad867a7  karaoke(2e.2): suppress TV signals for non-Active roles + venue thumbnails [v2.108]
eb6e7f4  assets: add take-stage notification chime for karaoke promotion modal
64b87e3  karaoke(2e.2): Take Stage modal DOM + audio + vibration [v2.109]
9ec5006  karaoke(2e.2): promotion push trigger + edge fn service-role + client modal hookup [v2.110]
c75a768  docs(2e.2): session log (initial; superseded by this revision)
ee7849a  karaoke(2e.2): switch §6b trigger auth to PROMOTION_TRIGGER_SECRET
```

All on origin/main.

---

## Next session: 2e.3

Per the original 2e audit phase plan, 2e.3 is Session Manager queue management UI plus Manager Override mechanism (Option B from the audit — manager phone joins Agora as host with mic-mute discipline). Estimated 3-4 hours, 5-6 sections.

Expected scope:
- Conditional manager-view UI on singer.html when `control_role === 'manager'`
- Queue management actions: reorder, force-promote, skip current, take over
- RPCs: `rpc_session_update_participant` (cross-user — manager can mutate others' rows), `rpc_session_update_queue_position`
- Manager Override mechanism: manager joins Agora as host, sends mid-song commands directly via existing sendToStage path
- Decide manager force-promote behavior re: push trigger (currently force-promote on a queued user fires push correctly; force-promote on an audience user does NOT — which is correct per spec but worth re-verifying once the UI exists)

Carry-forward to 2e.3:
- TV-side app-launch realtime issue (investigate before testing manager UI on real TV)
- Edge Function deploy `--no-verify-jwt` flag requirement (document in CLAUDE.md or scripts/)
- Production APNs cert + entitlement flip
- Failed-token cleanup (TODO from 2e.0, still TODO)
- Custom confirm-modal styling (papercut across 2c.2 / 2c.3 / 2e.2 §4)
- Pre-existing JS error at singer.html:645 — investigate when next touching that file

---

## End of log
