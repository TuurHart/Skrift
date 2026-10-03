import Foundation

/// The short-note summary rule (Q172, setexp-36): a note under this many words gets no
/// Gemma summary (user 2026-06-15). ONE constant and ONE word count for the Mac's
/// `BatchRunner` (via `AppSettings.effectiveSummaryMinWords`, which may override the
/// default) and the iPad's `PolishEscrow`. A manual "Redo summary" ignores it.
enum SummaryRule {
    static let defaultMinWords = 75

    /// Whitespace-separated word count, as both apps counted it.
    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    static func meetsThreshold(_ text: String, minWords: Int = defaultMinWords) -> Bool {
        wordCount(text) >= minWords
    }
}
