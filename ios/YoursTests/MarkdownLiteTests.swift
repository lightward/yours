import XCTest
@testable import Yours

// Protects parity with the web client's renderMarkdown/
// formatMarkdownIndicators (chat_controller.js). If rendering behavior
// changes there, it should change here — these are the invariants both
// clients share.
final class MarkdownLiteTests: XCTestCase {
    typealias Segment = MarkdownLite.Segment

    func testPlainTextPassesThrough() {
        XCTAssertEqual(
            MarkdownLite.finalSegments("just some words"),
            [Segment(text: "just some words")]
        )
    }

    func testBoldWithVisibleDimmedIndicators() {
        XCTAssertEqual(MarkdownLite.finalSegments("**bold**"), [
            Segment(text: "**", isIndicator: true),
            Segment(text: "bold", bold: true),
            Segment(text: "**", isIndicator: true)
        ])
    }

    func testItalicDoesNotSpanAcrossSeparateEmphases() {
        // The key constraint from the web: *a* and *b* must not become one
        // italic run spanning " and "
        XCTAssertEqual(MarkdownLite.finalSegments("*a* and *b*"), [
            Segment(text: "*", isIndicator: true),
            Segment(text: "a", italic: true),
            Segment(text: "*", isIndicator: true),
            Segment(text: " and "),
            Segment(text: "*", isIndicator: true),
            Segment(text: "b", italic: true),
            Segment(text: "*", isIndicator: true)
        ])
    }

    func testUnderscoresInsideWordsAreNotEmphasis() {
        XCTAssertEqual(
            MarkdownLite.finalSegments("snake_case_name"),
            [Segment(text: "snake_case_name")]
        )
    }

    func testItalicNestedInsideBold() {
        XCTAssertEqual(MarkdownLite.finalSegments("**a *b* c**"), [
            Segment(text: "**", isIndicator: true),
            Segment(text: "a ", bold: true),
            Segment(text: "*", isIndicator: true, bold: true),
            Segment(text: "b", bold: true, italic: true),
            Segment(text: "*", isIndicator: true, bold: true),
            Segment(text: " c", bold: true),
            Segment(text: "**", isIndicator: true)
        ])
    }

    func testDoubleUnderscoreBold() {
        XCTAssertEqual(MarkdownLite.finalSegments("__bold__"), [
            Segment(text: "__", isIndicator: true),
            Segment(text: "bold", bold: true),
            Segment(text: "__", isIndicator: true)
        ])
    }

    func testStreamingOnlyDimsIndicators() {
        XCTAssertEqual(MarkdownLite.streamingSegments("**bo"), [
            Segment(text: "**", isIndicator: true),
            Segment(text: "bo")
        ])
    }

    func testStreamingDimsTrailingIndicator() {
        XCTAssertEqual(MarkdownLite.streamingSegments("a*"), [
            Segment(text: "a"),
            Segment(text: "*", isIndicator: true)
        ])
    }
}
