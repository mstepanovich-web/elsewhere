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
