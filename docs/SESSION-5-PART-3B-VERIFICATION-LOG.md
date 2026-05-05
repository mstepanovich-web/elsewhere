# Session 5 Part 3b Hardware Verification Log

**Date:** 2026-05-04
**Pre-verification commit:** `4215387` (v2.106 active/audience cluster closeout from 2026-05-03)
**Post-verification commits (chronological):**
  - `bc99f13` (v2.108) — Euchre auto-end Bugs A + B fix
  - `046d374` (v2.109) — OpenTDB swap (first-ever working Trivia round)
  - `4c3a612` (v2.110) — Trivia polish (4 fixes)
  - `c4af15c` — Phase 2 Commit A (Edge Function + db/019 migration)
  - `8d70473` — db/019 row in MIGRATIONS_APPLIED.md flipped to ✅
  - `7f1c99c` (v2.111) — Phase 2 Commit B (browser premium opt-in via URL)
  - `8abbf6e` — DEFERRED.md SHA substitution
  - `e97dc94` (v2.112) — Trivia premium UI toggle (replaces URL easter-egg as primary)
  - `b068c2c` (v2.113) — Polish (☰ Games removed + stale status reset)
  - `0d9357b` — CONTEXT.md closeout (subsequently restructured)

## Summary

3b hardware verification ran intermixed with shipping rather than as a final gate — verify-after-each-commit pattern, with each verification round either confirming GREEN or surfacing a follow-up bug that shipped as the next commit. All 2026-05-04 commits verified GREEN on iPhone Safari (Mike, manager) + Mac Chrome (Michael, non-manager) EXCEPT v2.113 (PENDING — both polish items deferred to next session opening) and v2.108 (DEFERRED by analogy to v2.107 Last Card race fix — 4-player Euchre setup impractical with 2 devices).

This is the first session where Trivia ran end-to-end in production. Mike had previously never gotten a Trivia question to actually generate, since the Anthropic-direct `triviaGenerate` path 401'd in production every time per CLAUDE.md doctrine line 140. The v2.109 OpenTDB swap was the unblocker.

## Per-commit verification table

| # | Commit | Status | Notes |
|---|---|---|---|
| 1 | `bc99f13` (v2.108) Euchre auto-end fix | 🟡 DEFERRED by analogy | 4-player Euchre setup impractical with 2 devices. Bug shape and fix shape are exact analogs of v2.107 Last Card race which verified GREEN. Confidence is high by analogy; static review confirmed `gameInProgress=false` in `euEndHand` auto-end branch and `send({type:'game-over'})` inside the 3-second `setTimeout` before `showGameOver`. |
| 2 | `046d374` (v2.109) OpenTDB swap | ✅ GREEN | Test session TBFJJH, Movies + Easy difficulty, 10 questions to completion, 863 vs 285 final scores. **First-ever working end-to-end Trivia round in production.** Verified: questions render identically on both devices (rules out chunking issues), options render as "A &#124; The text" with NO duplicated letter (silent prefix-bug fix worked), special characters render correctly via TextDecoder UTF-8 path, scoring math accumulates correctly, streak bonus on consecutive correct, wrong answer resets streak, game-end transitions cleanly to screen-gameover on both devices, manager-bar Reveal/Next hide correctly on game-end. |
| 3 | `4c3a612` (v2.110) Trivia polish | ✅ GREEN | All four polish fixes verified: (a) auto-reveal grace fires 2s after both submit; (b) timer bar advances visibly on Michael's Mac Chrome (was previously frozen); (c) "QUESTION 7 OF 10" indicator visible on both devices above question text; (d) wrong-answer styling shows red border + red-faint background on user's wrong selection at reveal phase. |
| 4 | `c4af15c` Phase 2 Commit A (Edge Function + db/019) | ✅ GREEN (cURL) | cURL-verified post-deploy with HTTP 200 + 10 valid Movies/Easy questions returned + rate-limit row incremented to count=1 in `trivia_premium_usage` table. Anthropic upstream call succeeded with `claude-sonnet-4-6` model. Function logs confirmed `[generate-trivia] user=<uuid> cat=Movies diff=Easy count=10 valid=10 usedToday=1`. |
| 5 | `7f1c99c` (v2.111) Phase 2 Commit B browser premium opt-in | 🟡 PARTIAL | Surfaced URL-routing gap on iOS Safari: `?premium=1` query param gets stripped during session routing before `isPremiumTrivia()` runs. Toggling premium ON via URL appeared to work briefly but never persisted to the actual generation request. Led directly to v2.112 (in-UI toggle) as the resolution. URL backup path preserved in v2.112 for compatibility with bookmarks / muscle memory. |
| 6 | `e97dc94` (v2.112) Trivia premium UI toggle | ✅ GREEN | Verified end-to-end: (a) toggle visible on Trivia info screen between subtitle and description; (b) tapping toggle flips subtitle in real-time between "AI-generated questions" and "Community questions"; (c) generate questions with toggle ON returns "(premium)" suffix in status text "✓ 10 questions ready! (premium)"; (d) toggle state survives navigation away from screen-game-info and back; (e) toggle hidden on Last Card and Euchre info screens. Both iPhone Safari + Mac Chrome behaved identically. |
| 7 | `b068c2c` (v2.113) Polish | 🟡 PENDING | Both items pending iPhone Safari hardware verification at next session opening: (a) generate Trivia questions with premium toggle ON → tap Switch Game (confirm dialog) → return to Trivia tile → confirm status text is cleared (no stale "(premium)" suffix or "✓ 10 questions ready!"); (b) confirm ☰ Games button no longer appears on the manager bar; (c) confirm Switch Game still works as before (broadcasts switch-game to non-managers, asks for confirmation, transitions everyone to lobby). |

## Test environments

**iPhone Safari (manager device).** Mike Stepanovich (UID `8984755f-9534-437a-a2a7-2aeba06c7e9d`). Mobile Safari against `https://mstepanovich-web.github.io/elsewhere/games/player.html`. NOT the iOS Capacitor app — bundle is stale at v2.99 per Capacitor caveat in the closing log.

**Mac Chrome (non-manager device).** michael stepanovich (UID `a2ae608d-a819-4a2b-8073-f723d1850d52`). Chrome on macOS against the same GitHub Pages URL.

**Test sessions used:**

- **TBFJJH** — Movies + Easy difficulty, 10-question Trivia round, ran end-to-end during v2.109 verification. The first session to complete a full Trivia round in production. Reused for v2.110 polish verification (auto-reveal, non-manager timer, progress indicator, wrong-answer styling) and v2.112 toggle verification.

**Anthropic API key.** Active key digest: `3d16f5ccee065a7b5064c774c3363438ef03cbcf07b9551da363a9f056cc8cea`. **Note: original key rotated mid-session** after exposure in setup screenshots during the session. The original key was revoked; the digest above corresponds to the rotated replacement which is the live Supabase secret. Rotation flow: `supabase secrets set ANTHROPIC_API_KEY=<new> --project-ref gbrnuxyzrlzbybvcvyzm`. No re-deploy of `generate-trivia` was required (env var is read at runtime).

## Bugs surfaced and fix-forward record

Three bugs surfaced during 3b verification. All resolved in-session:

**URL-routing gap on iOS Safari.** Filed during v2.111 verification — `?premium=1` query param gets stripped during session routing before `isPremiumTrivia()` runs, making the URL easter-egg unreliable on iOS Safari. The Mac Chrome path worked correctly because Chrome's session routing preserves query params; iOS Safari's session routing apparently doesn't. Resolved in v2.112 (`e97dc94`) by adding an in-UI toggle on the Trivia info screen that writes directly to localStorage with no URL round-trip. URL backup path preserved unchanged for compatibility.

**Stale "(premium)" status text persistence.** Filed during v2.112 verification — after generating questions with premium ON, navigating away from screen-game-info via Switch Game, then re-entering Trivia, the previous round's "✓ 10 questions ready! (premium)" status text remained visible until the next Generate Questions tap. Root cause: `selectGame()` didn't reset `trivia-gen-status` textContent on entry — the div was only mutated by `triviaGenerate()` during loading and after success/failure. Resolved in v2.113 (`b068c2c`) by clearing it inside the trivia branch's setup block, alongside the v2.112 premium-row show/hide.

**☰ Games button redundancy.** Surfaced via Claude Code investigation during v2.112 verification (read-only audit of manager-bar buttons). Found that ☰ Games (added at v2.49 `ceff8cd` 2026-04-15) had no `confirm()` dialog, no Agora broadcast, and left the manager on the game picker while their players continued mid-game with no signal — a footgun with no documented use case. Switch Game (added at v2.101 `8825a08` 2026-04-30) already provides the proper "leave the current game" affordance with confirm + broadcast. Resolved in v2.113 (`b068c2c`) by removing the ☰ Games button from the manager-bar. `goToLobby()` itself preserved (called from 6 other sites).

## Migrations applied

`db/019_trivia_premium_usage.sql` applied 2026-05-04 via Supabase SQL Editor immediately after Phase 2 Commit A (`c4af15c`) landed. Three-query verification:

```sql
-- (1) Table exists
SELECT EXISTS (SELECT 1 FROM information_schema.tables
               WHERE table_name = 'trivia_premium_usage');
-- → t

-- (2) RLS enabled
SELECT tablename, rowsecurity FROM pg_tables
 WHERE tablename = 'trivia_premium_usage';
-- → trivia_premium_usage | t

-- (3) Zero policies (service-role-bypass-only access)
SELECT COUNT(*) FROM pg_policies
 WHERE tablename = 'trivia_premium_usage';
-- → 0
```

`db/MIGRATIONS_APPLIED.md` row 019 flipped from `❓ Verify pending` to `✅` in commit `8d70473`.

## Edge Function deployment record

**`generate-trivia`** deployed via:

```bash
supabase functions deploy generate-trivia --project-ref gbrnuxyzrlzbybvcvyzm
```

**No flags** — specifically NOT `--no-verify-jwt` (opposite of `send-push-notification`'s deploy pattern, per Phase 2 doctrine documented inline in the function's header comment). The Supabase gateway verifies caller JWT before the function runs.

Pre-deploy: `supabase secrets set ANTHROPIC_API_KEY=<key> --project-ref gbrnuxyzrlzbybvcvyzm`. Verified set via `supabase secrets list --project-ref gbrnuxyzrlzbybvcvyzm` (lists secret names, not values).

Post-deploy verification:

```bash
curl -i -X POST 'https://gbrnuxyzrlzbybvcvyzm.supabase.co/functions/v1/generate-trivia' \
  -H "Authorization: Bearer <user_jwt>" \
  -H "Content-Type: application/json" \
  -d '{"categoryLabel":"Movies","difficulty":"Easy","amount":10}'
# → HTTP 200, { "questions": [ ...10 valid Movies/Easy questions... ] }
```

Function logs tailed via `supabase functions logs generate-trivia --project-ref gbrnuxyzrlzbybvcvyzm`. Confirmed: `[generate-trivia] user=<uuid> cat=Movies diff=Easy count=10 valid=10 usedToday=1`.

## Net assessment

Trivia productionization + Trivia Phase 2 fully shipped. Trivia is now playable end-to-end for the first time with both default (OpenTDB) and premium (Anthropic Sonnet 4.6) paths.

Two open verification items:

1. **v2.113 hardware verification on iPhone Safari** — both items pending (stale-status reset + ☰ Games removal). Gate before any new Track per the closing log's "Next session entry point."
2. **v2.108 Euchre auto-end fix** — formal hardware verification deferred indefinitely (4-player setup impractical). Confidence is high by analogy to v2.107's Last Card race fix; documented in DEFERRED entry "Euchre auto-end path" with the v2.108 SHA.

Neither blocks day-to-day Trivia playability. Mike can run unlimited Trivia rounds today against either path with full confidence in v2.109 / v2.110 / v2.112's GREEN verification.

## Operational note

The Anthropic API key was exposed in setup screenshots during the session. Mike rotated it via Anthropic console (revoke + new key) and re-set the Supabase secret with `supabase secrets set ANTHROPIC_API_KEY=<new>`. No re-deploy needed (env var is read per-invocation). The exposed key is dead; the live key digest is recorded above in "Test environments" for future cross-reference.

Filing this here as a reminder: **never include API keys in screenshots, terminal output, or commit messages**. Even `supabase secrets set NAME=<value>` shows the value in shell history; clear it with `history -d <line>` if used. The CLI's recommended pattern is `read -s SECRET && supabase secrets set ANTHROPIC_API_KEY=$SECRET && unset SECRET` to avoid history persistence.
