import Foundation

/// D127 / C229: the join between a book and the capture notes made from it. The key was
/// written since 2026-07-06 (`MemoMetadata.bookID` + the GLOBAL `bookPosition`, set by
/// `MemoSaver.saveQuoteCapture`) and nothing read it; this is the reader. Pure — the
/// Books shelf counts and lists with it, and the note page's jump-back resolves with it.
///
/// Counts only live notes (a trashed capture is not "a note from this book") and one row
/// per memo id (`MemoDuplicates.canonicalRows`, the rule every display reader uses).
enum BookNotesJoin {

    /// Live capture notes of `bookID`, newest first.
    static func notes(forBook bookID: UUID, in memos: [Memo]) -> [Memo] {
        MemoDuplicates.canonicalRows(memos)
            .filter { $0.deletedAt == nil && $0.metadata?.bookID == bookID }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    /// Notes per book, for the shelf badges — one pass over the memos, not one per tile.
    static func counts(in memos: [Memo]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for memo in MemoDuplicates.canonicalRows(memos) where memo.deletedAt == nil {
            if let id = memo.metadata?.bookID { counts[id, default: 0] += 1 }
        }
        return counts
    }

    /// Where a capture note points back to: the book and the GLOBAL audio position.
    struct JumpTarget: Equatable {
        let bookID: UUID
        let position: TimeInterval
    }

    /// nil for a memo that wasn't captured from a book, or whose position was never stored.
    static func jumpTarget(for memo: Memo) -> JumpTarget? {
        guard let meta = memo.metadata, let bookID = meta.bookID,
              let position = meta.bookPosition, position.isFinite, position >= 0 else { return nil }
        return JumpTarget(bookID: bookID, position: position)
    }

    /// The mock's jump-back label: "Back to it at 1:12:05 in Library".
    static func jumpLabel(position: TimeInterval) -> String {
        "Back to it at \(AudiobookTime.clock(position)) in Library"
    }

    /// Q273: whether a playback session writes its position to the book's resume place. A
    /// jump-back session does not (Q6 mock: "The book's own place is not moved").
    static func shouldPersistProgress(jumpBackSession: Bool) -> Bool { !jumpBackSession }

    /// The Q6 mock's jump-back toast.
    static func jumpToast(bookTitle: String, position: TimeInterval) -> String {
        "Opens \(bookTitle) at \(AudiobookTime.clock(position)). The book’s own place is not moved."
    }

    /// The pill's count text and its VoiceOver label ("5 notes from this").
    static func accessibilityLabel(count: Int) -> String {
        "\(count) note\(count == 1 ? "" : "s") from this book"
    }

    /// One row of the notes sheet: "ch 7 · 1:12:05 · Mon 21 Sep" (chapter and time omitted
    /// when the metadata doesn't carry them).
    static func metaLine(for memo: Memo, calendar: Calendar = .current) -> String {
        var parts: [String] = []
        if let chapter = memo.metadata?.bookChapter?.trimmingCharacters(in: .whitespaces), !chapter.isEmpty {
            parts.append(chapter.allSatisfy(\.isNumber) ? "ch \(chapter)" : chapter)
        }
        if let target = jumpTarget(for: memo) { parts.append(AudiobookTime.clock(target.position)) }
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE d MMM"
        parts.append(f.string(from: memo.recordedAt))
        return parts.joined(separator: " · ")
    }

    /// What the jump-back does with a book that may or may not be loadable: open it and seek.
    /// Returns false when the audio isn't on this device (freed / still downloading) — the
    /// caller says so instead of showing a dead player.
    @MainActor
    @discardableResult
    static func jump(to target: JumpTarget,
                     store: AudiobookLibraryStore = .shared,
                     session: AudiobookSession = .shared) -> Bool {
        guard let book = store.book(id: target.bookID) else { return false }
        guard session.open(book, autoplay: false) else { return false }
        session.beginJumpBack(to: target.position)   // Q273: the book's own place is not moved
        return true
    }
}
