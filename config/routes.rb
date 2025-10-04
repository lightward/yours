Rails.application.routes.draw do
  root "home#index"

  # Google Sign In
  get "sign_in", to: "sessions#create"
  delete "sign_out", to: "sessions#destroy"

  # Chat
  get "chat", to: "chat#show"
  post "chat/stream", to: "chat#stream"

  # Stripe Subscriptions
  get "subscription", to: "subscriptions#show"
  delete "subscription", to: "subscriptions#destroy"
  get "subscribe", to: "subscriptions#new"
  post "subscribe", to: "subscriptions#create"
  get "subscribe/success", to: "subscriptions#success", as: :subscribe_success

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
