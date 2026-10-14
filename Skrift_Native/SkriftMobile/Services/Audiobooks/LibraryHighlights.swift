import Foundation

/// Q404 (D207): highlights on a Library source, stored inside its synced record (`Audiobook.highlights`).
/// Adding or removing one moves `modifiedAt`, the carrier's LWW key, so it reaches his other devices.
@MainActor
enum LibraryHighlights {
    static func list(_ bookID: UUID, store: AudiobookLibraryStore) -> [SourceHighlight] {
        store.book(id: bookID)?.highlights ?? []
    }

    /// The new highlight's id; nil for a blank selection or a range already highlighted.
    @discardableResult
    static func add(_ text: String, page: Int?, word: Int, bookID: UUID, store: AudiobookLibraryStore,
                    now: Date = Date()) -> UUID? {
        guard var book = store.book(id: bookID) else { return nil }
        let before = book.highlights ?? []
        let after = SourceHighlights.adding(text, page: page, word: word, to: before, now: now)
        guard after.count > before.count, let added = after.last else { return nil }
        book.highlights = after
        book.modifiedAt = max(now, book.modifiedAt.addingTimeInterval(0.001))
        store.update(book)
        return added.id
    }

    static func remove(_ id: UUID, bookID: UUID, store: AudiobookLibraryStore, now: Date = Date()) {
        guard var book = store.book(id: bookID), let list = book.highlights,
              list.contains(where: { $0.id == id }) else { return }
        let after = SourceHighlights.removing(id, from: list)
        book.highlights = after.isEmpty ? nil : after
        book.modifiedAt = max(now, book.modifiedAt.addingTimeInterval(0.001))
        store.update(book)
    }

    /// Q355 kept article highlights in a local `highlights.json` (plain strings, never synced).
    /// Fold them into the record once, then drop the file.
    static func adoptLegacyFile(bookID: UUID, doc: ArticleDoc?, store: AudiobookLibraryStore) {
        let url = store.folder(for: bookID).appendingPathComponent("highlights.json")
        guard let data = try? Data(contentsOf: url),
              let texts = try? JSONDecoder().decode([String].self, from: data) else { return }
        for t in texts { add(t, page: nil, word: doc?.wordOffset(of: t) ?? 0, bookID: bookID, store: store) }
        try? FileManager.default.removeItem(at: url)
    }
}

/// Q404: the selection menu both readers show (the Q6 + Q351 mocks' callout), and the menu a tap
/// on a highlight opens. One list, so the PDF page, the PDF reading view and the article agree.
enum SourceMenu {
    static let copy = "Copy"
    static let highlight = "Highlight"
    static let removeHighlight = "Remove highlight"
    static let addNote = "\u{275D} Add note"

    static func selectionItems(insideHighlight: Bool) -> [String] {
        [copy, insideHighlight ? removeHighlight : highlight, addNote]
    }

    static let highlightItems = [copy, removeHighlight]
}
