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

    @State private var showCapture = false
    @State private var showEditBook = false
    @State private var showTranscribe = false
    @State private var showTOC = false
    @State private var tocInitialTab: ChaptersBookmarksSheet.Tab = .chapters
    @State private var scrubTime: TimeInterval?
    @State private var dragOffset: CGFloat = 0
    @State private var coverTint: Color?
    @State private var toast: String?

    private let transcripts = BookTranscriptStore()
    private let bookmarks = BookmarkStore()

    var body: some View {
        ZStack {
            Color.skBg.ignoresSafeArea()
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
        .sheet(isPresented: $showTOC) {
            if let book = session.book {
                ChaptersBookmarksSheet(book: book, initialTab: tocInitialTab)
                    .presentationDetents([.medium, .large])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("audiobook-player")
        .task(id: session.book?.id) {
            loadCoverTint()
            await prewarmIfUseful()
        }
    }

    private func content(_ book: Audiobook) -> some View {
        let time = scrubTime ?? session.currentTime
        let location = book.fileLocation(at: time)
        return VStack(spacing: 0) {
            header(book)
            // The read-along is the hero: it fills the space below the header, and
            // the controls pin to the bottom edge — no dead `Spacer` gap (2026-06-13).
            ReadAlongView(
                book: book,
                fileIndex: location.index,
                fileLocal: location.offset,
                audioURL: session.store.audioURL(of: book, fileIndex: location.index),
                onTranscribe: { showTranscribe = true }
            )
            .frame(maxHeight: .infinity)
            .padding(.horizontal, Theme.Space.margin)
            .padding(.top, 16)

            VStack(spacing: 0) {
                scrubber(book, time: time).padding(.bottom, 14)
                transport.padding(.bottom, 14)
                utilityRow.padding(.bottom, 14)
                captureButton
            }
            .padding(.horizontal, Theme.Space.margin)
            .padding(.top, 14)
            .padding(.bottom, 8)
        }
        .contentShape(Rectangle())
        .offset(y: dragOffset)
        .gesture(dismissDrag)
    }

    // MARK: - Header (warm tint band, cover chip, title, chapter pill)

    private func header(_ book: Audiobook) -> some View {
        VStack(spacing: 14) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.skTextDim).frame(width: 30, height: 30)
                }
                .accessibilityIdentifier("player-collapse")
                .accessibilityLabel("Collapse — the mini-player takes over")
                Spacer()
                Text("NOW PLAYING").font(.system(size: 10.5, weight: .medium)).kerning(0.8)
                    .foregroundStyle(Color.skTextFaint)
                Spacer()
                menu(book)
            }

            HStack(spacing: 12) {
                BookCoverView(book: book)
                    .frame(width: 56, height: 56)
                    .clipShape(.rect(cornerRadius: 9, style: .continuous))
                    .onTapGesture { showEditBook = true }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Edit book details")
                    .accessibilityIdentifier("player-cover-edit")
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title).font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.skText).lineLimit(1)
                    Text(book.author).font(.system(size: 12)).foregroundStyle(Color.skTextDim).lineLimit(1)
                }
                Spacer(minLength: 6)
                if let pill = chapterPill(book) {
                    Text(pill).font(.system(size: 11)).foregroundStyle(Color.skAmber)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Color.skAmber.opacity(0.14), in: .capsule)
                }
            }
        }
        .padding(.horizontal, Theme.Space.margin)
        .padding(.top, 10).padding(.bottom, 16)
        .background((coverTint ?? Color.skSurface).ignoresSafeArea(edges: .top))
    }

    private func chapterPill(_ book: Audiobook) -> String? {
        guard let i = book.chapterIndex(at: scrubTime ?? session.currentTime) else { return nil }
        return "Ch \(i + 1) / \(book.chapters.count)"
    }

    private func menu(_ book: Audiobook) -> some View {
        Menu {
            Button { showEditBook = true } label: { Label("Edit book details", systemImage: "pencil") }
            Button { showTranscribe = true } label: { Label("Transcribe book", systemImage: "text.book.closed") }
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
                        .onChanged { v in scrubTime = scope.start + min(1, max(0, v.location.x / geo.size.width)) * length }
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

    // MARK: - Transport (speed ◁ ⟲15 ▶ 15⟳ ▷ sleep)

    private var transport: some View {
        HStack(spacing: 0) {
            Menu {
                ForEach(AudiobookSession.rates, id: \.self) { r in
                    Button { session.setRate(r) } label: {
                        if session.rate == r {
                            Label(Self.rateLabel(r), systemImage: "checkmark")
                        } else {
                            Text(Self.rateLabel(r))
                        }
                    }
                }
            } label: {
                Text(Self.rateLabel(session.rate)).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.skTextDim).frame(width: 44)
            }
            .accessibilityIdentifier("player-speed")

            Spacer()
            Button { session.skip(-AudiobookSession.skipInterval) } label: {
                Image(systemName: "gobackward.15").font(.system(size: 26, weight: .light)).foregroundStyle(Color.skText)
            }
            .accessibilityIdentifier("player-back-15").accessibilityLabel("Back 15 seconds")
            Spacer().frame(width: 26)
            Button { session.togglePlay() } label: {
                ZStack {
                    Circle().fill(Color.skAccent).frame(width: 60, height: 60)
                    Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 23)).foregroundStyle(.white)
                }
            }
            .accessibilityIdentifier("player-play").accessibilityLabel(session.isPlaying ? "Pause" : "Play")
            Spacer().frame(width: 26)
            Button { session.skip(AudiobookSession.skipInterval) } label: {
                Image(systemName: "goforward.15").font(.system(size: 26, weight: .light)).foregroundStyle(Color.skText)
            }
            .accessibilityIdentifier("player-forward-15").accessibilityLabel("Forward 15 seconds")
            Spacer()

            Menu {
                Button("Off") { session.setSleep(.off) }
                ForEach([5, 15, 30, 45, 60], id: \.self) { m in Button("\(m) minutes") { session.setSleep(.minutes(m)) } }
                if session.book?.chapters.isEmpty == false { Button("End of chapter") { session.setSleep(.endOfChapter) } }
            } label: {
                let sleepOn = session.sleepUntil != nil || session.sleepAtChapterEnd
                Image(systemName: sleepOn ? "moon.fill" : "moon")
                    .font(.system(size: 17)).foregroundStyle(sleepOn ? Color.skAccent : Color.skTextDim)
                    .frame(width: 44)
            }
            .accessibilityIdentifier("player-sleep")
        }
    }

    private static func rateLabel(_ r: Double) -> String {
        r == r.rounded() ? String(format: "%.0f×", r) : String(format: "%g×", r)
    }

    // MARK: - Slim utility row (Chapters · Bookmark)

    private var utilityRow: some View {
        HStack(spacing: 10) {
            utilChip("Chapters", icon: "list.bullet", id: "player-chapters") {
                tocInitialTab = .chapters; showTOC = true
            }
            utilChip("Bookmark", icon: "bookmark", id: "player-bookmark") { dropBookmark() }
        }
    }

    private func utilChip(_ title: String, icon: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 13))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color.skTextDim)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Color.skElev, in: .rect(cornerRadius: 11, style: .continuous))
        }
        .accessibilityIdentifier(id)
    }

    private func dropBookmark() {
        guard let book = session.book else { return }
        let at = session.currentTime
        let before = bookmarks.load(bookID: book.id).count
        let after = bookmarks.add(
            AudiobookBookmark(position: at, chapterLabel: book.shortChapterLabel(at: at)),
            bookID: book.id
        ).count
        Haptics.success()
        showToast(after > before ? "Bookmarked · \(AudiobookTime.clock(at))" : "Already bookmarked here")
    }

    private func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(.easeIn(duration: 0.3)) { toast = nil }
        }
    }

    // MARK: - Capture (hero)

    private var captureButton: some View {
        Button {
            session.pause(); showCapture = true
        } label: {
            HStack(spacing: 9) {
                Text("❝").font(.system(size: 18, weight: .heavy))
                Text("Capture this").font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(Color.skAccent, in: .rect(cornerRadius: 15, style: .continuous))
        }
        .accessibilityIdentifier("player-capture")
        .accessibilityLabel("Capture a quote from what you just heard")
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
