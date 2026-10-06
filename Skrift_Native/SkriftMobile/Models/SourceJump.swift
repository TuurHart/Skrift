import Foundation

/// Q297 / D177: the note page's jump-back for EVERY note that remembers where in its source it
/// came from, not only audiobook quotes. Two kinds of source position exist:
/// - audio: a library item + seconds (`MemoMetadata.bookID` + `bookPosition`). A podcast episode
///   is a library audio item, so a podcast clip takes the book's exact path (`BookNotesJoin.jump`,
///   Q273: the item's own resume place is never moved).
/// - a PDF capture's own file + a 1-based page (`MemoMetadata.sourcePage`).
/// Pure resolving + one `perform`; the button and the PDF viewer are views.
enum SourceJump {

    enum Target: Equatable {
        case audio(BookNotesJoin.JumpTarget)
        case pdf(page: Int)
    }

    enum Outcome: Equatable {
        /// The player is open on the position; the caller presents it.
        case openedPlayer
        /// The audio is not on this device (never imported here, freed, still downloading).
        case audioUnavailable
        /// Show the note's own PDF at this 1-based page.
        case openPDF(URL, page: Int)
        /// The note carries a page but no file on this device.
        case pdfUnavailable
    }

    /// nil when the note has no stored source position. Audio wins when both exist (a book quote).
    static func target(for memo: Memo) -> Target? {
        if let audio = BookNotesJoin.jumpTarget(for: memo) { return .audio(audio) }
        guard let page = memo.metadata?.sourcePage, page >= 1,
              let shared = memo.sharedContent, shared.type == .file, isPDF(shared) else { return nil }
        return .pdf(page: page)
    }

    /// "Back to it at 1:12:05 in Library" (audio, the book wording) / "Back to it on page 12".
    static func label(for target: Target) -> String {
        switch target {
        case .audio(let t): return BookNotesJoin.jumpLabel(position: t.position)
        case .pdf(let page): return "Back to it on page \(page)"
        }
    }

    @MainActor
    static func perform(_ target: Target, for memo: Memo,
                        store: AudiobookLibraryStore = .shared,
                        session: AudiobookSession = .shared) -> Outcome {
        switch target {
        case .audio(let t):
            return BookNotesJoin.jump(to: t, store: store, session: session) ? .openedPlayer : .audioUnavailable
        case .pdf(let page):
            guard let url = memo.sharedFileURL else { return .pdfUnavailable }
            return .openPDF(url, page: page)
        }
    }

    /// PDFKit page index for a 1-based page, held inside the document (0 when it has no pages).
    static func clampedPageIndex(page: Int, pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        return min(max(page, 1), pageCount) - 1
    }

    private static func isPDF(_ shared: SharedContent) -> Bool {
        let name = (shared.fileName ?? shared.filePath ?? "") as NSString
        return name.pathExtension.lowercased() == "pdf" || shared.mimeType == "application/pdf"
    }
}
