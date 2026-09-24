import SwiftUI
import UIKit

/// The quick-note body — a bare `UITextView` (no photos, no karaoke, no memo-link
/// resolution: those all assume a real synced `Memo`, which a draft doesn't have
/// until the first keystroke). It exists so the screen can carry the SAME keyboard
/// accessory pill (`NoteAccessoryBar`) as the real note editor (signed mock
/// `quick-note.html`) instead of the plain system strip a bare SwiftUI `TextEditor`
/// leaves behind. Undo/redo are wired to the text view's own `UndoManager`; the
/// checklist/photo/link/find glyphs sit inert here (no attachment/link plumbing to
/// aim them at pre-Memo) but keep the row's shape identical to the real editor's.
struct QuickNoteBodyTextView: UIViewRepresentable {
    @Binding var text: String
    var isFocused: Bool
    var onFocusChange: (Bool) -> Void

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = .systemFont(ofSize: 17)
        tv.backgroundColor = .clear
        tv.textColor = UIColor(Color.skText)
        tv.tintColor = UIColor(Color.skAccent)
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.alwaysBounceVertical = true
        tv.accessibilityIdentifier = "quick-note-body-textview"

        let bar = NoteAccessoryBar()
        bar.onUndo = { [weak tv] in tv?.undoManager?.undo() }
        bar.onRedo = { [weak tv] in tv?.undoManager?.redo() }
        bar.onDone = { [weak tv] in tv?.resignFirstResponder() }
        tv.inputAccessoryView = bar
        context.coordinator.accessoryBar = bar

        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text { tv.text = text }
        if isFocused, !tv.isFirstResponder {
            tv.becomeFirstResponder()
        } else if !isFocused, tv.isFirstResponder {
            tv.resignFirstResponder()
        }
        context.coordinator.accessoryBar?.refresh(
            canUndo: tv.undoManager?.canUndo ?? false,
            canRedo: tv.undoManager?.canRedo ?? false)
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, onFocusChange: onFocusChange) }

    final class Coordinator: NSObject, UITextViewDelegate {
        let text: Binding<String>
        let onFocusChange: (Bool) -> Void
        weak var accessoryBar: NoteAccessoryBar?

        init(text: Binding<String>, onFocusChange: @escaping (Bool) -> Void) {
            self.text = text
            self.onFocusChange = onFocusChange
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
            accessoryBar?.refresh(canUndo: textView.undoManager?.canUndo ?? false,
                                   canRedo: textView.undoManager?.canRedo ?? false)
        }

        func textViewDidBeginEditing(_ textView: UITextView) { onFocusChange(true) }
        func textViewDidEndEditing(_ textView: UITextView) { onFocusChange(false) }
    }
}
