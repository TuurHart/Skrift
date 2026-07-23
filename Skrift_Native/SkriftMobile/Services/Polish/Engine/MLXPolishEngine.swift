import Foundation
import UIKit
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers
import os

enum PolishEngineError: LocalizedError {
    case notLoaded
    var errorDescription: String? { "Polish model not loaded." }
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

        let copyedit = try await PolishEscrow.copyEdit(transcript) { input in
            try await self.run(prompt: PolishPromptsStore.copyEdit(), text: input, maxTokens: 1024)
        }
        onStep(.title, 0.55)

        let plain = PolishEscrow.plainForTitleSummary(transcript)
        let title = try await run(prompt: PolishPromptsStore.title(), text: plain, maxTokens: 64)
        onStep(.summary, 0.75)

        let summary = PolishEscrow.wordsMeetSummaryThreshold(transcript)
            ? try await run(prompt: PolishPromptsStore.summary(), text: plain, maxTokens: 256)
            : ""
        onStep(.summary, 1.0)

        return PolishResult(copyedit: copyedit, title: title, summary: summary)
    }

    // MARK: - Model lifecycle (ported 1:1 from EnhancementService)

    func ensureLoaded(onProgress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        if container != nil, loadedRepo == modelRepo { return }
        let config = ModelConfiguration(id: modelRepo)
        container = try await LLMModelFactory.shared.loadContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: config,
            progressHandler: { onProgress($0.fractionCompleted) }
        )
        loadedRepo = modelRepo
        Self.log.info("polish model loaded (\(self.modelRepo, privacy: .public))")
    }

    func unload() {
        container = nil
        loadedRepo = nil
        Self.log.info("polish model unloaded")
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
