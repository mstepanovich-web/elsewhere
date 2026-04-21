// shell/auth.js — Elsewhere shell: Supabase client, session, auth API.
//
// Loaded as <script type="module"> from any page that needs auth.
// Typically loaded once by index.html (the shell) and once by games/player.html.
// Because Supabase persists its session in localStorage, both loads share one session.
//
// Exposes:
//   window.sb                    — raw Supabase client (escape hatch for DB queries)
//   window.elsewhere             — high-level API; see below
//   window.elsewhere.ready       — Promise that resolves once the client is initialized
//   'elsewhere:sb-ready' event   — fires once at module boot
//   'elsewhere:auth-changed'     — fires on sign-in / sign-out, detail.user = user|null
//
// Deep-link router (iOS app only):
//   elsewhere://auth/callback?code=…     PKCE sign-in completion
//   elsewhere://auth/callback#access_token=…   implicit-flow sign-in completion
//   elsewhere://games?room=X&mgrname=Y&…  forward to games/player.html with query preserved

import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

const SUPABASE_URL = 'https://gbrnuxyzrlzbybvcvyzm.supabase.co';
const SUPABASE_KEY = 'sb_publishable_QQTDPpfpUI0NJlGawfYljw_O3d6Z9RK';
const AUTH_REDIRECT_URL = 'elsewhere://auth/callback';

const sb = createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    // Magic-link callback arrives via Capacitor appUrlOpen, not window.location —
    // we call exchangeCodeForSession / setSession manually in the deep-link handler.
    detectSessionInUrl: false,
  },
});

window.sb = sb;

let currentUser = null;

function emitAuthChanged() {
  document.dispatchEvent(new CustomEvent('elsewhere:auth-changed', { detail: { user: currentUser } }));
}

const ready = sb.auth.getSession().then(({ data }) => {
  currentUser = data?.session?.user || null;
  emitAuthChanged();
  return sb;
});

sb.auth.onAuthStateChange((event, session) => {
  currentUser = session?.user || null;
  emitAuthChanged();
});

window.elsewhere = {
  ready,

  getCurrentUser: () => currentUser,

  signInWithEmail: (email) =>
    sb.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: AUTH_REDIRECT_URL, shouldCreateUser: false },
    }),

  signUpWithEmail: (email, fullName) =>
    sb.auth.signInWithOtp({
      email,
      options: {
        emailRedirectTo: AUTH_REDIRECT_URL,
        shouldCreateUser: true,
        data: { full_name: fullName },
      },
    }),

  signOut: () => sb.auth.signOut(),

  onAuthChange: (cb) => {
    const listener = (e) => cb(e.detail.user);
    document.addEventListener('elsewhere:auth-changed', listener);
    // Fire once immediately with the current state so callers don't miss the first event.
    queueMicrotask(() => cb(currentUser));
    return () => document.removeEventListener('elsewhere:auth-changed', listener);
  },
};

document.dispatchEvent(new CustomEvent('elsewhere:sb-ready'));

// ════════════════════════════════════════════════════════════
//  CAPACITOR DEEP-LINK HANDLER (iOS app only)
// ════════════════════════════════════════════════════════════
// In a regular browser window.Capacitor is undefined and this block is a no-op.
// URL shapes handled:
//   elsewhere://auth/callback?code=…       PKCE
//   elsewhere://auth/callback#access_token=…&refresh_token=…   implicit
//   elsewhere://games?room=ABC&mgrname=Mike[&t=TOKEN&…]
//   elsewhere://tv-claim?device_key=<UUID>    Session 4.10 — first-time TV registration
//   elsewhere://tv-signin?device_key=<UUID>   Session 4.10 — returning TV sign-in
//
// AUTH:  finish Supabase sign-in; onAuthStateChange fires so pages update naturally.
// GAMES: navigate to games/player.html preserving the full query string so any
//        future params (invite tokens, etc.) flow through without code changes here.
// TV:    parse the device_key and dispatch a custom DOM event — routing into the
//        shell screens lives in index.html, kept separate so auth.js stays
//        UI-agnostic. Index listens for 'elsewhere:tv-claim' / 'elsewhere:tv-signin'.

if (window.Capacitor?.Plugins?.App) {
  const AppPlugin = window.Capacitor.Plugins.App;

  async function handleElsewhereDeepLink(url) {
    if (!url || !url.startsWith('elsewhere://')) return;
    // Don't log the full URL — fragment/query may contain access_tokens.
    console.log('[elsewhere] deep link:', url.split('?')[0].split('#')[0]);

    if (url.startsWith('elsewhere://auth/callback')) {
      try {
        const u = new URL(url);
        const code = u.searchParams.get('code');
        if (code) {
          const { error } = await sb.auth.exchangeCodeForSession(code);
          if (error) throw error;
          return;
        }
        if (u.hash) {
          const p = new URLSearchParams(u.hash.startsWith('#') ? u.hash.slice(1) : u.hash);
          const access_token = p.get('access_token');
          const refresh_token = p.get('refresh_token');
          if (access_token && refresh_token) {
            const { error } = await sb.auth.setSession({ access_token, refresh_token });
            if (error) throw error;
            return;
          }
        }
        document.dispatchEvent(new CustomEvent('elsewhere:auth-error', {
          detail: { message: 'Sign-in link was missing its token.' },
        }));
      } catch (e) {
        console.error('[elsewhere] auth callback error:', e);
        document.dispatchEvent(new CustomEvent('elsewhere:auth-error', {
          detail: { message: 'Sign-in failed: ' + (e?.message || 'link may be expired.') },
        }));
      }
      return;
    }

    if (url.startsWith('elsewhere://games')) {
      try {
        const u = new URL(url);
        // Forward the query string as-is so any future params (e.g. invite ?t=TOKEN)
        // reach games/player.html without changes here.
        const qs = u.search || '';
        // If already on games/player.html, just update URL + reload handlers; otherwise navigate.
        if (location.pathname.endsWith('/games/player.html')) {
          // Stay — games/player.html has its own listener that'll pick up the appUrlOpen event.
          return;
        }
        // From the shell (or anywhere else), navigate to the games page preserving params.
        // Use a path that's relative to the site root so it works in the iOS app bundle
        // and on GitHub Pages alike.
        const base = location.pathname.includes('/karaoke/') || location.pathname.includes('/games/')
          ? '../games/player.html'
          : 'games/player.html';
        location.href = base + qs;
      } catch (e) {
        console.error('[elsewhere] games deep-link parse failed:', e);
      }
      return;
    }

    // Session 4.10 — TV claim / sign-in. Parse device_key and dispatch a
    // custom event. index.html owns the screen routing; this handler just
    // delivers the payload.
    if (url.startsWith('elsewhere://tv-claim') || url.startsWith('elsewhere://tv-signin')) {
      try {
        const u = new URL(url);
        const device_key = u.searchParams.get('device_key') || '';
        if (!device_key) {
          document.dispatchEvent(new CustomEvent('elsewhere:auth-error', {
            detail: { message: 'TV link was missing its device key.' },
          }));
          return;
        }
        const evtName = url.startsWith('elsewhere://tv-claim')
          ? 'elsewhere:tv-claim'
          : 'elsewhere:tv-signin';
        document.dispatchEvent(new CustomEvent(evtName, { detail: { device_key } }));
      } catch (e) {
        console.error('[elsewhere] tv deep-link parse failed:', e);
      }
      return;
    }
  }

  AppPlugin.getLaunchUrl?.().then((res) => handleElsewhereDeepLink(res?.url)).catch(() => {});
  AppPlugin.addListener('appUrlOpen', (data) => handleElsewhereDeepLink(data?.url));
}
