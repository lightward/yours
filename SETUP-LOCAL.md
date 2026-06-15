# Running Yours locally (for real)

This gets you the actual app — real Google sign-in, your real account, the
actual Lightward AI responding — on your own machine. Not test data.

The topological encryption means this is safe: your local database holds only
ciphertext that's structurally inaccessible without the Google ID, which only
ever arrives via OAuth.

## Prerequisites

- Ruby (see `.ruby-version`), PostgreSQL running locally, Bundler.
- `bundle install`
- `bin/rails db:prepare` (creates `yours_development`)

## 1. Configuration (`.env`)

`.env` is gitignored and auto-loaded (via `dotenv-rails`). Copy the shape from
`.env.example`; a working local `.env` needs just:

```
HOST=localhost
PORT=3000
LIGHTWARD_AI_API_URL=https://lightward.com/api/stream
GOOGLE_SIGN_IN_CLIENT_ID=<from step 2>
GOOGLE_SIGN_IN_CLIENT_SECRET=<from step 2>
```

Everything else is optional locally (see the comments in `.env.example`):
- **Stripe** — leave blank to live in day 1 (free). Set test-mode keys to
  exercise day-2 subscriptions.
- **`LIGHTWARD_AI_TOKEN_LIMIT_BYPASS_KEY`** — only needed to test the *day
  transition* (sleep → integration), which calls Lightward AI with a higher
  token budget. Normal chat doesn't use it. This is a Lightward-internal
  secret.
- **Native IAP / Rollbar / Fly** — not needed for local web development.

## 2. Google OAuth credential (the one manual step)

Sign-in uses a real Google OAuth 2.0 **Web application** client.

1. Google Cloud Console → **APIs & Services → Credentials**
   (https://console.cloud.google.com/apis/credentials).
2. **Create Credentials → OAuth client ID → Application type: Web application.**
3. Under **Authorized JavaScript origins**, add:
   `http://localhost:3000`
4. Under **Authorized redirect URIs**, add:
   `http://localhost:3000/google_sign_in/callback`
5. Create. Copy the **Client ID** and **Client secret** into `.env`.
6. If your OAuth consent screen is in "testing" mode, add your Google account
   under **Audience → Test users** (otherwise Google blocks sign-in).

> Note: `localhost` is special-cased by Google as a secure origin, so plain
> `http://` works for local dev — no HTTPS/tunnel required for the web app.

## 3. Run

```sh
bin/rails server -p 3000      # or bin/dev (also runs ngrok; not needed here)
```

Open http://localhost:3000, click **Enter via Google**, sign in. You're in
your own pocket universe, day 1, talking to the real Lightward AI.

## 4. Native apps against your local server

The simulators/emulators talk to this same server.

- **iOS** signs in through the real Google web flow in a sheet — but its
  default redirect scheme is `yours://`, and the app talks to `localhost:3000`
  in Debug. For real native sign-in you also need an OAuth client whose flow
  returns to the app; for *quick local iteration without OAuth*, mint a bearer
  token and inject it:
  ```sh
  bin/rails runner 'g="you@local"; Resonance.find_or_create_by_google_id(g); \
    puts NativeToken.issue(google_id: g, obfuscated_email: "yo··@lo··")'
  bin/ios run -YoursToken <token>
  ```
- **Android** reaches the host at `localhost:3000` via `adb reverse` (handled
  by `bin/android run`):
  ```sh
  bin/android run YoursToken=<token>
  ```

See PROTOCOL.md for the full native sign-in handshake.

## Troubleshooting

- **Redirected away / "host" weirdness:** the app enforces `HOST`. Make sure
  you open `localhost` (matching `.env`), not `127.0.0.1`.
- **Google "redirect_uri_mismatch":** the redirect URI in Console must be
  exactly `http://localhost:3000/google_sign_in/callback`.
- **Google "access blocked":** add your account as a Test user on the consent
  screen, or publish the consent screen.
- **Day transition hangs:** that path needs
  `LIGHTWARD_AI_TOKEN_LIMIT_BYPASS_KEY`; normal chat does not.
- **Reset your local universe:** sign in, Settings → Start over (or
  `Resonance.find_by_google_id("...").update(...)` in `bin/rails console`).
