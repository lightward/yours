# frozen_string_literal: true

require "rails_helper"

RSpec.describe("Rollbar privacy protection") do # rubocop:disable RSpec/DescribeClass
  # Test the invariant: "Conversation data never appears in Rollbar payloads"
  # This protects against accidental leaks when adding new features

  let(:google_id) { "test-google-id-#{SecureRandom.hex(8)}" }
  let(:resonance) { Resonance.find_or_create_by_google_id(google_id) }

  describe "privacy-first transform" do
    it "strips request bodies from all error reports" do
      captured_payload = nil
      allow(Rollbar).to receive(:error) do |error, options = {}|
        # Simulate what the transform does
        Rollbar.configuration.transform.each do |transform|
          options = transform.call(options)
        end
        captured_payload = options
      end

      # Simulate an error with sensitive data in the request
      error = StandardError.new("Test error")
      Rollbar.error(error, {
        request: {
          params: { message: "secret conversation data", textarea: "private draft" },
          body: "secret body content",
          POST: { chat_log: "full conversation history" },
          url: "https://yours.fyi/stream?token=secret",
          method: "POST",
          route: "application#stream"
        }
      })

      request = captured_payload[:request]

      # Should preserve safe metadata
      expect(request[:url]).to eq("https://yours.fyi/stream") # query params stripped
      expect(request[:method]).to eq("POST")
      expect(request[:route]).to eq("application#stream")

      # Should NOT include sensitive data
      expect(request[:params]).to be_nil
      expect(request[:body]).to be_nil
      expect(request[:POST]).to be_nil
      expect(request[:session]).to be_nil
    end

    it "clears trace extra data that might contain conversation content" do
      captured_payload = nil
      allow(Rollbar).to receive(:error) do |error, options = {}|
        Rollbar.configuration.transform.each do |transform|
          options = transform.call(options)
        end
        captured_payload = options
      end

      # Simulate an error with sensitive data in trace extra
      error = StandardError.new("Test error")
      Rollbar.error(error, {
        trace: {
          extra: {
            message: "user message content",
            narrative: [ { role: "user", content: "secret" } ],
            some_future_field: "potentially sensitive"
          }
        }
      })

      trace = captured_payload[:trace]
      expect(trace[:extra]).to eq({})
    end

    it "preserves safe headers like User-Agent for debugging" do
      captured_payload = nil
      allow(Rollbar).to receive(:error) do |error, options = {}|
        Rollbar.configuration.transform.each do |transform|
          options = transform.call(options)
        end
        captured_payload = options
      end

      error = StandardError.new("Test error")
      Rollbar.error(error, {
        request: {
          headers: {
            "User-Agent" => "Mozilla/5.0",
            "Authorization" => "Bearer secret-token",
            "Cookie" => "session=secret"
          },
          url: "https://yours.fyi/stream",
          method: "POST"
        }
      })

      request = captured_payload[:request]
      expect(request[:user_agent]).to eq("Mozilla/5.0")
      # Other headers should not appear
      expect(request[:headers]).to be_nil
    end

    it "handles nil request gracefully" do
      captured_payload = nil
      allow(Rollbar).to receive(:error) do |error, options = {}|
        Rollbar.configuration.transform.each do |transform|
          options = transform.call(options)
        end
        captured_payload = options
      end

      error = StandardError.new("Test error")
      expect {
        Rollbar.error(error, { request: nil })
      }.not_to raise_error
    end
  end

  describe "Rails parameter filtering (for local logs)" do
    it "filters conversation-related params from logs" do
      # This tests that config/initializers/filter_parameter_logging.rb
      # includes conversation fields alongside standard sensitive fields

      filter = Rails.application.config.filter_parameters

      # Should include our conversation-related fields
      expect(filter).to include(:message)
      expect(filter).to include(:textarea)
      expect(filter).to include(:chat_log)
      expect(filter).to include(:narrative)
      expect(filter).to include(:harmonic)
      expect(filter).to include(:content)
    end
  end

  describe "CSRF exception level" do
    it "treats CSRF errors on authenticated routes as warnings, not errors" do
      exception = ActionController::InvalidAuthenticityToken.new("CSRF detected")

      # Simulate backtrace from stream action
      allow(exception).to receive(:backtrace).and_return([
        "/app/controllers/application_controller.rb:60:in `stream'",
        "/gems/actionpack/lib/action_controller/metal.rb:123:in `call'"
      ])

      filter = Rollbar.configuration.exception_level_filters['ActionController::InvalidAuthenticityToken']
      level = filter.call(exception)

      expect(level).to eq('warning')
    end

    it "treats CSRF errors on other routes as errors" do
      exception = ActionController::InvalidAuthenticityToken.new("CSRF detected")

      # Simulate backtrace from a different action
      allow(exception).to receive(:backtrace).and_return([
        "/app/controllers/some_other_controller.rb:10:in `some_action'",
        "/gems/actionpack/lib/action_controller/metal.rb:123:in `call'"
      ])

      filter = Rollbar.configuration.exception_level_filters['ActionController::InvalidAuthenticityToken']
      level = filter.call(exception)

      expect(level).to eq('error')
    end
  end
end
