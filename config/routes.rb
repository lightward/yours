Rails.application.routes.draw do
  # Google Sign In
  get "sign_in", to: "sessions#create"
  delete "sign_out", to: "sessions#destroy"

  # Home (for unauthenticated users)
  get "home", to: "home#index"

  # Chat (now at root)
  root "chat#show"
  post "chat/stream", to: "chat#stream"
  post "chat/integrate", to: "chat#integrate"

  # Account (formerly subscriptions)
  get "account", to: "subscriptions#show"
  delete "account/subscription", to: "subscriptions#destroy"
  post "account/reset", to: "subscriptions#reset"

  # Subscribe flow
  get "subscribe", to: "subscriptions#new"
  post "subscribe", to: "subscriptions#create"
  get "subscribe/success", to: "subscriptions#success", as: :subscribe_success
end
