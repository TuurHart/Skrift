import Foundation
import SwiftUI
import UIKit

/// What an on-device polish produces — the same three pieces the Mac's
/// `BatchRunner` writes into `MemoEnhancement`.
struct PolishResult: Sendable, Equatable {
    var copyedit: String
    var title: String
    var summary: String
}

/// The model passes a note goes through, in order — so the UI can say WHICH
/// step is running ("Copy-edit · 2 of 3") instead of an opaque spinner. Named
/// after the Mac's `RunState`, which has always published its current step
/// (Tuur, 2026-07-23: the iPad "doesn't give any indication of where we are at").
enum PolishStep: Int, Sendable, Equatable, CaseIterable {
    case copyEdit = 1, title, summary

    static let total = PolishStep.allCases.count

    var label: String {
        switch self {
        case .copyEdit: return "Copy-edit"
        case .title:    return "Title"
        case .summary:  return "Summary"
        }
    }

    /// "Copy-edit · 2 of 3" — one vocabulary, from `SharedCopy`.
    var line: String { SharedCopy.processingStep(label, rawValue, of: Self.total) }
}

/// The engine seam (iPad wave 1). `MLXPolishEngine` (Services/Polish/Engine/)
/// implements it with the Mac's exact stack; everything else in the app talks
/// only to `PolishCenter`, so surfaces compile and stay honest ("not available
/// on this device") when no engine is installed.
protocol PolishEngine: Sendable {
    /// True once the model weights are on disk (no download needed to polish).
    func isModelOnDisk() async -> Bool
    /// Fetch the model (idempotent). Progress 0…1.
    func downloadModel(onProgress: @escaping @Sendable (Double) -> Void) async throws
    /// Polish a RAW transcript → the three pieces. The engine owns the escrow
    /// steps (quote protection, image-marker anchors, memo-link escrow) exactly
    /// like the desktop `EnhancementService`, via the SAME Shared helpers.
    /// Reports the CURRENT step plus an overall 0…1 fraction, so the bar can
    /// show a determinate line the way the Mac's run bar does.
    func polish(transcript: String,
                onStep: @escaping @Sendable (PolishStep, Double) -> Void) async throws -> PolishResult
}

/// Device gate for the on-demand polisher. The iPhone never qualifies (the
/// phone's job is capture; polish belongs to the Mac + iPad per IPAD_PLAN.md),
/// the simulator can't run Metal-JIT MLX, and small-RAM pads would jetsam
/// mid-generation.
enum PolishGate {
    static var isSupported: Bool {
        #if targetEnvironment(simulator)
        // MLX needs a real Metal GPU (JIT kernels) — the sim build keeps the UI
        // reachable for screenshots but reports unsupported at the gate.
        return false
        #else
        return UIDevice.current.userInterfaceIdiom == .pad
            && ProcessInfo.processInfo.physicalMemory >= 6_000_000_000
        #endif
    }
}

/// ONE owner for on-device polish state + the `MemoEnhancement` write. UI reads
/// phases; the engine is installed at launch by `PolishBootstrap` (Polish lane).
/// The write path mirrors the Mac's contract exactly: reuse the memo's existing
/// enhancement row when present, stamp `enhancedByDeviceID` + `enhancedAt`, and
/// let LWW-by-`enhancedAt` settle any race with the Mac (`MemoEnhancement` doc).
@MainActor
@Observable
final class PolishCenter {
    static let shared = PolishCenter()

    enum Phase: Equatable {
        case idle
        case downloading(Double)                    // model fetch, 0…1
        case processing(step: PolishStep, fraction: Double)
        case failed(String)

        /// The line the note bar shows — the Mac's run vocabulary, verbatim.
        var line: String? {
            switch self {
            case .idle: return nil
            case .downloading(let f): return SharedCopy.processingDownload(f)
            case .processing(let step, _): return step.line
            case .failed: return "Couldn't process on this iPad"
            }
        }

        /// 0…1 for the determinate bar (nil = nothing to draw).
        var fraction: Double? {
            switch self {
            case .downloading(let f): return f
            case .processing(_, let f): return f
            case .idle, .failed: return nil
            }
        }
    }

    /// Model-level state for the Settings pane (m5) — distinct from the per-memo `Phase`.
    /// Settings talks ONLY to `PolishCenter` (never the engine), so the download lives here.
    enum ModelPhase: Equatable {
        case unknown            // no engine, or not yet probed
        case checking           // probing the disk
        case notDownloaded
        case downloading(Double)   // 0…1
        case downloaded
        case failed(String)
    }

    private var engine: PolishEngine?
    private(set) var phases: [UUID: Phase] = [:]
    /// Drives the Settings model card (Download / live % / Downloaded ✓).
    private(set) var modelPhase: ModelPhase = .unknown

    private init() {}

    /// Called once at launch by `PolishBootstrap` on capable devices.
    func install(engine: PolishEngine) { self.engine = engine }

    /// Supported device AND an installed engine (the flag surfaces honesty:
    /// Settings shows the section only when this is true).
    var isAvailable: Bool { PolishGate.isSupported && engine != nil }

    func phase(for id: UUID) -> Phase { phases[id] ?? .idle }
    func isWorking(_ id: UUID) -> Bool {
        switch phase(for: id) { case .downloading, .processing: return true; default: return false }
    }

    /// A memo the ⋯ menu may offer "Polish now" for: engine present, real
    /// transcript, not locked (locked notes stay sealed end-to-end), not already
    /// in flight. An already-polished memo stays eligible — a re-run overwrites
    /// by LWW, same as the Mac re-polishing.
    func canPolish(_ memo: Memo) -> Bool {
        guard isAvailable, !isWorking(memo.id), !memo.locked else { return false }
        let raw = memo.transcript ?? ""
        return !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The whole on-demand flow: (download if needed →) polish → write the
    /// enhancement. Fire-and-forget from UI; phases drive the indicators.
    func polishNow(_ memo: Memo, repository: NotesRepository = .shared) {
        guard canPolish(memo) else { return }
        guard let engine, let transcript = memo.transcript else { return }
        let id = memo.id
        phases[id] = .processing(step: .copyEdit, fraction: 0)
        Task {
            do {
                if await !engine.isModelOnDisk() {
                    phases[id] = .downloading(0)
                    try await engine.downloadModel { p in
                        Task { @MainActor in self.phases[id] = .downloading(p) }
                    }
                }
                phases[id] = .processing(step: .copyEdit, fraction: 0)
                let result = try await engine.polish(transcript: transcript) { step, fraction in
                    Task { @MainActor in self.phases[id] = .processing(step: step, fraction: fraction) }
                }
                write(result, forMemo: id, repository: repository)
                phases[id] = nil
            } catch {
                phases[id] = .failed(error.localizedDescription)
                DevLog.log("polish failed for \(id): \(error.localizedDescription)")
            }
        }
    }

    // NOTE (v2, Tuur 2026-07-23): the "polish when I open a note" automation was
    // REMOVED — the iPad polishes only on the visible Polish verb (the Mac's
    // idiom). If automation ever returns, resurrect AutoPolishTracker from git.

    // MARK: - Settings model card (m5)

    /// Probe whether the model is already on disk → drives the Settings card's initial state.
    func refreshModelState() {
        guard let engine else { modelPhase = .unknown; return }
        if case .downloading = modelPhase { return }   // don't stomp an in-flight download
        modelPhase = .checking
        Task {
            let onDisk = await engine.isModelOnDisk()
            // A download that started meanwhile wins over a stale probe.
            if case .downloading = modelPhase { return }
            modelPhase = onDisk ? .downloaded : .notDownloaded
        }
    }

    /// Fetch the model from the Settings card's Download button. Idempotent; progress drives
    /// the live %. Kept here (not in the view) so Settings never touches the engine directly.
    func downloadModelForSettings() {
        guard let engine else { return }
        if case .downloading = modelPhase { return }
        modelPhase = .downloading(0)
        Task {
            do {
                try await engine.downloadModel { p in
                    Task { @MainActor in
                        if case .downloading = self.modelPhase { self.modelPhase = .downloading(p) }
                    }
                }
                modelPhase = .downloaded
            } catch {
                modelPhase = .failed(error.localizedDescription)
                DevLog.log("polish model download failed: \(error.localizedDescription)")
            }
        }
    }

    /// The Mac-contract write: reuse the existing sidecar row (one enhancement
    /// per memo, reconciled by `memoID`), never touch `Memo.transcript` (RAW
    /// stays RAW — the spine rule).
    private func write(_ result: PolishResult, forMemo id: UUID, repository: NotesRepository) {
        let enhancement = repository.enhancement(forMemo: id) ?? {
            let fresh = MemoEnhancement(memoID: id)
            repository.context.insert(fresh)
            return fresh
        }()
        enhancement.copyedit = result.copyedit
        enhancement.title = result.title
        enhancement.summary = result.summary
        enhancement.enhancedByDeviceID = DeviceID.current()
        enhancement.enhancedAt = Date()
        repository.save()
        DevLog.log("polish: wrote enhancement for \(id) (copyedit \(result.copyedit.count) chars)")
    }
}
