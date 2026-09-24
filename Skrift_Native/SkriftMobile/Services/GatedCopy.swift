import Foundation
import UIKit

/// The ONE gated "copy this memo's transcript" action (R88/C213): every Copy
/// entry point on the detail page — `workbenchChrome`'s ⋯-menu Copy, the ⋯
/// menu's `noteOverflowItems` item, and the compact-sheet "Copy transcript" —
/// all funnel through `MemoDetailView.copyTranscript()`, which calls here, so
/// gating it once covers all three. A locked, not-yet-unlocked-this-session
/// memo ASKS for auth (Face ID) rather than silently doing nothing; a failed
/// or cancelled auth copies nothing.
@MainActor
enum GatedCopy {
    static func copyTranscript(_ memo: Memo, lockGate: LockGate = .shared,
                                write: (String) -> Void = { UIPasteboard.general.string = $0 }) async {
        if lockGate.isLocked(memo) {
            guard await lockGate.unlock(memo.id) else { return }
        }
        guard let text = memo.transcript, !text.isEmpty else { return }
        write(text)
    }
}
