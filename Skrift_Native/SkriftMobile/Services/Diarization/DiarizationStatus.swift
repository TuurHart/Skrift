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
    /// When the active diarization session began — drives the elapsed-time readout
    /// (diarization is opaque, so there's no real %; an honest "Identifying… · 0:14"
    /// + a "this can take a while" note is the agreed UX, 2026-06-21).
    @Published private(set) var startedAt: Date?

    func begin(_ id: UUID, phase: Phase = .identifying) { memoID = id; self.phase = phase; startedAt = Date() }
    func set(_ phase: Phase) { self.phase = phase }
    func finish() { memoID = nil; phase = .idle; startedAt = nil }

    /// True while actively running diarization for `id` (not a model download/prepare) —
    /// gates the "this can take a while" reassurance subtitle.
    func isIdentifying(_ id: UUID) -> Bool { memoID == id && (phase == .identifying || phase == .enrolling) }

    /// The banner label with an elapsed `· m:ss` appended while identifying, so the
    /// user can see it's still working. Falls back to the plain `label(for:)`.
    func labelWithElapsed(for id: UUID) -> String? {
        guard let base = label(for: id) else { return nil }
        guard isIdentifying(id), let startedAt else { return base }
        let s = max(0, Int(Date().timeIntervalSince(startedAt)))
        return base + String(format: " · %d:%02d", s / 60, s % 60)
    }

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
