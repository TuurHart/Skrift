import SwiftUI
import UIKit
import Combine

/// Mode of the note body — same precedence the old `TranscriptBodyView` swapped
/// views on, now driving STATE of one view (editable / painter / read-only):
/// playback always wins, an in-flight transcription is read-only (an open draft
/// could clobber the landing text), else always-editable. Static + pure so tests
/// pin the precedence.
enum NoteBody {
    enum Mode: Equatable { case editing, playing, reading }

    static func mode(isPlaying: Bool, status: TranscriptStatus) -> Mode {
        if isPlaying { return .playing }
        if status == .transcribing { return .reading }
        return .editing
    }
}

/// The re-founded note body (spec: `mocks/note-editor-redesign.html`): ONE
/// natively-scrolling `UITextView` IS the page. The transcript text, inline photo
/// attachments, name tiers, and the karaoke highlight all live on the same
/// textStorage; the metadata header (chips/importance/summary/quote) and footer
/// (people row) are SwiftUI views hosted INSIDE the scroll content, so everything
/// scrolls as one. Because the text view owns its scrolling, UIKit's native
/// editing mechanics — selection-drag autoscroll, caret-follow, magnifier, edit
/// menu, undo — work un-patched (the old `NonScrollingTextView` offset-pinning and
/// its keyboard-avoidance scars are deleted).
///
/// Play/pause no longer swaps renderers: the SAME text repaints in place at word
/// rate (played dim · current accent · upcoming default), photos keep their exact
/// size and position, and a tap during playback seeks to the tapped word. The
/// position ticks flow `PlayerClock` → coordinator (Combine), never through the
/// SwiftUI tree — the 20 Hz whole-page re-render is gone.
///
/// Audiobook captures stay QUOTE-PROTECTED: the editor holds only the ramble
/// (the styled quote block lives in the header) and write-back re-prepends the
/// raw "> " lines verbatim (`CaptureQuote`), so editing can never corrupt the
/// stored quote. When `polishedBinding` is set the editor edits the Mac's
/// copy-edit instead of `memo.transcript` (proportional karaoke — timings are
/// pinned to the raw words).
///
/// Saves are DEBOUNCED (the old per-keystroke `context.save()` + CloudKit churn
/// is gone): the draft commits after ~1 s idle, on end-editing, on play, on
/// app-resign, and on teardown.
struct NoteBodyView: UIViewRepresentable {
    let memo: Memo
    @ObservedObject var player: AudioPlayerModel   // rare state (isPlaying/duration); ticks stay in the coordinator
    var nameSpans: [NameSpan] = []
    var onTapName: (NameSpan) -> Void = { _ in }
    var polishedBinding: Binding<String>? = nil
    var onCommit: () -> Void = {}
    var header: AnyView = AnyView(EmptyView())
    var footer: AnyView = AnyView(EmptyView())
    /// Off-screen pager pages must vanish from the accessibility tree (XCUITest
    /// + VoiceOver would see 2-3 editors). SwiftUI's `.accessibilityHidden` on
    /// the page doesn't reach into this UIKit subtree, so it's driven explicitly.
    var a11yHidden: Bool = false

    @AppStorage("karaokeTapToSeek") private var tapToSeek = true

    private var mode: NoteBody.Mode { NoteBody.mode(isPlaying: player.isPlaying, status: memo.transcriptStatus) }

    func makeCoordinator() -> Coordinator { Coordinator(memo: memo, onCommit: onCommit) }

    func makeUIView(context: Context) -> NoteBodyTextView {
        let tv = NoteBodyTextView()
        tv.isScrollEnabled = true
        tv.alwaysBounceVertical = true
        tv.backgroundColor = .clear
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainerInset = UIEdgeInsets(top: 10, left: Theme.Space.margin,
                                             bottom: 24, right: Theme.Space.margin)
        tv.font = .systemFont(ofSize: 15.5)
        tv.tintColor = UIColor(Color.skAccent)
        tv.keyboardDismissMode = .interactive
        tv.delegate = context.coordinator
        tv.accessibilityIdentifier = "transcript-editor"
        tv.installAccessoryHosts()

        context.coordinator.textView = tv
        context.coordinator.player = player
        context.coordinator.nameSpans = nameSpans
        context.coordinator.onTapName = onTapName
        context.coordinator.polishedBinding = polishedBinding
        context.coordinator.tapToSeek = tapToSeek

        // One tap recognizer routes: word-seek while playing, name-resolve while
        // paused; anything else falls through to normal editing.
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        tv.addGestureRecognizer(tap)

        context.coordinator.observeAppResign()
        context.coordinator.load(force: true)
        return tv
    }

    func updateUIView(_ tv: NoteBodyTextView, context: Context) {
        let c = context.coordinator
        c.memo = memo
        c.player = player
        c.onTapName = onTapName
        c.polishedBinding = polishedBinding
        c.tapToSeek = tapToSeek

        tv.setAccessories(header: header, footer: footer)
        tv.setAccessibilityHidden(a11yHidden)

        c.load(force: false)                    // re-render only if the text changed under us
        c.apply(mode: mode)                     // editable / painter / read-only

        // Re-style when the tiers changed (a resolution applied) — never mid-edit
        // (offsets drift while typing) and never while the painter owns the colors.
        if !tv.isFirstResponder && mode == .editing {
            c.updateSpans(nameSpans)
        } else {
            c.nameSpans = nameSpans
        }
    }

    static func dismantleUIView(_ uiView: NoteBodyTextView, coordinator: Coordinator) {
        coordinator.commitDraft()
        coordinator.teardown()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var memo: Memo
        let onCommit: () -> Void
        weak var textView: NoteBodyTextView?
        weak var player: AudioPlayerModel?
        var polishedBinding: Binding<String>?
        var nameSpans: [NameSpan] = []
        var onTapName: (NameSpan) -> Void = { _ in }
        var tapToSeek = true

        /// The transcript string our attributed text currently reflects.
        private var loaded: String?
        /// Uncommitted edits exist in the view (debounce window).
        private var draftDirty = false
        private var commitTask: Task<Void, Never>?
        private var resignObserver: NSObjectProtocol?

        /// Name spans mapped to DISPLAYED offsets for hit-testing.
        private var displaySpans: [(range: NSRange, span: NameSpan)] = []

        // Karaoke painting state.
        private var clockSub: AnyCancellable?
        private var wordRanges: [NSRange] = []
        private var timings: [WordTiming] = []
        private var lastActive: Int?           // LOCAL word index (nil = nothing painted)
        private var painting = false
        private var currentMode: NoteBody.Mode = .editing

        /// Custom attribute tagging an attachment with its 1-based image-marker
        /// index, so the transcript string round-trips from the attributed text.
        static let markerKey = NSAttributedString.Key("skriftImgMarker")

        init(memo: Memo, onCommit: @escaping () -> Void) {
            self.memo = memo
            self.onCommit = onCommit
        }

        /// Portrait-locked app → fixed content width (screen − margins).
        private var contentWidth: CGFloat {
            max(80, UIScreen.main.bounds.width - 2 * Theme.Space.margin)
        }

        /// The text the editor shows/edits — the polished copy-edit when bound,
        /// else the raw transcript (both carry `[[img_NNN]]` markers).
        private var bodyText: String { polishedBinding?.wrappedValue ?? (memo.transcript ?? "") }

        /// The protected C1 quote split for a capture memo — recomputed on every
        /// use so an external transcript change can't leave a stale prefix.
        private var protectedQuote: CaptureQuote? { polishedBinding == nil ? memo.captureQuote : nil }

        // MARK: lifecycle

        func observeAppResign() {
            resignObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.commitDraft() }
            }
        }

        func teardown() {
            clockSub?.cancel()
            commitTask?.cancel()
            if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
            resignObserver = nil
        }

        // MARK: load / rebuild

        /// (Re)build the attributed text when the transcript changed under us
        /// (e.g. transcription finished) — never while the user is typing, and
        /// never over an uncommitted draft.
        func load(force: Bool) {
            guard let tv = textView else { return }
            let t = bodyText
            let display = protectedQuote?.ramble ?? t
            if !force {
                if t == loaded { return }
                if tv.isFirstResponder || draftDirty { return }        // don't yank text mid-edit
                if display == reconstruct(tv.attributedText) { loaded = t; return }
            }
            // Carry the (clamped) selection across the rebuild so the caret —
            // and with it the visible spot — stays put.
            let selection = tv.selectedRange
            tv.attributedText = attributed(from: display)
            let length = tv.attributedText.length
            let location = min(selection.location, length)
            tv.selectedRange = NSRange(location: location, length: min(selection.length, length - location))
            loaded = t
            rebuildWordRanges()
            applyTierStyling()
            tv.setNeedsAccessoryLayout()
        }

        // MARK: mode (editing / playing / reading)

        func apply(mode: NoteBody.Mode) {
            guard mode != currentMode else { return }
            let previous = currentMode
            currentMode = mode
            guard let tv = textView else { return }
            switch mode {
            case .playing:
                commitDraft()
                tv.resignFirstResponder()
                tv.isEditable = false
                // No selection during playback — and with UITextInteraction gone,
                // the word-seek tap recognizer actually receives the touches (the
                // system text interactions swallow single taps otherwise).
                tv.isSelectable = false
                startPainting()
            case .reading:
                if previous == .playing { stopPainting() }
                commitDraft()
                tv.isEditable = false
                tv.isSelectable = true
            case .editing:
                if previous == .playing { stopPainting() }
                tv.isEditable = true
                tv.isSelectable = true
            }
        }

        // MARK: karaoke painting

        private func startPainting() {
            guard let player else { return }
            painting = true
            timings = WordTimingsStore().load(for: memo.id) ?? []
            rebuildWordRanges()
            stripColors()
            lastActive = nil
            repaint(at: player.currentTime, full: true)
            clockSub = player.clock.$time
                .sink { [weak self] t in
                    guard let self, self.painting else { return }
                    self.repaint(at: t, full: false)
                }
        }

        private func stopPainting() {
            painting = false
            clockSub?.cancel()
            clockSub = nil
            lastActive = nil
            stripColors()
            applyTierStyling()
        }

        /// Sidecar word index of this editor's first word (a capture's ramble
        /// starts after the quote's spoken words).
        private var sidecarOffset: Int { protectedQuote?.spokenWordCount ?? 0 }

        /// LOCAL active word (index into `wordRanges`) at playback time `t`.
        private func activeLocal(at t: TimeInterval) -> Int? {
            guard !wordRanges.isEmpty else { return nil }
            if polishedBinding != nil {
                // Polished body: timings are pinned to the RAW words → track
                // progress proportionally instead (same rule as the old view).
                guard let player, player.duration > 0 else { return nil }
                return min(wordRanges.count - 1, Int(t / player.duration * Double(wordRanges.count)))
            }
            guard !timings.isEmpty, let global = Karaoke.activeWordIndex(timings, at: t) else { return nil }
            let local = global - sidecarOffset
            guard local >= 0 else { return nil }                  // still inside the quote block
            return min(local, wordRanges.count - 1)
        }

        private func repaint(at t: TimeInterval, full: Bool) {
            guard let tv = textView else { return }
            let active = activeLocal(at: t)
            guard full || active != lastActive else { return }
            let storage = tv.textStorage
            let dim = UIColor(Color.skTextDim), accent = UIColor(Color.skAccent), base = UIColor(Color.skText)
            storage.beginEditing()
            if full {
                for (i, r) in wordRanges.enumerated() where r.upperBound <= storage.length {
                    let color = active.map { i < $0 ? dim : (i == $0 ? accent : base) } ?? base
                    storage.addAttribute(.foregroundColor, value: color, range: r)
                }
            } else {
                // Recolor only the span between the old and new active word —
                // at speech rate that's 1–2 words, not the whole document.
                let lo = min(lastActive ?? 0, active ?? 0)
                let hi = max(lastActive ?? 0, active ?? 0)
                for i in lo...hi where i < wordRanges.count {
                    let r = wordRanges[i]
                    guard r.upperBound <= storage.length else { continue }
                    let color = active.map { i < $0 ? dim : (i == $0 ? accent : base) } ?? base
                    storage.addAttribute(.foregroundColor, value: color, range: r)
                }
            }
            storage.endEditing()
            lastActive = active
        }

        /// Reset every non-attachment run to the base text color (before painting
        /// starts / after it ends). Attachments and layout are untouched.
        private func stripColors() {
            guard let tv = textView, tv.textStorage.length > 0 else { return }
            let storage = tv.textStorage
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.enumerateAttribute(.attachment, in: full) { attachment, range, _ in
                guard attachment == nil else { return }
                storage.removeAttribute(.underlineStyle, range: range)
                storage.removeAttribute(.underlineColor, range: range)
                storage.removeAttribute(.backgroundColor, range: range)
                storage.addAttribute(.foregroundColor, value: UIColor(Color.skText), range: range)
            }
            storage.endEditing()
        }

        private func rebuildWordRanges() {
            guard let tv = textView else { wordRanges = []; return }
            wordRanges = KaraokeMap.wordRanges(in: tv.textStorage.string as NSString)
        }

        // MARK: name tiers (styling + hit-test)

        func updateSpans(_ spans: [NameSpan]) {
            nameSpans = spans
            applyTierStyling()
        }

        /// Re-color the name spans over the base text. Idempotent; skipped while
        /// the karaoke painter owns the colors.
        func applyTierStyling() {
            guard !painting, let tv = textView else { return }
            let storage = tv.textStorage
            let full = NSRange(location: 0, length: storage.length)
            guard full.length > 0 else { displaySpans = []; return }
            let sel = tv.selectedRange
            storage.beginEditing()
            storage.enumerateAttribute(.attachment, in: full) { attachment, range, _ in
                guard attachment == nil else { return }
                storage.removeAttribute(.underlineStyle, range: range)
                storage.removeAttribute(.underlineColor, range: range)
                storage.removeAttribute(.backgroundColor, range: range)
                storage.addAttribute(.foregroundColor, value: UIColor(Color.skText), range: range)
            }
            var built: [(NSRange, NameSpan)] = []
            let text = protectedQuote?.ramble ?? bodyText
            for span in nameSpans {
                guard let dr = displayRange(forRaw: span.range, transcript: text),
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

        /// Map a RAW-text range to the DISPLAYED range: each `[[img_NNN]]` marker
        /// before it collapses to one attachment glyph. nil if it straddles a marker.
        private func displayRange(forRaw raw: NSRange, transcript: String) -> NSRange? {
            let ns = transcript as NSString
            guard ns.length > 0, let rx = try? NSRegularExpression(pattern: #"\[\[img_\d+\]\]"#) else { return raw }
            var delta = 0
            for m in rx.matches(in: transcript, range: NSRange(location: 0, length: ns.length)) {
                if m.range.location + m.range.length <= raw.location {
                    delta += m.range.length - 1
                } else if m.range.location < raw.location + raw.length {
                    return nil
                } else {
                    break
                }
            }
            let loc = raw.location - delta
            return loc >= 0 ? NSRange(location: loc, length: raw.length) : nil
        }

        /// The name span under a point. `closestPosition(to:)` snaps the tap to
        /// the nearest character, so a tap at a name's edge still resolves; ±1
        /// char of tolerance keeps short names comfortable.
        func spanAt(_ point: CGPoint) -> NameSpan? {
            guard let tv = textView, !displaySpans.isEmpty,
                  let idx = tv.characterIndex(at: point) else { return nil }
            for entry in displaySpans {
                let r = entry.range
                if idx >= r.location - 1 && idx <= r.location + r.length { return entry.span }
            }
            return nil
        }

        // MARK: tap routing

        /// PLAYING-mode word-seek. (While editable, the system text interaction
        /// swallows single taps before this recognizer — DevLog-proven — so name
        /// taps route through the selection delegate below instead.)
        @objc func handleTap(_ gr: UITapGestureRecognizer) {
            guard gr.state == .ended, currentMode == .playing, tapToSeek,
                  let tv = textView, let player else { return }
            let point = gr.location(in: tv)
            // Taps on the hosted header/footer belong to their SwiftUI content.
            guard !tv.pointIsInAccessory(point) else { return }
            guard let charIndex = tv.characterIndex(at: point),
                  let local = KaraokeMap.wordIndex(at: charIndex, in: wordRanges) else { return }
            if polishedBinding != nil {
                guard player.duration > 0, !wordRanges.isEmpty else { return }
                player.seek(to: max(0, min(Double(local) / Double(wordRanges.count) * player.duration,
                                           player.duration)))
            } else {
                let global = local + sidecarOffset
                guard global >= 0, global < timings.count else { return }
                player.seek(to: timings[global].start)
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        // MARK: name taps (via the selection, not a gesture)

        /// The tap that STARTS an editing session places the caret at the tapped
        /// character — if that lands in a name span, the tap was on the name:
        /// yield the keyboard to the resolve sheet (same behaviour the old editor
        /// implemented with a gesture, which the scrolling text view's system
        /// interactions no longer let through). While ALREADY editing, taps stay
        /// plain caret placement — you're writing, not resolving.
        private var editingBeganAt: Date?

        func textViewDidBeginEditing(_ tv: UITextView) {
            editingBeganAt = Date()
            // UIKit's delegate order on a tap-to-focus varies: the caret can be
            // placed BEFORE didBeginEditing (no later selection callback comes),
            // so check the landing caret here too.
            resolveNameAtCaret(tv)
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            guard tv.isFirstResponder,
                  let began = editingBeganAt, Date().timeIntervalSince(began) < 0.35 else { return }
            resolveNameAtCaret(tv)
        }

        /// If the caret the focus-gaining tap just placed sits inside a name
        /// span, the tap was ON the name — yield the keyboard to the resolve
        /// sheet. While already editing, taps stay plain caret placement.
        private func resolveNameAtCaret(_ tv: UITextView) {
            guard currentMode == .editing, tv.selectedRange.length == 0 else { return }
            // ±1 char of tolerance: a tap at a name's leading edge places the
            // caret one position BEFORE the span (DevLog-traced: "…with |Jack"
            // lands at 11 for a span at 12).
            let idx = tv.selectedRange.location
            guard let hit = displaySpans.first(where: {
                idx >= $0.range.location - 1 && idx <= $0.range.location + $0.range.length
            }) else { return }
            editingBeganAt = nil
            tv.resignFirstResponder()
            Haptics.tap(.light)
            onTapName(hit.span)
        }

        // MARK: editing / debounced commit

        func textViewDidChange(_ tv: UITextView) {
            draftDirty = true
            (tv as? NoteBodyTextView)?.setNeedsAccessoryLayout()
            commitTask?.cancel()
            commitTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.commitDraft()
            }
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            commitDraft()
            applyTierStyling()
        }

        /// Persist the draft: reconstruct the marker string from the attributed
        /// text and write it to the model (quote-protected for captures, the
        /// copy-edit binding for polished bodies), flag the user edit, save.
        func commitDraft() {
            commitTask?.cancel()
            commitTask = nil
            guard draftDirty, let tv = textView else { return }
            draftDirty = false
            let text = reconstruct(tv.attributedText)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let binding = polishedBinding {
                binding.wrappedValue = text          // setter stamps provenance
                loaded = text
            } else if let quote = protectedQuote {
                // The editor held ONLY the ramble — re-prepend the raw "> " block
                // verbatim so the stored quote is untouchable.
                memo.transcript = quote.transcript(withRamble: text)
                memo.transcriptStatus = .done
                loaded = memo.transcript
            } else {
                let wasNonEmpty = !(loaded ?? "").isEmpty
                memo.transcript = trimmed.isEmpty ? nil : text
                if !trimmed.isEmpty { memo.transcriptStatus = .done }
                if trimmed.isEmpty && wasNonEmpty {
                    DevLog.log("editor cleared body → transcript=nil memo \(memo.id)")
                }
                loaded = memo.transcript ?? ""
            }
            memo.transcriptUserEdited = true         // Mac trusts it → no re-transcribe
            rebuildWordRanges()
            onCommit()
        }

        // MARK: attributed text ⇄ marker string (round-trip)

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
                    // Match the writer's zero-padded format (ImageMarkers %03d) —
                    // the old editor re-emitted "[[img_1]]" and drifted the format.
                    out.append("[[img_\(String(format: "%03d", marker))]]")
                } else if attrs[.attachment] == nil {
                    out.append(full.substring(with: range))
                }                                                  // untagged attachment → drop
            }
            return out as String
        }

        private func imageAttachment(markerIndex: Int) -> NSTextAttachment {
            let att = NSTextAttachment()
            let width = contentWidth
            if let url = memo.imageURL(markerIndex: markerIndex),
               let img = MemoImageLoader.thumbnail(at: url, maxWidth: width) {
                att.image = img
                // NSTextAttachment scales to FILL `bounds` (no aspect preserve),
                // so bounds must match the image aspect. Fit width × 320-pt cap;
                // a portrait frame shrinks WIDTH to keep aspect.
                let aspect = img.size.width / max(1, img.size.height)
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
            return UIGraphicsImageRenderer(size: size).image { _ in
                UIColor(Color.skElev).setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 14).fill()
                let icon = UIImage(systemName: "photo")?
                    .withTintColor(UIColor(Color.skTextFaint), renderingMode: .alwaysOriginal)
                if let icon {
                    let s: CGFloat = 34
                    icon.draw(in: CGRect(x: (size.width - s) / 2, y: (size.height - s) / 2, width: s, height: s))
                }
            }
        }
    }
}

// MARK: - The scrolling text view with hosted header/footer

/// A `UITextView` whose scroll content also carries a SwiftUI HEADER above the
/// text and FOOTER below it: the hosted views are subviews (so they scroll with
/// the content) and the text container insets make room for them. Heights are
/// re-measured whenever the width or the hosted content changes.
final class NoteBodyTextView: UITextView {
    private let headerHost = UIHostingController(rootView: AnyView(EmptyView()))
    private let footerHost = UIHostingController(rootView: AnyView(EmptyView()))
    private var headerHeight: CGFloat = 0
    private var footerHeight: CGFloat = 0
    private var measuredWidth: CGFloat = 0
    private var needsAccessoryLayout = true

    /// Insets the TEXT keeps clear regardless of accessories (set once at make).
    var baseTextInsets = UIEdgeInsets(top: 10, left: 20, bottom: 24, right: 20)

    func installAccessoryHosts() {
        baseTextInsets = textContainerInset
        for host in [headerHost, footerHost] {
            host.view.backgroundColor = .clear
            if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
            addSubview(host.view)
        }
    }

    func setAccessories(header: AnyView, footer: AnyView) {
        headerHost.rootView = header
        footerHost.rootView = footer
        setNeedsAccessoryLayout()
    }

    func setNeedsAccessoryLayout() {
        needsAccessoryLayout = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        guard width > 0 else { return }
        if needsAccessoryLayout || abs(width - measuredWidth) > 0.5 {
            needsAccessoryLayout = false
            measuredWidth = width
            let fit = CGSize(width: width, height: .greatestFiniteMagnitude)
            headerHeight = ceil(headerHost.sizeThatFits(in: fit).height)
            footerHeight = ceil(footerHost.sizeThatFits(in: fit).height)
            let insets = UIEdgeInsets(top: baseTextInsets.top + headerHeight,
                                      left: baseTextInsets.left,
                                      bottom: baseTextInsets.bottom + footerHeight,
                                      right: baseTextInsets.right)
            if textContainerInset != insets { textContainerInset = insets }
        }
        // Subview frames are in CONTENT coordinates, so they scroll with the text.
        headerHost.view.frame = CGRect(x: 0, y: 0, width: width, height: headerHeight)
        // The text ends at contentSize.height − bottom inset; the footer sits in
        // the reserved bottom inset (no full-document layout pass needed).
        let footerY = contentSize.height - baseTextInsets.bottom - footerHeight + 8
        footerHost.view.frame = CGRect(x: 0, y: max(footerY, headerHeight),
                                       width: width, height: footerHeight)
    }

    // MARK: geometry helpers (TextKit-2 first, TextKit-1 fallback)

    /// Hide this page's whole UIKit subtree from the accessibility tree while
    /// it's an off-screen pager neighbour: the hosted header/footer stop
    /// exposing their buttons, and the text view drops its identifier so
    /// "transcript-editor" matches exactly the CURRENT page.
    func setAccessibilityHidden(_ hidden: Bool) {
        accessibilityElementsHidden = hidden
        headerHost.view.accessibilityElementsHidden = hidden
        footerHost.view.accessibilityElementsHidden = hidden
        accessibilityIdentifier = hidden ? "transcript-editor-offscreen" : "transcript-editor"
    }

    /// Whether a point (view coordinates) lands on the hosted header/footer.
    func pointIsInAccessory(_ point: CGPoint) -> Bool {
        headerHost.view.frame.contains(point) || footerHost.view.frame.contains(point)
    }

    /// Character index at a point in VIEW coordinates (nil outside the text).
    func characterIndex(at point: CGPoint) -> Int? {
        guard let pos = closestPosition(to: point) else { return nil }
        return offset(from: beginningOfDocument, to: pos)
    }

    /// The drawn rect(s) of a character range, in VIEW coordinates.
    func rects(forCharacterRange range: NSRange) -> [CGRect] {
        guard let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length),
              let textRange = textRange(from: start, to: end) else { return [] }
        return selectionRects(for: textRange).map(\.rect).filter { !$0.isEmpty }
    }
}
