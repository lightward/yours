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

  describe "POST /chat/integrate" do
    context "when narrative exists" do
      before do
        resonance.narrative_accumulation_by_day = [
          { "role" => "user", "content" => [{ "type" => "text", "text" => "Hello" }] },
          { "role" => "assistant", "content" => [{ "type" => "text", "text" => "Hi there!" }] }
        ]
        resonance.save!
      end

      it "requires authentication" do
        delete sign_out_path
        post chat_integrate_path
        expect(response).to redirect_to(root_path)
      end

      it "redirects with error message when Lightward AI unavailable", :skip do
        # This would require mocking the HTTP request to Lightward AI
        # Skipping for now as it requires network mocking
      end
    end

    context "when narrative is empty" do
      it "redirects back with alert" do
        post chat_integrate_path
        expect(response).to redirect_to(chat_path)
        expect(flash[:alert]).to eq("No narrative to integrate yet.")
      end
    end
  end
end
