import Foundation

/// Q356 (D90 / D138, Q6 mock screens "A capture note" and "A note with a PDF"): the two hatches
/// between Library and Notes, one action each.
/// - "Send to a note" (a source's ⋯ and long-press): the source STAYS on the shelf; a new note
///   holds a link card that jumps back to it.
/// - "Move to Library" (a note's ⋯, only on a note holding a PDF): the PDF moves to the shelf and
///   his words stay in Notes as a note linked to it.
/// The link is the same metadata a capture carries (`MemoMetadata.bookID` + `bookPosition`, a PDF's
/// page as "p. N" in `bookChapter`), so the ❝ N count, the notes sheet and the jump-back all read it.
enum LibraryHatch {

    // MARK: - Copy

    static let sendLabel = "Send to a note"
    static let moveLabel = "Move to Library"
    static let movedToast = "Moved to Library. Your words stay in Notes, linked to it."
    static func sentToast(title: String) -> String { "Sent to Notes. \(title) stays in Library." }

    /// The mock's `sub`: what kind of source it is, as one word.
    /// Q386: the words live on the shared `SourceKind` (every link kind has both).
    static func kindLabel(_ kind: LibrarySourceKind) -> String {
        kind.linkKind.sourceName ?? kind.linkKind.label
    }

    /// The noun in "N notes from this episode".
    static func kindNoun(_ kind: LibrarySourceKind) -> String {
        kind.linkKind.sourceNoun ?? kind.rawValue
    }

    /// Where he is in the source, as the mock writes it: "1:12:05", "p. 4 of 18".
    static func placeLine(for book: Audiobook) -> String {
        switch book.sourceKind {
        case .pdf: LibraryPDF.progressLine(book)
        case .article: LibraryArticle.progressLine(book)   // Q355: "31%", never a clock
        case .book, .episode: AudiobookTime.clock(book.position)
        }
    }

    /// The link card's second line (mock `sentNoteScreen` `.srccard .d`):
    /// "PDF · p. 4 of 18 · open in Library ›".
    static func cardDetail(for book: Audiobook) -> String {
        "\(kindLabel(book.sourceKind)) · \(placeLine(for: book)) · open in Library ›"
    }

    // MARK: - The notes row under the player and the reader (mock `srcNotesRow`)

    static func notesRowTitle(count: Int, kind: LibrarySourceKind) -> String {
        guard count > 0 else { return SharedCopy.emptyLibraryTitle }
        return "\(count) note\(count == 1 ? "" : "s") from this \(kindNoun(kind))"
    }

    static let notesRowEmptyDetail = "Add note saves a quote and your voice from here."

    static func notesRowDetail(newestTitle: String, when: String) -> String {
        "Newest: \(newestTitle) · \(when)"
    }

    /// "Mon 21 Sep", the mock's date on the row.
    static func shortDate(_ date: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE d MMM"
        return f.string(from: date)
    }

    // MARK: - The link

    /// The metadata that links a note to `book` at the place he is now.
    static func linkMetadata(for book: Audiobook) -> MemoMetadata {
        let author = book.author.trimmingCharacters(in: .whitespaces)
        let chapter: String?
        let position: Double
        if book.sourceKind == .pdf {
            let page = LibraryPDF.page(of: book)
            chapter = LibraryPDF.pageLabel(page)
            position = Double(page)
        } else {
            chapter = book.chapterIndex(at: book.position).map { String($0 + 1) }
            position = book.position
        }
        var meta = MemoMetadata(bookTitle: book.title,
                                bookAuthor: author.isEmpty ? nil : author,
                                bookChapter: chapter,
                                bookID: book.id,
                                bookPosition: position)
        // Q372: the source's kind, so the export can write an episode's `— *Show*, episode, mm:ss`.
        meta.bookKind = book.sourceKind.rawValue
        return meta
    }

    /// A note that links to a source without a captured quote: what "Send to a note" and
    /// "Move to Library" leave. The note page draws the link card for it. The ONE shared rule
    /// (`SourceKind.sourceLink`) the Mac row and both exporters use too (Q372).
    static func isSourceLink(_ memo: Memo) -> Bool {
        SourceKind.sourceLink(metadataData: memo.metadataData, body: memo.transcript) != nil
    }

    // MARK: - Send to a note

    /// A new note linked to `book`. The source stays on the shelf. Returns the note's id.
    @MainActor
    @discardableResult
    static func sendToNote(book: Audiobook, repository: NotesRepository = .shared, now: Date = Date()) -> UUID? {
        let id = UUID()
        repository.insert(Memo.make(
            id: id,
            recordedAt: now,
            syncStatus: .waiting,
            transcriptStatus: .done,
            metadata: linkMetadata(for: book)))
        return id
    }

    // MARK: - Move to Library

    /// True for a note that holds a PDF (the mock's caption also names ePubs, article links and
    /// hour-long audio; only the PDF importer exists, so only a PDF is offered).
    static func canMoveToLibrary(_ memo: Memo) -> Bool {
        guard memo.deletedAt == nil, let shared = memo.sharedContent, shared.type == .file,
              let url = memo.sharedFileURL else { return false }
        let name = shared.fileName ?? url.lastPathComponent
        let isPDF = (name as NSString).pathExtension.lowercased() == "pdf"
            || url.pathExtension.lowercased() == "pdf"
            || shared.mimeType == "application/pdf"
        return isPDF && FileManager.default.fileExists(atPath: url.path)
    }

    /// Move the note's PDF onto the shelf and keep his words as a note linked to it (page 1).
    /// nil when the file is missing or not a readable PDF; the note is then left untouched.
    @MainActor
    @discardableResult
    static func moveToLibrary(memo: Memo, store: AudiobookLibraryStore = .shared,
                              repository: NotesRepository = .shared, now: Date = Date()) -> Audiobook? {
        guard canMoveToLibrary(memo), let src = memo.sharedFileURL,
              let book = LibraryPDF.importPDF(from: src, displayName: memo.sharedContent?.fileName,
                                              store: store, now: now) else { return nil }
        // His words: a share capture keeps them in `annotationText`; a plain note in `transcript`.
        let words = [memo.transcript, memo.annotationText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        memo.transcript = words.isEmpty ? nil : words
        memo.annotationText = nil
        memo.sharedContent = nil
        var meta = memo.metadata ?? MemoMetadata()
        let link = linkMetadata(for: book)
        meta.bookTitle = link.bookTitle
        meta.bookAuthor = link.bookAuthor
        meta.bookChapter = link.bookChapter
        meta.bookID = link.bookID
        meta.bookPosition = link.bookPosition
        meta.bookKind = link.bookKind
        memo.metadata = meta
        memo.transcriptStatus = .done
        memo.markEdited(stampWords: false)
        repository.save()
        // D90: Move MOVES the PDF, so the note's synced `document` asset goes too, but only
        // once the Library copy is on disk (`importPDF` returned a book whose file exists).
        // A failed import returned nil above with the note and its asset untouched.
        if libraryCopyExists(book, store: store) {
            if repository.deleteAssets(forMemo: memo.id, kind: MemoAsset.Kind.document) > 0 {
                repository.save()
            }
            try? FileManager.default.removeItem(at: src)
        }
        return book
    }

    /// True when every file of the moved source is on disk in the Library.
    @MainActor
    static func libraryCopyExists(_ book: Audiobook, store: AudiobookLibraryStore) -> Bool {
        !book.files.isEmpty && book.files.allSatisfy {
            FileManager.default.fileExists(atPath: store.folder(for: book.id).appendingPathComponent($0).path)
        }
    }
}
