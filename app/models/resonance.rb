class Resonance < ApplicationRecord
  include StripeSubscription
  include NativeSubscription

  # Custom exception for when decryption is attempted without the encryption key
  class MissingEncryptionKeyError < StandardError; end

  # A resonance is a subscriber if *any* storefront says so — Stripe (web),
  # Apple (iOS), or Google Play (Android). The platforms don't share an
  # identity; each manages its own billing. See PROTOCOL.md.
  def active_subscription?
    stripe_subscription_active? ||
      apple_subscription_active? ||
      google_play_subscription_active?
  end

  self.primary_key = "encrypted_google_id_hash"

  validates :encrypted_google_id_hash, presence: true, uniqueness: true

  # Encryption is keyed to the identity_key — without it, the data is
  # structurally inaccessible. The identity_key is the raw provider subject:
  # for Google sign-in it's the Google `sub`; for Sign in with Apple it's
  # "apple:<sub>". Two providers, two independent key spaces, no linking.
  #
  # The primary-key column is still named `encrypted_google_id_hash` for
  # historical reasons; it holds SHA256(identity_key), which for existing
  # Google resonances is byte-for-byte what it always was, so no data migrates.
  attr_accessor :identity_key

  # Backward-compatible alias: existing callers set/read `.google_id`. For a
  # Google resonance the identity_key *is* the Google sub, so this is a no-op
  # rename that keeps all the old plumbing (controllers, sleep thread) working.
  alias_method :google_id, :identity_key
  alias_method :google_id=, :identity_key=

  # Read-only hash of the identity (the stored primary key).
  def identity_hash
    encrypted_google_id_hash
  end
  alias_method :google_id_hash, :identity_hash

  # Find or create by identity_key, setting up the encryption context.
  def self.find_or_create_by_identity(identity_key)
    hash = Digest::SHA256.hexdigest(identity_key)

    resonance = find_or_initialize_by(encrypted_google_id_hash: hash)
    resonance.identity_key = identity_key
    resonance.save! if resonance.new_record?
    resonance
  end

  def self.find_by_identity(identity_key)
    resonance = find_by(encrypted_google_id_hash: Digest::SHA256.hexdigest(identity_key))
    resonance.identity_key = identity_key if resonance
    resonance
  end

  # Google-named wrappers, kept for existing callers and specs.
  def self.find_or_create_by_google_id(google_id)
    find_or_create_by_identity(google_id)
  end

  def self.find_by_google_id(google_id)
    find_by_identity(google_id)
  end

  # Encrypt data using Google ID as key
  def encrypt_field(value)
    return nil if value.nil?

    cipher = OpenSSL::Cipher.new("aes-256-gcm")
    cipher.encrypt
    cipher.key = encryption_key
    iv = cipher.random_iv
    cipher.auth_data = ""

    encrypted = cipher.update(value.to_s) + cipher.final
    auth_tag = cipher.auth_tag

    # Fixed-length concatenation: iv (12 bytes) + auth_tag (16 bytes) + encrypted data
    # Works for empty strings since we just concatenate the bytes directly
    Base64.strict_encode64(iv + auth_tag + encrypted)
  end

  # Decrypt data using Google ID as key
  def decrypt_field(encrypted_value)
    return nil if encrypted_value.nil? || encrypted_value.blank?

    # A missing identity_key is an auth-flow bug, not bad data — surface it loudly.
    unless identity_key
      raise MissingEncryptionKeyError, "Cannot decrypt field: identity_key not set. This indicates an authentication flow error."
    end

    raw = Base64.strict_decode64(encrypted_value.to_s)

    # Fixed-length extraction: first 12 bytes = iv, next 16 bytes = auth_tag, rest = encrypted
    iv = raw[0, 12]
    auth_tag = raw[12, 16]
    encrypted = raw[28..-1] || "" # Handle case where encrypted portion is empty

    decipher = OpenSSL::Cipher.new("aes-256-gcm")
    decipher.decrypt
    decipher.key = encryption_key
    decipher.iv = iv
    decipher.auth_tag = auth_tag
    decipher.auth_data = ""

    decrypted = decipher.update(encrypted) + decipher.final
    # Force UTF-8 encoding to prevent encoding compatibility errors
    decrypted.force_encoding("UTF-8")
  rescue OpenSSL::Cipher::CipherError, ArgumentError, TypeError
    # Corrupted, tampered, or truncated ciphertext (bad GCM tag, non-base64,
    # short buffer). Degrade to nil rather than raising: a single bad byte must
    # not 500 the request, lock the account out of every gated path, or signal
    # the encryption structure to error tracking. Callers treat nil as absent,
    # so e.g. active_subscription? simply reads false. The legitimately-fatal
    # MissingEncryptionKeyError above is intentionally NOT rescued here.
    nil
  end

  # Accessors for encrypted fields
  def stripe_customer_id
    decrypt_field(encrypted_stripe_customer_id)
  end

  def stripe_customer_id=(value)
    self.encrypted_stripe_customer_id = encrypt_field(value)
  end

  def integration_harmonic_by_night
    decrypt_field(encrypted_integration_harmonic_by_night)
  end

  def integration_harmonic_by_night=(value)
    self.encrypted_integration_harmonic_by_night = encrypt_field(value)
  end

  def narrative_accumulation_by_day
    decrypted = decrypt_field(encrypted_narrative_accumulation_by_day)
    decrypted ? JSON.parse(decrypted) : []
  end

  def narrative_accumulation_by_day=(value)
    self.encrypted_narrative_accumulation_by_day = encrypt_field(value.to_json)
  end

  # Universe day number (1-indexed, starts at 1)
  def universe_day
    return 1 if encrypted_universe_day.nil?
    value = decrypt_field(encrypted_universe_day)
    value&.to_i || 1
  end

  def universe_day=(value)
    # Track old value before changing for validation
    @universe_day_was = universe_day if persisted?
    self.encrypted_universe_day = value.nil? ? nil : encrypt_field(value.to_s)
  end

  # Textarea contents
  def textarea
    decrypt_field(encrypted_textarea)
  end

  def textarea=(value)
    self.encrypted_textarea = encrypt_field(value)
  end

  # Universe time as "day:message_count" (e.g., "3:14" for day 3, 14 messages)
  # This serves as a monotonically increasing guard against cross-device state clobbering
  def universe_time
    "#{universe_day}:#{narrative_accumulation_by_day.length}"
  end

  # Validation: universe_day can only increase, never decrease (except when resetting to 1)
  validate :universe_day_cannot_decrease

  private

  def universe_day_cannot_decrease
    return unless @universe_day_was && persisted?

    old_value = @universe_day_was
    new_value = universe_day

    # Allow reset to 1 (begin again), but prevent other decreases
    if new_value < old_value && new_value != 1
      errors.add(:universe_day, "cannot decrease (was #{old_value}, attempted #{new_value})")
    end
  end

  # Derive the encryption key from the identity_key. The salt is unchanged, so
  # for Google resonances (identity_key == the Google sub) this yields exactly
  # the same key as before — existing ciphertext decrypts identically.
  def encryption_key
    raise "Cannot encrypt/decrypt without identity_key" unless identity_key
    OpenSSL::PKCS5.pbkdf2_hmac(identity_key, "yours-resonance-salt", 100_000, 32, "sha256")
  end
end
