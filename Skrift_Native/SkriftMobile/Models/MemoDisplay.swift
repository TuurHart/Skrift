import Foundation

/// Display helpers shared by the memos list + memo detail. Kept off the `@Model`
/// so they don't touch SwiftData storage.
extension Memo {
    /// What to show as the heading: the phone-set title, else the transcript's
    /// first line (markers stripped), else a generic fallback.
    var displayTitle: String {
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        if let line = firstTranscriptLine { return line }
        return "Voice memo"
    }

    /// First non-empty line of the transcript with `[[img_NNN]]` markers removed.
    var firstTranscriptLine: String? {
        guard let transcript else { return nil }
        let cleaned = transcript.replacingOccurrences(
            of: #"\[\[img_\d+\]\]"#, with: "", options: .regularExpression
        )
        let line = cleaned
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })
        guard let line, !line.isEmpty else { return nil }
        return String(line.prefix(80))
    }

    var durationLabel: String {
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Whole days until the startup purge permanently removes this trashed memo
    /// (ceiling — a memo deleted an hour ago shows the full 14). 0 = expires on
    /// the next purge. Nil when the memo isn't in the trash. `now` injectable
    /// for tests.
    func trashDaysRemaining(now: Date = Date()) -> Int? {
        guard let deletedAt else { return nil }
        let remaining = TrashPolicy.retention - now.timeIntervalSince(deletedAt)
        return max(0, Int(ceil(remaining / 86_400)))
    }

    /// Countdown caption for Recently Deleted rows: "13 days left" / "1 day left"
    /// / "Deleting soon" (already past retention, gone at next launch).
    func trashCountdownLabel(now: Date = Date()) -> String? {
        guard let days = trashDaysRemaining(now: now) else { return nil }
        if days <= 0 { return "Deleting soon" }
        return days == 1 ? "1 day left" : "\(days) days left"
    }

    /// Honest status for the list pill, or `nil` when no pill should show.
    ///
    /// Transcript states (`transcribing` / `error`) are always informational and
    /// show regardless of sync eligibility. The *sync* states only apply once the
    /// memo is flagged to send: `significance == 0` is phone-only (SyncCoordinator
    /// never uploads it), so it shows NO sync pill — a "Waiting" pill there would
    /// lie, since it never syncs. `significance > 0` keeps Waiting / Synced.
    var statusKind: MemoStatusKind? {
        if transcriptStatus == .transcribing { return .transcribing }
        if transcriptStatus == .failed { return .error }
        guard significance > 0 else { return nil }
        return syncStatus == .synced ? .synced : .waiting
    }
}

// MARK: - Audiobook captures

/// Display helpers for audiobook quote-capture memos. Detection rides the C2
/// contract: `MemoMetadata.bookTitle` (set by the capture flow, defined in
/// `Models/MemoMetadata.swift`) marks a memo as a book capture. The transcript
/// shape is the C1 contract: markdown blockquote lines ("> ") holding the quote
/// at the TOP, a blank line, then the ramble.
extension Memo {
    /// True when this memo is an audiobook quote capture (C2 book metadata
    /// present). Drives the book glyph + quote-styled row in the memos list.
    var isBookCapture: Bool {
        !(metadata?.bookTitle?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
    }

    /// "Book · ch. N" caption for capture rows. A purely numeric chapter gets
    /// the "ch. " prefix (matching the export attribution); anything else (e.g.
    /// an m4b chapter *name*) is shown as-is. Nil for non-capture memos.
    var bookCaptionLabel: String? {
        guard let book = metadata?.bookTitle?.trimmingCharacters(in: .whitespaces),
              !book.isEmpty else { return nil }
        guard let chapter = metadata?.bookChapter?.trimmingCharacters(in: .whitespaces),
              !chapter.isEmpty else { return book }
        let label = chapter.allSatisfy(\.isNumber) ? "ch. \(chapter)" : chapter
        return "\(book) · \(label)"
    }

    /// The C1 quote block — the transcript's leading "> " blockquote lines,
    /// stripped of the markers and joined into one row-sized snippet. Nil when
    /// the transcript doesn't open with a blockquote (or doesn't exist yet).
    var quoteSnippet: String? {
        guard let transcript else { return nil }
        var lines: [String] = []
        for raw in transcript.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(">") {
                let text = line.dropFirst().trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { lines.append(text) }
            } else if lines.isEmpty && line.isEmpty {
                continue            // tolerate leading blank lines
            } else {
                break               // the quote block is the TOP — stop at the first non-quote line
            }
        }
        guard !lines.isEmpty else { return nil }
        return String(lines.joined(separator: " ").prefix(120))
    }

    /// First line of the ramble below the C1 quote block (markers stripped) —
    /// the capture row's secondary text. Nil while the capture has no ramble
    /// yet ("Save & keep listening" without recording thoughts).
    var rambleSnippet: String? {
        guard let transcript else { return nil }
        let cleaned = transcript.replacingOccurrences(
            of: #"\[\[img_\d+\]\]"#, with: "", options: .regularExpression
        )
        // Quote lines only legally appear at the top (C1), so skipping every
        // "> " line is equivalent to skipping the head block — and simpler.
        for raw in cleaned.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(">") { continue }
            return String(line.prefix(80))
        }
        return nil
    }
}

enum MemoStatusKind: Equatable {
    case synced, waiting, transcribing, error

    var pillStyle: PillStyle {
        switch self {
        case .synced: return .synced
        case .waiting: return .waiting
        case .transcribing: return .working
        case .error: return .error
        }
    }

    var label: String {
        switch self {
        case .synced: return "Synced"
        case .waiting: return "Waiting"
        case .transcribing: return "Transcribing"
        case .error: return "Error"
        }
    }
}

/// Relative date labels matching the mockups ("Today · 09:41", "Yesterday · 21:12",
/// "Mon · 14:03").
enum MemoDate {
    static func label(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let time = timeFormatter.string(from: date)
        if cal.isDateInToday(date) { return "Today · \(time)" }
        if cal.isDateInYesterday(date) { return "Yesterday · \(time)" }
        return "\(weekdayFormatter.string(from: date)) · \(time)"
    }

    /// Day-group header key for the list ("Today" / "Yesterday" / "Mon 3 Jun").
    static func group(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return groupFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()
    private static let groupFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f
    }()
}

/// Map a captured `DayPeriod` to an SF Symbol for the context chips.
extension DayPeriod {
    var symbol: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
    }
    var label: String { rawValue.capitalized }
}
