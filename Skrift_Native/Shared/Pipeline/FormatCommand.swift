import Foundation

/// The editor's formatting commands, ONE set for both apps (Q360 on the Mac, Q379 on the iPad;
/// D115, D197 "Apple's full list"): the Mac's Format menu, its Aa popover and right-click
/// block, and the iPad's Aa popover all read these. The edits themselves are the shared
/// `BodyFormat` (stored Markdown, C116; marks stay visible but dim, C24).
///
/// Foundation only, so the Mac's host-less unit bundle compiles it (`MacEditorFormattingTests`).
enum FormatCommand: CaseIterable, Hashable {
    case bold, italic, underline, strikethrough, highlight
    case title, heading, subheading, body, monostyled
    case bulletList, dashedList, numberedList
    case blockQuote
    case checklist

    var title: String {
        switch self {
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .underline: return "Underline"
        case .strikethrough: return "Strikethrough"
        case .highlight: return "Highlight"
        case .title: return "Title"
        case .heading: return "Heading"
        case .subheading: return "Subheading"
        case .body: return "Body"
        case .monostyled: return "Monostyled"
        case .bulletList: return "Bulleted List"
        case .dashedList: return "Dashed List"
        case .numberedList: return "Numbered List"
        case .blockQuote: return "Block Quote"
        case .checklist: return "Checklist"
        }
    }

    /// Apple Notes' chords; Q126's ⇧⌘L checklist stays. Highlight has none.
    var chord: AppShortcuts.Chord? {
        let c: (String) -> AppShortcuts.Chord = { .init(key: $0, modifiers: [.command]) }
        let sc: (String) -> AppShortcuts.Chord = { .init(key: $0, modifiers: [.command, .shift]) }
        switch self {
        case .bold: return c("b")
        case .italic: return c("i")
        case .underline: return c("u")
        case .strikethrough: return sc("x")
        case .highlight: return nil
        case .title: return sc("t")
        case .heading: return sc("h")
        case .subheading: return sc("j")
        case .body: return sc("b")
        case .monostyled: return sc("m")
        case .bulletList: return sc("7")
        case .dashedList: return sc("8")
        case .numberedList: return sc("9")
        case .blockQuote: return c("'")
        case .checklist: return sc("l")
        }
    }

    var mark: BodyFormat.InlineMark? {
        switch self {
        case .bold: return .bold
        case .italic: return .italic
        case .underline: return .underline
        case .strikethrough: return .strike
        case .highlight: return .highlight
        default: return nil
        }
    }

    var lineStyle: BodyFormat.LineStyle? {
        switch self {
        case .title: return .title
        case .heading: return .heading
        case .subheading: return .subheading
        case .body: return .body
        case .bulletList: return .bullet
        case .dashedList: return .dashed
        case .numberedList: return .numbered
        case .blockQuote: return .quote
        case .checklist: return .checklist
        default: return nil
        }
    }

    /// The Markdown the command writes, as the touch Aa panels caption it (no chords on touch).
    var markdownHint: String {
        if let mark { return mark.open + "…" + mark.close }
        switch self {
        case .title: return "# "
        case .heading: return "## "
        case .subheading: return "### "
        case .body: return "plain"
        case .monostyled: return "`code`"
        case .bulletList: return "- "
        case .dashedList: return "* "
        case .numberedList: return "1. "
        case .blockQuote: return "> "
        case .checklist: return "- [ ] "
        default: return ""
        }
    }

    /// The Aa popover, Apple Notes' order (Tuur 2026-10-13): B I U S | highlight; the styles;
    /// the lists; Block Quote.
    static let aaMarks: [FormatCommand] = [.bold, .italic, .underline, .strikethrough, .highlight]
    static let aaStyles: [FormatCommand] = [.title, .heading, .subheading, .body, .monostyled]
    static let aaLists: [FormatCommand] = [.bulletList, .dashedList, .numberedList]
    static let aaTail: [FormatCommand] = [.blockQuote]
}
