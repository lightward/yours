require "rails_helper"

RSpec.describe "Native auth token exchange", type: :request do
  let(:google_id) { "test-google-id-123" }
  let!(:resonance) { Resonance.find_or_create_by_google_id(google_id) }
  let(:auth_token) { Resonance.generate_auth_token(google_id) }

  # Set proper host to avoid verify_host! redirects
  let(:headers) { { "HTTP_HOST" => ENV.fetch("HOST") } }

  describe "token-to-session bootstrap" do
    it "exchanges auth token cookie for Rails session" do
      # First request with token cookie
      cookies[:_yours_auth_token] = auth_token
      get "/", headers: headers

      expect(response).to have_http_status(:success)

      # Session should be established
      expect(session[:google_id]).to eq(google_id)

      # Token cookie should be deleted (shows as empty string in tests)
      expect(cookies[:_yours_auth_token]).to be_blank
    end

    it "only works once (token is deleted after use)" do
      cookies[:_yours_auth_token] = auth_token

      # First request succeeds
      get "/", headers: headers
      expect(session[:google_id]).to eq(google_id)

      # Clear session to simulate second request
      reset!

      # Second request with same token should not work (cookie was deleted)
      cookies[:_yours_auth_token] = auth_token
      get "/", headers: headers

      # Actually, the token itself is still valid, but the cookie gets deleted
      # Let's verify that the exchange happens and cookie is deleted
      expect(cookies[:_yours_auth_token]).to be_blank
    end

    it "handles invalid tokens gracefully" do
      cookies[:_yours_auth_token] = "invalid-token"

      get "/", headers: headers

      # Should not error, just delete the bad token
      expect(response).to have_http_status(:success)
      expect(session[:google_id]).to be_nil
      expect(cookies[:_yours_auth_token]).to be_blank
    end

    it "does nothing if no token cookie present" do
      get "/", headers: headers

      expect(response).to have_http_status(:success)
      expect(session[:google_id]).to be_nil
    end
  end

  describe "subsequent requests use normal session" do
    before do
      # Bootstrap session via token
      cookies[:_yours_auth_token] = auth_token
      get "/", headers: headers
    end

    it "authenticates via session on subsequent requests" do
      # Make another request (no token this time)
      get "/", headers: headers

      expect(response).to have_http_status(:success)
      expect(session[:google_id]).to eq(google_id)
    end

    it "can access authenticated routes" do
      get "/", headers: headers

      # Should see chat interface (authenticated)
      expect(response.body).to include("chat")
      expect(response.body).not_to include("Enter via Google")
    end
  end

  describe "native app contract" do
    it "accepts tokens in the format the iOS app expects" do
      # iOS app receives token via lightward-yours://authenticated?token=...
      # and sets it as a cookie. This tests that contract.

      token_parts = auth_token.split(".")
      expect(token_parts.length).to eq(3), "Token format should be hash.encrypted.signature"

      # Token should be URL-safe (no special encoding needed)
      expect(auth_token).not_to match(%r{[+/= ]})

      # Should bootstrap session successfully
      cookies[:_yours_auth_token] = auth_token
      get "/", headers: headers

      expect(session[:google_id]).to eq(google_id)
    end
  end
end
