import XCTest
@testable import Yours

// H6 regression: the streaming response is targeted by stable id, not by a
// captured array index. A concurrent apply(state:) (refresh, purchase,
// mid-stream universe_time) replaces the whole messages array; the in-flight
// delta writes must not land on the wrong message or trap on a stale index.
@MainActor
final class StreamingSafetyTests: XCTestCase {
    private func makeModel() -> AppModel {
        // No token, no mock: start() will route to landing and touch nothing
        // external. We exercise the message bookkeeping directly.
        AppModel()
    }

    func testUpdateStreamingMutatesTheRightMessageByID() {
        let model = makeModel()
        model.messages = [
            .init(role: "user", text: "hello"),
            .init(role: "assistant", text: ".", isPulsing: true, isComplete: false)
        ]
        let streamingID = model.messages[1].id

        model.updateStreaming(streamingID) { $0.isPulsing = false; $0.text = "Hi" }

        XCTAssertEqual(model.messages[1].text, "Hi")
        XCTAssertFalse(model.messages[1].isPulsing)
        // The unrelated message is untouched
        XCTAssertEqual(model.messages[0].text, "hello")
    }

    func testUpdateStreamingNoOpsWhenMessageWasRemoved() {
        let model = makeModel()
        let placeholder = AppModel.DisplayMessage(role: "assistant", text: ".", isPulsing: true, isComplete: false)
        let streamingID = placeholder.id
        model.messages = [placeholder]

        // Simulate apply(state:) replacing the array out from under the stream
        model.messages = [
            .init(role: "user", text: "fresh from server"),
            .init(role: "assistant", text: "fresh reply")
        ]

        // The in-flight delta must not crash and must not corrupt the new array
        model.updateStreaming(streamingID) { $0.text += "LATE DELTA" }

        XCTAssertEqual(model.messages.count, 2)
        XCTAssertEqual(model.messages[0].text, "fresh from server")
        XCTAssertEqual(model.messages[1].text, "fresh reply")
        XCTAssertFalse(model.messages.contains { $0.text.contains("LATE DELTA") })
    }

    func testStreamingTargetSurvivesInsertionsBeforeIt() {
        let model = makeModel()
        let placeholder = AppModel.DisplayMessage(role: "assistant", text: "", isPulsing: false, isComplete: false)
        let streamingID = placeholder.id
        model.messages = [placeholder]

        // Something prepends (index would now be wrong); id lookup still finds it
        model.messages.insert(.init(role: "user", text: "inserted before"), at: 0)

        model.updateStreaming(streamingID) { $0.text += "delta" }

        XCTAssertEqual(model.messages.first(where: { $0.id == streamingID })?.text, "delta")
        XCTAssertEqual(model.messages.count, 2)
    }
}
