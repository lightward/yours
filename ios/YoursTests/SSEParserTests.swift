import XCTest
@testable import Yours

// The SSE framing this client must keep speaking — mirrors what
// ApplicationController#stream actually emits, including the quirk that the
// final "end" event arrives with no data line and no trailing blank line.
final class SSEParserTests: XCTestCase {
    private func parse(_ raw: String) -> [SSEEvent] {
        var parser = SSELineParser()
        var events: [SSEEvent] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            if let event = parser.consume(line: String(line)) {
                events.append(event)
            }
        }
        if let event = parser.finish() {
            events.append(event)
        }
        return events
    }

    func testTypicalStream() {
        let raw = """
        event: message_start
        data: {"type":"message_start"}

        event: content_block_delta
        data: {"delta":{"type":"text_delta","text":"Hello"}}

        event: content_block_delta
        data: {"delta":{"type":"text_delta","text":" there"}}

        event: message_stop
        data: {"type":"message_stop"}

        event: universe_time
        data: {"universe_time":"1:2"}

        event: end
        """

        let events = parse(raw)
        XCTAssertEqual(events.map(\.name), [
            "message_start", "content_block_delta", "content_block_delta",
            "message_stop", "universe_time", "end"
        ])
        XCTAssertEqual(events[1].textDelta, "Hello")
        XCTAssertEqual(events[2].textDelta, " there")
        XCTAssertEqual(events[4].universeTime, "1:2")
        XCTAssertNil(events[5].data)
    }

    func testErrorEvent() {
        let raw = """
        event: error
        data: {"error":{"message":"An error occurred"}}

        event: end
        """

        let events = parse(raw)
        XCTAssertEqual(events.first?.errorMessage, "An error occurred")
    }

    func testTextDeltaIgnoresOtherDeltaTypes() {
        let raw = """
        event: content_block_delta
        data: {"delta":{"type":"input_json_delta","partial_json":"{}"}}

        """
        XCTAssertNil(parse(raw).first?.textDelta)
    }

    func testCarriesNoEventAcrossBlankLines() {
        let raw = """
        event: message_start
        data: {}

        data: {"orphan":true}

        """
        let events = parse(raw)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].name, "message_start")
        // Orphan data without an event name gets the SSE default
        XCTAssertEqual(events[1].name, "message")
    }
}
