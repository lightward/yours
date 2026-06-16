package fyi.yours.app.support

// A faithful port of the web client's surgical markdown handling
// (chat_controller.js renderMarkdown / formatMarkdownIndicators): bold and
// italic only, with the indicator characters kept visible but dimmed.
// Anything beyond that intentionally stays plain text — same as the web and
// iOS (ios/Yours/Support/MarkdownLite.swift).
object MarkdownLite {
    data class Segment(
        val text: String,
        val isIndicator: Boolean = false,
        val bold: Boolean = false,
        val italic: Boolean = false
    )

    // Same placeholder strategy and ordering as the web client. Key
    // constraint preserved: italic markers must sit at word boundaries so
    // *a* ... *b* never spans between them.
    private val passes = listOf(
        Regex("""\*\*([^*]+(?:\*[^*]+)*)\*\*""") to "〔B2〕$1〔/B2〕",
        Regex("""__([^_]+(?:_[^_]+)*)__""") to "〔BU〕$1〔/BU〕",
        Regex("""(?:^|(?<=[\s〔]))(\*)((?:\S[^*]*?\S|\S))\*(?=[\s.,!?;:〔]|$)""") to "〔I1〕$2〔/I1〕",
        Regex("""(?:^|(?<=[\s〔]))(_)((?:\S[^_]*?\S|\S))_(?=[\s.,!?;:〔]|$)""") to "〔IU〕$2〔/IU〕"
    )

    private data class Token(val marker: String, val opens: Boolean, val bold: Boolean)

    private val tokens = listOf(
        "〔B2〕" to Token("**", opens = true, bold = true),
        "〔/B2〕" to Token("**", opens = false, bold = true),
        "〔BU〕" to Token("__", opens = true, bold = true),
        "〔/BU〕" to Token("__", opens = false, bold = true),
        "〔I1〕" to Token("*", opens = true, bold = false),
        "〔/I1〕" to Token("*", opens = false, bold = false),
        "〔IU〕" to Token("_", opens = true, bold = false),
        "〔/IU〕" to Token("_", opens = false, bold = false)
    )

    // Full treatment, applied once a message is complete
    fun finalSegments(text: String): List<Segment> {
        var processed = text
        for ((regex, template) in passes) {
            processed = regex.replace(processed) { match ->
                template.replace("$1", match.groupValues.getOrElse(1) { "" })
                    .replace("$2", match.groupValues.getOrElse(2) { "" })
            }
        }
        return segmentsFromPlaceholdered(processed)
    }

    // Streaming treatment: indicators dim as they arrive, no styling yet
    fun streamingSegments(text: String): List<Segment> {
        val patterns = listOf(
            Regex("""(\*\*?)(?=\S)"""),
            Regex("""(?<=\S)(\*\*?)"""),
            Regex("""(__?)(?=\S)"""),
            Regex("""(?<=\S)(__?)""")
        )

        val isIndicator = BooleanArray(text.length)
        for (pattern in patterns) {
            for (match in pattern.findAll(text)) {
                val range = match.groups[1]?.range ?: continue
                for (i in range) isIndicator[i] = true
            }
        }

        val segments = mutableListOf<Segment>()
        var start = 0
        for (i in 1..text.length) {
            if (i == text.length || isIndicator[i] != isIndicator[start]) {
                segments.add(Segment(text.substring(start, i), isIndicator = isIndicator[start]))
                start = i
            }
        }
        return segments
    }

    private fun segmentsFromPlaceholdered(processed: String): List<Segment> {
        val result = mutableListOf<Segment>()
        var boldDepth = 0
        var italicDepth = 0
        var remaining = processed

        fun appendText(text: String) {
            if (text.isEmpty()) return
            result.add(Segment(text, bold = boldDepth > 0, italic = italicDepth > 0))
        }

        while (remaining.isNotEmpty()) {
            var earliestIndex = -1
            var earliest: Pair<String, Token>? = null
            for (entry in tokens) {
                val index = remaining.indexOf(entry.first)
                if (index >= 0 && (earliestIndex < 0 || index < earliestIndex)) {
                    earliestIndex = index
                    earliest = entry
                }
            }
            if (earliest == null) break

            appendText(remaining.substring(0, earliestIndex))
            val token = earliest.second

            // Mirrors the web's HTML nesting: an opening indicator sits
            // outside the style it opens; a closing one outside the style it
            // closes; both inherit any styles already on the stack.
            if (!token.opens) {
                if (token.bold) boldDepth = maxOf(0, boldDepth - 1)
                else italicDepth = maxOf(0, italicDepth - 1)
            }
            result.add(
                Segment(token.marker, isIndicator = true, bold = boldDepth > 0, italic = italicDepth > 0)
            )
            if (token.opens) {
                if (token.bold) boldDepth++ else italicDepth++
            }

            remaining = remaining.substring(earliestIndex + earliest.first.length)
        }
        appendText(remaining)
        return result
    }
}
