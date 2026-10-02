import Foundation
import Observation

/// The Mac's observable transcription-model state, so the live recording pane can say
/// "Downloading / Preparing / ready / Couldn't load" instead of looking like silence while
/// `TranscriptionService.beginStream()` loads the model (Q165). Mirror of the phone's
/// `ModelLoadStatus`; both reduce to the shared `RecordingModelState`. Written ONLY by
/// `TranscriptionService` via `set(_:)`.
@MainActor
@Observable
final class ASRModelStatus {
    static let shared = ASRModelStatus()

    private static let everReadyKey = "modelEverReady"

    /// True once the model has loaded at least once on this Mac (persisted): its weights are
    /// cached, so an unloaded model is a fast reload and never claims "not downloaded".
    static var everDownloaded: Bool { UserDefaults.standard.bool(forKey: everReadyKey) }

    private(set) var state: RecordingModelState = .idle(everDownloaded: ASRModelStatus.everDownloaded)

    func set(_ new: RecordingModelState) {
        // Progress callbacks fire far more often than 1% steps — quantise and drop no-ops so
        // the pane doesn't re-render on every one.
        let incoming = Self.quantized(new)
        guard incoming != state else { return }
        state = incoming
        if incoming == .ready { UserDefaults.standard.set(true, forKey: Self.everReadyKey) }
    }

    /// The model was unloaded (idle timeout / language change): it is cached, so it will reload.
    func setUnloaded() { set(.idle(everDownloaded: Self.everDownloaded)) }

    nonisolated static func quantized(_ s: RecordingModelState) -> RecordingModelState {
        switch s {
        case .downloading(let p): return .downloading((p * 100).rounded() / 100)
        case .preparing(let p?):  return .preparing((p * 100).rounded() / 100)
        default:                  return s
        }
    }

    private init() {}
}
