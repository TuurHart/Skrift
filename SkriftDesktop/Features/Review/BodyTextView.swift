import SwiftUI
import AppKit

/// Editable note body with live `[[wiki link]]` accent styling AND inline image
/// thumbnails for `[[img_NNN]]` markers — an NSTextView bridge (SwiftUI's TextEditor
/// can't do either). Self-sizing (no internal scroll; the surrounding SwiftUI
/// ScrollView scrolls). The MODEL string always keeps the literal `[[img_NNN]]`
/// markers + `[[brackets]]` (WYSIWYG to the exported markdown); the text view shows
/// a thumbnail in the marker's place via a custom attachment, and the marker is
/// reconstructed from that attachment whenever the user edits.
struct BodyTextView: NSViewRepresentable {
    @Binding var text: String
    /// Resolves an image marker number (`[[img_NNN]]`) to its file URL. Defaults to
    /// none (markers stay as styled text).
    var imageURL: (Int) -> URL? = { _ in nil }

    fileprivate static let bodyFont = NSFont.systemFont(ofSize: 16)
    fileprivate static let markerRegex = try? NSRegularExpression(pattern: #"\[\[img_(\d+)\]\]"#)
    fileprivate static let linkRegex = try? NSRegularExpression(pattern: #"\[\[[^\]]+\]\]"#)

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
        context.coordinator.render(tv, model: text)
        return tv
    }

    func updateNSView(_ tv: SelfSizingTextView, context: Context) {
        // SwiftUI REUSES this NSView across note switches, so refresh the
        // coordinator's parent — otherwise its `text` binding write-back and
        // `imageURL` resolver stay bound to the first note shown (stale file).
        context.coordinator.parent = self
        // Re-render only on an EXTERNAL change (compare against the reconstructed
        // model so our own edits / thumbnail attachments don't trigger a clobber).
        if context.coordinator.modelString(tv) != text {
            context.coordinator.render(tv, model: text)
            tv.invalidateIntrinsicContentSize()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BodyTextView
        init(_ parent: BodyTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? SelfSizingTextView else { return }
            parent.text = modelString(tv)   // attachments → [[img_NNN]] markers
            colorLinks(tv)                   // in-place recolor (keeps attachments + caret)
            tv.invalidateIntrinsicContentSize()
        }

        /// Build the text storage from the model: plain body + inline image thumbnails
        /// spliced where `[[img_NNN]]` markers resolve to a file, + accent `[[links]]`.
        func render(_ tv: SelfSizingTextView, model: String) {
            let primary = NSColor(Theme.textPrimary)
            let attributed = NSMutableAttributedString(
                string: model, attributes: [.font: BodyTextView.bodyFont, .foregroundColor: primary])
            if let rx = BodyTextView.markerRegex {
                let ns = model as NSString
                // Reverse so earlier ranges stay valid as we replace.
                for m in rx.matches(in: model, range: NSRange(location: 0, length: ns.length)).reversed() {
                    let num = Int(ns.substring(with: m.range(at: 1))) ?? 0
                    guard let url = parent.imageURL(num), let img = NSImage(contentsOf: url) else { continue }
                    let att = ImageMarkerAttachment(imgNumber: num)
                    att.image = Self.thumbnail(img, maxWidth: 360)
                    attributed.replaceCharacters(in: m.range, with: NSAttributedString(attachment: att))
                }
            }
            tv.textStorage?.setAttributedString(attributed)
            colorLinks(tv)
            tv.typingAttributes = [.font: BodyTextView.bodyFont, .foregroundColor: primary]
        }

        /// Reset to primary, then accent the `[[links]]` — in place, so attachments and
        /// the caret/selection survive (no full storage rebuild per keystroke).
        func colorLinks(_ tv: SelfSizingTextView) {
            guard let storage = tv.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: NSColor(Theme.textPrimary), range: full)
            if let rx = BodyTextView.linkRegex {
                for m in rx.matches(in: storage.string, range: full) {
                    storage.addAttribute(.foregroundColor, value: NSColor(Theme.accent), range: m.range)
                }
            }
            storage.endEditing()
        }

        /// Reconstruct the model string: image attachments → `[[img_NNN]]`, rest verbatim.
        func modelString(_ tv: SelfSizingTextView) -> String {
            guard let storage = tv.textStorage else { return tv.string }
            var out = ""
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                if let att = value as? ImageMarkerAttachment {
                    out += String(format: "[[img_%03d]]", att.imgNumber)
                } else {
                    out += storage.attributedSubstring(from: range).string
                }
            }
            return out
        }

        /// Downscale to a review-friendly width (keeps aspect; never upscales).
        static func thumbnail(_ image: NSImage, maxWidth: CGFloat) -> NSImage {
            let size = image.size
            guard size.width > maxWidth, size.width > 0 else { return image }
            let newSize = NSSize(width: maxWidth, height: size.height * (maxWidth / size.width))
            let thumb = NSImage(size: newSize)
            thumb.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: newSize),
                       from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1)
            thumb.unlockFocus()
            return thumb
        }
    }
}

/// An `NSTextAttachment` that remembers which `[[img_NNN]]` marker it stands in for,
/// so the editor can reconstruct the literal marker for the model/export.
final class ImageMarkerAttachment: NSTextAttachment {
    let imgNumber: Int
    init(imgNumber: Int) { self.imgNumber = imgNumber; super.init(data: nil, ofType: nil) }
    required init?(coder: NSCoder) { self.imgNumber = 0; super.init(coder: coder) }
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
