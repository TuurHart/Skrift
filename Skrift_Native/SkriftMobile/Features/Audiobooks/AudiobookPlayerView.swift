import SwiftUI
import UIKit

/// The full player — TEXT-FORWARD redesign (signed-off mock
/// `mocks/audiobook-player-redesign.html`, 2026-06-13). A warm cover-tinted
/// header with the cover demoted to a chip; the live read-along text is the hero
/// (current line lit, from the wave-2 sidecar) with a "transcribe to read along"
/// nudge when a spot isn't chunked; speed/sleep flank the transport; a slim
/// Chapters + Bookmark row sits above the hero Capture pill. Swipe down to
/// collapse to the mini-player; tap the cover to edit book details.
struct AudiobookPlayerView: View {
    @ObservedObject private var session = AudiobookSession.shared
    @Environment(\.dismiss) private var dismiss
    /// iPad wave: regular width uses the room (transport left, read-along at
    /// a reading measure, chapters/bookmarks as a standing rail). Compact
    /// (incl. a split-view/Stage-Manager iPad) keeps today's player untouched.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isRegular: Bool { horizontalSizeClass == .regular }

    @State private var showCapture = false
    @State private var showEditBook = false
    @State private var showTranscribe = false
    @State private var showSyncSheet = false
    /// ⋯ → "Book text…" (device finding 2026-07-22: the verb only lived on the
    /// library's long-press; the player is where you actually are). Same shared
    /// `BookTextFlow` as the library.
    @State private var bookTextBook: Audiobook?
    @State private var showTOC = false
    @State private var showTextSettings = false
    @State private var tocInitialTab: ChaptersBookmarksSheet.Tab = .chapters
    @State private var scrubTime: TimeInterval?
    @State private var dragOffset: CGFloat = 0
    @State private var coverTint: Color?
    @State private var toast: String?
    /// Bookmarks for the current book — reloaded on book change + after a toggle.
    /// Drives the Mark chip's filled/outline state + the read-along margin glyphs.
    @State private var currentBookmarks: [AudiobookBookmark] = []
    /// Reading mode: chrome recedes after idle / on scroll so the page owns the
    /// screen; tap to bring it back. Never recedes while paused.
    @State private var chromeUp = true
    /// Bumped on every interaction to restart the idle-recede countdown.
    @State private var idleToken = 0

    /// ~3.5 s of no interaction while playing → recede (mock: "~3–4s idle").
    private static let idleRecede: UInt64 = 3_500_000_000
    private static let chromeFade = Animation.easeInOut(duration: 0.25)

    private let transcripts = BookTranscriptStore()
    private let bookmarks = BookmarkStore()

    var body: some View {
        ZStack {
            bodyBackground.ignoresSafeArea()
            if let book = session.book {
                content(book)
            } else {
                Color.clear.onAppear { dismiss() }
            }
            if let toast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.skText)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.skElev, in: .capsule)
                    .transition(.opacity)
                    .padding(.bottom, 120)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
            }
        }
        .fullScreenCover(isPresented: $showCapture) { QuoteCaptureFlowView() }
        .sheet(isPresented: $showEditBook) {
            if let book = session.book { EditBookDetailsView(book: book).presentationDetents([.medium]) }
        }
        .sheet(isPresented: $showTranscribe) {
            if let book = session.book { TranscribeBookView(book: book) }
        }
        .sheet(isPresented: $showSyncSheet) {
            if let book = session.book { AudiobookSyncSheet(book: book) }
        }
        .bookTextFlow(book: $bookTextBook)
        .sheet(isPresented: $showTOC, onDismiss: {
            // The sheet can delete bookmarks (swipe) over its own store copy; reload
            // ours so the Mark chip + margin glyphs don't show ghosts.
            if let id = session.book?.id { currentBookmarks = bookmarks.load(bookID: id) }
        }) {
            if let book = session.book {
                ChaptersBookmarksSheet(book: book, initialTab: tocInitialTab)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showTextSettings) { TextSettingsSheet() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("audiobook-player")
        .task(id: session.book?.id) {
            loadCoverTint()
            if let id = session.book?.id { currentBookmarks = bookmarks.load(bookID: id) }
            await prewarmIfUseful()
        }
        // Idle-recede countdown. Restarts whenever the key changes (an interaction
        // bumps idleToken; play/pause flips; chrome shown). Only counts down while
        // chrome is up AND playing — so a paused reader keeps its controls. Never at
        // regular width: the three-zone layout doesn't read `chromeUp` at all, so
        // this would just be wasted work, not a visible bug — the guard is belt and
        // braces, matching the compact-only intent everywhere else in this file.
        .task(id: IdleKey(token: idleToken, up: chromeUp, playing: session.isPlaying)) {
            guard !isRegular, chromeUp, session.isPlaying else { return }
            try? await Task.sleep(nanoseconds: Self.idleRecede)
            guard !Task.isCancelled, session.isPlaying, chromeUp else { return }
            withAnimation(Self.chromeFade) { chromeUp = false }
        }
        // Pausing always brings the chrome back (and the idle task above won't
        // recede it again until playback resumes).
        .onChange(of: session.isPlaying) { _, playing in
            if !playing { withAnimation(Self.chromeFade) { chromeUp = true } }
        }
    }

    /// Composite key so `.task(id:)` restarts the idle countdown on any of these.
    private struct IdleKey: Equatable { let token: Int; let up: Bool; let playing: Bool }

    private func noteInteraction() { idleToken += 1 }

    /// Tap the page: show chrome if hidden, hide it if shown (manual override).
    private func toggleChrome() {
        withAnimation(Self.chromeFade) { chromeUp.toggle() }
        if chromeUp { noteInteraction() }
    }

    /// A reader scroll recedes chrome — but only while playing (paused = reading,
    /// keep controls reachable, per "never while paused").
    private func recedeOnScroll() {
        guard session.isPlaying, chromeUp else { return }
        withAnimation(Self.chromeFade) { chromeUp = false }
    }

    /// v2 (Tuur 2026-07-23): ONE player at every width — the phone's
    /// reading-mode player, just bigger. The wave-1 three-zone iPad layout was
    /// RETIRED (recover from git if the book-expert redesign wants parts); the
    /// only regular-width difference is the read-along capping to a reading
    /// measure so prose never runs wall-to-wall.
    private func content(_ book: Audiobook) -> some View {
        compactContent(book)
    }

    private func compactContent(_ book: Audiobook) -> some View {
        let time = scrubTime ?? session.currentTime
        let location = book.fileLocation(at: time)
        return ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // Chrome up → the full header; receded → a faint one-line mini-header
                // (book · chapter · remaining), so the page owns the screen.
                if chromeUp { header(book) } else { miniHeader(book, time: time) }

                // The read-along is the hero: it fills the space below the header. A
                // user scroll recedes the chrome ("more page" while reading).
                ReadAlongView(
                    book: book,
                    fileIndex: location.index,
                    fileLocal: location.offset,
                    audioURL: session.store.audioURL(of: book, fileIndex: location.index),
                    bookmarks: currentBookmarks,
                    onTranscribe: { showTranscribe = true },
                    onUserScroll: { recedeOnScroll() },
                    onToggleBookmarkInSpan: { start, end in toggleBookmark(inSpan: start, end) }
                )
                .frame(maxHeight: .infinity)
                .frame(maxWidth: isRegular ? 680 : .infinity)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Space.margin)
                .padding(.top, chromeUp ? 16 : 8)

                if chromeUp {
                    VStack(spacing: 0) {
                        scrubber(book, time: time).padding(.bottom, 14)
                        transport.padding(.bottom, 16)
                        utilityRow
                    }
                    .padding(.horizontal, Theme.Space.margin)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }

            // Receded → the one saturated hero floats bottom-right (memo-detail
            // consistency); skip ±15/30 only flank it when controls are up.
            if !chromeUp {
                playButton(size: 52)
                    .padding(.trailing, 18)
                    .padding(.bottom, 18)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        // Tap the page to show/hide chrome (does not intercept line-tap-to-seek or
        // the transport buttons — those handle their own taps).
        .onTapGesture { toggleChrome() }
        .offset(y: dragOffset)
        .gesture(dismissDrag)
    }

    // MARK: - Receded mini-header (reading mode)

    /// The whisper-faint one-liner shown when chrome recedes: "Sapiens · Ch 4" left,
    /// chapter-remaining right (mock screen 3 `.minihdr`).
    private func miniHeader(_ book: Audiobook, time: TimeInterval) -> some View {
        let scope = scopeBounds(book, time: time)
        let chapter = book.chapterIndex(at: time).map { "Ch \($0 + 1)" }
        let left = [book.title, chapter].compactMap { $0 }.joined(separator: " · ")
        return HStack {
            Text(left).lineLimit(1)
            Spacer(minLength: 8)
            Text("−" + AudiobookTime.clock(scope.end - time)).monospacedDigit()
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(Color.skTextFaint)
        .padding(.horizontal, Theme.Space.margin)
        .padding(.top, 12).padding(.bottom, 2)
        .transition(.opacity)
    }

    // MARK: - Header (one slim bar: chevron · cover · title/author · chapter · ⋯)

    /// Reading-mode header: "less chrome, more page" — one compact row (no "NOW
    /// PLAYING" label, cover demoted to a 34pt chip), sitting on the cover-tint
    /// ambiance instead of its own opaque band. Mock screen 2 `.phdr`.
    private func header(_ book: Audiobook) -> some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.skTextDim).frame(width: 30, height: 30)
            }
            .accessibilityIdentifier("player-collapse")
            .accessibilityLabel("Collapse — the mini-player takes over")

            BookCoverView(book: book)
                .frame(width: 34, height: 34)
                .clipShape(.rect(cornerRadius: 7, style: .continuous))
                .onTapGesture { showEditBook = true }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Edit book details")
                .accessibilityIdentifier("player-cover-edit")

            VStack(alignment: .leading, spacing: 1) {
                Text(book.title).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.skText).lineLimit(1)
                Text(book.author).font(.system(size: 12)).foregroundStyle(Color.skTextDim).lineLimit(1)
            }

            Spacer(minLength: 6)

            if let pill = chapterPill(book) {
                // The chapter pill opens the Chapters/Bookmarks browse sheet (it left
                // the utility row to make room for Add note; also in the ⋯ menu).
                Button { tocInitialTab = .chapters; showTOC = true } label: {
                    Text(pill).font(.system(size: 9.5, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Color.skAccentText)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.skAccent.opacity(0.13), in: .capsule)
                }
                .accessibilityIdentifier("player-chapters")
                .accessibilityLabel("Chapters and bookmarks")
            }
            menu(book)
        }
        .padding(.horizontal, Theme.Space.margin)
        .padding(.top, 8).padding(.bottom, 6)
    }

    private func chapterPill(_ book: Audiobook) -> String? {
        guard let i = book.chapterIndex(at: scrubTime ?? session.currentTime) else { return nil }
        return "Ch \(i + 1) / \(book.playableChapters.count)"
    }

    private func menu(_ book: Audiobook) -> some View {
        Menu {
            Button { tocInitialTab = .chapters; showTOC = true } label: { Label("Chapters & bookmarks", systemImage: "list.bullet") }
            Button { showEditBook = true } label: { Label("Edit book details", systemImage: "pencil") }
            Button { showTranscribe = true } label: { Label("Transcribe book", systemImage: "text.book.closed") }
            Button { bookTextBook = book } label: { Label("Book text\u{2026}", systemImage: "doc.badge.plus") }
            // Per-book sync (Phase 1h) — same "Turn it on" sheet as the library long-press.
            Button { showSyncSheet = true } label: {
                Label(AudiobookCloudSync.isSynced(bookID: book.id) ? "Sync settings…" : "Sync this book…",
                      systemImage: "icloud")
            }
            Button(role: .destructive) { session.endSession(); dismiss() } label: {
                Label("End listening session", systemImage: "stop.circle")
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.skTextDim).frame(width: 30, height: 30)
        }
        .accessibilityIdentifier("player-menu")
    }

    // MARK: - Scrubber (chapter-scoped)

    private func scrubber(_ book: Audiobook, time: TimeInterval) -> some View {
        let scope = scopeBounds(book, time: time)
        let length = max(0.1, scope.end - scope.start)
        let fraction = min(1, max(0, (time - scope.start) / length))
        return VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.skBorder).frame(height: 3)
                    Capsule().fill(Color.skAccent).frame(width: max(3, geo.size.width * fraction), height: 3)
                    Circle().fill(.white).frame(width: 11, height: 11)
                        .offset(x: geo.size.width * fraction - 5.5)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            noteInteraction()
                            scrubTime = scope.start + min(1, max(0, v.location.x / geo.size.width)) * length
                        }
                        .onEnded { _ in if let t = scrubTime { session.seek(to: t) }; scrubTime = nil }
                )
            }
            .frame(height: 18)
            .accessibilityIdentifier("player-scrubber")
            HStack {
                Text(AudiobookTime.clock(time - scope.start))
                Spacer()
                Text("−" + AudiobookTime.clock(scope.end - time))
            }
            .font(.system(size: 11)).monospacedDigit().foregroundStyle(Color.skTextFaint)
        }
    }

    private func scopeBounds(_ book: Audiobook, time: TimeInterval) -> (start: TimeInterval, end: TimeInterval) {
        guard let chapter = book.chapter(at: time) else { return (0, max(0.1, book.duration)) }
        return (chapter.start, min(book.duration, chapter.start + max(0.1, chapter.duration)))
    }

    // MARK: - Play (flat accent circle — matches the memo-detail floating play)

    /// The play/pause control: a clean flat accent circle (no gradient sphere — the
    /// user found the sphere look off), with a soft glow. Centred in the transport
    /// when controls are up; floats bottom-right when chrome recedes.
    private func playButton(size: CGFloat) -> some View {
        Button { noteInteraction(); session.togglePlay() } label: {
            ZStack {
                Circle()
                    .fill(Color.skAccent)
                    .frame(width: size, height: size)
                    .shadow(color: Color.skAccent.opacity(0.35), radius: 8, y: 3)
                Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: size * 0.4)).foregroundStyle(.white)
            }
        }
        .accessibilityIdentifier("player-play")
        .accessibilityLabel(session.isPlaying ? "Pause" : "Play")
    }

    // MARK: - Transport (just ⟲15 ▶ 30⟳ — speed + sleep moved to the utility row)

    private var transport: some View {
        HStack(spacing: 0) {
            Spacer()
            Button { noteInteraction(); session.skip(-AudiobookSession.skipBack) } label: {
                Image(systemName: "gobackward.15").font(.system(size: 27, weight: .light)).foregroundStyle(Color.skText)
            }
            .accessibilityIdentifier("player-back-15").accessibilityLabel("Back 15 seconds")
            Spacer().frame(width: 28)
            playButton(size: 56)
            Spacer().frame(width: 28)
            Button { noteInteraction(); session.skip(AudiobookSession.skipForward) } label: {
                Image(systemName: "goforward.30").font(.system(size: 27, weight: .light)).foregroundStyle(Color.skText)
            }
            .accessibilityIdentifier("player-forward-30").accessibilityLabel("Forward 30 seconds")
            Spacer()
        }
    }

    private static func rateLabel(_ r: Double) -> String {
        r == r.rounded() ? String(format: "%.0f×", r) : String(format: "%g×", r)
    }

    // MARK: - Utility row (Aa · Mark · [Add note] · speed · sleep)

    /// Centred cluster with "Add note" as the accent hero in the middle and quiet
    /// icon-only utilities flanking it (mock screen 2 `.util`).
    private var utilityRow: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            textSettingsButton
            addNoteChip
            speedMenu
            sleepMenu
            Spacer(minLength: 0)
        }
    }

    private var textSettingsButton: some View {
        Button { showTextSettings = true } label: {
            Text("Aa").font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.skTextDim).frame(width: 34, height: 32)
        }
        .accessibilityIdentifier("player-text-settings")
        .accessibilityLabel("Text size and spacing")
    }

    /// The hero: capture a quote + your voice ramble from what you just heard.
    private var addNoteChip: some View {
        Button { noteInteraction(); session.pause(); showCapture = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                Text("Add note").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Color.skAccentText)
            .padding(.horizontal, 15).padding(.vertical, 9)
            .background(Color.skAccent.opacity(0.18), in: .capsule)
            .overlay(Capsule().strokeBorder(Color.skAccent.opacity(0.25), lineWidth: 0.5))
        }
        .accessibilityIdentifier("player-capture")
        .accessibilityLabel("Add a note — capture a quote from what you just heard")
    }

    private var speedMenu: some View {
        Menu {
            ForEach(AudiobookSession.rates, id: \.self) { r in
                Button { session.setRate(r) } label: {
                    if session.rate == r { Label(Self.rateLabel(r), systemImage: "checkmark") }
                    else { Text(Self.rateLabel(r)) }
                }
            }
        } label: {
            Text(Self.rateLabel(session.rate)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Color.skTextDim).frame(width: 38, height: 32)
        }
        .accessibilityIdentifier("player-speed")
        .accessibilityLabel("Playback speed")
    }

    private var sleepMenu: some View {
        Menu {
            Button("Off") { session.setSleep(.off) }
            ForEach([5, 15, 30, 45, 60], id: \.self) { m in Button("\(m) minutes") { session.setSleep(.minutes(m)) } }
            if session.book?.playableChapters.isEmpty == false { Button("End of chapter") { session.setSleep(.endOfChapter) } }
        } label: {
            let sleepOn = session.sleepUntil != nil || session.sleepAtChapterEnd
            Image(systemName: sleepOn ? "moon.fill" : "moon")
                .font(.system(size: 17)).foregroundStyle(sleepOn ? Color.skAccent : Color.skTextDim)
                .frame(width: 34, height: 32)
        }
        .accessibilityIdentifier("player-sleep")
        .accessibilityLabel("Sleep timer")
    }

    /// Fold / unfold a page corner: tap the read-along's left gutter to bookmark
    /// that line, tap again to remove it (2026-06-21 — replaces the bottom "Mark"
    /// button; the margin tap IS the gesture). The reader passes the tapped line's
    /// whole GLOBAL span [start, end]: if ANY bookmark sits inside it, lift it (that's
    /// the one the line's glyph shows — wherever in the sentence it landed); else add
    /// one at the start. (Span match, not ±start — the "tapping never removed it" fix.)
    private func toggleBookmark(inSpan start: TimeInterval, _ end: TimeInterval) {
        guard let book = session.book else { return }
        noteInteraction()
        let inSpan = currentBookmarks.filter { $0.position >= start - 0.5 && $0.position <= end + 0.5 }
        if !inSpan.isEmpty {
            for bm in inSpan { currentBookmarks = bookmarks.remove(id: bm.id, bookID: book.id) }
            Haptics.tap()
            showToast("Unfolded")
        } else {
            currentBookmarks = bookmarks.add(
                AudiobookBookmark(position: start, chapterLabel: book.shortChapterLabel(at: start)),
                bookID: book.id)
            Haptics.success()
            showToast("Folded · \(AudiobookTime.clock(start))")
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(.easeIn(duration: 0.3)) { toast = nil }
        }
    }

    // MARK: - Swipe-down to dismiss

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { v in
                if v.translation.height > 0, v.translation.height > abs(v.translation.width) {
                    dragOffset = v.translation.height
                } else if v.translation.height <= 0 { dragOffset = 0 }
            }
            .onEnded { v in
                if dragOffset > 130 || (dragOffset > 0 && v.predictedEndTranslation.height > 280) {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragOffset = 0 }
                }
            }
    }

    // MARK: - Cover tint + pre-warm

    /// Cover-tint ambiance: the warm dominant cover hue bleeds down from the top
    /// and fades to the app background by ~⅓ of the way down (mock: the player-body
    /// gradient — "the warm cover-derived gradient bleeds down the whole player").
    /// Falls back to a flat background when there's no cover.
    private var bodyBackground: some View {
        LinearGradient(
            stops: [
                .init(color: coverTint ?? .skBg, location: 0),
                .init(color: .skBg, location: 0.34),
            ],
            startPoint: .top, endPoint: .bottom)
    }

    private func loadCoverTint() {
        guard let book = session.book,
              let url = AudiobookLibraryStore.shared.coverURL(of: book),
              let img = UIImage(contentsOfFile: url.path),
              let avg = img.averageColor else { coverTint = nil; return }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        avg.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // A deeply-darkened version of the cover's dominant hue — the ambient band.
        coverTint = Color(hue: Double(h), saturation: Double(min(s, 0.55)), brightness: 0.10)
    }

    /// Pre-warm the ASR engine on book-open when the current spot isn't chunked
    /// (so the capture warming screen rarely shows). Skipped when chunked (capture
    /// is instant) or seeded (sim).
    private func prewarmIfUseful() async {
        guard LaunchFlags.seedTranscript == nil,
              let book = session.book else { return }
        let global = session.currentTime
        let fileIndex = book.fileIndex(at: global)
        let bounds = book.fileBounds(at: global)
        let endLocal = min(max(0, global - bounds.start), bounds.length)
        let startLocal = max(0, endLocal - 90)
        let audioURL = session.store.audioURL(of: book, fileIndex: fileIndex)
        let chunked = transcripts.coveredWindowWords(
            bookID: book.id, fileIndex: fileIndex, audioURL: audioURL, start: startLocal, end: endLocal) != nil
        guard !chunked else { return }
        Task { try? await TranscriptionService.shared.ensureLoaded() }
    }
}

private extension UIImage {
    /// Average color of the image (1×1 CIAreaAverage render). nil if unrenderable.
    var averageColor: UIColor? {
        guard let cg = cgImage else { return nil }
        let ci = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ci, kCIInputExtentKey: CIVector(cgRect: ci.extent)
        ]), let out = filter.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(
            out, toBitmap: &px, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return UIColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
    }
}
