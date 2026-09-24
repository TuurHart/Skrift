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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            titleField
            bodyEditor
        }
        .padding(.horizontal, Theme.Space.margin)
        .padding(.top, 8)
        .background(Color.skBg.ignoresSafeArea())
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
        .onDisappear { draft.leave(context: context) }
        .accessibilityIdentifier("quick-note-view")
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
            .onChange(of: title) { _, v in draft.edited(title: v, body: bodyText, context: context) }
            .padding(.top, 8)
            .padding(.bottom, 4)
            .accessibilityIdentifier("quick-note-title")
    }

    private var bodyEditor: some View {
        QuickNoteBodyTextView(text: $bodyText, isFocused: bodyFocused) { focused in
            bodyFocused = focused
            if focused { titleFocused = false }
        }
        .onChange(of: bodyText) { _, v in draft.edited(title: title, body: v, context: context) }
        .accessibilityIdentifier("quick-note-body")
    }

    private func deleteAndLeave() {
        draft.discard(context: context)
        onLeave()
    }
}
