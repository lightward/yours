# Mints and reads the encrypted credentials that let a native client (ios/,
# android/) carry a resonance's google_id between requests, the same way the
# web session cookie does. Nothing minted here is stored server-side: the
# token *is* the key envelope, and it lives only on the device. The
# topological encryption story (see README) is unchanged — without a request
# bearing the google_id, the data at rest remains structurally inaccessible.
class NativeToken
  CODE_TTL = 1.minute   # one hop: web sign-in window -> app
  TOKEN_TTL = 1.year    # ordinary residence in the device keychain

  class << self
    # Short-lived exchange code, bound to a PKCE challenge so that only the
    # app instance that opened the sign-in window can redeem it — a code
    # intercepted in transit is useless without the verifier, which never
    # leaves the device.
    def issue_code(google_id:, obfuscated_email:, code_challenge:)
      encryptor.encrypt_and_sign(
        {
          "google_id" => google_id,
          "obfuscated_email" => obfuscated_email,
          "code_challenge" => code_challenge
        }.to_json,
        purpose: :native_auth_code,
        expires_in: CODE_TTL
      )
    end

    # Returns the code's payload if the verifier matches its challenge, nil
    # otherwise (including expired or tampered codes).
    def redeem_code(code, code_verifier:)
      payload = decode(code, purpose: :native_auth_code)
      return nil unless payload

      challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier.to_s), padding: false)
      return nil unless ActiveSupport::SecurityUtils.secure_compare(challenge, payload["code_challenge"].to_s)

      payload
    end

    def issue(google_id:, obfuscated_email:)
      encryptor.encrypt_and_sign(
        {
          "google_id" => google_id,
          "obfuscated_email" => obfuscated_email
        }.to_json,
        purpose: :native_bearer,
        expires_in: TOKEN_TTL
      )
    end

    # Returns the token's payload, or nil for anything invalid or expired.
    def read(token)
      decode(token, purpose: :native_bearer)
    end

    private

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
