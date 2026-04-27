# Session 5 Part 2e.0 — Push Notification Infrastructure (Log)

Date: April 27, 2026
Status: SHIPPED and verified end-to-end on real device.
Spec source: docs/SESSION-5-PART-2E-AUDIT.md (locked decisions, commit c2b9427)

---

## Goal

Build push notification infrastructure for Elsewhere so that, in 2e.1, a remote household member starting a karaoke session can ping the active TV's manager via APNs.

This was infrastructure-only — no notification is actually sent yet. The pipeline was wired up and verified through device-token-registration only.

---

## What shipped

### iOS native (~/Projects/elsewhere-app — NOT git-tracked yet)

- Installed @capacitor/push-notifications@8.0.3 via npm
- Capacitor SPM Package.swift auto-managed
- Xcode capabilities: Push Notifications + Background Modes (Remote notifications)
- AppDelegate.swift: two new methods at end of class to forward APNs callbacks to Capacitor
- Info.plist: UIBackgroundModes contains remote-notification
- App.entitlements: aps-environment = development

### Database (Supabase project gbrnuxyzrlzbybvcvyzm)

- Migration db/014_push_subscriptions.sql applied
- push_subscriptions table with unique constraint on (device_token, apns_environment)
- Cascade delete on auth.users.id
- 5 RLS policies
- rpc_register_push_token and rpc_unregister_push_token functions, INVOKER security

### Supabase Edge Function

- supabase/functions/send-push-notification/index.ts deployed
- ES256 JWT signing for APNs auth via Web Crypto
- Caller auth required (JWT verified via supabase.auth.getUser)
- 5 secrets configured: APNS_BUNDLE_ID, APNS_HOST, APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY

### Web (committed to mstepanovich-web/elsewhere main)

- karaoke/singer.html v2.99 -> v2.100 -> v2.101
- setupPushNotifications() function at line ~1797
- Called from doJoin() after mic-connected log
- Plugin access via window.Capacitor.Plugins.PushNotifications (NOT dynamic import)

---

## Commits

- 353936d: karaoke(push): ship 2e.0 push notification infrastructure
- 943cb1b: karaoke(push): use Capacitor.Plugins for plugin access (v2.100->v2.101)

Both pushed to origin/main.

---

## Verification

Real-device test on iPhone (sandbox APNs, sideload from Xcode).

Whole pipeline executed under 1 second from doJoin to DB write.

LOG output (chronological):
- Push: register() called - waiting for token from APNs
- Push: token received
- Push: token registered with Supabase

Database row confirmed with:
- platform: ios
- apns_environment: sandbox
- created_at: 19:55 UTC (first registration)
- updated_at: 20:44 UTC (second registration — UPSERT semantics confirmed)

---

## Decisions locked

- Native APNs (NOT Safari Web Push)
- Schema: (device_token, apns_environment) tuple unique key
- Edge Function: requires authenticated JWT in 2e.0; manager-auth deferred to 2e.3
- Trigger: setupPushNotifications fires from doJoin (Option B), not page load
- Sandbox-only for now; production cert later

---

## Deferred to 2e.3

- Session-manager authorization in Edge Function
- Failed-token cleanup on 410 BadDeviceToken
- Production APNs environment

---

## Known issues (not 2e.0 bugs)

- Proximity banner Yes/No buttons unresponsive (2c.2 issue)
- Don't ask again should be checkbox not link (2c.2)
- TV picker shows for n>=2 households (intentional, from Session 4.10.2)

---

## Lessons learned

### Capacitor plugin access in plain HTML/JS
Use window.Capacitor.Plugins.PluginName, NOT dynamic import. Bare ESM specifiers fail in WKWebView without a bundler.

### Web bundle is bundled, not fetched
iOS Capacitor shell loads from local ios/App/App/public/, NOT GitHub Pages. Updating the web repo doesn't update the phone. Flow: elsewhere-repo -> rsync -> elsewhere-app/www -> cap sync -> ios/App/App/public -> Xcode build -> phone.

### Two repos, only one in git
~/Projects/elsewhere-app is NOT git-tracked. All native iOS changes today live only on local disk. Should git-init at start of next session.

### Don't open HTML files in TextEdit
TextEdit can render HTML or save with wrong extension. singer.html was nearly destroyed today and recovered via git checkout. Use nano or other plain-text editor.

### Chat-display markdown mangling
Patterns like domain.com, email addresses, and filenames sometimes get auto-converted to Markdown links between Claude and the terminal. When unsure, verify file contents with od -c.

---

## File inventory

New (committed in 353936d):
- db/014_push_subscriptions.sql
- supabase/.gitignore
- supabase/config.toml
- supabase/functions/send-push-notification/.npmrc
- supabase/functions/send-push-notification/deno.json
- supabase/functions/send-push-notification/index.ts

Modified:
- karaoke/singer.html (in 353936d and 943cb1b)

iOS shell files modified (NOT in git):
- package.json, package-lock.json
- ios/App/App/AppDelegate.swift
- ios/App/App/Info.plist
- ios/App/App/App.entitlements (new)
- ios/App/CapApp-SPM/Package.swift
- ios/App/App/public/ (rebundled)
- www/ (rsynced)

---

## Next session: 2e.1

1. Read this log + docs/SESSION-5-PART-2E-AUDIT.md
2. Verify infrastructure still in place
3. Implement 2e.1 spec
4. Pre-2e.1: git-init the iOS shell at ~/Projects/elsewhere-app

End of log.
