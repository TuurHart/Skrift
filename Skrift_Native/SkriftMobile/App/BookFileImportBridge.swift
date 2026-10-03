import Foundation

/// What Open-in does with a file whose kind is `.book` (C199: an `.m4b` / `.epub` opened from
/// Files or another app lands in Books). Pure, so the decision is unit-tested without a UI.
enum BookOpenInRouting {
    enum Decision: Equatable {
        /// An audiobook file: goes to the Books library's own import (`AudiobookImporter`).
        case importAudiobook
        /// An ePub is the TEXT of an audiobook, never a book on its own: the user is taken to
        /// Books and told to add it from the book's "Book text…" sheet.
        case needsAudiobook
        /// A `.skriftbook` bundle (the share offer path) or anything that is not a book.
        case notAudiobookFile
    }

    static func decision(for url: URL) -> Decision {
        guard url.isFileURL, ImportKinds.kind(of: url) == .book else { return .notAudiobookFile }
        switch url.pathExtension.lowercased() {
        case "epub": return .needsAudiobook
        case "skriftbook": return .notAudiobookFile
        default: return .importAudiobook
        }
    }

    /// The reason said for an `.epub` that arrived with no audiobook to attach it to.
    static let epubReason = "An ePub is a book's text: open the audiobook in Books, then Book text… > Add"
}

/// Carries `.m4b` files opened from outside the app to the Books library, which runs the same
/// import its own Add button runs. Mirrors `MemoOpenBridge`: a monotonic counter plus a queue,
/// consumed on appear AND on change, so a cold-launch Open-in (the Books tab is built lazily)
/// is not missed.
@MainActor
final class BookFileImportBridge: ObservableObject {
    static let shared = BookFileImportBridge()
    @Published private(set) var requestID = 0
    private var queue: [URL] = []
    private init() {}

    func offer(_ url: URL) {
        queue.append(url)
        requestID += 1
    }

    /// Everything waiting, at most once.
    func consume() -> [URL] {
        defer { queue = [] }
        return queue
    }
}
