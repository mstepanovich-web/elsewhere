/**
 * Elsewhere Games — Agora Sync
 * Thin wrapper around Agora RTC data streams.
 * Used by both games/tv.html and games/player.html.
 *
 * Usage:
 *   const sync = new GameSync(roomCode, myUid);
 *   await sync.connect();
 *   sync.on('state-update', (msg) => { ... });
 *   sync.send({ type: 'play-card', card: { ... } });
 */

const AGORA_APP_ID  = 'b2c6543a9ed946829e6526cb68c7efc9';
const CHAN_PREFIX    = 'elsewhere_g'; // 'g' prefix for games channel

export class GameSync {
  constructor(roomCode, uid = null) {
    this.roomCode  = roomCode;
    this.channel   = CHAN_PREFIX + roomCode;
    this.uid       = uid;
    this.client    = null;
    this.streamId  = null;
    this._handlers = {};
    this._log      = [];
  }

  async connect() {
    this.client = AgoraRTC.createClient({ mode: 'rtc', codec: 'vp8' });

    this.client.on('stream-message', (uid, data) => {
      this._handleRaw(data);
    });

    this.client.on('user-joined', (user) => {
      this._emit('user-joined', { uid: user.uid });
    });

    this.client.on('user-left', (user) => {
      this._emit('user-left', { uid: user.uid });
    });

    await this.client.join(AGORA_APP_ID, this.channel, null, this.uid);
    this.uid = this.client.uid;

    try {
      this.streamId = await this.client.createDataStream({ reliable: true, ordered: true });
    } catch (e) {
      this.streamId = null;
      console.warn('[GameSync] createDataStream not supported:', e.message);
    }

    this._log.push('Connected uid:' + this.uid + ' channel:' + this.channel);
    return this.uid;
  }

  send(obj) {
    const msg = JSON.stringify({ ...obj, _from: this.uid, _ts: Date.now() });
    const bytes = new TextEncoder().encode(msg);

    if (this.streamId !== null && this.client) {
      this.client.sendStreamMessage(this.streamId, bytes).catch(e => {
        // Chunk if too large (>1KB)
        if (bytes.length > 900) this._sendChunked(msg);
      });
    }
  }

  on(type, handler) {
    if (!this._handlers[type]) this._handlers[type] = [];
    this._handlers[type].push(handler);
  }

  off(type, handler) {
    if (!this._handlers[type]) return;
    this._handlers[type] = this._handlers[type].filter(h => h !== handler);
  }

  async leave() {
    if (this.client) await this.client.leave();
  }

  // ── Private ───────────────────────────────────────────────
  _handleRaw(data) {
    try {
      const text = new TextDecoder().decode(data);
      // Handle chunked messages
      if (text.startsWith('__chunk__')) {
        this._handleChunk(text);
        return;
      }
      const msg = JSON.parse(text);
      this._emit(msg.type, msg);
      this._emit('*', msg); // wildcard
    } catch (e) {
      console.warn('[GameSync] parse error:', e);
    }
  }

  _emit(type, data) {
    (this._handlers[type] || []).forEach(h => h(data));
  }

  // Chunked sending for large state objects (e.g. full game state)
  _chunkBufs = {};

  _sendChunked(msg) {
    const id = Date.now();
    const chunkSize = 800;
    const chunks = [];
    for (let i = 0; i < msg.length; i += chunkSize) {
      chunks.push(msg.slice(i, i + chunkSize));
    }
    chunks.forEach((chunk, idx) => {
      const payload = `__chunk__${id}:${idx}:${chunks.length}:${chunk}`;
      const bytes = new TextEncoder().encode(payload);
      if (this.streamId !== null) {
        this.client.sendStreamMessage(this.streamId, bytes).catch(() => {});
      }
    });
  }

  _handleChunk(text) {
    const [, meta, ...rest] = text.split(':');
    const content = rest.join(':');
    const [id, idx, total] = meta.split(',').map((v, i) => i < 2 ? parseInt(v) : parseInt(v));

    if (!this._chunkBufs[id]) this._chunkBufs[id] = { parts: [], total };
    this._chunkBufs[id].parts[idx] = content;

    if (this._chunkBufs[id].parts.filter(Boolean).length === this._chunkBufs[id].total) {
      const full = this._chunkBufs[id].parts.join('');
      delete this._chunkBufs[id];
      try {
        const msg = JSON.parse(full);
        this._emit(msg.type, msg);
        this._emit('*', msg);
      } catch (e) {}
    }
  }
}
