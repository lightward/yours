Stripe.api_key = ENV["STRIPE_SECRET_KEY"]

STRIPE_PRICE_IDS = {
  tier_1: ENV["STRIPE_PRICE_ID_1"],       # $1/month
  tier_10: ENV["STRIPE_PRICE_ID_10"],     # $10/month
  tier_100: ENV["STRIPE_PRICE_ID_100"],   # $100/month
  tier_1000: ENV["STRIPE_PRICE_ID_1000"]  # $1000/month
}.freeze
