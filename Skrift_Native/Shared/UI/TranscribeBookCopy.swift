import Foundation

/// ONE copy set for "transcribe this book" (Q187, row books-75). TranscribeBookView,
/// BookTextSheet and ReadAlongView each carried their own wording for the same job
/// (four start labels, two battery sentences). All three read these.
enum TranscribeBookCopy {
    static let start = "Start transcribing"
    static let resume = "Resume transcribing"

    /// Start or resume, by whether any progress is saved.
    static func startLabel(hasProgress: Bool) -> String { hasProgress ? resume : start }

    /// The power policy, said once: runs on battery, pauses below 20%.
    static let runsOnBattery =
        "Runs on battery, pauses below 20% — best overnight on a charger for a full book."

    static let pausedLowBattery = "Paused — the battery is below 20%. Resumes when you plug in."
}
