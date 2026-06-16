import SwiftUI

// A faithful port of the web client's surgical markdown handling
// (chat_controller.js renderMarkdown / formatMarkdownIndicators): bold and
// italic only, with the indicator characters kept visible but dimmed.
// Anything beyond that intentionally stays plain text — same as the web.
enum MarkdownLite {
    struct Segment: Equatable {
        var text: String
        var isIndicator = false
        var bold = false
        var italic = false
    }

    // MARK: - Public renderers

    // Full treatment, applied once a message is complete
    static func rendered(_ text: String) -> AttributedString {
        attributed(from: finalSegments(text))
    }

    // Streaming treatment: indicators dim as they arrive, no styling yet
    static func streaming(_ text: String) -> AttributedString {
        attributed(from: streamingSegments(text))
    }

    // MARK: - Segmentation (exposed for tests)

    static func finalSegments(_ text: String) -> [Segment] {
        var processed = text

        // Same placeholder strategy and ordering as the web client. Key
        // constraint preserved: italic markers must sit at word boundaries so
        // *a* ... *b* never spans between them.
        let passes: [(pattern: String, template: String)] = [
            (#"\*\*([^*]+(?:\*[^*]+)*)\*\*"#, "〔B2〕$1〔/B2〕"),
            (#"__([^_]+(?:_[^_]+)*)__"#, "〔BU〕$1〔/BU〕"),
            (#"(?:^|(?<=[\s〔]))(\*)((?:\S[^*]*?\S|\S))\*(?=[\s.,!?;:〔]|$)"#, "〔I1〕$2〔/I1〕"),
            (#"(?:^|(?<=[\s〔]))(_)((?:\S[^_]*?\S|\S))_(?=[\s.,!?;:〔]|$)"#, "〔IU〕$2〔/IU〕")
        ]
        for pass in passes {
            guard let regex = try? NSRegularExpression(pattern: pass.pattern) else { continue }
            processed = regex.stringByReplacingMatches(
                in: processed,
                range: NSRange(processed.startIndex..., in: processed),
                withTemplate: pass.template
            )
        }

        return segments(fromPlaceholdered: processed)
    }

    static func streamingSegments(_ text: String) -> [Segment] {
        let patterns = [
            #"(\*\*?)(?=\S)"#,
            #"(?<=\S)(\*\*?)"#,
            #"(__?)(?=\S)"#,
            #"(?<=\S)(__?)"#
        ]

        var indicatorIndices = IndexSet()
        let nsText = text as NSString
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            regex.enumerateMatches(in: text, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
                if let range = match?.range(at: 1) {
                    indicatorIndices.insert(integersIn: range.location..<(range.location + range.length))
                }
            }
        }

        var result: [Segment] = []
        for run in indicatorRuns(length: nsText.length, indicators: indicatorIndices) {
            let segmentText = nsText.substring(with: NSRange(location: run.range.lowerBound, length: run.range.count))
            result.append(Segment(text: segmentText, isIndicator: run.isIndicator))
        }
        return result
    }

    // MARK: - Internals

    private struct Token {
        let marker: String   // the literal indicator characters, e.g. "**"
        let opens: Bool
        let bold: Bool       // which style this token toggles
    }

    private static let tokens: [(placeholder: String, token: Token)] = [
        ("〔B2〕", Token(marker: "**", opens: true, bold: true)),
        ("〔/B2〕", Token(marker: "**", opens: false, bold: true)),
        ("〔BU〕", Token(marker: "__", opens: true, bold: true)),
        ("〔/BU〕", Token(marker: "__", opens: false, bold: true)),
        ("〔I1〕", Token(marker: "*", opens: true, bold: false)),
        ("〔/I1〕", Token(marker: "*", opens: false, bold: false)),
        ("〔IU〕", Token(marker: "_", opens: true, bold: false)),
        ("〔/IU〕", Token(marker: "_", opens: false, bold: false))
    ]

    private static func segments(fromPlaceholdered processed: String) -> [Segment] {
        var result: [Segment] = []
        var boldDepth = 0
        var italicDepth = 0
        var remaining = Substring(processed)

        func appendText(_ text: Substring) {
            guard !text.isEmpty else { return }
            result.append(Segment(text: String(text), bold: boldDepth > 0, italic: italicDepth > 0))
        }

        while !remaining.isEmpty {
            var earliest: (range: Range<Substring.Index>, token: Token)?
            for entry in tokens {
                if let range = remaining.range(of: entry.placeholder),
                   earliest == nil || range.lowerBound < earliest!.range.lowerBound {
                    earliest = (range, entry.token)
                }
            }
            guard let (range, token) = earliest else { break }

            appendText(remaining[..<range.lowerBound])

            // Mirrors the web's HTML nesting: an opening indicator sits
            // outside the style it opens; a closing one outside the style it
            // closes; both inherit any styles already on the stack.
            if !token.opens {
                if token.bold { boldDepth = max(0, boldDepth - 1) } else { italicDepth = max(0, italicDepth - 1) }
            }
            result.append(Segment(
                text: token.marker,
                isIndicator: true,
                bold: boldDepth > 0,
                italic: italicDepth > 0
            ))
            if token.opens {
                if token.bold { boldDepth += 1 } else { italicDepth += 1 }
            }

            remaining = remaining[range.upperBound...]
        }
        appendText(remaining)
        return result
    }

    private static func indicatorRuns(length: Int, indicators: IndexSet) -> [(range: Range<Int>, isIndicator: Bool)] {
        var runs: [(Range<Int>, Bool)] = []
        var start = 0
        var current: Bool?
        for index in 0..<length {
            let isIndicator = indicators.contains(index)
            if current == nil {
                current = isIndicator
            } else if isIndicator != current {
                runs.append((start..<index, current!))
                start = index
                current = isIndicator
            }
        }
        if let current, start < length {
            runs.append((start..<length, current))
        }
        return runs
    }

    private static func attributed(from segments: [Segment]) -> AttributedString {
        var result = AttributedString()
        for segment in segments {
            var piece = AttributedString(segment.text)
            piece.font = font(bold: segment.bold, italic: segment.italic)
            if segment.isIndicator {
                // .markdown-indicator { opacity: 0.7 }
                piece.foregroundColor = Theme.foreground.opacity(0.7)
            }
            result += piece
        }
        return result
    }

    private static func font(bold: Bool, italic: Bool) -> Font {
        var font: Font = .system(size: 16, weight: bold ? .bold : .light, design: .monospaced)
        if italic { font = font.italic() }
        return font
    }
}
