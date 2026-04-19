# Phase 1 — User Management

Schema lives in `db/001_user_management_schema.sql` (deployed to Supabase project `gbrnuxyzrlzbybvcvyzm`). Auth integration lives in `games/player.html` — Supabase client exposed as `window.sb`, magic-link flow wired through the `screen-account` screen and the Capacitor `appUrlOpen` handler.

## Known limitations

### 1. Magic-link sign-in requires the iOS app

Every `signInWithOtp` call passes `emailRedirectTo: 'elsewhere://auth/callback'` so the email contains the custom-scheme redirect. That scheme is registered only in the iOS app's `Info.plist` — desktop browsers have no way to resolve it, so a desktop user who clicks a magic link will see their browser fail with an "`elsewhere://auth/callback` can't be opened" error.

Accepted for v1. Signup is framed as an app experience in Phase 1; adding web-side handling would mean either maintaining a second redirect path or making the web app a full sign-in client, both out of scope.

The sign-in screen in the browser shows a small "Sign-in requires the Elsewhere app" note but does not block the flow — if the user somehow completes sign-in anyway (e.g. a future web client), the `onAuthStateChange` listener picks it up and everything keeps working.

### 2. Invite token resolution for unauthenticated invitees needs a Supabase Edge Function

The `invites` table has full per-owner RLS but intentionally no public-read policy. That means an unauthenticated invitee clicking a `?token=…` link can't query the row directly — they'd get an RLS denial.

Deferred to Phase 2. The plan is a Supabase Edge Function that accepts a token, validates `used_at IS NULL AND expires_at > now()`, and returns a minimal view (room code, session type, expires_at) without exposing `account_id` / `contact_id` / other fields. Until that function exists, the invite-landing flow has to go through an authenticated context.

## Phase 2 placeholders

- Edge Function for token resolution (see #2 above).
- Profile-edit UI (update `profiles.full_name`; today the name is write-once at signup via `raw_user_meta_data`).
- Contacts / groups management UI (schema is live, no screens yet).
- Desktop sign-in path — if ever needed, likely via a `redirect_to=https://<site>/auth/callback` → app-link fallback.

## Deferred — post-v2.93 testing observations

- [ ] Karaoke: small issues observed during v2.93.2 testing (venue transitions / UI / stream quality — details TBD, to be reported when revisiting)
- [ ] Games: small issues observed during v2.93.2 testing (details TBD)
- [ ] DeepAR `background_segmentation` jsdelivr 404 (stage.html falls back to MediaPipe, low priority)
- [ ] ~143 text-tone hardcoded colors deferred from Session 1 color audit (`rgba(255,220,150,*)` and `rgba(255,200,120,*)` across `karaoke/*.html`) — rebrand-safe enough for now
- [ ] Session 1 deferred: extract ambient venue effects (Type 1: speakeasy dust, stadium lasers, forest sway, etc.) from `karaoke/stage.html` into `shell/venue-effects.js` when wellness product work begins
- [ ] Session 1 deferred: create `venues.json` metadata file with product tags when wellness needs it
- [ ] Session 1 deferred: move karaoke performance effects (Type 2: DeepAR face filters, confetti, crowd reactions) formally under `karaoke/effects/` — physically there already but can be better organized
- [ ] Phase 1 pending after shell: de-emphasize room codes in UI (primary flow becomes QR/invite, manual code entry becomes hidden fallback)
- [ ] Direct-launch Games UX: when user launches the iOS app cold and taps the Games tile without having scanned a TV QR, `games/player.html` shows an empty room code screen with no explanation. Acceptable for Phase 1; the Phase 2 invite flow (tokens, share links, contact-based invites) will become the primary path to a game session. Manual room-code entry remains as an explicit fallback. Consider adding a brief "Need a room? Open `tv2.html` on your TV" hint on the join screen when arriving from the shell vs. from a QR.
- [ ] Avatar TV display: Phase 1 uploads single 512x512 avatars sized for phone use. When Phase 2 adds avatars to TV experiences (game lobbies, karaoke stage participant list), evaluate whether to add a larger size variant (1024x1024) for TV quality. If needed, path convention `{userId}/{contactId}@1024.jpg` alongside existing 512; display code picks variant by device; migration strategy is regenerate from source images or ask users to re-upload for key contacts.
- [ ] Profile-editing UI: when building the user's own profile-photo upload (vs contact photos), set `capture="user"` on the file input for front-facing default camera (selfie mode). Contact photos keep the current rear-facing default (`capture="environment"` or unspecified).
- [ ] Searchable contact list component: As contact lists grow (realistic target 50-200 per user), need search/autocomplete on first and last name. Build as a reusable component used by: Contacts screen, Group member selector (screen-group-edit), and Phase 2 invite-flow contact picker. Search matches any word in full_name with prefix match, case-insensitive. Consider debounce (~200ms). Build after Session 4 groups lands; likely Session 4.5 or folded into Session 5.

## Session 4.7 / 4.8 / 5 Architecture Decisions

### Two-device model for TV experience

- Device 1 (phone) runs `games/player.html` — user's private controller view
- Device 2 (iPad/laptop/second phone) runs `games/tv.html` — shared game state for display
- Getting Device 2 onto the physical TV is the user's job via OS-level casting (AirPlay, Chromecast, Miracast, HDMI cable)
- Elsewhere does NOT build casting infrastructure in Phase 1
- tv.html is designed to look great when cast (full-viewport, wake-lock, PWA-ready)
- First-time help overlay on tv.html shows casting instructions per device type
- Phase 2+: native tvOS/Roku/Fire TV apps could enable direct "Send to TV" button (not Phase 1)

### Roles determined by URL, not device size

- `games/player.html` → player role, regardless of device size
- `games/tv.html` → TV display role, regardless of device size
- No auto-detection or auto-redirect based on screen size
- Soft help message if user seems to have opened the "wrong" URL (e.g., TV view on a phone shows "If you meant to play, tap here")
- Rationale: An iPad can be a player OR a TV. Screen size is a property of the device; role is a property of intent. The URL is the contract.

### TV displays as session participant attachments

- Each session participant (player) can pair 0-N TV displays to their slot
- TV devices are Agora subscriber-only clients — receive video, don't publish
- TV displays are INVISIBLE in the participant/lobby list (no "Mike (TV)" showing up)
- TV displays ARE visible in a "who-has-what-setup" indicator shown to all participants
- Any participant adds their own TV displays — no host permission needed
- TV display pairing is a separate in-session mechanism, NOT part of the invite flow
- Rationale: Invites are for PEOPLE. TV displays are personal device-setup decisions.

### Invite architecture: per-person tokens, identity-preserving

- Each invite generates a unique token stored in the `invites` table
- Token links contact_id → session_id → status
- Link format: `elsewhere.my/i/TOKEN` (short URL with tiny redirect handler)
- Token validation via Supabase RPC function (not raw table access) for security
- Tokens are multi-use per contact (Sarah can tap her link, disconnect, tap again — still Sarah)
- Tokens expire after 7 days by default
- Mike can revoke pending (unused) invites; revoking active participants is a Phase 2 moderation feature
- Rationale: Identity linkage (knowing that a joiner is Mike's contact "Sarah") prevents the games-lobby-bug class where names diverged unpredictably

### Display name vs. contact name: separate concerns

- `contacts.full_name` = Mike's private label for a contact ("Mom", "Dr. Smith")
- Session participant `display_name` = what appears publicly in the game/karaoke session
- On join, display_name is PRE-FILLED from contact.full_name, but user can edit it before confirming
- Editing display_name updates ONLY the current session's participant record — does NOT alter Mike's contacts
- One identity per participant per session, used consistently across lobby, chat, scoreboard, video tiles
- Rationale: Mike's contacts are HIS organization. The invitee's display name is THEIRS. Keeping them separate prevents overwrites and the "why did my contact name change" confusion.

### Guest auth: allow guest join, prompt account creation post-session

- Invitee tapping link doesn't need an existing Elsewhere account
- Tap → display name confirmation → join as guest
- Guest participation is recorded with contact_id (who invited them) and display_name (what they called themselves)
- Post-session: optional prompt "Want to save your progress? Create an account"
- Never BLOCK play on account creation
- Rationale: Friction at the point of "tap and play" kills adoption. Account creation comes after value is demonstrated.

### Phase 1 invite distribution: manual send, per-person links

- Mike picks contacts/groups → system generates N tokens → UI shows N links
- Mike manually sends each link via iMessage/Mail/etc.
- Tedious for real users; fine for Phase 1 testing (Mike is the main user)
- Rationale: Gets the core architecture right (per-person tokens) without blocking on email/SMS infrastructure

### Phase 2 invite distribution (deferred): server-sent

- Resend (email) + Twilio (optional SMS) infrastructure
- Supabase Edge Function iterates invites, sends via provider APIs
- Requires: Resend account, DNS configuration for elsewhere.my (SPF/DKIM/DMARC), Twilio account if SMS
- Mike taps "Send invites" → server fan-out, one action → N channels
- Status tracking: sent/delivered/opened/accepted
- Token model UNCHANGED between Phase 1 and Phase 2 — only the distribution mechanism changes
- Rationale: Build the right architecture Phase 1, add polished distribution Phase 2 when there are real users

### Session 5 scope (Phase 1)

Built:
- invites table (verify schema exists from Session 2 migration)
- Pick contacts/groups to invite → generate N tokens → display links
- Short URL + redirect handler (`elsewhere.my/i/TOKEN`)
- Supabase RPC for secure token validation
- Join flow: token validate → pre-fill display name → confirm → enter room
- Revoke pending invites
- Invite history view (Mike sees who he invited, status)

Deferred to Phase 2:
- Server-sent email/SMS (Resend + Twilio)
- Auto-kick active participants
- Real-time delivery/open tracking
- Account creation prompts post-session

### Session sequencing

1. Session 4.7: responsive layouts on `games/player.html` and `games/tv.html`
2. Session 4.8: "Add TV display" pairing via QR/link; TV setup indicator; first-time casting instructions
3. Session 5: full invite flow with per-person tokens, manual distribution, identity linkage, join flow with display_name confirmation
4. Phase 2 later: server-sent invites (Resend/Twilio)
