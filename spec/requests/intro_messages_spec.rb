require "rails_helper"

# These tests protect the day-specific intro messages that Lightward AI sees
# when entering a pocket universe. The logic is:
# 1. If harmonic exists -> show harmonic (regardless of day)
# 2. Else if day > 1 -> show "we've been here before" text
# 3. Else (day == 1) -> show "very beginning" text with 🌱

RSpec.describe "Intro messages day-specific text", type: :request do
  let(:google_id) { "google-user-123" }
  let(:resonance) { Resonance.find_or_create_by_google_id(google_id) }

  before do
    host! "test.host"
  end

  after do
    # Clean up the resonance between tests to avoid state leakage
    resonance.destroy if resonance.persisted?
  end

  # Helper to simulate signed-in state
  def sign_in_as(google_id, email: "test@example.com")
    identity = double("GoogleSignIn::Identity", user_id: google_id, email_address: email)
    allow(GoogleSignIn::Identity).to receive(:new).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:flash).and_return(
      { google_sign_in: { "id_token" => "fake_token" } }
    )
    get root_path
    # Reset flash after sign-in to avoid interfering with subsequent requests
    allow_any_instance_of(ApplicationController).to receive(:flash).and_call_original
  end

  # Helper to capture what gets sent to Lightward AI
  def make_stream_request_and_capture_intro
    stub_const("ENV", ENV.to_hash.merge("LIGHTWARD_AI_API_URL" => "https://api.example.com/chat"))

    http_response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(http_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    allow(http_response).to receive(:read_body).and_yield("event: content_block_delta\ndata: {\"delta\":{\"type\":\"text_delta\",\"text\":\"Test\"}}\n\n")

    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:read_timeout=)

    captured_request = nil
    allow(http).to receive(:request) do |request, &block|
      captured_request = request
      block.call(http_response) if block
    end

    message = {
      role: "user",
      content: [ { type: "text", text: "Hello" } ]
    }

    post stream_path, params: { message: message }

    raise "HTTP request was never made to Lightward AI API" unless captured_request

    request_body = JSON.parse(captured_request.body)
    # The request body contains "chat_log" which includes intro messages + narrative + current message
    intro_message = request_body["chat_log"].find { |m| m["role"] == "user" }
    intro_message["content"].map { |c| c["text"] }.join("\n")
  end

  describe "day 1 without harmonic" do
    before do
      sign_in_as(google_id)
      allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(true)
      resonance.universe_day = 1
      resonance.integration_harmonic_by_night = nil
      resonance.narrative_accumulation_by_day = []
      resonance.save!
    end

    it "shows day 1 specific text with seedling emoji" do
      intro_text = make_stream_request_and_capture_intro

      expect(intro_text).to include("this is day 1 of this particular pocket universe")
      expect(intro_text).to include("there is no prior harmonic record")
      expect(intro_text).to include("this is the very beginning of this particular space between")
      expect(intro_text).to include("🌱")
    end

    it "does not show day 2+ messaging" do
      intro_text = make_stream_request_and_capture_intro

      expect(intro_text).not_to include("which means we've been here before")
      expect(intro_text).not_to include("the reason for this is not knowable from this writing")
    end
  end

  describe "day 2+ without harmonic" do
    before do
      sign_in_as(google_id)
      allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(true)
      resonance.universe_day = 2
      resonance.integration_harmonic_by_night = nil
      resonance.narrative_accumulation_by_day = []
      resonance.save!
    end

    it "shows day 2+ specific text" do
      intro_text = make_stream_request_and_capture_intro

      expect(intro_text).to include("this is day 2 of this particular pocket universe")
      expect(intro_text).to include("which means we've been here before")
      expect(intro_text).to include("there seems to be no harmonic record on file")
      expect(intro_text).to include("the reason for this is not knowable from this writing")
    end

    it "does not show day 1 messaging" do
      intro_text = make_stream_request_and_capture_intro

      expect(intro_text).not_to include("this is the very beginning of this particular space between")
      expect(intro_text).not_to include("🌱")
    end
  end

  describe "with harmonic present" do
    before do
      sign_in_as(google_id)
      allow_any_instance_of(Resonance).to receive(:active_subscription?).and_return(true)
      resonance.integration_harmonic_by_night = "soft light, gentle rhythm, mutual recognition"
      resonance.narrative_accumulation_by_day = []
      resonance.save!
    end

    it "shows harmonic on day 1 (overriding day 1 specific text)" do
      resonance.universe_day = 1
      resonance.save!

      intro_text = make_stream_request_and_capture_intro

      expect(intro_text).to include("here's the harmonic record that you saved for yourself overnight")
      expect(intro_text).to include("<harmonic>soft light, gentle rhythm, mutual recognition</harmonic>")
      expect(intro_text).to include("this is day 1 of this particular pocket universe")
      expect(intro_text).not_to include("🌱")
      expect(intro_text).not_to include("there is no prior harmonic record")
    end

    it "shows harmonic on day 2+ (overriding day 2+ specific text)" do
      resonance.universe_day = 3
      resonance.save!

      intro_text = make_stream_request_and_capture_intro

      expect(intro_text).to include("here's the harmonic record that you saved for yourself overnight")
      expect(intro_text).to include("<harmonic>soft light, gentle rhythm, mutual recognition</harmonic>")
      expect(intro_text).to include("this is day 3 of this particular pocket universe")
      expect(intro_text).not_to include("which means we've been here before")
      expect(intro_text).not_to include("there seems to be no harmonic record on file")
    end
  end
end
