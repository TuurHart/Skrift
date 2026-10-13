import SwiftUI
import UIKit
import Combine
import AVKit

/// Mode of the note body — same precedence the old `TranscriptBodyView` swapped
/// views on, now driving STATE of one view (editable / painter / read-only):
/// playback always wins, an in-flight transcription is read-only (an open draft
/// could clobber the landing text), else always-editable. Static + pure so tests
/// pin the precedence.
enum NoteBody {
    enum Mode: Equatable { case editing, playing, reading }

    /// `splitting`: Split speakers is running on this note — read-only like a transcription in
    /// flight, as on the Mac (Q183): the split rewrites the whole body when it lands.
    static func mode(isPlaying: Bool, status: TranscriptStatus, splitting: Bool = false) -> Mode {
        if isPlaying { return .playing }
        if status == .transcribing || splitting { return .reading }
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
    /// The text menu's "New person…" (D184): the trimmed selection to prefill the person editor.
    var onNewPersonFromSelection: (String) -> Void = { _ in }
    var polishedBinding: Binding<String>? = nil
    /// `wordsChanged`: true only when this commit wrote `memo.transcript` (the `.raw`
    /// target) — a `.polished` commit already stamps its own edit via
    /// `recordPolishedEdit` and must not ALSO stamp the (unchanged) raw words (C98).
    var onCommit: (_ wordsChanged: Bool) -> Void = { _ in }
    var header: AnyView = AnyView(EmptyView())
    var footer: AnyView = AnyView(EmptyView())
    /// Off-screen pager pages must vanish from the accessibility tree (XCUITest
    /// + VoiceOver would see 2-3 editors). SwiftUI's `.accessibilityHidden` on
    /// the page doesn't reach into this UIKit subtree, so it's driven explicitly.
    var a11yHidden: Bool = false
    /// A focus-gaining tap landed on an inline photo → the page opens the viewer.
    var onTapImage: (Int) -> Void = { _ in }
    /// D199: a tap on a video / file block → the page opens it (Quick Look plays a video).
    var onTapAttachment: (NoteAttachmentEntry) -> Void = { _ in }
    /// A focus-gaining tap landed on a memo-link chip → the page opens that memo.
    var onTapMemoLink: (UUID) -> Void = { _ in }
    /// "[[" was typed → the page presents the memo picker; the pick comes back
    /// through `proxy.insertMemoLink`.
    var onRequestMemoLink: () -> Void = {}
    /// The target memo's CURRENT title, so a chip shows the live title — not the snapshot
    /// frozen into `[[memo:UUID|Title]]` at creation (stale when the target is renamed /
    /// enhanced). nil → keep the snapshot. The raw payload always keeps the snapshot.
    var linkTitle: (UUID) -> String? = { _ in nil }
    /// The accessory bar's 📷 — the page presents the photo picker, then hands
    /// the image back through `proxy.insertPhoto`.
    var onRequestPhoto: () -> Void = {}
    /// Page-side handle into the coordinator (photo insertion from the picker).
    var proxy: NoteBodyProxy? = nil
    /// iPad reading-measure hint: the note column's capped width at regular size
    /// class (nil = compact/phone → the screen width). Drives `contentWidth` so
    /// inline images size to the 640 column, not the full iPad screen. Width cap
    /// ONLY — no scroll/selection behaviour changes.
    var readingWidthCap: CGFloat? = nil

    @AppStorage(PrefKey.karaokeTapToSeek) private var tapToSeek = PrefKey.karaokeTapToSeekDefault

    /// Observed so the body flips read-only the moment a split starts and editable when it ends.
    @ObservedObject private var diarStatus = DiarizationStatus.shared

    private var mode: NoteBody.Mode {
        NoteBody.mode(isPlaying: player.isPlaying, status: memo.transcriptStatus,
                      splitting: diarStatus.isSplitting(memo.id))
    }

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
        context.coordinator.onNewPersonFromSelection = onNewPersonFromSelection
        context.coordinator.linkTitle = linkTitle   // before load(), which builds the display
        context.coordinator.polishedBinding = polishedBinding
        context.coordinator.tapToSeek = tapToSeek
        context.coordinator.readingWidthCap = readingWidthCap

        // One tap recognizer routes: word-seek while playing, name-resolve while
        // paused; anything else falls through to normal editing.
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        tv.addGestureRecognizer(tap)
        context.coordinator.installPhotoDrag(on: tv)       // D112: long press lifts a photo

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
        c.onNewPersonFromSelection = onNewPersonFromSelection
        c.onTapImage = onTapImage
        c.onTapAttachment = onTapAttachment
        c.onTapMemoLink = onTapMemoLink
        c.onRequestPhoto = onRequestPhoto
        c.onRequestMemoLink = onRequestMemoLink
        c.linkTitle = linkTitle
        c.polishedBinding = polishedBinding
        c.tapToSeek = tapToSeek
        c.readingWidthCap = readingWidthCap
        proxy?.coordinator = c

        tv.setAccessories(header: header, footer: footer)
        tv.setAccessibilityHidden(a11yHidden)
        c.setKeyboardBarHidden(context.environment.horizontalSizeClass == .regular)   // Q379
        // The page on screen owns the top bar's undo / redo / Done and the ⋯ menu's Find.
        if !a11yHidden, NoteEditorChrome.shared.current !== c { NoteEditorChrome.shared.current = c }

        c.load(force: false)                    // re-render only if the text changed under us
        c.apply(mode: mode)                     // editable / painter / read-only

        // A list-search tap opened this note → flash WHERE it matched (one-
        // shot; the delay lets the page's layout + accessory insets settle).
        if let query = SearchHitBridge.take(for: memo.id) {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                c.flashSearchHit(query)
            }
        }

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
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate, UIEditMenuInteractionDelegate {
        var memo: Memo
        let onCommit: (Bool) -> Void
        weak var textView: NoteBodyTextView?
        weak var player: AudioPlayerModel?
        var polishedBinding: Binding<String>?
        var nameSpans: [NameSpan] = []
        var onTapName: (NameSpan) -> Void = { _ in }
        var onNewPersonFromSelection: (String) -> Void = { _ in }
        var onTapImage: (Int) -> Void = { _ in }
        var onTapAttachment: (NoteAttachmentEntry) -> Void = { _ in }
        var onTapMemoLink: (UUID) -> Void = { _ in }
        var onRequestPhoto: () -> Void = {}
        var onRequestMemoLink: () -> Void = {}
        var linkTitle: (UUID) -> String? = { _ in nil }
        var tapToSeek = true
        /// iPad reading-measure hint (nil = phone/compact → screen width).
        var readingWidthCap: CGFloat?
        private var accessory: NoteAccessoryBar?
        /// Caret at the moment 📷 was tapped — the picker's insert target.
        private var pendingPhotoLocation: Int?
        /// The "[[" the user just typed — replaced by the picked link chip.
        private var pendingLinkTrigger: NSRange?

        /// The transcript string our attributed text currently reflects.
        private var loaded: String?
        /// Uncommitted edits exist in the view (debounce window).
        private var draftDirty = false
        /// Where a dirty draft belongs — pinned at the FIRST unsaved edit of a burst.
        /// `polishedBinding` can arrive (the enhancement fetch lands) or drop (view-identity
        /// churn resets the page's @State) MID-EDIT; the commit must go to the body the
        /// user was actually editing, never the one the binding points at by commit time.
        /// (P0 2026-07-10: a raw-born draft flushed into an arriving polish binding and
        /// replaced the user's whole edited note with the raw transcript.)
        private enum DraftTarget { case polished(Binding<String>), raw }
        private var draftTarget: DraftTarget?

        /// Mark unsaved edits, pinning their commit target on the burst's first edit.
        private func markDraftDirty() {
            if draftTarget == nil {
                draftTarget = polishedBinding.map { .polished($0) } ?? .raw
            }
            draftDirty = true
        }
        private var commitTask: Task<Void, Never>?
        private var resignObserver: NSObjectProtocol?
        private var sizeObserver: NSObjectProtocol?

        /// Name spans mapped to DISPLAYED offsets for hit-testing.
        private var displaySpans: [(range: NSRange, span: NameSpan)] = []
        /// Last selection logged by the scroll probe (rate-limits the DevLog).
        private var lastScrollSel: NSRange?

        // Karaoke painting state.
        private var clockSub: AnyCancellable?
        private var wordRanges: [NSRange] = []
        /// The shared "which word is playing" rule for the body on screen (`KaraokeTrack`) —
        /// built lazily on the first tick and dropped when the words change, never on the
        /// 20 Hz clock and never while typing.
        private var track: KaraokeTrack?
        private var timings: [WordTiming] = []
        private var lastActive: Int?           // LOCAL word index (nil = nothing painted)
        private var painting = false
        private var currentMode: NoteBody.Mode = .editing

        /// Custom attribute tagging an attachment with its 1-based image-marker
        /// index, so the transcript string round-trips from the attributed text.
        static let markerKey = NSAttributedString.Key("skriftImgMarker")
        /// D199: a video / file block's glyph; value = its marker literal (`[[vid_001]]`).
        static let attachmentKey = NSAttributedString.Key("skriftAttachmentMarker")
        /// Custom attribute tagging a checkbox attachment with its checked state
        /// — reconstructs to Obsidian task syntax ("- [ ]" / "- [x]").
        static let taskKey = NSAttributedString.Key("skriftTask")
        /// Custom attribute tagging a memo-link chip: value = "UUID|Title" —
        /// reconstructs to the raw `[[memo:UUID|Title]]` syntax.
        static let memoLinkKey = NSAttributedString.Key("skriftMemoLink")
        /// Custom attribute tagging a DISPLAY-ONLY newline (the block breaks
        /// around an inline photo) — `reconstruct` skips it, so the raw text
        /// keeps the marker mid-sentence exactly as spoken.
        static let displayOnlyKey = NSAttributedString.Key("skriftDisplayOnly")

        init(memo: Memo, onCommit: @escaping (Bool) -> Void) {
            self.memo = memo
            self.onCommit = onCommit
        }

        /// The note column's content width, minus margins. The phone is
        /// portrait-locked → the screen width; the iPad at regular size class
        /// passes `readingWidthCap` (the 640 reading measure) so inline images
        /// size to the column, not the full screen.
        private var contentWidth: CGFloat {
            max(80, (readingWidthCap ?? UIScreen.main.bounds.width) - 2 * Theme.Space.margin)
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
            // Cheap no-op checks FIRST — this runs on every updateUIView, and the
            // snap pass below used to be computed even when t == loaded.
            if !force {
                if t == loaded { return }
                if tv.isFirstResponder || draftDirty { return }        // don't yank text mid-edit
            }
            // Body v2 stores every picture as its own paragraph (C10), so the display IS
            // the stored text. A body stored before v2 still goes through the Q13
            // read-only fallback (`BodyV2Legacy`, which Q14 kept).
            let display = BodyV2Legacy.shown(protectedQuote?.ramble ?? t).text
            if !force, display == reconstruct(tv.attributedText) { loaded = t; return }
            // Carry the (clamped) selection across the rebuild so the caret —
            // and with it the visible spot — stays put.
            DevLog.log("noteBody: load rebuild force=\(force) len=\(display.count)")
            let selection = tv.selectedRange
            stopInlineVideo()
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

        /// LOCAL active word (index into `wordRanges`) at playback time `t` — the shared
        /// `KaraokeTrack` answers, the same one the Mac asks.
        private func activeLocal(at t: TimeInterval) -> Int? {
            guard !wordRanges.isEmpty else { return nil }
            return currentTrack()?.activeIndex(at: t)
        }

        /// The track for the words on screen: exact when the shown words are the timed
        /// words, aligned when the body was copy-edited, proportional when neither holds.
        /// A capture's ramble starts after the quote's spoken words, so its timings are
        /// the sidecar minus the quote's.
        private func currentTrack() -> KaraokeTrack? {
            if let track { return track }
            guard let tv = textView, !wordRanges.isEmpty else { return nil }
            let text = tv.textStorage.string as NSString
            let displayed = wordRanges.map { text.substring(with: $0) }
            // D183: the quote may have been edited, so its shown count is no longer the sidecar's.
            let sidecar = QuoteKaraokeMap.rambleTimingsStart(
                quoteWordCount: sidecarOffset, rambleWordCount: displayed.count, timingCount: timings.count)
            let spoken = sidecar > 0 ? Array(timings[sidecar...]) : timings
            let built = KaraokeTrack(displayedWords: displayed, timings: spoken,
                                     duration: player?.duration ?? 0)
            track = built
            return built
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
            track = nil   // the words changed — the track is rebuilt on the next tick
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
            applyMarkdownStyling()          // headings + B I U S, marks dim (C24/C116)
            var built: [(NSRange, NameSpan)] = []
            // Name spans carry stored offsets; the ONE remap is marker → one glyph (C17).
            // (`shown.map` is the identity for a v2 body; only a pre-v2 body goes through
            // the Q13 fallback's snap map, which Q14 kept.)
            let shown = BodyV2Legacy.shown(protectedQuote?.ramble ?? bodyText)
            // ONE pieces() pass for all spans (the per-span displayRange re-scanned
            // the whole document each call — S+1 full regex passes for S names).
            let storedRanges = nameSpans.map { shown.map($0.range) }
            let displayRanges: [NSRange?] = shown.text.isEmpty
                ? storedRanges
                : BodyTransform.displayRanges(forRaw: storedRanges, in: shown.text)
            for (span, dr) in zip(nameSpans, displayRanges) {
                guard let dr, dr.location + dr.length <= storage.length else { continue }
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
            // The same shared track the highlight reads, so a tap seeks to the word that
            // lights up — on a polished body too (it used to seek by proportion).
            guard let t = currentTrack()?.seekTime(forWord: local) else { return }
            player.seek(to: t)
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
            // Q359 (mock Q350 pick 1): Aa · checklist · photo · note link. Undo / redo /
            // Done sit in the top bar (`NoteEditorChrome`), Find in the ⋯ menu.
            let bar = NoteAccessoryBar(layout: .editor)
            bar.onFormat = { [weak self] in self?.toggleFormatPanel() }
            bar.onPhoto = { [weak self] in
                guard let self, let tv = self.textView else { return }
                self.pendingPhotoLocation = tv.selectedRange.location
                self.onRequestPhoto()
            }
            bar.onChecklist = { [weak self] in self?.toggleChecklistAtCaret() }
            bar.onMemoLink = { [weak self] in
                // Same picker the typed "[[" opens; no trigger to replace —
                // the chip lands at the caret.
                self?.pendingLinkTrigger = nil
                self?.onRequestMemoLink()
            }
            tv.inputAccessoryView = bar
            accessory = bar
        }

        private func refreshAccessory() {
            let canUndo = textView?.undoManager?.canUndo ?? false
            let canRedo = textView?.undoManager?.canRedo ?? false
            accessory?.refresh(canUndo: canUndo, canRedo: canRedo, inChecklist: caretInTaskLine())
            let chrome = NoteEditorChrome.shared
            if chrome.current === self {
                if chrome.canUndo != canUndo { chrome.canUndo = canUndo }
                if chrome.canRedo != canRedo { chrome.canRedo = canRedo }
            }
            refreshFormatState()
        }

        // MARK: top-bar verbs (NoteEditorChrome)

        func undo() { textView?.undoManager?.undo(); refreshAccessory() }
        func redo() { textView?.undoManager?.redo(); refreshAccessory() }
        /// Done = save now (C234) and put the keyboard away; the commit marks the text as the
        /// user's edit (`transcriptUserEdited`), so the Mac trusts it.
        func finishEditing() {
            commitDraft()
            hideFormatPanel()
            textView?.resignFirstResponder()
        }
        func presentFind() {
            textView?.findInteraction?.presentFindNavigator(showingReplace: false)
        }

        // MARK: formatting (D115, mock Q350): B I U S + the Aa panel

        let formatState = EditorFormatState()

        func toggleFormatPanel() {
            guard let tv = textView else { return }
            if tv.inputView != nil { hideFormatPanel(); return }
            let panel = NoteFormatPanel(
                state: formatState,
                onStyle: { [weak self] in self?.applyLineStyle($0) },
                onMark: { [weak self] in self?.applyInline($0) },
                onClose: { [weak self] in self?.hideFormatPanel() })
            let host = UIHostingController(rootView: panel)
            host.view.backgroundColor = .clear
            let input = UIInputView(frame: CGRect(x: 0, y: 0, width: tv.bounds.width, height: 236),
                                    inputViewStyle: .keyboard)
            input.allowsSelfSizing = false
            host.view.translatesAutoresizingMaskIntoConstraints = false
            input.addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: input.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: input.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: input.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: input.bottomAnchor),
            ])
            refreshFormatState()
            tv.inputView = input
            tv.reloadInputViews()
            accessory?.setFormatOpen(true)
        }

        func hideFormatPanel() {
            guard let tv = textView, tv.inputView != nil else { return }
            tv.inputView = nil
            tv.reloadInputViews()
            accessory?.setFormatOpen(false)
        }

        // MARK: iPad top bar (Q379, mock Q378): the workbench toolbar runs the keyboard bar's verbs

        /// At regular width the tools sit in the note's top bar, so the keyboard bar stays away.
        func setKeyboardBarHidden(_ hidden: Bool) {
            guard let tv = textView else { return }
            let want: UIView? = hidden ? nil : accessory
            guard tv.inputAccessoryView !== want else { return }
            tv.inputAccessoryView = want
            if tv.isFirstResponder { tv.reloadInputViews() }
        }

        /// The toolbar's note link: the same picker the typed "[[" opens; the chip lands at the caret.
        func requestMemoLinkAtCaret() {
            pendingLinkTrigger = nil
            onRequestMemoLink()
        }

        /// Aa ▸ Monostyled (D197): inline code on a one-line selection, else a fenced block —
        /// the shared rule, applied through the text input system so it lands on the undo stack.
        func applyMonostyled() {
            guard let tv = textView, currentMode == .editing else { return }
            let r = BodyFormat.monostyled(in: tv.textStorage.string, selection: tv.selectedRange)
            tv.undoManager?.beginUndoGrouping()
            for e in r.edits.reversed() {
                guard let start = tv.position(from: tv.beginningOfDocument, offset: e.range.location),
                      let end = tv.position(from: start, offset: e.range.length),
                      let range = tv.textRange(from: start, to: end) else { continue }
                tv.replace(range, withText: e.replacement)
            }
            tv.undoManager?.endUndoGrouping()
            let len = tv.textStorage.length
            let loc = min(r.selection.location, len)
            tv.selectedRange = NSRange(location: loc, length: min(r.selection.length, len - loc))
            applyMarkdownStyling(around: tv.selectedRange)
            refreshAccessory()
        }

        /// The caret line's raw Markdown (tasks as `- [ ]`), its storage range (no newline),
        /// and the caret's offset into that raw line.
        private func caretLine() -> (range: NSRange, raw: String, caretRaw: Int, prevRaw: String?)? {
            guard let tv = textView else { return nil }
            let storage = tv.textStorage
            let ns = storage.string as NSString
            let caret = min(tv.selectedRange.location, ns.length)
            var line = ns.lineRange(for: NSRange(location: caret, length: 0))
            if line.length > 0, ns.character(at: NSMaxRange(line) - 1) == 10 { line.length -= 1 }
            let raw = reconstruct(storage.attributedSubstring(from: line))
            let caretRaw = (reconstruct(storage.attributedSubstring(
                from: NSRange(location: line.location, length: caret - line.location))) as NSString).length
            var prevRaw: String?
            if line.location > 0 {
                var prev = ns.lineRange(for: NSRange(location: line.location - 1, length: 0))
                if prev.length > 0, ns.character(at: NSMaxRange(prev) - 1) == 10 { prev.length -= 1 }
                prevRaw = reconstruct(storage.attributedSubstring(from: prev))
            }
            return (line, raw, caretRaw, prevRaw)
        }

        /// Aa's Title / Heading / Body / lists on the caret's line, through the shared rule.
        /// A photo's paragraph is left alone (C10: a picture is its own paragraph).
        func applyLineStyle(_ style: BodyFormat.LineStyle) {
            guard let tv = textView, currentMode == .editing, let line = caretLine() else { return }
            if tv.textStorage.length > 0, line.range.length > 0 {
                var hasPhoto = false
                tv.textStorage.enumerateAttribute(Self.markerKey, in: line.range) { v, _, _ in
                    if v != nil { hasPhoto = true }
                }
                if hasPhoto { return }
            }
            let lead = line.prevRaw.map { $0 + "\n" } ?? ""
            let offset = (lead as NSString).length
            let r = BodyFormat.setStyle(style, in: lead + line.raw,
                                        selection: NSRange(location: offset + line.caretRaw, length: 0))
            let newRaw = (r.text as NSString).substring(from: offset)
            let caretRaw = max(0, r.selection.location - offset)
            let piece = attributed(from: newRaw)
            let caretDisplay = attributed(from: (newRaw as NSString).substring(to: min(caretRaw, (newRaw as NSString).length))).length
            tv.textStorage.replaceCharacters(in: line.range, with: piece)
            tv.selectedRange = NSRange(location: line.range.location + caretDisplay, length: 0)
            Haptics.tap(.light)
            textViewDidChange(tv)
            applyTierStyling()
        }

        /// B I U S on the selection: the shared toggle, applied through the text input system so
        /// it lands on the undo stack.
        func applyInline(_ mark: BodyFormat.InlineMark) {
            guard let tv = textView, currentMode == .editing else { return }
            let r = BodyFormat.toggle(mark, in: tv.textStorage.string, selection: tv.selectedRange)
            tv.undoManager?.beginUndoGrouping()
            for e in r.edits.reversed() {
                guard let start = tv.position(from: tv.beginningOfDocument, offset: e.range.location),
                      let end = tv.position(from: start, offset: e.range.length),
                      let range = tv.textRange(from: start, to: end) else { continue }
                tv.replace(range, withText: e.replacement)
            }
            tv.undoManager?.endUndoGrouping()
            let len = tv.textStorage.length
            let loc = min(r.selection.location, len)
            tv.selectedRange = NSRange(location: loc, length: min(r.selection.length, len - loc))
            applyMarkdownStyling(around: tv.selectedRange)
            refreshAccessory()
        }

        private func refreshFormatState() {
            guard let tv = textView else { return }
            let text = tv.textStorage.string
            let sel = tv.selectedRange
            let style = caretLine().map { BodyFormat.parse(line: $0.raw).style } ?? .body
            var marks: Set<BodyFormat.InlineMark> = []
            if NSMaxRange(sel) <= (text as NSString).length {
                for m in BodyFormat.InlineMark.allCases where BodyFormat.isActive(m, in: text, selection: sel) {
                    marks.insert(m)
                }
            }
            if formatState.lineStyle != style { formatState.lineStyle = style }
            if formatState.marks != marks { formatState.marks = marks }
            if formatState.hasSelection != (sel.length > 0) { formatState.hasSelection = sel.length > 0 }
        }

        // MARK: dim-visible marks (C24 / C116)

        /// Tags the characters the markdown pass dimmed or decorated, so the next pass can undo it.
        static let mdKey = NSAttributedString.Key("skriftMdStyled")

        static func titleFont() -> UIFont {
            UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 22, weight: .bold))
        }
        static func headingFont() -> UIFont {
            UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 18.5, weight: .bold))
        }

        /// Restyle the paragraphs touching `range` (the whole text when nil): headings get their
        /// size, `**` `*` `<u>` `~~` pairs style their words, and every mark stays visible but dim.
        /// Characters are never changed (the stored text is the Markdown the export writes).
        func applyMarkdownStyling(around range: NSRange? = nil) {
            guard let tv = textView, tv.markedTextRange == nil else { return }
            let storage = tv.textStorage
            let ns = storage.string as NSString
            guard ns.length > 0 else { return }
            let target: NSRange
            if let range {
                let loc = min(range.location, ns.length)
                target = ns.paragraphRange(for: NSRange(location: loc, length: min(range.length, ns.length - loc)))
            } else {
                target = NSRange(location: 0, length: ns.length)
            }
            guard target.length > 0 else { return }
            let base = Coordinator.bodyFont()
            let text = UIColor(Color.skText)
            let markColor = UIColor(Color.skText).withAlphaComponent(0.25)
            storage.beginEditing()
            storage.enumerateAttribute(Self.mdKey, in: target) { v, r, _ in
                guard v != nil else { return }
                storage.removeAttribute(Self.mdKey, range: r)
                storage.removeAttribute(.strikethroughStyle, range: r)
                storage.removeAttribute(.underlineStyle, range: r)
                storage.removeAttribute(.backgroundColor, range: r)
                if !painting { storage.addAttribute(.foregroundColor, value: text, range: r) }
            }
            storage.enumerateAttribute(.attachment, in: target) { a, r, _ in
                guard a == nil else { return }
                storage.addAttribute(.font, value: base, range: r)
            }
            let sub = ns.substring(with: target)
            let off = target.location
            func shift(_ r: NSRange) -> NSRange { NSRange(location: r.location + off, length: r.length) }
            func dim(_ r: NSRange) {
                storage.addAttributes([.foregroundColor: markColor, .font: base, Self.mdKey: true], range: shift(r))
            }
            // Q380: WHICH ranges get styled is the shared `MarkdownLook` (the Mac reads the same
            // spans); only the fonts and colours below are the phone's.
            let spans = MarkdownLook.spans(in: sub)
            for span in spans where span.role != .mark {
                let c = shift(span.range)
                switch span.role {
                case .mark:
                    break
                case .heading(let level):
                    let f = level == 1 ? Coordinator.titleFont()
                        : level == 2 ? Coordinator.headingFont()
                        : UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 16.5, weight: .semibold))
                    storage.addAttribute(.font, value: f, range: c)
                case .fenceContent:
                    storage.addAttributes([.font: UIFont.monospacedSystemFont(ofSize: base.pointSize * 0.92, weight: .regular),
                                           Self.mdKey: true], range: c)
                case .quoteText:
                    storage.addAttributes([.foregroundColor: UIColor(Color.skTextDim), Self.mdKey: true], range: c)
                case .inline(let mark) where mark == .bold || mark == .italic:
                    let trait: UIFontDescriptor.SymbolicTraits = mark == .bold ? .traitBold : .traitItalic
                    storage.enumerateAttribute(.font, in: c) { f, r, _ in
                        let font = (f as? UIFont) ?? base
                        var traits = font.fontDescriptor.symbolicTraits
                        traits.insert(trait)
                        if let d = font.fontDescriptor.withSymbolicTraits(traits) {
                            storage.addAttribute(.font, value: UIFont(descriptor: d, size: font.pointSize), range: r)
                        }
                    }
                case .inline(.underline):
                    storage.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue, Self.mdKey: true], range: c)
                case .inline(.strike):
                    storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, Self.mdKey: true], range: c)
                case .inline(.highlight):
                    // Written on the Mac (Q360); the phone shows it, its Aa set stays D115's.
                    storage.addAttributes([.backgroundColor: UIColor(Color.skAmber).withAlphaComponent(0.22),
                                           Self.mdKey: true], range: c)
                case .inline:   // .code (bold / italic handled above)
                    storage.addAttributes([.font: UIFont.monospacedSystemFont(ofSize: base.pointSize * 0.92, weight: .regular),
                                           Self.mdKey: true], range: c)
                }
            }
            for span in spans where span.role == .mark { dim(span.range) }
            storage.endEditing()
        }

        /// Whether the caret's line starts with a checkbox glyph.
        func caretInTaskLine() -> Bool {
            guard let tv = textView, tv.textStorage.length > 0 else { return false }
            let ns = tv.textStorage.string as NSString
            let caret = min(tv.selectedRange.location, ns.length)
            let line = ns.lineRange(for: NSRange(location: caret, length: 0))
            guard line.length > 0 else { return false }
            return tv.textStorage.attribute(Self.taskKey, at: line.location,
                                            effectiveRange: nil) is Bool
        }

        /// Accessory ☑ (bar v2, signed off): make the caret's line a checklist
        /// item, or dissolve its box when it already is one. The Notes toggle.
        func toggleChecklistAtCaret() {
            guard let tv = textView, currentMode == .editing else { return }
            let storage = tv.textStorage
            let ns = storage.string as NSString
            let caret = min(tv.selectedRange.location, ns.length)
            let line = ns.lineRange(for: NSRange(location: caret, length: 0))

            if line.length > 0,
               storage.attribute(Self.taskKey, at: line.location, effectiveRange: nil) is Bool {
                // Un-task: drop the box (and its padding space when present).
                var drop = 1
                if line.location + 1 < ns.length, ns.character(at: line.location + 1) == 32 { drop = 2 }
                storage.deleteCharacters(in: NSRange(location: line.location, length: drop))
                tv.selectedRange = NSRange(location: max(line.location, caret - drop), length: 0)
            } else {
                let piece = NSMutableAttributedString(attachment: Self.taskAttachment(checked: false))
                piece.addAttribute(Self.taskKey, value: false,
                                   range: NSRange(location: 0, length: piece.length))
                piece.addAttributes(baseAttributes(), range: NSRange(location: 0, length: piece.length))
                piece.append(NSAttributedString(string: " ", attributes: baseAttributes()))
                storage.insert(piece, at: line.location)
                tv.selectedRange = NSRange(location: caret + piece.length, length: 0)
            }
            Haptics.tap(.light)
            textViewDidChange(tv)
            applyTierStyling()          // display offsets shifted under the spans
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
            // The commit may have moved the picture to its sentence end (C10) — show
            // what was stored.
            if reconstruct(tv.attributedText) != (protectedQuote?.ramble ?? bodyText) { load(force: true) }
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
            NoteEditorChrome.shared.current = self
            NoteEditorChrome.shared.isEditing = true
            refreshAccessory()
            // UIKit's delegate order on a tap-to-focus varies: the caret can be
            // placed BEFORE didBeginEditing (no later selection callback comes),
            // so check the landing caret here too.
            resolveNameAtCaret(tv)
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            // Typing next to an attachment glyph or a display-only block break
            // inherits its custom attributes — a marker key on typed text would
            // re-emit syntax, a display-only tag would DROP a real Return. Strip
            // them from the typing attributes at every caret move.
            sanitizeTypingAttributes(tv)
            // Round-1 P1#1 evidence: a selection that CHANGES while the view is
            // not first responder (keyboard interactively dismissed, handles
            // still up) means something is rewriting it under the scroll —
            // exactly the "handles follow the viewport" report. Rare state, so
            // this can't flood the ring buffer.
            if !tv.isFirstResponder, currentMode == .editing, tv.selectedRange.length > 0 {
                DevLog.log("noteBody: sel-noFR \(NSStringFromRange(tv.selectedRange))")
            }
            // Round-3 probe (the round-2 one missed his repro — FR stays true):
            // does the RANGE change while the view scrolls? Lines here = someone
            // rewrites the selection mid-scroll; silence while handles visibly
            // drift = the range is constant and only iOS 26's handle OVERLAY is
            // re-anchoring (a rendering-layer fight, not a data one). Logged
            // only on change, so it can't flood.
            if tv.selectedRange.length > 0, tv.isDragging || tv.isDecelerating || tv.isTracking,
               tv.selectedRange != lastScrollSel {
                lastScrollSel = tv.selectedRange
                DevLog.log("noteBody: sel-during-scroll \(NSStringFromRange(tv.selectedRange)) FR=\(tv.isFirstResponder)")
            }
            refreshAccessory()          // the ☑ lights up when the caret sits in a checklist
            guard tv.isFirstResponder,
                  let began = editingBeganAt, Date().timeIntervalSince(began) < 0.35 else { return }
            resolveNameAtCaret(tv)
        }

        private static let customKeys: [NSAttributedString.Key] =
            [markerKey, taskKey, memoLinkKey, displayOnlyKey, mdKey]

        private func sanitizeTypingAttributes(_ tv: UITextView) {
            guard Self.customKeys.contains(where: { tv.typingAttributes[$0] != nil }) else { return }
            var attrs = tv.typingAttributes
            for key in Self.customKeys { attrs.removeValue(forKey: key) }
            tv.typingAttributes = attrs
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
                case .openAttachment(let literal):
                    editingBeganAt = nil
                    tv.resignFirstResponder()
                    openAttachmentBlock(literal)
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

        // MARK: "New person…" in the text menu (D184)

        /// The trimmed selection to prefill the person editor with, or nil when the menu item
        /// is hidden (blank run, a name the note already shows, a known person, an attachment).
        func newPersonOffer(for range: NSRange, in tv: UITextView) -> String? {
            let ns = tv.textStorage.string as NSString
            guard range.length > 0, NSMaxRange(range) <= ns.length else { return nil }
            return NewPersonFromName.selectionOffer(
                text: ns.substring(with: range), selection: range,
                knownRanges: displaySpans.map(\.range),
                people: NamesStore.shared.livePeople())
        }

        /// The selection bar (D196 on mock Q350): the system's Cut · Copy · Paste in their
        /// normal place, then B I U S, then "New person…" at the right end when the
        /// selection qualifies (D184 — used less often).
        func textView(_ tv: UITextView, editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            var children = suggestedActions
            if currentMode == .editing, range.length > 0 {
                let text = tv.textStorage.string
                let formats: [(BodyFormat.InlineMark, String, String)] = [
                    (.bold, "bold", "Bold"), (.italic, "italic", "Italic"),
                    (.underline, "underline", "Underline"), (.strike, "strikethrough", "Strikethrough"),
                ]
                let actions = formats.map { mark, symbol, label in
                    let a = UIAction(title: "", image: UIImage(systemName: symbol),
                                     state: BodyFormat.isActive(mark, in: text, selection: range) ? .on : .off) { [weak self] _ in
                        self?.applyInline(mark)
                    }
                    a.discoverabilityTitle = label
                    return a
                }
                // First, so B I U S sit on the bar's first page (mock Q350). Appended after
                // the system's Cut/Copy/Replace/AutoFill they landed behind the › overflow.
                children.insert(UIMenu(options: .displayInline, children: actions), at: 0)
            }
            // D202: Apple's per-block small/large switch, on a selected video / file block.
            if let literal = attachmentLiteral(in: range, of: tv), let e = attachmentEntry(literal: literal) {
                let isLarge = NoteAttachment.size(of: e.filename, large: memo.metadata?.largeAttachments) == .large
                children.append(UIAction(title: isLarge ? NoteAttachment.viewSmallTitle : NoteAttachment.viewLargeTitle,
                                         image: UIImage(systemName: isLarge ? "rectangle.compress.vertical" : "rectangle.expand.vertical")) { [weak self] _ in
                    guard let self else { return }
                    NoteAttachmentStore.setSize(isLarge ? .small : .large, filename: e.filename, memo: self.memo)
                    tv.resignFirstResponder()
                    self.load(force: true)
                })
            }
            if let name = newPersonOffer(for: range, in: tv) {
                let item = UIAction(title: NameActionLabel.newPerson,
                                    image: UIImage(systemName: "person.badge.plus")) { [weak self] _ in
                    tv.resignFirstResponder()
                    self?.onNewPersonFromSelection(name)
                }
                children.append(item)
            }
            return UIMenu(children: children)
        }

        // MARK: D112: move a photo by long press

        /// A held block: its marker literal (photo, video or file), the lifted snapshot, the drop
        /// line, the grab offset and where the finger went down (no travel = the hold menu).
        private var photoDrag: (literal: String, snapshot: UIView, line: UIView, grab: CGFloat, start: CGPoint)?
        private var blockMenuLiteral: String?
        private lazy var blockMenuInteraction = UIEditMenuInteraction(delegate: self)

        func installPhotoDrag(on tv: NoteBodyTextView) {
            let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePhotoPress(_:)))
            press.minimumPressDuration = 0.42
            press.delegate = self
            tv.addGestureRecognizer(press)
        }

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard g is UILongPressGestureRecognizer, let tv = textView else { return true }
            guard currentMode != .playing else { return false }
            switch attachmentAction(at: g.location(in: tv)) {
            case .openImage?, .openAttachment?: return true
            default: return false
            }
        }

        /// The block literal + its glyph range under a press (photo or video / file block).
        private func heldBlock(at p: CGPoint) -> (literal: String, range: NSRange)? {
            switch attachmentAction(at: p) {
            case .openImage(let marker)?:
                return attachmentRange(forMarker: marker).map { (BodyV2Marker.literal(marker), $0) }
            case .openAttachment(let literal)?:
                return attachmentRange(forLiteral: literal).map { (literal, $0) }
            default:
                return nil
            }
        }

        func attachmentRange(forLiteral literal: String) -> NSRange? {
            guard let tv = textView else { return nil }
            var found: NSRange?
            tv.textStorage.enumerateAttribute(Self.attachmentKey, in: NSRange(location: 0, length: tv.textStorage.length)) { v, r, stop in
                if v as? String == literal { found = r; stop.pointee = true }
            }
            return found
        }

        /// The filename a block's size is stored under (photo manifest / attachment entry).
        private func blockFilename(_ literal: String) -> String? {
            if let e = attachmentEntry(literal: literal) { return e.filename }
            guard let n = BodyV2Marker.numbers(in: literal).first else { return nil }
            return memo.imageURL(markerIndex: n)?.lastPathComponent
        }

        private func blockFileURL(_ literal: String) -> URL? {
            if let e = attachmentEntry(literal: literal) {
                return NoteAttachmentStore.fileExists(e) ? NoteAttachmentStore.fileURL(e) : nil
            }
            guard let n = BodyV2Marker.numbers(in: literal).first, let url = memo.imageURL(markerIndex: n),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        }

        /// D202 (mock pick 6): a hold released without moving opens the block's menu (the shared
        /// `NoteAttachment.blockActions`: View as Small/Large, Move Up/Down, Share, Delete).
        private func presentBlockMenu(_ literal: String, at point: CGPoint) {
            guard let tv = textView else { return }
            if blockMenuInteraction.view == nil { tv.addInteraction(blockMenuInteraction) }
            blockMenuLiteral = literal
            blockMenuInteraction.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: point))
        }

        func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
                                 suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let literal = blockMenuLiteral, let filename = blockFilename(literal) else { return nil }
            let raw = reconstruct(textView?.attributedText)
            let spot = NoteAttachment.paragraphIndex(of: literal, in: raw) ?? (0, 1)
            let size = NoteAttachment.size(of: filename, large: memo.metadata?.largeAttachments)
            var actions = NoteAttachment.blockActions(size: size, paragraph: spot.index, count: spot.count,
                                                      shareable: blockFileURL(literal) != nil)
            if currentMode != .editing { actions.removeAll { $0 != .share && $0 != .setSize(size == .large ? .small : .large) } }
            return UIMenu(children: actions.map { a in
                UIAction(title: a.title, image: UIImage(systemName: a.symbol),
                         attributes: a == .delete ? .destructive : []) { [weak self] _ in
                    self?.performBlockAction(a, literal: literal, filename: filename, at: configuration.sourcePoint)
                }
            })
        }

        private func performBlockAction(_ a: NoteAttachment.BlockAction, literal: String, filename: String, at point: CGPoint) {
            guard let tv = textView else { return }
            switch a {
            case .setSize(let s):
                NoteAttachmentStore.setSize(s, filename: filename, memo: memo)
                load(force: true)
            case .moveUp, .moveDown, .delete:
                guard currentMode == .editing else { return }
                let raw = reconstruct(tv.attributedText)
                let changed = a == .delete ? NoteAttachment.deleting(literal, in: raw)
                    : NoteAttachment.moving(literal, by: a == .moveUp ? -1 : 1, in: raw)
                guard changed != raw else { return }
                tv.attributedText = attributed(from: changed)
                markDraftDirty()
                commitDraft()
                load(force: true)
                applyTierStyling()
                Haptics.tap(.light)
            case .share:
                guard let url = blockFileURL(literal), let host = Self.hostController(of: tv) else { return }
                let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                share.popoverPresentationController?.sourceView = tv
                share.popoverPresentationController?.sourceRect = CGRect(origin: point, size: .zero)
                host.present(share, animated: true)
            }
        }

        static func hostController(of view: UIView) -> UIViewController? {
            var r: UIResponder? = view
            while let next = r?.next { if let vc = next as? UIViewController { return vc }; r = next }
            return nil
        }

        // MARK: D202 inline video (pick 1): plays in the note, ⤢ in AVKit's controls

        private var inlineVideo: AVPlayerViewController?

        func stopInlineVideo() {
            guard let vc = inlineVideo else { return }
            vc.player?.pause()
            vc.willMove(toParent: nil)
            vc.view.removeFromSuperview()
            vc.removeFromParent()
            inlineVideo = nil
        }

        /// A tapped block: a LARGE video plays right there over its poster; a small one, or a file,
        /// goes to the page (Quick Look).
        private func openAttachmentBlock(_ literal: String) {
            guard let tv = textView, let e = attachmentEntry(literal: literal) else { return }
            let large = NoteAttachment.size(of: e.filename, large: memo.metadata?.largeAttachments) == .large
            guard e.kind == NoteAttachment.Kind.video, large, NoteAttachmentStore.fileExists(e),
                  let range = attachmentRange(forLiteral: literal), let rect = tv.rects(forCharacterRange: range).first,
                  let host = Self.hostController(of: tv) else {
                onTapAttachment(e)
                return
            }
            stopInlineVideo()
            let vc = AVPlayerViewController()
            vc.player = AVPlayer(url: NoteAttachmentStore.fileURL(e))
            vc.videoGravity = .resizeAspect
            vc.view.layer.cornerRadius = NoteAttachment.mediaCornerRadius
            vc.view.layer.masksToBounds = true
            host.addChild(vc)
            vc.view.frame = rect
            tv.addSubview(vc.view)
            vc.didMove(toParent: host)
            inlineVideo = vc
            vc.player?.play()
        }

        /// The drop spot for a finger at `y` (text-view coordinates): the start of the paragraph
        /// under it, or the end of the text below the last line.
        private func dropLocation(atY y: CGFloat) -> Int {
            guard let tv = textView else { return 0 }
            let ns = tv.textStorage.string as NSString
            let point = CGPoint(x: tv.textContainerInset.left + 4, y: y)
            guard let idx = tv.characterIndex(at: point) else { return ns.length }
            let para = ns.paragraphRange(for: NSRange(location: min(idx, ns.length), length: 0))
            let rects = tv.rects(forCharacterRange: NSRange(location: para.location, length: max(1, min(para.length, 1))))
            if let r = rects.first, y > r.midY, para.length > 0, NSMaxRange(para) >= ns.length { return ns.length }
            return para.location
        }

        @objc func handlePhotoPress(_ g: UILongPressGestureRecognizer) {
            guard let tv = textView else { return }
            let p = g.location(in: tv)
            switch g.state {
            case .began:
                stopInlineVideo()
                guard let held = heldBlock(at: p),
                      let rect = tv.rects(forCharacterRange: held.range).first,
                      let snap = tv.resizableSnapshotView(from: rect, afterScreenUpdates: false, withCapInsets: .zero)
                else { return }
                tv.resignFirstResponder()
                snap.frame = rect
                snap.layer.cornerRadius = 14
                snap.layer.shadowColor = UIColor.black.cgColor
                snap.layer.shadowOpacity = 0.35
                snap.layer.shadowRadius = 20
                snap.layer.shadowOffset = CGSize(width: 0, height: 18)
                tv.addSubview(snap)
                let line = UIView(frame: CGRect(x: tv.textContainerInset.left, y: rect.minY,
                                                width: tv.bounds.width - tv.textContainerInset.left - tv.textContainerInset.right,
                                                height: 3))
                line.backgroundColor = UIColor(Color.skAccent)
                line.layer.cornerRadius = 1.5
                line.isHidden = true
                tv.addSubview(line)
                UIView.animate(withDuration: 0.15) { snap.transform = CGAffineTransform(scaleX: 1.04, y: 1.04) }
                Haptics.tap(.medium)
                photoDrag = (held.literal, snap, line, p.y - rect.minY, p)
            case .changed:
                guard let drag = photoDrag else { return }
                // Editing only moves; reading only gets the menu.
                guard currentMode == .editing else { return }
                drag.snapshot.frame.origin.y = p.y - drag.grab
                let loc = dropLocation(atY: p.y)
                let ns = tv.textStorage.string as NSString
                let y: CGFloat
                if loc >= ns.length, let last = tv.rects(forCharacterRange: NSRange(location: max(0, ns.length - 1), length: 1)).last {
                    y = last.maxY + 4
                } else if let r = tv.rects(forCharacterRange: NSRange(location: loc, length: 1)).first {
                    y = r.minY - 4
                } else { y = p.y }
                drag.line.frame.origin.y = y
                drag.line.isHidden = false
                tv.bringSubviewToFront(drag.snapshot)
            case .ended:
                guard let drag = photoDrag else { return }
                finishPhotoDrag(drag)
                // No travel: the hold menu (mock pick 6). Travel: the block moves (D112).
                if hypot(p.x - drag.start.x, p.y - drag.start.y) < 10 || currentMode != .editing {
                    presentBlockMenu(drag.literal, at: p)
                } else {
                    moveBlock(literal: drag.literal, toDisplayLocation: dropLocation(atY: p.y))
                }
            default:
                if let drag = photoDrag { finishPhotoDrag(drag) }
            }
        }

        private func finishPhotoDrag(_ drag: (literal: String, snapshot: UIView, line: UIView, grab: CGFloat, start: CGPoint)) {
            drag.snapshot.removeFromSuperview()
            drag.line.removeFromSuperview()
            photoDrag = nil
        }

        /// Drop picture `marker` before the paragraph starting at `location` (display offsets),
        /// through the shared `BodyFormat.movePhoto`, and save now (a move is a decisive act).
        func movePhoto(marker: Int, toDisplayLocation location: Int) {
            moveBlock(literal: BodyV2Marker.literal(marker), toDisplayLocation: location)
        }

        /// Any block (photo, video, file) dropped before the paragraph at `location`.
        func moveBlock(literal: String, toDisplayLocation location: Int) {
            let marker = BodyV2Marker.numbers(in: literal).first
            guard let tv = textView, currentMode == .editing,
                  let own = marker.flatMap({ attachmentRange(forMarker: $0) }) ?? attachmentRange(forLiteral: literal) else { return }
            let ns = tv.textStorage.string as NSString
            let before = ns.substring(to: min(location, ns.length))
            var index = before.components(separatedBy: "\n\n").count - 1
            if location >= ns.length { index = Int.max / 2 }
            if own.location < location, index != Int.max / 2 { index -= 1 }   // its own paragraph leaves the count
            let raw = reconstruct(tv.attributedText)
            let moved = BodyFormat.moveBlock(literal: literal, in: raw, toParagraph: max(0, index))
            guard moved != raw else { return }
            tv.attributedText = attributed(from: moved)
            markDraftDirty()
            commitDraft()
            load(force: true)
            applyTierStyling()
            Haptics.tap(.light)
        }

        /// What a focus-gaining tap on an attachment should do.
        enum AttachmentAction: Equatable {
            case toggleTask(at: Int)
            case openImage(marker: Int)
            case openMemo(UUID)
            case openAttachment(String)
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
                if let literal = storage.attribute(Self.attachmentKey, at: probe, effectiveRange: nil) as? String,
                   hits(slopX: 0, slopY: 0) {
                    return .openAttachment(literal)
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

            // The rule (empty item ends the list; else split + fresh box) is the SHARED
            // `BodyTransform.taskReturn`, the same one the Mac's editor runs.
            let rule = BodyTransform.taskReturn(in: ns, caret: caret, boxIndex: line.location)
            let insertAt: Int
            let lead: String
            switch rule {
            case .passthrough:
                return false
            case .dissolve(let range):
                // Empty item → end the list here.
                tv.textStorage.replaceCharacters(
                    in: range, with: NSAttributedString(string: "", attributes: baseAttributes()))
                tv.selectedRange = NSRange(location: line.location, length: 0)
                textViewDidChange(tv)
                return true
            case .continued(let removeSpace, let at, let leading):
                // A space right after the caret is consumed (Notes trims the split tail),
                // then "\n" + fresh box + " ".
                if let removeSpace { tv.textStorage.deleteCharacters(in: removeSpace) }
                insertAt = at
                lead = leading
            }
            let piece = NSMutableAttributedString(string: lead, attributes: baseAttributes())
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

        // MARK: search-hit flash (list search → "show me WHERE it matched")

        /// Scroll to and briefly highlight the first match of `query`: the
        /// text range when the words are in the body, else the PHOTO whose
        /// OCR text matched (a background is invisible behind an image, so
        /// photos get an overlay ring). Cleanup = applyTierStyling, which
        /// idempotently repaints the canonical colors.
        func flashSearchHit(_ query: String) {
            guard let tv = textView, !painting else { return }
            let q = query.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else { return }
            // Q321: EVERY occurrence in highlighter yellow with dark text (readable in
            // both modes), the FIRST one centred in the visible area. The colours and
            // the centring rule are `SearchHitLook` (shared with the Mac).
            let hits = SearchHitLook.matchRanges(of: q, in: tv.textStorage.string)
            if let first = hits.first {
                let fill = Self.hexColor(SearchHitLook.fillHex)
                let ink = Self.hexColor(SearchHitLook.textHex)
                for r in hits {
                    tv.textStorage.addAttributes([.backgroundColor: fill, .foregroundColor: ink], range: r)
                }
                centerHit(first, in: tv)
                DispatchQueue.main.asyncAfter(deadline: .now() + SearchHitLook.holdSeconds) { [weak self] in
                    self?.applyTierStyling()
                }
                return
            }
            // Not in the body → the match lives inside a photo's OCR text.
            guard let manifest = memo.metadata?.imageManifest else { return }
            for (i, entry) in manifest.enumerated()
            where entry.text?.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                guard let attRange = attachmentRange(forMarker: i + 1) else { return }
                centerHit(attRange, in: tv)
                flashOverlay(on: tv, around: attRange)
                return
            }
        }

        static func hexColor(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }

        /// Scroll so the hit's rect sits at the vertical middle of the VISIBLE area
        /// (bounds minus the adjusted insets: safe area, player bar, keyboard). The
        /// text is laid out lazily, so a far-away hit's rect and the content height
        /// can both shift once it is scrolled into place — re-aim until it settles.
        func centerHit(_ range: NSRange, in tv: NoteBodyTextView, pass: Int = 0) {
            tv.layoutIfNeeded()
            let rects = tv.rects(forCharacterRange: range)
            guard let union = rects.dropFirst().reduce(rects.first, { $0?.union($1) }) else {
                tv.scrollRangeToVisible(range)
                return
            }
            let inset = tv.adjustedContentInset
            let y = SearchHitLook.centeredOffsetY(
                hitMidY: union.midY, contentHeight: tv.contentSize.height,
                viewportHeight: tv.bounds.height, topInset: inset.top, bottomInset: inset.bottom)
            let moved = abs(tv.contentOffset.y - y) > 1
            if moved { tv.setContentOffset(CGPoint(x: tv.contentOffset.x, y: y), animated: false) }
            if pass < 3 {
                DispatchQueue.main.async { [weak self, weak tv] in
                    guard let self, let tv else { return }
                    self.centerHit(range, in: tv, pass: pass + 1)
                }
            }
        }

        /// The zoom-transition anchor for the photo carrying marker `n`: the
        /// text view, the attachment's drawn rect, and its rendered thumbnail
        /// (P2#12 — the viewer lifts the photo off the page instead of the
        /// black bottom-sheet slide).
        func photoAnchor(marker n: Int) -> MarkupQuickLook.Anchor? {
            guard let tv = textView, let range = attachmentRange(forMarker: n) else { return nil }
            let rects = tv.rects(forCharacterRange: range)
            guard let union = rects.dropFirst().reduce(rects.first, { $0?.union($1) }) else { return nil }
            let image = (tv.textStorage.attribute(.attachment, at: range.location,
                                                  effectiveRange: nil) as? NSTextAttachment)?.image
            return (tv, union, image)
        }

        /// The 1-char range of the photo attachment carrying marker `n`.
        func attachmentRange(forMarker n: Int) -> NSRange? {
            guard let tv = textView else { return nil }
            var found: NSRange?
            tv.textStorage.enumerateAttribute(Self.markerKey,
                                              in: NSRange(location: 0, length: tv.textStorage.length)) {
                value, range, stop in
                if value as? Int == n { found = range; stop.pointee = true }
            }
            return found
        }

        /// A fading accent ring over the attachment's drawn rect(s).
        private func flashOverlay(on tv: NoteBodyTextView, around range: NSRange) {
            // Layout must settle before the rects are real (we may have just
            // scrolled a far-away fragment into place).
            DispatchQueue.main.async {
                let rects = tv.rects(forCharacterRange: range)
                guard let union = rects.dropFirst().reduce(rects.first, { $0?.union($1) }) else { return }
                let ring = UIView(frame: union.insetBy(dx: -5, dy: -5))
                ring.layer.cornerRadius = 16
                ring.layer.cornerCurve = .continuous
                ring.layer.borderWidth = 2.5
                ring.layer.borderColor = UIColor(Color.skAccent).cgColor
                ring.backgroundColor = UIColor(Color.skAccent).withAlphaComponent(0.12)
                ring.isUserInteractionEnabled = false
                tv.addSubview(ring)
                UIView.animate(withDuration: 0.55, delay: 0.9, options: [.curveEaseOut]) {
                    ring.alpha = 0
                } completion: { _ in
                    ring.removeFromSuperview()
                }
            }
        }

        // MARK: editing / debounced commit

        func textViewDidChange(_ tv: UITextView) {
            markDraftDirty()
            applyMarkdownStyling(around: NSRange(location: tv.selectedRange.location, length: 0))
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
            if NoteEditorChrome.shared.current === self { NoteEditorChrome.shared.isEditing = false }
            if tv.inputView != nil {             // the next edit opens on the keyboard again
                tv.inputView = nil
                accessory?.setFormatOpen(false)
            }
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
            markDraftDirty()
            commitDraft()
            applyTierStyling()          // re-derive display spans over the same offsets
        }

        /// One memo-link chip as an attributed piece (attachment + the raw
        /// payload in `memoLinkKey`, so it round-trips byte-exact).
        /// `title` is the raw snapshot (round-trips into `[[memo:UUID|title]]` via `memoLinkKey`);
        /// `display` is what the CHIP shows — pass the target's live title so a renamed note's
        /// chips stay current, while the raw payload keeps the snapshot as the export fallback.
        static func memoLinkPiece(id: UUID, title: String, display: String? = nil,
                                  base: [NSAttributedString.Key: Any]) -> NSAttributedString {
            let shown = (display?.isEmpty == false) ? display! : title
            let a = NSMutableAttributedString(attachment: memoLinkAttachment(title: shown))
            let r = NSRange(location: 0, length: a.length)
            a.addAttribute(memoLinkKey, value: "\(id.uuidString)|\(title)", range: r)   // raw keeps the snapshot
            a.addAttributes(base, range: r)
            return a
        }

        /// The chip image: "🗒 Title" in accent on a bordered soft pill (the shared
        /// `NoteLook` look, same as the Mac) — atomic (one glyph), so typing next to it
        /// can never extend the link.
        static func memoLinkAttachment(title: String) -> NSTextAttachment {
            let font = UIFont.systemFont(ofSize: bodyFont().pointSize - 1.5, weight: .medium)
            let text = NoteLook.memoLinkLabel(title: title, maxTitle: NoteLook.memoLinkMaxTitlePhone) as NSString
            let textSize = text.size(withAttributes: [.font: font])
            let padH = NoteLook.memoLinkPadH, padV: CGFloat = 3
            let size = CGSize(width: ceil(textSize.width) + padH * 2,
                              height: ceil(textSize.height) + padV * 2)
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                let accent = UIColor(Color.skNameLinked)
                let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5),
                                        cornerRadius: NoteLook.memoLinkCornerRadius)
                accent.withAlphaComponent(NoteLook.memoLinkFillAlpha).setFill(); path.fill()
                accent.withAlphaComponent(NoteLook.memoLinkStrokeAlpha).setStroke()
                path.lineWidth = 1; path.stroke()
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
            markDraftDirty()
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
            let target = draftTarget ?? (polishedBinding.map { .polished($0) } ?? .raw)
            draftTarget = nil
            let text = committedBody(reconstruct(tv.attributedText))
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // C98: only the `.raw` targets touch `memo.transcript` (the words hash) —
            // `.polished` writes the copy-edit and stamps its OWN conflict record via
            // `recordPolishedEdit` (the binding's setter), so `onCommit` must not also
            // stamp the (unchanged) raw words.
            var wordsChanged = false
            switch target {
            case .polished(let binding):
                binding.wrappedValue = text          // setter stamps provenance
                loaded = text
            case .raw where memo.captureQuote != nil:
                // The editor held ONLY the ramble — re-prepend the raw "> " block
                // verbatim so the stored quote is untouchable.
                memo.transcript = memo.captureQuote!.body(withRamble: text)
                memo.transcriptStatus = .done
                loaded = memo.transcript
                wordsChanged = true
            case .raw:
                let wasNonEmpty = !(loaded ?? "").isEmpty
                memo.transcript = trimmed.isEmpty ? nil : text
                if !trimmed.isEmpty { memo.transcriptStatus = .done }
                if trimmed.isEmpty && wasNonEmpty {
                    DevLog.log("editor cleared body → transcript=nil memo \(memo.id)")
                }
                loaded = memo.transcript ?? ""
                wordsChanged = true
            }
            memo.transcriptUserEdited = true         // Mac trusts it → no re-transcribe
            rebuildWordRanges()
            onCommit(wordsChanged)
        }

        /// C10 + C19 at the editor commit, ONE rule for every note (Q123): the body is written
        /// through body v2 whether or not it carries pictures (an edit: every marker keeps its
        /// place in the sequence, one inside a sentence moves to that sentence's end; the
        /// whitespace is normalised once). The Mac's end-of-editing commit calls the same entry,
        /// so the same keystrokes store the same string on both devices. The in-session text view
        /// is never rewritten (`load` skips a first-responder / dirty editor).
        func committedBody(_ text: String) -> String {
            let manifest = memo.metadata?.imageManifest ?? []
            let stored = BodyV2.committed(BodyV2.Input(text: text, manifest: manifest,
                                                       source: memo.bodyV2Source, userEdited: true))
            return NoteAttachment.blockShaped(stored, manifest: memo.metadata?.attachmentManifest ?? [])
        }

        // MARK: D199 videos and files

        func attachmentEntry(literal: String) -> NoteAttachmentEntry? {
            guard let m = NoteAttachment.markers(in: literal).first else { return nil }
            return NoteAttachment.entry(kind: m.kind, number: m.number, manifest: memo.metadata?.attachmentManifest ?? [])
        }

        private func attachmentLiteral(in range: NSRange, of tv: UITextView) -> String? {
            let storage = tv.textStorage
            var found: String?
            let r = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
            storage.enumerateAttribute(Self.attachmentKey, in: r) { v, _, stop in
                if let s = v as? String { found = s; stop.pointee = true }
            }
            return found
        }

        /// The block's glyph: the art for its current size, at the column width.
        private func attachmentPiece(_ entry: NoteAttachmentEntry, literal: String) -> NSAttributedString {
            let att = NSTextAttachment()
            let url = NoteAttachmentStore.fileExists(entry) ? NoteAttachmentStore.fileURL(entry) : nil
            let size = NoteAttachment.size(of: entry.filename, large: memo.metadata?.largeAttachments)
            let dark = textView?.traitCollection.userInterfaceStyle == .dark
            // iPad (a reading cap is set) caps media at 720 / the card at 520 pt (pick 8).
            let wide = readingWidthCap != nil
            let media = size == .large && url != nil && entry.kind == NoteAttachment.Kind.video
            let img = NoteAttachmentArt.image(entry, size: size,
                                              width: NoteAttachment.blockWidth(column: contentWidth, wide: wide, largeMedia: media),
                                              maxVideoHeight: NoteAttachment.videoMaxHeight(wide: wide), fileURL: url, dark: dark)
            att.image = img
            att.bounds = CGRect(x: 0, y: -4, width: img.size.width, height: img.size.height)
            let a = NSMutableAttributedString(attachment: att)
            a.addAttribute(Self.attachmentKey, value: literal, range: NSRange(location: 0, length: a.length))
            return a
        }

        /// Plain text with any resolving `[[vid_NNN]]` / `[[file_NNN]]` drawn as its block.
        private func appendText(_ s: String, to result: NSMutableAttributedString, base: [NSAttributedString.Key: Any]) {
            let manifest = memo.metadata?.attachmentManifest ?? []
            let ns = s as NSString
            var cursor = 0
            for m in NoteAttachment.markers(in: s) {
                guard let e = NoteAttachment.entry(kind: m.kind, number: m.number, manifest: manifest) else { continue }
                if m.range.location > cursor {
                    result.append(NSAttributedString(string: ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)), attributes: base))
                }
                result.append(attachmentPiece(e, literal: ns.substring(with: m.range)))
                cursor = NSMaxRange(m.range)
            }
            if cursor < ns.length { result.append(NSAttributedString(string: ns.substring(from: cursor), attributes: base)) }
        }

        /// The attach menu's video / file (D199): copied into the note, its block put at the caret
        /// the menu captured, then stored and mirrored like a photo.
        func insertAttachment(fileURL: URL, originalName: String?, uti: String?) {
            guard let tv = textView, currentMode == .editing,
                  let added = NoteAttachmentStore.add(fileURL: fileURL, originalName: originalName, uti: uti, to: memo) else { return }
            let at = min(pendingPhotoLocation ?? tv.selectedRange.location, tv.textStorage.length)
            pendingPhotoLocation = nil
            let piece = NSMutableAttributedString(string: "\n", attributes: baseAttributes())
            piece.append(attachmentPiece(added.entry, literal: NoteAttachment.literal(kind: added.entry.kind, number: added.number)))
            piece.append(NSAttributedString(string: "\n", attributes: baseAttributes()))
            tv.textStorage.insert(piece, at: at)
            tv.selectedRange = NSRange(location: at + piece.length, length: 0)
            textViewDidChange(tv)
            commitDraft()
            if reconstruct(tv.attributedText) != (protectedQuote?.ramble ?? bodyText) { load(force: true) }
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
                    appendText(s, to: result, base: base)
                case .image(let n):
                    // A picture is its own paragraph in the stored body (C10): the
                    // marker becomes one glyph, no display-only breaks (C17).
                    let a = NSMutableAttributedString(attachment: imageAttachment(markerIndex: n))
                    a.addAttribute(Self.markerKey, value: n, range: NSRange(location: 0, length: a.length))
                    result.append(a)
                case .task(let checked):
                    let a = NSMutableAttributedString(attachment: Self.taskAttachment(checked: checked))
                    a.addAttribute(Self.taskKey, value: checked, range: NSRange(location: 0, length: a.length))
                    a.addAttributes(base, range: NSRange(location: 0, length: a.length))
                    result.append(a)
                case .memoLink(let id, let title):
                    result.append(Self.memoLinkPiece(id: id, title: title, display: linkTitle(id), base: base))
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
        /// Marker/task/chip emission requires the run to BE the attachment char
        /// (U+FFFC) — typing next to a glyph inherits its custom attributes, and
        /// an inherited key on plain text must never re-emit syntax. Display-only
        /// newlines (photo block breaks) contribute nothing; typed text that
        /// inherited their tag stays text.
        func reconstruct(_ attr: NSAttributedString?) -> String {
            guard let attr else { return "" }
            let out = NSMutableString()
            let full = attr.string as NSString
            attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length)) { attrs, range, _ in
                let run = full.substring(with: range)
                if let marker = attrs[Self.markerKey] as? Int, run == "\u{FFFC}" {
                    // Match the writer's zero-padded format (`BodyV2Marker` %03d) —
                    // the old editor re-emitted "[[img_1]]" and drifted the format.
                    out.append(BodyV2Marker.literal(marker))
                } else if let literal = attrs[Self.attachmentKey] as? String, run == "\u{FFFC}" {
                    out.append(literal)
                } else if let checked = attrs[Self.taskKey] as? Bool, run == "\u{FFFC}" {
                    out.append(BodyTransform.rawTask(checked: checked))
                } else if let payload = attrs[Self.memoLinkKey] as? String, run == "\u{FFFC}" {
                    out.append("[[memo:\(payload)]]")
                } else if attrs[Self.displayOnlyKey] != nil {
                    out.append(run.filter { $0 != "\n" })          // block breaks vanish
                } else if attrs[.attachment] == nil {
                    out.append(run)
                }                                                  // untagged attachment → drop
            }
            return out as String
        }

        private func imageAttachment(markerIndex: Int) -> NSTextAttachment {
            let att = NSTextAttachment()
            let width = contentWidth
            // D202: a photo is SMALL (the shared grey card) until switched to large.
            if let url = memo.imageURL(markerIndex: markerIndex), FileManager.default.fileExists(atPath: url.path),
               NoteAttachment.size(of: url.lastPathComponent, large: memo.metadata?.largeAttachments) == .small {
                let w = NoteAttachment.blockWidth(column: width, wide: readingWidthCap != nil, largeMedia: false)
                att.image = NoteAttachmentArt.photoCard(filename: url.lastPathComponent, fileURL: url, width: w,
                                                        dark: textView?.traitCollection.userInterfaceStyle == .dark)
                att.bounds = CGRect(x: 0, y: -4, width: w, height: NoteAttachment.cardMinHeight)
                return att
            }
            if let url = memo.imageURL(markerIndex: markerIndex),
               let img = MemoImageLoader.thumbnail(at: url, maxWidth: width) {
                att.image = Self.roundedCorners(img)
                // NSTextAttachment scales to FILL `bounds` (no aspect preserve),
                // so bounds must match the image aspect. Fit width × 320-pt cap;
                // a portrait frame shrinks WIDTH to keep aspect.
                let fit = NoteLook.photoSize(image: img.size, columnWidth: width)
                att.bounds = CGRect(x: 0, y: -4, width: fit.width, height: fit.height)
            } else {
                att.image = Self.placeholder(width: width)
                att.bounds = CGRect(x: 0, y: -4, width: width, height: 150)
            }
            return att
        }

        /// Clip an inline photo to soft rounded corners — reads better in the note body.
        private static func roundedCorners(_ image: UIImage) -> UIImage {
            let size = image.size
            guard size.width > 0, size.height > 0 else { return image }
            let radius = min(size.width, size.height) * NoteLook.photoCornerFraction
            let rect = CGRect(origin: .zero, size: size)
            let r = UIGraphicsImageRendererFormat.default(); r.scale = image.scale
            return UIGraphicsImageRenderer(size: size, format: r).image { _ in
                UIBezierPath(roundedRect: rect, cornerRadius: radius).addClip()
                image.draw(in: rect)
            }
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
    func insertAttachment(fileURL: URL, originalName: String?, uti: String?) {
        coordinator?.insertAttachment(fileURL: fileURL, originalName: originalName, uti: uti)
    }
    func insertMemoLink(id: UUID, title: String) { coordinator?.insertMemoLink(id: id, title: title) }
    /// Rebuild the attributed text so attachment thumbnails re-decode (after
    /// a markup save-back rewrote a photo file). Caret carries across.
    func refreshAttachments() { coordinator?.load(force: true) }
    /// Zoom-transition anchor for the photo with marker `n` (P2#12).
    func photoAnchor(marker n: Int) -> MarkupQuickLook.Anchor? {
        coordinator?.photoAnchor(marker: n)
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
    #if DEBUG
    /// Q344 test seam: a 1-pt-tall marker at the top of the first text line
    /// (= the top text-container inset, in content coordinates), so a UI test can
    /// compare it with the header rows' frames. DEBUG only; invisible.
    private let firstLineProbe: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.isAccessibilityElement = true
        v.accessibilityIdentifier = "note-body-first-line"
        return v
    }()
    #endif

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
        // Q344: the header's OWN state (the destination row expanding, preset chips
        // appearing under a Personal→Portfolio flip) resizes it WITHOUT a new
        // rootView, so `updateUIView` never ran and the top inset stayed at the old
        // height: the body sat under the taller header. The hosted content now
        // reports its own height changes and the next layout pass re-measures.
        headerHost.rootView = AnyView(header.onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { [weak self] _ in
            self?.setNeedsAccessoryLayout()
        })
        footerHost.rootView = AnyView(footer.onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { [weak self] _ in
            self?.setNeedsAccessoryLayout()
        })
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
        // Assign ONLY on change: layoutSubviews runs every scroll frame, and
        // re-setting a hosting view's frame dirties its layer each time — iOS
        // 26's selection-handle host (_UICursorAccessoryHostView) relays out
        // alongside, which is exactly when handles wobble (round 2/3 P1#1).
        let headerFrame = CGRect(x: 0, y: 0, width: width, height: headerHeight)
        if headerHost.view.frame != headerFrame { headerHost.view.frame = headerFrame }
        // The text ends at contentSize.height − bottom inset; the footer sits in
        // the reserved bottom inset (no full-document layout pass needed).
        let footerY = contentSize.height - baseTextInsets.bottom - footerHeight + 8
        let footerFrame = CGRect(x: 0, y: max(footerY, headerHeight),
                                 width: width, height: footerHeight)
        if footerHost.view.frame != footerFrame { footerHost.view.frame = footerFrame }
        #if DEBUG
        if firstLineProbe.superview == nil { addSubview(firstLineProbe) }
        let probeFrame = CGRect(x: 0, y: textContainerInset.top, width: width, height: 1)
        if firstLineProbe.frame != probeFrame { firstLineProbe.frame = probeFrame }
        #endif
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
        #if DEBUG
        firstLineProbe.accessibilityElementsHidden = hidden
        firstLineProbe.isAccessibilityElement = !hidden
        #endif
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
