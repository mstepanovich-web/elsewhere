// shell/realtime.js — Elsewhere shell: realtime helpers on tv_device:<device_key>.
//
// Extracted from inline copies in index.html (publishers), karaoke/singer.html
// (publishExitApp), games/player.html (publishExitApp), karaoke/stage.html
// (wireExitAppListener), games/tv.html (wireExitAppListener) at Session 5
// Part 1c. Pure refactor — zero user-facing behavior change.
//
// Loaded as <script type="module" src="[path]shell/realtime.js"> AFTER
// shell/auth.js in each consumer. Depends on:
//   • window.sb               — Supabase client, set by auth.js
//   • window.elsewhere.ready  — Promise that resolves when auth.js finishes
//                               initial session hydration
//
// Exposed on window (bare globals so call sites stay unchanged from their
// pre-extraction inline form):
//   window.publishSessionHandoff(device_key)
//   window.publishLaunchApp(device_key, app, room)
//   window.publishExitApp(device_key, reason = 'user-exit')
//   window.wireExitAppListener(onExit)
//
//   Session 5 publishers (object-payload signatures; all async/awaitable,
//   all throw on failure matching the existing publishers' contract):
//   window.publishSessionStarted(device_key, { session_id, app, manager_user_id, room_code })
//   window.publishManagerChanged(device_key, { session_id, new_manager_user_id, reason })
//   window.publishParticipantRoleChanged(device_key, { session_id, user_id, control_role, participation_role })
//   window.publishQueueUpdated(device_key, { session_id })
//   window.publishSessionEnded(device_key, { session_id, reason })
//
// Session 5 event emission matrix — which RPC success triggers which publish:
//
//   rpc_session_start                        → session_started
//   rpc_session_end                          → session_ended (reason: 'user_ended')
//   rpc_session_leave (manager alone OR no
//     eligible promotee → session ends)      → session_ended (reason: 'manager_left')
//   rpc_session_leave (auto-promoted new
//     manager)                               → manager_changed (reason: 'auto_promote')
//                                              + participant_role_changed for the leaver
//   rpc_session_leave (non-manager leave)    → participant_role_changed
//   rpc_session_reclaim_manager              → manager_changed (reason: 'reclaim')
//   rpc_session_admin_reclaim                → manager_changed (reason: 'admin')
//   rpc_session_join                         → participant_role_changed
//   rpc_session_update_participant (with
//     control_role or participation_role)    → participant_role_changed
//   rpc_session_update_participant (with
//     only pre_selections)                   → queue_updated
//   rpc_session_update_queue_position        → queue_updated
//   rpc_session_promote_self_from_queue      → participant_role_changed
//
// Narrow rule: queue_updated fires ONLY for pure queue metadata changes
// (reorder, pre_selection update). Role transitions that affect queue
// composition fire participant_role_changed instead. Consumers interested
// in queue state subscribe to BOTH events.
//
// NOT extracted: tv2.html's subscribeToHandoffChannel. Its multi-event
// subscribe-with-timeout state machine doesn't compose cleanly with the
// simpler single-listener pattern used by stage.html / games/tv.html.
// Kept inline in tv2.html per "extract when duplicated, not preemptively."
//
// Module-loading note: because this is a `type="module"` script, it's
// deferred. Non-module inline scripts in consumer pages execute BEFORE
// this module runs. The publishers are only ever called from user-
// interaction handlers (button onclick, etc.), so the timing works out
// naturally. wireExitAppListener, however, is typically called at page
// boot from an inline script — consumers must wrap their call in a
// DOMContentLoaded listener so window.wireExitAppListener is defined by
// call time.
//
// Implementation notes (vs. the pre-extraction inline versions):
// • wireExitAppListener uses window.elsewhere.ready (promise) to wait for
//   the Supabase client, replacing the pre-extraction if-ready-else-listen
//   fallback on the elsewhere:sb-ready event. Functionally equivalent but
//   simpler to reason about.
// • wireExitAppListener's channel reference lives in closure scope instead
//   of a module-level `let _exitAppChannel = null` on each consumer page.
//   No change in behavior; eliminates a minor global state leak.

// Publishes the phone's current Supabase session tokens onto the
// 'tv_device:<device_key>' realtime channel so the TV (tv2.html) can call
// supabase.auth.setSession and proceed authed.
//
// Timing note: the TV must subscribe to this channel BEFORE the phone
// publishes. Supabase broadcasts are not buffered for late joiners — if
// the TV hasn't subscribed by the time send() fires, the handoff is
// dropped silently and the user ends up stuck on the TV's QR screen.
// tv2.html subscribes before rendering its QR per Session 4.10 Part C.
window.publishSessionHandoff = async function publishSessionHandoff(device_key) {
  const { data: { session }, error: sessionErr } = await window.sb.auth.getSession();
  if (sessionErr) throw sessionErr;
  if (!session) throw new Error('No session to hand off — please sign in again.');

  const channel = window.sb.channel('tv_device:' + device_key);

  // Subscribe first, then send. 5s timeout to fail fast if realtime is
  // unreachable rather than silently dropping the handoff.
  await new Promise((resolve, reject) => {
    let settled = false;
    const timer = setTimeout(() => {
      if (!settled) { settled = true; reject(new Error('Realtime subscribe timed out.')); }
    }, 5000);
    channel.subscribe(status => {
      if (settled) return;
      if (status === 'SUBSCRIBED') {
        settled = true; clearTimeout(timer); resolve();
      } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
        settled = true; clearTimeout(timer); reject(new Error('Realtime channel ' + status));
      }
    });
  });

  await channel.send({
    type:  'broadcast',
    event: 'session_handoff',
    payload: {
      access_token:  session.access_token,
      refresh_token: session.refresh_token,
    },
  });

  // Clean up. Broadcast is fire-and-forget; keeping the channel open
  // would leak realtime sockets across flows.
  await channel.unsubscribe();
  window.sb.removeChannel(channel);
};

// Publishes 'launch_app' on the tv_device:<device_key> realtime channel.
// Mirrors publishSessionHandoff's subscribe → send → unsubscribe →
// removeChannel pattern for consistency.
window.publishLaunchApp = async function publishLaunchApp(device_key, app, room) {
  const channel = window.sb.channel('tv_device:' + device_key);

  await new Promise((resolve, reject) => {
    let settled = false;
    const timer = setTimeout(() => {
      if (!settled) { settled = true; reject(new Error('Realtime subscribe timed out.')); }
    }, 5000);
    channel.subscribe(status => {
      if (settled) return;
      if (status === 'SUBSCRIBED') {
        settled = true; clearTimeout(timer); resolve();
      } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
        settled = true; clearTimeout(timer); reject(new Error('Realtime channel ' + status));
      }
    });
  });

  await channel.send({
    type:  'broadcast',
    event: 'launch_app',
    payload: { app, room },
  });

  await channel.unsubscribe();
  window.sb.removeChannel(channel);
};

// Publishes 'exit_app' on the tv_device:<device_key> realtime channel.
// Called from phone-side back-to-Elsewhere buttons on singer.html and
// player.html (4.10.3 Parts B + C).
window.publishExitApp = async function publishExitApp(device_key, reason = 'user-exit') {
  const channel = window.sb.channel('tv_device:' + device_key);

  await new Promise((resolve, reject) => {
    let settled = false;
    const timer = setTimeout(() => {
      if (!settled) { settled = true; reject(new Error('Realtime subscribe timed out.')); }
    }, 5000);
    channel.subscribe(status => {
      if (settled) return;
      if (status === 'SUBSCRIBED') {
        settled = true; clearTimeout(timer); resolve();
      } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
        settled = true; clearTimeout(timer); reject(new Error('Realtime channel ' + status));
      }
    });
  });

  await channel.send({
    type:  'broadcast',
    event: 'exit_app',
    payload: { reason },
  });

  await channel.unsubscribe();
  window.sb.removeChannel(channel);
};

// Subscribes the current TV page to 'exit_app' broadcasts on the
// tv_device:<device_key> realtime channel. When an exit_app event arrives,
// tears down the channel cleanly and invokes onExit (typically a
// location.href navigation).
//
// Reads device_key from localStorage['elsewhere.tv.device_key'] internally.
// No-op if no device_key is set (direct-nav dev flow).
//
// Uses window.elsewhere.ready to wait for the Supabase client. Callers
// that invoke this at page-boot time must wrap in a DOMContentLoaded
// listener since this module is deferred — window.wireExitAppListener
// won't exist yet when non-module inline scripts run during HTML parsing.
window.wireExitAppListener = function wireExitAppListener(onExit) {
  if (!window.elsewhere?.ready) return;
  window.elsewhere.ready.then(() => {
    if (!window.sb) return;

    let device_key = null;
    try { device_key = localStorage.getItem('elsewhere.tv.device_key'); } catch (_) {}
    if (!device_key) return;

    const channel = window.sb.channel('tv_device:' + device_key);
    channel.on('broadcast', { event: 'exit_app' }, async () => {
      try { await channel.unsubscribe(); } catch (_) {}
      try { window.sb.removeChannel(channel); } catch (_) {}
      if (typeof onExit === 'function') onExit();
    });
    channel.subscribe();
  });
};


// ─────────────────────────────────────────────────────────────────────────
// Session 5 event publishers.
// Each wraps the shared broadcast() helper with an event-specific name.
// ─────────────────────────────────────────────────────────────────────────

// Shared subscribe/send/unsubscribe/removeChannel ceremony. Private to
// this module. Not exposed on window. Used by the 5 Session-5 publishers
// below. Existing 4.10/4.10.2/4.10.3 publishers (publishSessionHandoff,
// publishLaunchApp, publishExitApp) retain their inline bodies — factoring
// them through broadcast() is a separate refactor.
async function broadcast(device_key, event, payload) {
  const channel = window.sb.channel('tv_device:' + device_key);

  await new Promise((resolve, reject) => {
    let settled = false;
    const timer = setTimeout(() => {
      if (!settled) { settled = true; reject(new Error('Realtime subscribe timed out.')); }
    }, 5000);
    channel.subscribe(status => {
      if (settled) return;
      if (status === 'SUBSCRIBED') {
        settled = true; clearTimeout(timer); resolve();
      } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
        settled = true; clearTimeout(timer); reject(new Error('Realtime channel ' + status));
      }
    });
  });

  await channel.send({ type: 'broadcast', event, payload });

  await channel.unsubscribe();
  window.sb.removeChannel(channel);
}

// Fired after rpc_session_start success.
// Payload: { session_id, app, manager_user_id, room_code }.
window.publishSessionStarted = async function publishSessionStarted(device_key, payload) {
  return broadcast(device_key, 'session_started', payload);
};

// Fired after rpc_session_reclaim_manager / rpc_session_admin_reclaim /
// rpc_session_leave-triggered auto-promote. See file-top emission matrix.
// Payload: { session_id, new_manager_user_id, reason }.
//   reason ∈ {'auto_promote', 'reclaim', 'admin'}
window.publishManagerChanged = async function publishManagerChanged(device_key, payload) {
  return broadcast(device_key, 'manager_changed', payload);
};

// Fired when a participant's control_role or participation_role changes.
// See file-top emission matrix for the full list of triggering RPCs.
// Payload: { session_id, user_id, control_role, participation_role } —
// always includes the CURRENT values of both roles (not a delta).
window.publishParticipantRoleChanged = async function publishParticipantRoleChanged(device_key, payload) {
  return broadcast(device_key, 'participant_role_changed', payload);
};

// Fired for pure queue metadata changes that don't involve role transitions:
// queue-position reorder, or pre-selection update. Consumers re-query
// session_participants to get authoritative state.
// Payload: { session_id }.
window.publishQueueUpdated = async function publishQueueUpdated(device_key, payload) {
  return broadcast(device_key, 'queue_updated', payload);
};

// Fired after rpc_session_end or after rpc_session_leave results in session
// ending (manager alone or no eligible promotee). Phase 1 does not
// distinguish "manager alone" from "no eligible promotee" — both emit
// reason 'manager_left'.
// Payload: { session_id, reason }.
//   reason ∈ {'user_ended', 'manager_left'}
window.publishSessionEnded = async function publishSessionEnded(device_key, payload) {
  return broadcast(device_key, 'session_ended', payload);
};
