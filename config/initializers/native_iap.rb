# Native in-app subscription configuration. Like Stripe's, the secrets live
# in ENV (this is an open-source repo — nothing real is committed); the
# product identifiers are the native-storefront counterparts of
# STRIPE_PRICE_IDS.
#
# Verification goes through each storefront's server API rather than
# hand-validating signature chains: the storefront is the authority on what's
# really been purchased.

# Apple App Store Server API (https://developer.apple.com/documentation/appstoreserverapi)
APPLE_IAP_CONFIG = {
  # App Store Connect API key, used to sign the JWT we present to Apple
  key_id: ENV["APPLE_IAP_KEY_ID"],
  issuer_id: ENV["APPLE_IAP_ISSUER_ID"],
  private_key: ENV["APPLE_IAP_PRIVATE_KEY"], # the .p8 contents
  bundle_id: ENV.fetch("APPLE_IAP_BUNDLE_ID", "fyi.yours.app"),
  # "Production" or "Sandbox"; verification falls back across both so TestFlight
  # and the live store both work
  environment: ENV.fetch("APPLE_IAP_ENVIRONMENT", "Production")
}.freeze

# Sign in with Apple (native). The identity token the app sends is verified
# against Apple's public keys; its `aud` claim is our app's bundle id (for
# native SiwA). Allow extra client ids (e.g. a Services ID) via env if ever
# needed. No secret is required to *verify* — Apple's keys are public.
APPLE_SIGN_IN_CONFIG = {
  client_ids: (ENV["APPLE_SIGN_IN_CLIENT_IDS"]&.split(",")&.map(&:strip).presence ||
    [ ENV.fetch("APPLE_IAP_BUNDLE_ID", "fyi.yours.app") ])
}.freeze

# Google Play Developer API (https://developers.google.com/android-publisher)
GOOGLE_PLAY_CONFIG = {
  package_name: ENV.fetch("GOOGLE_PLAY_PACKAGE_NAME", "fyi.yours.app"),
  # Service-account JSON for the androidpublisher scope
  service_account_json: ENV["GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"]
}.freeze

# Native product IDs, mirroring the Stripe tiers. Two lists, same reason as
# Stripe: what we OFFER (new $10/$20/$30/$50/$100) vs. what we RECOGNIZE as a
# valid subscription (offered + grandfathered legacy $1/$1000), so a purchase
# made before the pricing change keeps its access. Defaults match the tier
# naming so local/dev StoreKit config lines up without extra ENV.
APPLE_PRODUCT_IDS = (ENV["APPLE_PRODUCT_IDS"]&.split(",")&.map(&:strip).presence || %w[
  fyi.yours.subscription.tier_10
  fyi.yours.subscription.tier_20
  fyi.yours.subscription.tier_30
  fyi.yours.subscription.tier_50
  fyi.yours.subscription.tier_100
]).freeze

APPLE_RECOGNIZED_PRODUCT_IDS = (APPLE_PRODUCT_IDS + (
  ENV["APPLE_LEGACY_PRODUCT_IDS"]&.split(",")&.map(&:strip).presence || %w[
    fyi.yours.subscription.tier_1
    fyi.yours.subscription.tier_1000
  ]
)).uniq.freeze

GOOGLE_PRODUCT_IDS = (ENV["GOOGLE_PRODUCT_IDS"]&.split(",")&.map(&:strip).presence || %w[
  subscription_tier_10
  subscription_tier_20
  subscription_tier_30
  subscription_tier_50
  subscription_tier_100
]).freeze

GOOGLE_RECOGNIZED_PRODUCT_IDS = (GOOGLE_PRODUCT_IDS + (
  ENV["GOOGLE_LEGACY_PRODUCT_IDS"]&.split(",")&.map(&:strip).presence || %w[
    subscription_tier_1
    subscription_tier_1000
  ]
)).uniq.freeze
