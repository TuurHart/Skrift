import Foundation

/// The Mac title chooser's two values (C181 / C25). "From recording" is the shared
/// first-transcript-line cut (`NoteTitle.recordingLine`), never the filename: a phone memo's
/// file is `memo_<uuid>.m4a` and picking it wrote 'memo_<uuid>' as the title and synced it.
enum MacTitleSuggestion {
    /// "" when the transcript has no text (the chooser then stays hidden).
    static func fromRecording(transcript: String?) -> String {
        NoteTitle.recordingLine(transcript: transcript) ?? ""
    }

    /// Shown only when both values exist and differ.
    static func showChooser(suggested: String, recording: String) -> Bool {
        !suggested.isEmpty && !recording.isEmpty && suggested != recording
    }
}
