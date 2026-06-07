import SwiftUI
import AppKit
import ImageIO

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
    /// Called when the user right-clicks a text selection → "Add … as a name".
    var onAddName: (String) -> Void = { _ in }

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

        /// Inject "Add … as a name" into the right-click menu when there's a short
        /// text selection — the reliable, user-driven way to grow the names graph
        /// (no flaky auto-detection; you pick the exact words).
        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            let r = view.selectedRange()
            let ns = view.string as NSString
            if r.length > 0, r.location + r.length <= ns.length {
                let sel = ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
                if !sel.isEmpty, sel.count <= 60 {
                    let item = NSMenuItem(title: "Add “\(sel)” as a name", action: #selector(addNameAction(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = sel
                    menu.insertItem(item, at: 0)
                    menu.insertItem(.separator(), at: 1)
                }
            }
            return menu
        }

        @objc private func addNameAction(_ sender: NSMenuItem) {
            if let sel = sender.representedObject as? String { parent.onAddName(sel) }
        }

        /// Build the text storage from the model: plain body + inline image thumbnails
        /// spliced where `[[img_NNN]]` markers resolve to a file, + accent `[[links]]`.
        func render(_ tv: SelfSizingTextView, model: String) {
            let primary = NSColor(Theme.textPrimary)
            // Synchronous: text + markers-as-text only — instant. Image disk-load +
            // thumbnailing (measured ~600ms EACH on the main thread, freezing the
            // note switch) is moved off-main below and spliced in when ready.
            let attributed = NSMutableAttributedString(
                string: model, attributes: [.font: BodyTextView.bodyFont, .foregroundColor: primary])
            tv.textStorage?.setAttributedString(attributed)
            colorLinks(tv)
            tv.typingAttributes = [.font: BodyTextView.bodyFont, .foregroundColor: primary]
            loadThumbnails(into: tv, model: model)
        }

        /// Resolve marker→URL on main (cheap), load + thumbnail OFF-main, then splice
        /// the thumbnails into the storage on main — only if the note hasn't changed.
        private func loadThumbnails(into tv: SelfSizingTextView, model: String) {
            guard let rx = BodyTextView.markerRegex else { return }
            let ns = model as NSString
            var jobs: [(num: Int, url: URL)] = []
            for m in rx.matches(in: model, range: NSRange(location: 0, length: ns.length)) {
                let num = Int(ns.substring(with: m.range(at: 1))) ?? 0
                if let url = parent.imageURL(num) { jobs.append((num, url)) }
            }
            guard !jobs.isEmpty else { return }
            Task.detached(priority: .userInitiated) {
                var thumbs: [Int: NSImage] = [:]
                for job in jobs where thumbs[job.num] == nil {
                    if let img = Coordinator.loadThumbnail(url: job.url) { thumbs[job.num] = img }
                }
                guard !thumbs.isEmpty else { return }
                await MainActor.run { [weak self, weak tv] in
                    guard let self, let tv, self.modelString(tv) == model else { return }   // same note, unedited
                    self.splice(thumbs, into: tv)
                }
            }
        }

        private func splice(_ thumbs: [Int: NSImage], into tv: SelfSizingTextView) {
            guard let storage = tv.textStorage, let rx = BodyTextView.markerRegex else { return }
            let full = storage.string as NSString
            let sel = tv.selectedRanges
            storage.beginEditing()
            for m in rx.matches(in: storage.string, range: NSRange(location: 0, length: full.length)).reversed() {
                let num = Int(full.substring(with: m.range(at: 1))) ?? 0
                guard let img = thumbs[num] else { continue }
                let att = ImageMarkerAttachment(imgNumber: num)
                att.image = img
                storage.replaceCharacters(in: m.range, with: NSAttributedString(attachment: att))
            }
            storage.endEditing()
            colorLinks(tv)
            tv.selectedRanges = sel
            tv.invalidateIntrinsicContentSize()
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

        /// Thread-safe downscaled thumbnail via ImageIO — decodes directly at thumbnail
        /// size, so it's cheap to run OFF the main thread (unlike NSImage
        /// lockFocus/draw, which forced a full decode on main → the ~600ms/image lag).
        static func loadThumbnail(url: URL, maxPixel: CGFloat = 720) -> NSImage? {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                  ] as CFDictionary) else { return nil }
            // Display at half the pixel size → ~360pt wide, crisp on Retina.
            return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
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
