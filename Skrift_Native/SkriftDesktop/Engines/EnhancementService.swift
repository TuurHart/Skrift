import Foundation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers
import os

enum EnhancementError: LocalizedError {
    case notLoaded
    var errorDescription: String? { "Enhancement model not loaded." }
}

/// Local LLM enhancement via mlx-swift (Gemma 4 E4B). The model downloads from HF
/// on first use (matches the distribution decision) and stays cached. All steps run
/// on the RAW transcript (no `[[ ]]` reaches the LLM). Lives in `Engines/` (app
/// only) so MLX stays out of the host-less logic test target; the deterministic
/// marker reinsert is tested separately. The load+generate path was proven in the
/// Phase 0 go/no-go spike.
actor EnhancementService: Enhancing {
    static let shared = EnhancementService()

    private var container: ModelContainer?
    private var loadedRepo: String?

    private init() {}

    func ensureLoaded(modelRepo: String,
                      onProgress: @Sendable @escaping (Double) -> Void = { _ in }) async throws {
        if container != nil, loadedRepo == modelRepo { return }
        // Pinned revision, not `main` — see PolishPrompts.defaultModelRevision for
        // why an unpinned model let the Mac and the iPad run different weights.
        let config = ModelConfiguration(id: modelRepo, revision: PolishPrompts.revision(for: modelRepo))
        container = try await LLMModelFactory.shared.loadContainer(
            // Same resumable downloader as the iPad (see ResumableModelDownloader):
            // #hubDownloader() keeps nothing on failure, so a dropped 4.9 GB shard
            // restarts from zero. The Mac timed out on it once too.
            from: ResumableModelDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: config,
            progressHandler: { onProgress($0.fractionCompleted) }
        )
        loadedRepo = modelRepo
    }

    func unload() {
        container = nil
        loadedRepo = nil
    }

    /// Copy-edit / title / summary: the deterministic steps live in the MLX-free
    /// `CopyEditPipeline` (Q423, so the copy-edit harness replays them); this actor only
    /// owns the model and the one generate call.
    func copyEdit(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
        try await ensureLoaded(modelRepo: modelRepo)
        return try await CopyEditPipeline.copyEdit(transcript, prompts: prompts, generate: generator)
    }

    func title(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
        try await ensureLoaded(modelRepo: modelRepo)
        return try await CopyEditPipeline.title(transcript, prompts: prompts, generate: generator)
    }

    func summary(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
        try await ensureLoaded(modelRepo: modelRepo)
        return try await CopyEditPipeline.summary(transcript, prompts: prompts, generate: generator)
    }

    /// The live model as a `ModelGenerate` (the loaded model; call `ensureLoaded` first).
    nonisolated var generator: ModelGenerate {
        { prompt, text, maxTokens in try await self.generate(prompt: prompt, text: text, maxTokens: maxTokens) }
    }

    /// One deterministic instruct turn: the prompt + the text as a single user message.
    /// Returns the model's RAW output (`CopyEditPipeline` trims).
    func generate(prompt: String, text: String, maxTokens: Int) async throws -> String {
        guard let container else { throw EnhancementError.notLoaded }
        let session = ChatSession(
            container,
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0)
        )
        return try await session.respond(to: prompt + "\n\n" + text)
    }
}
