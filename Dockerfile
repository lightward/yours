# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t yours .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name yours yours

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.4.6
FROM ruby:$RUBY_VERSION-alpine AS base

# App lives here
WORKDIR /app

# Install base packages
RUN apk update && apk add --no-cache gcompat postgresql-client

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_PATH="/app/.bundle" \
    BUNDLE_WITHOUT="development test"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apk update && apk add --no-install-recommends build-base yaml-dev postgresql-dev

# Install application gems
COPY .ruby-version Gemfile Gemfile.lock ./
RUN bundle config set --local path /app/.bundle && \
    bundle config set --local without 'development test' && \
    bundle install

# Copy application code
COPY . .

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile

# Final stage for app image
FROM base

# Copy built artifacts: gems, application
COPY --from=build /app ./

# Configure bundle
RUN bundle config set --local path /app/.bundle && \
    bundle config set --local without 'development test'

# Start puma directly (no thruster needed for fly.io)
EXPOSE 8080
CMD ["bin/puma", "--port", "8080"]
