import SwiftUI

/// Observable model-load state shared by the record screen + onboarding, so the
/// "on-device transcription" status + the 494 MB download progress bar update
/// LIVE. Single source of truth = `phase`, written ONLY by `TranscriptionService`
/// via `set(_:)`. The previous three independent booleans were written
/// inconsistently → the status got stuck on "Preparing" (compile progress was
/// discarded) and falsely regressed to "not downloaded" after a memory-warning
/// unload. A persisted latch (`everDownloaded`) ensures an already-cached model
/// never claims "not downloaded" again.
@MainActor
final class ModelLoadStatus: ObservableObject {
    static let shared = ModelLoadStatus()

    enum Phase: Equatable {
        case idle                  // nothing started this process (and never cached)
        case downloading(Double)   // 0...1 network download
        case preparing(Double?)    // loading/compiling an already-downloaded model
        case ready
        case failed
    }

    @Published private(set) var phase: Phase = .idle

    private let everReadyKey = "modelEverReady"
    /// True once the model has finished loading at least once on this device
    /// (persisted) — its weights are then cached on disk, so a cold launch must
    /// never claim "not downloaded" before the fast cached reload completes.
    var everDownloaded: Bool { UserDefaults.standard.bool(forKey: everReadyKey) }

    func set(_ phase: Phase) {
        self.phase = phase
        if case .ready = phase { UserDefaults.standard.set(true, forKey: everReadyKey) }
    }

    // Back-compat conveniences (read by RecordView + OnboardingView).
    var ready: Bool { phase == .ready }
    var loading: Bool {
        switch phase { case .downloading, .preparing: return true; default: return false }
    }
    var downloadProgress: Double? {
        if case .downloading(let p) = phase { return p }
        return nil
    }

    private init() {}
}
