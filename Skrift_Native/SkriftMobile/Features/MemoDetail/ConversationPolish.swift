import Foundation

/// Q509 (C47, C152): a conversation note shows the Mac's current polish too, so an edit he made
/// to a diarized note on the Mac reaches this view. A conversation's copy-edit is its turns,
/// de-linked turn by turn (`MacEditRoundTrip`), so it parses as turns and keeps the speaker
/// gutter. Stale or absent → the transcript, as for prose (`MemoEnhancement.current`); a polish
/// that is not turns never replaces them.
enum ConversationPolish {
    /// The polish whose turns this note shows; nil = show `memo.transcript`.
    static func shown(_ e: MemoEnhancement?, for memo: Memo) -> MemoEnhancement? {
        guard SpeakerTranscript.parse(memo.transcript) != nil,
              let e = MemoEnhancement.current(e, for: memo),
              SpeakerTranscript.parse(e.copyedit) != nil else { return nil }
        return e
    }

    /// The text the turns on screen come from.
    static func body(for memo: Memo, polish: MemoEnhancement?) -> String? {
        polish?.copyedit ?? memo.transcript
    }

    /// Write a turn edit to the text the turns came from, so a turn index always lands in the
    /// text it was counted in: the polish (stamped as this device's edit, like a polished prose
    /// edit) or the transcript (a raw edit, C153). True when anything changed; the caller saves.
    @discardableResult
    static func apply(_ edit: (String?) -> String?, to memo: Memo, polish: MemoEnhancement?,
                      device: String = DeviceID.current(), now: Date = Date()) -> Bool {
        if let e = polish {
            guard let updated = edit(e.copyedit), updated != e.copyedit else { return false }
            e.copyedit = updated
            e.enhancedByDeviceID = device
            e.enhancedAt = now
            return true
        }
        guard let updated = edit(memo.transcript), updated != memo.transcript else { return false }
        memo.transcript = updated
        memo.transcriptUserEdited = true       // Mac trusts the edited transcript
        memo.transcriptEditedAt = now          // C153: an older polish goes stale
        return true
    }
}
