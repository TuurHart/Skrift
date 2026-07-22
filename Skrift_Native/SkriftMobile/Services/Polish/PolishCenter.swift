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
    func polish(transcript: String, onProgress: @escaping @Sendable (Double) -> Void) async throws -> PolishResult
}

/// Device gate for the on-demand polisher. The iPhone never qualifies (the
/// phone's job is capture; polish belongs to the Mac + iPad per IPAD_PLAN.md),
/// the simulator can't run Metal-JIT MLX, and small-RAM pads would jetsam
/// mid-generation.
enum PolishGate {
    /// UserDefaults key for the "Polish when I open a note" toggle (Settings).
    static let polishOnOpenKey = "polishOnOpen"

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
        case downloading(Double)   // model fetch, 0…1
        case polishing(Double)     // generation, 0…1 (coarse)
        case failed(String)
    }

    private var engine: PolishEngine?
    private(set) var phases: [UUID: Phase] = [:]

    private init() {}

    /// Called once at launch by `PolishBootstrap` on capable devices.
    func install(engine: PolishEngine) { self.engine = engine }

    /// Supported device AND an installed engine (the flag surfaces honesty:
    /// Settings shows the section only when this is true).
    var isAvailable: Bool { PolishGate.isSupported && engine != nil }

    func phase(for id: UUID) -> Phase { phases[id] ?? .idle }
    func isWorking(_ id: UUID) -> Bool {
        switch phase(for: id) { case .downloading, .polishing: return true; default: return false }
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
        phases[id] = .polishing(0)
        Task {
            do {
                if await !engine.isModelOnDisk() {
                    phases[id] = .downloading(0)
                    try await engine.downloadModel { p in
                        Task { @MainActor in self.phases[id] = .downloading(p) }
                    }
                }
                phases[id] = .polishing(0)
                let result = try await engine.polish(transcript: transcript) { p in
                    Task { @MainActor in self.phases[id] = .polishing(p) }
                }
                write(result, forMemo: id, repository: repository)
                phases[id] = nil
            } catch {
                phases[id] = .failed(error.localizedDescription)
                DevLog.log("polish failed for \(id): \(error.localizedDescription)")
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
