# frozen_string_literal: true

# spec/requests/hosts_spec.rb
require "rails_helper"

RSpec.describe("hosts", :aggregate_failures, type: :request) do
  it "accepts the primary host" do
    host! "test.host"
    get "/home"
    expect(response).to(have_http_status(:ok))
  end

  it "redirects unknown hosts to the canonical host" do
    host! "unknown.host"
    get "/home?some=params"
    expect(response).to(have_http_status(:moved_permanently))
    expect(response).to(redirect_to("https://test.host/home?some=params"))
  end

  it "redirects www to the canonical host" do
    host! "www.test.host"
    get "/home"
    expect(response).to(have_http_status(:moved_permanently))
    expect(response).to(redirect_to("https://test.host/home"))
  end
end
