import Foundation

/// C152 / C223: text appended to a POLISHED note. Every screen shows the polish
/// (`MemoEnhancement.copyedit`) when there is one, so an append that wrote only the raw
/// transcript was invisible. The append now lands in BOTH: the raw transcript (the contract
/// spine) and the shown polished body, where the new raw block is remembered as `pending`.
/// The next pass copy-edits only that block and splices it back in place of the raw tail, so
/// the earlier polish stays exactly as it was. Pure values, one copy for both apps.
enum AppendPolish {

    /// Does this polish have a body the append must join? A title-only polish shows the raw
    /// transcript, which already carries the new words.
    static func showsPolishedBody(_ copyedit: String) -> Bool {
        !copyedit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The phone's join: the body, a blank line, the new block (C223). An empty side drops out.
    static func joined(_ body: String, _ block: String) -> String {
        let a = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = block.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + "\n\n" + b
    }

    /// Append `block` to the shown polished body. `needsPolish` false (pictures alone) joins the
    /// body without asking a pass for anything.
    static func appended(copyedit: String, pending: String, block: String,
                         needsPolish: Bool = true) -> (copyedit: String, pending: String) {
        (joined(copyedit, block), needsPolish ? joined(pending, block) : pending)
    }

    /// The pass: `polished` (the copy-edit of `pending` alone) replaces the raw tail. Returns
    /// nil when the body no longer ends with the pending words (he edited them where they
    /// show: they are his now, so the pass leaves the body alone). An empty `polished` keeps
    /// the raw words.
    static func splice(copyedit: String, pending: String, polished: String) -> String? {
        let body = copyedit.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = pending.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, body.hasSuffix(raw) else { return nil }
        let clean = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(body.dropLast(raw.count)) + (clean.isEmpty ? raw : clean)
    }
}

extension MemoEnhancement {
    /// Join an appended block onto this polish (see `AppendPolish`), stamped as `deviceID`'s
    /// edit so it syncs. A polish with no body is left alone: the raw already shows the words.
    func appendBlock(_ block: String, needsPolish: Bool = true, deviceID: String, now: Date = Date()) {
        guard AppendPolish.showsPolishedBody(copyedit),
              !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        (copyedit, pendingBlock) = AppendPolish.appended(copyedit: copyedit, pending: pendingBlock,
                                                         block: block, needsPolish: needsPolish)
        enhancedByDeviceID = deviceID
        enhancedAt = now
    }
}
