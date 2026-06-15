require "rails_helper"

# The native client protocol (see PROTOCOL.md): ios/ and android/ sign in
# through the ordinary web Google flow inside a system browser sheet, then
# carry the google_id in an encrypted bearer token instead of a session
# cookie. These specs protect the invariants that make that safe:
#
# - the handshake only succeeds for the app instance that started it (PKCE)
# - the google_id stays structurally opaque in everything that travels
# - bearer requests work without cookies or CSRF tokens, while cookie
#   requests remain CSRF-protected
RSpec.describe "Native client protocol", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:google_id) { "google-user-123" }
  let(:code_verifier) { "native-app-generated-verifier-with-plenty-of-entropy" }
  let(:code_challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false) }

  before do
    host! "test.host"
  end

  # Walks the full native sign-in handshake: the app opens /native/auth in a
  # browser session, the human completes ordinary Google sign-in, and the
  # server redirects back into the app with a one-time code.
  def native_sign_in
    get "/native/auth", params: { code_challenge: code_challenge }
    expect(response).to redirect_to(root_path)

    identity = double("GoogleSignIn::Identity", user_id: google_id, email_address: "test@example.com")
    allow(GoogleSignIn::Identity).to receive(:new).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:flash).and_return(
      { google_sign_in: { "id_token" => "fake_token" } }
    )
    get root_path
    allow_any_instance_of(ApplicationController).to receive(:flash).and_call_original

    # Sign-in lands on the consent gate, never straight at the app — the code
    # is only minted by the deliberate confirmation POST.
    expect(response).to redirect_to(native_auth_confirm_path)
    post "/native/auth/confirm"

    expect(response.location).to start_with("yours://auth?code=")
    CGI.parse(URI.parse(response.location).query)["code"].first
  end

  def obtain_bearer_token
    code = native_sign_in
    post "/native/token", params: { code: code, code_verifier: code_verifier }
    expect(response).to have_http_status(:success)
    token = JSON.parse(response.body).fetch("token")

    # Drop the browser session so subsequent requests prove the bearer token
    # authenticates on its own — the app's URLSession won't carry cookies.
    get "/exit"

    token
  end

  describe "sign-in handshake" do
    it "exchanges a code for a working bearer token" do
      token = obtain_bearer_token

      get "/native/state", headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:success)
      state = JSON.parse(response.body)
      expect(state["universe_day"]).to eq(1)
      expect(state["universe_time"]).to eq("1:0")
      expect(state["narrative"]).to eq([])
      expect(state["obfuscated_email"]).to eq("te··@ex··")
      expect(state["subscription_active"]).to eq(false)
    end

    it "returns the obfuscated email alongside the token" do
      code = native_sign_in
      post "/native/token", params: { code: code, code_verifier: code_verifier }

      expect(JSON.parse(response.body)["obfuscated_email"]).to eq("te··@ex··")
    end

    # Regression test for the C1 account-takeover: an app opened on a device
    # where someone is *already* signed into the web app must NOT be handed a
    # code for that someone without a deliberate confirmation. The existence of
    # a browser session is not consent.
    it "does not auto-issue a code when a browser session already exists" do
      # User A is already signed into the web app in this browser
      identity = double("GoogleSignIn::Identity", user_id: google_id, email_address: "test@example.com")
      allow(GoogleSignIn::Identity).to receive(:new).and_return(identity)
      allow_any_instance_of(ApplicationController).to receive(:flash).and_return(
        { google_sign_in: { "id_token" => "fake_token" } }
      )
      get root_path
      allow_any_instance_of(ApplicationController).to receive(:flash).and_call_original

      # A native app (attacker's, holding its own verifier) starts sign-in
      get "/native/auth", params: { code_challenge: code_challenge }

      # It is sent to the consent gate, NOT handed a token
      expect(response).to redirect_to(native_auth_confirm_path)
      expect(response.location).not_to start_with("yours://auth?code=")
    end

    it "issues the code only after the explicit confirmation tap" do
      identity = double("GoogleSignIn::Identity", user_id: google_id, email_address: "test@example.com")
      allow(GoogleSignIn::Identity).to receive(:new).and_return(identity)
      allow_any_instance_of(ApplicationController).to receive(:flash).and_return(
        { google_sign_in: { "id_token" => "fake_token" } }
      )
      get root_path
      allow_any_instance_of(ApplicationController).to receive(:flash).and_call_original

      get "/native/auth", params: { code_challenge: code_challenge }
      expect(response).to redirect_to(native_auth_confirm_path)

      # The deliberate human action
      post "/native/auth/confirm"
      expect(response.location).to start_with("yours://auth?code=")
    end

    it "refuses to confirm without a pending native challenge" do
      # Signed in, but no native sign-in was started — a stray POST can't mint
      identity = double("GoogleSignIn::Identity", user_id: google_id, email_address: "test@example.com")
      allow(GoogleSignIn::Identity).to receive(:new).and_return(identity)
      allow_any_instance_of(ApplicationController).to receive(:flash).and_return(
        { google_sign_in: { "id_token" => "fake_token" } }
      )
      get root_path
      allow_any_instance_of(ApplicationController).to receive(:flash).and_call_original

      post "/native/auth/confirm"
      expect(response.location).not_to start_with("yours://auth?code=")
    end

    it "rejects a missing code challenge" do
      get "/native/auth"
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Missing code challenge")
    end

    it "rejects token exchange with the wrong verifier" do
      code = native_sign_in
      post "/native/token", params: { code: code, code_verifier: "not-the-verifier" }

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_code")
    end

    it "rejects expired codes" do
      code = native_sign_in

      travel 2.minutes do
        post "/native/token", params: { code: code, code_verifier: code_verifier }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    it "rejects garbage codes" do
      post "/native/token", params: { code: "garbage", code_verifier: code_verifier }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "structural opacity of transit artifacts" do
    # The topological encryption invariant extends to the native protocol:
    # nothing that travels through the handshake may expose the google_id,
    # at any decodable layer. (Encrypted is safe; encoded is not.)
    it "never exposes the google_id in codes or tokens" do
      code = native_sign_in
      post "/native/token", params: { code: code, code_verifier: code_verifier }
      token = JSON.parse(response.body).fetch("token")

      [ code, token ].each do |artifact|
        expect(artifact).not_to include(google_id)

        decoded_layers = artifact.split("--").filter_map do |part|
          begin
            Base64.decode64(part)
          rescue StandardError
            nil
          end
        end
        expect(decoded_layers).not_to be_empty
        decoded_layers.each do |layer|
          expect(layer).not_to include(google_id)
        end
      end
    end
  end

  describe "bearer-authenticated requests" do
    it "rejects state requests without a token" do
      get "/native/state"
      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["error"]).to eq("unauthenticated")
    end

    it "rejects state requests with a garbage token" do
      get "/native/state", headers: { "Authorization" => "Bearer garbage" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects expired tokens" do
      token = obtain_bearer_token

      travel (NativeToken::TOKEN_TTL + 1.day) do
        get "/native/state", headers: { "Authorization" => "Bearer #{token}" }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    it "includes subscription details when asked" do
      token = obtain_bearer_token
      details = { status: "active", amount: 1000, currency: "usd", interval: "month",
                  cancel_at_period_end: false, current_period_end: Time.at(0), id: "sub_123" }
      allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(true)
      allow_any_instance_of(Resonance).to receive(:subscription_details).and_return(details)

      get "/native/state", params: { include: "subscription" }, headers: { "Authorization" => "Bearer #{token}" }

      state = JSON.parse(response.body)
      expect(state["subscription_active"]).to eq(true)
      expect(state["subscription"]["status"]).to eq("active")
    end

    context "with forgery protection enabled (as in production)" do
      # The bearer token is minted via the browser handshake while forgery
      # protection is off (the handshake is cookie+CSRF-backed and uses real
      # form tokens in production); we then enable forgery protection to prove
      # the *bearer* requests afterward need no CSRF token.
      def with_forgery_protection
        ActionController::Base.allow_forgery_protection = true
        yield
      ensure
        ActionController::Base.allow_forgery_protection = false
      end

      it "accepts bearer-authenticated writes without a CSRF token" do
        token = obtain_bearer_token

        with_forgery_protection do
          put "/textarea",
            params: { textarea: "draft from the phone" },
            headers: { "Authorization" => "Bearer #{token}" }
        end

        expect(response).to have_http_status(:success)
        expect(Resonance.find_by_google_id(google_id).textarea).to eq("draft from the phone")
      end

      it "still protects cookie-authenticated writes" do
        with_forgery_protection do
          # show_exceptions = :rescuable renders InvalidAuthenticityToken as 422
          put "/textarea", params: { textarea: "forged" }
        end
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    # P0 regression: the browser sign-in confirm POST is cookie+session backed
    # and MUST keep CSRF protection — it is NOT part of the stateless bearer
    # API, even though its path starts with /native/.
    it "keeps CSRF protection on the browser confirm POST" do
      # Sign in (forgery off) so a session exists with a pending challenge
      get "/native/auth", params: { code_challenge: code_challenge }
      identity = double("GoogleSignIn::Identity", user_id: google_id, email_address: "test@example.com")
      allow(GoogleSignIn::Identity).to receive(:new).and_return(identity)
      allow_any_instance_of(ApplicationController).to receive(:flash).and_return(
        { google_sign_in: { "id_token" => "fake_token" } }
      )
      get root_path
      allow_any_instance_of(ApplicationController).to receive(:flash).and_call_original

      ActionController::Base.allow_forgery_protection = true
      begin
        post "/native/auth/confirm" # no CSRF token
        expect(response).to have_http_status(:unprocessable_content)
      ensure
        ActionController::Base.allow_forgery_protection = false
      end
    end

    it "denies textarea save with the structured contract codes (H1 regression)" do
      # No token at all -> unauthenticated code, not a human string in `error`
      put "/textarea", params: { textarea: "x" },
        headers: { "Authorization" => "Bearer garbage" }
      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["error"]).to eq("unauthenticated")

      # Day 2+ without subscription -> subscription_required code
      token = obtain_bearer_token
      resonance = Resonance.find_by_google_id(google_id)
      resonance.universe_day = 2
      resonance.save!
      allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(false)

      put "/textarea", params: { textarea: "x" },
        headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["error"]).to eq("subscription_required")
      expect(JSON.parse(response.body)["message"]).to be_present
    end

    it "streams chat over a bearer token and saves the narrative" do
      token = obtain_bearer_token

      stub_const("ENV", ENV.to_hash.merge("LIGHTWARD_AI_API_URL" => "https://api.example.com/chat"))

      http_response = Net::HTTPOK.new("1.1", "200", "OK")
      allow(http_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(http_response).to receive(:read_body).and_yield(
        "event: content_block_delta\ndata: {\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello!\"}}\n\n"
      )

      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_yield(http_response)

      message = { role: "user", content: [ { type: "text", text: "Hello" } ] }
      post "/stream", params: { message: message }, headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("content_block_delta")
      expect(response.body).to include("universe_time")

      narrative = Resonance.find_by_google_id(google_id).narrative_accumulation_by_day
      expect(narrative.length).to eq(2)
      expect(narrative.last["content"].first["text"]).to eq("Hello!")
    end

    it "denies streaming with structured JSON when subscription is required" do
      token = obtain_bearer_token
      resonance = Resonance.find_by_google_id(google_id)
      resonance.universe_day = 2
      resonance.save!
      allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(false)

      message = { role: "user", content: [ { type: "text", text: "Hello" } ] }
      post "/stream", params: { message: message }, headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["error"]).to eq("subscription_required")
    end

    it "starts sleep integration and reports it as JSON" do
      token = obtain_bearer_token
      allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(true)
      allow_any_instance_of(ApplicationController).to receive(:create_integration_harmonic_for).and_return("a harmonic")

      post "/sleep", headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("integrating")
      expect(body["starting_universe_time"]).to eq("1:0")
    end
  end

  describe "POST /native/subscription (in-app purchase verification)" do
    # The account token the buying account must present (StoreKit
    # appAccountToken / Play obfuscatedExternalAccountId).
    let(:account_token) { Resonance.find_or_create_by_google_id(google_id).iap_account_token }

    it "records an Apple subscription the storefront confirms, and returns refreshed state" do
      token = obtain_bearer_token
      result = AppleAppStore::Result.new(
        original_transaction_id: "2000000000000001",
        product_id: "fyi.yours.subscription.tier_1",
        active: true,
        app_account_token: account_token
      )
      allow_any_instance_of(AppleAppStore).to receive(:verify).and_return(result)

      post "/native/subscription",
        params: { platform: "apple", signed_transaction: "signed.jws.value" },
        headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:success)
      # Reported without a second storefront round-trip (we just verified it)
      expect(JSON.parse(response.body)["subscription_active"]).to eq(true)

      # Stored encrypted, decryptable only with the google_id
      expect(Resonance.find_by_google_id(google_id).apple_original_transaction_id)
        .to eq("2000000000000001")
    end

    it "rejects Google Play purchases while billing is gated off" do
      token = obtain_bearer_token # configured? is false in test (no service account)

      post "/native/subscription",
        params: { platform: "google", signed_transaction: "play-token-abc" },
        headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:not_implemented)
      expect(JSON.parse(response.body)["error"]).to eq("platform_unavailable")
    end

    it "records a Google Play subscription the storefront confirms (when configured)" do
      allow(GooglePlayStore).to receive(:configured?).and_return(true)
      token = obtain_bearer_token
      result = GooglePlayStore::Result.new(
        purchase_token: "play-token-abc",
        product_id: "subscription_tier_1",
        active: true,
        account_token: account_token
      )
      allow_any_instance_of(GooglePlayStore).to receive(:verify).and_return(result)

      post "/native/subscription",
        params: { platform: "google", signed_transaction: "play-token-abc" },
        headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:success)
      expect(Resonance.find_by_google_id(google_id).google_play_purchase_token)
        .to eq("play-token-abc")
    end

    # P0 regression: a verified transaction must not unlock an account it
    # wasn't bought by. Without the appAccountToken binding, a valid JWS could
    # be replayed from any account.
    it "rejects a verified transaction whose account token doesn't match (cross-account replay)" do
      token = obtain_bearer_token
      result = AppleAppStore::Result.new(
        original_transaction_id: "2000000000000001",
        product_id: "fyi.yours.subscription.tier_1",
        active: true,
        app_account_token: "00000000-0000-0000-0000-000000000000" # someone else's
      )
      allow_any_instance_of(AppleAppStore).to receive(:verify).and_return(result)

      post "/native/subscription",
        params: { platform: "apple", signed_transaction: "signed.jws.value" },
        headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["error"]).to eq("account_mismatch")
      expect(Resonance.find_by_google_id(google_id).apple_original_transaction_id).to be_nil
    end

    it "rejects a verified transaction with no account token at all (unbound)" do
      token = obtain_bearer_token
      result = AppleAppStore::Result.new(
        original_transaction_id: "2000000000000001",
        product_id: "fyi.yours.subscription.tier_1",
        active: true,
        app_account_token: nil
      )
      allow_any_instance_of(AppleAppStore).to receive(:verify).and_return(result)

      post "/native/subscription",
        params: { platform: "apple", signed_transaction: "signed.jws.value" },
        headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:forbidden)
    end

    # P0 regression: the same transaction can't be recorded against two
    # different accounts (DB unique fingerprint), even if both somehow presented
    # a matching token.
    it "refuses a transaction already claimed by another resonance" do
      # Account A claims the transaction directly
      other = Resonance.find_or_create_by_google_id("other-account-xyz")
      other.record_apple_subscription("2000000000000001")

      # Account B (our bearer user) presents the same transaction with a token
      # that matches B — but the fingerprint already belongs to A.
      token = obtain_bearer_token
      result = AppleAppStore::Result.new(
        original_transaction_id: "2000000000000001",
        product_id: "fyi.yours.subscription.tier_1",
        active: true,
        app_account_token: account_token
      )
      allow_any_instance_of(AppleAppStore).to receive(:verify).and_return(result)

      post "/native/subscription",
        params: { platform: "apple", signed_transaction: "signed.jws.value" },
        headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)["error"]).to eq("already_claimed")
    end

    it "rejects a transaction the storefront does not confirm" do
      token = obtain_bearer_token
      allow_any_instance_of(AppleAppStore).to receive(:verify).and_return(nil)

      post "/native/subscription",
        params: { platform: "apple", signed_transaction: "forged" },
        headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to eq("subscription_not_verified")
      expect(Resonance.find_by_google_id(google_id).apple_original_transaction_id).to be_nil
    end

    it "does not record a verified-but-inactive subscription" do
      token = obtain_bearer_token
      result = AppleAppStore::Result.new(
        original_transaction_id: "2000000000000001",
        product_id: "fyi.yours.subscription.tier_1",
        active: false
      )
      allow_any_instance_of(AppleAppStore).to receive(:verify).and_return(result)

      post "/native/subscription",
        params: { platform: "apple", signed_transaction: "signed.jws.value" },
        headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(Resonance.find_by_google_id(google_id).apple_original_transaction_id).to be_nil
    end

    it "rejects an unknown platform" do
      token = obtain_bearer_token
      post "/native/subscription",
        params: { platform: "windows", signed_transaction: "x" },
        headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/native/subscription", params: { platform: "apple", signed_transaction: "x" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "surfaces a storefront verification failure as 502" do
      token = obtain_bearer_token
      allow_any_instance_of(AppleAppStore).to receive(:verify)
        .and_raise(AppleAppStore::VerificationError, "Apple down")
      allow(Rollbar).to receive(:error)

      post "/native/subscription",
        params: { platform: "apple", signed_transaction: "x" },
        headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:bad_gateway)
    end
  end

  describe "storefront notification webhooks" do
    # Entitlement is verified live at read time, so these just acknowledge.
    it "acknowledges App Store Server Notifications" do
      post "/native/apple_notifications", params: { signedPayload: "jws" }
      expect(response).to have_http_status(:ok)
    end

    it "acknowledges Play Real-Time Developer Notifications" do
      post "/native/google_notifications", params: { message: { data: "base64" } }
      expect(response).to have_http_status(:ok)
    end
  end
end
