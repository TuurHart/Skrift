import SwiftUI

/// Live status of conversation-mode diarization for ONE memo, so the detail view can
/// show "Downloading speaker model… N%" / "Identifying speakers…" instead of leaving
/// the user staring at the plain transcript wondering if anything's happening (the
/// first-time Sortformer model download is ~90s).
@MainActor
final class DiarizationStatus: ObservableObject {
    static let shared = DiarizationStatus()

    enum Phase: Equatable {
        case idle
        case downloadingModel(Double?)        // first-time Sortformer download (0...1)
        case preparingModel                   // loading Sortformer from cache (already downloaded once)
        case downloadingVoiceModel(Double?)   // first-time wespeaker/voiceprint download (0...1)
        case preparingVoiceModel             // loading wespeaker from cache
        case identifying                      // running diarization
        case enrolling                        // learning a named speaker's voiceprint
    }

    @Published private(set) var memoID: UUID?
    @Published private(set) var phase: Phase = .idle

    func begin(_ id: UUID, phase: Phase = .identifying) { memoID = id; self.phase = phase }
    func set(_ phase: Phase) { self.phase = phase }
    func finish() { memoID = nil; phase = .idle }

    /// A banner label for the active memo, or nil when idle.
    func label(for id: UUID) -> String? {
        guard memoID == id else { return nil }
        switch phase {
        case .idle: return nil
        case .downloadingModel(let p):
            if let p { return "Downloading speaker model… \(Int(p * 100))%" }
            return "Downloading speaker model…"
        case .preparingModel: return "Preparing speaker model…"
        case .downloadingVoiceModel(let p):
            if let p { return "Downloading voice model… \(Int(p * 100))%" }
            return "Downloading voice model…"
        case .preparingVoiceModel: return "Preparing voice model…"
        case .identifying: return "Identifying speakers…"
        case .enrolling: return "Learning this voice…"
        }
    }

    private init() {}
}
