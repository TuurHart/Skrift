import SwiftUI

/// The unified "Text" sheet (mock `mocks/book-text-unified.html`, signed off 2026-07-23):
/// ONE sheet behind ONE "Text…" verb, two levels in the order they matter —
/// **Level 1 · Transcript** (the floor: status / live progress / Transcribe, driving
/// `BookTranscriptionJob` inline) stacked above **Level 2 · Book text** (the ceiling:
/// the 2026-07-22 signed-off variant-B timeline sheet, UNCHANGED — bar, legend, per-text
/// rows, Add). Replaces the separate "Transcribe book" + "Book text…" menu entries
/// (library long-press AND player ⋯). `TranscribeBookView` survives solely as the
/// read-along nudge's detail sheet.
///
/// Level-2 notes: the bar's segments are the REAL aligned spans in book-time order,
/// colored per attached text; rows carry the per-text verbs (Re-check / Remove); an
/// attached-but-not-yet-aligned text (added mid-transcribe, or before any transcript)
/// reads as an honest tan "waiting" row, never a bogus verdict.
struct BookTextSheet: View {
    let book: Audiobook
    @ObservedObject private var job = BookTranscriptionJob.shared
    /// Content-sized start: a book with texts attached (bar + legend + rows) is
    /// taller than .medium — opening there read as "cut off" (Tuur, b111).
    @State private var detent: PresentationDetent

    init(book: Audiobook, busyMessage: String? = nil, onAdd: @escaping () -> Void) {
        self.book = book
        self.busyMessage = busyMessage
        self.onAdd = onAdd
        let hasTexts = !(BookAlignmentRunner.textSummary(bookID: book.id)?.perText.isEmpty ?? true)
        _detent = State(initialValue: hasTexts ? .large : .medium)
    }
    /// The presenting view's `attachToast` (busy-message overlay), hosted HERE instead —
    /// a plain view overlay on the presenting view is invisible once this `.sheet` covers the
    /// screen (only UIKit-level presentations like `.alert`/`.fileImporter` stack over a sheet
    /// automatically), so the busy message needs to render from inside the sheet itself.
    var busyMessage: String?
    /// Opens the SAME fileImporter flow the library owns — this sheet never presents its own
    /// picker.
    var onAdd: () -> Void

    @State private var pendingRemove: BookTextSummary.PerText?
    /// The filename currently mid-Remove/-Re-check (disables + spinner-swaps only that row's
    /// ⋯). Mutating it is also what forces a fresh `summary` re-read once either completes —
    /// see `summary` below.
    @State private var busyFilename: String?

    /// Pure read, re-computed on every `body` evaluation — deliberately NOT cached in
    /// `@State`. "The sheet's summary refreshes" (brief) then falls out for free from ordinary
    /// SwiftUI re-render propagation: an attach completing on the presenting view mutates
    /// ITS `@State`, which re-evaluates the `.sheet(item:)` closure and produces a fresh
    /// `BookTextSheet`; a remove/re-check completing HERE mutates `busyFilename`. Either way
    /// `body` re-runs and this re-reads straight from the sidecars — no manual invalidation.
    private var summary: BookTextSummary? { BookAlignmentRunner.textSummary(bookID: book.id) }
    private var perText: [BookTextSummary.PerText] { summary?.perText ?? [] }
    private var bookDuration: TimeInterval { summary?.bookDuration ?? book.duration }

    var body: some View {
        ZStack {
            Color.skSurface.ignoresSafeArea()
            VStack(spacing: 0) {
                Capsule().fill(Color.skBorder).frame(width: 36, height: 4)
                    .frame(maxWidth: .infinity).padding(.top, 8).padding(.bottom, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        levelLabel("Level 1 · Transcript")
                        transcriptCard.padding(.bottom, 18)
                        levelLabel("Level 2 · Book text")
                        if perText.isEmpty {
                            emptyTextCard.padding(.bottom, 10)
                        } else {
                            bar.padding(.bottom, 6)
                            barLabels.padding(.bottom, 18)
                            legend.padding(.bottom, 18)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(perText.enumerated()), id: \.element.filename) { _, text in
                                row(text)
                            }
                            addRow
                        }
                        footer.padding(.top, 14)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.margin)
            .padding(.bottom, 8)

            if let busyMessage {
                // Stage line + the standing reassurance (Tuur 2026-07-22: "didn't know
                // if I could keep listening" — playback is genuinely unaffected).
                VStack(spacing: 3) {
                    Text(busyMessage)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.skText)
                    Text("You can keep listening while this runs.")
                        .font(.system(size: 10.5)).foregroundStyle(Color.skTextDim)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.skElev, in: RoundedRectangle.sk(16))
                .transition(.opacity)
                .padding(.bottom, 20)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .confirmationDialog(
            pendingRemove.map { "Remove \u{201C}\($0.title ?? $0.filename)\u{201D}?" } ?? "",
            isPresented: Binding(get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemove
        ) { text in
            Button("Remove", role: .destructive) { remove(text) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Read-along and captures for this text fall back to the transcript. You can re-add it any time.")
        }
        .accessibilityIdentifier("book-text-sheet")
    }

    // MARK: - Transcript state (Level 1)

    /// True when the singleton job is actively working THIS book (running or either
    /// paused flavor) — the only state in which the card shows live progress.
    private var transcribingThisBook: Bool {
        job.activeBookID == book.id && job.isRunningOrPaused
    }

    /// THIS book's transcript progress: the job's live number only while it's
    /// actually working this book; otherwise a plain cache-served sidecar read.
    /// Never the singleton's shared `progress` at rest — that is whatever book
    /// the job last touched, and the `.task`-based reflect it relied on doesn't
    /// reliably fire inside a sheet over the player's fullScreenCover (b111
    /// device catch: a fully-transcribed book read "Not transcribed").
    private var thisBookProgress: Double {
        transcribingThisBook ? job.progress : job.savedProgress(for: book)
    }

    private var cardState: BookTextDisplay.TranscriptCardState {
        BookTextDisplay.transcriptCardState(progress: thisBookProgress,
                                            transcribingThisBook: transcribingThisBook,
                                            pausedByUser: job.phase == .pausedByUser)
    }

    /// True when any attached text has no aligned coverage yet (the deferred /
    /// attach-before-transcribe case) — drives the tan waiting row + A2 subtitle.
    private var hasWaitingText: Bool { perText.contains(where: BookTextDisplay.isWaiting) }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Text")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.skText)
            Text(subtitleText)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.skTextFaint)
        }
        .padding(.bottom, 16)
    }

    private var subtitleText: String {
        let covered = summary.map {
            BookTextDisplay.percentCovered(covered: $0.totalCoveredSeconds, total: $0.bookDuration)
        } ?? 0
        return BookTextDisplay.sheetSubtitle(coveredPercent: covered,
                                             transcribing: transcribingThisBook,
                                             hasWaitingText: hasWaitingText)
    }

    private func levelLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(1.1)
            .foregroundStyle(Color.skTextFaint)
            .padding(.bottom, 6)
    }

    // MARK: - Level 1 card

    @ViewBuilder
    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            switch cardState {
            case .complete:
                Text("Transcript complete")
                    .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Color.skText)
                (Text(BookTextDisplay.durationText(book.duration) + " transcribed")
                    .foregroundStyle(Color.skGreen)
                 + Text(" · re-runs only if the audio changes")
                    .foregroundStyle(Color.skTextDim))
                    .font(.system(size: 11.5))
            case .transcribing(let paused):
                HStack {
                    Text(paused ? "Paused" : "Transcribing…")
                        .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Color.skText)
                    Spacer()
                    Button {
                        paused ? job.resumeByUser() : job.pauseByUser()
                    } label: {
                        Image(systemName: paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.skTextDim)
                            .frame(width: 26, height: 26)
                    }
                    .accessibilityLabel(paused ? "Resume transcribing" : "Pause transcribing")
                }
                transcriptProgressBar
                Text(transcribingMeta(paused: paused))
                    .font(.system(size: 11.5)).foregroundStyle(Color.skTextDim)
                    .padding(.top, 4)
            case .partial:
                Text("Partly transcribed")
                    .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Color.skText)
                transcriptProgressBar.padding(.top, 4)
                Text("\(Int((thisBookProgress * 100).rounded()))% · resumes where it left off")
                    .font(.system(size: 11.5)).foregroundStyle(Color.skTextDim)
                    .padding(.top, 4)
                transcribeButton("Resume transcribing")
            case .fresh:
                Text("Not transcribed")
                    .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Color.skText)
                Text(freshMeta)
                    .font(.system(size: 11.5)).foregroundStyle(Color.skTextDim)
                transcribeButton("Transcribe")
            }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.skElev, in: RoundedRectangle.sk(14))
        .accessibilityIdentifier("text-sheet-transcript-card")
    }

    private var transcriptProgressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.skBorder)
                Capsule().fill(Color.skAccent)
                    .frame(width: max(6, geo.size.width * thisBookProgress))
            }
        }
        .frame(height: 6)
        .padding(.top, 5)
    }

    private func transcribingMeta(paused: Bool) -> String {
        var parts = ["\(Int((thisBookProgress * 100).rounded()))%"]
        if !paused, let eta = BookTextDisplay.estimateSeconds(
            duration: book.duration, progress: thisBookProgress, rtf: job.measuredRTF) {
            parts.append("≈ \(TranscribeBookView.shortDuration(eta)) left")
        }
        parts.append(job.phase == .pausedUnplugged
                     ? "paused to save battery — resumes automatically"
                     : "runs on battery, pauses in Low Power Mode")
        return parts.joined(separator: " · ")
    }

    /// "Runs on-device, ≈ 24 min for this book." — the estimate uses the job's real
    /// measured per-device throughput; omitted entirely until one exists (never a
    /// fabricated figure — TranscribeBookView's standing rule).
    private var freshMeta: String {
        var line = "Transcribing gives read-along, quote captures and chapter detection. Runs on-device"
        if let eta = BookTextDisplay.estimateSeconds(
            duration: book.duration, progress: thisBookProgress, rtf: job.measuredRTF) {
            line += ", ≈ \(TranscribeBookView.shortDuration(eta)) for this book"
        }
        return line + "."
    }

    private func transcribeButton(_ title: String) -> some View {
        Button { job.start(book: book) } label: {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.skAccent, in: RoundedRectangle.sk(10))
        }
        .padding(.top, 7)
        .accessibilityIdentifier("text-sheet-transcribe")
    }

    // MARK: - Level 2 empty card

    private var emptyTextCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("No book text attached")
                .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Color.skText)
            Text("Add the ePub to upgrade read-along and captures to the published words, and chapters to the real table of contents.")
                .font(.system(size: 11.5)).foregroundStyle(Color.skTextDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.skElev, in: RoundedRectangle.sk(14))
        .opacity(0.62)
    }

    // MARK: - Bar

    private var bar: some View {
        // STRICTLY TIME-TRUE (device round 4, 2026-07-22: the mock-copied 2 pt
        // inter-segment spacing rendered a 44 s real gap ~5× too wide — "that's like
        // ten minutes of gap"). Grey is the background; colored spans overlay at
        // exact fractions; nothing is spaced, padded, or minimum-widthed. The truth,
        // at pixel resolution.
        let segments = BookTextDisplay.barSegments(perText: perText, bookDuration: bookDuration)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.skElev
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    if let idx = seg.textIndex {
                        colorFor(idx)
                            .frame(width: max(0, geo.size.width * seg.widthFraction))
                            .offset(x: geo.size.width * seg.startFraction)
                    }
                }
            }
        }
        .frame(height: 14)
        .clipShape(RoundedRectangle.sk(7))
        .accessibilityLabel(barAccessibilityLabel)
    }

    private var barAccessibilityLabel: String {
        guard let summary, !summary.perText.isEmpty else { return "No book text attached" }
        let pct = BookTextDisplay.percentCovered(covered: summary.totalCoveredSeconds, total: summary.bookDuration)
        let n = summary.perText.count
        return "\(pct) percent real book text, \(n) text\(n == 1 ? "" : "s") attached"
    }

    private var barLabels: some View {
        HStack {
            Text(AudiobookTime.clock(0))
            Spacer()
            Text(AudiobookTime.clock(bookDuration))
        }
        .font(.system(size: 10.5))
        .monospacedDigit()
        .foregroundStyle(Color.skTextFaint)
    }

    // MARK: - Legend

    private var legend: some View {
        FlowLayout(spacing: 12, lineSpacing: 6) {
            ForEach(Array(perText.enumerated()), id: \.element.filename) { i, text in
                legendChip(color: colorFor(i), label: text.title ?? text.filename)
            }
            legendChip(color: Color.skElev, label: "transcript")
        }
    }

    private func legendChip(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle.sk(3)
                .fill(color)
                .frame(width: 9, height: 9)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.skTextDim)
                .lineLimit(1)
        }
    }

    /// BASE.md's pinned color rule: accent for text 0, tan (`skNameSuggest` — the app's
    /// existing tan-toned text tier) for text 1, cycling for any further attached text.
    private func colorFor(_ textIndex: Int) -> Color {
        BookTextDisplay.colorCycleIndex(textIndex) == 0 ? Color.skAccent : Color.skNameSuggest
    }

    // MARK: - Rows

    private func row(_ text: BookTextSummary.PerText) -> some View {
        let isBusy = busyFilename == text.filename
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(text.title ?? text.filename)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color.skText)
                    .lineLimit(1)
                Spacer()
                if isBusy {
                    ProgressView().controlSize(.mini).frame(width: 24, height: 24)
                } else {
                    Menu {
                        Button { recheck(text) } label: {
                            Label("Re-check", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button(role: .destructive) { pendingRemove = text } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.skTextFaint)
                            .frame(width: 24, height: 24)
                    }
                    .accessibilityLabel("\(text.title ?? text.filename) options")
                }
            }
            if BookTextDisplay.isWaiting(text) {
                // Deferred / attach-before-transcribe (mock A2): honest tan waiting
                // line, never a bogus verdict off a missing or partial transcript.
                (Text(transcribingThisBook ? "Waiting for the transcript" : "No transcript yet")
                    .foregroundStyle(Color.skNameSuggest)
                 + Text(" — it will match up on its own the moment transcription finishes.")
                    .foregroundStyle(Color.skTextDim))
                    .font(.system(size: 11.5))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(metaText(for: text))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.skTextDim)
            }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .background(Color.skElev, in: RoundedRectangle.sk(14))
        .accessibilityIdentifier("book-text-row-\(text.filename)")
    }

    /// "58 min · full match" — duration formatted h/min, "full match" when this text's
    /// `coveredSeconds` accounts for essentially all of the audio files it aligned to.
    private func metaText(for text: BookTextSummary.PerText) -> String {
        let duration = BookTextDisplay.durationText(text.coveredSeconds)
        let alignedDuration = text.fileNumbers.reduce(TimeInterval(0)) { sum, n in
            let idx = n - 1
            return sum + (book.fileDurations.indices.contains(idx) ? book.fileDurations[idx] : 0)
        }
        let wording = BookTextDisplay.matchWording(coveredSeconds: text.coveredSeconds, alignedFilesDuration: alignedDuration)
        return "\(duration) · \(wording)"
    }

    // MARK: - Add + footer

    private var addRow: some View {
        Button(action: onAdd) {
            Text("\u{FF0B} \(BookTextDisplay.addRowLabel(hasTexts: !perText.isEmpty))")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.skAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle.sk(14)
                        .strokeBorder(Color.skAccent.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("book-text-add")
        .accessibilityLabel("Add book text")
    }

    private var footer: some View {
        Text(BookTextDisplay.sheetFooter(transcribing: transcribingThisBook,
                                         hasCoverage: (summary?.totalCoveredSeconds ?? 0) > 0))
            .font(.system(size: 10.5))
            .foregroundStyle(Color.skTextFaint)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func recheck(_ text: BookTextSummary.PerText) {
        busyFilename = text.filename
        Task {
            await BookAlignmentRunner.alignIfNeeded(bookID: book.id)
            busyFilename = nil
        }
    }

    private func remove(_ text: BookTextSummary.PerText) {
        busyFilename = text.filename
        Task {
            await BookAlignmentRunner.removeText(filename: text.filename, bookID: book.id)
            busyFilename = nil
        }
    }
}

// MARK: - Pure display logic (unit-tested — BookTextSummaryDisplayTests.swift)

/// Pure formatting/layout math for `BookTextSheet` — no I/O, no MainActor, everything a plain
/// function of its arguments (mirrors `AlignedSentenceSource`'s house style for this class of
/// helper). Kept in this file since `BookTextSheet.swift` is the one new non-test file this
/// lane owns.
enum BookTextDisplay {
    /// One bar slice: `textIndex` nil = uncovered (grey); otherwise the index into the
    /// summary's `perText` this slice came from. Fractions are 0...1 over the WHOLE bar.
    struct BarSegment: Equatable {
        var textIndex: Int?
        var startFraction: Double
        var widthFraction: Double
    }

    // MARK: Level 1 (unified "Text" sheet, mock book-text-unified.html)

    /// Which face the Level-1 transcript card wears. Precedence: a LIVE run on this
    /// book always shows as transcribing (even at 99.9% — the run owns the card until
    /// it finishes); then done; then a resumable partial; then fresh.
    enum TranscriptCardState: Equatable {
        case complete
        case transcribing(paused: Bool)
        case partial
        case fresh
    }

    static func transcriptCardState(progress: Double, transcribingThisBook: Bool,
                                    pausedByUser: Bool) -> TranscriptCardState {
        if transcribingThisBook { return .transcribing(paused: pausedByUser) }
        if progress >= 0.999 { return .complete }
        if progress > 0.001 { return .partial }
        return .fresh
    }

    /// An attached text with no aligned coverage anywhere — the deferred /
    /// attach-before-transcribe case (mock A2's tan "waiting" row).
    static func isWaiting(_ text: BookTextSummary.PerText) -> Bool {
        text.coveredSeconds <= 0 && text.fileNumbers.isEmpty
    }

    /// The sheet subtitle (mock A1/A2/A3): coverage wins whenever real book text
    /// exists; the queued line only while transcribing WITH a waiting text; else the
    /// standing invitation.
    static func sheetSubtitle(coveredPercent: Int, transcribing: Bool, hasWaitingText: Bool) -> String {
        if coveredPercent > 0 { return "Real book text covers \(coveredPercent)% of this audiobook" }
        if transcribing, hasWaitingText { return "Transcribing · the book text is queued behind it." }
        return "Give this audiobook words — transcribe it, then add the real book for the published text."
    }

    /// The dashed add row's label (Tuur amendment, b110 eyeball 2026-07-23: "it
    /// already got text… the text should change once you already uploaded a book
    /// and it got matched") — the bare invitation only while Level 2 is empty;
    /// with any text attached it reads as the multi-ePub affordance it is.
    static func addRowLabel(hasTexts: Bool) -> String {
        hasTexts ? "Add another text\u{2026}" : "Add book text\u{2026}"
    }

    /// Wall-seconds to transcribe the untranscribed remainder of a book, from the
    /// job's real measured per-device throughput. nil until a rate exists or when
    /// nothing meaningful remains — the caller omits the figure entirely (never a
    /// fabricated estimate).
    static func estimateSeconds(duration: TimeInterval, progress: Double, rtf: Double?) -> TimeInterval? {
        guard let rtf, rtf > 0 else { return nil }
        let remaining = max(0, duration * (1 - min(1, max(0, progress))))
        let eta = remaining / rtf
        return eta > 1 ? eta : nil
    }

    /// The sheet footer (mock A1/A2/A3).
    static func sheetFooter(transcribing: Bool, hasCoverage: Bool) -> String {
        if transcribing { return "You can keep listening while both run." }
        if hasCoverage { return "Texts never change your audio or transcript." }
        return "Both run in the background — you can keep listening."
    }

    /// Whole-percent coverage, rounded, clamped to 0...100 (defensive against FP overshoot
    /// when `covered` ≈ `total`). `total <= 0` → 0 (nothing to divide by).
    static func percentCovered(covered: TimeInterval, total: TimeInterval) -> Int {
        guard total > 0 else { return 0 }
        let pct = (covered / total * 100).rounded()
        return max(0, min(100, Int(pct)))
    }

    /// "58 min" under an hour, "1 h 06" at/over an hour (always 2-digit minutes) — matches
    /// `mocks/book-text-sheet.html` #m2's row examples exactly.
    static func durationText(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int((max(0, seconds) / 60).rounded())
        let h = totalMinutes / 60, m = totalMinutes % 60
        if h > 0 { return String(format: "%d h %02d", h, m) }
        return "\(m) min"
    }

    /// Fraction of the aligned files' duration a text's `coveredSeconds` must reach to read as
    /// "full match" rather than "partial" (the aligner will essentially never claim literally
    /// 100% of a file down to the millisecond — the last sliver of silence/tail audio
    /// shouldn't read as a partial match). 0.97→0.95, 2026-07-22 device round: the real Steal
    /// file 1 sits at 96.7% — the missing ~2 min are narrator credits + unnarrated front
    /// matter, exactly what this tolerance exists to absorb, and it read "partial".
    static let matchTolerance = 0.95

    static func isFullMatch(coveredSeconds: TimeInterval, alignedFilesDuration: TimeInterval) -> Bool {
        guard alignedFilesDuration > 0 else { return false }
        return coveredSeconds >= alignedFilesDuration * matchTolerance
    }

    /// "full match" / "partial" — see `isFullMatch`. Zero `alignedFilesDuration` (nothing
    /// aligned yet) always reads "partial", never a false "full match" on zero coverage.
    static func matchWording(coveredSeconds: TimeInterval, alignedFilesDuration: TimeInterval) -> String {
        isFullMatch(coveredSeconds: coveredSeconds, alignedFilesDuration: alignedFilesDuration) ? "full match" : "partial"
    }

    /// Text index → color-slot index (BASE.md's pinned rule: accent for 0, tan for 1, then
    /// cycle — only two Theme tones are assigned, a third+ attached text repeats from accent).
    static func colorCycleIndex(_ textIndex: Int) -> Int {
        textIndex % 2
    }

    /// The bar's span→fraction math. Flattens every text's `spans` into one
    /// `(range, textIndex)` list, sorts by start, and walks it left→right emitting an
    /// uncovered segment (`textIndex: nil`) for every gap plus a colored segment for every
    /// span — so the result is always one contiguous, chronologically-ordered tiling of
    /// `[0, bookDuration]`. Clamps defensively to `[0, bookDuration]` even though
    /// `PerText.spans` are contracted to already be GLOBAL/merged/sorted per text (cross-text
    /// overlap shouldn't occur either, given the sentence-level collision rule, but this never
    /// trusts that blindly). `bookDuration <= 0` → `[]`. Empty `perText` → one full-width
    /// uncovered segment — the empty state's "bar all-grey" falls out of this with no special
    /// case in the view.
    static func barSegments(perText: [BookTextSummary.PerText], bookDuration: TimeInterval) -> [BarSegment] {
        guard bookDuration > 0 else { return [] }
        var tagged: [(range: ClosedRange<TimeInterval>, textIndex: Int)] = []
        for (i, pt) in perText.enumerated() {
            for span in pt.spans { tagged.append((span, i)) }
        }
        tagged.sort { $0.range.lowerBound < $1.range.lowerBound }

        var segments: [BarSegment] = []
        var cursor: TimeInterval = 0
        for t in tagged {
            let start = min(max(cursor, t.range.lowerBound), bookDuration)
            let end = min(max(start, t.range.upperBound), bookDuration)
            if start > cursor {
                segments.append(BarSegment(textIndex: nil, startFraction: cursor / bookDuration,
                                           widthFraction: (start - cursor) / bookDuration))
            }
            if end > start {
                segments.append(BarSegment(textIndex: t.textIndex, startFraction: start / bookDuration,
                                           widthFraction: (end - start) / bookDuration))
            }
            cursor = max(cursor, end)
        }
        if cursor < bookDuration {
            segments.append(BarSegment(textIndex: nil, startFraction: cursor / bookDuration,
                                       widthFraction: (bookDuration - cursor) / bookDuration))
        }
        return segments
    }
}
