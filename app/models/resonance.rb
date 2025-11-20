class Resonance < ApplicationRecord
  include StripeSubscription

  # Custom exception for when decryption is attempted without the encryption key
  class MissingEncryptionKeyError < StandardError; end

  self.primary_key = "encrypted_google_id_hash"

  validates :encrypted_google_id_hash, presence: true, uniqueness: true

  # Encryption keyed to Google ID - without the Google ID, data is structurally inaccessible
  attr_accessor :google_id

  # Accessor for google_id_hash (read-only, computed from encrypted field)
  def google_id_hash
    encrypted_google_id_hash
  end

  # Find or create by Google ID, setting up encryption context
  def self.find_or_create_by_google_id(google_id)
    google_id_hash = Digest::SHA256.hexdigest(google_id)

    resonance = find_or_initialize_by(encrypted_google_id_hash: google_id_hash)
    resonance.google_id = google_id
    resonance.save! if resonance.new_record?
    resonance
  end

  # Find by Google ID and decrypt
  def self.find_by_google_id(google_id)
    google_id_hash = Digest::SHA256.hexdigest(google_id)
    resonance = find_by(encrypted_google_id_hash: google_id_hash)
    resonance.google_id = google_id if resonance
    resonance
  end

  # Generate one-time auth token for native apps to bootstrap into Rails session
  # Token is stateless, signed with secret, contains encrypted google_id
  # Token format: {google_id_hash}.{encrypted_google_id}.{signature}
  # Native app receives this via URL scheme, sets as cookie, Rails exchanges for real session
  def self.generate_auth_token(google_id)
    google_id_hash = Digest::SHA256.hexdigest(google_id)

    # Encrypt the google_id using app secret (so token is self-contained)
    cipher = OpenSSL::Cipher.new("aes-256-gcm")
    cipher.encrypt
    cipher.key = Digest::SHA256.digest(Rails.application.secret_key_base)
    iv = cipher.random_iv
    cipher.auth_data = ""

    encrypted = cipher.update(google_id) + cipher.final
    auth_tag = cipher.auth_tag
    encrypted_google_id = Base64.urlsafe_encode64(iv + auth_tag + encrypted, padding: false)

    # Sign the whole thing
    payload = "#{google_id_hash}.#{encrypted_google_id}"
    signature = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, payload)

    "#{payload}.#{signature}"
  end

  # Find by auth token (one-time use for native app session bootstrap)
  # Verifies signature, decrypts google_id, looks up resonance
  def self.find_by_auth_token(token)
    parts = token.split(".")
    return nil unless parts.length == 3

    google_id_hash, encrypted_google_id, signature = parts

    # Verify signature
    payload = "#{google_id_hash}.#{encrypted_google_id}"
    expected_signature = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, payload)
    return nil unless ActiveSupport::SecurityUtils.secure_compare(signature, expected_signature)

    # Decrypt google_id from token
    raw = Base64.urlsafe_decode64(encrypted_google_id)
    iv = raw[0, 12]
    auth_tag = raw[12, 16]
    encrypted = raw[28..-1]

    decipher = OpenSSL::Cipher.new("aes-256-gcm")
    decipher.decrypt
    decipher.key = Digest::SHA256.digest(Rails.application.secret_key_base)
    decipher.iv = iv
    decipher.auth_tag = auth_tag
    decipher.auth_data = ""

    google_id = decipher.update(encrypted) + decipher.final

    # Look up resonance and set google_id for decryption
    resonance = find_by(encrypted_google_id_hash: google_id_hash)
    resonance.google_id = google_id if resonance
    resonance
  rescue OpenSSL::Cipher::CipherError, ArgumentError
    # Invalid token or tampered
    nil
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

    unless google_id
      raise MissingEncryptionKeyError, "Cannot decrypt field: google_id not set. This indicates an authentication flow error."
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

  # Derive encryption key from Google ID
  def encryption_key
    raise "Cannot encrypt/decrypt without google_id" unless google_id
    OpenSSL::PKCS5.pbkdf2_hmac(google_id, "yours-resonance-salt", 100_000, 32, "sha256")
  end
end
