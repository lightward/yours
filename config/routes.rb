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
end
