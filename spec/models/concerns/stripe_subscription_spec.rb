require "rails_helper"

RSpec.describe StripeSubscription do
  let(:google_id) { "test-google-id" }
  let(:resonance) { Resonance.find_or_create_by_google_id(google_id) }

  describe "#active_subscription?" do
    context "when no Stripe customer ID exists" do
      it "returns false" do
        expect(resonance.active_subscription?).to be false
      end
    end

    context "when Stripe customer ID exists" do
      let(:customer_id) { "cus_test123" }
      let(:price_id) { "price_test_tier_1" }

      before do
        resonance.stripe_customer_id = customer_id
        resonance.save!

        # Stub Stripe constants
        stub_const("STRIPE_PRICE_IDS", {
          tier_1: price_id,
          tier_10: "price_test_tier_10",
          tier_100: "price_test_tier_100",
          tier_1000: "price_test_tier_1000"
        })
      end

      it "returns true when customer has active subscription to our price" do
        subscriptions = double("Stripe::ListObject",
          data: [
            double(
              items: double(data: [
                double(price: double(id: price_id))
              ])
            )
          ]
        )

        allow(Stripe::Subscription).to receive(:list).with(
          customer: customer_id,
          status: "active",
          limit: 10
        ).and_return(subscriptions)

        expect(resonance.active_subscription?).to be true
      end

      it "returns false when customer has no subscriptions" do
        subscriptions = double("Stripe::ListObject", data: [])
        allow(Stripe::Subscription).to receive(:list).and_return(subscriptions)

        expect(resonance.active_subscription?).to be false
      end

      it "returns false when subscription is to a different price" do
        subscriptions = double("Stripe::ListObject",
          data: [
            double(
              items: double(data: [
                double(price: double(id: "price_different_product"))
              ])
            )
          ]
        )

        allow(Stripe::Subscription).to receive(:list).and_return(subscriptions)

        expect(resonance.active_subscription?).to be false
      end

      it "returns false when Stripe API errors" do
        allow(Stripe::Subscription).to receive(:list).and_raise(Stripe::StripeError.new("API error"))

        expect(resonance.active_subscription?).to be false
      end
    end
  end

  describe "#create_checkout_session" do
    let(:tier) { "tier_1" }
    let(:success_url) { "https://example.com/success" }
    let(:cancel_url) { "https://example.com/cancel" }
    let(:price_id) { "price_test_tier_1" }
    let(:customer_id) { "cus_test123" }

    before do
      stub_const("STRIPE_PRICE_IDS", {
        tier_1: price_id,
        tier_10: "price_test_tier_10",
        tier_100: "price_test_tier_100",
        tier_1000: "price_test_tier_1000"
      })
    end

    it "creates a checkout session with correct parameters" do
      customer = double("Stripe::Customer", id: customer_id)
      allow(Stripe::Customer).to receive(:create).and_return(customer)

      session = double("Stripe::Checkout::Session", url: "https://checkout.stripe.com/session")
      expect(Stripe::Checkout::Session).to receive(:create).with(
        customer: customer_id,
        mode: "subscription",
        line_items: [{
          price: price_id,
          quantity: 1
        }],
        success_url: success_url,
        cancel_url: cancel_url
      ).and_return(session)

      result = resonance.create_checkout_session(
        tier: tier,
        success_url: success_url,
        cancel_url: cancel_url
      )

      expect(result).to eq(session)
    end

    it "stores the customer ID after first checkout" do
      customer = double("Stripe::Customer", id: customer_id)
      allow(Stripe::Customer).to receive(:create).and_return(customer)

      session = double("Stripe::Checkout::Session", url: "https://checkout.stripe.com/session")
      allow(Stripe::Checkout::Session).to receive(:create).and_return(session)

      resonance.create_checkout_session(
        tier: tier,
        success_url: success_url,
        cancel_url: cancel_url
      )

      expect(resonance.reload.stripe_customer_id).to eq(customer_id)
    end

    it "reuses existing customer ID" do
      resonance.stripe_customer_id = customer_id
      resonance.save!

      expect(Stripe::Customer).not_to receive(:create)

      session = double("Stripe::Checkout::Session", url: "https://checkout.stripe.com/session")
      allow(Stripe::Checkout::Session).to receive(:create).and_return(session)

      resonance.create_checkout_session(
        tier: tier,
        success_url: success_url,
        cancel_url: cancel_url
      )
    end

    it "raises ArgumentError for invalid tier" do
      expect {
        resonance.create_checkout_session(
          tier: "invalid_tier",
          success_url: success_url,
          cancel_url: cancel_url
        )
      }.to raise_error(ArgumentError, /Invalid tier/)
    end
  end

  describe "#subscription_details" do
    context "when customer has active subscription" do
      let(:customer_id) { "cus_test123" }
      let(:price_id) { "price_test_tier_10" }
      let(:subscription_id) { "sub_test123" }

      before do
        resonance.stripe_customer_id = customer_id
        resonance.save!

        stub_const("STRIPE_PRICE_IDS", {
          tier_1: "price_test_tier_1",
          tier_10: price_id,
          tier_100: "price_test_tier_100",
          tier_1000: "price_test_tier_1000"
        })
      end

      it "returns subscription details" do
        list_subscription = double(id: subscription_id)
        subscriptions = double("Stripe::ListObject", data: [list_subscription])

        period_end = Time.now.to_i + 30.days.to_i
        item = double(
          to_hash: { current_period_end: period_end },
          price: double(
            id: price_id,
            unit_amount: 1000,
            currency: "usd",
            recurring: double(interval: "month")
          )
        )

        full_subscription = double(
          id: subscription_id,
          status: "active",
          cancel_at_period_end: false,
          items: double(data: [item])
        )

        allow(Stripe::Subscription).to receive(:list).and_return(subscriptions)
        allow(Stripe::Subscription).to receive(:retrieve).with(subscription_id).and_return(full_subscription)

        details = resonance.subscription_details

        expect(details[:id]).to eq(subscription_id)
        expect(details[:status]).to eq("active")
        expect(details[:cancel_at_period_end]).to eq(false)
        expect(details[:amount]).to eq(1000)
        expect(details[:currency]).to eq("usd")
        expect(details[:interval]).to eq("month")
      end
    end

    context "when customer has no subscriptions" do
      it "returns nil" do
        resonance.stripe_customer_id = "cus_test123"
        resonance.save!

        subscriptions = double("Stripe::ListObject", data: [])
        allow(Stripe::Subscription).to receive(:list).and_return(subscriptions)

        expect(resonance.subscription_details).to be_nil
      end
    end
  end

  describe "#cancel_subscription" do
    let(:customer_id) { "cus_test123" }
    let(:price_id) { "price_test_tier_1" }
    let(:subscription_id) { "sub_test123" }

    before do
      resonance.stripe_customer_id = customer_id
      resonance.save!

      stub_const("STRIPE_PRICE_IDS", {
        tier_1: price_id,
        tier_10: "price_test_tier_10",
        tier_100: "price_test_tier_100",
        tier_1000: "price_test_tier_1000"
      })
    end

    it "cancels active subscription at period end" do
      subscriptions = double("Stripe::ListObject",
        data: [
          double(
            id: subscription_id,
            items: double(data: [
              double(price: double(id: price_id))
            ])
          )
        ]
      )

      allow(Stripe::Subscription).to receive(:list).and_return(subscriptions)
      expect(Stripe::Subscription).to receive(:update).with(subscription_id, cancel_at_period_end: true)

      expect(resonance.cancel_subscription).to be true
    end

    it "returns false on Stripe error" do
      allow(Stripe::Subscription).to receive(:list).and_raise(Stripe::StripeError.new("API error"))

      expect(resonance.cancel_subscription).to be false
    end
  end
end
