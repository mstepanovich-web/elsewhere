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
