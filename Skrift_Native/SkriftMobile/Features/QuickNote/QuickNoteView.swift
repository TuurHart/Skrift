import SwiftUI
import SwiftData

/// The quick-note screen (signed mock `mocks/quick-note.html`, C112/C114/C43,
/// D134/D135): an empty note, cursor in the body, keyboard up — reached from
/// the app's own ✎, the Lock Screen widget, Control Center, or Siri ("New
/// note in Skrift"). No `Memo` exists until the first keystroke
/// (`QuickNoteDraft`); an untouched-when-left note is discarded silently
/// (no toast, no undo — D91/C43) and never listed.
///
/// Q43: this is now the SAME chrome as the real note editor
/// (`MemoDetailView`'s compact nav bar + `NoteAccessoryBar` keyboard
/// accessory) instead of a bespoke bare title+TextEditor screen — the mock
/// draws the app's normal note screen, not a stripped-down one. What still
/// differs on purpose: no player, no photos, no memo-link/karaoke — a draft
/// has no audio and isn't a real `Memo` until the first keystroke, so those
/// stay gone until `MemoDetailView` takes over (reopening from the list uses
/// the full editor like any other typed note).
struct QuickNoteView: View {
    /// Navigation token only — never a real `Memo.id` until `QuickNoteDraft`
    /// creates one. Lets `MemosListView` route THIS screen instead of
    /// `MemoDetailView` for the id it pushed/selected.
    let draftID: UUID
    /// Tapping back: the caller decides what "leaving" means for its own
    /// navigation (pop the compact path / clear the iPad selected pane). The
    /// save-or-discard decision itself happens in `onDisappear`, below, so it
    /// fires no matter how the screen goes away.
    var onLeave: () -> Void

    @Environment(\.modelContext) private var context
    @FocusState private var titleFocused: Bool
    @State private var title = ""
    @State private var bodyText = ""
    /// D134: cursor lands in the body on open, not the title.
    @State private var bodyFocused = true
    @State private var draft = QuickNoteDraft()
    @State private var showAppendRecorder = false
    @State private var showDeleteConfirm = false
    /// D145 (build-172 feel check, "just a text field seems strange"): the
    /// full note screen shows date/tags/importance from the moment it opens
    /// — before any `Memo` exists (D91 still gates creation on the first
    /// TEXT keystroke), so these are plain local state, carried onto the
    /// row the instant `QuickNoteDraft` creates it (`seedTags`/
    /// `seedSignificance`) and written straight through once it exists.
    @State private var tags: [String] = []
    @State private var significance: Double = 0
    @State private var tagToast: TagEditorRow.TagToast?
    private let repository = NotesRepository.shared
    /// Q53/C277/C282: `draft.edited()` (a SwiftData save + a full-note hash,
    /// `EditConflicts.hash`) used to run on EVERY keystroke, unlike the real
    /// editor's 1 s debounced commit. Same coalescing here — the FIRST
    /// keystroke still creates the Memo immediately (D91: "the first
    /// keystroke", and the ✎ trailing buttons key off `draft.memo != nil`),
    /// every keystroke after that is debounced.
    @State private var commitDebouncer = CommitDebouncer()

    var body: some View {
        // NOT a SwiftUI `ScrollView` around the body: `QuickNoteBodyTextView`
        // is its own natively-scrolling `UITextView` (same reasoning as the
        // real editor, `NoteBodyView` — "the text view owns its scrolling"),
        // and nesting it inside another scroll view fights it for the pan
        // gesture. The chrome above sits at its fixed height; the body fills
        // whatever's left, exactly as before Q47's date/tags/importance row.
        VStack(alignment: .leading, spacing: 0) {
            dateChip
            titleField
            TagEditorRow(tags: $tags, library: repository.allTags(), style: .phone,
                         onChanged: syncMetaToMemo, idSuffix: "",
                         onToast: { tagToast = $0 })
                .padding(.top, 8)
            SignificanceCircles(value: $significance, onCommit: syncMetaToMemo)
                .padding(.top, 14)
            bodyEditor
                .padding(.top, 14)
        }
        .padding(.horizontal, Theme.Space.margin)
        .padding(.top, 8)
        .background(Color.skBg.ignoresSafeArea())
        .overlay(alignment: .bottom) { tagToastView }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { onLeave() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.skAccent)
                }
                .accessibilityIdentifier("quick-note-back")
                .accessibilityLabel("Back to Notes")
            }
            // The trail (add-recording / actions) only makes sense once a real
            // `Memo` exists — before the first keystroke there's nothing yet to
            // append audio to or act on.
            ToolbarItem(placement: .topBarTrailing) {
                if draft.memo != nil {
                    Button { showAppendRecorder = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.skTextDim)
                    }
                    .accessibilityIdentifier("quick-note-add-recording")
                    .accessibilityLabel("Add recording")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if draft.memo != nil {
                    Button { showDeleteConfirm = true } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.skTextDim)
                    }
                    .accessibilityIdentifier("quick-note-menu")
                }
            }
        }
        .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteAndLeave() }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showAppendRecorder) {
            if let memo = draft.memo { RecordView(appendTo: memo.id) }
        }
        .onDisappear {
            // Flush any pending debounced save first — `leave`'s empty check
            // must see the latest typed text, not a stale pre-debounce value.
            commitDebouncer.flush { commitEdit() }
            draft.leave(context: context)
        }
    }

    private var titleField: some View {
        TextField("", text: $title, prompt: Text("Add a title").foregroundStyle(Color.skTextFaint))
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(Color.skText)
            .tint(.skAccent)
            .submitLabel(.next)
            .onSubmit { titleFocused = false; bodyFocused = true }
            .focused($titleFocused)
            .onChange(of: titleFocused) { _, focused in if focused { bodyFocused = false } }
            .onChange(of: title) { _, _ in scheduleEdit() }
            .padding(.top, 8)
            .padding(.bottom, 4)
            .accessibilityIdentifier("quick-note-title")
    }

    private var bodyEditor: some View {
        QuickNoteBodyTextView(text: $bodyText, isFocused: bodyFocused) { focused in
            bodyFocused = focused
            if focused { titleFocused = false }
        }
        .onChange(of: bodyText) { _, _ in scheduleEdit() }
        .accessibilityIdentifier("quick-note-body")
    }

    /// D145: the date the real editor's header would show for a note
    /// recorded right now — same wording (`MemoDate.label`), no `Memo`
    /// needed since it's always "now" for a note that doesn't exist yet.
    private var dateChip: some View {
        ContextChip(text: MemoDate.label(Date()), systemImage: nil)
            .accessibilityIdentifier("quick-note-date")
    }

    /// Tags/importance are editable from the first frame, before any `Memo`
    /// exists. Once `QuickNoteDraft` has created one (title/body seeded it
    /// already — see the `onChange` handlers above), every further tag/
    /// importance change writes straight through so it isn't lost if the
    /// user only ever touches these controls after that first keystroke.
    private func syncMetaToMemo() {
        guard let memo = draft.memo else { return }
        memo.tags = tags
        memo.significance = significance
        memo.markEdited()
        try? context.save()
    }

    @ViewBuilder private var tagToastView: some View {
        if let toast = tagToast {
            TagUndoToastView(tag: toast.tag, style: .phone, onUndo: {
                toast.undo()
                withAnimation(Theme.Motion.spring) { tagToast = nil }
            })
            .padding(.bottom, bodyFocused ? 6 : 96)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: toast.id) {
                try? await Task.sleep(for: .seconds(4))
                if tagToast?.id == toast.id { withAnimation(Theme.Motion.spring) { tagToast = nil } }
            }
        }
    }

    private func deleteAndLeave() {
        commitDebouncer.cancel()   // a stale pending save must not resurrect the draft
        draft.discard(context: context)
        onLeave()
    }

    /// Title/body `onChange`: create the Memo on the very FIRST keystroke (D91,
    /// unchanged), debounce every save after that (Q53/C277/C282).
    private func scheduleEdit() {
        if draft.memo == nil {
            commitEdit()
            return
        }
        commitDebouncer.schedule { commitEdit() }
    }

    private func commitEdit() {
        draft.edited(title: title, body: bodyText, context: context,
                     seedTags: tags, seedSignificance: significance)
    }
}
