# Verifies Apple in-app purchases against the App Store Server API. The app
# sends a signed transaction (StoreKit 2 gives it a JWS); we ask Apple's own
# API for the authoritative record rather than trusting — or hand-validating
# the signature chain of — the client's value.
#
# Two calls matter:
#   - GET /inApps/v1/transactions/{transactionId} — confirm a transaction
#     exists and read its productId / originalTransactionId
#   - GET /inApps/v1/subscriptions/{originalTransactionId} — current renewal
#     status, used to answer "still active?"
#
# Apple's responses are themselves JWS-signed; since we only act on data we
# fetched directly from Apple's authenticated endpoint over TLS, we decode the
# payload without re-validating the signature (the transport already
# authenticated the source).
class AppleAppStore
  PRODUCTION_HOST = "api.storekit.itunes.apple.com".freeze
  SANDBOX_HOST = "api.storekit-sandbox.itunes.apple.com".freeze

  # Apple subscription states that count as entitled (1 = active, 3 = in
  # billing retry, 4 = in grace period). 2 = expired, 5 = revoked.
  ENTITLED_STATUSES = [ 1, 3, 4 ].freeze

  Result = Struct.new(:original_transaction_id, :product_id, :active, keyword_init: true)

  class VerificationError < StandardError; end

  def initialize(config: APPLE_IAP_CONFIG, product_ids: APPLE_PRODUCT_IDS)
    @config = config
    @product_ids = product_ids
  end

  # Given a signed transaction JWS from the app, return a Result if it's a
  # genuine, currently-entitled subscription to one of our products, else nil.
  def verify(signed_transaction)
    transaction_id = transaction_id_from(signed_transaction)
    return nil unless transaction_id

    info = decode_jws(fetch_transaction(transaction_id))
    return nil unless info
    return nil unless @product_ids.include?(info["productId"])

    original_id = info["originalTransactionId"] || transaction_id

    Result.new(
      original_transaction_id: original_id,
      product_id: info["productId"],
      active: subscription_active?(original_id)
    )
  end

  # Used by the entitlement check and renewal webhooks: is this original
  # transaction's subscription currently in an entitled state?
  def subscription_active?(original_transaction_id)
    statuses = fetch_subscription_statuses(original_transaction_id)
    return false unless statuses

    statuses.any? do |group|
      Array(group["lastTransactions"]).any? do |txn|
        ENTITLED_STATUSES.include?(txn["status"])
      end
    end
  rescue VerificationError
    false
  end

  private

  # The JWS payload is the middle segment, base64url-encoded JSON. We read it
  # to learn the transactionId before asking Apple to confirm it.
  def transaction_id_from(signed_transaction)
    decode_jws(signed_transaction)&.dig("transactionId")
  end

  def decode_jws(jws)
    return nil if jws.blank?
    payload_segment = jws.to_s.split(".")[1]
    return nil unless payload_segment
    JSON.parse(Base64.urlsafe_decode64(pad(payload_segment)))
  rescue ArgumentError, JSON::ParserError
    nil
  end

  def pad(segment)
    segment + ("=" * ((4 - segment.length % 4) % 4))
  end

  def fetch_transaction(transaction_id)
    get("/inApps/v1/transactions/#{transaction_id}")&.dig("signedTransactionInfo")
  end

  def fetch_subscription_statuses(original_transaction_id)
    get("/inApps/v1/subscriptions/#{original_transaction_id}")&.dig("data")
  end

  # Calls the App Store Server API, falling back from production to sandbox
  # (Apple returns 4040010 for a sandbox transaction queried in production).
  def get(path)
    hosts = @config[:environment] == "Sandbox" ? [ SANDBOX_HOST ] : [ PRODUCTION_HOST, SANDBOX_HOST ]
    last_error = nil

    hosts.each do |host|
      response = request(host, path)
      case response
      when Net::HTTPSuccess
        return JSON.parse(response.body)
      when Net::HTTPNotFound
        last_error = :not_found
        next # try sandbox
      else
        raise VerificationError, "App Store Server API #{response.code}: #{response.body}"
      end
    end

    return nil if last_error == :not_found
    nil
  end

  def request(host, path)
    uri = URI("https://#{host}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 15

    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{bearer_token}"
    http.request(request)
  end

  # Signs the ES256 JWT that authenticates us to the App Store Server API.
  # Cached for most of its 1-hour validity window.
  def bearer_token
    raise VerificationError, "Apple IAP not configured" if @config[:private_key].blank?

    now = Time.now.to_i
    payload = {
      iss: @config[:issuer_id],
      iat: now,
      exp: now + 3000,
      aud: "appstoreconnect-v1",
      bid: @config[:bundle_id]
    }
    headers = { kid: @config[:key_id], typ: "JWT" }

    JWT.encode(payload, ec_key, "ES256", headers)
  end

  def ec_key
    OpenSSL::PKey::EC.new(@config[:private_key])
  end
end
