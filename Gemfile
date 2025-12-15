source "https://rubygems.org"

gem "rails", "~> 8.1.1"
gem "propshaft"
gem "tzinfo-data"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "bootsnap", require: false

gem "turbo-rails"
gem "stimulus-rails"
gem "importmap-rails"

gem "google_sign_in"

gem "stripe"

gem "rollbar"
gem "oj" # per rollbar recommendation

# https://github.com/ruby/openssl/issues/949#issuecomment-3614908180
gem 'openssl', '~> 3.3', '>= 3.3.1'

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: [ :mri, :windows ]

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # rspec
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "rspec-github", require: false

  # audit
  gem "brakeman", require: false
  gem "bundler-audit", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end
