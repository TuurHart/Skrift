import Foundation
import SwiftData

/// The lazy-creation + silent-discard core of the quick-note screen
/// (C43/D91, D134/D135 — signed mock `quick-note.html`). Kept UI-free
/// (no SwiftUI) so `QuickNoteTests` can drive it directly without rendering.
///
/// `Memo.newTyped` saves eagerly today (the ✎/⌘N verb on both apps) — fine for
/// an author who's already deciding to keep a note, wrong for a screen that
/// opens EMPTY from a widget/Siri/Lock-Screen tap every time. This defers that
/// creation to the FIRST keystroke (title or body), so an untouched quick note
/// never becomes a `Memo` at all, and therefore never has a chance to sync an
/// empty row to the Mac before the leave-check below could delete it again.
@MainActor
final class QuickNoteDraft {
    private(set) var memo: Memo?

    /// Call on every title/body change. A no-op until the first non-empty
    /// edit; from then on keeps the created `Memo` in sync.
    @discardableResult
    func edited(title: String, body: String, context: ModelContext) -> Memo? {
        if memo == nil {
            guard !title.isEmpty || !body.isEmpty else { return nil }
            memo = try? Memo.newTyped(into: context)
        }
        guard let memo else { return nil }
        memo.title = title.isEmpty ? nil : title
        memo.transcript = body.isEmpty ? nil : body
        memo.markEdited()
        try? context.save()
        return memo
    }

    /// Leaving the screen (D91/C43): a `Memo` that got created but is still
    /// empty at the moment of leaving — typed something then deleted it all
    /// counts as empty too — is discarded silently: no toast, no undo, never
    /// listed. Never typed at all → `memo` is nil → nothing to do.
    func leave(context: ModelContext) {
        guard let memo else { return }
        let empty = isBlank(memo.title) && isBlank(memo.transcript)
        if empty {
            context.delete(memo)
            try? context.save()
        }
        self.memo = nil
    }

    /// Explicit delete (the note screen's own ⋯ → Delete) — unlike `leave`,
    /// this discards a NON-empty note too, and only on the user's own request.
    func discard(context: ModelContext) {
        if let memo { context.delete(memo) }
        try? context.save()
        memo = nil
    }

    private func isBlank(_ s: String?) -> Bool {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
