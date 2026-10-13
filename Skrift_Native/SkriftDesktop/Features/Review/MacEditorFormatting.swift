import Foundation

/// Q360 (D115, signed mock `Q350-note-editor-apple.html`, D196, Tuur 2026-10-13 "Apple's full
/// list"): the Mac editor's formatting commands, written ONCE for the three places that show
/// them: the Format menu (shortcuts), the band's Aa popover, and the Format block at the top of
/// the body's right-click menu. The edits themselves are the shared `BodyFormat` (stored
/// Markdown, C116; marks stay visible but dim, C24).
///
/// Foundation only, so the host-less unit bundle compiles it (`MacEditorFormattingTests`).
enum MacEditorFormatting {
    enum Command: CaseIterable, Hashable {
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
    }

    /// The Aa popover, Apple Notes' order (Tuur 2026-10-13): B I U S | highlight; the styles
    /// (Body checked when current); the lists; a divider; Block Quote.
    static let popoverMarks: [Command] = [.bold, .italic, .underline, .strikethrough, .highlight]
    static let popoverStyles: [Command] = [.title, .heading, .subheading, .body, .monostyled]
    static let popoverLists: [Command] = [.bulletList, .dashedList, .numberedList]
    static let popoverTail: [Command] = [.blockQuote]

    /// Which style row is checked for the caret's line.
    static func checkedStyle(_ style: BodyFormat.LineStyle, inFence: Bool) -> Command {
        if inFence { return .monostyled }
        switch style {
        case .title: return .title
        case .heading: return .heading
        case .subheading: return .subheading
        default: return .body
        }
    }

    /// The right-click menu's leading Format block (mock `#m-select`).
    enum ContextEntry: Equatable {
        case header
        case command(Command)
        /// D184 + D196: "New person…", the LAST entry of the block, after the formatting items.
        case newPerson(String)
    }

    static func contextBlock(newPerson: String?) -> [ContextEntry] {
        var out: [ContextEntry] = [.header]
        out += [Command.bold, .italic, .underline, .strikethrough].map { .command($0) }
        if let newPerson { out.append(.newPerson(newPerson)) }
        return out
    }
}

/// D196: "Include audio in export" left the header; it is a choice in the confirmation Export
/// opens, and the choice is remembered per note (`Memo.includeAudioInExport`, mirrored by the row).
enum MacExportConfirm {
    static let title = "Export this note?"
    static let body = "It is written to your vault as Markdown."
    static let includeAudioLabel = "Include audio in export"
    static let confirmVerb = "Export"

    /// Only a note with audio has the choice to make; any other note exports on click.
    static func asksAboutAudio(hasAudio: Bool) -> Bool { hasAudio }

    /// Write the confirmed choice to the note. True = it changed (push it to the phone).
    @discardableResult
    static func apply(includeAudio: Bool, to stored: inout Bool) -> Bool {
        guard stored != includeAudio else { return false }
        stored = includeAudio
        return true
    }
}
