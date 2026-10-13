import SwiftUI
import UIKit

/// What the open editor tells the chrome around it (Q359, mock Q350 pick 1): while typing,
/// undo / redo and Done sit in the top bar, as in Apple Notes; Find lives in the ⋯ menu.
/// The coordinator of the note on screen registers itself; the nav bar observes this.
@MainActor
final class NoteEditorChrome: ObservableObject {
    static let shared = NoteEditorChrome()
    @Published var isEditing = false
    @Published var canUndo = false
    @Published var canRedo = false
    /// The coordinator of the page on screen (set on every update of the current page).
    weak var current: NoteBodyView.Coordinator?

    func undo() { current?.undo() }
    func redo() { current?.redo() }
    func done() { current?.finishEditing() }
    func find() { current?.presentFind() }
}

/// The Aa panel's live state: which style the caret's line has, which marks the selection carries.
@MainActor
final class EditorFormatState: ObservableObject {
    @Published var lineStyle: BodyFormat.LineStyle = .body
    @Published var marks: Set<BodyFormat.InlineMark> = []
    @Published var hasSelection = false
}

/// The "Aa" Format panel (D115, signed mock Q350 state "Aa menu", D195 40 pt buttons): it
/// replaces the keyboard. Title · Heading · Body, B I U S, the three lists. Each button shows
/// the Markdown it writes as a small caption (C116: the body stays plain Markdown).
struct NoteFormatPanel: View {
    @ObservedObject var state: EditorFormatState
    var onStyle: (BodyFormat.LineStyle) -> Void
    var onMark: (BodyFormat.InlineMark) -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Format").font(.system(size: 17, weight: .bold)).foregroundStyle(Color.skText)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.skTextDim)
                        .frame(width: 28, height: 28)
                        .background(Color.skElev, in: Circle())
                }
                .accessibilityLabel("Close format")
                .accessibilityIdentifier("format-close")
            }
            HStack(spacing: 6) {
                styleButton(.title, "Title", "# ", .system(size: 17, weight: .bold))
                styleButton(.heading, "Heading", "## ", .system(size: 15, weight: .bold))
                styleButton(.body, "Body", "plain", .system(size: 14))
            }
            HStack(spacing: 6) {
                markButton(.bold, "B", "**…**") { $0.font(.system(size: 16, weight: .heavy)) }
                markButton(.italic, "I", "*…*") { $0.font(.custom("Georgia-Italic", size: 16)) }
                markButton(.underline, "U", "<u>…</u>") { $0.font(.system(size: 16)).underline() }
                markButton(.strike, "S", "~~…~~") { $0.font(.system(size: 16)).strikethrough() }
            }
            HStack(spacing: 6) {
                styleButton(.bullet, "• List", "- ", .system(size: 13.5))
                styleButton(.numbered, "1. List", "1. ", .system(size: 13.5))
                styleButton(.checklist, "☑ Checklist", "- [ ] ", .system(size: 13.5))
            }
            Text("Acts on the caret’s line. B I U S act on the selected words.")
                .font(.system(size: 11.5)).foregroundStyle(Color.skTextDim)
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.skSurface)
        .accessibilityIdentifier("format-panel")
    }

    private func styleButton(_ style: BodyFormat.LineStyle, _ label: String, _ hint: String, _ font: Font) -> some View {
        let on = state.lineStyle == style
        return Button { onStyle(style) } label: {
            cell(on: on) {
                Text(label).font(font)
                Text(hint).font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(on ? Color.skAccentText : Color.skTextFaint)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("format-\(label)")
    }

    private func markButton(_ mark: BodyFormat.InlineMark, _ label: String, _ hint: String,
                            _ look: (Text) -> Text) -> some View {
        let on = state.marks.contains(mark)
        return Button { onMark(mark) } label: {
            cell(on: on) {
                look(Text(label))
                Text(hint).font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(on ? Color.skAccentText : Color.skTextFaint)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("format-\(label)")
    }

    private func cell<C: View>(on: Bool, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .foregroundStyle(on ? Color.skAccent : Color.skText)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(on ? Color.skAccentSoft : Color.skElev, in: .rect(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(on ? Color.skAccent.opacity(0.35) : .clear, lineWidth: 1))
            .contentShape(.rect)
    }
}
