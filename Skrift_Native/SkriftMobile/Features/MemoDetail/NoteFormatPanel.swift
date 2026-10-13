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
    /// `.phone` = D115's set under the keyboard; `.full` = the Mac's full list (D197,
    /// `FormatCommand`'s Aa groups) in the iPad's Aa popover (Q379, mock Q378).
    enum ItemSet { case phone, full }

    @ObservedObject var state: EditorFormatState
    var items: ItemSet = .phone
    var onStyle: (BodyFormat.LineStyle) -> Void
    var onMark: (BodyFormat.InlineMark) -> Void
    var onMonostyled: () -> Void = {}
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
            if items == .full { fullList } else { phoneList }
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.skSurface)
        // .contain keeps the container's id off its buttons (a bare id on a stack stamped
        // 'format-panel' on every child, so 'format-B' was never findable).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("format-panel")
    }

    /// D197: B I U S + highlight; Title, Heading, Subheading, Body, Monostyled; the three lists;
    /// Block Quote — each captioned with the Markdown it writes.
    @ViewBuilder private var fullList: some View {
        HStack(spacing: 6) {
            ForEach(FormatCommand.aaMarks, id: \.self) { cmd in
                if let mark = cmd.mark {
                    markButton(mark, cmd.shortTitle, cmd.markdownHint) { Self.markLook($0, mark) }
                }
            }
        }
        VStack(spacing: 0) {
            ForEach(Array(FormatCommand.aaStyles.enumerated()), id: \.offset) { i, cmd in
                if i > 0 { Rectangle().fill(Color.skBorder).frame(height: 0.5) }
                styleRow(cmd)
            }
        }
        .background(Color.skElev, in: .rect(cornerRadius: 12, style: .continuous))
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        HStack(spacing: 6) {
            ForEach(FormatCommand.aaLists, id: \.self) { cmd in commandButton(cmd) }
        }
        ForEach(FormatCommand.aaTail, id: \.self) { cmd in commandButton(cmd) }
        Text("Written as Markdown in the note. No colour.")
            .font(.system(size: 11.5)).foregroundStyle(Color.skTextDim)
    }

    @ViewBuilder private var phoneList: some View {
            // Q380: D115's subset of the ONE shared table (`FormatCommand.phone*`); only the
            // button faces are the phone's.
            HStack(spacing: 6) {
                ForEach(FormatCommand.phoneStyles, id: \.self) { cmd in
                    if let style = cmd.lineStyle {
                        styleButton(style, cmd.shortTitle, cmd.markdownHint, Self.styleFace(cmd))
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(FormatCommand.phoneMarks, id: \.self) { cmd in
                    if let mark = cmd.mark {
                        markButton(mark, cmd.shortTitle, cmd.markdownHint) { Self.markLook($0, mark) }
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(FormatCommand.phoneLists, id: \.self) { cmd in
                    if let style = cmd.lineStyle {
                        styleButton(style, cmd.shortTitle, cmd.markdownHint, .system(size: 13.5))
                    }
                }
            }
            Text("Acts on the caret’s line. B I U S act on the selected words.")
                .font(.system(size: 11.5)).foregroundStyle(Color.skTextDim)
    }

    // MARK: the full set's pieces (Q379)

    /// The phone row's style buttons wear their own size (the look stays local).
    private static func styleFace(_ cmd: FormatCommand) -> Font {
        switch cmd {
        case .title: return .system(size: 17, weight: .bold)
        case .heading: return .system(size: 15, weight: .bold)
        default: return .system(size: 14)
        }
    }

    private static func markLook(_ t: Text, _ mark: BodyFormat.InlineMark) -> Text {
        switch mark {
        case .bold: return t.font(.system(size: 16, weight: .heavy))
        case .italic: return t.font(.custom("Georgia-Italic", size: 16))
        case .underline: return t.font(.system(size: 16)).underline()
        case .strike: return t.font(.system(size: 16)).strikethrough()
        default: return t.font(.system(size: 13, weight: .semibold))
        }
    }

    private func isOn(_ cmd: FormatCommand) -> Bool {
        guard let style = cmd.lineStyle else { return false }
        return state.lineStyle == style
    }

    private func run(_ cmd: FormatCommand) {
        if let style = cmd.lineStyle { onStyle(style) }
        else if cmd == .monostyled { onMonostyled() }
        else if let mark = cmd.mark { onMark(mark) }
    }

    private func styleRow(_ cmd: FormatCommand) -> some View {
        let on = isOn(cmd)
        let font: Font = {
            switch cmd {
            case .title: return .system(size: 22, weight: .bold)
            case .heading: return .system(size: 18, weight: .bold)
            case .subheading: return .system(size: 16, weight: .semibold)
            case .monostyled: return .system(size: 14, design: .monospaced)
            default: return .system(size: 15)
            }
        }()
        return Button { run(cmd) } label: {
            HStack(spacing: 10) {
                Text(cmd.title).font(font)
                Spacer(minLength: 0)
                Text(cmd.markdownHint)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(on ? Color.skAccentText : Color.skTextFaint)
            }
            .foregroundStyle(on ? Color.skAccent : Color.skText)
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(on ? Color.skAccentSoft : Color.clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("format-\(cmd.title)")
    }

    private func commandButton(_ cmd: FormatCommand) -> some View {
        let glyph: String = {
            switch cmd {
            case .bulletList: return "• "
            case .dashedList: return "– "
            case .numberedList: return "1. "
            case .blockQuote: return "❝ "
            default: return ""
            }
        }()
        return Button { run(cmd) } label: {
            cell(on: isOn(cmd)) {
                Text(glyph + cmd.title).font(.system(size: 13.5)).lineLimit(1).minimumScaleFactor(0.85)
                Text(cmd.markdownHint).font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(isOn(cmd) ? Color.skAccentText : Color.skTextFaint)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("format-\(cmd.title)")
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
