# Karaoke Function Audit

**Created:** 2026-04-25
**Purpose:** Inventory of `karaoke/singer.html` and `karaoke/stage.html` functionality before the 2d control-model spec work. Pure description — no recommendations, no proposed changes.
**Scope:** State as of commit `0a127db` (post-2c, pre-2d). Both files reflect the **pre-Session-5 single-singer model**: there is no existing active/inactive participant distinction, no queue, no manager/host concept beyond `profiles.is_platform_admin`.

---

## karaoke/singer.html

**Size:** ~1860 lines.

### Shell module dependencies

| Module | Loaded at | Source |
|---|---|---|
| `shell/auth.js` | line 556 | added Session 4.10.3 Part B |
| `shell/realtime.js` | line 557 | added Session 5 Part 1c |

### External dependencies

- Agora RTC SDK (CDN; primary + jsDelivr fallback)
- DeepAR (CDN, for face filters/effects)

### Screens (state branches)

The page uses a screen-based system managed by `showScreen(id)`. Ten screens defined; nine functional, one placeholder:

| Screen ID | Purpose |
|---|---|
| `screen-join` | Initial room-code entry (4.10 deep-link can pre-fill) |
| `screen-home` | Main hub after joining: action tile grid |
| `screen-search` | Song search (text + voice) |
| `screen-voice` | Voice-search active state |
| `screen-confirm` | Confirm selected song before performing |
| `screen-countdown` | 3-2-1 countdown before song starts |
| `screen-performing` | Active during song playback |
| `screen-mic` | Mic device + FX settings |
| `screen-costume` | DeepAR costume + accessories picker |
| `screen-postsong` | Placeholder; currently empty (line 530) |

**No queue, audience, inactive, or wait-state screens. No active/inactive singer distinction.**

### UI capabilities by screen

**screen-join**
- Enter room code → `doJoin()`
- Input auto-formatted to uppercase alphanumeric

**screen-home** (post-join hub)
- Tap "Search Song" → screen-search
- Tap "Mute Home" → `toggleHomeMute()`
- Tap "Leave" → external link to tv2.html
- Tap "Invite" → `doInvite()` (share/copy)
- Tap "Stage Settings" → `showStageOverlay()` (venue picker + view tabs)
- Tap "Costumes" → `showSingerCostumePicker()`
- Tap mic gear → screen-mic
- Toggle "Video Chat with Audience" → `toggleVideoChat()`

**screen-search**
- Text input search (debounced) → `doSearch()`, `onSearchInput()`
- Voice search → `startVoiceFullscreen()`
- Result list select → `selectResult(r)`
- Recent searches → `renderRecent()`, `useRecent(q)`
- Clear search → `clearSearch()`
- Demo songs builder → `buildDemos()`
- Back → screen-home

**screen-voice**
- Cancel → returns to screen-search

**screen-confirm**
- Confirm song → screen-countdown (`confirmSong()` → `goToCountdown()`)
- Back / Search Again → screen-search

**screen-countdown**
- Pause/resume → `toggleCdPause()`
- Cancel → `cancelCd()` → screen-home
- 3-2-1 elapse → `startLyrics()` → screen-performing

**screen-performing**
- Pause/resume → `perfPauseToggle()`
- Stop → `perfStop()`
- Restart → `perfRestart()`
- Stage view toggle (singer ⇄ audience) → `toggleStageView()`
- Pan camera left/right → `sendPanLeft()`, `sendPanRight()`
- Zoom toggle → `toggleZoom()`
- Mute mic → `toggleMutePerf()`
- Lyrics: pause, restart, seek → `toggleLyricPause()`, `lyricRestart()`, `lyricSeek(dir)`
- Comments → `togglePerfComments()`
- Quick costume → `showPerfCostumePicker()`

**screen-mic**
- Pick microphone device → `switchMicDevice(deviceId)`
- Refresh device list → `populateMicList()`
- Mute toggle → `toggleMute()`
- Volume slider → `setVolume(v)`
- FX toggles (4): reverb, echo, boost, deep → `toggleFx(name)`
- Back → screen-home

**screen-costume**
- Costume accessories grid (cumulative selection) → `singerToggleAccessory(id)`
- DeepAR effects grid → `toggleDeepAREffect(eff)`
- Clear all accessories → `sendClearAllAccessories()`
- Clear all DeepAR effects → `clearAllDeepAREffects()`
- Back → screen-home

**Cross-screen overlays**
- Stage overlay (venue picker + view tabs): `showStageOverlay()`, `hideStageOverlay()`, with `selectVenue(v)`, `requestVenueTour(venueId)`, `setVenuePreviewView(view)`, `sendVenuePan(delta)`
- Performance-mode costume picker: `showPerfCostumePicker()` / `hidePerfCostumePicker()`
- Lyrics preview: `showLyricPreview()`
- Back-to-Elsewhere pill (2c.3.2; visibility-gated)
- Debug log panel: `toggleSingerLog()`

### Agora data-stream messages SENT to stage

Sent via `sendToStage(obj)` (line 651). Message types observed:

| Type | When |
|---|---|
| `mic-connected` | After successful Agora join + mic publish |
| `tv-search` | Search input change (with results array) |
| `tv-search-clear` | Search cleared |
| `tv-result-highlight` | User taps a result (before confirming) |
| `song-select` | Song confirmed (videoId, title, artist, thumb, lyrics, isDemo) |
| `start-countdown` | Confirm → countdown |
| `countdown-pause` / `countdown-resume` / `countdown-cancel` | Countdown controls |
| `lyrics-start` / `lyrics-resume` / `lyrics-pause` / `lyrics-restart` / `lyrics-seek` | Lyrics controls |
| `pause` / `resume` / `restart-song` / `stop-song` | Playback control |
| `set-deepar-effect` / `clear-deepar-effects` | DeepAR effects |
| `toggle-accessory` / `clear-accessories` | Costume accessories |
| `set-venue` | Venue selection |
| `venue-tour` | Trigger 360° venue tour |
| `set-view` | Singer-view ⇄ Audience-view |
| `singer-pan` / `venue-pan` | Camera/panorama panning |
| `zoom-in` / `zoom-out` | Stage zoom |
| `toggle-comments` | Toggle TV comment bar |
| `video-chat-open` / `video-chat-close` | Video chat tile |

### Agora data-stream messages RECEIVED from stage

Handled by `handleStageMsg(msg)` (line 688). Types:
- `song-ended` — mute mic + return to screen-home

### Realtime (Supabase) publishers
- `publishExitApp(device_key)` — called from `handleBackToElsewhere()` (Session 4.10.3 Part B)

### Realtime (Supabase) subscribers
- None

### Supabase RPC calls
- None

### sessionStorage usage
- Read `elsewhere.active_tv.device_key` (in `handleBackToElsewhere`)
- Remove same key on back-nav

---

## karaoke/stage.html

**Size:** 5254 lines.

### Shell module dependencies

| Module | Loaded at | Source |
|---|---|---|
| `shell/auth.js` | line 13 | Session 4.10 production auth |
| `shell/realtime.js` | line 14 | Session 5 Part 1c |
| `shell/venue-settings.js` | line 15 | venue tuning helpers |

### External dependencies

- Agora RTC SDK (CDN; primary + jsDelivr fallback)
- GSAP (CDN, animations)
- Three.js (CDN, panorama rendering)
- MediaPipe `selfie_segmentation` + `face_mesh` + `pose` (CDN)
- DeepAR
- YouTube IFrame API (loaded dynamically via `loadYouTubeAPI()`)

### States / modes

stage.html does **not** use a screen-based system. It has overlay-driven states based on what is currently visible / active:

| State | Trigger |
|---|---|
| **Idle** | Default after enterStage; `idle-panel` visible (room QR + scan-to-join prompt) |
| **Tour mode** | Admin venue tour (`startVenueTour` → `cancelVenueTour`) |
| **Pre-song** | Singer connected and searching/selecting; `tv-search` overlay or `tv-song-card` visible |
| **Countdown** | 3-2-1 (`startCountdown`) before song begins |
| **Song-playing** | YouTube video plays; lyrics ticker active (`startLyricsTicker`); progress reported |
| **Between songs** | After `doEnd()`, returns to idle until next song-select |

State transitions are driven by:
- Singer's Agora messages (`handleAudienceMsg(msg)` at line 3294)
- TV-side admin controls (gear → venue tuning + quality picker)
- Local handlers (`startCountdown`, `doPlay`, `doPause`, `resetPlay`, `doEnd`, etc.)

**No explicit "active singer" / "inactive singer" / "queued singer" state. Single-singer model — the active singer is whoever is currently connected as the Agora publisher.**

### Visible UI elements / controls

**Top bar (`#bar`):**
- Camera-off indicator (`#sdot`, `#slbl`)
- Room code display + click-to-copy (`#rcode-wrap`, `#rcode`)
- QR toggle (`#qr-toggle`) → `showSongs()`
- Watcher count (`#adot`, `#albl` — "N watching 👀")
- Version badge (`v2.99`)
- Head-tracking toggle (`#htoggle`) — debug visibility, auto-hidden in prod
- View mode toggle (`#vtoggle`) — Singer View ⇄ Audience View
- Admin gear (`#admin-gear`) — visible only when `profiles.is_platform_admin = true`

**Stage canvas + overlays:**
- Venue background (panorama; Three.js)
- Camera composite (singer composited onto stage via segmentation mask)
- DeepAR effects on singer
- Lyrics overlay (`#lw` / `#lm` / `#ln`)
- Comment bar (`#comment-bar` — toggle via singer's `toggle-comments`)
- Video chat tiles wrap (`#videochat-wrap`)
- Reactions (`#rx` — emoji rain)
- Idle panel (`#idle-panel` — QR + scan prompt + room code)
- TV search overlay (`#tv-search`, `#tv-results-grid`)
- TV song card (`#tv-song-card`)
- Stage venue picker (idle-only) — `showStageVenuePicker()` / `hideStageVenuePicker()`
- Quality picker overlay (`#quality-overlay`) — `showQualityPicker()`
- Costume picker overlay — `showCostumePicker()`
- Venue effect tray (gesture-controlled) — `showVenueEffectTray()`, `processTrayGesture()`
- Guide overlay (gesture instructions) — `showGuide()`
- Venue transition splash (`#venue-transition`) — `showVenueTransition()`
- Set View Coordinates dialog (admin-only, `#coords-dialog`) — `openCoordsDialog()`
- Admin menu dropdown (`#admin-menu`) — `toggleAdminMenu()`

### Admin menu items
- "Set View Coordinates" → `openCoordsDialog()` (saves yaw/pitch tuning per venue per app, plus optional global default)

### Agora data-stream messages RECEIVED from singer

Processed by `handleAudienceMsg(msg)` at line 3294. Message-type set mirrors singer.html's `sendToStage` payload list above (search, song-select, countdown, lyrics, playback, deepar, accessories, venue, view, pan, zoom, comments, video-chat).

### Agora data-stream messages SENT
- `progress` — playback progress (percentage + elapsed seconds), via `updP()` in `sendMsg()` (line 3267)

### Realtime (Supabase) publishers
- None

### Realtime (Supabase) subscribers
- `exit_app` on `tv_device:<device_key>` channel — wired via `wireExitAppListener` from `shell/realtime.js` (line 5245). The handler `onExit()` at line 5216 (Session 5 Part 2b extension, commit `601d125`):
  - Reads `device_key` from localStorage
  - Queries `tv_devices.id` by device_key, then `sessions` for active session on that TV
  - If session is live → log + stay on stage
  - Else (no session, query failed, dev/direct-nav) → `location.href = '../tv2.html'`

### Supabase queries / RPC calls

| Call | Location | Purpose |
|---|---|---|
| `sb.from('profiles').select('is_platform_admin')` | line 4934 | Admin gear visibility check |
| `sb.from('venue_defaults').select('*')` | line 5036 | Venue tuning load (yaw/pitch) |
| `sb.from('karaoke_venue_settings').select('*')` | line 5037 | Per-app venue override load |
| `sb.from('tv_devices').select('id')` | line 5222 | exit_app handler — TV identity lookup |
| `sb.from('sessions').select('id')` | line 5225 | exit_app handler — active-session check |

**No `rpc_session_*` RPC calls. No `session_participants` queries. No `pre_selections` reads or writes.**

### sessionStorage usage
- None

### localStorage usage
- `elsewhere.tv.device_key` — read by `wireExitAppListener` (TV-side identifier set during TV claim)

---

## Cross-cutting observations

- **Single-singer model is universal across both files.** Neither has any concept of multiple participants, queue position, role transitions, or session-aware participant state. The "active singer" today is implicit: whoever is currently connected as the Agora publisher.
- **Singer ⇄ stage coordination is Agora-only.** They communicate exclusively via Agora data streams (`sendStreamMessage`), not Supabase realtime broadcasts. The Supabase `tv_device:<device_key>` channel is reserved for cross-page coordination events (`launch_app`, `exit_app`, `session_handoff`, `session_started`, `session_ended`) — singer/stage don't currently use it for inter-device messaging.
- **No `rpc_session_*` calls anywhere in karaoke today.** All session lifecycle (start, end, join, leave, role changes) happens on `index.html` (phone home) and `tv2.html`. Karaoke is downstream of session management, not a participant.
- **Admin distinction is only `profiles.is_platform_admin`.** There is no app-level manager/host concept yet. The admin gear gates the Set-View-Coordinates dialog, which is venue tuning — unrelated to session control.
- **Existing 2b wiring on stage.html** (commit `601d125`) is read-only: it queries the sessions table to decide whether to stay or navigate on `exit_app`. No write operations to session tables.
- **Pre-selection concepts (song, venue, costume) exist as singer-side ephemeral state.** The singer picks venue + costume + searches for a song in their own UI flow; results are pushed to stage via Agora messages. Nothing is persisted to a `pre_selections` JSONB column today — that schema field exists on `session_participants` (db/008) but is not yet read or written by either karaoke page.

---

## Active Singer Mid-Song Controls (Detailed)

**Audit date:** 2026-04-25
**Scope:** Every control visible/accessible to the singer while a song is actively playing — i.e., while `screen-performing` is the active screen, plus any overlay surfaces that can slide over it.

**Role/auth gating overall:** Pre-Session-5 single-singer model. Whoever is on this device IS the singer. **No app-level role/auth gating on any mid-song control.** The only ambient gating is the Back-to-Elsewhere pill (Session 5 Part 2c.3.2 visibility heuristic on `isLikelyHouseholdMember`), which is page-wide, not specific to active-singer state.

### Layout summary

`screen-performing` markup is at lines 443-509 of singer.html. The screen is single-column, divided into top-down regions:

1. Header / Now Playing display (read-only)
2. Big Mute button (`#perf-mute-wrap`)
3. Progress bar (`#perf-prog-wrap`, read-only)
4. Lyrics preview + lyrics controls (`#perf-lyric-preview`, `#perf-lyrics-btn`, `#lyric-transport`)
5. Action grid (`#perf-actions`)
6. Bottom row: watchers (read-only) + comments toggle

Plus three cross-screen surfaces that can appear over screen-performing:
- Performance costume overlay (`#perf-costume-overlay`) — slides up via `showPerfCostumePicker()`
- Back-to-Elsewhere pill (top-right, fixed)
- Debug LOG button (top-left, fixed) → opens `#singer-dbg-panel` log overlay

---

### 1. Now Playing header (read-only)

- **Label:** "Now Playing" + song name + green "Live" pill
- **DOM:** `#perf-nav` containing `#perf-sname` (song name) + `.pill.ok` (Live indicator with `.pdot`)
- **Handler:** none
- **State effect:** none — text populated when song starts
- **Visibility:** always during song
- **Gating:** none

### 2. Big Mute button — primary mic control

- **Label:** "🎤 Tap to mute" / "🔇 Tap to unmute" (text in `#perf-mute-txt`)
- **DOM:** `#perf-mute-btn` inside `#perf-mute-wrap`; icon `#perf-mute-icon`, text `#perf-mute-txt`
- **Handler:** `toggleMutePerf()` (line 834) → calls `toggleMute()` → `muteMic()` / `unmuteMic()`
- **State effect:**
  - Local: sets `muted` flag, mutes the audioCtx gain node, calls `micAudioTrack.setVolume(0)` on Agora track
  - Sends to TV: NO direct Agora message; the muted Agora track is the signal
- **Visibility:** always during song
- **Gating:** none

### 3. Progress bar (read-only)

- **DOM:** `#perf-prog-track` containing `#perf-prog-fill`
- **Handler:** none
- **State effect:** display-only — animated by song-progress events delivered from stage.html via Agora `progress` messages
- **Visibility:** always during song
- **Gating:** none

### 4. Lyrics preview text (read-only)

- **DOM:** `#perf-lyric-preview` (italic display-format paragraph)
- **Handler:** content set by `showLyricPreview()` (line 1437)
- **State effect:** display-only; shows next lyric line prefixed "↓ " before lyrics start, cleared after start
- **Visibility:** always during song
- **Gating:** none

### 5. Start Lyrics button

- **Label:** "▶ Start Lyrics" (green, ready) / "✓ Lyrics Running" (greyed-out post-tap) / "No Lyrics" (red, disabled — when `syncedLyrics` is empty)
- **DOM:** `#perf-lyrics-btn`
- **Handler:** `startLyrics()` (line 1405)
- **State effect:**
  - Local: clears preview text, reveals `#lyric-transport` row, disables this button
  - Sends to TV via Agora: `{type:'lyrics-start'}`
- **Visibility:** always during song; visually three modes (ready / running / no-lyrics)
- **Gating:** none

### 6. Lyrics transport: seek-back, pause/resume, restart, seek-forward

- **Labels (left to right):** ← (seek -1 line) / ⏸-▶ (pause/resume) / ↺ (restart) / → (seek +1 line)
- **DOM:** `#lyric-transport` (4 inline `<div>` cells); pause cell is `#lyric-pause-btn`
- **Handlers:**
  - Seek back: `lyricSeek(-1)` → Agora `{type:'lyrics-seek', dir:-1}`
  - Pause/resume: `toggleLyricPause()` (line 1414) → Agora `{type:'lyrics-pause'}` or `{type:'lyrics-resume'}`
  - Restart: `lyricRestart()` (line 1426) → Agora `{type:'lyrics-restart'}`
  - Seek forward: `lyricSeek(1)` → Agora `{type:'lyrics-seek', dir:1}`
- **State effect:** sends Agora message; pause-cell text toggles locally between ⏸ / ▶
- **Visibility:** **conditional** — `#lyric-transport` is `display:none` until "Start Lyrics" is tapped; visible from then through end of song
- **Gating:** none

### 7. Pause / Resume song

- **Label:** "⏸ Pause" / "▶ Resume" (toggles)
- **DOM:** `#perf-pause` (`.perf-btn` in `#perf-actions` grid)
- **Handler:** `perfPauseToggle()` (line 1514)
- **State effect:**
  - Local: toggles `perfPaused` flag; updates button label
  - Sends to TV via Agora: `{type:'pause'}` or `{type:'resume'}`
- **Visibility:** always during song
- **Gating:** none

### 8. Stop song

- **Label:** "■ Stop" (in `.danger` style — red accent)
- **DOM:** `.perf-btn.danger` in `#perf-actions`
- **Handler:** `perfStop()` (line 1533)
- **State effect:**
  - Local: clears countdown interval, mutes mic, resets `zoomActive` / `perfCommentsOn` / `perfPaused` flags, navigates back to `screen-home`
  - Sends to TV via Agora: `{type:'stop-song'}`
- **Visibility:** always during song
- **Gating:** none

### 9. Restart song

- **Label:** "↩ Restart"
- **DOM:** `.perf-btn` in `#perf-actions`
- **Handler:** `perfRestart()` (line 1521)
- **State effect:**
  - Local: clears `perfPaused`, resets pause-button text + lyrics-button state, hides `#lyric-transport`, calls `showLyricPreview()` to re-render preview
  - Sends to TV via Agora: `{type:'restart-song'}`
- **Visibility:** always during song
- **Gating:** none

### 10. Stage view toggle (Audience ⇄ Singer)

- **Label:** "👥 Audience" / "🎤 Singer" (toggles)
- **DOM:** `#perf-view-btn` (`.perf-btn` in `#perf-actions`)
- **Handler:** `toggleStageView()` (line 1663)
- **State effect:**
  - Local: toggles `currentStageView` between `'audience'` and `'singer'`; updates button label
  - Sends to TV via Agora: `{type:'set-view', view:<new>}`
- **Visibility:** always during song
- **Gating:** none

### 11. Zoom toggle

- **Label:** "🔍 Zoom Out" / "🔍 Zoom In" (toggles)
- **DOM:** `#perf-zoom-btn` (`.perf-btn` in `#perf-actions`)
- **Handler:** `toggleZoom()` (line 1498)
- **State effect:**
  - Local: toggles `zoomActive` flag; updates button label
  - Sends to TV via Agora: `{type:'zoom-out'}` or `{type:'zoom-in'}`
- **Visibility:** always during song
- **Gating:** none

### 12. Pan left / Pan right

- **Labels:** ◀ / ▶
- **DOM:** two `.perf-btn` cells in a flex pair occupying grid column 2
- **Handlers:** `sendPanLeft()` (line 1672), `sendPanRight()` (line 1676)
- **State effect:** sends to TV via Agora — `{type:'singer-pan', delta:±15}` if `currentStageView === 'singer'`, else `{type:'venue-pan', delta:±15}`
- **Visibility:** always during song
- **Gating:** none

### 13. Costume button (opens overlay)

- **Label:** "👑 Costume"
- **DOM:** `.perf-btn` spanning the action-grid full width
- **Handler:** `showPerfCostumePicker()` (line 1177)
- **State effect:** local — slides up `#perf-costume-overlay` over the performance screen; calls `updatePerfCostumeGrid()`
- **Visibility:** always during song
- **Gating:** none

### 14. Watcher count (read-only)

- **Label:** "N watching" (text varies)
- **DOM:** `#perf-w` (`.label`)
- **Handler:** none — populated by audience-join Agora events handled via `addAudMember()` / `refreshAudList()`
- **State effect:** display-only
- **Visibility:** always during song
- **Gating:** none

### 15. Comments toggle

- **Label:** "Comments On" / "Comments Off" (toggles)
- **DOM:** `#perf-comments-btn`
- **Handler:** `togglePerfComments()` (line 1508)
- **State effect:**
  - Local: toggles `perfCommentsOn` flag; updates button label
  - Sends to TV via Agora: `{type:'toggle-comments'}`
- **Visibility:** always during song
- **Gating:** none

---

### Performance costume overlay (`#perf-costume-overlay`)

Slides up over screen-performing when control 13 (Costume button) is tapped. Stays open until the user closes it. Markup at lines 533-546.

#### 16. Close

- **Label:** "✕ Close"
- **DOM:** unstyled `<div>` at top-left of overlay
- **Handler:** `hidePerfCostumePicker()` (line 1183)
- **State effect:** local — hides the overlay
- **Visibility:** while overlay is open
- **Gating:** none

#### 17. Clear All

- **Label:** "Clear All"
- **DOM:** unstyled `<div>` at top-right of overlay
- **Handler:** inline composite — `sendClearAllAccessories(); clearAllDeepAREffects(); updatePerfCostumeGrid();`
- **State effect:**
  - Local: clears DeepAR effects on the singer's local effect-slot array (`clearAllDeepAREffects()`); refreshes overlay grid
  - Sends to TV via Agora: `{type:'clear-accessories'}` (from `sendClearAllAccessories()`)
- **Visibility:** while overlay is open
- **Gating:** none

#### 18. AR Filters grid (DeepAR effects)

- **DOM:** `#perf-deepar-grid` populated by `buildDeepARGrid('perf-deepar-grid')`
- **Handler per cell:** `toggleDeepAREffect(eff)` (line 1081)
- **State effect:**
  - Local: toggles effect in the per-slot DeepAR effect array
  - Sends to TV via Agora: `{type:'set-deepar-effect', slot, url}` (or `url:null` to clear that slot)
- **Visibility:** while overlay is open
- **Gating:** none

#### 19. Basic Overlays grid (accessories)

- **DOM:** `#perf-costume-grid` populated by `buildCostumeGrid('perf-costume-grid', ...)`
- **Handler per cell:** `singerToggleAccessory(id)` (line 1134)
- **State effect:**
  - Local: toggles ID in `singerActiveAccessories` Set
  - Sends to TV via Agora: `{type:'toggle-accessory', id, active:<bool>}`
- **Visibility:** while overlay is open
- **Gating:** none

---

### Cross-screen surfaces visible during a song

#### 20. Back-to-Elsewhere pill (top-right)

- **Label:** "← Elsewhere"
- **DOM:** `#back-to-elsewhere-btn.back-to-elsewhere` (line 1855)
- **Handler:** `handleBackToElsewhere()` (line 1796)
- **State effect:**
  - Sends to TV via Supabase realtime: `publishExitApp(device_key)`
  - Clears sessionStorage `elsewhere.active_tv.device_key`
  - Navigates phone to `../index.html`
- **Visibility:** **conditional** — starts hidden (`style="display:none"`); revealed when `window.elsewhere.isLikelyHouseholdMember()` returns true (Session 5 Part 2c.3.2). Hidden for non-household deep-link users.
- **Gating:** household-membership heuristic (auth + `sessionStorage.elsewhere.active_tv.device_key` present). **Only ambient gating on any mid-song control.**

#### 21. Debug LOG button (top-left)

- **Label:** "LOG"
- **DOM:** unstyled fixed-position `<div>` (line 1858)
- **Handler:** `toggleSingerLog()` (line 1776)
- **State effect:** local — toggles `#singer-dbg-panel` visibility
- **Visibility:** always (across all screens)
- **Gating:** none — debug affordance always available to all users

---

### NOT accessible during an active song

The following controls exist in singer.html but are **not reachable from screen-performing** (no on-screen affordance to navigate there mid-song):

| Control | Where it lives | Why locked out |
|---|---|---|
| Mic device picker (`#mic-select`) | screen-mic | Settings finalized pre-song |
| FX toggles (Reverb / Echo / Boost / Deep) | screen-mic | Settings finalized pre-song |
| Volume slider (`#vol-sl`) | screen-mic | Settings finalized pre-song |
| Per-screen mute button (`#mute-btn`) | screen-mic | Pre-song; mid-song mute is `#perf-mute-btn` only |
| Stage venue picker / venue tour | `#stage-overlay` (triggered from screen-home action card) | Venue locked at song start; cannot change mid-song |
| Venue tab toggle (singer/audience preview) | inside stage overlay | Same |
| Video chat with audience toggle (`#video-chat-btn`) | screen-home action area (line 285) | Pre-song activation only |
| Invite (`doInvite()`) | screen-home action card | Pre-song |
| "Stage Settings" entry point | screen-home action card | Pre-song |
| "Costumes" home entry (full `screen-costume`) | screen-home action card | Pre-song; mid-song uses `#perf-costume-overlay` instead |
| Search song / song-select flow | screen-search → screen-confirm | Song locked at song start |
| Mic-gear shortcut to screen-mic | top-right of screen-home | Pre-song only |

**Implication:** the singer's full set of mid-song levers is locally constrained to mic mute, lyric playback, song playback, stage view, zoom, pan, costume layer, comments toggle, and exit. **No mid-song venue/song/FX/invite/video-chat changes possible without song interruption** (Stop song → screen-home).

---

### Cross-cutting observations on mid-song controls

- **All TV-affecting controls send via Agora data streams** (`sendToStage(obj)`), never via Supabase realtime. The Supabase channel reserved for cross-page coordination (`exit_app`, `session_started`, `session_ended`, etc.) doesn't carry mid-song messages today.
- **No mid-song RPC calls.** No `rpc_session_*`, no `session_participants` reads/writes, no `pre_selections` touches. The mid-song flow is entirely Agora-mediated.
- **Stop and Restart are different flow shapes.** Stop fully exits to screen-home (mute mic, clear flags, navigate). Restart sends `restart-song` to TV but stays on screen-performing locally.
- **Zoom and stage view are TV-side visual controls only.** They don't affect singer's local UI or audio chain — they mutate stage.html's render state via Agora messages.
- **The singer cannot mid-song hand off to another participant.** Single-singer model. Stop = end-of-singer; nothing in between transfers control.
- **No queue panel exists** on singer.html in any screen, including during an active song. Pre-Session-5 model has no concept of next-up.
- **No role-based control hiding mid-song.** Every control on screen-performing is visible to whoever loaded the page. Only Back-to-Elsewhere has visibility gating, and that's auth/sessionStorage-based, not role-based.
