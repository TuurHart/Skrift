import SwiftUI

/// Q352 (Q6 mock, D90/D128/D134/D135): what a Library source is. Stored on `Audiobook.kind`
/// (inside the existing synced carrier blob; nil = book).
enum LibrarySourceKind: String, Codable, CaseIterable, Sendable {
    case book, episode, pdf, article
}

/// One door of the empty Library tab. All four are listed in `all`; `visible` is the subset whose
/// importer exists. A door with nothing behind it is hidden, never shown dead (Q352): flip
/// `isBuilt` when Q354 (ePub or PDF) and Q355 (article) land their importers.
enum LibraryDoor: String, CaseIterable, Identifiable, Sendable {
    case audiobook, podcast, epubOrPDF, article

    var id: String { rawValue }

    var title: String {
        switch self {
        case .audiobook: "Audiobook"
        case .podcast: "Podcast or episode"
        case .epubOrPDF: "ePub or PDF"
        case .article: "Article"
        }
    }

    var detail: String {
        switch self {
        case .audiobook: "From Files. Pick every part of a multi-file book at once."
        case .podcast: "Paste a show or episode link."
        case .epubOrPDF: "From Files."
        case .article: "Paste a link. Opens in reader view."
        }
    }

    /// The kind of source this door creates.
    var kind: LibrarySourceKind {
        switch self {
        case .audiobook: .book
        case .podcast: .episode
        case .epubOrPDF: .pdf
        case .article: .article
        }
    }

    /// True once the door's importer exists.
    var isBuilt: Bool {
        switch self {
        case .audiobook, .podcast: true
        case .epubOrPDF, .article: false
        }
    }

    static var all: [LibraryDoor] { allCases }
    static var visible: [LibraryDoor] { allCases.filter(\.isBuilt) }

    static let heading = "Add your first book, podcast, article or PDF"
    static let lede = "Things you come back to live here, with your place saved. Add a note from any of them and it lands in Notes, linked back."
    static let staysInNotes = "Voice memos, photos, screenshots and messages from people stay in Notes."
}

/// The empty Library tab (Q6 mock `emptyScreen`): heading, one line, the doors in one card, and
/// what stays in Notes.
struct LibraryEmptyView: View {
    var doors: [LibraryDoor] = LibraryDoor.visible
    let onDoor: (LibraryDoor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(LibraryDoor.heading)
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.2)
                .foregroundStyle(Color.skText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(LibraryDoor.lede)
                .font(.system(size: 13.5))
                .foregroundStyle(Color.skTextDim)
                .fixedSize(horizontal: false, vertical: true)
            if !doors.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(doors.enumerated()), id: \.element.id) { index, door in
                        if index > 0 {
                            Rectangle().fill(Color.skBorder).frame(height: 0.5)
                        }
                        Button { onDoor(door) } label: { row(door) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("library-door-\(door.rawValue)")
                    }
                }
                .background(Color.skSurface, in: .rect(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle.sk(14).stroke(Color.skBorder, lineWidth: 0.5))
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
            }
            Text(LibraryDoor.staysInNotes)
                .font(.system(size: 12))
                .foregroundStyle(Color.skTextFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("library-empty")
    }

    private func row(_ door: LibraryDoor) -> some View {
        HStack(spacing: 12) {
            LibraryDoorIcon(kind: door.kind)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 0) {
                Text(door.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.skText)
                Text(door.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.skTextDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.skTextFaint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }
}

/// The 40pt cover swatch beside a door: the mock's gradients per kind, no text.
private struct LibraryDoorIcon: View {
    let kind: LibrarySourceKind

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(fill)
            .overlay(alignment: .topLeading) { marks }
            .accessibilityHidden(true)
    }

    private var fill: LinearGradient {
        switch kind {
        case .book:
            LinearGradient(colors: [Color(red: 0.31, green: 0.48, blue: 0.37), Color(red: 0.18, green: 0.29, blue: 0.23)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .episode:
            LinearGradient(colors: [Color(red: 0.25, green: 0.44, blue: 0.60), Color(red: 0.12, green: 0.23, blue: 0.34)],
                           startPoint: .topTrailing, endPoint: .bottomLeading)
        case .pdf:
            LinearGradient(colors: [Color(red: 0.91, green: 0.93, blue: 0.95)], startPoint: .top, endPoint: .bottom)
        case .article:
            LinearGradient(colors: [Color(red: 0.94, green: 0.91, blue: 0.84)], startPoint: .top, endPoint: .bottom)
        }
    }

    @ViewBuilder
    private var marks: some View {
        switch kind {
        case .pdf, .article:
            let ink = kind == .pdf ? Color(red: 0.23, green: 0.25, blue: 0.31) : Color(red: 0.16, green: 0.14, blue: 0.09)
            VStack(alignment: .leading, spacing: 4) {
                ForEach([26.0, 20.0, 24.0], id: \.self) { w in
                    RoundedRectangle(cornerRadius: 1).fill(ink.opacity(0.25)).frame(width: w, height: 2)
                }
            }
            .padding(6)
        case .book, .episode:
            EmptyView()
        }
    }
}
