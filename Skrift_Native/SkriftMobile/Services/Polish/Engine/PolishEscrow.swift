import Foundation

/// The escrow layer for on-device Polish — factored OUT of `MLXPolishEngine` so it stays
/// pure + host-testable WITHOUT loading MLX (iPad wave 1, honesty contract). It is the
/// byte-exact port of the desktop `EnhancementService.copyEdit`/`editProse` escrow:
/// audiobook quote protection (contract C1), memo-link escrow, and image-marker anchors —
/// all via the SAME `Shared/` helpers, so a note reads identically whichever device
/// polished it (twin copies drift; the escrow can't).
///
/// `generate` is the raw LLM turn (the caller has already chosen the prompt). Tests inject
/// an identity or a deliberately-mutating stub; every loss/mutation fallback lives here.
enum PolishEscrow {

    /// Copy-edit with full escrow. A leading `> ` blockquote is an audiobook capture
    /// (contract C1) — the author's literal words — so it never reaches the LLM: split it
    /// off, edit ONLY the ramble, reinsert the quote, then BYTE-ASSERT it. Any mismatch
    /// returns the fully-unedited transcript (skip-all — the conversation-mode precedent).
    /// Mirrors `EnhancementService.copyEdit`.
    static func copyEdit(_ transcript: String,
                         generate: (String) async throws -> String) async throws -> String {
        if let split = QuoteProtection.splitLeadingQuote(transcript) {
            // Quote-only capture (no ramble yet): nothing the LLM may touch.
            guard !split.ramble.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return transcript
            }
            let editedRamble = try await editProse(split.ramble, generate: generate)
            let rejoined = QuoteProtection.reassemble(quote: split.quote, ramble: editedRamble)
            guard QuoteProtection.leadingQuoteIntact(original: transcript, edited: rejoined) else {
                return transcript
            }
            return rejoined
        }
        return try await editProse(transcript, generate: generate)
    }

    /// The plain copy-edit body path: memo-links escrow to their plain titles and image
    /// markers strip to anchors → `generate` → both come back in. A link whose title
    /// didn't survive the edit falls the WHOLE body back to unedited (never ship a lost
    /// reference — the QuoteProtection pattern). Mirrors `EnhancementService.editProse`.
    private static func editProse(_ text: String,
                                  generate: (String) async throws -> String) async throws -> String {
        let (linkStripped, links) = MemoLinkSyntax.escrowForEditing(text)
        let (stripped, imgNums, anchors) = ImageMarkerReinsert.extractAnchors(linkStripped)
        let input = imgNums.isEmpty ? linkStripped : stripped
        let edited = try await generate(input)
        let withImages = imgNums.isEmpty ? edited
            : ImageMarkerReinsert.reinsert(text: edited, imgNums: imgNums, anchors: anchors)
        guard let reattached = MemoLinkSyntax.reattach(edited: withImages, links: links) else {
            return text
        }
        return reattached
    }

    /// Title + summary read a link-stripped transcript (image markers are meaningless in a
    /// short generated line) — mirrors the desktop `title`/`summary` inputs.
    static func plainForTitleSummary(_ transcript: String) -> String {
        MemoLinkSyntax.escrowForEditing(transcript).text
    }

    /// The Mac's summary rule (`BatchRunner` reads `settings.effectiveSummaryMinWords`,
    /// default 75): a brief memo gets no summary. The title always runs — matching the Mac,
    /// which sets `titleSuggested` unconditionally.
    static let summaryMinWords = 75

    static func wordsMeetSummaryThreshold(_ transcript: String) -> Bool {
        transcript.split(whereSeparator: \.isWhitespace).count >= summaryMinWords
    }
}
