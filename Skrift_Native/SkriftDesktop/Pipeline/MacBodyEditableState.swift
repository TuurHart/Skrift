import Foundation

/// The Mac note body's mode — the phone's `NoteBody.mode` (Q183) on the Mac's step columns
/// (Q124, C173). Playback wins; a transcription in flight (or a Split speakers run, which
/// rewrites the whole body when it lands) makes the body read-only so an open draft can never
/// clobber the landing text; otherwise always editable. Pure, so `MacBodyEditableStateTests`
/// pins the precedence without the AppKit text view.
enum MacBodyEditableState: Equatable {
    case editing, playing, reading

    static func of(isPlaying: Bool, transcribe: StepStatus, splitting: Bool = false) -> MacBodyEditableState {
        if isPlaying { return .playing }
        if transcribe == .processing || splitting { return .reading }
        return .editing
    }

    var isEditable: Bool { self == .editing }

    /// The pill that says why the text is read-only — the phone's "Transcribing" StatusPill.
    /// nil unless a transcription is running (a split has its own band).
    static func pillLabel(transcribe: StepStatus) -> String? {
        transcribe == .processing ? "Transcribing" : nil
    }
}
