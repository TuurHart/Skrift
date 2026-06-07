import SwiftUI
import AppKit

/// Editable note body with live `[[wiki link]]` accent styling — an NSTextView
/// bridge (SwiftUI's TextEditor can't style ranges). Self-sizing (no internal
/// scroll; the surrounding SwiftUI ScrollView scrolls), so long notes grow
/// naturally. Brackets stay visible (WYSIWYG to the exported markdown).
/// (Inline image-marker thumbnails are a further follow-up; `[[img_NNN]]` shows
/// as styled text for now.)
struct BodyTextView: NSViewRepresentable {
    @Binding var text: String

    private static let bodyFont = NSFont.systemFont(ofSize: 16)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> SelfSizingTextView {
        let tv = SelfSizingTextView()
        tv.delegate = context.coordinator
        tv.isRichText = false                 // we own the attributes
        tv.drawsBackground = false
        tv.font = Self.bodyFont
        tv.textContainerInset = .zero
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.allowsUndo = true
        tv.string = text
        context.coordinator.applyStyling(tv)
        return tv
    }

    func updateNSView(_ tv: SelfSizingTextView, context: Context) {
        // External change (file switch / pipeline write) — re-sync, but never clobber
        // mid-edit (delegate already pushed the user's text into the binding).
        if tv.string != text {
            tv.string = text
            context.coordinator.applyStyling(tv)
            tv.invalidateIntrinsicContentSize()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: BodyTextView
        init(_ parent: BodyTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? SelfSizingTextView else { return }
            parent.text = tv.string
            applyStyling(tv)
            tv.invalidateIntrinsicContentSize()
        }

        /// Repaint: body text in the primary color, `[[...]]` spans in accent.
        func applyStyling(_ tv: SelfSizingTextView) {
            let primary = NSColor(Theme.textPrimary)
            let accent = NSColor(Theme.accent)
            let full = tv.string as NSString
            let attributed = NSMutableAttributedString(
                string: tv.string,
                attributes: [.font: BodyTextView.bodyFont, .foregroundColor: primary]
            )
            if let rx = try? NSRegularExpression(pattern: "\\[\\[[^\\]]+\\]\\]") {
                for m in rx.matches(in: tv.string, range: NSRange(location: 0, length: full.length)) {
                    attributed.addAttribute(.foregroundColor, value: accent, range: m.range)
                }
            }
            let selected = tv.selectedRanges
            tv.textStorage?.setAttributedString(attributed)
            tv.selectedRanges = selected
            tv.typingAttributes = [.font: BodyTextView.bodyFont, .foregroundColor: primary]
        }
    }
}

/// NSTextView that reports its laid-out height as `intrinsicContentSize`, so SwiftUI
/// sizes it to its content (width comes from the parent column).
final class SelfSizingTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else { return super.intrinsicContentSize }
        layoutManager.ensureLayout(for: textContainer)
        let height = layoutManager.usedRect(for: textContainer).height + textContainerInset.height * 2
        return NSSize(width: NSView.noIntrinsicMetric, height: max(height, 60))
    }
}
