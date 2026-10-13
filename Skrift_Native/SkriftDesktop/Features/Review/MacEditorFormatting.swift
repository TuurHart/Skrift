import Foundation

/// Q360 (D115, signed mock `Q350-note-editor-apple.html`, D196, Tuur 2026-10-13 "Apple's full
/// list"): the Mac editor's formatting commands, written ONCE for the three places that show
/// them: the Format menu (shortcuts), the band's Aa popover, and the Format block at the top of
/// the body's right-click menu. The edits themselves are the shared `BodyFormat` (stored
/// Markdown, C116; marks stay visible but dim, C24).
///
/// Foundation only, so the host-less unit bundle compiles it (`MacEditorFormattingTests`).
enum MacEditorFormatting {
    /// The command set lives in Shared (`FormatCommand`, Q379): the iPad's Aa reads the same list.
    typealias Command = FormatCommand

    /// The Aa popover, Apple Notes' order (Tuur 2026-10-13): B I U S | highlight; the styles
    /// (Body checked when current); the lists; a divider; Block Quote.
    static let popoverMarks: [Command] = FormatCommand.aaMarks
    static let popoverStyles: [Command] = FormatCommand.aaStyles
    static let popoverLists: [Command] = FormatCommand.aaLists
    static let popoverTail: [Command] = FormatCommand.aaTail

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
