# Mints and reads the encrypted credentials that let a native client (ios/,
# android/) carry a resonance's identity_key between requests, the same way the
# web session cookie does. Nothing minted here is stored server-side: the
# token *is* the key envelope, and it lives only on the device. The
# topological encryption story (see README) is unchanged — without a request
# bearing the identity_key, the data at rest remains structurally inaccessible.
#
# identity_key is the raw provider subject: the Google `sub` for Google
# sign-in, "apple:<sub>" for Sign in with Apple. Tokens minted before this
# change carried the key under "google_id"; read() still accepts those (they
# live up to a year in keychains), normalizing them to identity_key.
class NativeToken
  CODE_TTL = 1.minute   # one hop: web sign-in window -> app
  TOKEN_TTL = 1.year    # ordinary residence in the device keychain

  class << self
    # Short-lived exchange code, bound to a PKCE challenge so that only the
    # app instance that opened the sign-in window can redeem it — a code
    # intercepted in transit is useless without the verifier, which never
    # leaves the device. (Used by the web Google flow; codes expire in a
    # minute, so no legacy-key handling is needed here.)
    def issue_code(identity_key:, obfuscated_email:, code_challenge:)
      encryptor.encrypt_and_sign(
        {
          "identity_key" => identity_key,
          "obfuscated_email" => obfuscated_email,
          "code_challenge" => code_challenge
        }.to_json,
        purpose: :native_auth_code,
        expires_in: CODE_TTL
      )
    end

    # Returns the (normalized) code payload if the verifier matches its
    # challenge, nil otherwise (including expired or tampered codes).
    def redeem_code(code, code_verifier:)
      payload = decode(code, purpose: :native_auth_code)
      return nil unless payload

      challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier.to_s), padding: false)
      return nil unless ActiveSupport::SecurityUtils.secure_compare(challenge, payload["code_challenge"].to_s)

      normalize(payload)
    end

    def issue(identity_key:, obfuscated_email:)
      encryptor.encrypt_and_sign(
        {
          "identity_key" => identity_key,
          "obfuscated_email" => obfuscated_email
        }.to_json,
        purpose: :native_bearer,
        expires_in: TOKEN_TTL
      )
    end

    # Returns the (normalized) token payload, or nil for anything invalid or
    # expired.
    def read(token)
      normalize(decode(token, purpose: :native_bearer))
    end

    private

    # Bridge legacy tokens: a token minted before the identity_key rename
    # carried the key under "google_id". Expose it as identity_key either way.
    def normalize(payload)
      return nil unless payload
      payload["identity_key"] ||= payload["google_id"]
      payload
    end

    def decode(message, purpose:)
      payload = encryptor.decrypt_and_verify(message.to_s, purpose: purpose)
      payload ? JSON.parse(payload) : nil
    rescue ActiveSupport::MessageEncryptor::InvalidMessage, JSON::ParserError
      nil
    end

    def encryptor
      key = Rails.application.key_generator.generate_key("native client auth", ActiveSupport::MessageEncryptor.key_len)
      ActiveSupport::MessageEncryptor.new(key)
    end
  end
end
