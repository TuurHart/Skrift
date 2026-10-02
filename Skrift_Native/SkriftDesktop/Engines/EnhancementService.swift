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

    /// The plain copy-edit body path: memo-links escrow to their plain titles
    /// and image markers strip to anchors → LLM → both come back in. A link
    /// whose title didn't survive the edit falls the WHOLE body back to
    /// unedited (the QuoteProtection pattern — never ship a lost reference).
    private func editProse(_ text: String, prompts: AppSettings.Prompts) async throws -> String {
        let (linkStripped, links) = MemoLinkSyntax.escrowForEditing(text)
        let (stripped, imgNums, anchors) = ImageMarkerReinsert.extractAnchors(linkStripped)
        let input = imgNums.isEmpty ? linkStripped : stripped
        // Budget sized from THIS input (PolishPrompts, restored 2026-08-18) — the
        // fixed 1024 cut every long note mid-generation and the escrow's link guard
        // then shipped the raw body, so copy-edit read as "does nothing".
        let cap = PolishPrompts.copyEditTokenBudget(forInput: input)
        let edited = try await run(prompt: prompts.effectiveCopyEdit, text: input, maxTokens: cap)
        if PolishPrompts.looksTruncated(output: edited, cap: cap) {
            Self.log.warning("copy-edit output hit the \(cap)-token cap — keeping the unedited body (never ship a cut note)")
            return text
        }
        if PolishPrompts.lostTooMuch(input: input, output: edited) {
            Self.log.warning("copy-edit ate the note (\(input.count) → \(edited.count) chars) — keeping the unedited body")
            return text
        }
        // The wall cure: paragraph deterministically when the model returns none
        // (Dutch/mixed long text — proven model behavior, not promptable away).
        let broken = PolishPrompts.ensureParagraphs(edited)
        // The paragraph ledger. Three numbers answer every "did copy-edit do anything"
        // question this feature has produced: what the note HAD, what the model gave back,
        // and what shipped. It is also the only way to tell from outside which binary is
        // running — the 2026-08-20 picture fix is pure regex, and Swift stores short
        // literals inline, so nothing in it is string-greppable.
        //   log stream --predicate 'subsystem == "com.skrift.desktop" AND category == "paragraphs"'
        Logger(subsystem: "com.skrift.desktop", category: "paragraphs").log(
            "copy-edit paragraphs: in \(Self.breaks(input), privacy: .public) → model \(Self.breaks(edited), privacy: .public) → shipped \(Self.breaks(broken), privacy: .public)  (\(input.count, privacy: .public) → \(broken.count, privacy: .public) chars, images: \(imgNums.count, privacy: .public))")
        let withImages = imgNums.isEmpty ? broken
            : ImageMarkerReinsert.reinsert(text: broken, imgNums: imgNums, anchors: anchors)
        guard let reattached = MemoLinkSyntax.reattach(edited: withImages, links: links) else {
            Self.log.warning("memo-link title lost during copy-edit — falling back to the unedited body")
            return text
        }
        return reattached
    }

    /// Blank-line-separated blocks — "how many paragraphs does this text have".
    private static func breaks(_ s: String) -> Int {
        s.components(separatedBy: "\n\n").filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    func title(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
        try await ensureLoaded(modelRepo: modelRepo)
        return try await run(prompt: prompts.effectiveTitle,
                             text: MemoLinkSyntax.escrowForEditing(transcript).text, maxTokens: 64)
    }

    func summary(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
        try await ensureLoaded(modelRepo: modelRepo)
        return try await run(prompt: prompts.effectiveSummary,
                             text: MemoLinkSyntax.escrowForEditing(transcript).text, maxTokens: 256)
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
