# Karaoke Control Model

**Created:** 2026-04-25
**Updated:** 2026-04-29 (vocabulary-trap callout added; phase status synced to 2e.2 shipped)
**Purpose:** Defines the role hierarchy, state machine, and permission matrix for karaoke sessions in Elsewhere. Specifies what each role can do, how transitions happen, and how the manager intervenes when needed.
**Scope:** karaoke/singer.html and karaoke/stage.html. References audience.html as a frozen surface (no new features in Session 5).
**Anchored to:** `docs/PHONE-AND-TV-STATE-MODEL.md` (platform-level user model). Where this doc references HHU, HHM, household admin, proximity, or Modes A/B/C, those concepts are defined in the state model. This doc does not redefine them.
**Referenced by:** `docs/SESSION-5-PART-2-BREAKDOWN.md` 2d, 2e, 2f sub-parts.

---

## ⚠️ Critical vocabulary trap: "audience"

**The word "audience" means two different things in karaoke and they get conflated constantly.** This callout is the single most important thing in this doc. Read it before reading anything else, and re-read it any time a manager-action discussion uses the word "audience."

There are two distinct meanings:

### Schema-state `'audience'` (database value)

`session_participants.participation_role = 'audience'` — a database enum value meaning "this user is in the session but is neither the active singer nor in the queue." It is a state, not a role label.

Users with this schema state include both:

- **Available Singers who haven't queued yet** — HHU + at home + has TV device. Eligible to sing. Hasn't tapped Add to Queue. Surface-label: "Available Singer (not queued)."
- **Actual non-singing audience members** — NHHU, OR HHU not at home, OR HHU without a TV device. Cannot sing. Surface-label: "Audience."

The schema does not distinguish these two populations because the underlying queue/promotion logic doesn't need to. Eligibility is computed client-side at the moment of action (Add to Queue, Start Song, etc.).

### Surface-label "Audience" (UI role)

A karaoke UI role meaning "watching only, cannot sing." Lives on `audience.html`. Applied to NHHU users, or HHU users not at home, or HHU users without a TV device. **These users have no path to the queue, no path to active, and the manager UI cannot promote them.**

### What this means for manager actions in this doc

When this doc says "force-promote from audience," "promote an audience user," or anything similar — it is *always* talking about the schema state, never the surface label. The user being acted on is an Available Singer in disguise (HHU at home with a TV device whose `participation_role` happens to be `'audience'` because they haven't queued yet).

The manager UI on singer.html operates only on rows in `session_participants`. Surface-label Audience users on `audience.html` don't appear in that table in any actionable way — see Section 4.3 (audience.html freeze). So there is no path by which a manager could force-promote a "can't sing" user; the schema makes this impossible by construction. Combined with the doctrine that singer.html is HHU-eligible by construction (model audit Path A), every `'audience'` row the manager sees on singer.html is, by construction, an Available Singer.

### Reading rule

- See `'audience'` in code voice or schema discussion (backticks, `participation_role = 'audience'`, "schema-state audience") → **schema state**. Includes both populations. Manager UI can act on these rows.
- See "Audience" capitalized as a UI role label (in role tables, surface vocabulary, UX copy) → **surface label**. Watching-only users on audience.html. Manager UI cannot act on them.
- When in doubt, the four-role table in Section 1 below is canonical. Refer back.

If you find yourself thinking "but audience users can't sing — why is the manager promoting them?" — the language tripped you. Re-read it as the schema state.

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

### Two layers of vocabulary

Karaoke uses two layers of role vocabulary that map cleanly to each other but live in different parts of the system:

**Platform layer — `participation_role` (database schema).** A three-value enum stored in `session_participants.participation_role`: `active`, `queued`, `audience`. This is universal across all apps (karaoke, games, future wellness). The platform doesn't know what "singing" means; it just tracks who's in the active slot, who's waiting, and who's watching.

**Karaoke UI layer — role labels.** The four labels above (Session Manager, Active Singer, Available Singer, Audience) are karaoke-specific UI mappings, computed in client code from `(participation_role, control_role, household_membership, proximity, has_tv_device)`. Each app does its own mapping; the platform doesn't need to know.

The mapping for karaoke:

| Karaoke UI label | `participation_role` | Additional client-side conditions |
|---|---|---|
| Active Singer | `active` | (none) |
| Queued (sub-state of Available Singer) | `queued` | HHU + at-home + has TV device |
| Available Singer (not queued) | `audience` | HHU + at-home + has TV device |
| Audience | `audience` | NHHU, OR HHU not at home, OR no TV device |

> **⚠️ Reminder:** the bottom two rows both have `participation_role = 'audience'` in the database, but they are different surface-level roles. Available Singer (not queued) is eligible to sing; Audience is not. See the vocabulary trap callout at the top of this doc. Manager actions on `'audience'` rows always operate on the Available Singer population — Audience users (the watching-only role) live on audience.html and are not reachable from the manager UI.

Eligibility (the "Available Singer" vs "Audience" distinction) is **a client-side, self-only derivation**. Each user computes their own eligibility for their own UI. No cross-user eligibility check is ever required because Session Manager only promotes from queue, and queue entry is self-gated by eligibility at the moment a user taps "Add to Queue."

Session Manager is orthogonal to `participation_role`. It's tracked via `control_role` (separate schema column with values `manager`/`host`/`none`). A Session Manager can simultaneously be an Active Singer, Available Singer, or Audience.

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

**Manager intervention powers (overview; see vocabulary trap at top):**

The Session Manager has cross-user authority on any `session_participants` row. Manager actions on a row with `participation_role = 'audience'` always operate on an Available Singer (per the singer.html HHU-eligibility doctrine — surface-label Audience users live on audience.html and aren't reachable here).

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

**Just-finished singer transitions out, queue empty (Idle state begins):**

When a song ends, the just-finished singer transitions out of the Active Singer slot regardless of queue state. Their `participation_role` flips from `active` to `audience`. The karaoke UI label they get on their phone re-derives to "Available Singer" (because they're an HHU at home with a TV device).

If the queue is empty at that moment, the Active Singer slot is now empty → **Idle state begins**. The TV enters a 60-second social window where the room can applaud, comment, or just talk. During this window, any Available Singer (including the just-finished one) can start a new song to become the new Active Singer immediately.

After 60 seconds with no action, the TV begins the 360° venue tour with the "Select and start a song to sing next!" overlay. Any Available Singer can still start a song any time during the tour, transitioning back into Active Singer.

The just-finished singer's phone UI does not change visibly during this transition — they were already on screen-performing → screen-home (handled by the existing Agora `song-ended` message), and their action hub remains available. The role transition is a backend correctness concern, not a user-facing UI change.

The Session Manager retains "Skip current Active Singer" authority for the case where someone is mid-song; once Idle, there's no Active Singer to skip.

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

### Manager intervention powers (full list)

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
- **Force-promote a queued user to Active Singer:** pulls a specific queued user out of order, makes them active immediately.
- **Force-promote an Available Singer (schema-state `'audience'`) directly to Active Singer:** see vocabulary-trap callout at top of doc. This acts on a `participation_role='audience'` row that, by HHU-eligibility doctrine on singer.html, is an Available Singer who hasn't queued yet. Not on a Surface-label Audience user — that's a separate population on audience.html and isn't reachable from the manager UI.
- **Take over active singer slot:** Session Manager promotes themselves (or another specific person) to Active Singer immediately, displacing the current Active Singer if any.

**Session-level interventions:**

- **End Session entirely:** triggers `rpc_session_end`, ending the session for everyone. Session Manager only.

### Manager Override mechanism — implementation note

Currently no implementation exists for the manager override mechanism. All mid-song singer controls send via Agora data streams (`sendToStage(obj)`) from the Active Singer's phone to stage.html. There is no path today for Session Manager's phone to send equivalent commands.

The 2e implementation needs to design this mechanism. Options under consideration:

- **Option A:** Session Manager's phone sends a Supabase realtime command that the Active Singer's phone listens for and re-broadcasts as Agora to stage.
- **Option B:** Session Manager's phone gets direct stage-channel access and sends Agora commands directly.
- **Option C:** New RPC layer for session-state mutations that publishes events stage.html consumes.

**Status: locked to Option B in the 2e audit (`docs/SESSION-5-PART-2E-AUDIT.md` — Locked Decisions appendix).** Manager phone joins Agora as silent host with mic-mute discipline. Implementation in 2e.3.

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

Audience.html is frozen for Session 5: regression fixes only — fix things that were working and stopped working. No new features, no spec-compliance updates, no design-decision reversals, no polish. Defer all other changes to the unified-app consolidation. Audience capabilities in this matrix reflect what's available in audience.html today. Where the spec intent goes beyond what audience.html currently supports, those rows are flagged as deferred to post-Session-5 unified-app migration.

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

**Removed in 2e.2:** the "Leave"/"Home" tile (`screen-home`) was redundant with Back-to-Elsewhere and was removed.

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
- Force-promote a specific queued person to Active Singer
- Force-promote a specific Available Singer (schema-state `'audience'` row — see vocabulary-trap callout at top) directly to Active Singer
- Force-start a song on the Active Singer's behalf (deferred per Q-2B helper feature)

**Footnote 2.11–2.13 — Manager Override mechanism:** Locked to Option B — manager phone joins Agora as silent host. See Section 2's "Manager Override mechanism — implementation note" and `docs/SESSION-5-PART-2E-AUDIT.md`. Implementation in 2e.3.

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

(Note: "Available Singer (not queued)" has `participation_role = 'audience'` in the schema. See vocabulary trap at top of doc.)

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
- Panel content per row: **avatar + name + queue position + song + venue**. Active Singer highlighted with avatar ring + label
- Avatar uses initials + color hash (no `profiles.avatar_url` column in Phase 1)
- Reads `pre_selections.song.title`, `pre_selections.song.artist`, `pre_selections.venue.name` for each participant
- Subscribes to `participant_role_changed` + `queue_updated` while session is loaded (NOT panel-scoped — subscription persists across panel open/close)
- Tappable any time, including during active songs (testing utility)
- No auto-show, no auto-hide
- Visible to everyone with stage.html access (not gated by role)
- The same queue list rendering component is reused on Session Manager's phone UI in 2e.3 (with action affordances overlaid for reorder/remove/promote)

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

### 5.1 Session 5 — Part 2d (karaoke/stage.html session integration) — SHIPPED

**Sub-split:** 2d.0 (prerequisite migration, ~1-1.5 hours) + 2d.1 (read/display + event-driven mutations, ~6-8 sections, ~3-4 hours). 2d.2 collapsed into 2d.1 per audit (`docs/SESSION-5-PART-2D-AUDIT.md` DECISION-AUDIT-2).

**2d.0 — prerequisite migration (db/013):**

Two new SECURITY DEFINER RPCs that unblock 2d.1 against existing RLS gates:

- `rpc_karaoke_song_ended(p_session_id)` — atomic dual transition (active→audience, queue head→active). Idempotent. Stage.html calls this on YouTube video end.
- `rpc_session_get_participants(p_session_id)` — returns participant rows with `display_name` joined from profiles (bypasses owner-only profiles RLS).

Auth gate on both: `is_session_participant(session_id) OR is_tv_household_member(tv_device_id)`. See `docs/SESSION-5-PART-2D-AUDIT.md` DECISION-AUDIT-6.

**2d.1 scope (session-aware stage):**

"Read-only" in 2d.1 means **no user-input mutators** (no buttons that change session state). Event-driven mutations are part of the scope — stage.html responds to its own internal events (YouTube video ended) and to received realtime events.

- Session load on stage.html mount (query by tv_device_id, with URL fallback)
- Graceful fallback to pre-Session-5 solo mode if no session (silent + log warning; dev/legacy only — production always has session via 2b)
- Render queue panel (new bottom-right button + slide-out matching Comments pattern, content per § 4.2)
- Subscribe to realtime events: `participant_role_changed`, `queue_updated`, `session_ended`
- Active-singer highlight in queue (avatar ring + label)
- "Up Next" card display during inter-song transitions (avatar + name + song + venue from queue head's pre_selections)
- Idle-state behavior: 60-second social window after song ends with empty queue, then 360° venue tour with "Select and start a song to sing next!" overlay
- Pre_selections loading on promotion (when `participant_role_changed` indicates a queue→active transition, the new active singer's pre_selections become the initial stage state)
- Song-end RPC trigger: stage.html calls `rpc_karaoke_song_ended` when YouTube video ends, with `_currentSongInstanceId` double-fire guard
- `session_ended` graceful teardown: `doEnd()` → `stopStageRealtimeSub()` → navigate to tv2.html
- Migration-window grace: stage.html sends `sendMsg({type:'session-ended'})` Agora message before teardown so singer.html can respond before its own session_ended subscription lands in 2e

**Key implementation notes:**

- Solo mode (no session in DB) preserves Way 1 (legacy QR + room code path) verbatim. Way 1 removal deferred post-Session-5.
- Realtime subscription is bound to the loaded session, not to queue panel open/close (idiomatic per `index.html`'s 2c.3.1 pattern).
- `wireExitAppListener` (2b) is unchanged; the new realtime subscription is an independent channel instance on the same `tv_device:<device_key>` topic.
- Room code displayed in idle-panel and singer-link QR is overridden from `sessions.room_code` when a session is loaded; falls back to URL `ROOM_CODE` in solo mode.

Full implementation contract in `docs/SESSION-5-PART-2D-AUDIT.md`.

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
- Session Manager queue management UI: reorder, remove, force-promote queued user, force-promote Available Singer (schema-state `'audience'` row — see vocabulary-trap callout at top), skip current/next, take over
- Remove redundant "Leave"/"Home" tile from screen-home (Back-to-Elsewhere replaces it)
- Restart, Pause, Stop, End-Song semantics per Section 2 (Stop ≠ End Turn)
- Manager override mechanism implementation (Option B locked — manager phone joins Agora as silent host with mic-mute discipline)

**Phase status:**

- **2e.0** — push notification infrastructure: ✓ SHIPPED
- **2e.1** — read-only role-aware UI: ✓ SHIPPED
- **2e.2** — self write actions (queue, leave, update song, start song; promotion push trigger; Take Stage modal): ✓ SHIPPED (singer.html v2.110)
- **2e.3** — manager queue management UI + Manager Override (Option B): PENDING (next session, ~3-4 hr)

**Deferred (per Q-2B):**

- Manager picks song/venue/costume on behalf of Active Singer (helper-for-elderly-relative scenario)

### 5.3 Session 5 — Part 2f (karaoke/audience.html session integration)

**Sub-part scope significantly reduced under new model.**

Original 2f plan included audience read-only queue display. Per the audience.html freeze decision, audience.html receives no new features in Session 5.

**Remaining 2f work (minimal):**

- Verify audience.html still functions correctly with new session lifecycle (test for regressions)
- Update Back-to-Elsewhere visibility rule from "HHU only" to "all audience users" (small change, removes household-membership gate on existing pill)
- Bug fixes only beyond this

2f may not need a dedicated implementation pass. It could land as part of 2e.3's verification work or as a small standalone commit.

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

**Constraint during migration window:** No investment in audience.html. Defer all features and all fixes other than regressions (things that were working and stopped working). New audience-experience features build into the unified app.

### 5.6 Post-Session-5 — Manager helper feature (Q-2B)

**Scope:** Session Manager can pick a song / venue / costume on behalf of the Active Singer who needs help (e.g., older relative, accessibility need, network issue).

**Why deferred:** Adds non-trivial complexity to manager UI:
- Manager UI needs a "current Active Singer" view with full session controls
- Permission system must allow manager's selection to apply to Active Singer's slot
- UI handoff (manager picks song, it appears on TV as if Active Singer picked it)

**Workaround until built:** Manager takes the stage themselves (force-take-over) and then sings/configures. Or someone next to the elderly user uses their phone directly.

This is captured as DEFERRED entry: "Manager picks song/venue/costume on behalf of Active Singer."

### 5.7 Architectural decisions

**Manager Override mechanism:** locked to Option B in 2e audit. Manager phone joins Agora as silent host (`setClientRole('audience')` initially, upgrade to `'host'` only when sending data-channel commands), with mic-mute discipline. Implementation in 2e.3.

**Push notification mechanism:** locked in 2e.0 and shipped end-to-end in 2e.2. Capacitor `@capacitor/push-notifications` + APNs HTTP/2 via Edge Function `send-push-notification`. Postgres trigger on `session_participants` UPDATE (queued→active only) fires `pg_net.http_post` to Edge Function. Operational on iOS Capacitor app, sandbox cert. Production cert flip pending.

**Take-over UI specifics:** When Session Manager force-takes-over, what does the displaced Active Singer see on their phone? Per 2e.3 framing, the cheap path is "silent flip — role-aware UI re-renders." Toast/explanation is a polish addition deferred post-2e.

### 5.8 Implementation summary by sub-part

| Sub-part | Status | Scope |
|---|---|---|
| 2a | ✓ SHIPPED (commit `d1b4edd`) | 5 new publishers in shell/realtime.js |
| 2b | ✓ SHIPPED (commit `601d125`) | Session lifecycle wiring |
| 2c.1 | ✓ SHIPPED (commit `daa8718`) | User preferences storage |
| 2c.2 | ✓ SHIPPED (commit `0a3a9ea`) | Post-login home unification + proximity banner |
| 2c.3.1 | ✓ SHIPPED (commit `e4a348e`) | Active-session rendering + rejoin + cross-app switch |
| 2c.3.2 | ✓ SHIPPED (commit `5617689`) | Back-to-Elsewhere visibility across play-pages |
| 2d.1 | ✓ SHIPPED | Stage.html read/display (queue panel, realtime subs, idle state, "Up Next" card) |
| 2e.0 | ✓ SHIPPED | Push notification infrastructure (Capacitor + APNs + Edge Function) |
| 2e.1 | ✓ SHIPPED | Read-only role-aware UI on singer.html |
| 2e.2 | ✓ SHIPPED (singer.html v2.110) | Self write actions on singer.html (queue, leave, update song, start song) + promotion push trigger end-to-end |
| 2e.3 | PENDING — next session | Manager queue management UI + Manager Override (Option B) |
| 2f | PENDING — significantly reduced | Audience.html session lifecycle verification + Back-to-Elsewhere visibility rule update |

Total Session 5 scope after this control model: 2e.3, 2f. Estimated remaining time: 4-6 hours of focused work.

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
  7. Manager Override mechanism design (architectural decision) — RESOLVED: Option B locked in 2e audit
- `docs/SESSION-5-HANDOFF.md` — point at this control model as the spec source for 2d/2e/2f implementation
