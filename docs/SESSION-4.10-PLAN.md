# SESSION 4.10 PLAN — Household + TV Device Registration

**Status:** Design complete, implementation not started
**Drafted:** 2026-04-21
**Depends on:** v2.99 shipped (Session 4.9)
**Unblocks:** Session 4.11 (household admin controls), Session 5 (session + invite flow)

---

## Scope

Build the foundational **household and TV device model** for Elsewhere. This replaces the temporary `?dev=1` email+password bridge on `karaoke/stage.html` with a proper production auth flow.

In scope:

- New schema: `households`, `tv_devices`, `household_members`, `pending_household_invites`
- `tv2.html` as the canonical TV landing page with first-time setup and returning sign-in flows
- `claim.html` intermediate landing page — QR targets this, it auto-attempts `elsewhere://` deep link, falls back to branded "Get the app" screen with App Store link if deep link doesn't fire within ~1.5s
- Phone-side claim UI in the iOS shell (`index.html`) for registering a TV, joining a household, or linking an additional TV to an existing household
- Minimal pre-invite UI in shell (single "Invite by email" field, no management screen — full admin UI is 4.11)
- Session handoff from authenticated phone → TV browser (so `stage.html`, `games/tv.html`, `wellness/*.html` all inherit an authenticated session when launched from a claimed TV)
- Guest access path (scan TV QR → launch app as guest, admin notification deferred to 4.11)
- Remove the `?dev=1` dev bridge (grep `remove-in-4.10`)

Explicitly out of scope (deferred to later sessions):

- Admin controls for managing household members (child/adult flags, designating co-admins, removing members) → **Session 4.11**
- Session model + invite flow for non-household participants to join a game or karaoke session (`session_participants`, invites, display-name persistence) → **Session 5**
- Cross-household session sharing (two households on one karaoke stage) → post-Phase-1
- Lazy camera init cleanup on `tv2.html` → already tracked in Deferred, included here only incidentally

### Household membership vs. session participation — not the same thing

This plan deals only with **household membership**: the persistent relationship between a user and a physical household/TV ("Jane is a member of the Stepanovich household"). Household membership answers "when Jane walks up to this TV and scans, should she be recognized as belonging here?"

**Session participation** is different and stays in Session 5: the per-session, per-invite relationship between a user and a specific game or karaoke session ("Jane was invited by Mike to Saturday night's karaoke session"). A remote friend invited to a session on their own phone is a session participant but never a household member — they never scan the host's TV.

These are orthogonal. A user can be:
- A household member only (walks up to their household TV, launches apps)
- A session participant only (remote friend invited to a game, joins on their phone)
- Both (invited to a session hosted at a household they're already a member of)
- Neither (a guest who scans a TV without an invite — see Flow 3)

4.10 builds the household-membership layer. Session 5 layers session-participation on top without disturbing it. This plan is deliberately scoped to not paint Session 5 into a corner: `household_members` is never used to gate session participation, and `session_participants` (when it arrives) won't need a household-membership check.

---

## Roles (product-level, codified here)

Four distinct roles, each resolved at a specific layer:

| Role | Resolved by | Granted via |
|---|---|---|
| **Platform admin** | `profiles.is_platform_admin = true` | Manual DB flag (Anthropic-style) |
| **Household admin** | `household_members.role = 'admin'` | First user to register a TV to a household; can be designated by existing admin |
| **Household user** | `household_members.role = 'user'` | Pre-invited by admin + email match, OR approved by admin after scan |
| **Guest** | No `household_members` row for this (user, household) pair | Default state when scanning a TV without an invite |

Platform admin ⊂ anyone. Household admin ⊂ household user ⊂ guest when ambient permissions are checked. A single user can be a household admin of household A and a guest at household B simultaneously.

---

## Data model

### New tables

```sql
-- Households — one per physical home/venue
create table households (
  id              uuid primary key default gen_random_uuid(),
  name            text,                      -- user-assigned, e.g. "The Stepanovich House"
  created_at      timestamptz not null default now(),
  created_by      uuid not null references auth.users(id)
);

-- TV devices — first-class entities so we can reason about them
-- (rename, list, see last-seen, etc.). Multi-TV-per-household supported.
create table tv_devices (
  id                    uuid primary key default gen_random_uuid(),
  household_id          uuid not null references households(id) on delete cascade,
  device_key            text not null unique,   -- localStorage-stored UUID on the TV browser
  display_name          text,                   -- e.g. "Living Room TV"
  registered_at         timestamptz not null default now(),
  registered_by         uuid not null references auth.users(id),
  last_seen_at          timestamptz not null default now()
);

create index tv_devices_household_idx on tv_devices(household_id);

-- Household membership — user belongs to household with a role
create table household_members (
  household_id    uuid not null references households(id) on delete cascade,
  user_id         uuid not null references auth.users(id) on delete cascade,
  role            text not null check (role in ('admin', 'user')),
  joined_at       timestamptz not null default now(),
  joined_via      text not null check (joined_via in ('founder', 'pre_invite', 'scan_approved')),
  primary key (household_id, user_id)
);

create index household_members_user_idx on household_members(user_id);

-- Pre-invites — admin can pre-load members by email/phone
-- When a matching user signs up + scans, they're auto-admitted
create table pending_household_invites (
  id              uuid primary key default gen_random_uuid(),
  household_id    uuid not null references households(id) on delete cascade,
  email           citext,                 -- one of email/phone required
  phone           text,
  invited_by      uuid not null references auth.users(id),
  invited_at      timestamptz not null default now(),
  consumed_at     timestamptz,            -- set when the user actually joins
  consumed_by     uuid references auth.users(id),
  check (email is not null or phone is not null)
);

create unique index pending_invites_email_per_household
  on pending_household_invites(household_id, lower(email))
  where email is not null and consumed_at is null;

create unique index pending_invites_phone_per_household
  on pending_household_invites(household_id, phone)
  where phone is not null and consumed_at is null;
```

### RLS policies (sketch)

- `households`: read by household members; write by household admins only; insert by any authed user (founder case).
- `tv_devices`: read by household members; write by household admins only.
- `household_members`: read by household members (they see each other); write by household admins (add/remove/change role); self-insert allowed via RPC for pre-invite-match and scan-approved cases.
- `pending_household_invites`: read+write by household admins only (plus RPC-level match check).

Full policy text written during implementation.

### RPCs

Logic that shouldn't live in RLS:

- `rpc_claim_tv_device(device_key text, household_name text default null) → tv_device` — first-time TV registration. Creates household if admin doesn't have one, creates `tv_devices` row, writes `household_members` row with role 'admin' and joined_via 'founder'.
- `rpc_link_tv_to_existing_household(device_key text, household_id uuid) → tv_device` — admin adding a second TV to their existing household.
- `rpc_request_household_access(device_key text) → {status, household_id}` — called by scanning user; returns `'auto_admitted'` (email match), `'pending_approval'` (admin will be notified), or `'guest'` (user chose not to join).
- `rpc_approve_household_member(user_id uuid) → household_members` — admin approves a pending scan.
- `rpc_designate_admin(user_id uuid) → household_members` — admin promotes a user to co-admin.

---

## Flow design

### Flow 1 — First-time TV setup (new household)

```
1. TV opens tv2.html for the first time.
   - Page generates a device_key UUID, stores it in localStorage under 'elsewhere.tv.device_key'.
   - Queries Supabase: is this device_key in tv_devices? No → unregistered state.
   - Displays: large QR code encoding elsewhere://tv-claim?device_key=<UUID>, 
     plus a short 6-char backup code (derived from device_key) in smaller text.
   - Message: "Scan with your iPhone to set up this TV."

2. User scans QR with iPhone camera.
   - elsewhere:// scheme opens the iOS shell.
   - Shell routes to a new /tv-claim?device_key=<UUID> view.
   - If user isn't signed in yet → sign-in flow first (existing magic link), then 
     redirect back to /tv-claim with the device_key preserved.
   - If signed in → proceeds directly.

3. Shell shows claim UI:
   - "You're setting up a new TV. What should we call it?" [text field, optional]
   - "This TV will be added to:" [household picker, if user has existing households]
     | or "A new household for you" if they don't
   - Button: "Claim TV"

4. User taps Claim.
   - Shell calls rpc_claim_tv_device(device_key, household_name) 
     OR rpc_link_tv_to_existing_household(device_key, household_id).
   - Supabase returns tv_device row.

5. TV tv2.html polls Supabase for its device_key every ~2s.
   - When the row appears → TV knows it's been claimed.
   - TV then needs to obtain an authenticated session. See "Session handoff" below.

6. Shell shows success: "✓ TV claimed. Head to your TV to continue."
   TV shows the apps tile grid.
```

### Flow 2 — Returning TV sign-in (existing device_key)

```
1. TV opens tv2.html.
   - device_key already in localStorage.
   - Queries tv_devices, finds row → knows it's registered.
   - Updates last_seen_at.
   - But: tv2.html has no Supabase session yet (browser refresh cleared it, 
     or this is a fresh browser).
   - Shows QR: elsewhere://tv-signin?device_key=<UUID>
   - Message: "Scan to sign in." 
   - Plus small text: "Household: [Living Room Setup] · Not your TV? Reset"

2. User scans QR.
   - Shell routes to /tv-signin?device_key=<UUID>.
   - If user isn't signed in → sign-in flow, then back to tv-signin.
   - If signed in → checks: is user a household_member of this TV's household?
     - Yes (admin or user) → session handoff (see below). TV proceeds.
     - No (pending_invite match) → auto-admit via rpc_request_household_access, 
       session handoff.
     - No (not pre-invited) → "You're not a member of this household. 
       Options: [Request to join] [Continue as guest]"

3. Admin gets push/in-app notification for scan-approval or access requests 
   (notification delivery deferred to 4.11; for 4.10 just an in-app indicator 
   on the shell when admin next opens it).
```

### Flow 3 — Guest access

```
1. Guest scans TV QR, opens shell, signs in (if not already).
2. Shell calls rpc_request_household_access(device_key).
3. RPC returns status='guest' if no pre-invite match.
4. Shell shows: "You're signed in as a guest. You can launch apps on this TV."
5. Session handoff happens the same way — just without household membership.
6. Admin is notified of guest presence (same mechanism as scan approval).
```

### Flow 4 — Pre-invited member

```
1. Household admin, in shell: "Manage household" → "Invite members" → enters 
   email or phone. Creates pending_household_invites row.
2. Admin texts/emails the invitee a generic "Install Elsewhere" link (manual 
   for 4.10, automated in later session — consistent with existing Phase 1 
   invite distribution decision).
3. Invitee downloads app, signs up with the pre-loaded email.
4. Invitee visits household TV, scans QR.
5. Shell calls rpc_request_household_access(device_key).
6. RPC finds pending_household_invites row matching (user's email, TV's 
   household_id), creates household_members row with joined_via='pre_invite', 
   marks invite as consumed.
7. Status='auto_admitted', session handoff proceeds.
```

### Session handoff — the technical core

**The problem in plain terms:** After a user signs in on their phone and claims a TV, the TV browser still has no Supabase session of its own. The phone knows who the user is; the TV doesn't. We need a way for the phone to tell the TV "act authenticated as this user" so that when the user taps into an app (stage.html, games/tv.html, etc.) the TV is already signed in.

**Considered approaches:**

- **Credentials in URL redirect.** Phone communicates session back to TV via URL params. Simple but "credentials in a URL" is a known attack vector — URLs get logged, cached, screenshotted.
- **Pairing token via new DB table.** Phone mints a short-lived one-time code, stores it in a `pairing_tokens` table. TV polls and exchanges the code for a session. Secure but adds a new table, new RPC, expiry/cleanup logic, and polling overhead.
- **Supabase realtime channel.** Phone publishes session credentials to a private channel scoped to the TV's unique device_key. TV subscribes to that channel and receives them.

**Chosen: Supabase realtime channel, scoped by `tv_device:<device_key>`.**

Rationale:
- Supabase realtime is already a dependency — no new infrastructure
- No new tables, no polling, no cleanup jobs
- Channel name is the TV's UUID device_key; only someone holding the TV's QR code knows it
- Messages are transient; tokens don't persist anywhere
- Supabase realtime is TLS-encrypted end-to-end
- ~20 lines on the TV side, ~10 on the phone side

**Tradeoff being accepted:** The phone sends real session tokens on the wire. If an attacker could intercept Supabase realtime messages, they'd get replayable tokens until the refresh rotates. In practice this requires already having compromised either the phone or the TV (the channel name is not guessable — it's a v4 UUID), at which point the session is lost anyway. For Phase 1 stage admin tooling this is acceptable.

**Phase 2 upgrade path if the threat model tightens:** Replace direct token transfer with a mint-once pairing token exchanged via RPC (option 2 above). Not worth the complexity for Phase 1.

Mechanism:

```
1. tv2.html subscribes to channel 'tv_device:<device_key>' on load.
   Listens for message type 'session_handoff' with payload {access_token, refresh_token}.

2. Phone, after a successful claim/sign-in for a given device_key, calls 
   supabase.auth.getSession() to retrieve its tokens, then publishes them 
   to the channel.

3. tv2.html receives tokens, calls supabase.auth.setSession({access_token, 
   refresh_token}), now has a real authenticated session in localStorage.

4. tv2.html transitions from "show QR" state to "show apps tile grid".

5. User taps an app tile → stage.html / games/tv.html / etc. loads from the 
   same origin, inherits the localStorage session automatically. No more 
   ?dev=1 dance.
```

### "Not your TV? Reset" flow

- Tapping "Reset" wipes `elsewhere.tv.device_key` from localStorage.
- On refresh, tv2.html treats it as a new unclaimed TV.
- The old `tv_devices` row remains in DB — orphaned, not reclaimable by same device_key (new UUID will be generated).
- Admin can delete the old row from a "Manage household" UI (4.11).

---

## iOS shell additions

New shell routes (via URL params or hash fragments, consistent with existing shell pattern):

- `/tv-claim?device_key=X` — first-time TV registration
- `/tv-signin?device_key=X` — returning sign-in
- (Later) `/household` — household management (deferred to 4.11)

The iOS camera QR scan flow triggers `elsewhere://tv-claim` or `elsewhere://tv-signin` via the deep-link manager — reuses existing Capacitor deep-link infrastructure. Note the existing pre-Session-5 blocker: Capacitor deep-link manager auto-check. Should verify this is resolved before 4.10 implementation.

---

## Verification checklist

End-to-end tests to pass before shipping:

1. **Fresh TV setup:** new browser, open tv2.html, QR appears, scan on authed phone, claim → tv2.html transitions to apps grid. ✓
2. **Returning sign-in:** same TV, refresh page, QR appears, scan on same phone, recognized as household admin, apps grid loads. ✓
3. **New user joins household (pre-invite):** admin pre-invites user B, user B signs up with matching email, scans TV, auto-admitted. ✓
4. **New user joins household (scan approval):** user C scans TV, admin gets notified, admin approves in shell, user C now a member. ✓
5. **Guest access:** user D scans TV, chooses "continue as guest", gets session for this TV, can launch apps. ✓
6. **Second TV, same household:** admin opens tv2.html on second browser, scans, picks "add to existing household", TV registers. ✓
7. **App launches work authenticated:** karaoke/stage.html, games/tv.html both load without `?dev=1` and see correct user. ✓
8. **Admin venue tuning verified under production auth:** reach stage.html from the post-handoff flow, gear icon appears, Set View Coordinates works. Session 4.9 Part D verified under real auth. ✓
9. **?dev=1 block removed:** grep `remove-in-4.10` returns no hits. ✓

---

## Parts breakdown (for implementation session)

Rough ordering. Approve/refine before Claude Code starts.

- **Part A** — Schema migration (`db/006_household_and_tv_devices.sql`). Create tables, RLS, RPCs. Apply and verify in Supabase SQL editor.
- **Part B** — Shell side: new routes `/tv-claim` and `/tv-signin`. Claim UI. Call RPCs. Publish session handoff to realtime channel.
- **Part C** — tv2.html rewrite: generate/restore device_key, unclaimed vs returning state, QR rendering, realtime channel subscription, setSession on handoff, transition to apps grid.
- **Part D** — Remove `?dev=1` block from stage.html. Remove dev-only code paths.
- **Part E** — Re-verify Session 4.9 Part D end-to-end under production auth.
- **Part F** — PHASE1-NOTES updates (Session 4.10 catalog row, new architecture decisions: "Household + TV device model", "Session handoff via realtime channel").
- **Part G** — Version bump v2.99 → v3.0, sync, commit, push.

Time estimate: genuinely unknown, probably 2-4 focused sessions. Part A and Part C each look like real session-sized pieces on their own.

---

## Open questions for implementation

These didn't need answers for the plan but will need decisions during Part-level execution:

- Does the iOS camera's QR scanner already exist in the shell, or does it need adding? (If missing, that's a scope addition.)
- Where does the "Manage household" surface live in the shell UI? (4.11 territory but informs Part B routing.)
- What's the backup-code length? (6 chars ≈ 36^6 ≈ 2.2B permutations — probably fine. Deferred to implementation.)
- Should the `tv_devices.display_name` default to something sensible ("Living Room TV") or stay NULL? (Implementation detail.)
- Realtime channel: does the TV re-subscribe on reconnect automatically, or does it need manual reconnection logic? (Supabase client handles this but worth verifying.)

---

## Related existing architecture (to remain consistent with)

From PHASE1-NOTES.md, existing decisions this plan honors:

- **Two-device model for TV** — tv2.html is the new Device 2 entry point; nothing about the two-device pattern changes.
- **Roles determined by URL** — tv2.html is the URL for "this device is a shared household TV"; consistent pattern.
- **Invite architecture** — household membership is persistent cross-session; per-session invites (Session 5) layer on top, not replaced by this.
- **Guest auth** — guests scanning a TV still get frictionless app launch; household membership is an additional affordance, not required.

This plan does NOT contradict any locked architecture decision.
