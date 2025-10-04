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

  private

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
