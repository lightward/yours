require "rails_helper"

RSpec.describe "Chat", type: :request do
  let(:google_id) { "google-user-123" }
  let(:resonance) { Resonance.find_or_create_by_google_id(google_id) }

  before do
    # Sign in
    identity = double("GoogleSignIn::Identity", user_id: google_id)
    allow(GoogleSignIn::Identity).to receive(:new).and_return(identity)
    allow_any_instance_of(SessionsController).to receive(:flash).and_return(
      { google_sign_in: { "id_token" => "fake_token" } }
    )
    get sign_in_path
  end

  describe "GET /chat" do
    it "returns http success" do
      get chat_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /chat/stream" do
    let(:message) do
      {
        role: "user",
        content: [{ type: "text", text: "Hello" }]
      }
    end

    it "requires authentication" do
      delete sign_out_path
      post chat_stream_path, params: { message: message }
      expect(response).to redirect_to(root_path)
    end

    # Note: Full SSE streaming spec would require mocking the Lightward AI API
    # For now, we verify the endpoint exists and requires auth
  end
end
