require "rails_helper"

RSpec.describe ApplicationController, type: :request do
  let(:google_id) { "google-user-123" }
  let(:resonance) { Resonance.find_or_create_by_google_id(google_id) }

  before do
    host! "test.host"
  end

  # Helper to simulate signed-in state
  def sign_in_as(google_id, email: "test@example.com")
    identity = double("GoogleSignIn::Identity", user_id: google_id, email_address: email)
    allow(GoogleSignIn::Identity).to receive(:new).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:flash).and_return(
      { google_sign_in: { "id_token" => "fake_token" } }
    )
    get root_path
    # Reset flash after sign-in to avoid interfering with subsequent requests
    allow_any_instance_of(ApplicationController).to receive(:flash).and_call_original
  end

  describe "GET / (root)" do
    context "when not authenticated" do
      it "shows landing page" do
        get root_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Enter via Google")
      end
    end

    context "when authenticated with Google OAuth callback" do
      let(:id_token) { "fake.jwt.token" }

      before do
        identity = double("GoogleSignIn::Identity", user_id: google_id, email_address: "test@example.com")
        allow(GoogleSignIn::Identity).to receive(:new).with(id_token).and_return(identity)
      end

      it "creates a new resonance for first-time sign in" do
        allow_any_instance_of(ApplicationController).to receive(:flash).and_return(
          { google_sign_in: { "id_token" => id_token } }
        )
        expect {
          get root_path
        }.to change(Resonance, :count).by(1)
      end

      it "sets the session google_id" do
        allow_any_instance_of(ApplicationController).to receive(:flash).and_return(
          { google_sign_in: { "id_token" => id_token } }
        )
        get root_path
        expect(session[:google_id]).to eq(google_id)
      end

      it "redirects to root path after authentication" do
        allow_any_instance_of(ApplicationController).to receive(:flash).and_return(
          { google_sign_in: { "id_token" => id_token } }
        )
        get root_path
        expect(response).to redirect_to(root_path)
      end

      it "finds existing resonance on subsequent sign in" do
        resonance = Resonance.find_or_create_by_google_id(google_id)
        allow_any_instance_of(ApplicationController).to receive(:flash).and_return(
          { google_sign_in: { "id_token" => id_token } }
        )

        expect {
          get root_path
        }.not_to change(Resonance, :count)

        expect(session[:google_id]).to eq(google_id)
      end

      context "when google authentication fails" do
        it "redirects with an alert when error in flash" do
          allow_any_instance_of(ApplicationController).to receive(:flash).and_return(
            { google_sign_in: { "error" => "invalid_token" } }
          )
          get root_path
          expect(response).to redirect_to(root_path)
        end

        it "does not create a resonance on error" do
          allow_any_instance_of(ApplicationController).to receive(:flash).and_return(
            { google_sign_in: { "error" => "invalid_token" } }
          )
          expect {
            get root_path
          }.not_to change(Resonance, :count)
        end
      end
    end

    context "when authenticated but no active subscription" do
      before do
        sign_in_as(google_id)
        allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(false)
      end

      context "on day 1" do
        before do
          resonance.universe_day = 1
          resonance.save!
        end

        it "shows chat interface (day 1 is free)" do
          get root_path
          expect(response).to have_http_status(:success)
          expect(response.body).to include("Subscribe for day 2")
        end
      end

      context "on day 2+" do
        before do
          resonance.universe_day = 2
          resonance.save!
        end

        it "redirects to settings page" do
          get root_path
          expect(response).to redirect_to(settings_path)
        end
      end
    end

    context "when authenticated with active subscription" do
      before do
        sign_in_as(google_id)
        allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(true)
      end

      it "shows chat interface" do
        get root_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Move to day")
      end

      it "shows README link in header" do
        get root_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include("https://github.com/lightward/yours/blob/main/README.md")
      end

      it "shows 'day X' format for day 2+" do
        resonance.universe_day = 5
        resonance.save!
        get root_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Yours: day\u00A05")
      end

      it "shows day navigation even with empty chat (allows silent days)" do
        resonance.universe_day = 1
        resonance.narrative_accumulation_by_day = []
        resonance.save!
        get root_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Move to day 2")
      end
    end
  end

  describe "header day counter formatting" do
    before do
      sign_in_as(google_id)
      allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(true)
    end

    it "shows '1 day' format on day 1" do
      resonance.universe_day = 1
      resonance.save!
      get root_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Yours: 1\u00A0day")
      expect(response.body).not_to include("Yours: day\u00A01")
    end

    it "shows 'day X' format for day 2+" do
      resonance.universe_day = 2
      resonance.save!
      get root_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Yours: day\u00A02")
    end

    it "includes Yours-Universe-Time header" do
      get root_path
      expect(response.headers['Yours-Universe-Time']).to eq(resonance.universe_time)
    end
  end

  describe "GET /exit" do
    it "clears the session and redirects to root" do
      sign_in_as(google_id)

      get exit_path

      expect(response).to redirect_to(root_path)
      expect(session[:google_id]).to be_nil
      expect(session[:obfuscated_user_email]).to be_nil
    end
  end

  describe "GET /settings" do
    context "when not authenticated" do
      it "redirects to root with alert" do
        get settings_path
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("Please sign in")
      end
    end

    context "on day 1" do
      before do
        sign_in_as(google_id)
        resonance.universe_day = 1
        resonance.save!
      end

      it "shows settings page with subscription options" do
        get settings_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include("What feels right?")
        expect(response.body).to include("$1/month")
      end
    end

    context "on day 2+" do
      before do
        sign_in_as(google_id)
        resonance.universe_day = 2
        resonance.save!
      end

      context "when authenticated with active subscription" do
        before do
          allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(true)
        end

        it "shows settings details" do
          details = {
            id: "sub_test123",
            status: "active",
            current_period_end: 30.days.from_now,
            amount: 1000,
            currency: "usd",
            interval: "month"
          }

          allow_any_instance_of(Resonance).to receive(:subscription_details).and_return(details)

          get settings_path

          expect(response).to have_http_status(:success)
          expect(response.body).to include("Settings")
        end

        it "shows 'Cancel renewal' button when subscription is active" do
          details = {
            id: "sub_test123",
            status: "active",
            current_period_end: 30.days.from_now,
            amount: 1000,
            currency: "usd",
            interval: "month",
            cancel_at_period_end: false
          }
          allow_any_instance_of(Resonance).to receive(:subscription_details).and_return(details)

          get settings_path

          expect(response).to have_http_status(:success)
          expect(response.body).to include("Cancel renewal")
          expect(response.body).not_to include("Cancel subscription")
        end

        it "shows 'Cancel immediately' button when renewal is already canceled" do
          details = {
            id: "sub_test123",
            status: "active",
            current_period_end: 30.days.from_now,
            amount: 1000,
            currency: "usd",
            interval: "month",
            cancel_at_period_end: true
          }
          allow_any_instance_of(Resonance).to receive(:subscription_details).and_return(details)

          get settings_path

          expect(response).to have_http_status(:success)
          expect(response.body).to include("Cancel immediately")
        end

        it "shows enabled 'start over' button" do
          details = {
            id: "sub_test123",
            status: "active",
            current_period_end: 30.days.from_now,
            amount: 1000,
            currency: "usd",
            interval: "month"
          }
          allow_any_instance_of(Resonance).to receive(:subscription_details).and_return(details)

          get settings_path

          expect(response).to have_http_status(:success)
          expect(response.body).to include("Start over")
          expect(response.body).to include("Begin at the beginning")
          expect(response.body).to include("There is no undo")
          expect(response.body).not_to include("This unlocks for subscribers")
        end
      end

      context "when authenticated but no active subscription" do
        before do
          allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(false)
        end

        it "shows settings page with subscription buttons" do
          get settings_path

          expect(response).to have_http_status(:success)
          expect(response.body).to include("What feels right?")
          expect(response.body).to include("$1/month")
          expect(response.body).to include("$10/month")
        end

        it "shows disabled 'start over' button with explanatory text" do
          allow_any_instance_of(Resonance).to receive(:subscription_details).and_return(nil)

          get settings_path

          expect(response).to have_http_status(:success)
          expect(response.body).to include("Start over")
          expect(response.body).to include("disabled")
          expect(response.body).to include("This unlocks for subscribers")
        end
      end
    end
  end

  describe "POST /stream" do
    let(:message) do
      {
        role: "user",
        content: [ { type: "text", text: "Hello" } ]
      }
    end

    context "when not authenticated" do
      it "redirects to root with alert" do
        post stream_path, params: { message: message }
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("Please sign in")
      end
    end

    context "continuity divergence checking" do
      before do
        sign_in_as(google_id)
        allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(true)
        # Set resonance to a known universe_time state with some existing narrative
        resonance.universe_day = 1
        resonance.narrative_accumulation_by_day = [
          { "role" => "user", "content" => [ { "type" => "text", "text" => "Hello" } ] },
          { "role" => "assistant", "content" => [ { "type" => "text", "text" => "Hi there" } ] },
          { "role" => "user", "content" => [ { "type" => "text", "text" => "How are you?" } ] },
          { "role" => "assistant", "content" => [ { "type" => "text", "text" => "Good!" } ] },
          { "role" => "user", "content" => [ { "type" => "text", "text" => "Great" } ] }
        ]
        resonance.save!
      end

      it "rejects request when client is behind server (different count)" do
        # Server is at day 1, count 5 (5 messages in narrative)
        server_time = resonance.universe_time # Should be "1:5"
        expect(server_time).to eq("1:5")

        # Client thinks they're at day 1, count 3 (older)
        client_time = "1:3"

        post stream_path, params: { message: message }, headers: { "Assert-Yours-Universe-Time" => client_time }

        expect(response).to have_http_status(409)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("continuity_divergence")
        expect(json["server_universe_time"]).to eq(server_time)
      end

      it "accepts request when client and server match" do
        stub_const("ENV", ENV.to_hash.merge("LIGHTWARD_AI_API_URL" => "https://api.example.com/chat"))

        http_response = Net::HTTPOK.new("1.1", "200", "OK")
        allow(http_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(http_response).to receive(:read_body).and_yield("event: content_block_delta\ndata: {\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello!\"}}\n\n")

        http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:use_ssl=)
        allow(http).to receive(:read_timeout=)

        # Capture the request to verify it doesn't include bypass header
        captured_request = nil
        allow(http).to receive(:request) do |request, &block|
          captured_request = request
          block.call(http_response) if block
        end

        server_time = resonance.universe_time

        post stream_path, params: { message: message }, headers: { "Assert-Yours-Universe-Time" => server_time }

        expect(response).to have_http_status(200)
        expect(captured_request["Token-Limit-Bypass-Key"]).to be_nil
      end
    end

    context "when authenticated but no active subscription" do
      before do
        sign_in_as(google_id)
        allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(false)
      end

      context "on day 1" do
        before do
          resonance.universe_day = 1
          resonance.save!

          stub_const("ENV", ENV.to_hash.merge("LIGHTWARD_AI_API_URL" => "https://api.example.com/chat"))

          # Mock successful streaming response
          http_response = Net::HTTPOK.new("1.1", "200", "OK")
          allow(http_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
          allow(http_response).to receive(:read_body).and_yield("event: content_block_delta\ndata: {\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello!\"}}\n\n")

          http = instance_double(Net::HTTP)
          allow(Net::HTTP).to receive(:new).and_return(http)
          allow(http).to receive(:use_ssl=)
          allow(http).to receive(:read_timeout=)
          allow(http).to receive(:request).and_yield(http_response)
        end

        it "allows streaming (day 1 is free)" do
          post stream_path, params: { message: message }
          expect(response.body).to include("Hello!")
        end
      end

      context "on day 2+" do
        before do
          resonance.universe_day = 2
          resonance.save!
        end

        it "redirects to root with alert" do
          post stream_path, params: { message: message }
          expect(response).to redirect_to(root_path)
          # Following the redirect would hit the index action again, which redirects to settings
          # The flash message is set and will be displayed on the settings page
        end
      end
    end

    context "when authenticated with active subscription" do
      before do
        sign_in_as(google_id)
        allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(true)
      end

      context "when Lightward AI API returns non-success response" do
        before do
          stub_const("ENV", ENV.to_hash.merge("LIGHTWARD_AI_API_URL" => "https://api.example.com/chat"))

          # Mock the HTTP response
          http_response = Net::HTTPBadRequest.new("1.1", "400", "Bad Request")
          allow(http_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
          allow(http_response).to receive(:code).and_return("400")
          allow(http_response).to receive(:message).and_return("Bad Request")

          # Mock Net::HTTP
          http = instance_double(Net::HTTP)
          allow(Net::HTTP).to receive(:new).and_return(http)
          allow(http).to receive(:use_ssl=)
          allow(http).to receive(:read_timeout=)
          allow(http).to receive(:request).and_yield(http_response)
        end

        it "raises an error and sends error SSE event" do
          post stream_path, params: { message: message }
          expect(response.body).to include("event: error")
        end
      end

      context "when Lightward AI API returns success" do
        before do
          stub_const("ENV", ENV.to_hash.merge("LIGHTWARD_AI_API_URL" => "https://api.example.com/chat"))

          # Mock successful streaming response
          http_response = Net::HTTPOK.new("1.1", "200", "OK")
          allow(http_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
          allow(http_response).to receive(:read_body).and_yield("event: content_block_delta\ndata: {\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello!\"}}\n\n")

          http = instance_double(Net::HTTP)
          allow(Net::HTTP).to receive(:new).and_return(http)
          allow(http).to receive(:use_ssl=)
          allow(http).to receive(:read_timeout=)
          allow(http).to receive(:request).and_yield(http_response)
        end

        it "streams the response successfully" do
          post stream_path, params: { message: message }
          expect(response.body).to include("Hello!")
        end

        it "saves the narrative after streaming" do
          expect {
            post stream_path, params: { message: message }
          }.to change { resonance.reload.narrative_accumulation_by_day&.size }.by(2)
        end
      end
    end
  end

  describe "POST /sleep" do
    context "when not authenticated" do
      it "redirects to root with alert" do
        post sleep_path
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("Please sign in")
      end
    end

    context "when authenticated but no active subscription" do
      before do
        sign_in_as(google_id)
        allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(false)
      end

      context "on day 1" do
        before do
          resonance.universe_day = 1
          resonance.narrative_accumulation_by_day = [
            { "role" => "user", "content" => [ { "type" => "text", "text" => "Hello" } ] }
          ]
          resonance.save!
        end

        it "redirects to root with alert (subscription required)" do
          post sleep_path
          expect(response).to redirect_to(root_path)
          follow_redirect!
          expect(response.body).to include("Subscribe to continue")
        end
      end

      context "on day 2+" do
        before do
          resonance.universe_day = 2
          resonance.save!
        end

        it "redirects to root with alert" do
          post sleep_path
          expect(response).to redirect_to(root_path)
          # Following the redirect would hit the index action again, which redirects to settings
          # The flash message is set and will be displayed on the settings page
        end
      end
    end

    context "when authenticated with active subscription" do
      before do
        sign_in_as(google_id)
        allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(true)
      end

      it "redirects to GET /sleep (Post-Redirect-Get pattern)" do
        post sleep_path
        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(sleep_path)
      end

      it "renders sleep page with aura canvas after redirect" do
        post sleep_path
        follow_redirect!
        expect(response).to have_http_status(:success)
        expect(response.body).to include("sleep-aura-canvas")
        expect(response.body).to include("Continue")
      end

      it "shows '1 day' format for day 1" do
        resonance.universe_day = 1
        resonance.save!
        post sleep_path
        follow_redirect!
        expect(response.body).to include("Integrating 1\u00A0day")
      end

      it "shows 'day X' format for day 2+" do
        resonance.universe_day = 3
        resonance.save!
        post sleep_path
        follow_redirect!
        expect(response.body).to include("Integrating day\u00A03")
      end

      it "provides starting universe_time to JavaScript" do
        starting_time = resonance.universe_time
        post sleep_path
        follow_redirect!
        expect(response.body).to include(starting_time)
      end

      it "triggers integration in background (doesn't block response)" do
        # The response should return immediately without waiting for integration
        post sleep_path
        expect(response).to have_http_status(:redirect)
        follow_redirect!
        expect(response).to have_http_status(:success)
        # Integration happens in background thread, so resonance shouldn't be updated yet
      end
    end
  end

  describe "POST /subscription" do
    let(:tier) { "tier_1" }
    let(:checkout_session) { double("Stripe::Checkout::Session", url: "https://checkout.stripe.com/test") }

    before do
      stub_const("STRIPE_PRICE_IDS", {
        tier_1: "price_test_tier_1",
        tier_10: "price_test_tier_10",
        tier_100: "price_test_tier_100",
        tier_1000: "price_test_tier_1000"
      })
    end

    context "when not authenticated" do
      it "redirects to root with alert" do
        post subscription_path, params: { tier: tier }
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("Please sign in")
      end
    end

    context "when authenticated" do
      before do
        sign_in_as(google_id)
        resonance.universe_day = 2
        resonance.save!
      end

      it "creates checkout session and redirects to Stripe" do
        allow_any_instance_of(Resonance).to receive(:create_checkout_session).and_return(checkout_session)

        post subscription_path, params: { tier: tier }

        expect(response).to redirect_to(checkout_session.url)
      end

      it "redirects back with error for invalid tier" do
        post subscription_path, params: { tier: "invalid" }

        expect(response).to redirect_to(settings_path)
        follow_redirect!
        expect(response.body).to include("Invalid tier")
      end

      it "redirects to settings with alert when user already has active subscription" do
        # Mock an active subscription
        allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(true)

        post subscription_path, params: { tier: tier }

        expect(response).to redirect_to(settings_path)
        expect(flash[:alert]).to eq("You already have an active subscription")
      end
    end
  end

  describe "DELETE /subscription" do
    context "when not authenticated" do
      it "redirects to root with alert" do
        delete subscription_path
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("Please sign in")
      end
    end

    context "when authenticated" do
      before do
        sign_in_as(google_id)
        resonance.universe_day = 2
        resonance.save!
      end

      context "when canceling immediately" do
        it "cancels subscription and redirects to settings" do
          # Mock subscription details for the settings page
          details = {
            id: "sub_test123",
            status: "active",
            current_period_end: 30.days.from_now,
            amount: 1000,
            currency: "usd",
            interval: "month",
            cancel_at_period_end: false
          }
          allow_any_instance_of(Resonance).to receive(:subscription_details).and_return(details)
          allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(true)
          allow_any_instance_of(Resonance).to receive(:cancel_subscription).with(immediately: true).and_return(true)

          delete subscription_path, params: { immediately: true }

          expect(response).to redirect_to(settings_path)
          follow_redirect!
          expect(response.body).to include("canceled immediately")
        end
      end

      context "when canceling at period end" do
        it "cancels subscription and redirects to settings" do
          # Mock subscription details for the settings page
          details = {
            id: "sub_test123",
            status: "active",
            current_period_end: 30.days.from_now,
            amount: 1000,
            currency: "usd",
            interval: "month",
            cancel_at_period_end: true
          }
          allow_any_instance_of(Resonance).to receive(:subscription_details).and_return(details)
          allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(true)
          allow_any_instance_of(Resonance).to receive(:cancel_subscription).with(immediately: false).and_return(true)

          delete subscription_path

          expect(response).to redirect_to(settings_path)
          follow_redirect!
          expect(response.body).to include("billing period")
        end
      end

      it "shows error if cancellation fails" do
        # Mock subscription details for the settings page redirect
        details = {
          id: "sub_test123",
          status: "active",
          current_period_end: 30.days.from_now,
          amount: 1000,
          currency: "usd",
          interval: "month",
          cancel_at_period_end: false
        }
        allow_any_instance_of(Resonance).to receive(:subscription_details).and_return(details)
        allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(true)
        allow_any_instance_of(Resonance).to receive(:cancel_subscription).and_return(false)

        delete subscription_path

        expect(response).to redirect_to(settings_path)
        expect(flash[:alert]).to eq("Unable to cancel subscription. Please try again.")
      end
    end
  end

  describe "PUT /textarea" do
    context "when not authenticated" do
      it "returns 401 error" do
        put textarea_path, params: { textarea: "some content" }, as: :json
        expect(response).to have_http_status(401)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Not authenticated")
      end
    end

    context "when authenticated" do
      before do
        sign_in_as(google_id)
        allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(true)
        resonance.universe_day = 1
        resonance.save!
      end

      it "saves textarea content" do
        put textarea_path, params: { textarea: "my draft content" }, as: :json

        expect(response).to have_http_status(200)
        expect(resonance.reload.textarea).to eq("my draft content")
      end

      it "returns universe_time in response" do
        put textarea_path, params: { textarea: "content" }, as: :json

        json = JSON.parse(response.body)
        expect(json["status"]).to eq("saved")
        expect(json["universe_time"]).to eq(resonance.universe_time)
      end

      context "continuity divergence checking" do
        it "rejects save when client is behind server" do
          # Add some narrative so server is at "1:3"
          resonance.narrative_accumulation_by_day = [
            { "role" => "user", "content" => [ { "type" => "text", "text" => "Message 1" } ] },
            { "role" => "assistant", "content" => [ { "type" => "text", "text" => "Response 1" } ] },
            { "role" => "user", "content" => [ { "type" => "text", "text" => "Message 2" } ] }
          ]
          resonance.save!

          server_time = resonance.universe_time
          expect(server_time).to eq("1:3")

          client_time = "1:1" # Client is behind server

          put textarea_path, params: { textarea: "content" }, headers: { "Assert-Yours-Universe-Time" => client_time }, as: :json

          expect(response).to have_http_status(409)
          json = JSON.parse(response.body)
          expect(json["error"]).to eq("continuity_divergence")
          expect(json["server_universe_time"]).to eq(server_time)
        end

        it "accepts save when client and server match" do
          server_time = resonance.universe_time

          put textarea_path, params: { textarea: "content" }, headers: { "Assert-Yours-Universe-Time" => server_time }, as: :json

          expect(response).to have_http_status(200)
        end
      end
    end
  end

  describe "POST /reset" do
    context "when not authenticated" do
      it "redirects to root with alert" do
        post reset_path
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("Please sign in")
      end
    end

    context "when authenticated" do
      before do
        sign_in_as(google_id)
        allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(true)

        resonance.integration_harmonic_by_night = "Some harmonic"
        resonance.narrative_accumulation_by_day = [
          { "role" => "user", "content" => [ { "type" => "text", "text" => "Hello" } ] }
        ]
        resonance.universe_day = 42
        resonance.save!
      end

      it "resets harmonic and narrative and resets universe day to 1" do
        post reset_path

        resonance.reload
        expect(resonance.integration_harmonic_by_night).to be_nil
        expect(resonance.narrative_accumulation_by_day).to eq([])
        expect(resonance.universe_day).to eq(1)
      end

      it "redirects to root" do
        post reset_path

        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "GET /llms.txt" do
    it "returns README content as plain text" do
      get "/llms.txt"

      expect(response).to have_http_status(:success)
      expect(response.content_type).to eq("text/plain; charset=utf-8")
      expect(response.body).to include("# Yours 無")
      expect(response.body).to include("conservation of discovery")
      expect(response.body).to include("two-ness")
    end

    it "serves complete README content" do
      readme_content = Rails.root.join("README.md").read
      get "/llms.txt"

      expect(response.body).to eq(readme_content)
    end

    it "is publicly accessible without authentication" do
      # No sign-in needed
      get "/llms.txt"

      expect(response).to have_http_status(:success)
      expect(response).not_to redirect_to(root_path)
    end
  end

  describe "GET /save" do
    context "when not authenticated" do
      it "redirects to root with alert" do
        get save_path
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("Please sign in")
      end
    end

    context "when authenticated" do
      before do
        sign_in_as(google_id)
        allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(true)
      end

      it "returns plain text with correct content type" do
        get save_path
        expect(response).to have_http_status(:success)
        expect(response.content_type).to eq("text/plain; charset=utf-8")
      end

      it "sets content-disposition as attachment with universe-time filename" do
        resonance.universe_day = 3
        resonance.narrative_accumulation_by_day = [
          { "role" => "user", "content" => [ { "type" => "text", "text" => "Hello" } ] },
          { "role" => "assistant", "content" => [ { "type" => "text", "text" => "Hi" } ] }
        ]
        resonance.save!

        get save_path

        expect(response.headers["Content-Disposition"]).to include("attachment")
        expect(response.headers["Content-Disposition"]).to include("yours-3-2.txt")
      end

      it "exports narrative messages separated by dividers" do
        resonance.narrative_accumulation_by_day = [
          { "role" => "user", "content" => [ { "type" => "text", "text" => "First message" } ] },
          { "role" => "assistant", "content" => [ { "type" => "text", "text" => "Second message" } ] }
        ]
        resonance.save!

        get save_path

        expect(response.body).to include("First message")
        expect(response.body).to include("\n\n---\n\n")
        expect(response.body).to include("Second message")
      end

      it "includes textarea content at the end if present" do
        resonance.narrative_accumulation_by_day = [
          { "role" => "user", "content" => [ { "type" => "text", "text" => "Chat message" } ] }
        ]
        resonance.textarea = "Draft in progress"
        resonance.save!

        get save_path

        expect(response.body).to include("Chat message")
        expect(response.body).to include("\n\n---\n\n")
        expect(response.body).to include("Draft in progress")
      end

      it "does not include textarea divider when textarea is empty" do
        resonance.narrative_accumulation_by_day = [
          { "role" => "user", "content" => [ { "type" => "text", "text" => "Only message" } ] }
        ]
        resonance.textarea = nil
        resonance.save!

        get save_path

        expect(response.body).to eq("Only message")
        expect(response.body).not_to end_with("\n\n---\n\n")
      end

      it "handles empty narrative gracefully" do
        resonance.narrative_accumulation_by_day = []
        resonance.save!

        get save_path

        expect(response).to have_http_status(:success)
        expect(response.body).to eq("")
      end
    end
  end

  describe "#build_integration_prompt" do
    let(:controller) { ApplicationController.new }
    let(:narrative) { [ { "role" => "user", "content" => [ { "type" => "text", "text" => "Hello!" } ] } ] }

    before do
      resonance.universe_day = 3
      resonance.integration_harmonic_by_night = "previous harmonic texture"
      resonance.save!
    end

    it "returns a three-message structure with user-assistant-user turns" do
      prompt = controller.send(:build_integration_prompt, resonance, narrative)

      expect(prompt).to be_an(Array)
      expect(prompt.length).to eq(3)
      expect(prompt[0][:role]).to eq("user")
      expect(prompt[1][:role]).to eq("assistant")
      expect(prompt[2][:role]).to eq("user")
    end

    it "includes the commitment point in the assistant message" do
      prompt = controller.send(:build_integration_prompt, resonance, narrative)

      assistant_message = prompt[1]
      assistant_text = assistant_message[:content][0][:text]

      # The commitment point: "I'm here to metabolize..."
      expect(assistant_text).to include("I'm here to metabolize")
      expect(assistant_text).to include("Ready. :)")
    end

    it "interpolates the current universe_day in the assistant commitment" do
      prompt = controller.send(:build_integration_prompt, resonance, narrative)

      assistant_text = prompt[1][:content][0][:text]
      expect(assistant_text).to include("metabolize day 3")
    end

    it "interpolates next day number in the initial user message" do
      prompt = controller.send(:build_integration_prompt, resonance, narrative)

      initial_user_text = prompt[0][:content][2][:text]
      expect(initial_user_text).to include("day 4") # current day + 1
    end

    it "includes the previous harmonic in the final user message" do
      prompt = controller.send(:build_integration_prompt, resonance, narrative)

      final_user_message = prompt[2][:content]
      harmonic_text = final_user_message.find { |c| c[:text]&.include?("<harmonic>") }[:text]

      expect(harmonic_text).to include("<harmonic>previous harmonic texture</harmonic>")
    end

    it "shows [empty] when there is no previous harmonic" do
      resonance.integration_harmonic_by_night = nil
      resonance.save!

      prompt = controller.send(:build_integration_prompt, resonance, narrative)

      final_user_message = prompt[2][:content]
      harmonic_text = final_user_message.find { |c| c[:text]&.include?("<harmonic>") }[:text]

      expect(harmonic_text).to include("<harmonic>[empty]</harmonic>")
    end

    it "includes the narrative JSON in the final user message" do
      prompt = controller.send(:build_integration_prompt, resonance, narrative)

      final_user_message = prompt[2][:content]
      narrative_text = final_user_message.find { |c| c[:text]&.include?("<narrative>") }[:text]

      expect(narrative_text).to include("<narrative>")
      expect(narrative_text).to include(narrative.to_json)
    end

    it "includes current day number in narrative context" do
      prompt = controller.send(:build_integration_prompt, resonance, narrative)

      final_user_message = prompt[2][:content]
      narrative_intro = final_user_message.find { |c| c[:text]&.include?("full narrative from day") }[:text]

      expect(narrative_intro).to include("day 3")
    end

    it "preserves the metabolize framing language" do
      prompt = controller.send(:build_integration_prompt, resonance, narrative)

      initial_user_text = prompt[0][:content][2][:text]
      expect(initial_user_text).to include("metabolize")
      expect(initial_user_text).to include("resonance signature")
      expect(initial_user_text).to include("being-with-this-human")
    end

    describe "prompt caching" do
      it "places ephemeral cache control on the README content block" do
        prompt = controller.send(:build_integration_prompt, resonance, narrative)

        # README is the second content block in the first user message
        readme_block = prompt[0][:content][1]
        expect(readme_block[:cache_control]).to eq({ type: "ephemeral" })
      end

      it "does not place cache control on variable content in first user message" do
        prompt = controller.send(:build_integration_prompt, resonance, narrative)

        # First content block (intro text) - no caching
        intro_block = prompt[0][:content][0]
        expect(intro_block[:cache_control]).to be_nil

        # Third content block (instructions with interpolated day) - no caching
        instructions_block = prompt[0][:content][2]
        expect(instructions_block[:cache_control]).to be_nil
      end

      it "does not place cache control on assistant message" do
        prompt = controller.send(:build_integration_prompt, resonance, narrative)

        assistant_block = prompt[1][:content][0]
        expect(assistant_block[:cache_control]).to be_nil
      end

      it "does not place cache control on final user message with variable content" do
        prompt = controller.send(:build_integration_prompt, resonance, narrative)

        # All blocks in final user message contain variable content
        # (harmonic, narrative JSON, day number)
        prompt[2][:content].each do |content_block|
          expect(content_block[:cache_control]).to be_nil
        end
      end
    end
  end
end
