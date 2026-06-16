# Native in-app subscriptions (Apple App Store, Google Play), alongside the
# web's Stripe subscription. Each storefront's identity is stored encrypted
# under the google_id — exactly like encrypted_stripe_customer_id — so the
# topological-opacity invariant holds for IAP too.
#
# This concern owns the encrypted accessors, the per-resonance account token
# that binds a purchase to its buyer, and the "is this storefront's
# subscription active?" checks. The any-source-unlocks combination lives on
# Resonance#active_subscription?, which calls these.
module NativeSubscription
  extend ActiveSupport::Concern

  # Raised when a transaction is already bound to a *different* resonance — the
  # cross-account replay attempt. The controller turns this into a 409.
  class AlreadyClaimedError < StandardError; end

  # A stable, opaque token identifying this resonance to the storefronts,
  # derived from the google_id (no storage needed; same input → same token).
  # The iOS client sets it as StoreKit's appAccountToken at purchase; Apple
  # echoes it back in the signed transaction, and we verify the transaction was
  # bought by *this* account. Formatted as a UUID because Apple requires
  # appAccountToken to be one. Reveals nothing about the google_id (keyed HMAC).
  def iap_account_token
    raise "Cannot derive account token without google_id" unless google_id
    digest = OpenSSL::HMAC.digest("SHA256", Rails.application.secret_key_base, "iap-account-token:#{google_id}")
    bytes = digest[0, 16].unpack("H*").first
    [ bytes[0, 8], bytes[8, 4], bytes[12, 4], bytes[16, 4], bytes[20, 12] ].join("-")
  end

  # --- Apple ---

  def apple_original_transaction_id
    decrypt_field(encrypted_apple_original_transaction_id)
  end

  def apple_original_transaction_id=(value)
    self.encrypted_apple_original_transaction_id = encrypt_field(value)
  end

  # Record a verified Apple purchase. The caller (controller) has already
  # confirmed the signed transaction with Apple AND that its appAccountToken
  # matches this resonance. We store the encrypted identity plus a keyed
  # fingerprint whose DB unique index guarantees no other resonance can claim
  # the same transaction.
  def record_apple_subscription(original_transaction_id)
    self.apple_original_transaction_id = original_transaction_id
    self.apple_transaction_fingerprint = NativeSubscription.fingerprint(original_transaction_id)
    save!
  rescue ActiveRecord::RecordNotUnique
    raise AlreadyClaimedError, "This Apple subscription is already linked to another account."
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
    self.google_play_transaction_fingerprint = NativeSubscription.fingerprint(purchase_token)
    save!
  rescue ActiveRecord::RecordNotUnique
    raise AlreadyClaimedError, "This Google Play subscription is already linked to another account."
  end

  def google_play_subscription_active?
    return false unless GooglePlayStore.configured?
    token = google_play_purchase_token
    return false if token.blank?
    GooglePlayStore.new.subscription_active?(token)
  end

  # Keyed, deterministic hash of a transaction identifier. Same id → same
  # fingerprint (so the unique index can reject a second claimant), but the
  # app-secret HMAC means the stored value discloses nothing on its own.
  def self.fingerprint(transaction_identifier)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "iap-txn:#{transaction_identifier}")
  end
end
