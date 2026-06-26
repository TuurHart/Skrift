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
    /// Name-linking tiers over the RAW transcript (derived by the parent from the memo +
    /// names DB). Styled in place and tappable; empty = no name-linking (no people).
    var nameSpans: [NameSpan] = []
    /// A name span was tapped (while not editing) → the parent presents the resolve sheet.
    var onTapName: (NameSpan) -> Void = { _ in }
    /// When set, the editor edits THIS text (the Mac's polished `MemoEnhancement.copyedit`)
    /// instead of `memo.transcript` — the Phase-4 "polished body". Image markers + name
    /// tiers + tap all work over it; the capture-quote split is bypassed (a polished memo is
    /// never an audiobook capture). The caller's binding setter writes copyedit + provenance.
    var polishedBinding: Binding<String>? = nil

    /// Portrait-locked app → the body width is fixed (screen − the page's side margins).
    private var contentWidth: CGFloat { max(80, UIScreen.main.bounds.width - 2 * Theme.Space.margin) }

    func makeCoordinator() -> Coordinator { Coordinator(memo: memo, onCommit: onCommit, width: contentWidth) }

    func makeUIView(context: Context) -> UITextView {
        // TextKit 1 (explicit) so `layoutManager` hit-testing for the name-tap is reliable
        // (a default UITextView is TextKit 2 on iOS 16+, where touching `layoutManager`
        // silently migrates the view — we pin the classic stack instead).
        let tv = NonScrollingTextView(usingTextLayoutManager: false)
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
        context.coordinator.nameSpans = nameSpans
        context.coordinator.onTapName = onTapName
        context.coordinator.polishedBinding = polishedBinding
        // A tapped NAME opens the resolve sheet. The editor stays always-editable, so the
        // tap also begins editing; `handleNameTap` detects the name hit and resigns first
        // responder, so the keyboard yields to the sheet. Tapping plain text edits normally.
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleNameTap(_:)))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        tv.addGestureRecognizer(tap)
        context.coordinator.load(force: true)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.memo = memo
        context.coordinator.onTapName = onTapName
        context.coordinator.polishedBinding = polishedBinding
        context.coordinator.load(force: false)     // re-render only if the transcript changed under us
        // Re-style when the tiers changed (a resolution applied) — but never mid-edit
        // (offsets drift while typing; we restyle on end-edit instead).
        if !uiView.isFirstResponder {
            context.coordinator.updateSpans(nameSpans)
        } else {
            context.coordinator.nameSpans = nameSpans
        }
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

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var memo: Memo
        let onCommit: () -> Void
        let width: CGFloat
        weak var textView: NonScrollingTextView?
        private var loaded: String?           // the transcript string our attributed text currently reflects

        /// Name-linking tiers over the RAW transcript (set by the representable). Styled
        /// in place; `displaySpans` is the same set mapped to the DISPLAYED text offsets
        /// (image markers collapse to one glyph) for hit-testing + restyle.
        var nameSpans: [NameSpan] = []
        var onTapName: (NameSpan) -> Void = { _ in }
        /// When set, edit the Mac's polished copy-edit instead of `memo.transcript`.
        var polishedBinding: Binding<String>?
        private var displaySpans: [(range: NSRange, span: NameSpan)] = []

        /// The text the editor currently shows/edits — the polished copy-edit when bound,
        /// else the raw transcript. (Both carry `[[img_NNN]]` markers + name tiers.)
        private var bodyText: String { polishedBinding?.wrappedValue ?? (memo.transcript ?? "") }

        /// Custom attribute tagging an attachment with its 1-based image-marker index,
        /// so the transcript string can be reconstructed from the attributed text.
        static let markerKey = NSAttributedString.Key("skriftImgMarker")

        init(memo: Memo, onCommit: @escaping () -> Void, width: CGFloat) {
            self.memo = memo; self.onCommit = onCommit; self.width = width
        }

        // MARK: name-linking tiers (styling + tap hit-test)

        /// Re-apply tier styling for a new span set (a resolution was applied). No-op while
        /// the user is typing (the representable guards on `!isFirstResponder`).
        func updateSpans(_ spans: [NameSpan]) {
            nameSpans = spans
            applyTierStyling()
        }

        /// The name span under a tap point, or nil for plain text / outside any name. Used
        /// both to suppress begin-editing (so a name tap opens the sheet, not the keyboard)
        /// and to route the tap to the resolve sheet.
        func spanAt(_ point: CGPoint) -> NameSpan? {
            guard let tv = textView, tv.textStorage.length > 0, !displaySpans.isEmpty else { return nil }
            let p = CGPoint(x: point.x - tv.textContainerInset.left, y: point.y - tv.textContainerInset.top)
            let lm = tv.layoutManager
            // Hit-test against each token's DRAWN rect(s) (expanded for a comfortable touch
            // target), not the nearest char index — a tap at the trailing edge of a short
            // name resolves to the boundary index just OUTSIDE the span, which would miss.
            // A span can wrap a line, so union its enclosing rects.
            for entry in displaySpans {
                let glyphRange = lm.glyphRange(forCharacterRange: entry.range, actualCharacterRange: nil)
                var hit = false
                lm.enumerateEnclosingRects(forGlyphRange: glyphRange,
                                           withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                           in: tv.textContainer) { rect, stop in
                    if rect.insetBy(dx: -6, dy: -4).contains(p) { hit = true; stop.pointee = true }
                }
                if hit { return entry.span }
            }
            return nil
        }

        @objc func handleNameTap(_ gr: UITapGestureRecognizer) {
            guard gr.state == .ended, let tv = textView else { return }
            // A tap on a name → resolve sheet; otherwise let it edit (caret + keyboard).
            guard let span = spanAt(gr.location(in: tv)) else { return }
            // The tap also began editing (UITextView raises the keyboard on tap); resign so
            // the keyboard yields to the resolve sheet.
            tv.resignFirstResponder()
            Haptics.tap(.light)
            onTapName(span)
        }

        // Let the tap coexist with the text view's own selection gestures.
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        /// Re-color the name spans on top of the base attributed text. Idempotent: resets
        /// tier attributes over the text first (attachments untouched), then applies each
        /// span. Rebuilds `displaySpans` (display offsets) for hit-testing.
        func applyTierStyling() {
            guard let tv = textView else { return }
            let storage = tv.textStorage
            let full = NSRange(location: 0, length: storage.length)
            guard full.length > 0 else { displaySpans = []; return }
            let sel = tv.selectedRange
            storage.beginEditing()
            storage.enumerateAttribute(.attachment, in: full) { attachment, range, _ in
                guard attachment == nil else { return }     // skip image attachments
                storage.removeAttribute(.underlineStyle, range: range)
                storage.removeAttribute(.underlineColor, range: range)
                storage.removeAttribute(.backgroundColor, range: range)
                storage.addAttribute(.foregroundColor, value: UIColor(Color.skText), range: range)
            }
            var built: [(NSRange, NameSpan)] = []
            let transcript = bodyText                        // raw transcript OR the polished copy-edit
            for span in nameSpans {
                guard let dr = displayRange(forRaw: span.range, transcript: transcript),
                      dr.location + dr.length <= storage.length else { continue }
                NameTierStyle.apply(span.tier, to: storage, range: dr)
                built.append((dr, span))
            }
            storage.endEditing()
            displaySpans = built
            let len = storage.length
            let loc = min(sel.location, len)
            tv.selectedRange = NSRange(location: loc, length: min(sel.length, len - loc))
        }

        /// Map a RAW-transcript range to the DISPLAYED-text range: each `[[img_NNN]]`
        /// marker before the range collapses to a single attachment glyph. Returns nil if
        /// the range overlaps a marker (names never do).
        private func displayRange(forRaw raw: NSRange, transcript: String) -> NSRange? {
            let ns = transcript as NSString
            guard ns.length > 0, let rx = try? NSRegularExpression(pattern: #"\[\[img_\d+\]\]"#) else { return raw }
            var delta = 0
            for m in rx.matches(in: transcript, range: NSRange(location: 0, length: ns.length)) {
                if m.range.location + m.range.length <= raw.location {
                    delta += m.range.length - 1             // marker → 1 glyph
                } else if m.range.location < raw.location + raw.length {
                    return nil                              // span straddles a marker
                } else {
                    break
                }
            }
            let loc = raw.location - delta
            return loc >= 0 ? NSRange(location: loc, length: raw.length) : nil
        }

        /// The protected C1 quote split for a capture memo — recomputed from the
        /// memo on every use so an external transcript change can't leave a stale
        /// prefix. Nil for ordinary memos (the editor then holds the full text).
        private var protectedQuote: CaptureQuote? { memo.captureQuote }

        /// (Re)build the attributed text from the memo's transcript when it changed under
        /// us (e.g. transcription finished) — but never while the user is typing.
        func load(force: Bool) {
            guard let tv = textView else { return }
            let t = bodyText
            // Polished body: edit the copy-edit verbatim (no capture-quote split — a polished
            // memo is never an audiobook capture). Otherwise quote-protected captures edit
            // only the ramble; the styled quote block above presents the "> " lines.
            let display = polishedBinding != nil ? t : (protectedQuote?.ramble ?? t)
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
            applyTierStyling()                                 // re-color names over the fresh text
            tv.invalidateIntrinsicContentSize()
        }

        /// Editing ended → re-derive the name tiers over the final text (we skip restyling
        /// while typing, since offsets drift). The representable passed the up-to-date spans.
        func textViewDidEndEditing(_ tv: UITextView) {
            applyTierStyling()
        }

        func textViewDidChange(_ tv: UITextView) {
            let text = reconstruct(tv.attributedText)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let binding = polishedBinding {
                // Polished body: write the Mac's copy-edit; the caller's binding setter stamps
                // provenance (this phone + now) so it syncs as the source of truth.
                binding.wrappedValue = text
                loaded = text
                tv.invalidateIntrinsicContentSize()
                onCommit()
                return
            }
            if let quote = protectedQuote {
                // Capture memo: the editor held ONLY the ramble — re-prepend the
                // raw "> " block verbatim so the stored quote is untouchable.
                // Emptying the ramble leaves a quote-only capture, never nil.
                memo.transcript = quote.transcript(withRamble: text)
                memo.transcriptStatus = .done
            } else {
                let wasNonEmpty = !(loaded ?? "").isEmpty
                memo.transcript = trimmed.isEmpty ? nil : text
                if !trimmed.isEmpty { memo.transcriptStatus = .done }
                // Timeline marker for the 2026-06-21 "cleared body → append → note
                // vanished" hunt: log the moment the body is emptied to nil.
                if trimmed.isEmpty && wasNonEmpty {
                    DevLog.log("editor cleared body → transcript=nil memo \(memo.id)")
                }
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

// MARK: - Name-tier attributed styling

/// Maps a `NameSpan.Tier` to attributed-text attributes over a token range, matching the
/// signed-off mock (`mocks/phone-name-linking.html`): LINKED solid accent; SUGGESTED tan +
/// dotted tan underline; AMBIGUOUS accent wash + dotted purple underline; PLAIN (leftplain)
/// a faint dotted underline. The mock's ambiguous "?" superscript is dropped on purpose —
/// injecting a glyph would corrupt the RAW transcript the editor reconstructs.
enum NameTierStyle {
    private static let dotted = NSNumber(value: NSUnderlineStyle([.single, .patternDot]).rawValue)

    static func apply(_ tier: NameSpan.Tier, to storage: NSTextStorage, range: NSRange) {
        switch tier {
        case .linked:
            storage.addAttribute(.foregroundColor, value: UIColor(Color.skNameLinked), range: range)
        case .suggested:
            storage.addAttributes([
                .foregroundColor: UIColor(Color.skNameSuggest),
                .underlineStyle: dotted,
                .underlineColor: UIColor(Color.skNameSuggestLine),
            ], range: range)
        case .ambiguous:
            storage.addAttributes([
                .backgroundColor: UIColor(Color.skAccentSoft),
                .underlineStyle: dotted,
                .underlineColor: UIColor(Color.skNameAmbigLine),
            ], range: range)
        case .plain:
            storage.addAttributes([
                .underlineStyle: dotted,
                .underlineColor: UIColor(Color.skNamePlainLine),
            ], range: range)
        }
    }
}
