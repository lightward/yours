class SubscriptionsController < ApplicationController
  before_action :require_authentication

  def new
    # Show subscription tiers
  end

  def create
    tier = params[:tier]

    session = current_resonance.create_checkout_session(
      tier: tier,
      success_url: url_for(controller: "subscriptions", action: "success", only_path: false),
      cancel_url: url_for(controller: "subscriptions", action: "new", only_path: false)
    )

    redirect_to session.url, allow_other_host: true
  rescue ArgumentError => e
    redirect_to subscribe_path, alert: e.message
  end

  def success
    # User returned from successful Stripe checkout
    redirect_to root_path, notice: "Subscription activated!"
  end

  def show
    @subscription = current_resonance.subscription_details

    unless @subscription
      redirect_to subscribe_path, alert: "No active subscription found"
    end
  end

  def destroy
    if current_resonance.cancel_subscription
      redirect_to root_path, notice: "Subscription canceled. You'll have access until the end of your billing period."
    else
      redirect_to subscription_path, alert: "Unable to cancel subscription. Please try again."
    end
  end
end
