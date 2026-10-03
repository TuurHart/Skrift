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
    /// Delete the weights so the next download is CLEAN — the way out of a corrupt cache.
    func removeModel() async throws
    /// Polish a RAW transcript → the three pieces. The engine owns the escrow
    /// steps (quote protection, image-marker anchors, memo-link escrow) exactly
    /// like the desktop `EnhancementService`, via the SAME Shared helpers.
    /// Reports the CURRENT step plus an overall 0…1 fraction, so the bar can
    /// show a determinate line the way the Mac's run bar does.
    func polish(transcript: String,
                onStep: @escaping @Sendable (PolishStep, Double) -> Void) async throws -> PolishResult
    /// Re-run ONE part (the Mac's Redo ▸ Title/Copy-edit/Summary). Same prompts,
    /// same escrow, same budget as the full pass. Part names come from the shared
    /// menu vocabulary (`NoteRedoItem`) — one word set, both apps.
    func redo(_ part: NoteRedoItem, transcript: String) async throws -> String
}

/// Device gate for the on-demand polisher. The iPhone never qualifies (the
/// phone's job is capture; polish belongs to the Mac + iPad per IPAD_PLAN.md),
/// the simulator can't run Metal-JIT MLX, and small-RAM pads would jetsam
/// mid-generation.
enum PolishGate {
    static var isSupported: Bool {
        #if DEBUG
        // Screenshot rig only — see FakePolishEngine. Never true in a Release build.
        if LaunchFlags.fakePolishEngine { return true }
        #endif
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
        // ONE note at a time, device-wide. Not per-note: `isWorking(memo.id)` alone let
        // Tuur start note A, walk to note B and start it too (2026-08-14) — and the app
        // died. `MLXPolishEngine` is an actor, but `polish` awaits internally and actor
        // reentrancy lets a second run interleave at those awaits, so two generations
        // against an 8.9 GB model were alive together. There is only enough memory for one.
        guard busyMemoID == nil else { return false }
        guard isAvailable, !isWorking(memo.id), !memo.locked else { return false }
        let raw = memo.transcript ?? ""
        return !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The whole on-demand flow: (download if needed →) polish → write the
    /// enhancement. Fire-and-forget from UI; phases drive the indicators.
    func polishNow(_ memo: Memo, repository: NotesRepository = .shared) {
        guard canPolish(memo) else { return }
        // Pressing Polish IS a judgment — so it RATES the note (the `MacMemoAuthor`
        // 0.1-floor precedent). Without this, an unrated note could be polished on
        // demand and stay unrated: still fading, still invisible to the Mac,
        // polished-but-dying. The rating is consent, and this is the user giving it;
        // it's the door out of unrated, the same way a backlink is.
        if memo.significance <= 0 {
            memo.significance = 0.1
            repository.save()
        }
        Task { await run(memo, repository: repository) }
    }

    /// Redo ONE part — the Mac's ⋯ ▸ Redo, on the iPad (Tuur 2026-08-18: the menu
    /// "should also have the same redo options"). Offered only on an already-polished
    /// note, so the result overwrites that part in the EXISTING enhancement and rides
    /// LWW to every device (same stamp discipline as `write`). Runs under the same
    /// one-note-at-a-time device claim as a full polish.
    func redo(_ part: NoteRedoItem, for memo: Memo, repository: NotesRepository = .shared) {
        guard isAvailable, !memo.locked, !isWorking(memo.id) else { return }
        Task { await runRedo(part, memo, repository: repository) }
    }

    private func runRedo(_ part: NoteRedoItem, _ memo: Memo, repository: NotesRepository) async {
        guard let engine, let transcript = memo.transcript else { return }
        let id = memo.id
        guard busyMemoID == nil else { return }
        busyMemoID = id
        defer { busyMemoID = nil }
        let step: PolishStep = switch part {
        case .title: .title
        case .copyEdit: .copyEdit
        case .summary: .summary
        }
        phases[id] = .processing(step: step, fraction: 0.2)
        do {
            let out = try await engine.redo(part, transcript: transcript)
            // The existing sidecar row is the target — redo is only offered when a
            // polish exists (menu gate); a vanished row means the note was un-polished
            // mid-run, and writing a fresh partial enhancement would call it processed.
            guard let e = repository.enhancement(forMemo: id) else {
                phases[id] = nil
                return
            }
            switch part {
            case .title: e.title = out
            case .copyEdit: e.copyedit = out
            case .summary: e.summary = out
            }
            e.enhancedByDeviceID = DeviceID.current()
            e.enhancedAt = Date()
            repository.save()
            DevLog.log("polish: redo \(part) wrote \(out.count) chars for \(id)")
            phases[id] = nil
        } catch {
            phases[id] = .failed(error.localizedDescription)
            DevLog.log("polish redo failed for \(id): \(error.localizedDescription)")
        }
    }

    /// ONE pass over ONE note. Awaited directly by the bulk run below, so the
    /// pile and the single-note button can never drift apart.
    private func run(_ memo: Memo, repository: NotesRepository) async {
        guard let engine, let transcript = memo.transcript else { return }
        let id = memo.id
        // Claim the device before the first await. The pile awaits each `run` in turn, so
        // it passes through here one note at a time exactly as it always did.
        guard busyMemoID == nil else { return }
        busyMemoID = id
        defer { busyMemoID = nil }
        phases[id] = .processing(step: .copyEdit, fraction: 0)
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

    // MARK: - The pile (the Mac's Process button, ported)

    /// A bulk run's live state — the Mac's `RunState`, in the words it already
    /// uses ("Processing 2 of 5").
    struct PileRun: Equatable {
        var done: Int
        var total: Int
        var line: String { SharedCopy.processingCount(min(done + 1, total), of: total) }
        var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }
    }

    /// The note being polished right now, if any — the device-wide gate (see `canPolish`).
    private(set) var busyMemoID: UUID?

    private(set) var pileRun: PileRun?
    private var pileTask: Task<Void, Never>?

    /// Process a whole pile on this iPad. **Sequential by design** — one MLX
    /// context at a time; a pad running several would jetsam mid-generation.
    /// Stoppable between notes (the current note always finishes; the engine
    /// call itself isn't interruptible).
    func processPile(_ memos: [Memo], repository: NotesRepository = .shared) {
        guard pileRun == nil, isAvailable else { return }
        let targets = memos.filter { canPolish($0) }
        guard !targets.isEmpty else { return }
        pileRun = PileRun(done: 0, total: targets.count)
        pileTask = Task { @MainActor [weak self] in
            for memo in targets {
                if Task.isCancelled { break }
                guard let self else { return }
                await self.run(memo, repository: repository)
                if let current = self.pileRun {
                    self.pileRun = PileRun(done: current.done + 1, total: current.total)
                }
            }
            self?.pileRun = nil
            self?.pileTask = nil
        }
    }

    func cancelPile() {
        pileTask?.cancel()
        pileTask = nil
        pileRun = nil
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

    /// Delete the downloaded weights and return the card to "Download".
    ///
    /// Exists because a bad cache used to be unrecoverable: the Settings card shows a dead
    /// "Downloaded ✓" once weights are present, so a half-fetched or corrupt copy could
    /// never be cleared from inside the app (2026-08-12 — cost two device rounds on an
    /// iPad whose resumed download produced right-length, wrong-bytes weights).
    func removeModelForSettings() {
        guard let engine else { return }
        if case .downloading = modelPhase { return }   // never yank a live download
        Task {
            do {
                try await engine.removeModel()
                modelPhase = .notDownloaded
                DevLog.log("polish model removed — next download starts clean")
            } catch {
                modelPhase = .failed(error.localizedDescription)
                DevLog.log("polish model remove failed: \(error.localizedDescription)")
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
        // A pass ran, whatever it produced — the fact the export gate and the process
        // pile read (`MemoEnhancement.isProcessed`).
        enhancement.processedAt = Date()
        repository.save()
        DevLog.log("polish: wrote enhancement for \(id) (copyedit \(result.copyedit.count) chars)")
    }
}
