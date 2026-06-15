# The client protocol

This is the contract between the Rails server and every client of it: the web
front-end (`app/javascript/controllers/chat_controller.js`, the reference
implementation) and the native apps (`ios/` and `android/`).

When server behavior that clients depend on changes, this file changes with
it — and then each client follows. That's the whole update loop: web feature
lands, this contract gets re-read, native clients get the same change ported.
`spec/requests/native_client_spec.rb` protects the server side of this
contract.

## Identity model (read this first)

All data lives server-side, encrypted with a key derived from the person's
Google ID (see `app/models/resonance.rb`). The server never stores that ID —
it arrives with each request and is forgotten after:

- **Web**: inside the encrypted Rails session cookie
- **Native**: inside an encrypted bearer token (`Authorization: Bearer ...`),
  minted at sign-in, held in the device keychain

Both envelopes are sealed with server-side keys derived from
`secret_key_base`. Neither is stored server-side. Two doors, one universe:
the same Google account sees the same narrative everywhere.

## Native sign-in handshake

No Google SDK; the app rides the existing web sign-in flow in a system
browser sheet (PKCE-style):

1. App generates a random `code_verifier`, computes
   `code_challenge = base64url(sha256(verifier))`
2. App opens `GET /native/auth?code_challenge=...` in the browser sheet
   **ephemerally** (no shared cookies); the human signs in with Google
   exactly as on the web
3. Server shows a consent gate (`/native/auth/confirm`) naming the account;
   the human taps **Continue**, and only then does the server redirect to
   `yours://auth?code=<one-time code>` (60-second TTL, bound to the
   challenge). An existing browser session is never silently inherited — the
   tap is required, which prevents a confused-deputy account takeover.
4. App exchanges it: `POST /native/token` with `code` + `code_verifier` →
   `{ token, obfuscated_email }`
5. App stores `token` in the keychain; all further requests send
   `Authorization: Bearer <token>`

Tokens expire after a year; any 401 means sign in again. Bearer requests are
exempt from CSRF (no cookies involved); cookie requests remain protected.

## Endpoints clients use

| Endpoint | Auth | Returns |
|---|---|---|
| `GET /native/state` | bearer | `{ universe_day, universe_time, narrative, textarea, obfuscated_email, subscription_active }`; add `?include=subscription` for `subscription` details |
| `POST /stream` | either | SSE stream (below). Body: `{ message: { role, content: [{ type: "text", text }] } }` |
| `PUT /textarea` | either | `{ status: "saved", universe_time }`. Body: `{ textarea }` |
| `POST /sleep` | either | web: redirect; bearer: `{ status: "integrating", starting_universe_time }` — then poll `/native/state` until `universe_time` moves |
| `GET /save` | either | the narrative as `text/plain` |
| `POST /reset` | either | start over at day 1 (subscriber gesture; web confirms first, apps must too) |
| `POST /native/subscription` | bearer | verify and record a native in-app purchase (below) |

## Subscriptions across three storefronts

A resonance can become a subscriber via Stripe (web) or Apple in-app
purchase (iOS), and `active_subscription?` is **any-source-unlocks**: true
if *any* live source reports a subscription. The platforms don't share an
identity, so a person could in principle pay on more than one; each
storefront manages its own billing and cancellation, and we don't try to
reconcile across them.

> **Google Play (Android) is implemented server-side but gated off** until
> the Android client has a billing flow. `POST /native/subscription` with
> `platform: "google"` returns **501** `platform_unavailable` until a Play
> service account is configured (`GooglePlayStore.configured?`), and the
> Google entitlement check is skipped. The verification code and its specs
> are in place so enabling it is a config + Android-client change, not new
> server work.

Each subscription identity is stored encrypted under the google_id, exactly
like `encrypted_stripe_customer_id` — so the topological-opacity invariant
holds for IAP too: without the OAuth key, the server can't link an Apple or
Google transaction to a resonance.

### Native purchase flow (StoreKit 2 / Play Billing)

1. The app fetches products from the storefront and runs the purchase
   locally (StoreKit 2 / Play Billing), **binding the purchase to this
   account**: it sets StoreKit's `appAccountToken` (Apple) /
   `obfuscatedExternalAccountId` (Google) to the `iap_account_token` from
   `/native/state`. The storefront, not our server, takes the money.
2. The app receives a **signed** transaction (Apple: a JWS; Google: a
   purchase token) and POSTs it to `POST /native/subscription`:
   `{ platform: "apple" | "google", signed_transaction: "..." }`
3. The server **verifies it with the storefront's own API** — never trusting
   the raw client value — checks that the transaction's account token matches
   *this* resonance (so a valid transaction can't unlock an account it wasn't
   bought by), and on success stores the encrypted `originalTransactionId`
   (Apple) / `purchaseToken` (Google) plus a keyed fingerprint with a DB
   unique index (so one transaction can't be claimed by two accounts).
   Returns the refreshed state. Mismatched account token → **403**
   `account_mismatch`; already-claimed → **409** `already_claimed`.
4. Renewals, cancellations, refunds, and billing retries arrive
   server-to-server (App Store Server Notifications V2, Play Real-Time
   Developer Notifications) at webhook endpoints, so entitlement stays
   current without the app present.

Verification goes through each storefront's server API (Apple's App Store
Server API `GET /inApps/v1/transactions/{id}`; Google's
`purchases.subscriptionsv2.get`) rather than hand-validating signature
chains — the storefront is the authority, and our code stays HTTP +
entitlement logic.

Cancellation has no native path: the OS owns subscription management
(iOS Settings / Play subscriptions). The apps link out to the system screen
and describe where to manage it, the same way the web app owns Stripe's
cancel flow.

## Continuity (cross-device safety)

Send `Assert-Yours-Universe-Time: <day>:<message count>` with `POST /stream`
and `PUT /textarea`. If the client is behind the server — the space moved
forward on another device — the server answers **409** with
`{ error: "continuity_divergence", message, server_universe_time }`. Show the
message, offer a refresh. After each successful stream the server emits the
new `universe_time` (see below); keep it.

## Structured errors (native clients)

Denials arrive as JSON with stable `error` codes:

- **401** `{ error: "unauthenticated", message }` — token missing/expired
- **403** `{ error: "subscription_required", message }` — day 2+ without a
  subscription; day 1 is always free
- **409** `{ error: "continuity_divergence", ... }` — as above

Web clients get redirects-with-alerts for the same conditions.

## The SSE stream

`POST /stream` relays Lightward AI's Anthropic-shaped events and adds its
own. Events arrive as `event: <name>\ndata: <json>\n\n`:

- `message_start` — clear the pulsing placeholder
- `content_block_delta` — append `data.delta.text` when
  `data.delta.type == "text_delta"`
- `message_stop` — message complete; apply full markdown treatment
- `universe_time` — `{ universe_time }`: the server saved the narrative;
  adopt this value
- `error` — `{ error: { message } }`: display it
- `end` — always last; **arrives with no data line and no trailing blank
  line**, so flush your parser at EOF

## Rendering rules shared by all clients

Markdown handling is deliberately minimal and identical everywhere: bold
(`**` / `__`) and italic (`*` / `_`, word-boundary-bound so `*a* ... *b*`
never spans), indicators kept visible but dimmed (opacity 0.7). During
streaming, indicators dim only; full styling lands at `message_stop`. The
reference implementation is `renderMarkdown` in `chat_controller.js`; the
ports are `ios/Yours/Support/MarkdownLite.swift` and
`android/.../support/MarkdownLite.kt`, each with parity tests
(`ios/YoursTests/MarkdownLiteTests.swift`,
`android/app/src/test/.../MarkdownLiteTest.kt`).

The day counter reads "1 day" on day 1 and "day N" after — everywhere,
always, with a non-breaking space.

## Draft sync

The composer draft saves locally on every keystroke (web: localStorage;
iOS: UserDefaults, key `yours-input-<universe_time>`) and to the server
(`PUT /textarea`) after 1.5s of stillness. On load, prefer whichever of
server/local is longer. Clear both when a message sends.
