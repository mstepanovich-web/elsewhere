# SESSION 4.10.2 PLAN — Phone-as-remote UX fixes

**Status:** Design complete, implementation not started
**Drafted:** 2026-04-21
**Depends on:** Session 4.10 shipped (v3.0 not yet, but merge state ≥ commit `e7952ae`)
**Unblocks:** Real customer acquisition; Session 4.11 (admin UI) benefits from this landing first

---

## Goal

Make the phone the primary remote control for the TV. Session 4.10 shipped a working claim + signin flow, but Part E verification exposed three coupled UX failures: the phone drops the user at a dead-end after claim, the TV has the only interactive app launcher (mental model inverted — TV is out of reach, phone is in hand), and relaunching the phone app gives no way to resume control of the TV the user already owns. This session fixes all three plus the adjacent TV sign-in screen copy that implies the wrong direction of action.

---

## Scope

### In scope

- **Phone-as-remote redesign** — the big one. Three coupled pieces:
  1. Phone home becomes "Your TVs" — persistent list of TVs the user is a member of.
  2. Remote-control screen on phone shows the 3 launchable apps. Tap → broadcast `launch_app` on `tv_device:<device_key>`.
  3. TV's apps grid becomes display-only (no click handlers; subtitle reads "Use your phone to select an app").
  - Ref: DEFERRED.md → "Phone-as-remote — persistent app launcher on phone, display-only grid on TV"

- **TV sign-in screen copy rewrite** — folded in here deliberately. Concrete strings picked below. Avoids a standalone Medium-priority session for three string swaps.
  - Ref: DEFERRED.md → "TV sign-in screen copy implies wrong direction of action"

- **Post-claim → app launcher transition** — phone, after a successful first-time claim, lands directly on the new remote-control screen for the just-claimed TV. No more "head to the TV" dead-end.

### Out of scope (mentioned briefly, link to DEFERRED)

- **claim.html App Store URL** — waits on the real iOS App Store listing. See DEFERRED "claim.html App Store URL placeholder".
- **Inline-script TDZ audit** — opportunistic per-file pass, not a session. See DEFERRED "Audit inline-script TDZ risk in other pages".
- **tv2.html render race** — Low priority, post-Session-5 polish. See DEFERRED "tv2.html render race — concurrent renderCurrentState calls".

### On ship, also do

Mark "TV sign-in screen copy implies wrong direction of action" in DEFERRED.md as **Folded into Session 4.10.2 scope** — strikethrough + preservation note. Same pattern used for the camera lazy-init resolution in Session 4.10 Part C.

---

## Architecture decisions (explicit answers, no punting)

### 1. `launch_app` broadcast shape

**Payload:** `{ app: 'karaoke' | 'games' | 'wellness', room: string }`

**Who generates the room code:** **Phone.** User taps on phone → phone generates a 6-char room code (same alphabet as tv2.html: `ABCDEFGHIJKLMNPQRSTUVWXYZ23456789`, no 0/1/O/I) → phone broadcasts → TV navigates.

Rationale: phone is the active agent in the new UX. TV generating would require phone to wait for TV's reply before showing a "now playing" state — extra round trip for zero benefit. Phone-side `crypto.getRandomValues` is trivial.

### 2. Reply from TV

**No reply.** One-way broadcast. Phone updates its UI to "Now playing Karaoke · Room ABCD" immediately on publish. TV navigates on receive. If TV fails to navigate (offline, bug, whatever), the user sees the room code on their phone and can physically investigate. A TV-side ack could be added post-4.10.2 if it turns out to matter in practice.

### 3. "Your TVs" home screen content

Each TV tile shows:
- **Household name** (primary, larger)
- **TV display name** (secondary, smaller)
- **Freshness dot** based on `last_seen_at`:
  - Green = within last 60s (TV is awake)
  - Yellow = within last 24h (TV is registered, may be asleep)
  - Gray = older (likely offline)

Tap → enters remote-control mode for that TV.

Stretch (if scope permits): "now playing" subtitle when TV is on `stage.html` / `games/tv.html`. Requires TV to publish its current location. Defer this; not blocking.

### 4. Post-claim transition

**Directly to the remote-control screen for the just-claimed TV.** Skip any picker. The user's intent at this moment is "launch an app on the TV I just set up."

They reach the picker (home "Your TVs") on any subsequent app launch — but only if they have ≥2 TVs (see Decision 5).

### 5. Singular vs plural picker (n=1 TV)

**If n=1, skip picker and go straight to remote-control screen for that single TV. If n≥2, show the "Your TVs" picker.**

Rationale: for n=1 the picker has nothing to pick — it's friction without benefit. The n≥2 case requires choice, so the UX divergence is intrinsic to the situation, not inconsistency for inconsistency's sake.

Implementation note: phone's home flow queries `tv_devices` first. If the result set has length 1, navigate directly to the remote-control screen for that TV. If length ≥2, render the picker. Length 0 means the user has no household membership — handled by pre-existing shell states (not a 4.10.2 concern).

### 6. Stale TV when phone foregrounds

Phone home screen **queries `tv_devices` on every foreground event** (Capacitor `App` listener: `appStateChange` → active). Shows a loading shimmer during query. Fresh results replace the list.

If a TV has been removed (user demoted/ejected from household by admin), it silently drops from the list on next refresh. No error dialog. The admin-side UX for "I removed you from the household" is explicitly Session 4.11's problem.

If the user is mid-launch and their membership is revoked between publish and TV-navigate, the TV silently ignores the broadcast (no session or session with no membership → RLS denies the app navigation's data reads). Acceptable for Phase 1.

### 7. Multi-TV, multi-phone, who triggered

**Phase 1: broadcast does NOT include triggerer identity.** Husband and wife both see the same TV; either can launch. Whoever tapped last wins. No conflict-resolution UI, no "take over?" prompt.

Session 5's `session_participants` is the natural place to track triggerer — punt until then.

### 8. Disabled Wellness tile

**On phone: hide entirely.** The launcher must feel snappy and actionable. A dead tile taunts the user.

**On TV: keep as a visual placeholder** with "Coming soon" subtitle. TV serves a "here's what's coming" signal to guests glancing at the room. Different job.

When Wellness actually ships, add the phone tile back.

### 9. TV sign-in screen copy — concrete strings

| Surface | Current | New |
|---|---|---|
| Title, pre-status | "Sign in on TV" | **"Signing in…"** |
| Title, post-status | (n/a — becomes success sub-text) | **"Signed in to `<household name>`"** |
| Sub-text, pre-status | "Connecting…" | **"Authenticating with your household"** |
| Sub-text, on success | "Head to the TV to continue" | **"Your TV is ready"** |
| Action button, on success | (none) | **"Open TV apps"** — navigates phone to remote-control screen for this TV |

Preposition choice: "to" not "on" — `Signed in to <household>` frames it as identity, not device.

---

## Data model

**No schema changes.** 4.10 already ships the tables and realtime channel this redesign needs. Phone reads `tv_devices` under the existing RLS policies. `launch_app` is a new event on the same `tv_device:<device_key>` channel that currently carries `session_handoff`.

If any schema work emerges during implementation, stop and revisit scope — the point of this session is UX on top of 4.10's foundation, not more DB work.

---

## Realtime channel — `launch_app` event

```
Channel: tv_device:<device_key>  (existing from 4.10)
Event:   'launch_app'
Payload: { app: 'karaoke' | 'games', room: 'ABC234' }

Publisher: phone (index.html remote-control screen)
Subscriber: tv2.html (adds to its existing 'session_handoff' listener)

TV action on receive:
  if event.app === 'karaoke' → location.href = 'karaoke/stage.html?room=' + room
  if event.app === 'games'   → location.href = 'games/tv.html?room=' + room
  (wellness not reachable; app === 'wellness' logs warning, no-op)
```

Phone does NOT await an ack. It optimistically updates UI to "Now playing…" the moment publish resolves.

---

## Parts breakdown

Approximate ordering. Each part is a pause-point for review.

### Part A — "Your TVs" home screen on phone

- **What:** New index.html screen `screen-your-tvs`. On mount: query `tv_devices` joined with `households` (filtered by user's household_members). If result length is 1, skip rendering this screen entirely and navigate to Part B's remote-control screen for that single TV (per Decision 5). If ≥2, render one tile per TV. Freshness dot computed from `last_seen_at`. Tap handler → navigate to Part B.
- **Foreground refresh:** Capacitor `App.addListener('appStateChange')` re-queries when app returns to foreground.
- **Files:** `index.html` (new screen markup + inline JS), `shell/auth.js` (maybe: a `loadUserTvs()` helper if it cleans up index.html).

### Part B — Remote-control screen on phone

- **What:** New index.html screen `screen-tv-remote`. Shows currently-selected TV's name at top, three app tiles below (Karaoke + Games; Wellness hidden). Tap tile → generate room code → `supabase.channel('tv_device:' + device_key).send({type: 'broadcast', event: 'launch_app', payload: {app, room}})` → update local state to "now playing" banner.
- **"Now playing" state:** simple banner at top of remote-control screen showing last-launched app + room + timestamp. No realtime sync; just local state. Clears when user taps a different app tile.
- **Back nav:** back button returns to "Your TVs" (Part A) — but only if the user arrived via the picker. If they arrived via the n=1 skip or via the post-claim flow, back nav returns to shell home.
- **Files:** `index.html` (new screen + broadcast publisher), `shell/auth.js` (probably no change — broadcast uses the raw `sb` client).

### Part C — tv2.html subscribes to `launch_app`; apps grid goes display-only

- **What:** Extend tv2.html's existing realtime subscription (added in 4.10 Part C) to handle `launch_app` events. On receive, navigate to product page. Remove `onclick` handlers from the three app tiles. Change tile subtitle text. Add "Use your phone to select an app" as a header-level instruction on the apps screen.
- **Files:** `tv2.html` (single file, bounded change).

### Part D — TV sign-in screen copy rewrite

- **What:** Apply the concrete strings from Architecture Decision 9 to `screen-tv-signin` in index.html. Add the "Open TV apps" button on success state — tap handler navigates to the remote-control screen for this device_key.
- **Files:** `index.html` only.
- **Mark DEFERRED entry:** strikethrough + "Folded into Session 4.10.2 scope" note.

### Part E — Post-claim direct transition to remote-control screen

- **What:** After `rpc_claim_tv_device` resolves successfully in index.html's claim flow, navigate the phone directly to the remote-control screen for the just-claimed device_key (skip the success-only dead-end screen). Queue the "Your TV is ready" banner as a one-shot toast on the remote-control screen's first render.
- **Files:** `index.html` only.

### Part F — Verification

- **What:** Create `docs/SESSION-4.10.2-VERIFICATION.md` (parallel to PART-E-VERIFICATION.md). Four flows:
  1. **Phone-first launch:** fresh claim → post-claim transitions directly to remote-control screen → tap Karaoke → TV navigates → stage.html loads with inherited session.
  2. **Relaunch-resume (n=1):** close app, reopen app, with a single claimed TV the app lands directly on the remote-control screen for that TV (per Decision 5). Tap Karaoke, launch works.
  3. **Copy correctness:** trigger sign-in flow from laptop (devtools snippet per PART-E's pattern), scan, verify the new copy appears, success state shows "Open TV apps" button, tapping it lands on remote-control screen.
  4. **Multi-TV sanity:** claim a second TV from the same household using a second browser tab. Verify both TVs appear in phone's "Your TVs" picker. Verify launching from the second TV works. Doesn't require multi-trigger testing (that's still Session 5+); just confirms the picker shows what RLS allows it to show.
- Skip flows requiring a second account (still gated on the Part E Flows 3+4 DEFERRED).
- **Files:** new `docs/SESSION-4.10.2-VERIFICATION.md`.

### Part G — PHASE1-NOTES + version bump (split into two commits)

**Commit G1 — `feat(4.10.2): <code work summary>`**
- Everything from Parts A–F.
- PHASE1-NOTES.md updates: catalog row for 4.10.2, architecture decision entries for "Phone-as-remote model" and "`launch_app` realtime event on existing `tv_device` channel".

**Commit G2 — `chore(4.10.2): bump version v3.0 → v3.1`**
- Version badge swap across every page that renders it: `index.html`, `tv2.html`, `karaoke/stage.html`, `karaoke/singer.html`, `karaoke/audience.html`, `games/tv.html`, `games/player.html`. Mechanical find-and-replace, no logic changes.

**Why the split:** when a regression surfaces weeks later, `git bisect` should land on the commit that introduced the bug — not on a "version bump + 50 file changes" mega-commit where the version badge swap obscures the real cause. G1 is the semantic change; G2 is the version marker. Bisecting past G2 lands cleanly on G1's scope. This is consistent with the existing repo pattern of version badges being a separate mechanical concern from feature work (see commits across Session 4.9 where version bumps landed after the feature work stabilized).

**Files:** PHASE1-NOTES.md (G1), all seven HTML files above (G2).

---

## Verification approach

Patterned on PART-E-VERIFICATION.md. Single file, executable checklist, run by Mike after each implementation session. Four headline flows as listed in Part F. Skip flows requiring a second account (still gated on Part E Flows 3+4 DEFERRED).

---

## Deferred items likely to emerge

Pre-log these so we catch them during planning review:

- **"Now playing" TV presence (TV publishing its current location back):** mentioned as stretch for Architecture Decision 3. If not shipped in 4.10.2, file as DEFERRED for Session 5 or later.
- **Launch-conflict UI (two phones launch simultaneously):** Architecture Decision 7 punts to Session 5. May surface earlier if testing shows confusion.
- **"You were removed from household" error UX:** Architecture Decision 6 punts to Session 4.11 admin UI work. Verify still deferred at 4.11 planning.

---

## Open questions for implementation

None — every design decision above is concrete. If new questions surface during Part-level execution, update this file rather than punting.

---

## Related existing architecture (to remain consistent with)

- **Two-device model for TV:** unchanged. tv2.html remains the TV entry point; phone remains the controller. 4.10.2 just makes the controller role explicit.
- **Session handoff via realtime channel** (4.10 Part C architecture decision): `launch_app` is the second event on this channel, reusing the same infrastructure.
- **Guest auth** (4.10 plan): this session doesn't touch the guest path. A guest on a TV won't see "Your TVs" because they don't have a `household_members` row. That's correct — deferred Part E Flow 3 path will cover it.
- **RLS read filter on `tv_devices`:** phone's "Your TVs" query leans on 4.10's existing "members read" policy. No new RLS.
