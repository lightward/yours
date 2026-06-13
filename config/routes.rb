Rails.application.routes.draw do
  # Root handles everything: landing, auth callback, subscribe, and chat
  root "application#index"

  # User-facing routes
  get "exit", to: "application#logout"
  get "settings", to: "application#settings"
  get "save", to: "application#save"

  # Service routes
  post "stream", to: "application#stream"
  get "sleep", to: "application#sleep"
  post "sleep", to: "application#sleep"
  put "textarea", to: "application#save_textarea"
  post "subscription", to: "application#create_subscription"
  delete "subscription", to: "application#destroy_subscription"
  post "reset", to: "application#reset"
  get "llms.txt", to: "application#llms_txt"

  # Native client routes (ios/, android/) — see PROTOCOL.md
  get "native/auth", to: "application#native_auth_start"
  post "native/token", to: "application#native_token"
  get "native/state", to: "application#native_state"
  post "native/subscription", to: "application#native_subscription"

  # Storefront server-to-server notifications (renewals, cancellations,
  # refunds) — App Store Server Notifications V2 and Play RTDN
  post "native/apple_notifications", to: "application#apple_notifications"
  post "native/google_notifications", to: "application#google_notifications"
end
