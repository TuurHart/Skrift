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
    /// A focus-gaining tap landed on an inline photo → the page opens the viewer.
    var onTapImage: (Int) -> Void = { _ in }
    /// A focus-gaining tap landed on a memo-link chip → the page opens that memo.
    var onTapMemoLink: (UUID) -> Void = { _ in }
    /// "[[" was typed → the page presents the memo picker; the pick comes back
    /// through `proxy.insertMemoLink`.
    var onRequestMemoLink: () -> Void = {}
    /// The accessory bar's 📷 — the page presents the photo picker, then hands
    /// the image back through `proxy.insertPhoto`.
    var onRequestPhoto: () -> Void = {}
    /// Page-side handle into the coordinator (photo insertion from the picker).
    var proxy: NoteBodyProxy? = nil

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
        tv.font = Coordinator.bodyFont()
        tv.adjustsFontForContentSizeCategory = true      // Dynamic Type
        tv.isFindInteractionEnabled = true               // system find-in-note
        tv.tintColor = UIColor(Color.skAccent)
        tv.keyboardDismissMode = .interactive
        tv.delegate = context.coordinator
        tv.accessibilityIdentifier = "transcript-editor"
        tv.installAccessoryHosts()
        context.coordinator.installAccessoryBar(on: tv)

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

        context.coordinator.observeEnvironment()
        context.coordinator.load(force: true)
        proxy?.coordinator = context.coordinator
        return tv
    }

    func updateUIView(_ tv: NoteBodyTextView, context: Context) {
        let c = context.coordinator
        c.memo = memo
        c.player = player
        c.onTapName = onTapName
        c.onTapImage = onTapImage
        c.onTapMemoLink = onTapMemoLink
        c.onRequestPhoto = onRequestPhoto
        c.onRequestMemoLink = onRequestMemoLink
        c.polishedBinding = polishedBinding
        c.tapToSeek = tapToSeek
        proxy?.coordinator = c

        tv.setAccessories(header: header, footer: footer)
        tv.setAccessibilityHidden(a11yHidden)

        c.load(force: false)                    // re-render only if the text changed under us
        c.apply(mode: mode)                     // editable / painter / read-only

        // Re-style when the tiers changed (a resolution applied) — never mid-edit
        // (offsets drift while typing), never while the painter owns the colors,
        // and never over a LIVE selection: SwiftUI re-evals storm during an
        // interactive keyboard dismiss, and a full-document restyle per re-eval
        // reflows the text under the visible selection handles (device round 1:
        // "markers follow the viewport"). Styling lands at the next end-editing.
        if !tv.isFirstResponder && tv.selectedRange.length == 0 && mode == .editing {
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
        var onTapImage: (Int) -> Void = { _ in }
        var onTapMemoLink: (UUID) -> Void = { _ in }
        var onRequestPhoto: () -> Void = {}
        var onRequestMemoLink: () -> Void = {}
        var tapToSeek = true
        private var accessory: NoteAccessoryBar?
        /// Caret at the moment 📷 was tapped — the picker's insert target.
        private var pendingPhotoLocation: Int?
        /// The "[[" the user just typed — replaced by the picked link chip.
        private var pendingLinkTrigger: NSRange?

        /// The transcript string our attributed text currently reflects.
        private var loaded: String?
        /// Uncommitted edits exist in the view (debounce window).
        private var draftDirty = false
        private var commitTask: Task<Void, Never>?
        private var resignObserver: NSObjectProtocol?
        private var sizeObserver: NSObjectProtocol?

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
        /// Custom attribute tagging a checkbox attachment with its checked state
        /// — reconstructs to Obsidian task syntax ("- [ ]" / "- [x]").
        static let taskKey = NSAttributedString.Key("skriftTask")
        /// Custom attribute tagging a memo-link chip: value = "UUID|Title" —
        /// reconstructs to the raw `[[memo:UUID|Title]]` syntax.
        static let memoLinkKey = NSAttributedString.Key("skriftMemoLink")

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

        func observeEnvironment() {
            resignObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.commitDraft() }
            }
            sizeObserver = NotificationCenter.default.addObserver(
                forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                // Rebuild the attributed text with the freshly scaled body font.
                MainActor.assumeIsolated {
                    guard let self, let tv = self.textView else { return }
                    tv.font = Coordinator.bodyFont()
                    self.load(force: true)
                }
            }
        }

        func teardown() {
            clockSub?.cancel()
            commitTask?.cancel()
            for o in [resignObserver, sizeObserver].compactMap({ $0 }) {
                NotificationCenter.default.removeObserver(o)
            }
            resignObserver = nil
            sizeObserver = nil
        }

        /// The body font, scaled for Dynamic Type (15.5 pt at the default size).
        static func bodyFont() -> UIFont {
            UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 15.5))
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
            DevLog.log("noteBody: load rebuild force=\(force) len=\(display.count)")
            let selection = tv.selectedRange
            tv.attributedText = attributed(from: display)
            let length = tv.attributedText.length
            let location = min(selection.location, length)
            let carried = NSRange(location: location, length: min(selection.length, length - location))
            if tv.selectedRange != carried { tv.selectedRange = carried }
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
            // Unchanged spans = nothing to restyle. Without this, every SwiftUI
            // re-eval (keyboard frames, sheet presentations) re-ran the full
            // attribute rewrite — churn that reflowed text during scroll.
            guard spans != nameSpans else { return }
            nameSpans = spans
            DevLog.log("noteBody: restyle spans=\(spans.count)")
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
            let restored = NSRange(location: loc, length: min(sel.length, len - loc))
            // Restore ONLY if the attribute pass actually moved the selection
            // (it shouldn't — attribute edits preserve it). A redundant
            // selectedRange write makes iOS 26 rebuild the whole selection UI,
            // which is churn exactly when handles are on screen.
            if tv.selectedRange != restored {
                DevLog.log("noteBody: tierStyle moved sel \(NSStringFromRange(tv.selectedRange)) → \(NSStringFromRange(restored))")
                tv.selectedRange = restored
            }
        }

        /// Map a RAW-text range to the DISPLAYED range — every `[[img_NNN]]`
        /// marker AND task prefix before it collapses to one glyph (the shared
        /// BodyTransform, so this can never drift from the attributed builder).
        private func displayRange(forRaw raw: NSRange, transcript: String) -> NSRange? {
            guard !transcript.isEmpty else { return raw }
            return BodyTransform.displayRange(forRaw: raw, in: transcript)
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

        /// Every touch bound for our tap recognizer also stashes its down-point
        /// — belt and braces beside `touchesBegan` (the system text
        /// interactions can swallow the recognizer's ACTION, but touches still
        /// pass through here; the DevLog-proven build-31 finding).
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if let tv = textView { tv.noteTouchDown(touch.location(in: tv)) }
            return true
        }

        // MARK: keyboard accessory (undo · redo · find · photo · Done)

        func installAccessoryBar(on tv: NoteBodyTextView) {
            let bar = NoteAccessoryBar()
            bar.onUndo = { [weak self, weak tv] in
                tv?.undoManager?.undo()
                self?.refreshAccessory()
            }
            bar.onRedo = { [weak self, weak tv] in
                tv?.undoManager?.redo()
                self?.refreshAccessory()
            }
            bar.onFind = { [weak tv] in
                tv?.findInteraction?.presentFindNavigator(showingReplace: false)
            }
            bar.onPhoto = { [weak self] in
                guard let self, let tv = self.textView else { return }
                self.pendingPhotoLocation = tv.selectedRange.location
                self.onRequestPhoto()
            }
            bar.onDone = { [weak self, weak tv] in
                self?.commitDraft()
                tv?.resignFirstResponder()
            }
            tv.inputAccessoryView = bar
            accessory = bar
        }

        private func refreshAccessory() {
            accessory?.refresh(canUndo: textView?.undoManager?.canUndo ?? false,
                               canRedo: textView?.undoManager?.canRedo ?? false)
        }

        /// Insert a picked photo AT THE CARET: the file lands in the recordings
        /// directory under the manifest convention (photo_<memoID>_<NNN>.jpg),
        /// the manifest gains its entry, and the marker's attachment goes into
        /// the text (own paragraph). The caller registers the file for CloudKit
        /// (AssetMaterializer) after the commit.
        func insertPhoto(_ image: UIImage) {
            guard let tv = textView, currentMode == .editing,
                  let jpeg = image.jpegData(compressionQuality: 0.85) else { return }
            let index = (memo.metadata?.imageManifest?.count ?? 0) + 1
            let filename = "photo_\(memo.id.uuidString)_\(String(format: "%03d", index)).jpg"
            let dest = AppPaths.recordingsDirectory.appendingPathComponent(filename)
            do { try jpeg.write(to: dest) } catch {
                DevLog.log("insertPhoto: write failed \(error)")
                return
            }
            var meta = memo.metadata ?? MemoMetadata()
            var manifest = meta.imageManifest ?? []
            manifest.append(ImageManifestEntry(filename: filename, offsetSeconds: 0))
            meta.imageManifest = manifest
            memo.metadata = meta

            let at = min(pendingPhotoLocation ?? tv.selectedRange.location, tv.textStorage.length)
            pendingPhotoLocation = nil
            let piece = NSMutableAttributedString(string: "\n", attributes: baseAttributes())
            let att = NSMutableAttributedString(attachment: imageAttachment(markerIndex: index))
            att.addAttribute(Self.markerKey, value: index, range: NSRange(location: 0, length: att.length))
            piece.append(att)
            piece.append(NSAttributedString(string: "\n", attributes: baseAttributes()))
            tv.textStorage.insert(piece, at: at)
            tv.selectedRange = NSRange(location: at + piece.length, length: 0)
            textViewDidChange(tv)
            commitDraft()          // persist text + manifest atomically
        }

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
            refreshAccessory()
            // UIKit's delegate order on a tap-to-focus varies: the caret can be
            // placed BEFORE didBeginEditing (no later selection callback comes),
            // so check the landing caret here too.
            resolveNameAtCaret(tv)
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            // Round-1 P1#1 evidence: a selection that CHANGES while the view is
            // not first responder (keyboard interactively dismissed, handles
            // still up) means something is rewriting it under the scroll —
            // exactly the "handles follow the viewport" report. Rare state, so
            // this can't flood the ring buffer.
            if !tv.isFirstResponder, currentMode == .editing, tv.selectedRange.length > 0 {
                DevLog.log("noteBody: sel-noFR \(NSStringFromRange(tv.selectedRange))")
            }
            guard tv.isFirstResponder,
                  let began = editingBeganAt, Date().timeIntervalSince(began) < 0.35 else { return }
            resolveNameAtCaret(tv)
        }

        /// If the caret the focus-gaining tap just placed sits inside a name
        /// span, the tap was ON the name — yield the keyboard to the resolve
        /// sheet. Attachment taps (checkbox / photo / memo-link chip) resolve
        /// from the TOUCH POINT against the glyph's drawn rect instead. While
        /// already editing, taps stay plain caret placement.
        private func resolveNameAtCaret(_ tv: UITextView) {
            guard currentMode == .editing, tv.selectedRange.length == 0 else { return }
            // Attachments: anchored on the TOUCHED character and gated on the
            // glyph's drawn rect — the old caret-adjacency probe was too greedy
            // for photos (a tap in the empty space beside a portrait photo
            // landed the caret adjacent and opened the viewer) and too tight
            // for checkboxes (a caret snapping past the following space never
            // toggled). Device round 1, build 31.
            if let touch = (tv as? NoteBodyTextView)?.recentTouchPoint {
                switch attachmentAction(at: touch) {
                case .toggleTask(let index):
                    editingBeganAt = nil
                    tv.resignFirstResponder()
                    toggleTask(at: index)
                    return
                case .openMemo(let id):
                    editingBeganAt = nil
                    tv.resignFirstResponder()
                    Haptics.tap(.light)
                    onTapMemoLink(id)
                    return
                case .openImage(let marker):
                    editingBeganAt = nil
                    tv.resignFirstResponder()
                    onTapImage(marker)
                    return
                case nil:
                    break
                }
            }
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

        /// What a focus-gaining tap on an attachment should do.
        enum AttachmentAction: Equatable {
            case toggleTask(at: Int)
            case openImage(marker: Int)
            case openMemo(UUID)
        }

        /// The attachment action for a touch at `touch` (view coordinates), or
        /// nil when the touch isn't on an attachment glyph. Anchored on the
        /// touched character — `closestPosition` is geometric, so it can't be
        /// fooled by wherever the caret snapped — and gated on the glyph's
        /// drawn rect(s). Small glyphs get finger-sized slop (a checkbox is
        /// ~20 pt; ±12 pt horizontal reaches Apple's 44-pt target), photos are
        /// their own huge target and get none.
        func attachmentAction(at touch: CGPoint) -> AttachmentAction? {
            guard let tv = textView, let anchor = tv.characterIndex(at: touch) else { return nil }
            let storage = tv.textStorage
            for probe in [anchor, anchor - 1, anchor + 1, anchor - 2, anchor + 2]
            where probe >= 0 && probe < storage.length {
                func hits(slopX: CGFloat, slopY: CGFloat) -> Bool {
                    tv.rects(forCharacterRange: NSRange(location: probe, length: 1))
                        .contains { $0.insetBy(dx: -slopX, dy: -slopY).contains(touch) }
                }
                if storage.attribute(Self.taskKey, at: probe, effectiveRange: nil) is Bool,
                   hits(slopX: 12, slopY: 6) {
                    return .toggleTask(at: probe)
                }
                if let payload = storage.attribute(Self.memoLinkKey, at: probe,
                                                   effectiveRange: nil) as? String,
                   let id = UUID(uuidString: String(payload.prefix(36))),
                   hits(slopX: 4, slopY: 4) {
                    return .openMemo(id)
                }
                if let marker = storage.attribute(Self.markerKey, at: probe,
                                                  effectiveRange: nil) as? Int,
                   hits(slopX: 0, slopY: 0) {
                    return .openImage(marker: marker)
                }
            }
            return nil
        }

        // MARK: checklist continuation (Apple Notes flow)

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            guard text == "\n", range.length == 0 else { return true }
            return !continueChecklist(tv, at: range.location)
        }

        /// Return inside a task line continues the list with a fresh unchecked
        /// box; Return on an EMPTY task item ends the list (the box dissolves
        /// into a plain line) — round-1 P2#8, the Notes idiom. True = handled.
        private func continueChecklist(_ tv: UITextView, at caret: Int) -> Bool {
            let ns = tv.textStorage.string as NSString
            guard caret <= ns.length, ns.length > 0 else { return false }
            let line = ns.lineRange(for: NSRange(location: min(caret, ns.length), length: 0))
            guard line.length > 0,
                  tv.textStorage.attribute(Self.taskKey, at: line.location,
                                           effectiveRange: nil) is Bool
            else { return false }

            // The line past its 1-char box glyph, without the trailing newline.
            let contentStart = line.location + 1
            let lineEnd = line.location + line.length
            let hasNewline = lineEnd > line.location && ns.character(at: lineEnd - 1) == 10
            let contentEnd = hasNewline ? lineEnd - 1 : lineEnd
            let content = contentStart < contentEnd
                ? ns.substring(with: NSRange(location: contentStart,
                                             length: contentEnd - contentStart)) : ""

            if content.trimmingCharacters(in: .whitespaces).isEmpty {
                // Empty item → end the list here.
                tv.textStorage.replaceCharacters(
                    in: NSRange(location: line.location, length: contentEnd - line.location),
                    with: NSAttributedString(string: "", attributes: baseAttributes()))
                tv.selectedRange = NSRange(location: line.location, length: 0)
                textViewDidChange(tv)
                return true
            }

            // Split/continue: a space right after the caret is consumed (Notes
            // trims the split tail), then "\n" + fresh box + " ".
            var insertAt = caret
            if insertAt < contentEnd, ns.character(at: insertAt) == 32 {
                tv.textStorage.deleteCharacters(in: NSRange(location: insertAt, length: 1))
            }
            let piece = NSMutableAttributedString(string: "\n", attributes: baseAttributes())
            let box = NSMutableAttributedString(attachment: Self.taskAttachment(checked: false))
            box.addAttribute(Self.taskKey, value: false,
                             range: NSRange(location: 0, length: box.length))
            box.addAttributes(baseAttributes(), range: NSRange(location: 0, length: box.length))
            piece.append(box)
            piece.append(NSAttributedString(string: " ", attributes: baseAttributes()))
            tv.textStorage.insert(piece, at: insertAt)
            tv.selectedRange = NSRange(location: insertAt + piece.length, length: 0)
            textViewDidChange(tv)
            return true
        }

        // MARK: editing / debounced commit

        func textViewDidChange(_ tv: UITextView) {
            draftDirty = true
            refreshAccessory()
            detectLinkTrigger(tv)
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
            // Task syntax TYPED during this session is still literal text in the
            // display — materialize it into live checkboxes now that the
            // keyboard is down (rebuilding mid-typing would fight the caret).
            if BodyTransform.containsTaskSyntax(tv.text) {
                load(force: true)
            }
            applyTierStyling()
        }

        /// Flip a checkbox attachment in place and persist immediately (a toggle
        /// is a decisive act — no debounce window).
        func toggleTask(at index: Int) {
            guard let tv = textView,
                  let checked = tv.textStorage.attribute(Self.taskKey, at: index,
                                                         effectiveRange: nil) as? Bool else { return }
            let sel = tv.selectedRange
            let piece = NSMutableAttributedString(attachment: Self.taskAttachment(checked: !checked))
            piece.addAttribute(Self.taskKey, value: !checked, range: NSRange(location: 0, length: piece.length))
            piece.addAttributes(baseAttributes(), range: NSRange(location: 0, length: piece.length))
            tv.textStorage.replaceCharacters(in: NSRange(location: index, length: 1), with: piece)
            let len = tv.textStorage.length
            tv.selectedRange = NSRange(location: min(sel.location, len), length: 0)
            Haptics.tap(.light)
            draftDirty = true
            commitDraft()
            applyTierStyling()          // re-derive display spans over the same offsets
        }

        /// One memo-link chip as an attributed piece (attachment + the raw
        /// payload in `memoLinkKey`, so it round-trips byte-exact).
        static func memoLinkPiece(id: UUID, title: String,
                                  base: [NSAttributedString.Key: Any]) -> NSAttributedString {
            let a = NSMutableAttributedString(attachment: memoLinkAttachment(title: title))
            let r = NSRange(location: 0, length: a.length)
            a.addAttribute(memoLinkKey, value: "\(id.uuidString)|\(title)", range: r)
            a.addAttributes(base, range: r)
            return a
        }

        /// The chip image: "→ Title" in accent on a soft pill — atomic (one
        /// glyph), so typing next to it can never extend the link.
        static func memoLinkAttachment(title: String) -> NSTextAttachment {
            let font = UIFont.systemFont(ofSize: bodyFont().pointSize - 1.5, weight: .medium)
            let display = title.isEmpty ? "Untitled" : (title.count > 28 ? title.prefix(27) + "…" : title)
            let text = "→ \(display)" as NSString
            let textSize = text.size(withAttributes: [.font: font])
            let padH: CGFloat = 8, padV: CGFloat = 3
            let size = CGSize(width: ceil(textSize.width) + padH * 2,
                              height: ceil(textSize.height) + padV * 2)
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                UIColor(Color.skAccentSoft).setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 7).fill()
                text.draw(at: CGPoint(x: padH, y: padV),
                          withAttributes: [.font: font, .foregroundColor: UIColor(Color.skNameLinked)])
            }
            let att = NSTextAttachment()
            att.image = image
            att.bounds = CGRect(x: 0, y: -5.5, width: size.width, height: size.height)
            return att
        }

        /// Replace the typed "[[" trigger with a link chip to the picked memo
        /// (falls back to the caret if the trigger moved), then persist.
        func insertMemoLink(id: UUID, title: String) {
            guard let tv = textView, currentMode == .editing else { return }
            let storage = tv.textStorage
            var at = min(pendingLinkTrigger?.location ?? tv.selectedRange.location, storage.length)
            if let trigger = pendingLinkTrigger,
               trigger.location + trigger.length <= storage.length,
               storage.attributedSubstring(from: trigger).string == "[[" {
                storage.deleteCharacters(in: trigger)
                at = trigger.location
            }
            pendingLinkTrigger = nil
            let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let piece = NSMutableAttributedString(
                attributedString: Self.memoLinkPiece(id: id,
                                                     title: clean.isEmpty ? "Untitled" : clean,
                                                     base: baseAttributes()))
            piece.append(NSAttributedString(string: " ", attributes: baseAttributes()))
            storage.insert(piece, at: at)
            tv.selectedRange = NSRange(location: at + piece.length, length: 0)
            draftDirty = true
            commitDraft()
        }

        /// "[[" just typed → stash its range and ask the page for the picker.
        private func detectLinkTrigger(_ tv: UITextView) {
            let caret = tv.selectedRange.location
            guard caret >= 2, tv.selectedRange.length == 0 else { return }
            let r = NSRange(location: caret - 2, length: 2)
            guard tv.textStorage.attributedSubstring(from: r).string == "[[",
                  tv.textStorage.attribute(.attachment, at: r.location, effectiveRange: nil) == nil
            else { return }
            pendingLinkTrigger = r
            onRequestMemoLink()
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
            return [.font: Coordinator.bodyFont(),
                    .foregroundColor: UIColor(Color.skText),
                    .paragraphStyle: para]
        }

        private func attributed(from transcript: String) -> NSAttributedString {
            let result = NSMutableAttributedString()
            let base = baseAttributes()
            for piece in BodyTransform.pieces(of: transcript) {
                switch piece.segment {
                case .text(let s):
                    result.append(NSAttributedString(string: s, attributes: base))
                case .image(let n):
                    let a = NSMutableAttributedString(attachment: imageAttachment(markerIndex: n))
                    a.addAttribute(Self.markerKey, value: n, range: NSRange(location: 0, length: a.length))
                    result.append(a)
                case .task(let checked):
                    let a = NSMutableAttributedString(attachment: Self.taskAttachment(checked: checked))
                    a.addAttribute(Self.taskKey, value: checked, range: NSRange(location: 0, length: a.length))
                    a.addAttributes(base, range: NSRange(location: 0, length: a.length))
                    result.append(a)
                case .memoLink(let id, let title):
                    result.append(Self.memoLinkPiece(id: id, title: title, base: base))
                }
            }
            return result
        }

        /// The checkbox glyph for a task line — SF square / checkmark.square.fill,
        /// scaled with the body font, accent when checked.
        static func taskAttachment(checked: Bool) -> NSTextAttachment {
            let side = bodyFont().pointSize + 4
            let config = UIImage.SymbolConfiguration(pointSize: side - 4, weight: .medium)
            let color = checked ? UIColor(Color.skAccent) : UIColor(Color.skTextDim)
            let image = UIImage(systemName: checked ? "checkmark.square.fill" : "square",
                                withConfiguration: config)?
                .withTintColor(color, renderingMode: .alwaysOriginal)
            let att = NSTextAttachment()
            att.image = image
            att.bounds = CGRect(x: 0, y: -3.5, width: side, height: side)
            return att
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
                } else if let checked = attrs[Self.taskKey] as? Bool {
                    out.append(BodyTransform.rawTask(checked: checked))
                } else if let payload = attrs[Self.memoLinkKey] as? String {
                    out.append("[[memo:\(payload)]]")
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

// MARK: - Page-side handle

/// Lets the page hand a picked photo into the live coordinator (the picker is
/// presented by SwiftUI at page level; the insertion happens at the caret the
/// accessory captured). @State-held, so identity survives body re-evals.
@MainActor
final class NoteBodyProxy {
    weak var coordinator: NoteBodyView.Coordinator?
    func insertPhoto(_ image: UIImage) { coordinator?.insertPhoto(image) }
    func insertMemoLink(id: UUID, title: String) { coordinator?.insertMemoLink(id: id, title: title) }
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

    /// Touch-down point of the most recent touch, view coordinates — the
    /// selection delegate gates attachment taps on the glyph's DRAWN rect
    /// (the caret alone was too greedy/too tight; device round 1, build 31).
    /// Stale after 0.6 s so a keyboard-driven caret move can't replay it.
    private var lastTouchDown: (point: CGPoint, at: Date)?

    var recentTouchPoint: CGPoint? {
        guard let t = lastTouchDown, Date().timeIntervalSince(t.at) < 0.6 else { return nil }
        return t.point
    }

    func noteTouchDown(_ point: CGPoint) {
        lastTouchDown = (point, Date())
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let t = touches.first { noteTouchDown(t.location(in: self)) }
        super.touchesBegan(touches, with: event)
    }

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
            if textContainerInset != insets {
                // An inset write REFLOWS the whole text — if this fires while
                // selection handles are up, they visibly jump (round-1 suspect).
                DevLog.log("noteBody: accessory inset top \(textContainerInset.top)→\(insets.top) bottom \(textContainerInset.bottom)→\(insets.bottom)")
                textContainerInset = insets
            }
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
    /// `selectionRects` needs live display; `firstRect(for:)` is the fallback
    /// (fine for the 1-char attachment ranges the hit-testing asks about).
    func rects(forCharacterRange range: NSRange) -> [CGRect] {
        guard let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length),
              let textRange = textRange(from: start, to: end) else { return [] }
        let rects = selectionRects(for: textRange).map(\.rect).filter { !$0.isEmpty && !$0.isInfinite }
        if !rects.isEmpty { return rects }
        let first = firstRect(for: textRange)
        return (first.isEmpty || first.isInfinite || first.isNull) ? [] : [first]
    }
}
