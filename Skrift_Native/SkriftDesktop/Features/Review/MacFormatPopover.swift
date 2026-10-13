import SwiftUI
import AppKit

/// Q360 (signed mock Q350 #m-note, Tuur 2026-10-13 "Apple's full list"): the band's one Aa
/// button and its popover. Apple Notes' order: B I U S | highlight; Title, Heading, Subheading,
/// Body (checked when current), Monostyled; Bulleted, Dashed, Numbered; a divider; Block Quote.
/// Each row shows in its own style. Every row sends its command to the focused note's text
/// (`FormatCommandBox`), so the edit is the shared `BodyFormat` Markdown and the marks stay dim.
struct MacAaButton: View {
    @State private var open = false
    @State private var checked: MacEditorFormatting.Command = .body

    var body: some View {
        Button {
            checked = Self.focusedText?.caretLineStyle ?? .body
            open.toggle()
        } label: {
            Text("Aa")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(open ? Theme.accentText : Theme.textPrimary)
                .frame(minWidth: 48, minHeight: 30)
                .barGlass(on: open, in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Format")
        .accessibilityIdentifier("format-aa")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            MacFormatPopover(checked: checked) { cmd in
                FormatCommandBox.send(cmd)
                checked = Self.focusedText?.caretLineStyle ?? checked
            }
        }
    }

    static var focusedText: SelfSizingTextView? {
        (NSApp.mainWindow ?? NSApp.keyWindow)?.firstResponder as? SelfSizingTextView
    }
}

struct MacFormatPopover: View {
    var checked: MacEditorFormatting.Command
    var onPick: (MacEditorFormatting.Command) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(MacEditorFormatting.popoverMarks, id: \.self) { c in
                    if c == .highlight { Divider().frame(height: 18).padding(.horizontal, 2) }
                    Button { onPick(c) } label: { markLabel(c).frame(width: 34, height: 28).contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .background(Theme.hairline.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        .help(c.title + (c.chord.map { " " + $0.glyphs } ?? ""))
                }
            }
            .padding(.bottom, 4)
            ForEach(MacEditorFormatting.popoverStyles, id: \.self) { row($0) }
            Divider().padding(.vertical, 2)
            ForEach(MacEditorFormatting.popoverLists, id: \.self) { row($0) }
            Divider().padding(.vertical, 2)
            ForEach(MacEditorFormatting.popoverTail, id: \.self) { row($0) }
        }
        .padding(10)
        .frame(width: 250)
    }

    @ViewBuilder private func markLabel(_ c: MacEditorFormatting.Command) -> some View {
        switch c {
        case .bold: Text(c.shortTitle).font(.system(size: 14, weight: .heavy))
        case .italic: Text(c.shortTitle).font(.system(size: 14).italic())
        case .underline: Text(c.shortTitle).font(.system(size: 14)).underline()
        case .strikethrough: Text(c.shortTitle).font(.system(size: 14)).strikethrough()
        default: Image(systemName: "highlighter").font(.system(size: 13))
        }
    }

    private func row(_ c: MacEditorFormatting.Command) -> some View {
        Button { onPick(c) } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .opacity(c == checked ? 1 : 0)
                    .frame(width: 12)
                rowTitle(c)
                Spacer(minLength: 8)
                if let chord = c.chord {
                    Text(chord.glyphs).font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textPrimary)
    }

    @ViewBuilder private func rowTitle(_ c: MacEditorFormatting.Command) -> some View {
        switch c {
        case .title: Text(c.title).font(.system(size: 20, weight: .bold))
        case .heading: Text(c.title).font(.system(size: 16.5, weight: .bold))
        case .subheading: Text(c.title).font(.system(size: 14, weight: .semibold))
        case .monostyled: Text(c.title).font(.system(size: 13, design: .monospaced))
        case .bulletList: Text("•  " + c.title).font(.system(size: 13))
        case .dashedList: Text("–  " + c.title).font(.system(size: 13))
        case .numberedList: Text("1.  " + c.title).font(.system(size: 13))
        case .blockQuote:
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1).fill(Theme.textMuted).frame(width: 2, height: 14)
                Text(c.title).font(.system(size: 13))
            }
        default: Text(c.title).font(.system(size: 13))
        }
    }
}
