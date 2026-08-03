# Verifies a "Sign in with Apple" identity token (a JWS the app receives from
# ASAuthorizationController) and returns the stable Apple subject.
#
# Unlike the Google web flow, this token comes straight from Apple through the
# native SDK and is cryptographically bound to our app (its `aud` is our bundle
# id) and to a per-attempt nonce — so there's no confused-deputy risk, and no
# consent gate is needed. We verify:
#   - signature (RS256) against Apple's published JWKS
#   - iss == https://appleid.apple.com
#   - aud == our app's client id (the bundle id, for native SiwA)
#   - exp not passed
#   - nonce matches sha256(raw nonce the app used)  [replay protection]
# then read `sub`.
#
# The resulting identity_key is "apple:<sub>" — its own key space, never linked
# to any Google resonance.
class AppleIdentity
  ISSUER = "https://appleid.apple.com".freeze
  KEYS_URL = "https://appleid.apple.com/auth/keys".freeze
  KEYS_CACHE_TTL = 1.hour

  Result = Struct.new(:sub, :email, keyword_init: true) do
    def identity_key
      "apple:#{sub}"
    end
  end

  class VerificationError < StandardError; end

  def initialize(config: APPLE_SIGN_IN_CONFIG)
    @config = config
  end

  # Given the identity token (and the raw nonce the app generated for this
  # sign-in), return a Result, or raise VerificationError. `raw_nonce` may be
  # nil only if the client didn't use one — but we require it, since it's the
  # replay defense.
  def verify(identity_token, raw_nonce:)
    raise VerificationError, "Missing identity token" if identity_token.blank?
    raise VerificationError, "Missing nonce" if raw_nonce.blank?

    claims = decode(identity_token)

    verify_claim!(claims["iss"] == ISSUER, "issuer")
    verify_claim!(Array(@config[:client_ids]).include?(claims["aud"]), "audience")
    verify_claim!(nonce_matches?(claims["nonce"], raw_nonce), "nonce")
    verify_claim!(claims["sub"].present?, "subject")

    Result.new(sub: claims["sub"], email: claims["email"])
  end

  private

  def verify_claim!(condition, name)
    raise VerificationError, "Apple identity token failed #{name} check" unless condition
  end

  # sha256(raw_nonce), hex — the value the app passes as request.nonce and that
  # Apple echoes in the token's `nonce` claim. Constant-time compared.
  def nonce_matches?(token_nonce, raw_nonce)
    return false if token_nonce.blank?
    expected = Digest::SHA256.hexdigest(raw_nonce)
    ActiveSupport::SecurityUtils.secure_compare(token_nonce.to_s, expected)
  end

  # Decodes + verifies signature/exp against Apple's JWKS. Refetches the key
  # set once on a `kid` miss (Apple rotates keys). ExpiredSignature is a
  # subclass of DecodeError, so it must be rescued first.
  def decode(token)
    JWT.decode(token, nil, true, decode_options(jwks)).first
  rescue JWT::ExpiredSignature
    raise VerificationError, "Apple identity token expired"
  rescue JWT::DecodeError => e
    # A kid miss / signature mismatch surfaces as a DecodeError; retry once
    # with a freshly-fetched key set before giving up.
    raise VerificationError, "Apple identity token signature invalid: #{e.message}" if @retried
    @retried = true
    decode_with_fresh_keys(token)
  end

  def decode_with_fresh_keys(token)
    JWT.decode(token, nil, true, decode_options(jwks(force: true))).first
  rescue JWT::ExpiredSignature
    raise VerificationError, "Apple identity token expired"
  rescue JWT::DecodeError => e
    raise VerificationError, "Apple identity token signature invalid: #{e.message}"
  end

  def decode_options(key_set)
    {
      algorithms: [ "RS256" ],
      jwks: key_set,
      verify_expiration: true
    }
  end

  def jwks(force: false)
    Rails.cache.delete(cache_key) if force
    cached = Rails.cache.read(cache_key)
    return cached if cached

    body = fetch_keys
    Rails.cache.write(cache_key, body, expires_in: KEYS_CACHE_TTL)
    body
  end

  def cache_key
    "apple_identity:jwks"
  end

  def fetch_keys
    uri = URI(KEYS_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 10
    response = http.request(Net::HTTP::Get.new(uri))
    raise VerificationError, "Apple JWKS fetch failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue JSON::ParserError, SocketError, Timeout::Error => e
    raise VerificationError, "Apple JWKS unavailable: #{e.message}"
  end
end
