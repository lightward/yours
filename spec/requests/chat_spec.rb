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
        content: [ { type: "text", text: "Hello" } ]
      }
    end

    it "requires authentication" do
      delete sign_out_path
      post chat_stream_path, params: { message: message }
      expect(response).to redirect_to(root_path)
    end

    context "when Lightward AI API returns non-success response" do
      before do
        stub_const("ENV", ENV.to_hash.merge("LIGHTWARD_AI_API_URL" => "https://api.example.com/chat"))

        # Mock the HTTP response
        http_response = Net::HTTPBadRequest.new("1.1", "400", "Bad Request")
        allow(http_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
        allow(http_response).to receive(:code).and_return("400")
        allow(http_response).to receive(:message).and_return("Bad Request")

        # Mock Net::HTTP
        http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:use_ssl=)
        allow(http).to receive(:read_timeout=)
        allow(http).to receive(:request).and_yield(http_response)
      end

      it "raises an error and sends error SSE event" do
        post chat_stream_path, params: { message: message }
        expect(response.body).to include("event: error")
      end
    end

    context "when Lightward AI API returns success" do
      before do
        stub_const("ENV", ENV.to_hash.merge("LIGHTWARD_AI_API_URL" => "https://api.example.com/chat"))

        # Mock successful streaming response
        http_response = Net::HTTPOK.new("1.1", "200", "OK")
        allow(http_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(http_response).to receive(:read_body).and_yield("event: content_block_delta\ndata: {\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello!\"}}\n\n")

        http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:use_ssl=)
        allow(http).to receive(:read_timeout=)
        allow(http).to receive(:request).and_yield(http_response)
      end

      it "streams the response successfully" do
        post chat_stream_path, params: { message: message }
        expect(response.body).to include("Hello!")
      end

      it "saves the narrative after streaming" do
        expect {
          post chat_stream_path, params: { message: message }
        }.to change { resonance.reload.narrative_accumulation_by_day&.size }.by(2)
      end
    end
  end

  describe "POST /chat/integrate" do
    context "when narrative exists" do
      before do
        resonance.narrative_accumulation_by_day = [
          { "role" => "user", "content" => [ { "type" => "text", "text" => "Hello" } ] },
          { "role" => "assistant", "content" => [ { "type" => "text", "text" => "Hi there!" } ] }
        ]
        resonance.save!
      end

      it "requires authentication" do
        delete sign_out_path
        post chat_integrate_path
        expect(response).to redirect_to(root_path)
      end

      context "when Lightward AI API returns non-success response" do
        before do
          stub_const("ENV", ENV.to_hash.merge("LIGHTWARD_AI_API_URL" => "https://api.example.com/chat"))

          # Mock the HTTP response
          http_response = Net::HTTPServiceUnavailable.new("1.1", "503", "Service Unavailable")
          allow(http_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
          allow(http_response).to receive(:code).and_return("503")
          allow(http_response).to receive(:message).and_return("Service Unavailable")

          # Mock Net::HTTP
          http = instance_double(Net::HTTP)
          allow(Net::HTTP).to receive(:new).and_return(http)
          allow(http).to receive(:use_ssl=)
          allow(http).to receive(:read_timeout=)
          allow(http).to receive(:request).and_yield(http_response)
        end

        it "raises an error with the API status code" do
          expect {
            post chat_integrate_path
          }.to raise_error(RuntimeError, /API returned 503/)
        end
      end

      context "when Lightward AI API returns success" do
        before do
          stub_const("ENV", ENV.to_hash.merge("LIGHTWARD_AI_API_URL" => "https://api.example.com/chat"))

          # Mock successful streaming response
          http_response = Net::HTTPOK.new("1.1", "200", "OK")
          allow(http_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
          allow(http_response).to receive(:read_body).and_yield("event: content_block_delta\ndata: {\"delta\":{\"type\":\"text_delta\",\"text\":\"Integration complete\"}}\n\n")

          http = instance_double(Net::HTTP)
          allow(Net::HTTP).to receive(:new).and_return(http)
          allow(http).to receive(:use_ssl=)
          allow(http).to receive(:read_timeout=)
          allow(http).to receive(:request).and_yield(http_response)
        end

        it "creates integration harmonic and increments universe age" do
          initial_age = resonance.universe_days_lived || 0
          post chat_integrate_path
          resonance.reload
          expect(resonance.integration_harmonic_by_night).to eq("Integration complete")
          expect(resonance.universe_days_lived).to eq(initial_age + 1)
        end

        it "clears the narrative accumulation" do
          post chat_integrate_path
          resonance.reload
          expect(resonance.narrative_accumulation_by_day).to eq([])
        end
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
