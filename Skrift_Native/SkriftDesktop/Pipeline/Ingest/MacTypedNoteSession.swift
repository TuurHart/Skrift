import Foundation
import SwiftData

/// The Mac's ✎/⌘N verb, run through the SAME draft rules as the phone's quick note
/// (`QuickNoteDraft`, Shared — C43/D91/D151). Clicking New note mints an id and opens an
/// empty pane; NO `Memo` exists until the first non-empty edit, and a note left empty is
/// deleted — so an untouched click never leaves a quiet 'Note' row that syncs to the phone.
///
/// Host-less like `MacMemoAuthor`: every entry point takes its `ModelContext`, and the
/// metadata provider is injected (a test passes a fake; the app passes `MacMetadataService`).
/// One session per window — at most one open draft; starting another leaves the first.
@MainActor
final class MacTypedNoteSession {
    private(set) var draft: QuickNoteDraft?
    private(set) var id: UUID?
    private let makeProvider: @MainActor () -> (any MetadataProviding)?

    init(metadataProvider: @escaping @MainActor () -> (any MetadataProviding)? = { MacMetadataService() }) {
        self.makeProvider = metadataProvider
    }

    /// The click. Leaves any earlier draft (discarding it if it is still empty), then
    /// mints the id the note will have. Creates nothing in `context`.
    @discardableResult
    func begin(context: ModelContext?) -> UUID {
        if let context { leave(context: context) }
        let new = UUID()
        id = new
        draft = QuickNoteDraft(metadataProvider: makeProvider(), id: new)
        return new
    }

    /// Is `noteID` the open draft's id?
    func isDraft(_ noteID: String?) -> Bool {
        guard let noteID, let id, draft != nil else { return false }
        return noteID == id.uuidString
    }

    /// An unattached `Memo` with the draft's id and the typed-note shape, so the pane can
    /// project it into the ordinary note view before the real row exists. Never inserted.
    func placeholder() -> Memo? {
        guard let id else { return nil }
        let marker = try? JSONSerialization.data(withJSONObject: ["mediaSource": "typed"],
                                                 options: [.sortedKeys])
        return Memo(id: id, transcriptStatus: .done, significance: 0, metadataData: marker)
    }

    /// Every title/body change. A no-op until the first non-empty edit, which creates the
    /// `Memo` (with the draft's id) and starts the place capture; afterwards keeps it in sync.
    /// What he typed himself is his words, so the transcript is marked user-edited (the
    /// same mark `MemoNoteProjection.writeBack` puts on a hand edit).
    @discardableResult
    func edited(title: String, body: String, tags: [String] = [], significance: Double = 0,
                context: ModelContext) -> Memo? {
        guard let draft else { return nil }
        draft.edited(title: title, body: body, context: context,
                     seedTags: tags, seedSignificance: significance)
        guard let memo = draft.memo else { return nil }
        if !body.isEmpty, !memo.transcriptUserEdited {
            memo.transcriptUserEdited = true
            try? context.save()
        }
        return memo
    }

    /// Leaving the note: a created-but-blank memo is deleted, an untouched draft never
    /// existed. Ends the draft either way.
    func leave(context: ModelContext) {
        draft?.leave(context: context)
        draft = nil
        id = nil
    }
}
