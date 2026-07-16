import SwiftUI
import AppKit

/// The inline `#` tag menu: a PASSIVE, non-activating child panel anchored under
/// the caret's `#word` run. It never becomes key and intercepts nothing — the text
/// view keeps focus and every keystroke (including Backspace) lands in the document
/// natively; the coordinator drives it from the outside (↑ ↓ Return Esc via
/// `doCommandBy`, clicks via `onPick`). NSTextView's built-in completion session is
/// the wrong tool for this: it preview-inserts candidates into the storage and its
/// bookkeeping desyncs when the previews are suppressed (eaten keystrokes, dead
/// backspace — device round 1). A dumb floating list is how Obsidian/Xcode do it.
/// Main-thread only (AppKit delegate call sites), like the rest of the editor bridge.
final class TagSuggestPanel {
    private var panel: NSPanel?
    private(set) var isVisible = false
    var onPick: (String) -> Void = { _ in }

    func show(matches: [String], selected: Int, anchoredTo rect: NSRect, of tv: NSTextView) {
        guard let window = tv.window else { return }
        let host = NSHostingView(rootView: TagSuggestList(matches: matches, selected: selected,
                                                          onPick: { [weak self] in self?.onPick($0) }))
        host.frame.size = host.fittingSize
        let p = panel ?? Self.makePanel()
        panel = p
        p.contentView = host
        p.setContentSize(host.fittingSize)

        // Under the run; flip above when the screen runs out below.
        let screenRect = window.convertToScreen(tv.convert(rect, to: nil))
        var origin = NSPoint(x: screenRect.minX, y: screenRect.minY - host.fittingSize.height - 4)
        if let screen = window.screen, origin.y < screen.visibleFrame.minY {
            origin.y = screenRect.maxY + 4
        }
        p.setFrameOrigin(origin)
        if !isVisible {
            window.addChildWindow(p, ordered: .above)
            isVisible = true
        }
    }

    func hide() {
        guard isVisible, let p = panel else { return }
        p.parent?.removeChildWindow(p)
        p.orderOut(nil)
        isVisible = false
    }

    private static func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = true
        p.hasShadow = true
        p.isOpaque = false
        p.backgroundColor = .clear
        return p
    }
}

/// The menu rows: matching tags, keyboard-selected row highlighted, click to pick.
/// SCROLLS past ~11 rows (a bare `#` browses the whole library, Obsidian-style);
/// the keyboard selection stays in view.
struct TagSuggestList: View {
    let matches: [String]
    let selected: Int
    var onPick: (String) -> Void

    private static let rowHeight: CGFloat = 26
    private static let maxListHeight: CGFloat = 286   // 11 rows

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element) { i, tag in
                        row(i, tag).id(i)
                    }
                }
            }
            .frame(width: 190,
                   height: min(CGFloat(matches.count) * Self.rowHeight, Self.maxListHeight))
            .onAppear { if selected > 0 { proxy.scrollTo(selected) } }
        }
        .padding(5)
        .background(Theme.surfaceHover)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.hairline.opacity(0.12), lineWidth: 1))
    }

    private func row(_ i: Int, _ tag: String) -> some View {
        Button { onPick(tag) } label: {
            HStack(spacing: 6) {
                Image(systemName: "number").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(i == selected ? Theme.accent : Theme.textMuted)
                Text(tag).font(.system(size: 12.5)).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: Self.rowHeight)
            .background(i == selected ? Theme.accent.opacity(0.16) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
