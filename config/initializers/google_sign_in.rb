Rails.application.configure do
  config.google_sign_in.client_id = ENV.fetch("GOOGLE_SIGN_IN_CLIENT_ID", nil).presence
  config.google_sign_in.client_secret = ENV.fetch("GOOGLE_SIGN_IN_CLIENT_SECRET", nil).presence
end
