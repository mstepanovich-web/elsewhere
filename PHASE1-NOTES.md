# Phase 1 — User Management

Phase 1 adds authenticated user accounts, contacts, groups, and (in Session 5) a per-person invite flow on top of the existing Elsewhere browser party app. Schema lives in `db/001_user_management_schema.sql` (deployed to Supabase project `gbrnuxyzrlzbybvcvyzm`). Auth lives in `shell/auth.js` and exposes `window.sb` + `window.elsewhere.{getCurrentUser, signIn…, onAuthChange}`; `games/player.html` is an auth consumer, not an auth UI.

Companion context: `CLAUDE.md` (repo layout, conventions, Agora data-channel gotchas) and `ARCHIVE-NOTES.md` (Fashion product archived 2026-04-17 at v2.90).

## Session Catalog

| # | Status | Date | Version | Commit | Scope |
|---|--------|------|---------|--------|-------|
| 1 | ✅ | 2026-04-17 | v2.93 – v2.94 | `7877769`, `b491af8` | Pre-Phase-1 foundation: karaoke directory restructure, color audit for theme portability, shell refactor extracting auth + building Elsewhere launcher |
| 2 | ✅ | 2026-04-17 | — | `de7e43e` | User management schema migration — `profiles`, `contacts`, `groups`, `group_members`, `invites` tables, RLS, avatar storage bucket |
| 3 | ✅ | 2026-04-18 | v2.95 | `b267e41` | Contacts CRUD with avatar uploads via Supabase Storage |
| 4 | ✅ | 2026-04-18 | v2.96 | `a482edb` | Groups CRUD |
| 4.7 | ✅ | 2026-04-19 | v2.97 | `ee6b950` | Responsive layouts on `games/player.html` and `games/tv.html` (phone / tablet / TV breakpoints) |
| 4.8 | ✅ | 2026-04-19 | v2.98 | `e3aaa05` | TV display pairing — any player pairs a secondary device as a TV display, stable `player_id` for reconnect-safe ownership |
| 4.9 | ✅ | 2026-04-20 | v2.99 | `9296a50` | Karaoke venue polish + admin venue tuning — venues.json manifest (25 venues reachable); `profiles.is_platform_admin` (renamed from `is_admin` via db/004); db/005 splits venue tuning into front/back (global) + singer/audience (karaoke); view-aware resolver in `shell/venue-settings.js`; rewritten admin dialog reads `viewMode` to capture live camera state with "Also apply to Global Defaults" checkbox; gear icon relocated to top bar; temporary `?dev=1` email+password sign-in bridge for desktop admin access. Part D verified end-to-end (both views, both save paths). |
| 4.10 | 🔜 | upcoming | — | — | Laptop/TV production auth path for `karaoke/stage.html` — replace the temporary `?dev=1` email+password bridge with the tv2.html landing flow (QR-code-to-phone sign-in, shell passes authenticated session into stage). When landed, remove the dev block (grep `remove-in-4.10` in source). |
| 5 | 🔜 | upcoming | — | — | Invite flow: per-person tokens, `contact_id` linkage, display-name confirmation on join; replaces client-authoritative lobby state with `session_participants` on Supabase realtime |

## Architecture Decisions

Decisions locked by design conversation — reference these when future choices imply re-opening them.

### Two-device model for TV experience

- Device 1 (phone) runs `games/player.html` — user's private controller view
- Device 2 (iPad / laptop / second phone) runs `games/tv.html` — shared game state for display
- Getting Device 2 onto the physical TV is the user's job via OS-level casting (AirPlay, Chromecast, Miracast, HDMI cable)
- Elsewhere does NOT build casting infrastructure in Phase 1
- `tv.html` is designed to look great when cast: full-viewport, wake-lock, fullscreen-on-tap, PWA-ready
- First-time help overlay on `tv.html` shows casting instructions per device type
- Phase 2+: native tvOS / Roku / Fire TV apps could enable a direct "Send to TV" button (not Phase 1)

### Roles determined by URL, not device size

- `games/player.html` → player role, regardless of device size
- `games/tv.html` → TV display role, regardless of device size
- No auto-detection or auto-redirect based on screen size
- Soft help message if user seems to have opened the "wrong" URL
- Rationale: an iPad can be a player OR a TV. Screen size is a property of the device; role is a property of intent. The URL is the contract.

### TV displays as session participant attachments

- Each session participant can pair 0-N TV displays to their slot
- TV devices are Agora subscriber-only — receive video, don't publish
- TV displays are INVISIBLE in the participant / lobby list (no "Mike (TV)" showing up as a separate player)
- TV displays ARE visible in a dedicated "TV Displays" section shown to all participants
- Any participant adds their own TV displays — no host permission needed
- TV display pairing is a separate in-session mechanism, NOT part of the invite flow
- Rationale: invites are for PEOPLE. TV displays are personal device-setup decisions.

### Invite architecture: per-person tokens, identity-preserving

- Each invite generates a unique token stored in the `invites` table
- Token links `contact_id → session_id → status`
- Link format: `elsewhere.my/i/TOKEN` (short URL with a tiny redirect handler)
- Token validation via Supabase RPC (Phase 1) — not raw table access
- Tokens are multi-use per contact (Sarah can tap her link, disconnect, tap again — still Sarah)
- Tokens expire after 7 days by default
- Mike can revoke pending (unused) invites; revoking active participants is Phase 2 moderation
- Rationale: identity linkage (knowing a joiner is Mike's contact "Sarah") prevents the games-lobby-bug class where names diverge unpredictably

### Display name vs. contact name: separate concerns

- `contacts.full_name` = Mike's private label for a contact ("Mom", "Dr. Smith")
- Session participant `display_name` = what appears publicly in the game / karaoke session
- On join, `display_name` is PRE-FILLED from `contact.full_name`, but the user can edit it before confirming
- Editing `display_name` updates ONLY the current session's participant record — does NOT alter Mike's contacts
- One identity per participant per session, used consistently across lobby, chat, scoreboard, video tiles
- Rationale: Mike's contacts are HIS organization. The invitee's display name is THEIRS. Keeping them separate prevents overwrites and the "why did my contact name change" confusion.

### Guest auth: allow guest join, prompt account creation post-session

- Invitee tapping link doesn't need an existing Elsewhere account
- Tap → display-name confirmation → join as guest
- Guest participation is recorded with `contact_id` (who invited them) and `display_name` (what they called themselves)
- Post-session: optional prompt "Want to save your progress? Create an account"
- Never BLOCK play on account creation
- Rationale: friction at the point of "tap and play" kills adoption. Account creation comes after value is demonstrated.

### Phase 1 invite distribution: manual send, per-person links

- Mike picks contacts / groups → system generates N tokens → UI shows N links
- Mike manually sends each link via iMessage / Mail / etc.
- Tedious for real users; fine for Phase 1 testing (Mike is the main user)
- Token model UNCHANGED between Phase 1 and Phase 2 — only the distribution mechanism changes
- Rationale: get the core architecture right Phase 1, add polished distribution Phase 2 when there are real users

### Session 5 scope (Phase 1)

Built in Session 5:
- `invites` table (already in the Session 2 migration)
- Pick contacts / groups to invite → generate N tokens → display links
- Short URL + redirect handler (`elsewhere.my/i/TOKEN`)
- Supabase RPC for secure token validation
- Join flow: token validate → pre-fill display name → confirm → enter room
- Revoke pending invites
- Invite history view (Mike sees who he invited + status)
- Replaces the current client-authoritative `lobbyPlayers[]` / `tv_displays` pattern with `session_participants` + `session_tv_displays` rows on Supabase realtime — structurally fixes the broadcast-ephemerality fragility documented under "Deferred — Games"

### Venue property override pattern

Two-level settings system: global venue defaults + per-app overrides. Each property can be independently overridden by each app; NULL override means inherit from global. Resolution via shared `resolveVenueYawPitch()` helper in `shell/venue-settings.js`. Generalizes to all venue properties — Phase 1 today implements yaw/pitch for two views (front/back on global, singer/audience on karaoke-specific); schema accommodates future additions via added columns.

Global defaults live in `venue_defaults` table with `front_yaw` / `front_pitch` (audience view) and `back_yaw` / `back_pitch` (singer view). Karaoke-specific overrides live in `karaoke_venue_settings` with `singer_yaw_override` / `singer_pitch_override` and `audience_yaw_override` / `audience_pitch_override`. Post-refactor (when venues become Elsewhere-level shared entities), `venue_defaults` becomes the canonical `venues` table, and per-app tables follow the same pattern (`wellness_venue_settings`, etc.).

Admin gating: `profiles.is_platform_admin` column controls write access. Read is public. Admin gear icon on `karaoke/stage.html` (only visible when `is_platform_admin = true`).

### Three-app runtime split (karaoke)

Karaoke's three apps have distinct runtime targets:

- `stage.html` — TV/desktop browser only. Never runs in the iOS Capacitor wrapper. Admin UI (venue tuning) lives here.
- `singer.html` — Wrapper-aware: runs inside the iOS Capacitor wrapper as the primary path, falls back to iPhone Safari when the wrapper isn't present. Follows the games manager/player pattern.
- `audience.html` — Same pattern as `singer.html`. Wrapper-aware with browser fallback.

Consequence for auth: the wrapper owns the `elsewhere://` URL scheme and handles magic-link callbacks. Because `stage.html` never loads in the wrapper, it has no production path to complete a magic-link sign-in on laptop/TV browsers. v2.99 ships with a temporary `?dev=1` sign-in affordance that uses Supabase email+password directly, bypassing the magic-link flow. This is a bridge until the tv2.html landing flow lands in a future session (Session 4.10), at which point `stage.html` will receive an already-authenticated session from the Elsewhere shell (similar to how `games/player.html` receives context from its shell launcher).

## Pre-Session 5 Blockers

Must-fix before the invite flow ships.

### Capacitor deep-link auto-checks manager checkbox

- Current: `games/player.html` deep-link handler sets `mgrCheck.checked = true` on every `elsewhere://games?…` arrival
- Impact: every iOS-app user opening an invite deep link becomes a manager of the room they join, creating duplicate managers — breaks the single-manager assumption throughout the games code
- Fix options: (a) gate on a `?role=manager` deep-link param (set only by the inviter's "share to my own device" flow, not by invitee links), or (b) remove the auto-check entirely and trust the URL `?mgr=1` param exclusively

### Lobby state fragility

Will be resolved structurally by Session 5's `session_participants` + Supabase realtime migration. See **Deferred — Games → Games lobby state fragility** for full diagnosis. Listed here because Session 5's design explicitly depends on this fix landing as part of the invite-flow work; they ship together.

## Deferred — Games

Known bugs + UX gaps accepted for Phase 1. Session 5 structurally addresses the lobby fragility; other items are separate polish.

### Games lobby state fragility (fixed structurally in Session 5)

- Current: `lobbyPlayers[]` is client-authoritative, propagated by `player-join` / `player-join-ack` / `tv-display-added` broadcasts over the Agora data stream
- **Diagnosed root cause (2026-04-19, during Session 4.7):** Agora data-stream messages are ephemeral — dropped, not buffered, across `CONNECTED → RECONNECTING → CONNECTED` transitions. iOS backgrounds the WebView tab aggressively, so the iPhone Agora client reconnects multiple times per session. Any broadcast landing during a reconnect window is lost forever on that device.
- Symptom observed: Mike (manager) on iPhone saw only himself in the lobby despite Jeff + Steve joining from stable browsers. Also observed on `tv2.html` "IN THE LOBBY" staying empty — same root cause.
- **Original hypothesis was wrong** — first suspected silent throws in `renderRoster` / `renderInvited` inside the message handler. Safari Web Inspector showed no such errors; instead, multiple `CONNECTED → RECONNECTING` state changes correlated with the missing broadcasts.
- **No tactical patch pursued.** try/catch wrappers wouldn't help — the messages never arrive in the first place. A resend-on-reconnect heartbeat would paper over this but is the wrong shape of fix given Session 5's design.
- **Structural fix (Session 5):** replace `lobbyPlayers[]` + `tvDisplays[]` broadcast propagation with `session_participants` + `session_tv_displays` rows in Supabase + Postgres realtime subscriptions. Supabase realtime handles reconnect buffering correctly (DB is source of truth; clients replay state on reconnect). `player-join` / `tv-display-added` broadcasts become redundant once the DB is authoritative — broadcast sites in `games/player.html` + `games/tv.html` are already annotated with "will move to Supabase realtime in Session 5".
- **Testing workaround until Session 5:** iPhone is unreliable as a multi-player test client for lobby flows. Use stable browsers (laptop Chrome/Safari, iPad Safari) for any repro involving multiple joiners. iPhone remains fine for solo CSS / single-device testing.

### Last Card end-game state leakage

- Symptom (reported 2026-04-19 during Session 4.7 smoke testing): when a Last Card round ends and the manager starts a new game with the same players, the new deal distributes fresh cards BUT players also retain cards from the previous game
- Root cause: "End Game" isn't clearing player hands before the next deal — likely in the end-game → start-game state transition in `games/player.html` (the state reset is incomplete)
- Impact: players start subsequent rounds with oversized hands, breaking the win condition and the 7-card-deal invariant

### Direct-launch Games UX

- Cold iOS-app launch → user taps Games tile without having scanned a TV QR → `games/player.html` shows an empty room-code screen with no explanation
- Acceptable for Phase 1. Session 5's invite flow (tokens, share links, contact-based invites) becomes the primary path to a game session; manual room-code entry stays as an explicit fallback
- Optional polish: a brief "Need a room? Open `tv2.html` on your TV" hint on the join screen when arriving from the shell vs. from a QR

### Player tile avatar unification (folds into Session 5)

- Contacts screen uses circular avatars with two-letter initials + one of 7 deterministic palette colors (`--color-avatar-1..7`), optionally with photo
- `games/tv.html` currently uses rectangular dark tiles with monospace initials — different visual language
- Unification requires `contact_id` linkage on participants (Session 5 provides this)
- Session 5 should reuse the Contacts avatar component for player tiles
- Guest joins (no `contact_id`) fall back to initials-only; palette color hashed from `display_name`
- Also applies to `karaoke/stage.html` participant list in Phase 2

### Minor games issues observed during v2.93.2 testing

- Details TBD, to be reported when revisiting

## Deferred — Karaoke

Karaoke is post-archive (Fashion product archived 2026-04-17 at v2.90). Phase 1 does not touch karaoke functionality; these are pre-existing polish items.

- Minor karaoke issues observed during v2.93.2 testing — venue transitions / UI / stream quality, details TBD
- DeepAR `background_segmentation` jsdelivr 404 — `karaoke/stage.html` falls back to MediaPipe, low priority
- ~143 text-tone hardcoded colors deferred from Session 1 color audit (`rgba(255,220,150,*)` and `rgba(255,200,120,*)` across `karaoke/*.html`) — rebrand-safe enough for now
- Extract ambient venue effects (Type 1: speakeasy dust, stadium lasers, forest sway, etc.) from `karaoke/stage.html` into `shell/venue-effects.js` when wellness product work begins
- ~~Create `venues.json` metadata file with product tags when wellness needs it~~ — shipped in Session 4.9 Part A (karaoke use case; wellness can extend the manifest when needed)
- Move karaoke performance effects (Type 2: DeepAR face filters, confetti, crowd reactions) formally under `karaoke/effects/` — physically there already but could be better organized
- Laptop/TV production auth path for `karaoke/stage.html` (Session 4.10+). Shipped v2.99 uses a temporary `?dev=1` email+password affordance. Long-term fix is the tv2.html landing flow with shell-passes-session-to-stage pattern (matching games manager/player). When that lands, remove the dev block (grep `remove-in-4.10` in `karaoke/stage.html`).
- Tune `back_yaw` / `back_pitch` for remaining venues via the admin dialog. Most venues have NULL back values today; resolver falls back to `venues.json.startYaw` (no `back_pitch` fallback — uses 0).
- Bug: `karaoke/stage.html` line ~3085 has `if(viewMode==='singer')` — a dead branch (actual value is `'panorama'`). Cleanup candidate, no functional impact today.

## Deferred — UX Refinements

Cross-product polish. Small, cosmetic, non-blocking. Fold into Session 5 work or a dedicated polish pass.

### Relocate "Add TV display" to top nav

- Current: "📺 Add TV display" button lives in the lobby only (pre-game inside `#screen-game-room`). A separate "TV ON / NO TV" mode toggle appears during active games (`#lc-mode-toggle` inside `#screen-lastcard`).
- Change: move "Add TV display" to the top nav of `games/player.html` so every player can access it at all times — lobby AND active games. Remove the "TV ON / NO TV" mode toggle entirely.
- Rationale: TV pairing shouldn't be lobby-only. The current mode toggle is redundant once pairing is always reachable, and clutters in-game real estate. Applies across all game screens (lobby, active Last Card, Trivia, Euchre).

### "Add TV display" modal: require explicit close

- Current: `maybeCloseAddTvModal(e)` dismisses the modal on any click targeting the overlay backdrop
- Change: the modal should only close via the explicit Close button. Remove backdrop-click dismissal.
- Rationale: Mike accidentally dismissed the modal while reaching toward the QR / URL field. The cost of an accidental dismiss (re-open, re-share) is higher than the cost of one explicit tap to close.

### Copy buttons: in-button "✓ COPIED" state

- Current: Copy triggers `navigator.clipboard.writeText(...)` then shows a toast / separate text line below the button. Easy to miss; users re-tap because they didn't see feedback.
- Change: on Copy tap, swap the button label to "✓ COPIED" for ~2s, then revert. Apply to every copy button — Add-TV-display modal URL, any other existing copy affordances, and any future ones. Write once as a reusable helper.
- Rationale: in-button state change is the clearest possible confirmation. Toast / sibling-text feedback is too easy to overlook.

### De-emphasize room codes in UI

- Pending after shell work: primary flow becomes QR / invite; manual room-code entry becomes a hidden fallback

### Searchable contact list component

- As contact lists grow (realistic target 50-200 per user), need search / autocomplete on first and last name
- Build as a reusable component used by: Contacts screen, Group member selector (`screen-group-edit`), and Session 5's invite-flow contact picker
- Search matches any word in `full_name` with prefix match, case-insensitive. Consider debounce (~200ms).
- Likely folded into Session 5, since the invite picker needs it anyway

### Profile photo capture mode

- When building self-profile-photo upload, set `capture="user"` on the file input for front-facing default camera (selfie mode)
- Contact photos keep the current rear-facing default (`capture="environment"` or unspecified)

## Phase 2 Deferred

Explicitly NOT in Phase 1 scope. Scheduled work, not permanent limitations.

### Auth / sign-in

- **Magic-link desktop sign-in path** — today every `signInWithOtp` passes `emailRedirectTo: 'elsewhere://auth/callback'`, a scheme only registered in the iOS app's `Info.plist`. Desktop users clicking a magic link hit an "`elsewhere://auth/callback` can't be opened" error — this affects real users who try to sign in from a laptop. If ever needed, likely implemented via a `redirect_to=https://<site>/auth/callback` → app-link fallback. Today the desktop sign-in screen shows a small "Sign-in requires the Elsewhere app" note as mitigation.
- Profile-edit UI — today `profiles.full_name` is write-once at signup via `raw_user_meta_data`. No UI to change it. Lower priority than the desktop sign-in path.

### Invite flow — Phase 2 extensions

- **Supabase Edge Function for token resolution** — needed only if Phase 2 adds a web-browser invite-link handler for non-iOS users (an unauthenticated invitee clicking a `?token=…` link from a desktop). Phase 1 Session 5 uses a Supabase RPC instead; authenticated iOS-app calls bypass RLS via the RPC's `SECURITY DEFINER`, so an Edge Function isn't required.
- Server-sent invites — Resend (email) + Twilio (optional SMS) infrastructure. Supabase Edge Function iterates invites, sends via provider APIs. Requires: Resend account, DNS configuration for `elsewhere.my` (SPF / DKIM / DMARC), Twilio account if SMS. Mike taps "Send invites" → server fan-out, one action → N channels.
- Real-time invite delivery / open tracking
- Account creation prompts post-session (optional, never blocks play)
- Auto-kick active participants (moderation — revoking an *active* participant mid-session; Phase 1 revoke only covers pending/unused invites)

### TV / device rendering

- Avatar @1024 variant for TV-scale rendering — Phase 1 uploads single 512×512 avatars sized for phone use. When Phase 2 adds avatars to TV experiences (game lobbies, karaoke stage participant list), evaluate whether to add a larger variant (1024×1024). If needed, path convention `{userId}/{contactId}@1024.jpg` alongside existing 512; display code picks variant by device; migration is regenerate from source or ask users to re-upload for key contacts.
- Native tvOS / Roku / Fire TV apps — would enable direct "Send to TV" pairing without OS-level casting

### Contacts + Groups polish

Core CRUD shipped in Sessions 3-4. Phase 2 polish candidates:
- Bulk actions (multi-select contacts / groups, batch delete, batch group-add)
- Advanced contact search filters beyond name prefix (by group membership, tags, last-invited, etc.)
- Contact import (vCard, Google Contacts) — needs OAuth
- Group sharing (invite someone else to co-own a group)

## How to use this document

Future Claude Code sessions: read this file + `CLAUDE.md` before starting new work. Reference sections by name ("check Pre-Session 5 Blockers", "update Deferred — Games").

When Mike says "make a note for later," "add to notes," "defer this," or equivalent, write it to this file under the appropriate section. Never leave deferred items only in chat responses or session task lists.

When closing a session: update the Session Catalog with the new entry (# / status / date / version / commit / scope), and move any "to-do during session" items out of Pre-Session 5 Blockers if they got fixed.
