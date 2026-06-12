# frozen_string_literal: true

require "rails_helper"

# The policy's load-bearing refusals, protected as invariants: the exact host
# lists may evolve, but the page must always arrive with a policy, and the
# policy must always refuse objects, embedding, and unlisted form targets.
RSpec.describe "Content Security Policy", type: :request do
  before do
    host! "test.host"
  end

  let(:csp) do
    get root_path
    response.headers["Content-Security-Policy"]
  end

  it "arrives with every page" do
    expect(csp).to be_present
  end

  it "defaults to self" do
    expect(csp).to include("default-src 'self'")
  end

  it "refuses objects and embedding" do
    expect(csp).to include("object-src 'none'")
    expect(csp).to include("frame-ancestors 'none'")
  end

  it "constrains form targets to self plus the two named off-site handoffs" do
    expect(csp).to match(/form-action 'self' https:\/\/accounts\.google\.com https:\/\/checkout\.stripe\.com/)
  end

  it "pins script execution to self plus named hosts" do
    expect(csp).to include("script-src 'self'")
    expect(csp).to include("https://aura.lightward.io")
  end
end
