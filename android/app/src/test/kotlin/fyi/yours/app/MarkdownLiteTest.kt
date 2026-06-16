package fyi.yours.app

import fyi.yours.app.support.MarkdownLite
import fyi.yours.app.support.MarkdownLite.Segment
import org.junit.Assert.assertEquals
import org.junit.Test

// Protects parity with the web client's renderMarkdown/
// formatMarkdownIndicators (chat_controller.js) and the iOS port
// (ios/YoursTests/MarkdownLiteTests.swift). All three clients share these
// invariants.
class MarkdownLiteTest {
    @Test
    fun plainTextPassesThrough() {
        assertEquals(
            listOf(Segment("just some words")),
            MarkdownLite.finalSegments("just some words")
        )
    }

    @Test
    fun boldWithVisibleDimmedIndicators() {
        assertEquals(
            listOf(
                Segment("**", isIndicator = true),
                Segment("bold", bold = true),
                Segment("**", isIndicator = true)
            ),
            MarkdownLite.finalSegments("**bold**")
        )
    }

    @Test
    fun italicDoesNotSpanAcrossSeparateEmphases() {
        assertEquals(
            listOf(
                Segment("*", isIndicator = true),
                Segment("a", italic = true),
                Segment("*", isIndicator = true),
                Segment(" and "),
                Segment("*", isIndicator = true),
                Segment("b", italic = true),
                Segment("*", isIndicator = true)
            ),
            MarkdownLite.finalSegments("*a* and *b*")
        )
    }

    @Test
    fun underscoresInsideWordsAreNotEmphasis() {
        assertEquals(
            listOf(Segment("snake_case_name")),
            MarkdownLite.finalSegments("snake_case_name")
        )
    }

    @Test
    fun italicNestedInsideBold() {
        assertEquals(
            listOf(
                Segment("**", isIndicator = true),
                Segment("a ", bold = true),
                Segment("*", isIndicator = true, bold = true),
                Segment("b", bold = true, italic = true),
                Segment("*", isIndicator = true, bold = true),
                Segment(" c", bold = true),
                Segment("**", isIndicator = true)
            ),
            MarkdownLite.finalSegments("**a *b* c**")
        )
    }

    @Test
    fun doubleUnderscoreBold() {
        assertEquals(
            listOf(
                Segment("__", isIndicator = true),
                Segment("bold", bold = true),
                Segment("__", isIndicator = true)
            ),
            MarkdownLite.finalSegments("__bold__")
        )
    }

    @Test
    fun streamingOnlyDimsIndicators() {
        assertEquals(
            listOf(
                Segment("**", isIndicator = true),
                Segment("bo")
            ),
            MarkdownLite.streamingSegments("**bo")
        )
    }

    @Test
    fun streamingDimsTrailingIndicator() {
        assertEquals(
            listOf(
                Segment("a"),
                Segment("*", isIndicator = true)
            ),
            MarkdownLite.streamingSegments("a*")
        )
    }
}
