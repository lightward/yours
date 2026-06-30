# Be sure to restart your server when you modify this file.
#
# Defense-in-depth: the app renders only the user's own conversation, with
# escaping handled in the chat controller's renderer - this policy is the
# second wall. External script execution is pinned to named hosts; objects,
# embedding, and off-site form targets are refused.
#
# script-src keeps :unsafe_inline for now: the Rollbar JS middleware injects
# its snippet without nonce awareness, and importmap + the theme-flash
# snippet are inline by design. Tightening to nonces is possible whenever
# Rollbar's injection learns nonces - the chat controller already avoids
# inline event handlers, so nothing else stands in the way.
#
# (An iOS wrapper pointed at the live site is unaffected by page CSP; only a
# local-serve wrapper with a custom scheme would need its scheme added here.)

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src  :self, :unsafe_inline,
      "https://aura.lightward.io",
      "https://status.yours.fyi",
      "https://cdn.usefathom.com",
      "https://cdn.rollbar.com"
    policy.style_src   :self, :unsafe_inline, "https://fonts.lightward.io"
    policy.font_src    :self, "https://fonts.lightward.io"
    policy.img_src     :self, :data, "https://cdn.usefathom.com"
    policy.connect_src :self,
      "https://status.yours.fyi",
      "https://cdn.usefathom.com",
      "https://api.rollbar.com"
    # the status embed injects its widget as an iframe hosted on statuspage.io
    policy.frame_src   "https://status.yours.fyi", "https://*.statuspage.io"
    policy.object_src  :none
    policy.frame_ancestors :none
    policy.base_uri :self
    # forms post to self and the canonical host; Chrome enforces form-action
    # through redirect chains, so the two off-site handoffs are named. HOST is
    # absent during boot-only contexts (asset precompilation, db tasks), so the
    # canonical host is included only when it's set — at request time it always is.
    canonical_host = ENV["HOST"]
    policy.form_action :self,
      *(canonical_host ? [ "https://#{canonical_host}" ] : []),
      "https://accounts.google.com",
      "https://checkout.stripe.com"
  end
end
