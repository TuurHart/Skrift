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

    /// True once every model file is on disk at its exact expected byte count (C292) —
    /// `ResumableModelDownloader` records the Hub's sizes when it downloads and checks each
    /// file against them. A truncated download is never "downloaded", however big. The
    /// download path is idempotent, so a false here only means the next polish resumes it.
    func isModelOnDisk() async -> Bool {
        ResumableModelDownloader().isComplete(id: modelRepo,
                                              revision: PolishPrompts.revision(for: modelRepo))
    }

    /// Fetch (idempotent) = load the container with a progress handler; it downloads what's
    /// missing and keeps it cached. Loading into memory here means the following `polish`
    /// call reuses the session (no reload).
    func downloadModel(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        try await ensureLoaded(onProgress: onProgress)
    }

    /// Re-run ONE part — the Mac's Redo ▸ Title/Copy-edit/Summary, on the iPad
    /// (Tuur 2026-08-18: the ⋯ "should also have the same redo options"). Same
    /// prompts, same v2 guards as the full pass; a redone summary
    /// deliberately ignores the min-words threshold (the Mac's rule — a manual
    /// redo is an override).
    func redo(_ part: NoteRedoItem, transcript: String, source: CopyEditV2.Source) async throws -> String {
        try await ensureLoaded()
        // Q426: copy-edit v2, the Mac's exact pass (`PolishV2` is the pure half).
        return try await PolishV2.redo(part, transcript: transcript, source: source,
                                       prompts: PolishV2.prompts(), generate: liveGenerate)
    }

    /// The loaded model as copy-edit v2's one generate call (raw output; v2 trims and guards).
    private nonisolated var liveGenerate: CopyEditV2.Generate {
        { prompt, text, maxTokens in try await self.run(prompt: prompt, text: text, maxTokens: maxTokens) }
    }

    /// Polish a RAW transcript → the three pieces the Mac writes, through copy-edit v2 (Q426):
    /// the same `CopyEditV2.runPass` as the Mac — quote, links, pictures, held lines and
    /// emphasis escrowed, the guards and the fallbacks, title and summary over the same prose,
    /// summary only past the word threshold. `PolishEscrow` (v1) stays until Q427 deletes it.
    func polish(transcript: String, source: CopyEditV2.Source,
                onStep: @escaping @Sendable (PolishStep, Double) -> Void) async throws -> PolishResult {
        onStep(.copyEdit, 0.05)
        try await ensureLoaded()   // no-op when the download path already loaded it
        return try await PolishV2.polish(transcript: transcript, source: source, prompts: PolishV2.prompts(),
                                         generate: liveGenerate, onStep: onStep)
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
        // And the copy `ResumableModelDownloader` actually loads from — `isModelOnDisk`
        // reads it, so leaving it would keep the card on "Downloaded" after Remove.
        let snapshot = ResumableModelDownloader().snapshotDirectory(
            id: modelRepo, revision: PolishPrompts.revision(for: modelRepo))
        if fm.fileExists(atPath: snapshot.path) { try? fm.removeItem(at: snapshot) }
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
