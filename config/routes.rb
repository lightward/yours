Rails.application.routes.draw do
  # Root handles everything: landing, auth callback, subscribe, and chat
  root "application#index"

  # User-facing routes
  get "logout", to: "application#logout"
  get "account", to: "application#account"

  # Service routes
  post "stream", to: "application#stream"
  post "integrate", to: "application#integrate"
  put "textarea", to: "application#save_textarea"
  post "subscription", to: "application#create_subscription"
  delete "subscription", to: "application#destroy_subscription"
  post "reset", to: "application#reset"
end
