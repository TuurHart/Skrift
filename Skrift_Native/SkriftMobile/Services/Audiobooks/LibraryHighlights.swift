import Foundation

/// Q404 (D207): highlights on a Library source, stored inside its synced record (`Audiobook.highlights`).
/// Adding or removing one moves `modifiedAt`, the carrier's LWW key, so it reaches his other devices.
/// Q474: the receiving device merges the list per highlight (`SourceHighlights.merged`), so a
/// removal leaves a tombstone in `Audiobook.highlightRemovals` and a comment edit a stamp.
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
        // Q463: a spoken comment's audio goes with its highlight (he confirmed the removal first).
        if let audio = list.first(where: { $0.id == id })?.commentAudio {
            try? FileManager.default.removeItem(at: commentAudioURL(audio, bookID: bookID, store: store))
        }
        book.highlights = after.isEmpty ? nil : after
        // Q474 (C267): the tombstone, so a sync merge with another device's older copy keeps it removed.
        book.highlightRemovals = (book.highlightRemovals ?? [:]).merging([id.uuidString: now]) { max($0, $1) }
        book.modifiedAt = max(now, book.modifiedAt.addingTimeInterval(0.001))
        store.update(book)
    }

    static func highlight(_ id: UUID, bookID: UUID, store: AudiobookLibraryStore) -> SourceHighlight? {
        list(bookID, store: store).first { $0.id == id }
    }

    /// Q463 (D214): save the comment on a highlight: typed text, or a spoken comment's transcript
    /// plus its audio file name. A blank text with no audio deletes the comment (and the old audio).
    static func setComment(_ comment: String?, audio: String?, on id: UUID, bookID: UUID,
                           store: AudiobookLibraryStore, now: Date = Date()) {
        guard var book = store.book(id: bookID), let list = book.highlights,
              let old = list.first(where: { $0.id == id }) else { return }
        if let was = old.commentAudio, was != audio {
            try? FileManager.default.removeItem(at: commentAudioURL(was, bookID: bookID, store: store))
        }
        let after = SourceHighlights.commenting(id, comment: comment, audio: audio, in: list, now: now)
        guard after != list else { return }
        book.highlights = after
        book.modifiedAt = max(now, book.modifiedAt.addingTimeInterval(0.001))
        store.update(book)
    }

    /// Q463 (D214 corrected): leaving the PDF reader writes his highlights and comments into the
    /// Library PDF itself (off the main thread; a no-op when nothing changed since the last write).
    /// Returns whether the file was rewritten.
    @discardableResult
    static func writeIntoPDF(bookID: UUID, store: AudiobookLibraryStore) async -> Bool {
        guard let book = store.book(id: bookID), book.kind == .pdf else { return false }
        let file = store.audioURL(of: book, fileIndex: 0)
        let list = book.highlights?.filter { $0.page != nil } ?? []
        return await Task.detached(priority: .utility) {
            do { return try PDFAnnotationExport.writeBack(file: file, highlights: list) } catch {
                DevLog.log("PDF annotation write failed: \(error)")
                return false
            }
        }.value
    }

    /// Q473 (D214): a sync changed this PDF's highlight list, or just downloaded the file. Rebuild
    /// the Library PDF here from the hidden original plus the synced list (off the main thread;
    /// a no-op when nothing changed). Spoken-comment audio stays on the device that recorded it:
    /// only its words ride the list. Returns whether the file was rewritten.
    @discardableResult
    static func rebuildPDFFromSync(bookID: UUID, store: AudiobookLibraryStore, fileIsFresh: Bool) async -> Bool {
        guard let book = store.book(id: bookID), book.kind == .pdf else { return false }
        let file = store.audioURL(of: book, fileIndex: 0)
        let list = book.highlights?.filter { $0.page != nil } ?? []
        return await Task.detached(priority: .utility) {
            do {
                return try PDFAnnotationExport.rebuildFromSync(file: file, highlights: list, fileIsFresh: fileIsFresh)
            } catch {
                DevLog.log("PDF annotation rebuild failed: \(error)")
                return false
            }
        }.value
    }

    /// Where a spoken comment's audio lives: `comments/` inside the Library item's folder.
    static func commentAudioURL(_ name: String, bookID: UUID, store: AudiobookLibraryStore) -> URL {
        store.folder(for: bookID).appendingPathComponent("comments", isDirectory: true)
            .appendingPathComponent(name)
    }

    /// Moves a finished recording into the item's `comments/` folder; returns its file name.
    static func adoptCommentAudio(_ recording: URL, highlightID: UUID, bookID: UUID,
                                  store: AudiobookLibraryStore) -> String? {
        let ext = recording.pathExtension.isEmpty ? "m4a" : recording.pathExtension
        let name = "\(highlightID.uuidString)-\(Int(Date().timeIntervalSince1970)).\(ext)"
        let dest = commentAudioURL(name, bookID: bookID, store: store)
        do {
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: recording, to: dest)
            return name
        } catch {
            return nil
        }
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

    /// Q463 (Q462 mock, step 1): a PDF highlight's menu, Copy · Comment · Remove highlight ("Edit
    /// comment" once it has one). An article's highlight keeps `highlightItems`.
    static let comment = "Comment"
    static let editComment = "Edit comment"

    static func pdfHighlightItems(hasComment: Bool) -> [String] {
        [copy, hasComment ? editComment : comment, removeHighlight]
    }

    /// The ⋯ menu's share row and the question it asks every time (D214).
    static let sharePDF = "Share PDF"
    static let shareAsk = "Share this PDF"
    static let shareWithHighlights = "With my highlights and comments"
    static let shareClean = "Clean PDF, as imported"
}
