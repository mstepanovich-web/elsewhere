# Active/audience cluster — Commit 3 prompt

> Queued from session 2026-05-02 for next-session pickup. Feed this to Claude Code after v2.104 default-role fix is hardware-verified green.

Read CLAUDE.md and docs/GAMES-CONTROL-MODEL.md § 2.4.3, § 2.4.5, § 2.4.6 first.

This is the third and largest commit of the active/audience UX cluster. Two coupled UI changes:

(A) Participant-side "I'm playing in this game" toggle — mirrors the manager toggle (§ 2.4.2) for non-managers. Uses rpc_session_set_my_participation_role from db/017.
(B) Roster sectioning into PLAYING (N) / WATCHING (M) headers per § 2.4.5.

Plus lock-on-start behavior for both manager and participant toggles per § 2.4.6.

## Prerequisites

- db/017 migration applied to prod (verify via db/MIGRATIONS_APPLIED.md showing ✅ for row 017 — confirmed 2026-05-02)
- Commit 2 of cluster shipped (754d0a8 — v2.104 — doJoin defaults to 'active')
- v2.104 hardware-verified green (was incomplete at end of 2026-05-02 session — see SESSION-5-PART-3A2-VERIFICATION-LOG.md addendum for remediation steps before attempting)

## Part A — Participant toggle

Locate the existing manager toggle in games/player.html — the `<input id="mgr-is-player">` checkbox referenced in spec § 2.4.2. The toggle currently renders inside the manager-only conditional block.

Add a parallel participant toggle. Two possible patterns:

**Pattern 1** — Single render path with conditional behavior:
Make the existing toggle render for ALL participants (manager + non-manager). Branch the change-handler logic to call rpc_session_update_participant for managers and rpc_session_set_my_participation_role for non-managers.

**Pattern 2** — Separate elements:
Keep manager toggle as-is. Add a new `<input id="participant-is-player">` element rendered only when currentMyRow.control_role !== 'manager'. New change-handler calls rpc_session_set_my_participation_role.

Recommend Pattern 2 for cleaner separation and easier rollback if issues surface. Ship with Pattern 2 unless code reading suggests Pattern 1 is materially simpler.

Toggle behavior (both patterns):
- UI label: "I'm playing in this game" (matches manager's label per § 2.4.3)
- Default checked state on render: based on currentMyRow.participation_role ('active' = checked, 'audience' = unchecked)
- Change handler:
  1. Optimistically update checkbox state
  2. Call rpc_session_set_my_participation_role(p_session_id, p_role) where p_role = 'active' if checked else 'audience'
  3. On success: publish participant_role_changed via the reused-channel pattern (pass _playerRealtimeChannel; same pattern as v2.103 doJoin fix)
  4. On error 55000: surface toast "Room is full — remove a player first" and revert checkbox to authoritative state (whatever currentMyRow shows)
  5. On other errors: surface generic error toast, revert

Lock-on-start (§ 2.4.6):
- Both manager toggle and participant toggle are disabled (not hidden) once a specific game has started
- Detect game-started state via existing currentSession or game-state variable — figure out the right signal during implementation
- Disabled toggle shows explanatory text below: "Game in progress — use [per-game sit-out UX] to step out." For v1, the [per-game sit-out UX] phrasing can be a generic "the game-specific controls" since per-game sit-out flows aren't built yet (3b/3c/3d work)

## Part B — Roster sectioning

Locate renderRoster (or the equivalent post-3a.2 lobby roster render function — name may differ). Currently renders a single flat list of participants.

Change to two sections, displayed as:

    PLAYING (N)
    [participants where participation_role = 'active', sorted by joined_at]
    
    WATCHING (M)
    [participants where participation_role = 'audience', sorted by joined_at]

Both sections render even when one is empty (header reads "PLAYING (0)" with empty body).

Visual treatment per § 2.4.5:
- WATCHING section: dimmed visual weight (reduced opacity, subdued dot color)
- Reuse existing roster styling tokens from elsewhere-theme.css
- No new design vocabulary

Manager-only Remove button (§ 2.5) appears on rows in either section when current viewer is manager.

Apply this rendering change to BOTH manager and non-manager views — visibility benefits everyone.

## Test plan (post-deploy hardware verification)

Setup:
- Mike (manager) and Michael (non-manager) both signed in
- Mike creates session via Games tile, navigates to Last Card lobby
- Michael joins via room code, navigates to Last Card lobby

**Test 1 — Default role:**
- Verify Michael's row in DB has participation_role = 'active'
- Verify Mike's iPhone roster shows Michael under PLAYING (2)

**Test 2 — Participant toggle off:**
- Michael taps "I'm playing in this game" OFF on his Chrome
- Verify Michael's row flips to 'audience' in DB
- Verify Michael's Chrome moves Michael to WATCHING (1) section
- Within 1-2s, verify Mike's iPhone roster updates: Michael moves from PLAYING (2) to WATCHING (1), PLAYING shows just Mike (1)

**Test 3 — Participant toggle on (back to active):**
- Michael taps toggle ON
- Verify reverse propagation

**Test 4 — Manager toggle interplay:**
- Mike toggles his own "I'm playing" OFF
- Verify Mike moves to WATCHING section on both devices
- PLAYING shows just Michael (assuming he's active from Test 3)
- WATCHING shows Mike

**Test 5 — Section rendering when empty:**
- Both Mike and Michael in audience: PLAYING (0) renders with empty body, WATCHING (2) renders both
- Both in active: PLAYING (2) renders both, WATCHING (0) renders with empty body

**Test 6 — Lock-on-start:**
- Both active. Mike taps Start on Last Card.
- Game starts.
- Verify both toggles are now disabled on both devices
- Verify explanatory text appears
- End game, return to lobby
- Verify toggles re-enable

## Deliverable

Single commit. Files touched:
- games/player.html (toggle UI + roster render + change handlers)
- (any peer file sharing the version badge)
- (possibly elsewhere-theme.css if new styling tokens needed; prefer reusing existing tokens)

Bump version per CLAUDE.md doctrine (v2.104 → v2.105).

Closes 3 DEFERRED entries from 2026-05-02:
- "Default participation_role for self-join is 'audience' instead of 'active'" — fixed in Commit 2 of cluster (v2.104)
- "No participant-side 'I'm playing in this game' toggle" — fixed here
- "Manager lobby view doesn't differentiate active vs audience" — fixed here

Cluster sequence:
- Spec amendment: 410ccc1
- Commit 1: db/017 migration (8c83b35)
- Commit 1a: db/017 applied to prod (b1a8e4a)
- Commit 2: doJoin default role fix (754d0a8 — v2.104)
- Commit 3: this commit (v2.105)
