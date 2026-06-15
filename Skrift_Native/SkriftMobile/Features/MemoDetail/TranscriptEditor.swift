import SwiftUI
import UIKit

/// The always-editable transcript body. A self-sizing `UITextView` (no inner scroll,
/// so it grows inside the page's ScrollView) that renders inline image attachments at
/// the `[[img_NNN]]` markers and edits in place — no Edit button, no boxed field. On
/// every change it writes the transcript back, reconstructing the markers from the
/// attachments, and flags `transcriptUserEdited` so the Mac trusts it (no re-transcribe).
///
/// Audiobook captures (C2 book metadata + a C1 "> " quote block) are QUOTE-PROTECTED:
/// the editor holds only the ramble below the quote — the detail page renders the
/// styled quote block above it — and write-back re-prepends the raw "> " lines
/// verbatim (`CaptureQuote`), so editing can never corrupt the stored quote.
///
/// Shown in `TranscriptBodyView`'s editing mode; playback swaps in its read-only
/// full-text karaoke view (highlight + tap-to-seek). The two render identically
/// when idle, so the swap is seamless.
struct TranscriptEditor: UIViewRepresentable {
    let memo: Memo
    var onCommit: () -> Void

    /// Portrait-locked app → the body width is fixed (screen − the page's side margins).
    private var contentWidth: CGFloat { max(80, UIScreen.main.bounds.width - 2 * Theme.Space.margin) }

    func makeCoordinator() -> Coordinator { Coordinator(memo: memo, onCommit: onCommit, width: contentWidth) }

    func makeUIView(context: Context) -> UITextView {
        let tv = NonScrollingTextView()
        tv.isScrollEnabled = false                 // self-size inside the SwiftUI ScrollView
        // No safe-area inset adjustment: the view is mid-scroll-content and never
        // scrolls itself, so its rest contentOffset is always exactly .zero (which
        // NonScrollingTextView pins it to).
        tv.contentInsetAdjustmentBehavior = .never
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.font = .systemFont(ofSize: 15.5)
        tv.tintColor = UIColor(Color.skAccent)
        tv.delegate = context.coordinator
        tv.keyboardDismissMode = .interactive
        tv.accessibilityIdentifier = "transcript-editor"
        context.coordinator.textView = tv
        context.coordinator.load(force: true)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.memo = memo
        context.coordinator.load(force: false)     // re-render only if the transcript changed under us
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        // Clamp degenerate probe widths (0 / tiny) like contentWidth does — measuring a
        // long transcript at width ~0 reports an absurd height, which spikes the outer
        // ScrollView's content size and can throw its offset around.
        let w = max(80, proposal.width ?? contentWidth)
        let h = uiView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height
        return CGSize(width: w, height: max(h, 40))
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        var memo: Memo
        let onCommit: () -> Void
        let width: CGFloat
        weak var textView: UITextView?
        private var loaded: String?           // the transcript string our attributed text currently reflects

        /// Custom attribute tagging an attachment with its 1-based image-marker index,
        /// so the transcript string can be reconstructed from the attributed text.
        static let markerKey = NSAttributedString.Key("skriftImgMarker")

        init(memo: Memo, onCommit: @escaping () -> Void, width: CGFloat) {
            self.memo = memo; self.onCommit = onCommit; self.width = width
        }

        /// The protected C1 quote split for a capture memo — recomputed from the
        /// memo on every use so an external transcript change can't leave a stale
        /// prefix. Nil for ordinary memos (the editor then holds the full text).
        private var protectedQuote: CaptureQuote? { memo.captureQuote }

        /// (Re)build the attributed text from the memo's transcript when it changed under
        /// us (e.g. transcription finished) — but never while the user is typing.
        func load(force: Bool) {
            guard let tv = textView else { return }
            let t = memo.transcript ?? ""
            // Quote-protected captures edit only the ramble; the styled quote
            // block above the editor presents the "> " lines.
            let display = protectedQuote?.ramble ?? t
            if !force {
                if t == loaded { return }
                if tv.isFirstResponder { return }                 // don't yank text mid-edit
                if display == reconstruct(tv.attributedText) { loaded = t; return }
            }
            // Replacing the attributed string resets the caret to the start — and
            // SwiftUI's keyboard avoidance then scrolls the note to that top-of-text
            // caret. Carry the (clamped) selection across the rebuild so the caret —
            // and with it the visible spot — stays put.
            let selection = tv.selectedRange
            tv.attributedText = attributed(from: display)
            let length = tv.attributedText.length
            let location = min(selection.location, length)
            tv.selectedRange = NSRange(location: location, length: min(selection.length, length - location))
            loaded = t
            tv.invalidateIntrinsicContentSize()
        }

        func textViewDidChange(_ tv: UITextView) {
            let text = reconstruct(tv.attributedText)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let quote = protectedQuote {
                // Capture memo: the editor held ONLY the ramble — re-prepend the
                // raw "> " block verbatim so the stored quote is untouchable.
                // Emptying the ramble leaves a quote-only capture, never nil.
                memo.transcript = quote.transcript(withRamble: text)
                memo.transcriptStatus = .done
            } else {
                memo.transcript = trimmed.isEmpty ? nil : text
                if !trimmed.isEmpty { memo.transcriptStatus = .done }
            }
            memo.transcriptUserEdited = true                       // Mac trusts it → no re-transcribe
            loaded = memo.transcript ?? ""
            tv.invalidateIntrinsicContentSize()
            onCommit()
        }

        // MARK: attributed text ⇄ marker string

        private func baseAttributes() -> [NSAttributedString.Key: Any] {
            let para = NSMutableParagraphStyle()
            para.lineSpacing = 4
            return [.font: UIFont.systemFont(ofSize: 15.5),
                    .foregroundColor: UIColor(Color.skText),
                    .paragraphStyle: para]
        }

        private func attributed(from transcript: String) -> NSAttributedString {
            let result = NSMutableAttributedString()
            let base = baseAttributes()
            let ns = transcript as NSString
            let regex = try? NSRegularExpression(pattern: #"\[\[img_(\d+)\]\]"#)
            var last = 0
            func text(_ s: String) { result.append(NSAttributedString(string: s, attributes: base)) }
            regex?.enumerateMatches(in: transcript, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m else { return }
                if m.range.location > last {
                    text(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
                }
                let n = Int(ns.substring(with: m.range(at: 1))) ?? 0
                let piece = NSMutableAttributedString(attachment: imageAttachment(markerIndex: n))
                piece.addAttribute(Self.markerKey, value: n, range: NSRange(location: 0, length: piece.length))
                result.append(piece)
                last = m.range.location + m.range.length
            }
            if last < ns.length { text(ns.substring(from: last)) }
            return result
        }

        /// Walk the attributed text → the raw transcript string with `[[img_NNN]]`
        /// markers where attachments are (so edits round-trip losslessly).
        func reconstruct(_ attr: NSAttributedString?) -> String {
            guard let attr else { return "" }
            let out = NSMutableString()
            let full = attr.string as NSString
            attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length)) { attrs, range, _ in
                if let marker = attrs[Self.markerKey] as? Int {
                    out.append("[[img_\(marker)]]")
                } else if attrs[.attachment] == nil {
                    out.append(full.substring(with: range))       // plain text
                }                                                  // untagged attachment → drop
            }
            return out as String
        }

        private func imageAttachment(markerIndex: Int) -> NSTextAttachment {
            let att = NSTextAttachment()
            if let url = memo.imageURL(markerIndex: markerIndex), let img = MemoImageLoader.thumbnail(at: url, maxWidth: width) {
                att.image = img
                // NSTextAttachment scales the image to FILL `bounds` (it does NOT
                // preserve aspect), so the bounds MUST match the image's aspect or it
                // distorts. Fit within full width × a 320-pt height cap; when a tall/
                // PORTRAIT frame would exceed the cap, shrink the WIDTH to keep aspect
                // (was: width pinned full + height capped → portrait video frames came
                // out stretched wide — device bug 2026-06-15).
                let aspect = img.size.width / max(1, img.size.height)   // w / h
                let maxHeight: CGFloat = 320
                var w = width
                var h = width / max(0.01, aspect)
                if h > maxHeight { h = maxHeight; w = maxHeight * aspect }
                att.bounds = CGRect(x: 0, y: -4, width: w, height: h)
            } else {
                att.image = Self.placeholder(width: width)
                att.bounds = CGRect(x: 0, y: -4, width: width, height: 150)
            }
            return att
        }

        private static func placeholder(width: CGFloat) -> UIImage {
            let size = CGSize(width: width, height: 150)
            return UIGraphicsImageRenderer(size: size).image { ctx in
                UIColor(Color.skElev).setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 14).fill()
                let icon = UIImage(systemName: "photo")?.withTintColor(UIColor(Color.skTextFaint), renderingMode: .alwaysOriginal)
                if let icon {
                    let s: CGFloat = 34
                    icon.draw(in: CGRect(x: (size.width - s) / 2, y: (size.height - s) / 2, width: s, height: s))
                }
            }
        }
    }
}

/// A `UITextView` that self-sizes (no inner scrolling) without UIKit's caret-scroll
/// jumps. `isScrollEnabled = false` only blocks USER scrolling — on paste (and some
/// edits) UIKit still calls `setContentOffset` internally, with an offset computed
/// against the stale pre-growth bounds. That stray offset shifts the text inside the
/// fixed frame and feeds SwiftUI's keyboard avoidance a bogus caret rect — the
/// "paste teleports the note to the top" bug. While self-sizing, the only valid
/// offset is `.zero`, so pin it there.
final class NonScrollingTextView: UITextView {
    override var contentOffset: CGPoint {
        get { super.contentOffset }
        set { super.contentOffset = isScrollEnabled ? newValue : .zero }
    }

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        super.setContentOffset(isScrollEnabled ? contentOffset : .zero, animated: isScrollEnabled && animated)
    }
}
