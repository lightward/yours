import Foundation

// One server-sent event off the /stream wire. The server relays upstream
// event names and adds its own (universe_time, error, end). See PROTOCOL.md
// for framing details.
struct SSEEvent: Equatable {
    var name: String
    var data: String?

    // Decodes the data payload's interesting fields without committing to a
    // full schema — unknown events pass through harmlessly.
    var textDelta: String? {
        guard name == "content_block_delta", let object = jsonObject,
              let delta = object["delta"] as? [String: Any],
              delta["type"] as? String == "text_delta"
        else { return nil }
        return delta["text"] as? String
    }

    var universeTime: String? {
        guard name == "universe_time", let object = jsonObject else { return nil }
        return object["universe_time"] as? String
    }

    var errorMessage: String? {
        guard name == "error", let object = jsonObject,
              let error = object["error"] as? [String: Any]
        else { return nil }
        return error["message"] as? String
    }

    private var jsonObject: [String: Any]? {
        guard let data = data?.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

// Line-by-line SSE parser. Dispatch-on-blank-line per the SSE spec, with one
// accommodation for this server: the final "end" event arrives without a
// trailing blank line, so finish() flushes whatever is pending at EOF.
struct SSELineParser {
    private var pendingName: String?
    private var pendingData: String?

    mutating func consume(line: String) -> SSEEvent? {
        if line.isEmpty {
            return flush()
        }
        if line.hasPrefix("event:") {
            let flushed = (pendingData != nil) ? flush() : nil
            pendingName = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
            return flushed
        }
        if line.hasPrefix("data:") {
            let value = String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
            pendingData = pendingData.map { $0 + "\n" + value } ?? value
            return nil
        }
        return nil
    }

    mutating func finish() -> SSEEvent? {
        flush()
    }

    private mutating func flush() -> SSEEvent? {
        guard pendingName != nil || pendingData != nil else { return nil }
        let event = SSEEvent(name: pendingName ?? "message", data: pendingData)
        pendingName = nil
        pendingData = nil
        return event
    }
}
