class Resonance < ApplicationRecord
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

    # Store: iv + auth_tag + encrypted_data (all base64 encoded)
    Base64.strict_encode64([ iv, auth_tag, encrypted ].map { |d| Base64.strict_encode64(d) }.join(":"))
  end

  # Decrypt data using Google ID as key
  def decrypt_field(encrypted_value)
    return nil if encrypted_value.nil? || encrypted_value.blank?
    return nil unless google_id # Can't decrypt without Google ID

    # Handle case where encrypted_value might not be a string
    encrypted_str = encrypted_value.to_s

    decoded = Base64.strict_decode64(encrypted_str)
    iv_b64, auth_tag_b64, encrypted_b64 = decoded.split(":")

    iv = Base64.strict_decode64(iv_b64)
    auth_tag = Base64.strict_decode64(auth_tag_b64)
    encrypted = Base64.strict_decode64(encrypted_b64)

    decipher = OpenSSL::Cipher.new("aes-256-gcm")
    decipher.decrypt
    decipher.key = encryption_key
    decipher.iv = iv
    decipher.auth_tag = auth_tag
    decipher.auth_data = ""

    decipher.update(encrypted) + decipher.final
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
    decrypt_field(encrypted_narrative_accumulation_by_day)
  end

  def narrative_accumulation_by_day=(value)
    self.encrypted_narrative_accumulation_by_day = encrypt_field(value)
  end

  def universe_days_lived
    return nil if encrypted_universe_days_lived.nil?
    value = decrypt_field(encrypted_universe_days_lived)
    value&.to_i
  end

  def universe_days_lived=(value)
    self.encrypted_universe_days_lived = value.nil? ? nil : encrypt_field(value.to_s)
  end

  private

  # Derive encryption key from Google ID
  def encryption_key
    raise "Cannot encrypt/decrypt without google_id" unless google_id
    OpenSSL::PKCS5.pbkdf2_hmac(google_id, "yours-resonance-salt", 100_000, 32, "sha256")
  end
end
