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
