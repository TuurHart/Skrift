import Foundation

/// What the live-recording screen says about the transcription model while a take runs, and the
/// placeholder shown in place of words until it is ready. ONE copy for both apps (Q165, parity
/// audit P66): the phone's `ModelLoadStatus.Phase` and the Mac's `ASRModelStatus` both reduce
/// to this and read the strings from it, so "Downloading model · 12%" cannot be spelled twice.
/// Foundation-only (compiled into the host-less Mac test bundle).
enum RecordingModelState: Equatable {
    case notDownloaded
    case downloading(Double)   // 0...1
    case preparing(Double?)    // loading/compiling an already-downloaded model
    case ready
    case failed

    /// A model that is not loaded and has nothing running. Once the weights have been cached on
    /// disk it is a fast reload, never a re-download, so it never claims "not downloaded".
    static func idle(everDownloaded: Bool) -> RecordingModelState {
        everDownloaded ? .preparing(nil) : .notDownloaded
    }

    /// The status line (phone: the dot + text under the recording header).
    var statusText: String {
        switch self {
        case .downloading(let p): return "Downloading model · \(Self.percent(p))%"
        case .preparing(let p?):  return "Preparing model · \(Self.percent(p))%"
        case .preparing(nil):     return "Preparing model…"
        case .ready:              return "On-device transcription · ready"
        case .failed:             return "Couldn’t load model"
        case .notDownloaded:      return "Transcription model not downloaded"
        }
    }

    /// True while a caption cannot appear yet and nothing says it never will. The words catch up
    /// once the model is ready; a failed load shows its own line instead of a hopeful placeholder.
    var isLoading: Bool { self != .ready && self != .failed }

    /// Shown where the words will appear, while `isLoading` and nothing has been transcribed.
    static let captionPlaceholder = "Model loading — your words appear once it’s ready"

    private static func percent(_ fraction: Double) -> Int {
        Int((min(max(fraction, 0), 1) * 100).rounded(.towardZero))
    }
}
