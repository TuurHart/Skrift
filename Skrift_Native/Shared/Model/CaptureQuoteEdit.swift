import Foundation

/// What an editor must do with one proposed edit to a body that may open with a quote block
/// (C172: the quote block of a capture is read-only; only the ramble edits). The phone gets
/// that by construction (its editor holds only the ramble and re-prepends `rawBlock`); the
/// Mac edits the whole body in one text view, so it asks this question per edit instead.
/// The block is found by `CaptureQuote.split` — there is no second splitter.
enum CaptureQuoteEdit: Equatable, Sendable {
    /// Apply the edit as proposed.
    case allow
    /// The edit touches the quote block: refuse it.
    case reject
    /// A first ramble typed at the end of a quote-only body: apply the edit, but with this
    /// separator in front, so the new text starts its own paragraph instead of extending the
    /// last quote line.
    case allowAfterSeparator(String)
}

extension CaptureQuote {
    /// UTF-16 length of the read-only prefix of `body`: the quote block, its blank separator
    /// line(s) and the newline that joins it to the ramble. 0 when the body has no leading
    /// quote. The ramble is an exact suffix of the body, so this is `body.length - ramble.length`.
    static func readOnlyLength(in body: String) -> Int {
        guard let split = split(body) else { return 0 }
        return (body as NSString).length - (split.ramble as NSString).length
    }

    /// Judge one edit — `range` replaced by `replacement` — against the body's quote block.
    /// `replacement == nil` is an attribute-only change (no characters move), always allowed.
    static func editVerdict(body: String, range: NSRange, replacement: String?) -> CaptureQuoteEdit {
        guard let replacement else { return .allow }
        let readOnly = readOnlyLength(in: body)
        guard readOnly > 0 else { return .allow }
        if range.location < readOnly { return .reject }
        let length = (body as NSString).length
        // First ramble on a quote-only body: keep it off the quote's last line.
        guard readOnly == length, range.location == length, range.length == 0,
              replacement.contains(where: { !$0.isWhitespace }) else { return .allow }
        let have = body.reversed().prefix(while: { $0 == "\n" }).count
            + replacement.prefix(while: { $0 == "\n" }).count
        return have >= 2 ? .allow : .allowAfterSeparator(String(repeating: "\n", count: 2 - have))
    }
}
