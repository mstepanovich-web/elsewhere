# Immersive TV Tier 1 — Build Spec: The Web-Only Claim Trigger

Status: BUILD-READY for review. This is a build spec — it defines WHAT
to build and the constraints, for a Claude Code implementation done
propose-pause. It does not itself contain code.

This is **Stage 3** of the Immersive TV workstream (Stage 1 = the design
model `IMMERSIVE-TV-DESIGN-MODEL.md`; Stage 2 = the read-only
verification investigation). It specs **Tier 1 only** — one of the three
Phase 3 gates (`IMMERSIVE-TV-DESIGN-MODEL.md §13`). The other two gates
are items 5/6, specced separately.

Grounded in two read-only investigations (cited inline as "Stage 2" —
the verification investigation — and "code-read" — the follow-up
open-questions trace). All open questions from the original draft are
now RESOLVED — see §9.

## 1. The problem

(Stage 2, Q1–Q3.) A device can become a registered `tv_devices` row —
and the full claim round-trip works end-to-end — but the ONLY trigger
path requires the iOS Elsewhere app on a second phone:

`tv2.html` shows a claim QR → a phone with the iOS app scans it →
`claim.html` fires `elsewhere://tv-claim` → `shell/auth.js` parses the
deep link → dispatches an `elsewhere:tv-claim` CustomEvent →
`index.html`'s claim screen calls `rpc_claim_tv_device` /
`rpc_link_tv_to_existing_household`.

Two facts from Stage 2 make Tier 1 small:

- The claim RPCs have **no iOS-specific assumption** — they are callable
  from an ordinary authenticated web session. The claim UI in
  `index.html` (`submitTvClaim`) is already web code.
- The iOS dependency is **only the trigger** — the deep-link →
  CustomEvent hop. And the CustomEvent listener wiring in `index.html`
  is unconditional (not gated on `Capacitor.isNativePlatform()`), so a
  web-synthesized equivalent would reach the same flow.

So Tier 1 is NOT "build an Immersive TV setup flow." The flow exists.
Tier 1 is: **provide a web path that reaches the existing claim flow
without the iOS app.**

## 2. Scope

**In scope (Tier 1):** a web entry point by which a logged-in household
member, on a laptop, makes that laptop the household's Immersive TV —
reaching the existing `rpc_claim_tv_device` /
`rpc_link_tv_to_existing_household` claim flow without the iOS app.

**Explicitly OUT of scope (Tier 2 — `IMMERSIVE-TV-DESIGN-MODEL.md §11`,
each tracked separately):** presence-by-scan; periodic TV heartbeat +
idle release (R4); scan-aware second-person / takeover paths; the
ownership-seize RPC; the "TV" button; trust-boundary hardening
(actor-authorization on claim, `device_key` format enforcement);
casting; immersive gating granularity.

Tier 1 makes the laptop claimable from the web. It does NOT add presence
mechanics, idle release, or any new authority rule. The existing
question-based presence and the existing four-tier room authority are
unchanged.

## 3. What already exists (do not rebuild)

(Stage 2 — verified.) Tier 1 must REUSE, not duplicate:

- `tv2.html` — the generic TV surface. One generic URL; per-device
  identity via the `device_key` in its `localStorage`
  (`getOrCreateDeviceKey()`). Shows claim QR / sign-in QR / apps grid
  per registration state. Subscribes to its `tv_device:<device_key>`
  channel at boot.
- `rpc_claim_tv_device(p_device_key, p_household_name, p_tv_display_name)`
  — creates a new household + makes the caller HH admin + inserts the
  `tv_devices` row. Auth: requires `auth.uid()`. Web-callable.
- `rpc_link_tv_to_existing_household(p_device_key, p_household_id)` —
  links a device to an existing household; requires the caller be that
  household's admin. Web-callable.
- `submitTvClaim` in `index.html` — the existing claim UI that calls
  those RPCs; reached today via the `elsewhere:tv-claim` CustomEvent.
- The multi-device picker (`enterYourTvsFlow`) and presence question —
  unchanged, reused as-is.

Tier 1 adds a new WAY IN to `submitTvClaim`'s flow. It does not
re-implement the claim.

## 4. The Tier 1 build — the web claim trigger

The investigation established the iOS path is: scan → `claim.html` →
`elsewhere://tv-claim?device_key=<key>` → `shell/auth.js` →
`elsewhere:tv-claim` CustomEvent → claim screen. Tier 1 provides a
web-native path to that same claim screen, for the case where the user
is *already on the laptop that will become the TV*.

R4.1 — **The web claim trigger is a control on `tv2.html` itself.**
[OPEN 1 + OPEN 4 RESOLVED — decided together; code-read showed the shell
has NO URL routing (it is screen-swap via `goTo()`; cross-surface nav is
full-page `location.href`), so a "dedicated `/tv` SPA route" is not a
pattern that exists. The original draft's "dedicated route" lean is
superseded.]

The laptop becoming a TV is *already on `tv2.html`* — that is where it
displays the claim QR today. So Tier 1 adds, to `tv2.html`'s claiming
screen, a web-native claim control: a logged-in household member can
claim *this* TV directly — the web counterpart to the iOS-app QR claim —
instead of only via a QR scanned from a second phone.

Why `tv2.html` and not an `index.html` route:
  - `tv2.html` already has the `device_key` in scope
    (`getOrCreateDeviceKey()` at ~line 367) — no cross-surface handoff.
  - The post-claim end state for a laptop-as-TV must be `tv2.html`'s
    registered `screen-apps` state (the TV state), NOT `index.html`'s
    `screen-home` (the phone/controller state). `submitTvClaim`'s
    existing tail is `enterHomeForTv` → `screen-home` — the phone-side
    outcome, designed for the iOS case where the claimer is a phone. A
    `tv2.html`-native claim reaches `screen-apps` via the existing
    `handleSessionHandoff → renderCurrentState → showAppsScreen` path
    with no cross-surface redirect to engineer.
  - An `index.html?action=tv-claim` route would require reading
    `device_key` from `localStorage` AND a post-claim redirect to
    `tv2.html` — more moving parts, no gain.

R4.2 — **Reaching the claim logic.** `tv2.html`'s claim control drives
the existing `rpc_claim_tv_device` / `rpc_link_tv_to_existing_household`
RPCs. [OPEN 2 RESOLVED — the listener-synthesis option from the original
draft applies to an `index.html`-based entry; since the entry now lives
on `tv2.html`, the claim control calls the claim RPCs directly (the same
calls `submitTvClaim` makes), reusing `submitTvClaim`'s exact RPC logic.]
The claim RPCs are unchanged; this is a new caller, not new claim logic.

R4.3 — **New vs. existing household — the household picker.** The claim
flow branches: a user with no household → `rpc_claim_tv_device` (creates
the household, makes them admin); a user already in a household →
`rpc_link_tv_to_existing_household`. The existing household-picker UI
that presents this choice lives ONLY in `index.html`'s `screen-tv-claim`
(code-read B2). Therefore the Tier 1 build must **port or rebuild a
minimal household-picker onto `tv2.html`** — new-vs-existing household
selection + (for new) a household-name field + (for the TV) a display-
name field. This is UI assembly from existing pieces, not new claim
logic. **[BUILD-CONFIRM]** — confirm the cleanest way to bring that
picker onto `tv2.html` (port the markup, or a minimal reimplementation).

R4.4 — **The laptop becomes the TV — post-claim end state.** [OPEN 4
RESOLVED.] After a successful claim from `tv2.html`, the laptop must end
in `tv2.html`'s registered `screen-apps` state — the correct TV end
state — via the existing post-claim path: the claim writes the session,
`renderCurrentState()` re-runs, `rpc_tv_is_registered` now returns
registered, `showAppsScreen` fires. Because the claim happens ON
`tv2.html`, no `publishSessionHandoff` cross-tab broadcast is needed for
the laptop itself — the same tab that claimed transitions directly to
`screen-apps`. (Contrast the iOS path, where the handoff broadcast is
needed precisely because the claimer is a *different* device.) The build
must ensure the `tv2.html` claim control's success path lands on
`screen-apps`, not on any `index.html` screen.

R4.5 — **No second device required.** The whole flow completes on the
one laptop, by the logged-in household member, with no phone and no iOS
app. That is the entire point of Tier 1.

## 5. The trust boundary — Tier 1 posture

(Stage 2, Q1/Q2 — verified.) `device_key` has no server-side format
validation; `rpc_claim_tv_device` has no actor-authorization check (any
authenticated user holding a `device_key` can claim). The "128-bit UUID
secret" is doctrine in a code comment, not enforced.

Tier 1 **does not fix this** — trust-boundary hardening is explicitly
Tier 2 (`IMMERSIVE-TV-DESIGN-MODEL.md §7, §11`). Tier 1 must simply not
make it worse:

R5.1 — The `device_key` must NEVER travel in a URL. [OPEN 3 RESOLVED —
code-read confirmed `localStorage` is per-origin and shared across
pages; and with the claim control now living ON `tv2.html` (R4.1), the
`device_key` is already in that page's scope from `getOrCreateDeviceKey()`
— it does not need to move at all.] The iOS path puts `device_key` in a
URL only because the deep link is a cross-*process* channel between the
iOS app and the website; that necessity does not apply to an in-browser,
single-page web claim. Putting a `device_key` in a URL would leak it via
browser history, Referer headers, and server access logs — the build
must not do this.

R5.2 — The claim still requires an authenticated session (`auth.uid()`)
— unchanged; `rpc_claim_tv_device` enforces it. Tier 1 adds no new
auth bypass.

This section is a constraint, not a feature: Tier 1 reaches the existing
claim flow and inherits its (acknowledged, Tier-2-tracked) trust posture
— no better, no worse.

## 6. Constraints and non-regressions

- The claim RPCs (`rpc_claim_tv_device`,
  `rpc_link_tv_to_existing_household`) are NOT modified. No db migration.
  Tier 1 is a client-side new-entry-point, not a backend change.
- The iOS-app claim path (`claim.html` → `elsewhere://tv-claim` →
  `shell/auth.js`) must continue to work unchanged. Tier 1 ADDS a web
  path beside it; it does not replace it.
- `tv2.html`'s existing behavior — `getOrCreateDeviceKey`, the three
  registration-state screens, the `launch_app` subscription — must not
  regress.
- The multi-device picker (`enterYourTvsFlow`) and the presence question
  are unchanged.
- Tier 1 must not depend on any Tier 2 mechanic (presence-by-scan, idle
  release, etc.) — those do not exist and Tier 1 must work without them.
- Phase 2 (db/032, `venue-settings.js`, `venue-registry.js`) is
  untouched.

## 7. Interlock with items 5/6

(Items 5/6 build spec §10; Stage 2 Q4 — confirmed clean.) Tier 1 changes
WHO can become a TV (a laptop, web-only). Items 5/6 change WHICH code
path publishes `launch_app` (shell tile-tap → in-app click-through).
They share the `tv_device:<device_key>` channel as substrate but operate
at different layers and are compatible.

One coordination note, not a blocker: both Tier 1 and items 5/6 touch
entry/navigation surfaces. Whichever builds second should re-verify the
other's surface still behaves. If Tier 1 chooses Option A (a dedicated
`/tv` route), it should be confirmed not to collide with the shell
routing items 5/6 also touches.

## 8. Verification

The build is verified when, with NO iOS app and NO second device:

V8.1 — A logged-in household member, on a laptop, can reach the web
entry point and make that laptop the household's Immersive TV.

V8.2 — Both branches work: a user with no household creates one and
becomes admin; a user already in a household links the laptop to it.

V8.3 — After claiming, the laptop is in `tv2.html`'s registered state,
subscribed to its channel, and receives a `launch_app` broadcast
correctly (i.e. it can be driven as the TV).

V8.4 — The existing iOS-app claim path still works unchanged.

V8.5 — `enterYourTvsFlow`, the presence question, and `tv2.html`'s
existing screens are unregressed.

This clears Phase 3 gate #1. Gates #2 and #3 (items 5/6) are separate.

## 9. Resolved decisions (was: open questions)

All open questions from the original draft are resolved (code-read
follow-up investigation). Record:

- **OPEN 1 + OPEN 4** (R4.1, R4.4) — the web claim trigger lives on
  `tv2.html` itself, not as an `index.html` route (the shell has no URL
  routing — code-read B1). Post-claim end state is `tv2.html`'s
  `screen-apps` — the correct TV state — reached without a cross-surface
  redirect.
- **OPEN 2** (R4.2) — the `tv2.html` claim control calls the claim RPCs
  directly, reusing `submitTvClaim`'s RPC logic. (CustomEvent synthesis
  was an `index.html`-entry option, now moot.)
- **OPEN 3** (R5.1) — `device_key` never travels in a URL; it is already
  in `tv2.html`'s scope via `getOrCreateDeviceKey()`.

Remaining **[BUILD-CONFIRM]** item (a code fact to settle DURING
implementation, not a decision):
- R4.3 — confirm the cleanest way to bring the household-picker UI
  (currently only in `index.html`'s `screen-tv-claim`) onto `tv2.html`:
  port the markup, or a minimal reimplementation.

## 10. Build sequence (proposed)

1. Build the web claim trigger on `tv2.html` (§4), propose-pause-apply.
   All design opens are resolved (§9); the entry-point mechanics
   (shell routing, `submitTvClaim`, the claim listener, `device_key`
   handling, the post-claim transition) were all traced in the code-read
   investigation. The one [BUILD-CONFIRM] — how best to bring the
   household-picker onto `tv2.html` — is settled inline during the build.
2. Verify per §8.
3. Phase 3 gate #1 cleared.
