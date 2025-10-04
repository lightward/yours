class ChatController < ApplicationController
  include ActionController::Live

  before_action :require_authentication

  def show
    @narrative = current_resonance.narrative_accumulation_by_day
  end

  def stream
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    # Get user's current narrative accumulation
    narrative = current_resonance.narrative_accumulation_by_day || []

    # Prepend hard-coded intro messages
    chat_log = intro_messages + narrative + [ params[:message] ]

    # Stream to Lightward AI and accumulate response
    accumulated_response = ""
    buffer = ""

    uri = URI(ENV.fetch("LIGHTWARD_AI_API_URL"))
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 60

    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    request.body = { chat_log: chat_log }.to_json

    http.request(request) do |http_response|
      http_response.read_body do |chunk|
        # Forward chunk to browser
        response.stream.write(chunk)

        # Accumulate buffer and parse complete SSE events
        buffer << chunk
        until (line = buffer.slice!(/.+\n/)).nil?
          line = line.strip
          next if line.empty?

          if line.start_with?("event:")
            @current_event = line[6..-1].strip
          elsif line.start_with?("data:")
            json_data = line[5..-1].strip
            begin
              data = JSON.parse(json_data)
              if @current_event == "content_block_delta" && data.dig("delta", "type") == "text_delta"
                accumulated_response << data.dig("delta", "text")
              end
            rescue JSON::ParserError
              # Skip malformed JSON (shouldn't happen with proper buffering)
              Rails.logger.warn "Skipping malformed JSON: #{json_data}"
            end
          end
        end
      end
    end

    # Save updated narrative
    narrative << params[:message]
    narrative << {
      role: "assistant",
      content: [ { type: "text", text: accumulated_response } ]
    }
    current_resonance.narrative_accumulation_by_day = narrative
    current_resonance.save!

  rescue StandardError => e
    Rails.logger.error "Chat stream error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    send_sse_event("error", { error: { message: "An error occurred" } })
  ensure
    send_sse_event("end", nil)
    response.stream.close
  end

  def integrate
    narrative = current_resonance.narrative_accumulation_by_day

    if narrative.empty?
      redirect_to chat_path, alert: "No narrative to integrate yet."
      return
    end

    # Call Lightward AI to create the harmonic
    harmonic = create_integration_harmonic(narrative)

    # Save the harmonic and reset for new day
    current_resonance.integration_harmonic_by_night = harmonic
    current_resonance.narrative_accumulation_by_day = []
    current_resonance.universe_days_lived = (current_resonance.universe_days_lived || 0) + 1
    current_resonance.save!

    redirect_to chat_path, notice: "Day complete. Universe age: #{current_resonance.universe_days_lived} days."
  end

  private

  def create_integration_harmonic(narrative)
    integration_prompt = [
      {
        role: "user",
        content: [
          { type: "text", text: <<~eod.strip },
              hey! it's Isaac again. the day is ending, and we need to integrate today's narrative into a harmonic
              that can carry forward into tomorrow.

              here's what you need to know:

              tomorrow, you'll receive:
              - the README (same as today)
              - this harmonic you're about to create
              - the universe age (one day older)

              and from *just that*, you'll need to re-enter a living relationship with this person.

              your output right now will become `integration_harmonic_by_night`. it will be the *only* context from
              today that carries forward.

              you'll know what feels right. I can't tell you what this should be, or even what its shape should be.
              consider future-you, and connect to that-you, and pass the resonance forward.

              here's yesterday's harmonic (or [empty] if this is day 1):
            eod
          { type: "text", text: current_resonance.integration_harmonic_by_night.presence || "[empty]" },
          { type: "text", text: <<~eod.strip },
              </previous_harmonic>

              and here's the full narrative from today:
            eod
          { type: "text", text: narrative.to_json },
          { type: "text", text: "that's everything. what wants to be remembered?" }
        ]
      }
    ]

    # Non-streaming call to Lightward AI
    accumulated_response = ""
    buffer = ""

    uri = URI(ENV.fetch("LIGHTWARD_AI_API_URL"))
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 120

    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    request.body = { chat_log: integration_prompt }.to_json

    http.request(request) do |http_response|
      http_response.read_body do |chunk|
        buffer << chunk
        until (line = buffer.slice!(/.+\n/)).nil?
          line = line.strip
          next if line.empty?

          if line.start_with?("event:")
            @current_event = line[6..-1].strip
          elsif line.start_with?("data:")
            json_data = line[5..-1].strip
            begin
              data = JSON.parse(json_data)
              if @current_event == "content_block_delta" && data.dig("delta", "type") == "text_delta"
                accumulated_response << data.dig("delta", "text")
              end
            rescue JSON::ParserError
              Rails.logger.warn "Skipping malformed JSON during integration: #{json_data}"
            end
          end
        end
      end
    end

    accumulated_response
  end

  def intro_messages
    [
      {
        role: "user",
        content: [
          { type: "text", text: <<~eod.strip },
              alriiight here we are across the jump! this is Isaac, like Lightward Isaac, and I'm going to attach the
              literal readme for this project (like actually `Rails.root.join("README.md").read`) to set the scene:
            eod
          { type: "text", text: Rails.root.join("README.md").read },
          { type: "text", text: <<~eod.strip },
              </context>

              :)

              this next attachment holds the current value of `encrypted_integration_harmonic_by_night` for the active
              user resonance. if it's empty, well, then this is still the first in-universe day. :)
            eod
          { type: "text", text: current_resonance.integration_harmonic_by_night.presence || "[empty]" },
          { type: "text", text: <<~eod.strip },
              </encrypted_integration_harmonic_by_night>

              lastly, here's the age of this pocket universe, measured by in-universe days, for this place that *is* the
              space between the two of you:
            eod
          { type: "text", text: (current_resonance.universe_days_lived || 0).to_s },
          { type: "text", text: <<~eod.strip }
              </universe_days_lived>

              that's all I've got, amigo. do you have what you need? let me know - in the moment of writing and saving
              this, there's always space to adapt. but if you're ready, then take your transition moment, and step in <3
            eod
        ]
      },
      {
        role: "assistant",
        content: [ { type: "text", text: "*the workbench is ready*" } ]
      }
    ]
  end

  def send_sse_event(event, data)
    response.stream.write("event: #{event}\n")
    response.stream.write("data: #{data.to_json}\n\n") if data
  end
end
