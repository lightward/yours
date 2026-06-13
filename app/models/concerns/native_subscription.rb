# Native in-app subscriptions (Apple App Store, Google Play), alongside the
# web's Stripe subscription. Each storefront's identity is stored encrypted
# under the google_id — exactly like encrypted_stripe_customer_id — so the
# topological-opacity invariant holds for IAP too.
#
# This concern owns the encrypted accessors and the "is this storefront's
# subscription active?" checks. The any-source-unlocks combination lives in
# StripeSubscription#active_subscription?, which calls these.
module NativeSubscription
  extend ActiveSupport::Concern

  # --- Apple ---

  def apple_original_transaction_id
    decrypt_field(encrypted_apple_original_transaction_id)
  end

  def apple_original_transaction_id=(value)
    self.encrypted_apple_original_transaction_id = encrypt_field(value)
  end

  # Record a verified Apple purchase. Caller has already confirmed the signed
  # transaction with Apple's server; we only persist the (encrypted) identity.
  def record_apple_subscription(original_transaction_id)
    self.apple_original_transaction_id = original_transaction_id
    save!
  end

  def apple_subscription_active?
    id = apple_original_transaction_id
    return false if id.blank?
    AppleAppStore.new.subscription_active?(id)
  end

  # --- Google Play ---

  def google_play_purchase_token
    decrypt_field(encrypted_google_play_purchase_token)
  end

  def google_play_purchase_token=(value)
    self.encrypted_google_play_purchase_token = encrypt_field(value)
  end

  def record_google_play_subscription(purchase_token)
    self.google_play_purchase_token = purchase_token
    save!
  end

  def google_play_subscription_active?
    token = google_play_purchase_token
    return false if token.blank?
    GooglePlayStore.new.subscription_active?(token)
  end
end
