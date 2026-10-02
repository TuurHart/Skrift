import SwiftUI
import SwiftData

/// An unrated memo, open in the detail pane as a NORMAL note.
///
/// This view renders nothing itself — that is the entire point. It resolves the memo,
/// projects it into the type the note view already reads (`MemoNoteProjection`), hands
/// it to the SAME `NoteDisplayView` every other note goes through, and mirrors edits
/// back onto the memo. Tuur, after two attempts that each built a look-alike renderer:
/// *"make an unrated note identical to other notes"* — so there is no second renderer
/// to drift, only a different source for the same one.
///
/// Rating it here is the ordinary significance control doing the ordinary thing: the
/// write flags the memo, the reconcile sweep ingests it into a real `PipelineFile`, and
/// the shell's `@Query` hands the pane over to that row. "The rating IS the flag" is untouched.
struct UnratedNotePane: View {
    let memoID: String
    var coordinator: ProcessingCoordinator
    /// A memo-link chip inside the body pointed at another note.
    var onOpenMemo: (String) -> Void = { _ in }
    /// The sidebar's live search text — an unrated note opened from a search result
    /// scrolls to the match and flashes it, exactly like a pipelined one (Tuur:
    /// "should flash"). Reading your own note back is never gated on the rating.
    var searchQuery: String = ""
    /// The Mac's new-note draft (new note button / Cmd-N). While `memoID` is the draft's id and no
    /// `Memo` exists yet, the pane edits a transient projection, and the FIRST non-empty edit
    /// creates the Memo with that same id (`commit`), so the open note never changes identity
    /// under the cursor and an untouched note leaves nothing behind (C43/D91).
    var draft: MacTypedNoteSession? = nil
    /// Put the cursor in the body once for this note (a new note opens ready to type, C112).
    var focusBody: Bool = false

    @State private var projection: PipelineFile?
    @State private var memo: Memo?
    @State private var loaded = false

    var body: some View {
        Group {
            if let projection {
                NoteDisplayView(file: projection, coordinator: coordinator,
                                onOpenMemo: onOpenMemo,
                                searchQuery: searchQuery,
                                focusBodyToken: focusBody ? "new-note:\(memoID)" : nil)
                    // The note view edits the projection; these put those edits on the
                    // memo, which is the real record. Cheap value compares — SwiftData
                    // models are Observable, so each fires only on an actual change.
                    .onChange(of: projection.enhancedTitle) { commit() }
                    .onChange(of: projection.transcript) { commit() }
                    .onChange(of: projection.tags) { commit() }
                    .onChange(of: projection.significance) { _, new in
                        commit()
                        // A rating pipelines the memo: kick the sweep that ingests it; the
                        // shell follows it to its new row when the `@Query` yields it.
                        if NoteConsent.isRated(new) {
                            // It's pipelining: the real ingest folder takes over, so
                            // the materialised cache copy is dropped.
                            if let uuid = UUID(uuidString: memoID) {
                                MemoNoteProjection.discardMedia(for: uuid)
                            }
                            MemoCloudReconciler.reconcileSoon()
                        }
                    }
            } else if loaded {
                missing
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .task(id: memoID) { load() }
        .accessibilityIdentifier("unrated-note-pane")
    }

    private var missing: some View {
        VStack(spacing: 6) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 30)).foregroundStyle(Theme.textMuted.opacity(0.4))
            Text("This note may have been removed.")
                .font(.system(size: 14)).foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() {
        loaded = false
        projection = nil
        memo = nil
        defer { loaded = true }
        guard let uuid = UUID(uuidString: memoID),
              let ctx = MemoCloudStore.container?.mainContext else { return }
        guard let found = MemoCloudStore.memo(id: uuid, context: ctx) else {
            // A new note nobody has typed in: no Memo exists. Show the empty note through the
            // ordinary projection; `commit` creates the row on the first keystroke.
            if let draft, draft.isDraft(memoID), let blank = draft.placeholder() {
                projection = MemoNoteProjection.file(for: blank)
            }
            return
        }
        memo = found
        let pf = MemoNoteProjection.file(for: found)
        // Audio, photos and word timings out of the synced blobs — an unrated note
        // plays, shows its pictures and reads along like any other note. Everything
        // it needs already synced; only the files were missing.
        MemoNoteProjection.materialiseMedia(for: found, into: pf) {
            let mid = found.id
            let photoKind = MemoAsset.Kind.photo
            let audioKind = MemoAsset.Kind.audio
            let timingKind = MemoAsset.Kind.wordTimings
            return (try? ctx.fetch(FetchDescriptor<MemoAsset>(predicate: #Predicate {
                $0.memoID == mid && ($0.kind == photoKind || $0.kind == audioKind || $0.kind == timingKind)
            }))) ?? []
        }
        projection = pf
    }

    /// Mirror the projection's current values onto the memo and save.
    private func commit() {
        guard let projection else { return }
        if memo == nil, let draft, draft.isDraft(memoID), let ctx = MemoCloudStore.container?.mainContext {
            // First edit of a new note: only text creates the row (a rating or tag picked
            // first rides along onto it, like the phone's quick note).
            let title = (projection.enhancedTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let created = draft.edited(title: title, body: projection.transcript ?? "",
                                             tags: projection.tags,
                                             significance: projection.significance ?? 0,
                                             context: ctx) else { return }
            memo = created
            NotificationCenter.default.post(name: .cloudMemosDidChangeFromSync, object: nil)
        }
        guard let memo, MemoNoteProjection.writeBack(projection, to: memo) else { return }
        try? MemoCloudStore.container?.mainContext.save()
    }
}
