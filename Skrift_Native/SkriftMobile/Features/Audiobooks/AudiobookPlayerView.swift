import SwiftUI

/// The full player (mock state 2 — Bound parity + the one Skrift verb):
/// cover, chapter line, chapter-scoped scrubber, speed + sleep chips,
/// ⟲15 / play / 15⟳ transport, and the full-width Capture pill in the thumb
/// zone. ⌄ collapses back to the list — the mini-player takes over. Swiping
/// DOWN anywhere outside the scrubber also collapses (round-2 re-test ask:
/// a fullScreenCover doesn't get the sheet's pull-down for free), and tapping
/// the big cover opens Edit book details (the ⋯ entry was never discovered).
struct AudiobookPlayerView: View {
    @ObservedObject private var session = AudiobookSession.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showCapture = false
    @State private var showEditBook = false
    /// While the finger is on the scrubber: the candidate time (seek on release).
    @State private var scrubTime: TimeInterval?
    /// Live vertical displacement of the swipe-down-to-dismiss drag.
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.skBg.ignoresSafeArea()
            if let book = session.book {
                content(book)
            } else {
                // Session ended underneath us (e.g. book deleted) — nothing to show.
                Color.clear.onAppear { dismiss() }
            }
        }
        .fullScreenCover(isPresented: $showCapture) {
            QuoteCaptureFlowView()
        }
        .sheet(isPresented: $showEditBook) {
            // Re-read at presentation — the freshest record, and nothing to
            // show if the session ended underneath the menu.
            if let book = session.book {
                EditBookDetailsView(book: book)
                    .presentationDetents([.medium])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("audiobook-player")
    }

    private func content(_ book: Audiobook) -> some View {
        let time = scrubTime ?? session.currentTime
        return VStack(spacing: 0) {
            navBar(book)

            Spacer(minLength: 6)

            BookCoverView(book: book)
                .frame(width: 264, height: 264)
                .clipShape(.rect(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
                // Discoverability (round-2 re-test): the user never found
                // ⋯ → Edit book details — the cover itself is the obvious
                // "change this" surface.
                .onTapGesture { showEditBook = true }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Edit book details")
                .accessibilityIdentifier("player-cover-edit")

            Group {
                if let line = book.chapterLine(at: time) {
                    Text(line.uppercased())
                        .font(.system(size: 10.5, weight: .medium))
                        .kerning(0.5)
                        .foregroundStyle(Color.skTextFaint)
                        .padding(.top, 16)
                        .accessibilityIdentifier("player-chapter-line")
                }
                Text(book.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.skText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 3)
                Text(book.author)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.skTextDim)
                    .padding(.top, 1)
            }
            .padding(.horizontal, Theme.Space.margin)

            scrubber(book, time: time)
                .padding(.horizontal, Theme.Space.margin + 6)
                .padding(.top, 14)

            chips
                .padding(.top, 12)

            transport
                .padding(.top, 14)

            Spacer(minLength: 10)

            captureButton
                .padding(.horizontal, Theme.Space.margin)
            Text("pauses & proposes the last 30 s — adjust on a fine scrubber, confirm")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.skTextFaint)
                .padding(.top, 7)
                .padding(.bottom, 18)
        }
        // Empty regions (spacers, padding) must be hit-testable for the
        // dismiss drag.
        .contentShape(Rectangle())
        .offset(y: dragOffset)
        .gesture(dismissDrag)
    }

    /// Swipe-down-to-dismiss: the content tracks the finger, then either
    /// collapses (past the threshold or flicked) or springs back. Only
    /// downward, vertically-dominant drags move it — horizontal motion stays
    /// with the scrubber (whose own DragGesture wins inside its frame anyway,
    /// since a child gesture beats an ancestor's).
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                if value.translation.height > 0,
                   value.translation.height > abs(value.translation.width) {
                    dragOffset = value.translation.height
                } else if value.translation.height <= 0 {
                    // Dragged back above the start — fully relaxed, no dismiss.
                    dragOffset = 0
                }
            }
            .onEnded { value in
                // The flick path still requires the drag to have been tracking
                // (dragOffset > 0) so a diagonal fling can't dismiss by surprise.
                if dragOffset > 130 || (dragOffset > 0 && value.predictedEndTranslation.height > 280) {
                    // Leave the offset in place — the cover's dismissal
                    // animation takes over; the view is recreated next open.
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        dragOffset = 0
                    }
                }
            }
    }

    // MARK: - Nav

    private func navBar(_ book: Audiobook) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.skTextDim)
                    .frame(width: 30, height: 30)
            }
            .accessibilityIdentifier("player-collapse")
            .accessibilityLabel("Collapse — the mini-player takes over")

            Spacer()
            Text("NOW PLAYING")
                .font(.system(size: 10.5, weight: .medium))
                .kerning(0.8)
                .foregroundStyle(Color.skTextFaint)
            Spacer()

            Menu {
                if !book.chapters.isEmpty {
                    // Display titles, not raw chapter names — synthesized
                    // multi-file chapters carry whole filenames otherwise.
                    let titles = book.displayChapterTitles
                    Section("Chapters") {
                        ForEach(Array(book.chapters.enumerated()), id: \.offset) { index, chapter in
                            Button {
                                session.seek(to: chapter.start)
                            } label: {
                                if book.chapterIndex(at: session.currentTime) == index {
                                    Label(titles[index], systemImage: "checkmark")
                                } else {
                                    Text(titles[index])
                                }
                            }
                        }
                    }
                }
                Button {
                    showEditBook = true
                } label: {
                    Label("Edit book details", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    session.endSession()
                    dismiss()
                } label: {
                    Label("End listening session", systemImage: "stop.circle")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.skTextDim)
                    .frame(width: 30, height: 30)
            }
            .accessibilityIdentifier("player-menu")
        }
        .padding(.horizontal, Theme.Space.margin)
        .padding(.top, 8)
    }

    // MARK: - Scrubber (chapter-scoped; whole book when there are no chapters)

    private func scrubber(_ book: Audiobook, time: TimeInterval) -> some View {
        let scope = scopeBounds(book, time: time)
        let length = max(0.1, scope.end - scope.start)
        let fraction = min(1, max(0, (time - scope.start) / length))

        return VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.skBorder)
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.skAccent)
                        .frame(width: max(4, geo.size.width * fraction), height: 4)
                    Circle()
                        .fill(.white)
                        .frame(width: 12, height: 12)
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                        .offset(x: geo.size.width * fraction - 6)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let f = min(1, max(0, value.location.x / geo.size.width))
                            scrubTime = scope.start + f * length
                        }
                        .onEnded { _ in
                            if let t = scrubTime { session.seek(to: t) }
                            scrubTime = nil
                        }
                )
            }
            .frame(height: 22)
            .accessibilityIdentifier("player-scrubber")

            HStack {
                Text(AudiobookTime.clock(time - scope.start))
                Spacer()
                Text("−" + AudiobookTime.clock(scope.end - time))
            }
            .font(.system(size: 10.5))
            .monospacedDigit()
            .foregroundStyle(Color.skTextFaint)
        }
    }

    /// The scrubber's range: the current chapter (a 15 h book makes a
    /// whole-book scrubber useless), or the whole book without chapters.
    private func scopeBounds(_ book: Audiobook, time: TimeInterval) -> (start: TimeInterval, end: TimeInterval) {
        guard let chapter = book.chapter(at: time) else { return (0, max(0.1, book.duration)) }
        return (chapter.start, min(book.duration, chapter.start + max(0.1, chapter.duration)))
    }

    // MARK: - Chips

    private var chips: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(AudiobookSession.rates, id: \.self) { r in
                    Button {
                        session.setRate(r)
                    } label: {
                        if session.rate == r {
                            Label(Self.rateLabel(r), systemImage: "checkmark")
                        } else {
                            Text(Self.rateLabel(r))
                        }
                    }
                }
            } label: {
                chipLabel(Self.rateLabel(session.rate))
            }
            .accessibilityIdentifier("player-speed")

            Menu {
                Button("Off") { session.setSleep(.off) }
                ForEach([5, 15, 30, 45, 60], id: \.self) { m in
                    Button("\(m) minutes") { session.setSleep(.minutes(m)) }
                }
                if session.book?.chapters.isEmpty == false {
                    Button("End of chapter") { session.setSleep(.endOfChapter) }
                }
            } label: {
                chipLabel(session.sleepLabel, systemImage: "moon")
            }
            .accessibilityIdentifier("player-sleep")
        }
    }

    private static func rateLabel(_ r: Double) -> String {
        r == r.rounded() ? String(format: "%.0f×", r) : String(format: "%g×", r)
    }

    private func chipLabel(_ text: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 10))
            }
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(Color.skTextDim)
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(Color.skElev, in: .capsule)
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 30) {
            Button {
                session.skip(-AudiobookSession.skipInterval)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Color.skText)
            }
            .accessibilityIdentifier("player-back-15")
            .accessibilityLabel("Back 15 seconds")

            Button {
                session.togglePlay()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.skElev)
                        .frame(width: 66, height: 66)
                    Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.skText)
                }
            }
            .accessibilityIdentifier("player-play")
            .accessibilityLabel(session.isPlaying ? "Pause" : "Play")

            Button {
                session.skip(AudiobookSession.skipInterval)
            } label: {
                Image(systemName: "goforward.15")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Color.skText)
            }
            .accessibilityIdentifier("player-forward-15")
            .accessibilityLabel("Forward 15 seconds")
        }
    }

    // MARK: - Capture

    private var captureButton: some View {
        Button {
            session.pause()
            showCapture = true
        } label: {
            HStack(spacing: 9) {
                Text("❝")
                    .font(.system(size: 19, weight: .heavy))
                Text("Capture")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.skAccent, in: .rect(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.skAccent.opacity(0.45), radius: 8, y: 2)
        }
        .accessibilityIdentifier("player-capture")
        .accessibilityLabel("Capture — pauses and proposes the last 30 seconds")
    }
}
