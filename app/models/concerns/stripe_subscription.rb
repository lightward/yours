module StripeSubscription
  extend ActiveSupport::Concern

  def active_subscription?
    return false unless stripe_customer_id.present?

    # List subscriptions for this customer
    subscriptions = Stripe::Subscription.list(
      customer: stripe_customer_id,
      status: "active",
      limit: 10
    )

    return false unless subscriptions&.data

    # Look for active subscriptions to any of our Yours price IDs
    subscriptions.data.any? do |sub|
      sub.items.data.any? { |item| STRIPE_PRICE_IDS.values.include?(item.price.id) }
    end
  rescue Stripe::StripeError => e
    Rails.logger.error "Stripe error checking subscription: #{e.message}"
    false
  end

  def subscription_details
    return nil unless stripe_customer_id.present?

    subscriptions = Stripe::Subscription.list(
      customer: stripe_customer_id,
      status: "active",
      limit: 1
    )

    return nil if subscriptions.data.empty?

    subscription = subscriptions.data.first

    # Retrieve the full subscription object to ensure all fields are loaded
    full_subscription = Stripe::Subscription.retrieve(subscription.id)
    item = full_subscription.items.data.first
    price = item.price

    {
      id: full_subscription.id,
      status: full_subscription.status,
      cancel_at_period_end: full_subscription.cancel_at_period_end,
      current_period_end: Time.at(item.to_hash[:current_period_end]),
      amount: price.unit_amount,
      currency: price.currency,
      interval: price.recurring.interval
    }
  rescue Stripe::StripeError => e
    Rails.logger.error "Stripe error getting subscription details: #{e.message}"
    nil
  end

  def cancel_subscription
    return false unless stripe_customer_id.present?

    subscriptions = Stripe::Subscription.list(
      customer: stripe_customer_id,
      status: "active",
      limit: 10
    )

    # Cancel all active Yours subscriptions at period end
    subscriptions.data.each do |sub|
      if sub.items.data.any? { |item| STRIPE_PRICE_IDS.values.include?(item.price.id) }
        Stripe::Subscription.update(sub.id, cancel_at_period_end: true)
      end
    end

    true
  rescue Stripe::StripeError => e
    Rails.logger.error "Stripe error canceling subscription: #{e.message}"
    false
  end

  def create_checkout_session(tier:, success_url:, cancel_url:)
    price_id = STRIPE_PRICE_IDS[tier.to_sym]
    raise ArgumentError, "Invalid tier: #{tier}" unless price_id

    # Create or retrieve Stripe customer
    customer_id = stripe_customer_id || create_stripe_customer

    # Create checkout session
    session = Stripe::Checkout::Session.create(
      customer: customer_id,
      mode: "subscription",
      line_items: [ {
        price: price_id,
        quantity: 1
      } ],
      success_url: success_url,
      cancel_url: cancel_url
    )

    # Store customer ID if this is first time
    unless stripe_customer_id
      self.stripe_customer_id = customer_id
      save!
    end

    session
  end

  private

  def create_stripe_customer
    customer = Stripe::Customer.create
    customer.id
  end
end
