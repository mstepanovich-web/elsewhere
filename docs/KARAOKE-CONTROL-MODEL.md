# Karaoke Control Model

**Created:** 2026-04-25
**Purpose:** Defines the role hierarchy, state machine, and permission matrix for karaoke sessions in Elsewhere. Specifies what each role can do, how transitions happen, and how the manager intervenes when needed.
**Scope:** karaoke/singer.html and karaoke/stage.html. References audience.html as a frozen surface (no new features in Session 5).
**Anchored to:** `docs/PHONE-AND-TV-STATE-MODEL.md` (platform-level user model). Where this doc references HHU, HHM, household admin, proximity, or Modes A/B/C, those concepts are defined in the state model. This doc does not redefine them.
**Referenced by:** `docs/SESSION-5-PART-2-BREAKDOWN.md` 2d, 2e, 2f sub-parts.

---

## 1. Role hierarchy and definitions

### Platform-level roles (defined in PHONE-AND-TV-STATE-MODEL.md)

This document references three platform-level concepts:

- **Household Manager (HHM):** the household admin (`household_members.role = 'admin'`). One per household. Has authority for member management, TV claims, invitations.
- **Household User (HHU):** a household member (`household_members.role = 'user'`). Pre-invited or post-scan-approved. Multiple per household.
- **Non-Household User (NHHU):** authenticated user not associated with the household where the session is happening. Per the platform user model, NHHUs are first-class users with one specific limitation: they cannot access TV-device-required features. Karaoke singing is one such feature.

### Session-level roles (this document defines)

A karaoke session has these roles:

| Role | Definition |
|---|---|
| **Session Manager** | The user with session-level control authority. Always exactly one per session. Computed from a hierarchy (see below). |
| **Active Singer** | The user currently performing OR next-in-queue between songs. State-derived; not assigned. See state machine in section 3. |
| **Available Singer** | An HHU with at-home proximity who is in the session and is not the Active Singer. Can be queued (has a queue entry) or not queued (no entry). Queue membership is a state, not a separate role. |
| **Audience** | Anyone in audience mode for this session: HHU not at home, HHU who deep-linked to audience by accident, or NHHU via deep link. Audience users are on audience.html. |

### Session Manager hierarchy

Authority flows in this order:

1. **HHM is in the session → HHM is the Session Manager.** Always. The HHM can never be displaced by an HHU while present.
2. **HHM is not in the session → the session originator (an HHU) is the Session Manager.** This HHU is colloquially called the "host" — they hold session manager authority temporarily, in absence of the HHM.
3. **Auto-pass on departure:** if the current Session Manager (HHM or host) leaves the session, authority auto-passes to the next person who joined the session after the current Session Manager joined. Determined by session-join order, not Elsewhere-login order.

The system always designates exactly one Session Manager. If no one in the session has explicitly claimed it, the system computes who holds it. That person may not be aware they have the role until they need to take action.

### Hosts and HHMs have the same in-session authority

Whether the Session Manager is an HHM or a host (HHU acting as session manager), they have identical in-session powers. The permission matrix uses a single "Session Manager" column for both cases. The distinction matters only for hierarchy resolution (HHM displaces host on join), not for what they can do once in the role.

### Promoted hosts who are not household members

The state model notes that in edge cases, a manager may promote a non-household audience user to a host role. Such a promoted host has session manager authority within the session, but their household-membership status is unchanged. They do NOT gain Back-to-Elsewhere visibility to a household home they're not part of. This safety guarantee is preserved in karaoke.

---

## 2. Active Singer state machine

The Active Singer role is **state-derived, not assigned**. The system computes who holds it at any moment based on session state. There is always either exactly one Active Singer, or none.

### The three states

| State | Condition | Active Singer |
|---|---|---|
| **Performing** | A song is currently playing | The person whose song is playing |
| **Between songs** | No song is playing AND the queue has entries | The person at queue position 1 |
| **Idle** | No song is playing AND the queue is empty | None — the active-singer slot is empty |

### Active Singer sub-states

When a user is in the Active Singer role, they pass through sub-states during their turn:

- **Pre-song:** They have just been promoted (after tapping "take stage") but haven't started a song yet. Their pre-selections (song, venue, costume) are loaded onto the TV. They can change their song, venue, costume, and other settings before tapping Start.
- **Mid-song:** A song is actively playing. They can pause, restart, stop, end the song, change costume, change view/zoom/pan, mute, toggle comments, etc.
- **Post-song / between own songs:** Their song just ended (naturally or via End Song). The system computes the next state. If queue is empty, they remain Active Singer (Idle slot consumed by them sitting). If queue has someone next, they transition out of Active Singer (see "Transitions" below).

The pre-song / mid-song / post-song distinction is sub-state, not different roles. Permissions are largely the same across sub-states; differences are state-dependent (e.g., "Pause Song" is only meaningful during mid-song).

### One queue entry per HHU

Each HHU has at most one queue entry at any moment. When an HHU is the Active Singer, they do NOT have a queue entry — they ARE the active slot. The state transitions are:

```
Available Singer (no entry)
  → submits to queue →
Available Singer (with entry, "queued")
  → promoted (queue advances) →
Active Singer (pre-song)
  → taps Start Song →
Active Singer (mid-song)
  → song ends →
[queue check]
  → if queue has another entry: → Available Singer (no entry — they can re-queue if they want)
  → if queue is empty AND they don't end turn: → remain Active Singer (Idle, can start a new song)
  → if queue is empty AND they tap End Turn or leave: → no Active Singer (Idle state)
```

This means an HHU is always in exactly one of these positions: not in queue, has a queue entry waiting, or is the Active Singer.

### Transitions and triggers

**Promotion (Available Singer → Active Singer):**

When the active-singer slot becomes empty (song ends with queue waiting, OR someone in the active slot leaves), the system promotes the next-in-queue user. Specifically:

1. System computes who is next-in-queue (queue position 1)
2. That user's phone receives a "You're up — tap to take stage" prompt
3. If their phone app is backgrounded, they receive a push notification: "You are up — click here to take the stage"
4. The TV shows "Up next: [name]" (avatar + name + their queued song + their queued venue)
5. **No countdown.** The system waits indefinitely for them to tap.
6. They have two actions:
   - **Tap to take stage** → they become Active Singer (pre-song). Their pre-selections load onto the TV. They can adjust before starting.
   - **Remove themselves from queue** → they decline this turn. Their queue entry is removed. System computes the next next-in-queue and repeats from step 1. If queue empties out from sequential declines, system enters Idle state.

**Manager intervention during promotion stall:**

If the next-up user doesn't respond and the Session Manager wants to push things along:

- Session Manager sees a non-blocking toast/banner on their phone: "[name] hasn't confirmed, wait or move to next" with two buttons:
  - **Skip [name] and promote next** → that user's queue entry is removed; system promotes the next next-in-queue.
  - **Wait longer** → dismiss the toast; continue waiting.

The toast appears proactively after some delay (specifics TBD in 2e implementation) but it does not auto-skip — manager action is required.

**Active Singer → out (song ends, queue has someone next):**

1. Active Singer's song ends (natural completion, End Song tap, or Stop Song followed by End Turn)
2. **Social window:** the just-finished singer remains visible on stage briefly. Time for applause, bows, comments from the room. No fixed duration; the room takes its time.
3. TV displays the "Next Singer" card: avatar, name, queued song, queued venue
4. The promotion flow begins for the next-in-queue user (see above)
5. The just-finished singer transitions to Available Singer (no queue entry — they can re-queue if they want another turn)

**Active Singer remains active (queue empty, song ends):**

If the queue is empty when a song ends, the just-finished singer stays as Active Singer. They can:

- Start a new song (search → select → start)
- Restart their last song
- Take a break, talk to the room, then start a new song
- Sit indefinitely without action

There is no automatic timeout pushing them out. The Session Manager has the "Skip current Active Singer" power to force-end their turn if they need to be moved along.

**Idle state (no song, no queue):**

When there's no Active Singer, the TV displays the 360° venue tour (cycling through available venues, or current venue's 360 view) with overlay text: **"Select and start a song to sing next!"**

This invites any Available Singer to start a song, becoming the new Active Singer immediately (no queue intermediary needed when queue is empty).

### Restart and Stop semantics

The Active Singer has three distinct actions for managing their current song:

| Action | Effect on song | Effect on turn |
|---|---|---|
| **Pause / Resume** | Holds playback at current position; resumes from same position | Stays in active state, mid-song sub-state |
| **Restart** | Plays the song from the beginning | Stays in active state, mid-song sub-state |
| **Stop** | Terminates the song; mute + clear flags + return to screen-home (per current code) | Stays in Active Singer role; sub-state shifts (no song playing) |
| **End Song / End Turn** | Terminates the song; explicit "I'm done with my turn" | Triggers next-in-queue promotion if queue has someone; otherwise Idle |

The principle: **Stop ≠ End Turn.** A singer who stops mid-song stays as Active Singer. They can restart the same song, start a different song, or sit. Their turn only ends when:
- A song completes naturally
- They explicitly tap End Song / End Turn
- Session Manager skips them via "Skip current Active Singer"

This respects the casual family/friends context — singers who flub a song shouldn't lose their turn just because they hit Stop. They get to retry.

### Manager intervention powers (recap)

The Session Manager can intervene at any point. Per the hybrid model (Q-2A from product discussion):

**Soft interventions (modify what the active singer is doing without ending their turn):**

- Restart current song
- Pause / Resume current song
- Toggle stage view, zoom, pan
- Mute / unmute mic
- Toggle costume effects
- Toggle comments display

These match Active Singer's mid-song controls. Session Manager has Override authority on each.

**Hard interventions (change who is in the active singer slot):**

- **Skip current Active Singer:** force-ends their turn even if no song completed. Triggers promotion of next-in-queue (or Idle if queue empty).
- **Skip next-up unresponsive singer:** removes them from queue position 1 without making them active. Promotes the queue position 2 user instead.
- **Take over active singer slot:** Session Manager promotes themselves (or another specific person) to Active Singer immediately, displacing the current Active Singer if any.

**Session-level interventions:**

- **End Session entirely:** triggers `rpc_session_end`, ending the session for everyone. Session Manager only.

### Manager Override mechanism — implementation note

Currently no implementation exists for the manager override mechanism. All mid-song singer controls send via Agora data streams (`sendToStage(obj)`) from the Active Singer's phone to stage.html. There is no path today for Session Manager's phone to send equivalent commands.

The 2e implementation needs to design this mechanism. Options under consideration:

- **Option A:** Session Manager's phone sends a Supabase realtime command that the Active Singer's phone listens for and re-broadcasts as Agora to stage.
- **Option B:** Session Manager's phone gets direct stage-channel access and sends Agora commands directly.
- **Option C:** New RPC layer for session-state mutations that publishes events stage.html consumes.

Decision deferred to 2e implementation pass. Documented as known implementation gap.

---

## 3. Permission matrix

The matrix below catalogs every karaoke-related capability across the four roles defined in Section 1. Entries are based on the function audit in `docs/KARAOKE-FUNCTION-AUDIT.md` (commits `c713919` and `4886241`).

### Default lens

This matrix applies a **default-permissive** lens: a capability is restricted only when there is a genuine reason to do so. Reasons that justify restriction:

- The action would affect another user's experience without their consent (e.g., changing the live stage venue when you aren't the active singer)
- The action would violate the role hierarchy (e.g., a non-manager taking session-manager-only actions)
- The action requires capabilities the user doesn't have (e.g., audience users can't sing because karaoke singing requires a TV device, and audience includes NHHU users)

Capabilities that are purely self-affecting (configuring own mic, browsing venues for personal preview, viewing read-only displays) default to permissive — restrictions add complexity without benefit.

### Audience.html freeze

Audience.html is frozen for Session 5: bug fixes only, no new features. Audience capabilities in this matrix reflect what's available in audience.html today. Where the spec intent goes beyond what audience.html currently supports, those rows are flagged as deferred to post-Session-5 unified-app migration.

### Roles in the matrix

- **SM** — Session Manager
- **AS** — Active Singer
- **AvS** — Available Singer (covers both queued and not-yet-queued sub-states)
- **Aud** — Audience

### Section 3.1: screen-home (post-join action hub)

Singer.html's main hub screen after joining a session.

| # | Capability | SM | AS | AvS | Aud |
|---|---|---|---|---|---|
| 1.1 | Search for a song | Yes | Yes | Yes | No |
| 1.2 | Mute Home | Yes | Yes | Yes | No |
| 1.3 | Invite — share/copy session link | Yes | Yes | Yes | No |
| 1.4 | Browse venues (own phone-side preview) | Yes | Yes | Yes | No (deferred — see footnote) |
| 1.5 | Apply venue selection | Override (apply to live stage) | Yes (live or pre-selection) | Yes (own pre-selection only) | No |
| 1.6 | Browse costumes (phone-side preview with images) | Yes | Yes | Yes | No (deferred — see footnote) |
| 1.7 | Apply costume selection | Override | Yes (live or pre-selection) | Yes (own pre-selection only) | No |
| 1.8 | Open mic gear / settings | Yes | Yes | Yes | No |
| 1.9 | Toggle "Video Chat with Audience" | Override | Yes | Yes | No |
| 1.10 | View "Back to Elsewhere" pill | Yes (if HHU/HHM) | Yes (if HHU/HHM) | Yes (if HHU/HHM) | Yes (all audience — see footnote) |

**Removed in 2e:** the "Leave" button (`screen-home`) is redundant with Back-to-Elsewhere and will be removed in 2e implementation.

**Footnote 1.4 / 1.6 — Audience browse for marketing:** Spec intent is Yes (advertising / user acquisition value). Implementation requires audience.html UI changes, which is frozen for Session 5. Captured as DEFERRED: "Audience browsing of venues/costumes for marketing." Implementation lands when audience surface migrates to unified app post-Session-5.

**Footnote 1.10 — Back-to-Elsewhere for all audience:** This is a CHANGE from current behavior. Today only HHU audience sees the pill. Under the new HHU/NHHU framing, all audience users see it. HHU audience lands on their normal Elsewhere home. NHHU audience lands on a placeholder Elsewhere home with options to return to audience or explore Elsewhere (the audience-to-NHHU conversion path). State model gets updated alongside this spec.

### Section 3.2: search / select / song flow

| # | Capability | SM | AS | AvS | Aud |
|---|---|---|---|---|---|
| 2.1 | Type in search bar / fetch results | Yes | Yes | Yes | No |
| 2.2 | Browse search results | Yes | Yes | Yes | No |
| 2.3 | Tap a result → song detail view | Yes | Yes | Yes | No |
| 2.4 | View song detail (title, artist, video preview) | Yes | Yes | Yes | No |
| 2.5 | Play song preview clip on phone | Yes | Yes | Yes | No |
| 2.6 | "Start Song" — begin live song | Override (force-start) | Yes (begin own turn) | Yes (if no live song AND queue empty/they're up) | No |
| 2.7 | "Add to Queue" / "Update My Song" | No (manager doesn't queue songs for others) | N/A (already active) | Yes (creates entry if none, replaces song if entry exists) | No |
| 2.8 | Cancel out of song selection | Yes | Yes | Yes | No |
| 2.9 | Edit existing queue entry's song | Yes (reorder/remove others, but cannot change their song) | N/A | Yes (own entry only) | No |
| 2.10 | Remove queue entry | Yes (override remove others) | N/A | Yes (own entry only) | No |
| 2.11 | Restart current song | Override | Yes | No | No |
| 2.12 | Stop current song (without ending turn) | Override (skip them entirely) | Yes | No | No |
| 2.13 | End song / End turn | Override (skip) | Yes | No | No |
| 2.14 | Skip current Active Singer (force-end their turn) | Yes | — | — | — |
| 2.15 | Skip next-up singer (pass over in queue) | Yes | — | — | — |

**Footnote 2.6 — Available Singer Start Song conditions:** Available Singer can start a song if no live song is playing AND (queue is empty OR they're the next-up singer who has tapped take-stage and become Active Singer). Otherwise Start Song is greyed out or replaced with "Add to Queue."

**Footnote 2.7 — Add to Queue UX:** Button label changes based on Available Singer's queue state:
- No existing entry: button says "Add to Queue" — creates new entry (queue membership state shifts to "queued")
- Existing entry: button says "Update My Song" — replaces song in existing entry

**Footnote 2.9 — Manager queue editing scope:** Session Manager can REORDER queue positions and REMOVE entries. Session Manager CANNOT edit the song selection of another singer's queue entry — let people pick their own songs.

**Footnote 2.6b — Manager force-start scenarios:** Per the hybrid intervention model, Session Manager can:
- Take the stage themselves (force-promote self to Active Singer)
- Force-promote a specific person from the queue
- Force-start a song on the Active Singer's behalf (deferred per Q-2B helper feature)

**Footnote 2.11–2.13 — Manager Override mechanism:** Currently no implementation exists. See Section 2's "Manager Override mechanism — implementation note" for the architectural decision deferred to 2e.

### Section 3.3: Active Singer live controls (mid-song / pre-song unified)

These controls live on `screen-performing` and its overlays. Per the audit, all 21 controls catalogued are currently ungated (single-singer model). Under the new role model, they become Active Singer with Session Manager Override.

| # | Capability | Audit ref | SM | AS | AvS | Aud |
|---|---|---|---|---|---|---|
| 3.1 | Big Mute / Unmute mic | Control 2 | Override | Yes | No (not on screen-performing) | No |
| 3.2 | Start Lyrics | Control 5 | Override | Yes (when song playing and lyrics available) | No | No |
| 3.3 | Lyrics seek-back / pause / restart / seek-forward | Control 6 | Override | Yes (when lyrics running) | No | No |
| 3.4 | Pause song / Resume song | Control 7 | Override | Yes (when song playing) | No | No |
| 3.5 | Stop song | Control 8 | Override (skip) | Yes (when song playing) | No | No |
| 3.6 | Restart song | Control 9 | Override | Yes (when song playing) | No | No |
| 3.7 | Stage view toggle (Audience ⇄ Singer) | Control 10 | Override | Yes | No | No |
| 3.8 | Zoom toggle | Control 11 | Override | Yes | No | No |
| 3.9 | Pan left / Pan right | Control 12 | Override | Yes | No | No |
| 3.10 | Costume overlay (DeepAR effects + accessories + Clear All) | Controls 13, 17, 18, 19 | Override | Yes | No | No |
| 3.11 | Toggle Comments display on stage | Control 15 | Override | Yes | No | No |
| 3.12 | Close costume overlay | Control 16 | Override | Yes | No | No |
| 3.13 | Back-to-Elsewhere pill | Control 20 | Yes (if HHU/HHM) | Yes (if HHU/HHM) | Yes (if HHU/HHM) | Yes (per Section 3.1 footnote) |
| 3.14 | Debug LOG button | Control 21 | Yes | Yes | Yes | Yes |

**Footnotes for Section 3.3:**

- **Mid-song venue change is OUT.** Venue is locked at song start. Singer must Stop the song to change venue. No mid-song venue change capability.
- **"When song playing" annotations:** Some rows say "Yes (when song playing)" or "Yes (when lyrics running)." This reflects state-machine reality, not permission restriction. The control is permissioned to Active Singer; whether it's actionable depends on whether a song / lyrics are currently playing.
- **Available Singer "No (not on screen-performing)":** These controls render only on screen-performing (the Active Singer's mid-song surface). Available Singer doesn't reach this screen. Permission is "No" by structural design, not by intent.

### Section 3.4: mic / costume / settings (pre-song / configuration)

These are the pre-song setup screens. Per the audit, NOT accessible during an active song.

| # | Capability | SM | AS | AvS | Aud |
|---|---|---|---|---|---|
| 4.1 | Open mic settings (screen-mic entry) | Yes | Yes | Yes | No |
| 4.2 | Select mic device | Yes | Yes | Yes | No |
| 4.3 | Toggle FX (Reverb / Echo / Boost / Deep) | Yes | Yes | Yes | No |
| 4.4 | Adjust volume slider | Yes | Yes | Yes | No |
| 4.5 | Per-screen mute button | Yes | Yes | Yes | No |
| 4.6 | Open stage venue picker (browse venues) | Yes | Yes | Yes | No (frozen audience.html) |
| 4.7 | Apply venue selection | Override | Yes (live or pre-selection) | Yes (own pre-selection only) | No |
| 4.8 | Open full costume screen | Yes | Yes | Yes | No |
| 4.9 | Select / apply DeepAR effects | Override | Yes (live or pre-selection) | Yes (own pre-selection only) | No |
| 4.10 | Select / apply Basic accessories | Override | Yes (live or pre-selection) | Yes (own pre-selection only) | No |
| 4.11 | Toggle Video Chat with Audience | Override | Yes | Yes | No |

**Footnotes for Section 3.4:**

- **Apply semantics depend on role state (rows 4.7 / 4.9 / 4.10):**
  - Active Singer (mid-song): applies to live TV stage immediately (where current code permits — costumes yes, venue no per Section 3.3 footnotes)
  - Active Singer (pre-song): applies to live TV stage (their stage during their turn)
  - Available Singer: applies to own pre-selection only (stored for when they become Active later)
  - Session Manager: Override (deferred per Q-2B helper feature)
- **Manager Override deferred:** All Override entries in Section 3.4 are deferred per the Q-2B helper feature deferral. Implementation post-Session-5.

### Section 3.5: cross-cutting + queue management + session-level powers

| # | Capability | SM | AS | AvS | Aud |
|---|---|---|---|---|---|
| 5.1 | View full session queue (read-only) | Yes | Yes | Yes | Yes (deferred — frozen audience.html) |
| 5.2 | Reorder queue positions | Yes | No | No (only own entry) | No |
| 5.3 | Remove other participants from queue | Yes | No | No (only own entry) | No |
| 5.4 | Force-promote specific queue entry to Active | Yes | No | No | No |
| 5.5 | View who is currently Active Singer | Yes | Yes | Yes | Yes (visible on stage / audience UI) |
| 5.6 | View other participants' pre-selections (read-only) | Yes (for queue management) | No | No (just their position) | No |
| 5.7 | End session entirely | Yes | No | No | No |

**Footnote 5.1 — Audience read-only queue:** Per the audience.html freeze, NOT shipped in Session 5. DEFERRED for unified-app migration.

**Footnote 5.6 — Manager view of pre-selections:** Manager needs to see what other singers have queued (song, venue, costume) for queue management. Read-only — manager doesn't EDIT others' selections.

**Footnote 5.7 — End session:** Session Manager only authority. Auto-pass mechanic from Section 1 handles transitions when current Session Manager leaves.

---

## 4. UI surfaces

This section maps the role permissions from Section 3 onto the actual UI surfaces — what each role sees and uses. References the function audit at `docs/KARAOKE-FUNCTION-AUDIT.md`.

### 4.1 Singer.html — role-aware screens

Singer.html today operates as a single-singer model. Under the new role model, it becomes role-aware: the same DOM is reused, but conditional rendering shows different screens and controls based on the user's current role and state.

**Active Singer (pre-song) sees:**

- screen-home with all action tiles (search song, mic gear, costume, venue, video chat toggle, invite)
- Their pre-selections loaded as defaults (song, venue, costume from queue entry that promoted them)
- "Start Song" affordance (the primary action — confirms ready to begin)
- All settings screens accessible (screen-mic, screen-costume, screen-venue) for last-minute adjustments
- Back-to-Elsewhere pill (top-right, visible per HHU/HHM gating)

**Active Singer (mid-song) sees:**

- screen-performing with the 21 controls catalogued in the audit
- Lyrics overlay (if available for the song)
- Costume overlay accessible via Costume button
- Mute / pause / restart / stop / end song controls
- View toggle, zoom, pan controls
- Comments toggle
- Back-to-Elsewhere pill
- NOT accessible mid-song: mic settings, venue picker, song search, video chat toggle, full costume screen (locked-out per audit)

**Available Singer (queued) sees:**

- screen-home with most action tiles
- Their queue position prominently displayed (e.g., "You're #3 in queue")
- Song detail of their queued entry (what they've selected)
- "Update My Song" affordance instead of "Start Song" (since they're queued, not next)
- Edit queue entry: change song / venue / costume / comments-toggle, or remove themselves from queue
- All settings screens accessible — selections apply to their own pre-selection only
- Back-to-Elsewhere pill

**Available Singer (not queued) sees:**

- screen-home with most action tiles
- "Add to Queue" affordance — search for song, configure venue/costume, submit entry
- "Start Song" affordance available IF no live song is playing AND queue is empty — they become Active Singer immediately on song start
- All settings screens accessible — selections apply to their own pre-selection
- Back-to-Elsewhere pill

**Session Manager sees:**

- All Available Singer affordances PLUS
- Queue management UI (reorder, remove others, force-promote, skip current/next)
- Override affordances on Active Singer's controls (deferred per Q-2B for song/venue/costume; not deferred for skip/end-song/take-over/end-session)
- Session-level "End Session" action
- Visibility into other participants' pre-selections (read-only)

**Audience sees on singer.html:**

- Singer.html is not the audience surface. Audience uses audience.html exclusively.
- This row is in the matrix for completeness; audience never reaches singer.html.

### 4.2 Stage.html — TV-side display + queue panel

Stage.html is the TV-side display surface. Per the platform model, the phone is primary control; the TV is display + testing affordances + future remote-control target.

**TV displays during a session:**

- Singer's video composited into the venue background (when active singing happens)
- Lyrics overlay (when active and toggled on)
- Audience video tiles (when video-chat-with-audience toggled on)
- Comments overlay (when comments toggled on)
- "Up Next" card during transitions between songs (avatar + name + song + venue)
- Queue panel (slide-out, manually toggled — see below)
- 360° venue tour during Idle state ("Select and start a song to sing next!")

**Queue panel (new in 2d.1):**

- Added to existing bottom-right button cluster on stage.html (alongside Comments button)
- Tap toggles a right-side slide-out panel matching Comments panel's existing pattern
- Panel content: avatar + name + queue position, Active Singer highlighted (avatar ring + label)
- Subscribes to `participant_role_changed` + `queue_updated` while panel is open
- Tappable any time, including during active songs (testing utility)
- No auto-show, no auto-hide
- Visible to everyone with stage.html access (not gated by role)

**Existing testing/admin affordances (kept as-is for Session 5):**

- Admin gear → Set-View-Coordinates dialog (gated by `profiles.is_platform_admin`)
- Debug LOG button (top-left, visible to all)
- Other developer testing surfaces

These will be redesigned when remote-control hardware lands — out of scope for Session 5.

### 4.3 Audience.html — frozen surface

Audience.html is **frozen for Session 5.** Bug fixes only; no new features.

**What's available on audience.html today:**

- Agora audio/video stream from the active singer's TV-stage composite
- Comments input (audience can send comments to the stage)
- Claps/cheers (audience reactions)
- Back-to-Elsewhere pill (visibility-gated per Session 5 Part 2c.3.2 — currently HHU only; spec intent revises to "all audience" but implementation requires a small change)

**What's deferred to post-Session-5:**

- Read-only queue display (audience can see who's queued)
- Browse venues / costumes for marketing
- NHHU registration / sign-up flow from audience deep-link return
- Migration into unified app as parameterized NHHU view

These features will land when the audience surface migrates into the unified HHU app (post-Session-5 architectural direction). Building them on audience.html in Session 5 creates parallel UI codebases that compound with each new feature.

### 4.4 Cross-screen patterns

**Back-to-Elsewhere pill** (singer.html, audience.html, games/player.html) — visibility rule:

- Today: Yes if HHU/HHM; No if non-HHU
- Spec intent (post Session 5 Part 2c.3.2 update): Yes for all users
- Behavior on tap differs by user type:
  - HHU/HHM: lands on their normal Elsewhere home (Mode A/B per state model)
  - NHHU audience: lands on placeholder Elsewhere home with "go back to where you were" + "explore Elsewhere" options (audience-to-NHHU conversion path)

This is a state model change. State model and karaoke spec land it together.

**Queue panel pattern parity:**

The Queue panel on stage.html follows the same UX pattern as the existing Comments panel:

- Bottom-right button cluster on stage.html
- Slide-out from right side
- Tap to toggle (open or close)
- Independent — Queue panel and Comments panel can be open or closed independently
- Both panels accessible any time during stage rendering, including mid-song

This consistency reduces user confusion and reuses the existing animation/dismiss conventions.

---

## 5. Implementation mapping

This section maps the spec's contents to specific implementation work in Session 5 sub-parts (2d, 2e, 2f) and post-Session-5. It identifies what ships when, what gets deferred, and what architectural decisions remain open for implementation passes.

### 5.1 Session 5 — Part 2d (karaoke/stage.html session integration)

**Sub-split:** 2d.1 (read/display, ~5 sections, ~2-2.5 hours) + 2d.2 (write/interact, depending on what the new model retains)

**2d.1 scope (read/display):**

- Session load on stage.html mount (per DECISION-1: query by tv_device_id, URL fallback)
- Graceful fallback to pre-Session-5 solo mode if no session (silent + log warning)
- Render queue panel (new bottom-right button + slide-out matching Comments pattern)
- Subscribe to realtime events: `participant_role_changed`, `queue_updated`, `session_ended`
- Active-singer highlight in queue (avatar ring + label per DECISION-4)
- "Up Next" card display between songs (avatar + name + song + venue per DECISION-3)
- Idle-state 360° venue tour with "Select and start a song" overlay
- Read-only consumption of session state — no user inputs on stage.html mutate state

**2d.2 scope (write/interact) — re-evaluated under new model:**

The original 2d.2 plan included manager override UI on stage.html (change venue mid-song, change costume mid-song, end song button). Per the new control model, these overrides live on the phone, not the TV. Stage.html in 2d.2 has minimal interactive surface.

What remains for 2d.2:

- Pre_selections loading on promotion (when `participant_role_changed` indicates a queue→active transition, load that user's pre-selections as initial stage state)
- End Session navigation (when `session_ended` fires, navigate stage.html back to tv2.html)
- Reaction logic for skip/take-over events (manager-driven from phone; stage.html responds to resulting events)

2d.2 may collapse into 2d.1 since stage.html has no direct user-input override controls. Decision deferred to 2d.1's pre-implementation audit.

### 5.2 Session 5 — Part 2e (karaoke/singer.html mode-aware)

This is the largest sub-part. Singer.html becomes role-aware per Section 4.1.

**Major work items:**

- Role detection: query session state on mount, determine user's current role (Active Singer / Available Singer queued / Available Singer not queued / Session Manager + role overlay)
- Conditional rendering of screen-home tiles based on role and queue state
- "Take Stage" prompt when promoted to Active Singer (tap-to-confirm, removable, no countdown)
- Push notification: "You are up — click here to take the stage" when phone backgrounded during promotion
- Available Singer queue position display
- "Add to Queue" / "Update My Song" UX based on queue membership
- Queue editing: Inactive Singer edits own entry (song / venue / costume / comments-toggle / remove)
- Phone-side venue preview for non-active singers (currently TV-only)
- Phone-side costume preview images for non-active singers
- Session Manager queue management UI (reorder, remove, force-promote, skip current/next, take over)
- Remove redundant "Leave" button from screen-home (Back-to-Elsewhere replaces it)
- Restart, Pause, Stop, End-Song semantics per Section 2 (Stop ≠ End Turn)
- Manager override mechanism implementation (per Section 2 implementation note — choose Option A/B/C in pre-implementation audit)

**Deferred (per Q-2B):**

- Manager picks song/venue/costume/mic on behalf of Active Singer (helper-for-elderly-relative scenario)

### 5.3 Session 5 — Part 2f (karaoke/audience.html session integration)

**Sub-part scope significantly reduced under new model.**

Original 2f plan included audience read-only queue display. Per the audience.html freeze decision, audience.html receives no new features in Session 5.

**Remaining 2f work (minimal):**

- Verify audience.html still functions correctly with new session lifecycle (test for regressions)
- Update Back-to-Elsewhere visibility rule from "HHU only" to "all audience users" (small change, removes household-membership gate on existing pill)
- Bug fixes only beyond this

2f may not need a dedicated implementation pass. It could land as part of 2e's verification work or as a small standalone commit.

### 5.4 Post-Session-5 — Audience-to-NHHU conversion path

When NHHU audience users tap Back-to-Elsewhere, they land on a placeholder Elsewhere home with these options:

- "Go back to where you were" — return to audience.html session (or last page they were on)
- "Stay on this page / Sign up" — register as NHHU, gain access to non-TV-required features (games, etc.)
- "Explore Elsewhere" — browse what's available

**Phase 1 placeholder (to be built in Session 5 alongside the karaoke spec):**

Minimum-viable placeholder Elsewhere home for NHHU returning from audience deep link. Just a static page with the two return options. Full conversion funnel (sign-up flow, app downloads, game launchers) lands post-Session-5.

This is captured as DEFERRED entry: "Audience-to-NHHU conversion path."

### 5.5 Post-Session-5 — Audience.html migration into unified app

**Architectural direction:** The unified Elsewhere app (currently the HHU experience) will eventually absorb audience.html as a parameterized view based on user context. NHHU users see the same UI fabric as HHU users; conditional rendering hides TV-required features and routes appropriately.

**Why this matters:**

- Single source of truth for new features (no parallel UI codebases)
- Consistent UX across HHU and NHHU
- Conversion path built into the app fabric (audience users see the same Elsewhere home, just with different tile states)

**When:** Post-Session-5. Triggered when NHHU-as-first-class-user feature work begins (games venues, wellness, etc.).

This is captured as DEFERRED entry: "Migrate audience.html into unified app as parameterized NHHU view."

**Constraint during migration window:** No new features land on audience.html. Bug fixes only. New audience-experience features build into the unified app.

### 5.6 Post-Session-5 — Manager helper feature (Q-2B)

**Scope:** Session Manager can pick a song / venue / costume on behalf of the Active Singer who needs help (e.g., older relative, accessibility need, network issue).

**Why deferred:** Adds non-trivial complexity to manager UI:
- Manager UI needs a "current Active Singer" view with full session controls
- Permission system must allow manager's selection to apply to Active Singer's slot
- UI handoff (manager picks song, it appears on TV as if Active Singer picked it)

**Workaround until built:** Manager takes the stage themselves (force-take-over) and then sings/configures. Or someone next to the elderly user uses their phone directly.

This is captured as DEFERRED entry: "Manager picks song/venue/costume on behalf of Active Singer."

### 5.7 Architectural decisions deferred to implementation passes

**Manager Override mechanism:** How the Session Manager's phone sends mid-song commands that affect the Active Singer's TV stage. Three options under consideration:

- **Option A:** Session Manager phone sends Supabase realtime command → Active Singer's phone listens and re-broadcasts as Agora to stage
- **Option B:** Session Manager phone gets direct stage-channel access; sends Agora commands directly
- **Option C:** New RPC layer for session-state mutations that publishes events stage.html consumes

Decision deferred to 2e implementation pass.

**Push notification mechanism:** "You are up — click to take stage" notification when phone is backgrounded.

- Web Push API requires service worker registration and user permission grant
- Native push requires app shell (Capacitor wrapper) configured for FCM/APNs
- Decision deferred — likely native via Capacitor since the iOS app shell already exists

**Take-over UI specifics:** When Session Manager force-takes-over, what does the displaced Active Singer see on their phone? Sudden state change with explanation? Toast notification? Undo affordance for the manager (within a few seconds)?

Decision deferred to 2e implementation pass.

### 5.8 Implementation summary by sub-part

| Sub-part | Status | Scope |
|---|---|---|
| 2a | ✓ SHIPPED (commit `d1b4edd`) | 5 new publishers in shell/realtime.js |
| 2b | ✓ SHIPPED (commit `601d125`) | Session lifecycle wiring |
| 2c.1 | ✓ SHIPPED (commit `daa8718`) | User preferences storage |
| 2c.2 | ✓ SHIPPED (commit `0a3a9ea`) | Post-login home unification + proximity banner |
| 2c.3.1 | ✓ SHIPPED (commit `e4a348e`) | Active-session rendering + rejoin + cross-app switch |
| 2c.3.2 | ✓ SHIPPED (commit `5617689`) | Back-to-Elsewhere visibility across play-pages |
| 2d.1 | PENDING | Stage.html read/display (queue panel, realtime subs, idle state, "Up Next" card) |
| 2d.2 | PENDING — possibly collapses into 2d.1 | Stage.html state mutation handlers (pre-selections load, navigation on session_ended) |
| 2e | PENDING — largest remaining sub-part | Singer.html role-aware (most of this control model's net-new work) |
| 2f | PENDING — significantly reduced | Audience.html session lifecycle verification + Back-to-Elsewhere visibility rule update |

Total Session 5 scope after this control model: 2d, 2e, 2f. Estimated remaining time depends on how 2d.2 collapses and the 2e architectural decisions; rough estimate is 6-10 hours of focused work across all three sub-parts.

### 5.9 Documents updated alongside this spec

When this control model lands, the following docs need synchronized updates:

- `docs/PHONE-AND-TV-STATE-MODEL.md` — HHU/NHHU framing changes, Mode C revisions, tile state matrix updates, Back-to-Elsewhere visibility rule change, architectural direction note for audience.html
- `docs/SESSION-5-PART-2-BREAKDOWN.md` — re-scope 2d (sub-split or collapse), 2e (largest), 2f (minimal); update status line
- `docs/DEFERRED.md` — add seven entries:
  1. Manager picks song/venue/costume on behalf of Active Singer (Q-2B helper feature)
  2. Audience-to-NHHU conversion path (placeholder Elsewhere home)
  3. Audience.html freeze (no new features in Session 5)
  4. Migrate audience.html into unified app as parameterized NHHU view
  5. Audience browsing of venues/costumes for marketing
  6. Audience read-only queue display
  7. Manager Override mechanism design (architectural decision)
- `docs/SESSION-5-HANDOFF.md` — point at this control model as the spec source for 2d/2e/2f implementation
