require "rails_helper"

RSpec.describe "Subscriptions", type: :request do
  let(:google_id) { "google-user-123" }
  let(:resonance) { Resonance.find_or_create_by_google_id(google_id) }

  before do
    host! "test.host"

    # Sign in
    identity = double("GoogleSignIn::Identity", user_id: google_id, email_address: "test@example.com")
    allow(GoogleSignIn::Identity).to receive(:new).and_return(identity)
    allow_any_instance_of(SessionsController).to receive(:flash).and_return(
      { google_sign_in: { "id_token" => "fake_token" } }
    )
    get sign_in_path
  end

  describe "GET /subscribe" do
    it "returns http success" do
      get subscribe_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /subscribe" do
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

    it "creates checkout session and redirects to Stripe" do
      allow_any_instance_of(Resonance).to receive(:create_checkout_session).and_return(checkout_session)

      post subscribe_path, params: { tier: tier }

      expect(response).to redirect_to(checkout_session.url)
    end

    it "redirects back with error for invalid tier" do
      post subscribe_path, params: { tier: "invalid" }

      expect(response).to redirect_to(subscribe_path)
      expect(flash[:alert]).to be_present
    end
  end

  describe "GET /subscribe/success" do
    it "redirects to root with success message" do
      get subscribe_success_path

      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("Subscription activated!")
    end
  end

  describe "GET /account" do
    context "when user has active subscription" do
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

    context "when user has no active subscription" do
      it "redirects to subscribe page" do
        allow_any_instance_of(Resonance).to receive(:subscription_details).and_return(nil)

        get account_path

        expect(response).to redirect_to(subscribe_path)
        expect(flash[:alert]).to eq("No active subscription found")
      end
    end
  end

  describe "DELETE /account/subscription" do
    it "cancels subscription and redirects" do
      allow_any_instance_of(Resonance).to receive(:cancel_subscription).and_return(true)

      delete account_subscription_path

      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to include("canceled")
    end

    it "shows error if cancellation fails" do
      allow_any_instance_of(Resonance).to receive(:cancel_subscription).and_return(false)

      delete account_subscription_path

      expect(response).to redirect_to(account_path)
      expect(flash[:alert]).to include("Unable to cancel")
    end
  end

  describe "POST /account/reset" do
    before do
      resonance.integration_harmonic_by_night = "Some harmonic"
      resonance.narrative_accumulation_by_day = [
        { "role" => "user", "content" => [ { "type" => "text", "text" => "Hello" } ] }
      ]
      resonance.universe_days_lived = 42
      resonance.save!
    end

    it "resets harmonic and narrative but preserves universe age" do
      post account_reset_path

      resonance.reload
      expect(resonance.integration_harmonic_by_night).to be_nil
      expect(resonance.narrative_accumulation_by_day).to eq([])
      expect(resonance.universe_days_lived).to eq(42)
    end

    it "redirects to root with success message" do
      post account_reset_path

      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to include("Resonance reset")
      expect(flash[:notice]).to include("42 day(s)")
    end
  end
end
