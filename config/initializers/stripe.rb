Stripe.api_key = ENV["STRIPE_SECRET_KEY"]

# Tiers we OFFER for new checkouts: $10 / $20 / $30 / $50 / $100 per month.
# tier_10 and tier_100 predate the pricing change; tier_20/30/50 are new.
STRIPE_PRICE_IDS = {
  tier_10: ENV["STRIPE_PRICE_ID_10"],     # $10/month
  tier_20: ENV["STRIPE_PRICE_ID_20"],     # $20/month
  tier_30: ENV["STRIPE_PRICE_ID_30"],     # $30/month
  tier_50: ENV["STRIPE_PRICE_ID_50"],     # $50/month
  tier_100: ENV["STRIPE_PRICE_ID_100"]    # $100/month
}.compact.freeze

# Tiers we RECOGNIZE as an active subscription: everything offered, PLUS the
# retired $1 and $1000 tiers. A subscription's price lives in Stripe, not our
# DB — so if we stopped recognizing the old price IDs, an existing $1 or $1000
# subscriber would keep being billed by Stripe while losing access here. This
# grandfathers them: we no longer *offer* those tiers, but we still honor them.
STRIPE_RECOGNIZED_PRICE_IDS = (
  STRIPE_PRICE_IDS.values + [ ENV["STRIPE_PRICE_ID_1"], ENV["STRIPE_PRICE_ID_1000"] ]
).compact.uniq.freeze
