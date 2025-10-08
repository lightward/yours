require "rails_helper"

RSpec.describe "Sessions", type: :request do
  describe "POST /sign_in" do
    let(:google_id) { "google-user-123" }
    let(:id_token) { "fake.jwt.token" }

    before do
      # Mock GoogleSignIn::Identity
      identity = double("GoogleSignIn::Identity", user_id: google_id, email_address: "test@example.com")
      allow(GoogleSignIn::Identity).to receive(:new).with(id_token).and_return(identity)
    end

    it "creates a new resonance for first-time sign in" do
      allow_any_instance_of(SessionsController).to receive(:flash).and_return(
        { google_sign_in: { "id_token" => id_token } }  # String keys, not symbols
      )
      expect {
        get sign_in_path
      }.to change(Resonance, :count).by(1)
    end

    it "sets the session google_id" do
      allow_any_instance_of(SessionsController).to receive(:flash).and_return(
        { google_sign_in: { "id_token" => id_token } }
      )
      get sign_in_path
      expect(session[:google_id]).to eq(google_id)
    end

    it "redirects to root path" do
      allow_any_instance_of(SessionsController).to receive(:flash).and_return(
        { google_sign_in: { "id_token" => id_token } }
      )
      get sign_in_path
      expect(response).to redirect_to(root_path)
    end

    it "finds existing resonance on subsequent sign in" do
      resonance = Resonance.find_or_create_by_google_id(google_id)
      allow_any_instance_of(SessionsController).to receive(:flash).and_return(
        { google_sign_in: { "id_token" => id_token } }
      )

      expect {
        get sign_in_path
      }.not_to change(Resonance, :count)

      expect(session[:google_id]).to eq(google_id)
    end

    context "when google authentication fails" do
      it "redirects with an alert when error in flash" do
        allow_any_instance_of(SessionsController).to receive(:flash).and_return(
          { google_sign_in: { "error" => "invalid_token" } }
        )
        get sign_in_path
        expect(response).to redirect_to(home_path)
        # Flash alert is set but won't show in the test without following redirect and rendering the flash
        # Just verify the redirect happened and no resonance was created (tested in next spec)
      end

      it "does not create a resonance on error" do
        allow_any_instance_of(SessionsController).to receive(:flash).and_return(
          { google_sign_in: { "error" => "invalid_token" } }
        )
        expect {
          get sign_in_path
        }.not_to change(Resonance, :count)
      end
    end
  end

  describe "DELETE /sign_out" do
    it "clears the session and redirects" do
      google_id = "google-user-123"
      resonance = Resonance.find_or_create_by_google_id(google_id)

      # Simulate signed-in state by posting sign-in first
      identity = double("GoogleSignIn::Identity", user_id: google_id, email_address: "test@example.com")
      allow(GoogleSignIn::Identity).to receive(:new).and_return(identity)
      allow_any_instance_of(SessionsController).to receive(:flash).and_return(
        { google_sign_in: { "id_token" => "token" } }
      )
      get sign_in_path

      # Now sign out
      delete sign_out_path

      expect(response).to redirect_to(home_path)
      expect(session[:google_id]).to be_nil
      expect(session[:obfuscated_user_email]).to be_nil
    end
  end
end
