import Foundation
import os

/// One model call: the prompt, the text, the token cap → the model's RAW output (untrimmed).
/// The live MLX engine (`EnhancementService.generate`) and the recorded-output replay
/// (`ModelOutputCache`) both have this shape, so every deterministic step around the model
/// runs MLX-free in the unit tests (Q423, C7/C286).
typealias ModelGenerate = @Sendable (_ prompt: String, _ text: String, _ maxTokens: Int) async throws -> String

/// v1's copy-edit / title / summary around ONE model call each — moved verbatim out of
/// `EnhancementService` (Q423) so the copy-edit harness replays it without MLX. Behaviour is
/// unchanged: quote held back (C29/C31), memo-links escrowed, picture markers stripped to
/// 6-word anchors and reinserted (the v1 machinery C30 deletes), token budget + truncation +
/// shrink guards (C32/C33), deterministic paragraphing of a returned wall (C34).
enum CopyEditPipeline {
    private static let log = Logger(subsystem: "com.skrift.desktop", category: "enhancement")

    /// Copy-edit. Audiobook-quote-aware (spec 8, contract C1): a leading "> " blockquote is a
    /// captured quote and survives byte-identical; only the ramble is edited; any quote
    /// mismatch returns the fully-unedited body.
    static func copyEdit(_ transcript: String, prompts: AppSettings.Prompts,
                         generate: ModelGenerate) async throws -> String {
        if let split = QuoteProtection.splitLeadingQuote(transcript) {
            guard !split.ramble.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return transcript
            }
            let editedRamble = try await editProse(split.ramble, prompts: prompts, generate: generate)
            let rejoined = QuoteProtection.reassemble(quote: split.quote, ramble: editedRamble)
            guard QuoteProtection.leadingQuoteIntact(original: transcript, edited: rejoined) else {
                log.warning("audiobook quote block mutated during copy-edit — falling back to the unedited body")
                return transcript
            }
            return rejoined
        }
        return try await editProse(transcript, prompts: prompts, generate: generate)
    }

    /// The plain copy-edit body path: memo-links escrow to their plain titles and image
    /// markers strip to anchors → LLM → both come back in. A link whose title didn't survive
    /// the edit falls the WHOLE body back to unedited.
    private static func editProse(_ text: String, prompts: AppSettings.Prompts,
                                  generate: ModelGenerate) async throws -> String {
        let (linkStripped, links) = MemoLinkSyntax.escrowForEditing(text)
        let (stripped, imgNums, anchors) = ImageMarkerReinsert.extractAnchors(linkStripped)
        let input = imgNums.isEmpty ? linkStripped : stripped
        let cap = PolishPrompts.copyEditTokenBudget(forInput: input)
        let edited = try await run(prompt: prompts.effectiveCopyEdit, text: input, maxTokens: cap, generate: generate)
        if PolishPrompts.looksTruncated(output: edited, cap: cap) {
            log.warning("copy-edit output hit the \(cap)-token cap — keeping the unedited body (never ship a cut note)")
            return text
        }
        if PolishPrompts.lostTooMuch(input: input, output: edited) {
            log.warning("copy-edit ate the note (\(input.count) → \(edited.count) chars) — keeping the unedited body")
            return text
        }
        let broken = PolishPrompts.ensureParagraphs(edited)
        // The paragraph ledger (in → model → shipped):
        //   log stream --predicate 'subsystem == "com.skrift.desktop" AND category == "paragraphs"'
        Logger(subsystem: "com.skrift.desktop", category: "paragraphs").log(
            "copy-edit paragraphs: in \(breaks(input), privacy: .public) → model \(breaks(edited), privacy: .public) → shipped \(breaks(broken), privacy: .public)  (\(input.count, privacy: .public) → \(broken.count, privacy: .public) chars, images: \(imgNums.count, privacy: .public))")
        let withImages = imgNums.isEmpty ? broken
            : ImageMarkerReinsert.reinsert(text: broken, imgNums: imgNums, anchors: anchors)
        guard let reattached = MemoLinkSyntax.reattach(edited: withImages, links: links) else {
            log.warning("memo-link title lost during copy-edit — falling back to the unedited body")
            return text
        }
        return reattached
    }

    /// Blank-line-separated blocks — "how many paragraphs does this text have".
    static func breaks(_ s: String) -> Int {
        s.components(separatedBy: "\n\n").filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    static func title(_ transcript: String, prompts: AppSettings.Prompts,
                      generate: ModelGenerate) async throws -> String {
        try await run(prompt: prompts.effectiveTitle,
                      text: MemoLinkSyntax.escrowForEditing(transcript).text, maxTokens: 64, generate: generate)
    }

    static func summary(_ transcript: String, prompts: AppSettings.Prompts,
                        generate: ModelGenerate) async throws -> String {
        try await run(prompt: prompts.effectiveSummary,
                      text: MemoLinkSyntax.escrowForEditing(transcript).text, maxTokens: 256, generate: generate)
    }

    /// One deterministic instruct turn; the output is trimmed here, so a recorded output is
    /// the model's raw text.
    private static func run(prompt: String, text: String, maxTokens: Int,
                            generate: ModelGenerate) async throws -> String {
        try await generate(prompt, text, maxTokens).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// An `Enhancing` built from a `ModelGenerate` — the replay engine of the copy-edit harness
/// and the recording wrapper of `-recordcopyedit`. The live app keeps `EnhancementService`.
struct GenerateEnhancer: Enhancing {
    let generate: ModelGenerate

    func copyEdit(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
        try await CopyEditPipeline.copyEdit(transcript, prompts: prompts, generate: generate)
    }
    func title(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
        try await CopyEditPipeline.title(transcript, prompts: prompts, generate: generate)
    }
    func summary(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
        try await CopyEditPipeline.summary(transcript, prompts: prompts, generate: generate)
    }
}
