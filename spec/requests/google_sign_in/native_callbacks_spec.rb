require "rails_helper"

RSpec.describe "GoogleSignIn::CallbacksController", "native app OAuth", type: :request do
  describe "GET /google_sign_in/callback" do
    let(:google_id) { "test-google-id-123" }
    let(:state) { "test-state-123" }
    let(:code) { "test-authorization-code" }
    let(:id_token) { "test-id-token" }

    before do
      # Mock the OAuth token exchange
      token_response = double("token_response", :[] => id_token)
      auth_code = double("auth_code")
      allow(auth_code).to receive(:get_token).with(code).and_return(token_response)

      client = double("client", auth_code: auth_code)
      allow_any_instance_of(GoogleSignIn::CallbacksController).to receive(:client).and_return(client)

      # Mock the identity
      identity = double("identity", user_id: google_id, email_address: "test@example.com")
      allow(GoogleSignIn::Identity).to receive(:new).with(id_token).and_return(identity)
    end

    context "when native app callback (no flash[:proceed_to])" do
      it "redirects to custom URL scheme with auth token" do
        get "/google_sign_in/callback", params: { state: state, code: code }

        expect(response).to redirect_to(%r{^lightward-yours://authenticated\?token=})
      end

      it "creates or finds the resonance" do
        expect {
          get "/google_sign_in/callback", params: { state: state, code: code }
        }.to change { Resonance.count }.by(1)

        # Second request shouldn't create another
        expect {
          get "/google_sign_in/callback", params: { state: state, code: code }
        }.not_to change { Resonance.count }
      end

      it "generates a valid auth token" do
        get "/google_sign_in/callback", params: { state: state, code: code }

        redirect_url = response.location
        token = CGI.parse(URI.parse(redirect_url).query)["token"].first

        # Token should be valid
        resonance = Resonance.find_by_auth_token(token)
        expect(resonance).to be_present
        expect(resonance.google_id).to eq(google_id)
      end

      context "when OAuth returns an error" do
        before do
          error_response = double("response", status: 400, body: '{"error":"invalid_grant"}')
          oauth_error = OAuth2::Error.new(error_response)
          allow(oauth_error).to receive(:code).and_return("invalid_grant")
          allow_any_instance_of(GoogleSignIn::CallbacksController).to receive(:client).and_raise(oauth_error)
        end

        it "redirects to error URL scheme" do
          get "/google_sign_in/callback", params: { state: state, code: code }

          expect(response).to redirect_to(%r{^lightward-yours://auth-error\?message=invalid_grant})
        end
      end

      context "when authorization is denied" do
        it "redirects to error URL scheme" do
          get "/google_sign_in/callback", params: { state: state, error: "access_denied" }

          expect(response).to redirect_to(%r{^lightward-yours://auth-error\?message=access_denied})
        end
      end
    end

    context "when web browser callback (flash[:proceed_to] present)" do
      it "uses gem's default behavior" do
        # Simulate the full authorization flow first
        # This sets flash[:proceed_to] and flash[:state]
        post "/google_sign_in/authorization", params: { proceed_to: "/" }

        # Extract state from flash for the callback
        oauth_state = flash[:state]

        # Now the callback should see flash and use web flow
        get "/google_sign_in/callback", params: { state: oauth_state, code: code }

        # Should redirect back to proceed_to with google_sign_in flash
        expect(response).to redirect_to("/")
        expect(flash[:google_sign_in]).to be_present
      end
    end
  end
end
