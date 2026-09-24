import SwiftUI
import SwiftData

/// The quick-note screen (signed mock `mocks/quick-note.html`, C112/C114/C43,
/// D134/D135): an empty note, cursor in the body, keyboard up — reached from
/// the app's own ✎, the Lock Screen widget, Control Center, or Siri ("New
/// note in Skrift"). No `Memo` exists until the first keystroke
/// (`QuickNoteDraft`); an untouched-when-left note is discarded silently
/// (no toast, no undo — D91/C43) and never listed.
///
/// A lightweight editor on purpose — once a keystroke lands and the `Memo` is
/// real, reopening it from the list uses the full `MemoDetailView` like any
/// other typed note.
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
    @FocusState private var focused: Field?
    @State private var title = ""
    @State private var body = ""
    @State private var draft = QuickNoteDraft()

    private enum Field { case title, body }

    var body: some View {
        ZStack(alignment: .top) {
            Color.skBg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 6) {
                Spacer().frame(height: 40)   // clears the back bar overlay
                TextField("", text: $title, prompt: Text("Add a title").foregroundStyle(Color.skTextFaint))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.skText)
                    .tint(.skAccent)
                    .submitLabel(.next)
                    .onSubmit { focused = .body }
                    .focused($focused, equals: .title)
                    .onChange(of: title) { _, v in draft.edited(title: v, body: body, context: context) }
                    .accessibilityIdentifier("quick-note-title")
                bodyEditor
            }
            .padding(.horizontal, Theme.Space.margin)
            backBar
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { focused = .body }   // D134: cursor lands in the body, not the title
        .onDisappear { draft.leave(context: context) }
        .accessibilityIdentifier("quick-note-view")
    }

    private var bodyEditor: some View {
        TextEditor(text: $body)
            .font(.system(size: 17))
            .foregroundStyle(Color.skText)
            .tint(.skAccent)
            .scrollContentBackground(.hidden)
            .focused($focused, equals: .body)
            .onChange(of: body) { _, v in draft.edited(title: title, body: v, context: context) }
            .accessibilityIdentifier("quick-note-body")
    }

    private var backBar: some View {
        HStack {
            Button { onLeave() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.skAccent)
                    .frame(width: 34, height: 34)
            }
            .accessibilityIdentifier("quick-note-back")
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }
}
