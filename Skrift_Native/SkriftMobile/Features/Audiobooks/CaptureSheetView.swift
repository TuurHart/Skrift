import SwiftUI

/// Mock state 4 — the capture sheet over the dimmed player: the snapped quote
/// in italics + a plain attribution PREVIEW ("— Author, Book, ch. N" — the
/// `[[Author]]` wikilink is written by the Mac at export ONLY), the BIG
/// record-your-thoughts button (the ramble; reuses the recording stack via
/// `RecordView(appendTo:)` so it transcribes and appends below the quote per
/// C1), "Save & keep listening", and the significance circles (the usual
/// flag-to-send gate — unrated captures stay on the phone).
///
/// Post-ramble (device-test fix): the book does NOT auto-resume when the
/// recorder closes — it stays paused so the spoken thoughts can be reviewed
/// (they appear under the quote as they transcribe), the big purple button
/// flips to a modest "Add more", and "Save & keep listening" — now the
/// primary action — is the ONLY path that resumes playback.
struct CaptureSheetView: View {
    let book: Audiobook
    let output: QuoteCaptureOutput
    let memoID: UUID
    /// Close-and-save. `resume: true` restarts the book ("Save & keep
    /// listening"); `false` keeps it paused (✕ after a ramble).
    var onFinish: (_ resume: Bool) -> Void
    /// ✕ before any ramble: delete the capture memo + resume.
    var onDiscard: () -> Void

    @ObservedObject private var session = AudiobookSession.shared
    @State private var significance: Double = 0
    @State private var showRamble = false
    @State private var rambleAdded = false
    /// The capture's memo (a SwiftData `@Model`, so Observation re-renders
    /// this sheet when the appended ramble's transcription lands).
    @State private var memo: Memo?

    var body: some View {
        ZStack {
            backdrop
            VStack {
                Spacer(minLength: 0)
                sheet
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .onAppear { memo = NotesRepository.shared.memo(id: memoID) }
        .fullScreenCover(isPresented: $showRamble) {
            // NO auto-resume on dismiss — the book resumes only via
            // "Save & keep listening", so the ramble can be reviewed first.
            RecordView(onSaved: { _ in rambleAdded = true }, appendTo: memoID)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture-sheet")
    }

    // MARK: - Backdrop (the dimmed player)

    private var backdrop: some View {
        ZStack {
            VStack {
                BookCoverView(book: book)
                    .frame(width: 170, height: 170)
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
                    .padding(.top, 30)
                Spacer()
            }
            .opacity(0.45)
            .saturation(0.6)
            Color.black.opacity(0.45).ignoresSafeArea()
        }
    }

    // MARK: - Sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color.skTextFaint.opacity(0.5))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)

            header
                .padding(.bottom, 12)

            quoteBlock
                .padding(.bottom, 8)

            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.system(size: 10))
                Text(metaLine)
                    .font(.system(size: 10))
            }
            .foregroundStyle(Color.skTextFaint)
            .padding(.horizontal, 2)
            .padding(.bottom, 12)

            if rambleAdded {
                rambleReview
                    .padding(.bottom, 10)
                addMoreButton
                    .padding(.bottom, 9)
            } else {
                recordButton
                    .padding(.bottom, 9)
            }

            Button {
                onFinish(true)
            } label: {
                Text("Save & keep listening")
                    .font(.system(size: 13, weight: rambleAdded ? .bold : .semibold))
                    .foregroundStyle(rambleAdded ? .white : Color.skTextDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        rambleAdded ? Color.skAccent : .clear,
                        in: .rect(cornerRadius: 12, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle.sk(12)
                            .stroke(rambleAdded ? .clear : Color.skBorder, lineWidth: 1)
                    )
            }
            .accessibilityIdentifier("capture-save-keep-listening")
            .padding(.bottom, 12)

            SignificanceCircles(value: $significance) {
                commitSignificance()
            }
        }
        .padding(EdgeInsets(top: 11, leading: 16, bottom: 16, trailing: 16))
        .background(Color.skSurface, in: .rect(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle.sk(22).stroke(Color.skBorder, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.5), radius: 24, y: -6)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Text("❝")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(
                    LinearGradient(colors: [Color(hex: 0x8e7dff), Color(hex: 0x6a59ef)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 7, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("Capture")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.skText)
                Text(contextLine)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.skTextFaint)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                // Once a ramble exists, ✕ must not destroy it — close like
                // save, but WITHOUT resuming (only "Save & keep listening"
                // restarts the book).
                rambleAdded ? onFinish(false) : onDiscard()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.skTextDim)
                    .frame(width: 24, height: 24)
                    .background(Color.skElev, in: .circle)
            }
            .accessibilityIdentifier("capture-close")
            .accessibilityLabel(rambleAdded
                ? "Save and close — the book stays paused"
                : "Discard — resume the book")
        }
    }

    private var contextLine: String {
        var parts = [book.title]
        if let chapter = book.shortChapterLabel(at: output.spanStart) { parts.append(chapter) }
        parts.append(AudiobookTime.clock(output.spanStart) + " → " + AudiobookTime.clock(output.spanEnd))
        return parts.joined(separator: " · ")
    }

    private var quoteBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("“\(output.quote)”")
                .font(.system(size: 13.5))
                .italic()
                .lineSpacing(4)
                .foregroundStyle(Color.skText)
                .accessibilityIdentifier("capture-quote-text")

            // Plain preview — NO [[..]] on the phone (the Mac writes the
            // wikilink at export; authors never enter the names DB).
            attributionText
                .font(.system(size: 11.5))
                .accessibilityIdentifier("capture-attribution")
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.skAccent.opacity(0.05), in: .rect(cornerRadius: 11, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 11, bottomLeadingRadius: 11)
                .fill(Color.skAccent.opacity(0.6))
                .frame(width: 2.5)
        }
        .overlay(RoundedRectangle.sk(11).stroke(Color.skBorder, lineWidth: 0.5))
    }

    /// "— David Deutsch, *The Beginning of Infinity*, ch. 4" — book title in
    /// italics, author PLAIN (the wikilink is export-side, Mac-owned).
    private var attributionText: Text {
        let lead = Text("— \(book.author), ").foregroundStyle(Color.skTextDim)
        let title = Text(book.title).italic().foregroundStyle(Color.skTextDim)
        let tail = Text(chapterSuffix).foregroundStyle(Color.skTextDim)
        return lead + title + tail
    }

    private var chapterSuffix: String {
        if let n = book.chapterNumberString(at: output.spanStart) { return ", ch. \(n)" }
        return ""
    }

    private var metaLine: String {
        AudiobookTime.clock(output.duration)
            + " of book audio attached · transcribed on-device, snapped to sentences"
    }

    private var recordButton: some View {
        Button {
            showRamble = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "mic")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.18), in: .circle)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Record your thoughts")
                        .font(.system(size: 14.5, weight: .bold))
                    Text("the book stays paused while you talk — review, then resume")
                        .font(.system(size: 10.5))
                        .opacity(0.75)
                }
                .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16))
            .background(
                LinearGradient(colors: [Color(hex: 0x8e7dff), Color(hex: 0x6a59ef)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 14, style: .continuous)
            )
            .shadow(color: Color.skAccent.opacity(0.5), radius: 7, y: 2)
        }
        .accessibilityIdentifier("capture-record-thoughts")
    }

    // MARK: - Post-ramble state (thoughts saved — review + add more)

    /// The appended ramble, shown under the quote for review the moment its
    /// transcription lands (`memo` is a SwiftData `@Model`, so the text
    /// appears here as the append flow writes it).
    private var rambleReview: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.skGreen)
                Text("YOUR THOUGHTS — SAVED")
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(Color.skTextDim)
            }

            switch rambleState {
            case .transcribing:
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Transcribing what you said…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.skTextDim)
                }
            case .failed:
                Text("Transcription failed — the audio is saved on the memo and can be retried there.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.skAmber)
            case .noSpeech:
                Text("No speech was recognized — try Add more.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.skTextDim)
            case .text(let body):
                ScrollView(.vertical, showsIndicators: true) {
                    Text(body)
                        .font(.system(size: 12.5))
                        .lineSpacing(3)
                        .foregroundStyle(Color.skText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            }
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.skGreen.opacity(0.05), in: .rect(cornerRadius: 11, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 11, bottomLeadingRadius: 11)
                .fill(Color.skGreen.opacity(0.55))
                .frame(width: 2.5)
        }
        .overlay(RoundedRectangle.sk(11).stroke(Color.skBorder, lineWidth: 0.5))
        .accessibilityIdentifier("capture-ramble-review")
    }

    private enum RambleState {
        case transcribing
        case failed
        case noSpeech
        case text(String)
    }

    private var rambleState: RambleState {
        guard let memo else { return .transcribing }
        if memo.transcriptStatus == .transcribing { return .transcribing }
        if memo.transcriptStatus == .failed { return .failed }
        if let body = QuoteFormatting.rambleBody(transcript: memo.transcript ?? "") {
            return .text(body)
        }
        return .noSpeech
    }

    /// The modest follow-up affordance once a ramble landed — same verb, same
    /// accessibility id, no longer the screen-dominating purple block.
    private var addMoreButton: some View {
        Button {
            showRamble = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "mic")
                    .font(.system(size: 11, weight: .medium))
                Text("Add more")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(Color.skAccentText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .overlay(RoundedRectangle.sk(11).stroke(Color.skAccent.opacity(0.45), lineWidth: 1))
        }
        .accessibilityIdentifier("capture-record-thoughts")
        .accessibilityLabel("Add more thoughts — the book stays paused")
    }

    private func commitSignificance() {
        let repository = NotesRepository.shared
        guard let memo = repository.memo(id: memoID) else { return }
        memo.significance = significance
        repository.save()
    }
}
