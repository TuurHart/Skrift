import Foundation

/// Audiobook quote-capture — quote protection (backlog spec 8, contract C1).
///
/// A capture memo's transcript opens with the captured quote as markdown
/// blockquote lines ("> " prefix), then a blank line, then the user's ramble
/// (contract C1; the phone writes no `[[ ]]` and no attribution — the Mac owns
/// both). The quote is the author's literal words and must reach the export
/// BYTE-IDENTICAL, so it never goes through the LLM: the copy-edit path strips
/// the leading block (the same strip/reinsert idea as `ImageMarkerReinsert`),
/// edits only the ramble, reinserts the quote, and then BYTE-ASSERTS it — any
/// mismatch falls back to the fully-unedited body (skip-all), the same way
/// conversation-mode transcripts already skip copy-edit. Pure + host-testable.
enum QuoteProtection {
    struct Split: Equatable, Sendable {
        /// The leading blockquote block, byte-exact as it appears in the text
        /// (no trailing newline).
        var quote: String
        /// Everything after the block, with the separating blank lines dropped.
        var ramble: String
    }

    /// Splits a C1 capture body into its leading quote block + ramble. Returns nil when the
    /// text doesn't OPEN with a non-empty blockquote — ASR output never does, so plain memos
    /// take the normal path untouched. C172: this is an ADAPTER over `CaptureQuote.split`,
    /// the one splitter, not a parser of its own — so a body that DISPLAYS as a quote
    /// (leading blank lines, an indented `>`) is also copy-edit protected, name-link
    /// protected and exported as a quote. The quote keeps its exact bytes (leading blanks
    /// and indent included); only the blank separator after it is dropped.
    static func splitLeadingQuote(_ text: String) -> Split? {
        guard let split = CaptureQuote.split(text) else { return nil }
        return Split(quote: split.quoteBlock, ramble: split.ramble)
    }

    /// Puts the (untouched) quote back on top of the edited ramble in C1 shape.
    static func reassemble(quote: String, ramble: String) -> String {
        ramble.isEmpty ? quote : quote + "\n\n" + ramble
    }

    /// The byte-identical assert (spec 8's safety net): if `original` opens with
    /// a C1 quote block, `edited` must open with the very same bytes. An edited
    /// ramble that itself begins with ">" extends the re-extracted block and
    /// fails here — exactly the corruption this guards against. Texts without a
    /// leading quote pass trivially.
    static func leadingQuoteIntact(original: String, edited: String) -> Bool {
        guard let orig = splitLeadingQuote(original) else { return true }
        guard let ed = splitLeadingQuote(edited) else { return false }
        return Array(orig.quote.utf8) == Array(ed.quote.utf8)
    }
}
