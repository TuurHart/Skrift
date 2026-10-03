import Foundation
import UIKit
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers
import os

enum PolishEngineError: LocalizedError {
    case notLoaded
    /// MLX's C++ layer raised during a load or an eval. Carries its message so the
    /// failure reaches the user (and DevLog) as words instead of a stack.
    case mlx(String)

    var errorDescription: String? {
        switch self {
        case .notLoaded: "Polish model not loaded."
        case .mlx(let m): "The polish model couldn't be loaded — \(m)"
        }
    }
}

/// Collects what MLX's error handler reports during a scoped block.
///
/// Why this exists: mlx-swift's DEFAULT error handler calls `fatalError`, so an MLX
/// fault kills the app outright — it never reaches `PolishCenter`'s `catch`, writes no
/// DevLog line, and leaves only an `EXC_BREAKPOINT` stack. That is exactly how the
/// 2026-08-12 iPad crash presented, and it cost a full diagnosis round to read a
/// message the app already had in hand. Scoping a handler converts the trap into a
/// Swift `throw` we can log and show.
private final class MLXErrorTrap: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []
    func record(_ message: String) { lock.withLock { messages.append(message) } }
    var first: String? { lock.withLock { messages.first } }
}

/// The iPad's on-demand polish engine — the Mac's EXACT enhancement stack (mlx-swift-lm,
/// Gemma 4 E4B, the shared `PolishPrompts`) behind the `PolishEngine` seam. It is a 1:1
/// port of the desktop `EnhancementService`: same `#hubDownloader()`/`#huggingFaceTokenizerLoader()`
/// load, same `ChatSession` deterministic turns (temperature 0), same escrow via the shared
/// helpers — so a note reads identically whichever device polished it. Lives in
/// `Services/Polish/Engine/` (MLX out of the pure escrow layer, which is tested separately).
///
/// Honesty: the simulator can't run Metal-JIT MLX, so `PolishGate.isSupported` is false
/// there and this engine is never installed; live generation is DEVICE-OWED by contract.
actor MLXPolishEngine: PolishEngine {
    private static let log = Logger(subsystem: "com.skrift.mobile", category: "polish")

    /// The single model the iPad runs (no model UI on the pad — the Mac is the tuning bench).
    private let modelRepo = PolishPrompts.defaultModelRepo

    private var container: ModelContainer?
    private var loadedRepo: String?
    private var memoryObserver: NSObjectProtocol?

    /// Cheap init: registers the memory-warning observer ONLY. NO model load at launch
    /// (brief step 2 — engine init must stay lazy so launch is untouched on capable iPads).
    init() {
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: nil
        ) { [weak self] _ in
            // Free the ~4.6 GB container under memory pressure; the next polish reloads it.
            Task { await self?.unload() }
        }
    }

    deinit {
        if let memoryObserver { NotificationCenter.default.removeObserver(memoryObserver) }
    }

    // MARK: - PolishEngine

    /// True once the model weights are actually on disk (not merely a config/tokenizer
    /// partial). Probes the HF blob store — the library's own cache path, so it can never
    /// drift from where `#hubDownloader()` writes — and reuses `ModelInventory.sizeOnDisk`
    /// (the cited pattern). Advisory only: the download path is idempotent, so a wrong read
    /// costs a Settings label, never correctness. Exact detection is device-owed to confirm.
    func isModelOnDisk() async -> Bool {
        guard let repoID = Repo.ID(rawValue: modelRepo) else { return false }
        let blobs = HubCache.default.blobsDirectory(repo: repoID, kind: .model)
        return (ModelInventory.sizeOnDisk(blobs) ?? 0) > Self.modelDiskFloorBytes
    }

    /// Weights present (not just a partial). 0.5 GB is far above any config/tokenizer and
    /// far below the full ~4.6 GB, so a half-fetched repo reads as not-downloaded.
    private static let modelDiskFloorBytes: Int64 = 500_000_000

    /// Fetch (idempotent) = load the container with a progress handler; it downloads what's
    /// missing and keeps it cached. Loading into memory here means the following `polish`
    /// call reuses the session (no reload).
    func downloadModel(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        try await ensureLoaded(onProgress: onProgress)
    }

    /// The one copy-edit LLM turn, budget-sized from ITS input (PolishPrompts,
    /// restored 2026-08-18 — the fixed 1024 cut every long note mid-generation).
    /// Returning the input unchanged rides the escrow back to the raw body
    /// (never ship a cut note). Shared by the full polish AND the per-part redo.
    private func copyEditGenerate(_ input: String) async throws -> String {
        let cap = PolishPrompts.copyEditTokenBudget(forInput: input)
        let out = try await run(prompt: PolishPromptsStore.copyEdit(), text: input, maxTokens: cap)
        if PolishPrompts.looksTruncated(output: out, cap: cap) {
            DevLog.log("polish: copy-edit hit the \(cap)-token cap — keeping the unedited body")
            return input
        }
        if PolishPrompts.lostTooMuch(input: input, output: out) {
            DevLog.log("polish: copy-edit ate the note (\(input.count) → \(out.count) chars) — keeping the unedited body")
            return input
        }
        // The wall cure (Dutch/mixed long text gets no breaks from the model).
        return PolishPrompts.ensureParagraphs(out)
    }

    /// Re-run ONE part — the Mac's Redo ▸ Title/Copy-edit/Summary, on the iPad
    /// (Tuur 2026-08-18: the ⋯ "should also have the same redo options"). Same
    /// prompts, same escrow, same budget as the full pass; a redone summary
    /// deliberately ignores the min-words threshold (the Mac's rule — a manual
    /// redo is an override).
    func redo(_ part: NoteRedoItem, transcript: String) async throws -> String {
        try await ensureLoaded()
        switch part {
        case .copyEdit:
            return try await PolishEscrow.copyEdit(transcript, generate: copyEditGenerate)
        case .title:
            return try await titleTurn(plain: PolishEscrow.plainForTitleSummary(transcript))
        case .summary:
            return try await summaryTurn(plain: PolishEscrow.plainForTitleSummary(transcript))
        }
    }

    /// Output-token ceilings for the two short turns (copy-edit sizes its own, from its input).
    private static let titleTokenBudget = 64
    private static let summaryTokenBudget = 256

    /// The title turn — one spelling for the full polish and the per-part redo.
    private func titleTurn(plain: String) async throws -> String {
        try await run(prompt: PolishPromptsStore.title(), text: plain, maxTokens: Self.titleTokenBudget)
    }

    /// The summary turn — one spelling for the full polish and the per-part redo.
    private func summaryTurn(plain: String) async throws -> String {
        try await run(prompt: PolishPromptsStore.summary(), text: plain, maxTokens: Self.summaryTokenBudget)
    }

    /// Polish a RAW transcript → the three pieces the Mac writes. Copy-edit runs through the
    /// full `PolishEscrow` (quote protection + link/image escrow); title always runs; summary
    /// is skipped on short transcripts (Mac parity — `BatchRunner`/`effectiveSummaryMinWords`).
    /// Progress is coarse (per-step) — generation gives no fine-grained signal.
    func polish(transcript: String,
                onStep: @escaping @Sendable (PolishStep, Double) -> Void) async throws -> PolishResult {
        // The fractions are the real pass boundaries (copy-edit is by far the
        // longest — a full-transcript generation vs a 64/256-token one), so the
        // bar moves in proportion to the work, not in equal thirds.
        onStep(.copyEdit, 0.05)
        try await ensureLoaded()   // no-op when the download path already loaded it
        onStep(.copyEdit, 0.10)

        let copyedit = try await PolishEscrow.copyEdit(transcript, generate: copyEditGenerate)
        onStep(.title, 0.55)

        let plain = PolishEscrow.plainForTitleSummary(transcript)
        let title = try await titleTurn(plain: plain)
        onStep(.summary, 0.75)

        let summary = PolishEscrow.wordsMeetSummaryThreshold(transcript)
            ? try await summaryTurn(plain: plain)
            : ""
        onStep(.summary, 1.0)

        return PolishResult(copyedit: copyedit, title: title, summary: summary)
    }

    // MARK: - Model lifecycle (ported 1:1 from EnhancementService)

    func ensureLoaded(onProgress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        if container != nil, loadedRepo == modelRepo { return }
        // Pinned revision, not `main` — see PolishPrompts.defaultModelRevision. This
        // is the line that made this iPad fail while the Mac's June cache kept working.
        let config = ModelConfiguration(id: modelRepo, revision: PolishPrompts.revision(for: modelRepo))
        // MLX faults are FATAL by default (see `MLXErrorTrap`) — scope a handler so a bad
        // weight file throws instead of taking the app down with it.
        let trap = MLXErrorTrap()
        let loaded = try await MLX.withErrorHandler({ trap.record($0) }) {
            try await LLMModelFactory.shared.loadContainer(
                // NOT `#hubDownloader()`: it buffers each file whole and keeps nothing on
                // failure, so the 4.9 GB shard restarted from zero on every blip and this
                // iPad never finished it. See `ResumableModelDownloader`.
                from: ResumableModelDownloader(),
                using: #huggingFaceTokenizerLoader(),
                configuration: config,
                progressHandler: { onProgress($0.fractionCompleted) }
            )
        }
        if let message = trap.first {
            // Anything MLX produced after its own error is not safe to use.
            Self.log.error("polish model load failed: \(message, privacy: .public)")
            throw PolishEngineError.mlx(message)
        }
        container = loaded
        loadedRepo = modelRepo
        Self.log.info("polish model loaded (\(self.modelRepo, privacy: .public))")
    }

    func unload() {
        container = nil
        loadedRepo = nil
        Self.log.info("polish model unloaded")
    }

    /// Delete the downloaded weights so the next Download fetches them CLEAN.
    ///
    /// The escape hatch the Settings card lacked: a half-fetched or corrupt cache used to
    /// be terminal, because the card renders a dead "Downloaded ✓" with no way back
    /// (2026-08-12 — a resumed download on this iPad produced right-length, wrong-bytes
    /// weights and nothing in the UI could clear them).
    func removeModel() async throws {
        unload()
        guard let repoID = Repo.ID(rawValue: modelRepo) else { return }
        let fm = FileManager.default
        // Both halves of the HF cache entry: the blobs AND the snapshot/refs that point
        // at them. Removing only the blobs leaves dangling symlinks that read as present.
        for dir in [HubCache.default.blobsDirectory(repo: repoID, kind: .model),
                    HubCache.default.repoDirectory(repo: repoID, kind: .model)] {
            if fm.fileExists(atPath: dir.path) { try? fm.removeItem(at: dir) }
        }
        Self.log.info("polish model removed from disk")
    }

    /// One deterministic instruct turn: the prompt + the text as a single user message.
    private func run(prompt: String, text: String, maxTokens: Int) async throws -> String {
        guard let container else { throw PolishEngineError.notLoaded }
        let session = ChatSession(
            container,
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0)
        )
        let out = try await session.respond(to: prompt + "\n\n" + text)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
