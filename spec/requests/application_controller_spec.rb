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
        expect(response.body).to include("Sign in with Google")
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
          expect(response.body).to include("Move to day 2")
        end
      end

      context "on day 2+" do
        before do
          resonance.universe_day = 2
          resonance.save!
        end

        it "shows gate message directing to account area" do
          get root_path
          expect(response).to have_http_status(:success)
          expect(response.body).to include("Ready for day 2")
          expect(response.body).to include("account area")
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
        expect(response.body).to include("Yours: day 5")
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
      expect(response.body).to include("Yours: 1 day")
      expect(response.body).not_to include("Yours: day 1")
    end

    it "shows 'day X' format for day 2+" do
      resonance.universe_day = 2
      resonance.save!
      get root_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Yours: day 2")
    end
  end

  describe "GET /logout" do
    it "clears the session and redirects to root" do
      sign_in_as(google_id)

      get logout_path

      expect(response).to redirect_to(root_path)
      expect(session[:google_id]).to be_nil
      expect(session[:obfuscated_user_email]).to be_nil
    end
  end

  describe "GET /account" do
    context "when not authenticated" do
      it "redirects to root with alert" do
        get account_path
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("Please sign in")
      end
    end

    context "when authenticated with active subscription" do
      before do
        sign_in_as(google_id)
        allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(true)
      end

      it "shows account details" do
        details = {
          id: "sub_test123",
          status: "active",
          current_period_end: 30.days.from_now,
          amount: 1000,
          currency: "usd",
          interval: "month"
        }

        allow_any_instance_of(Resonance).to receive(:subscription_details).and_return(details)

        get account_path

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Account")
      end
    end

    context "when authenticated but no active subscription" do
      before do
        sign_in_as(google_id)
        allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(false)
      end

      it "shows account page with subscription buttons" do
        get account_path

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Not subscribed")
        expect(response.body).to include("$1/month")
        expect(response.body).to include("$10/month")
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
          follow_redirect!
          expect(response.body).to include("Active subscription required")
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

  describe "POST /integrate" do
    context "when not authenticated" do
      it "redirects to root with alert" do
        post integrate_path
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

          stub_const("ENV", ENV.to_hash.merge("LIGHTWARD_AI_API_URL" => "https://api.example.com/chat"))

          # Mock successful streaming response
          http_response = Net::HTTPOK.new("1.1", "200", "OK")
          allow(http_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
          allow(http_response).to receive(:read_body).and_yield("event: content_block_delta\ndata: {\"delta\":{\"type\":\"text_delta\",\"text\":\"Integration complete\"}}\n\n")

          http = instance_double(Net::HTTP)
          allow(Net::HTTP).to receive(:new).and_return(http)
          allow(http).to receive(:use_ssl=)
          allow(http).to receive(:read_timeout=)
          allow(http).to receive(:request).and_yield(http_response)
        end

        it "allows integration (day 1 is free)" do
          post integrate_path
          resonance.reload
          expect(resonance.integration_harmonic_by_night).to eq("Integration complete")
          expect(resonance.universe_day).to eq(2)
        end
      end

      context "on day 2+" do
        before do
          resonance.universe_day = 2
          resonance.save!
        end

        it "redirects to root with alert" do
          post integrate_path
          expect(response).to redirect_to(root_path)
          follow_redirect!
          expect(response.body).to include("Active subscription required")
        end
      end
    end

    context "when authenticated with active subscription" do
      before do
        sign_in_as(google_id)
        allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(true)
      end

      context "when narrative is empty" do
        it "redirects back with alert" do
          post integrate_path
          expect(response).to redirect_to(root_path)
          follow_redirect!
          expect(response.body).to include("No narrative to integrate yet.")
        end
      end

      context "when narrative exists" do
        before do
          resonance.narrative_accumulation_by_day = [
            { "role" => "user", "content" => [ { "type" => "text", "text" => "Hello" } ] },
            { "role" => "assistant", "content" => [ { "type" => "text", "text" => "Hi there!" } ] }
          ]
          resonance.save!
        end

        context "when Lightward AI API returns non-success response" do
          before do
            stub_const("ENV", ENV.to_hash.merge("LIGHTWARD_AI_API_URL" => "https://api.example.com/chat"))

            # Mock the HTTP response
            http_response = Net::HTTPServiceUnavailable.new("1.1", "503", "Service Unavailable")
            allow(http_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
            allow(http_response).to receive(:code).and_return("503")
            allow(http_response).to receive(:message).and_return("Service Unavailable")

            # Mock Net::HTTP
            http = instance_double(Net::HTTP)
            allow(Net::HTTP).to receive(:new).and_return(http)
            allow(http).to receive(:use_ssl=)
            allow(http).to receive(:read_timeout=)
            allow(http).to receive(:request).and_yield(http_response)
          end

          it "raises an error with the API status code" do
            expect {
              post integrate_path
            }.to raise_error(RuntimeError, /API returned 503/)
          end
        end

        context "when Lightward AI API returns success" do
          before do
            stub_const("ENV", ENV.to_hash.merge("LIGHTWARD_AI_API_URL" => "https://api.example.com/chat"))

            # Mock successful streaming response
            http_response = Net::HTTPOK.new("1.1", "200", "OK")
            allow(http_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
            allow(http_response).to receive(:read_body).and_yield("event: content_block_delta\ndata: {\"delta\":{\"type\":\"text_delta\",\"text\":\"Integration complete\"}}\n\n")

            http = instance_double(Net::HTTP)
            allow(Net::HTTP).to receive(:new).and_return(http)
            allow(http).to receive(:use_ssl=)
            allow(http).to receive(:read_timeout=)
            allow(http).to receive(:request).and_yield(http_response)
          end

          it "creates integration harmonic and increments universe age" do
            initial_day = resonance.universe_day
            post integrate_path
            resonance.reload
            expect(resonance.integration_harmonic_by_night).to eq("Integration complete")
            expect(resonance.universe_day).to eq(initial_day + 1)
          end

          it "clears the narrative accumulation" do
            post integrate_path
            resonance.reload
            expect(resonance.narrative_accumulation_by_day).to eq([])
          end
        end
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
      before { sign_in_as(google_id) }

      it "creates checkout session and redirects to Stripe" do
        allow_any_instance_of(Resonance).to receive(:create_checkout_session).and_return(checkout_session)

        post subscription_path, params: { tier: tier }

        expect(response).to redirect_to(checkout_session.url)
      end

      it "redirects back with error for invalid tier" do
        post subscription_path, params: { tier: "invalid" }

        expect(response).to redirect_to(account_path)
        follow_redirect!
        expect(response.body).to include("Invalid tier")
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
      before { sign_in_as(google_id) }

      context "when canceling immediately" do
        it "cancels subscription and redirects to account" do
          # Mock subscription details for the account page
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

          expect(response).to redirect_to(account_path)
          follow_redirect!
          expect(response.body).to include("canceled immediately")
        end
      end

      context "when canceling at period end" do
        it "cancels subscription and redirects to account" do
          # Mock subscription details for the account page
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

          expect(response).to redirect_to(account_path)
          follow_redirect!
          expect(response.body).to include("billing period")
        end
      end

      it "shows error if cancellation fails" do
        # Mock subscription details for the account page redirect
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

        expect(response).to redirect_to(account_path)
        expect(flash[:alert]).to eq("Unable to cancel subscription. Please try again.")
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

      it "redirects to root with success message" do
        post reset_path

        expect(response).to redirect_to(root_path)
        follow_redirect!
        expect(response.body).to include("The day is 1")
      end
    end
  end
end
