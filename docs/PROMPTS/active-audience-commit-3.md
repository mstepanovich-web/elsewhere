# Active/audience cluster — Commit 4 prompt (toggle UI + roster sectioning)

> Drafted 2026-05-02; amended 2026-05-03 after the cluster's default-role thread fully closed via three commits. Feed this to Claude Code to ship Commit 4 of the active/audience cluster.
>
> Originally drafted 2026-05-02 as "Commit 3" before the v2.104 → v2.105 → v2.101 partial-then-full split renumbered the cluster commits. Filename retained as `commit-3.md` for git history; content amended 2026-05-03 to current reality.

Read CLAUDE.md and docs/GAMES-CONTROL-MODEL.md § 2.4.3, § 2.4.5, § 2.4.6 first.

This is the fourth and final commit of the active/audience UX cluster. Two coupled UI changes:

(A) Participant-side "I'm playing in this game" toggle — mirrors the manager toggle (§ 2.4.2) for non-managers. Uses rpc_session_set_my_participation_role from db/017.
(B) Roster sectioning into PLAYING (N) / WATCHING (M) headers per § 2.4.5.

Plus lock-on-start behavior for both manager and participant toggles per § 2.4.6.

## Prerequisites

All cluster prerequisites are met as of 2026-05-03 — this commit ships into a green foundation:

- db/017 migration applied to prod (✅ in `db/MIGRATIONS_APPLIED.md` row 017, confirmed 2026-05-02). `rpc_session_set_my_participation_role` available for Part A's change handler.
- db/018 migration applied to prod (✅ in `db/MIGRATIONS_APPLIED.md` row 018, confirmed 2026-05-02). Manager rows now land as `'active'` from `rpc_session_start` for games — Part B's PLAYING section will correctly include them.
- Cluster Commit 2 (`754d0a8`, v2.104, 2026-05-02): doJoin caller-side override on rpc_session_join.
- Cluster Commit 2.5 (`1a3a396`, v2.105, 2026-05-02): db/018 + doJoin restructure.
- Cluster Commit 2.6 (`8825a08`, v2.101 index.html, 2026-05-03): shell rejoin role branch + publishParticipantRoleChanged after each successful join.
- All three above hardware-verified GREEN 2026-05-03 against test sessions DMZS4G (games) + U97XUQ (karaoke). All 4 verification steps green per `docs/SESSION-5-PART-3A2-VERIFICATION-LOG.md` "Cluster Commit 2.6 verification — RESULTS (2026-05-03)" sub-section.
- `games/player.html` currently at v2.105 — this commit bumps to v2.106.
- `index.html` currently at v2.101 — this commit does NOT touch index.html.

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
  4. Gate the publish on actual role change. If the toggle was already in the requested state (e.g., user clicked the already-checked "I'm playing" checkbox), the RPC succeeds idempotently — no role change happened, no publish needed. Detect by comparing the optimistic new value to currentMyRow.participation_role before the RPC; only publish if they differ. Mirrors yesterday's v2.101 Prong 2 gating where the shell publish only fires on `!joinErr` (i.e., actual fresh insert, not 23505 already-a-participant).
  5. On error 55000: surface toast "Room is full — remove a player first" and revert checkbox to authoritative state (whatever currentMyRow shows)
  6. On other errors: surface generic error toast, revert

Lock-on-start (§ 2.4.6):
- Both manager toggle and participant toggle are disabled (not hidden) once a specific game has started
- Detect game-started state via the post-mount routing logic in `games/player.html` around line 1090-1109. That code already distinguishes "in lobby" from "in game-room" to route control_role to the correct screen. The same signal (whatever variable it reads) gates whether we're in lobby or in-game state. Surface the actual variable name during implementation; it's likely something like `currentSession.current_game_id` or similar — but check before assuming.
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

Bump version per CLAUDE.md doctrine (v2.105 → v2.106 on games/player.html).

Closes 2 remaining DEFERRED entries from 2026-05-02:
- "No participant-side 'I'm playing in this game' toggle" — fixed here
- "Manager lobby view doesn't differentiate active vs audience" — fixed here

(The third entry from the original cluster filing — "Default participation_role for self-join is 'audience' instead of 'active'" — already closed 2026-05-03 in commit `c77cc74` via the three-commit chain culminating in cluster Commit 2.6.)

Cluster sequence:
- Spec amendment: `410ccc1` (GAMES-CONTROL-MODEL § 2.4 amendment)
- Migration db/017: `8c83b35` (committed) + `b1a8e4a` (applied to prod)
- Commit 2 (default-role partial — non-manager fresh-join): `754d0a8` (v2.104, 2026-05-02)
- Commit 2.5 (default-role full except shell rejoin — db/018 + doJoin restructure): `1a3a396` (v2.105, 2026-05-02)
- Commit 2.6 (shell rejoin bypass fix — Prong 1 role branch + Prong 2 publish): `8825a08` (v2.101 index.html, 2026-05-03)
- Closeout: `c77cc74` (docs only — DEFERRED status flip + verification log RESULTS), `07ff37d` (db/015 verified applied to prod, ❓ Verify → ✅)
- Commit 4 (this commit, v2.106 games/player.html): toggle UI + roster sectioning
