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
    private static let log = Logger(subsystem: "com.skrift.desktop", category: "enhancement")

    private var container: ModelContainer?
    private var loadedRepo: String?

    private init() {}

    var isModelReady: Bool { container != nil }

    func ensureLoaded(modelRepo: String,
                      onProgress: @Sendable @escaping (Double) -> Void = { _ in }) async throws {
        if container != nil, loadedRepo == modelRepo { return }
        let config = ModelConfiguration(id: modelRepo)
        container = try await LLMModelFactory.shared.loadContainer(
            from: #hubDownloader(),
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

    /// Copy-edit. Photo-aware: strips `[[img_NNN]]` markers, edits, reinserts via
    /// anchors (the LLM never sees markers). Mirrors the backend behavior.
    ///
    /// Audiobook-quote-aware (spec 8, contract C1): a leading "> " blockquote is a
    /// captured quote — the author's literal words — and must survive byte-identical.
    /// It is stripped off (the marker strip/reinsert pattern), ONLY the ramble is
    /// copy-edited, the quote is reinserted, and the result is byte-asserted; any
    /// mismatch returns the fully-unedited body (skip-all — the conversation-mode
    /// precedent). `BatchRunner` re-asserts after this call as the outer safety net.
    func copyEdit(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
        try await ensureLoaded(modelRepo: modelRepo)
        if let split = QuoteProtection.splitLeadingQuote(transcript) {
            // Quote-only capture (no ramble yet): nothing the LLM may touch.
            guard !split.ramble.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return transcript
            }
            let editedRamble = try await editProse(split.ramble, prompts: prompts)
            let rejoined = QuoteProtection.reassemble(quote: split.quote, ramble: editedRamble)
            guard QuoteProtection.leadingQuoteIntact(original: transcript, edited: rejoined) else {
                Self.log.warning("audiobook quote block mutated during copy-edit — falling back to the unedited body")
                return transcript
            }
            return rejoined
        }
        return try await editProse(transcript, prompts: prompts)
    }

    /// The plain copy-edit body path: image markers out → LLM → markers back in.
    private func editProse(_ text: String, prompts: AppSettings.Prompts) async throws -> String {
        let (stripped, imgNums, anchors) = ImageMarkerReinsert.extractAnchors(text)
        let input = imgNums.isEmpty ? text : stripped
        let edited = try await run(prompt: prompts.copyEdit, text: input, maxTokens: 1024)
        return imgNums.isEmpty ? edited : ImageMarkerReinsert.reinsert(text: edited, imgNums: imgNums, anchors: anchors)
    }

    func title(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
        try await ensureLoaded(modelRepo: modelRepo)
        return try await run(prompt: prompts.title, text: transcript, maxTokens: 64)
    }

    func summary(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
        try await ensureLoaded(modelRepo: modelRepo)
        return try await run(prompt: prompts.summary, text: transcript, maxTokens: 256)
    }

    /// One deterministic instruct turn: the prompt + the text as a single user message.
    private func run(prompt: String, text: String, maxTokens: Int) async throws -> String {
        guard let container else { throw EnhancementError.notLoaded }
        let session = ChatSession(
            container,
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0)
        )
        let out = try await session.respond(to: prompt + "\n\n" + text)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
