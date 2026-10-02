import Foundation
import UIKit

/// The ONE gated "copy this memo's transcript" action (R88/C213): every Copy
/// entry point — `workbenchChrome`'s ⋯-menu Copy, the ⋯ menu's
/// `noteOverflowItems` item, the compact-sheet "Copy transcript" (all through
/// `MemoDetailView.copyTranscript()`) and the notes-list long-press menu —
/// funnels through here, so gating it once covers all of them. The decision is
/// `CopyTranscriptRule` (Q180, shared with the Mac): a locked, not-yet-unlocked
/// memo ASKS for auth (Face ID) rather than silently doing nothing, a failed or
/// cancelled auth copies nothing, and an empty note says `emptyMessage`.
@MainActor
enum GatedCopy {
    /// `write` stays the FIRST closure parameter: existing callers use trailing-closure syntax.
    static func copyTranscript(_ memo: Memo, lockGate: LockGate = .shared,
                                write: (String) -> Void = { UIPasteboard.general.string = $0 },
                                onEmpty: () -> Void = {},
                                text: (Memo) -> String? = { $0.transcript }) async {
        var step = CopyTranscriptRule.step(needsAuth: lockGate.isLocked(memo), text: nil)
        if step == .authenticate {
            guard await lockGate.unlock(memo.id) else { return }
        }
        step = CopyTranscriptRule.step(needsAuth: false, text: text(memo))
        switch step {
        case .copy(let t): write(t)
        case .nothingToCopy: onEmpty()
        case .authenticate: break
        }
    }
}
