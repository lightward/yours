# Verifies Google Play in-app purchases against the Google Play Developer API.
# The app sends a purchase token; we ask Google's own API
# (purchases.subscriptionsv2.get) for the authoritative record rather than
# trusting the client.
#
# Auth is a service-account JWT-bearer OAuth2 exchange, done by hand to keep
# the dependency footprint small (no googleauth/google-apis gems) — the same
# spirit as the Apple verifier signing its own ES256 JWT.
class GooglePlayStore
  TOKEN_URI = "https://oauth2.googleapis.com/token".freeze
  SCOPE = "https://www.googleapis.com/auth/androidpublisher".freeze
  API_HOST = "androidpublisher.googleapis.com".freeze

  # SubscriptionState values that count as entitled.
  ENTITLED_STATES = %w[
    SUBSCRIPTION_STATE_ACTIVE
    SUBSCRIPTION_STATE_IN_GRACE_PERIOD
    SUBSCRIPTION_STATE_ON_HOLD
  ].freeze

  Result = Struct.new(:purchase_token, :product_id, :active, keyword_init: true)

  class VerificationError < StandardError; end

  def initialize(config: GOOGLE_PLAY_CONFIG, product_ids: GOOGLE_PRODUCT_IDS)
    @config = config
    @product_ids = product_ids
  end

  # Given a purchase token from the app, return a Result if it's a genuine,
  # currently-entitled subscription to one of our products, else nil.
  def verify(purchase_token)
    purchase = fetch_subscription(purchase_token)
    return nil unless purchase

    product_ids = Array(purchase["lineItems"]).map { |item| item["productId"] }
    return nil if (product_ids & @product_ids).empty?

    Result.new(
      purchase_token: purchase_token,
      product_id: product_ids.first,
      active: ENTITLED_STATES.include?(purchase["subscriptionState"])
    )
  end

  # Used by the entitlement check and RTDN webhooks.
  def subscription_active?(purchase_token)
    purchase = fetch_subscription(purchase_token)
    return false unless purchase
    ENTITLED_STATES.include?(purchase["subscriptionState"])
  rescue VerificationError
    false
  end

  private

  def fetch_subscription(purchase_token)
    return nil if purchase_token.blank?
    path = "/androidpublisher/v3/applications/#{@config[:package_name]}" \
           "/purchases/subscriptionsv2/tokens/#{ERB::Util.url_encode(purchase_token)}"
    response = get(path)
    case response
    when Net::HTTPSuccess then JSON.parse(response.body)
    when Net::HTTPNotFound then nil
    else raise VerificationError, "Play Developer API #{response.code}: #{response.body}"
    end
  end

  def get(path)
    uri = URI("https://#{API_HOST}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 15

    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{access_token}"
    http.request(request)
  end

  # Service-account JWT-bearer flow: sign a JWT with the account's private key,
  # exchange it for a short-lived access token.
  def access_token
    credentials = service_account
    now = Time.now.to_i
    assertion = JWT.encode(
      {
        iss: credentials.fetch("client_email"),
        scope: SCOPE,
        aud: TOKEN_URI,
        iat: now,
        exp: now + 3600
      },
      OpenSSL::PKey::RSA.new(credentials.fetch("private_key")),
      "RS256"
    )

    uri = URI(TOKEN_URI)
    response = Net::HTTP.post_form(uri, {
      "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
      "assertion" => assertion
    })

    unless response.is_a?(Net::HTTPSuccess)
      raise VerificationError, "Google token exchange #{response.code}: #{response.body}"
    end

    JSON.parse(response.body).fetch("access_token")
  end

  def service_account
    raise VerificationError, "Google Play IAP not configured" if @config[:service_account_json].blank?
    JSON.parse(@config[:service_account_json])
  rescue JSON::ParserError
    raise VerificationError, "Invalid GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"
  end
end
