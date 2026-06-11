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

    /// Splits a C1 capture body into its leading quote block + ramble. Returns
    /// nil when the text doesn't OPEN with a blockquote line (`>` at offset 0) —
    /// ASR output never does, so plain memos take the normal path untouched.
    static func splitLeadingQuote(_ text: String) -> Split? {
        guard text.hasPrefix(">") else { return nil }
        let lines = text.components(separatedBy: "\n")
        var idx = 0
        while idx < lines.count, lines[idx].hasPrefix(">") { idx += 1 }
        let quote = lines[..<idx].joined(separator: "\n")
        var rest = Array(lines[idx...])
        while let first = rest.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            rest.removeFirst()
        }
        return Split(quote: quote, ramble: rest.joined(separator: "\n"))
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
