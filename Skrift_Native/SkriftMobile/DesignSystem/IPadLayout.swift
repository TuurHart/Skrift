import SwiftUI

/// Q379: the iPad layout of the universal phone target, per the signed mock
/// `SkriftDesktop/mocks/Q378-ipad-apple.html` with D198's picks: tabs option A (a slim glass
/// control at the top of the list column, no system tab bar), the note text the FULL pane width
/// (48 pt margins beside the list, 89 pt alone), Apple's in-note attach menu minus Record Audio,
/// and the Mac's full Aa list (D197). Layout branches on the horizontal size class, never the
/// device idiom: an iPad in Split View is compact and keeps the phone layout.
enum IPadLayout {
    enum Mode: Equatable { case split, stack }

    static func mode(_ size: UserInterfaceSizeClass?) -> Mode { size == .regular ? .split : .stack }
    static func showsSystemTabBar(_ size: UserInterfaceSizeClass?) -> Bool { mode(size) == .stack }

    // MARK: geometry (mock points)

    /// The list column (the phone canvas).
    static let listColumnWidth: CGFloat = 375
    /// The tab row, the list header and the note toolbar are each one 60 pt line.
    static let rowHeight: CGFloat = 60
    /// Glass controls: the ◧, the tab capsule, Select, the toolbar group.
    static let glassHeight: CGFloat = 44
    /// ◧ from the leading edge; the tab capsule starts after it and ends 9 pt short of the divider.
    static let toggleLeading: CGFloat = 9
    static let tabRowLeading: CGFloat = 63
    static let tabRowTrailing: CGFloat = 9

    /// Apple's note margins: beside the list, and with the list hidden.
    static func noteMargin(listVisible: Bool) -> CGFloat { listVisible ? 48 : 89 }
    static func textWidth(paneWidth: CGFloat, listVisible: Bool) -> CGFloat {
        max(80, paneWidth - 2 * noteMargin(listVisible: listVisible))
    }

    // MARK: tabs (option A)

    static let tabs: [AppTabView.Tab] = [.notes, .books, .journal, .settings]
    static func tabTitle(_ tab: AppTabView.Tab) -> String {
        switch tab {
        case .notes: return SharedCopy.notesTitle
        case .books: return "Library"
        case .journal: return SharedCopy.reviewTitle
        case .settings: return "Settings"
        }
    }

    // MARK: Apple's attach menu (D198)

    static let attachHeader = "Add to this note"
    /// Apple's in-note attach menu minus Record Audio (Skrift records its own way).
    enum AttachItem: CaseIterable {
        case scanDocument, takePhoto, choosePhoto, attachFile
        var title: String {
            switch self {
            case .scanDocument: return "Scan Document"
            case .takePhoto: return "Take Photo or Video"
            case .choosePhoto: return "Choose Photo or Video"
            case .attachFile: return "Attach File"
            }
        }
        var symbol: String {
            switch self {
            case .scanDocument: return "doc.viewfinder"
            case .takePhoto: return "camera"
            case .choosePhoto: return "photo.on.rectangle"
            case .attachFile: return "paperclip"
            }
        }
        var id: String {
            switch self {
            case .scanDocument: return "attach-scan"
            case .takePhoto: return "attach-camera"
            case .choosePhoto: return "attach-photos"
            case .attachFile: return "attach-file"
            }
        }
    }
}

extension View {
    /// The mock's glass control (`.gl`): a near-white capsule or circle with a hairline ring and a
    /// soft shadow, accent-soft while its state is on.
    func ipadGlass<S: InsettableShape>(on: Bool = false, in shape: S) -> some View {
        background(on ? Color.skAccentSoft : Color.skSurface.opacity(0.86), in: shape)
            .overlay(shape.strokeBorder(on ? Color.clear : Color.skBorder, lineWidth: 0.5))
            .shadow(color: .black.opacity(on ? 0 : 0.06), radius: 5, y: 2)
    }
}

/// The open note's text width at regular width, measured by the workbench, so inline photos
/// size to the full pane instead of the old 640 pt column.
private struct IPadPaneWidthKey: EnvironmentKey { static let defaultValue: CGFloat? = nil }
extension EnvironmentValues {
    var ipadPaneWidth: CGFloat? {
        get { self[IPadPaneWidthKey.self] }
        set { self[IPadPaneWidthKey.self] = newValue }
    }
}

/// The iPad Aa popover = the Mac's full list (D197): B I U S + highlight; Title, Heading,
/// Subheading, Body, Monostyled; Bulleted, Dashed, Numbered; Block Quote. Captions are the
/// Markdown the shared `BodyFormat` rule writes.
enum IPadFormatMenu {
    enum Action: Equatable { case line(BodyFormat.LineStyle), monostyled }
    struct Row: Equatable {
        let label: String
        let hint: String
        let action: Action
        let size: CGFloat
        let weight: Font.Weight
        var id: String { "ipad-format-\(label)" }
    }

    static let marks: [BodyFormat.InlineMark] = [.bold, .italic, .underline, .strike, .highlight]

    static let styles: [Row] = [
        Row(label: "Title", hint: "# ", action: .line(.title), size: 22, weight: .bold),
        Row(label: "Heading", hint: "## ", action: .line(.heading), size: 18, weight: .bold),
        Row(label: "Subheading", hint: "### ", action: .line(.subheading), size: 16, weight: .semibold),
        Row(label: "Body", hint: "plain", action: .line(.body), size: 15, weight: .regular),
        Row(label: "Monostyled", hint: "`code`", action: .monostyled, size: 14, weight: .regular),
    ]

    static let lists: [Row] = [
        Row(label: "Bulleted", hint: "- ", action: .line(.bullet), size: 14, weight: .regular),
        Row(label: "Dashed", hint: "* ", action: .line(.dashed), size: 14, weight: .regular),
        Row(label: "Numbered", hint: "1. ", action: .line(.numbered), size: 14, weight: .regular),
    ]

    static let quote = Row(label: "Block Quote", hint: "> ", action: .line(.quote), size: 14, weight: .regular)

    static func markLabel(_ mark: BodyFormat.InlineMark) -> String {
        switch mark {
        case .bold: return "B"
        case .italic: return "I"
        case .underline: return "U"
        case .strike: return "S"
        case .highlight: return "Highlight"
        case .code: return "Code"
        }
    }
    static func markHint(_ mark: BodyFormat.InlineMark) -> String { mark.open + "…" + mark.close }
}
