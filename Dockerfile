FROM ruby:3.4.6-alpine AS builder
WORKDIR /app

RUN apk update && apk add --no-cache build-base yaml-dev libpq-dev
RUN bundle config set --local path /app/.bundle
RUN bundle config set --local without 'development test'

COPY .ruby-version Gemfile Gemfile.lock ./
RUN bundle install

COPY . .
RUN bin/rails assets:precompile

FROM ruby:3.4.6-alpine as runner
RUN apk update
WORKDIR /app

# runtime dependencies for the application
RUN apk add --no-cache libpq postgresql-client

COPY --from=builder /app ./
RUN bundle config set --local path /app/.bundle
RUN bundle config set --local without 'development test'
