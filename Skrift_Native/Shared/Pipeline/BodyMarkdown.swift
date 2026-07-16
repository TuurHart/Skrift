import Foundation

/// The SHARED markdown-styling RULES for the note body — pure text → semantic
/// ranges, so the phone and the Mac can't drift on what counts as a heading or
/// an inline tag (the Obsidian split: `#`+space = heading, `#`+word = tag).
/// Renderers own the LOOK (fonts/colors, Dynamic Type); this owns the WHAT.
/// Characters always stay verbatim — the export is already markdown.
///
/// Today: headings + inline `#tags` (shipped on the Mac 2026-07-16; phone
/// rendering = the pinned "Obsidian-grade markdown body" roadmap idea, which
/// also adds bold/italic/highlight/strike to THIS core).
enum BodyMarkdown {

    /// A markdown heading line: `# Title` … `###### Title` at line start.
    struct Heading: Equatable {
        /// 1…6 (`#` count). Renderers map tiers to fonts (deeper reuse the last).
        let level: Int
        /// The `#…#` marks (rendered faint — visible but receding).
        let marks: NSRange
        /// The title text after the space (rendered as the heading).
        let text: NSRange
    }

    private static let headingRegex = try! NSRegularExpression(
        pattern: #"(?m)^(#{1,6}) (.+)$"#)

    // An inline `#tag` run (Obsidian's alphabet; `#` at start-of-line or after
    // whitespace; ≥1 word char after it, so `# heading` and mid-word `C#` never match).
    private static let hashtagRegex = try! NSRegularExpression(
        pattern: #"(?m)(?:^|(?<=[ \t\n]))#[\p{L}\p{N}_][\p{L}\p{N}_\-/]*"#)

    static func headings(in text: String) -> [Heading] {
        headingRegex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
            .map { Heading(level: $0.range(at: 1).length, marks: $0.range(at: 1), text: $0.range(at: 2)) }
    }

    /// Ranges of inline `#tag` runs (marker + word — the whole run accents).
    static func inlineTags(in text: String) -> [NSRange] {
        hashtagRegex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
            .map(\.range)
    }
}
