import Foundation
import SwiftData

/// The lazy-creation + silent-discard core of the quick-note screen, SHARED by the phone's
/// quick note and the Mac's ✎/⌘N (C43/D91, D134/D135 — signed mock `quick-note.html`). Kept UI-free
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

    /// D151/Q73: a typed note records place, weather and daypart like a voice
    /// recording. `nil` (the default) captures nothing, which keeps unit tests off
    /// the sensors and the network; `QuickNoteView` passes the real provider.
    private let metadataProvider: (any MetadataProviding)?
    /// The in-flight capture for the current note. Started once, at creation, and never
    /// awaited by the keyboard path (C112). Internal so tests can await it.
    private(set) var captureTask: Task<Void, Never>?

    /// The id the `Memo` is born with (nil = a fresh one). The Mac mints it at the click, so the
    /// open pane's id is already the note's id when the first keystroke creates the row.
    private let id: UUID?

    init(metadataProvider: (any MetadataProviding)? = nil, id: UUID? = nil) {
        self.metadataProvider = metadataProvider
        self.id = id
    }

    /// Call on every title/body change. A no-op until the first non-empty
    /// edit; from then on keeps the created `Memo` in sync.
    ///
    /// `seedTags`/`seedSignificance` (Q47/D145): the quick note now shows
    /// tags + importance chrome from the moment it opens, before any Memo
    /// exists (a plain local `@State` on the screen). Only TEXT creates the
    /// row (D91 stays literal — "the first keystroke"), but whatever the
    /// user had already picked before typing a word rides along onto the
    /// row the instant it's born, instead of silently resetting to nothing.
    @discardableResult
    func edited(title: String, body: String, context: ModelContext,
                seedTags: [String] = [], seedSignificance: Double = 0,
                seedDestination: NoteDestination = .personal) -> Memo? {
        if memo == nil {
            guard !title.isEmpty || !body.isEmpty else { return nil }
            memo = try? Memo.newTyped(into: context, id: id ?? UUID())
            memo?.tags = seedTags
            memo?.significance = seedSignificance
            memo?.destination = seedDestination
            if let memo { startCapture(for: memo) }
        }
        guard let memo else { return nil }
        memo.title = title.isEmpty ? nil : title
        memo.transcript = body.isEmpty ? nil : body
        memo.markEdited()
        try? context.save()
        return memo
    }

    /// Fire-and-forget: the note and its keyboard exist first, the place lands a moment
    /// later. A nil fix / geocode just leaves those fields nil (`LocationOneShot` drops
    /// them silently). A kept note still receives its place after the screen is left; a
    /// discarded one cancels the task.
    private func startCapture(for memo: Memo) {
        guard let metadataProvider else { return }
        captureTask = Task { @MainActor in
            let captured = await metadataProvider.capture()
            // Cancelled = the note was discarded while the fix was in flight.
            guard !Task.isCancelled else { return }
            memo.mergeCapturedMetadata(captured)
            try? memo.modelContext?.save()
        }
    }

    /// Leaving the screen (D91/C43): a `Memo` that got created but is still
    /// empty at the moment of leaving — typed something then deleted it all
    /// counts as empty too — is discarded silently: no toast, no undo, never
    /// listed. Never typed at all → `memo` is nil → nothing to do.
    func leave(context: ModelContext) {
        guard let memo else { return }
        let empty = isBlank(memo.title) && isBlank(memo.transcript)
        if empty {
            captureTask?.cancel()
            context.delete(memo)
            try? context.save()
        }
        self.memo = nil
    }

    /// Explicit delete (the note screen's own ⋯ → Delete) — unlike `leave`,
    /// this discards a NON-empty note too, and only on the user's own request.
    func discard(context: ModelContext) {
        captureTask?.cancel()
        if let memo { context.delete(memo) }
        try? context.save()
        memo = nil
    }

    private func isBlank(_ s: String?) -> Bool {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
