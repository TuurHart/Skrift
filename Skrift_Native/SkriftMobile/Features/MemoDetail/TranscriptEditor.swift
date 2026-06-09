import SwiftUI
import UIKit

/// The always-editable transcript body. A self-sizing `UITextView` (no inner scroll,
/// so it grows inside the page's ScrollView) that renders inline image attachments at
/// the `[[img_NNN]]` markers and edits in place — no Edit button, no boxed field. On
/// every change it writes the transcript back, reconstructing the markers from the
/// attachments, and flags `transcriptUserEdited` so the Mac trusts it (no re-transcribe).
///
/// Shown when paused; during playback the parent swaps in the read-only karaoke
/// `TranscriptContentView` (highlight + tap-to-seek). The two render identically when
/// idle, so the swap is seamless.
struct TranscriptEditor: UIViewRepresentable {
    let memo: Memo
    var onCommit: () -> Void

    /// Portrait-locked app → the body width is fixed (screen − the page's side margins).
    private var contentWidth: CGFloat { max(80, UIScreen.main.bounds.width - 2 * Theme.Space.margin) }

    func makeCoordinator() -> Coordinator { Coordinator(memo: memo, onCommit: onCommit, width: contentWidth) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isScrollEnabled = false                 // self-size inside the SwiftUI ScrollView
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
        let w = proposal.width ?? contentWidth
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

        /// (Re)build the attributed text from the memo's transcript when it changed under
        /// us (e.g. transcription finished) — but never while the user is typing.
        func load(force: Bool) {
            guard let tv = textView else { return }
            let t = memo.transcript ?? ""
            if !force {
                if t == loaded { return }
                if tv.isFirstResponder { return }                 // don't yank text mid-edit
                if t == reconstruct(tv.attributedText) { loaded = t; return }
            }
            tv.attributedText = attributed(from: t)
            loaded = t
            tv.invalidateIntrinsicContentSize()
        }

        func textViewDidChange(_ tv: UITextView) {
            let text = reconstruct(tv.attributedText)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            memo.transcript = trimmed.isEmpty ? nil : text
            memo.transcriptUserEdited = true                       // Mac trusts it → no re-transcribe
            if !trimmed.isEmpty { memo.transcriptStatus = .done }
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

        private func imageURL(markerIndex: Int) -> URL? {
            guard let manifest = memo.metadata?.imageManifest,
                  markerIndex >= 1, markerIndex <= manifest.count else { return nil }
            return AppPaths.recordingsDirectory.appendingPathComponent(manifest[markerIndex - 1].filename)
        }

        private func imageAttachment(markerIndex: Int) -> NSTextAttachment {
            let att = NSTextAttachment()
            if let url = imageURL(markerIndex: markerIndex), let img = UIImage(contentsOfFile: url.path) {
                att.image = img
                let h = min(width * (img.size.height / max(1, img.size.width)), 320)
                att.bounds = CGRect(x: 0, y: -4, width: width, height: h)
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
