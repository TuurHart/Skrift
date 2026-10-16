import AVFoundation
import SwiftUI

/// What opens the comment sheet: one highlight, read first (it has a comment) or written straight away.
struct HighlightCommentRequest: Identifiable {
    let id = UUID()
    let highlightID: UUID
    let editing: Bool
}

/// Q463 (Q462 mock steps 2 and 5, D214): the comment on one PDF highlight. Reading it shows the
/// words, the spoken clip if there is one, Edit, Delete comment and Remove highlight. Writing it is
/// a plain text field under a hairline (no box) plus a mic: the recorder and the on-device
/// transcriber the capture voice note uses (`LiveRecordingService` + `TranscriberFactory`), the
/// transcript lands in the text, and the audio is kept on the highlight. Nothing leaves the phone.
struct HighlightCommentSheet: View {
    let book: Audiobook
    let highlightID: UUID
    /// Remove highlight: the reader asks first when a comment would go with it.
    let onRemove: (UUID) -> Void
    let onFinish: () -> Void

    @State private var editing: Bool
    @State private var draft = ""
    /// A clip recorded in this sheet, not yet saved (deleted on Cancel).
    @State private var pendingClip: URL?
    @State private var service = LiveRecordingService()
    @State private var transcribing = false
    @State private var noWordsHeard = false
    @State private var micUnavailable = false
    @StateObject private var player = CommentClipPlayer()
    @FocusState private var focused: Bool

    private var store: AudiobookLibraryStore { .shared }

    init(book: Audiobook, highlightID: UUID, editing: Bool, onRemove: @escaping (UUID) -> Void,
         onFinish: @escaping () -> Void) {
        self.book = book
        self.highlightID = highlightID
        self.onRemove = onRemove
        self.onFinish = onFinish
        _editing = State(initialValue: editing)
    }

    private var highlight: SourceHighlight? { LibraryHighlights.highlight(highlightID, bookID: book.id, store: store) }
    private var pageLabel: String { highlight?.page.map { "p. \($0)" } ?? "" }

    /// The clip to play: the one just recorded, else the saved one.
    private var clipURL: URL? {
        if let pendingClip { return pendingClip }
        guard let name = highlight?.commentAudio else { return nil }
        let url = LibraryHighlights.commentAudioURL(name, bookID: book.id, store: store)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if editing { writeBody } else { readBody }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 20)
        .background(Color.skSurface.ignoresSafeArea())
        .onAppear {
            draft = highlight?.comment ?? ""
            if editing { focused = draft.isEmpty }
        }
        .onDisappear { player.stop() }
        .onChange(of: service.writeFailure) { _, failure in
            if failure != nil, service.isRecording { stopRecording() }
        }
        .accessibilityIdentifier("library-pdf-comment-sheet")
    }

    // MARK: - Reading the comment (mock step 5)

    private var readBody: some View {
        Group {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Comment").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.skText)
                    Text(editedLine).font(.system(size: 11)).foregroundStyle(Color.skTextFaint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                textButton("Edit", id: "library-pdf-comment-edit") {
                    draft = highlight?.comment ?? ""
                    editing = true
                }
            }
            quote
            if let text = highlight?.commentText {
                Text(text)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.skText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("library-pdf-comment-text")
            }
            if let url = clipURL { clipRow(url) }
            hairline
            HStack {
                textButton("Delete comment", color: .skRed, id: "library-pdf-comment-delete") { deleteComment() }
                Spacer()
                textButton(SourceMenu.removeHighlight, color: .skTextDim, weight: .medium,
                           id: "library-pdf-comment-remove-highlight") {
                    onRemove(highlightID)
                }
            }
        }
    }

    private var editedLine: String {
        guard let when = highlight?.commentedAt else { return pageLabel }
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .medium
        f.timeStyle = .short
        return "\(pageLabel) \u{00B7} edited \(f.string(from: when).lowercased())"
    }

    // MARK: - Writing it (mock step 2, D214: typed or spoken)

    private var writeBody: some View {
        Group {
            HStack(alignment: .center, spacing: 10) {
                textButton("Cancel", color: .skTextDim, weight: .medium, id: "library-pdf-comment-cancel") { cancel() }
                VStack(spacing: 1) {
                    Text("Comment").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.skText)
                    Text("\(pageLabel) \u{00B7} goes into the PDF")
                        .font(.system(size: 11)).foregroundStyle(Color.skTextFaint)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity)
                textButton("Save", id: "library-pdf-comment-save") { save() }
                    .disabled(service.isRecording || transcribing)
            }
            quote
            hairline
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("Your comment on this highlight")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.skTextFaint)
                        .padding(.top, 8).padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draft)
                    .focused($focused)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.skText)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 96, maxHeight: 220)
                    .accessibilityIdentifier("library-pdf-comment-field")
            }
            voiceRow
            if highlight?.hasComment == true {
                textButton("Delete comment", color: .skRed, id: "library-pdf-comment-delete") { deleteComment() }
            }
        }
    }

    /// The mic: idle → recording (live caption, stop) → transcribing → the words in the field.
    @ViewBuilder private var voiceRow: some View {
        if service.isRecording {
            HStack(spacing: 9) {
                Circle().fill(Color.red).frame(width: 9, height: 9)
                Text(clock(service.elapsed))
                    .font(.system(size: 12.5).monospacedDigit())
                    .foregroundStyle(Color.skTextDim)
                Text(service.liveCaption.isEmpty ? "Listening\u{2026}" : service.liveCaption)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.skTextDim)
                    .lineLimit(1).truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { stopRecording() } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.red)
                        .frame(width: 32, height: 32)
                        .background(Color.red.opacity(0.16), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop recording")
                .accessibilityIdentifier("library-pdf-comment-stop")
            }
        } else if transcribing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Transcribing on this iPhone\u{2026}").font(.system(size: 13)).foregroundStyle(Color.skTextDim)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Button { startRecording() } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "mic.fill").font(.system(size: 13, weight: .semibold))
                            Text(clipURL == nil ? "Speak a comment" : "Speak it again")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(Color.skAccentText)
                        .frame(minHeight: 38)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library-pdf-comment-mic")
                    if let url = clipURL { clipRow(url) }
                }
                if noWordsHeard {
                    Text("\(VoiceAnnotationOutcome.noWordsHeardLine). The recording is kept with the comment.")
                        .font(.system(size: 12)).foregroundStyle(Color.skTextDim)
                        .accessibilityIdentifier("library-pdf-comment-no-words")
                }
                if micUnavailable {
                    Text("The microphone isn't available right now")
                        .font(.system(size: 11)).foregroundStyle(Color.skTextFaint)
                }
            }
        }
    }

    private func clipRow(_ url: URL) -> some View {
        Button { player.toggle(url) } label: {
            HStack(spacing: 6) {
                Image(systemName: player.playing ? "pause.fill" : "play.fill").font(.system(size: 11, weight: .semibold))
                Text(player.playing ? "Playing" : "Spoken comment \u{00B7} \(clock(CommentClipPlayer.duration(of: url)))")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Color.skTextDim)
            .frame(minHeight: 38)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library-pdf-comment-play")
    }

    // MARK: - Pieces

    /// The highlighted words in the quote idiom, with the highlight's yellow bar.
    private var quote: some View {
        Text(highlight?.text ?? "")
            .font(.system(size: 15).italic())
            .foregroundStyle(Color.skText.opacity(0.78))
            .lineLimit(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 14)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xe0a800)).frame(width: 3)
            }
    }

    private var hairline: some View { Rectangle().fill(Color.skBorder).frame(height: 0.5) }

    private func textButton(_ title: String, color: Color = .skAccentText, weight: Font.Weight = .semibold,
                            id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: weight)).foregroundStyle(color)
                .padding(.vertical, 8).padding(.horizontal, 2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func clock(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - Actions

    private func save() {
        var audio = highlight?.commentAudio
        if let clip = pendingClip,
           let name = LibraryHighlights.adoptCommentAudio(clip, highlightID: highlightID, bookID: book.id, store: store) {
            audio = name
        }
        pendingClip = nil
        LibraryHighlights.setComment(draft, audio: audio, on: highlightID, bookID: book.id, store: store)
        Haptics.success()
        onFinish()
    }

    private func cancel() {
        if service.isRecording { _ = service.stop() }
        discardPending()
        onFinish()
    }

    private func deleteComment() {
        discardPending()
        LibraryHighlights.setComment(nil, audio: nil, on: highlightID, bookID: book.id, store: store)
        onFinish()
    }

    private func discardPending() {
        player.stop()
        if let clip = pendingClip { try? FileManager.default.removeItem(at: clip) }
        pendingClip = nil
    }

    private func startRecording() {
        // The main recorder owns the session when it is live.
        guard !LiveRecordingService.isRecordingActive else { micUnavailable = true; return }
        player.stop()
        micUnavailable = false
        noWordsHeard = false
        focused = false
        Haptics.tap()
        do { try service.start() } catch { micUnavailable = true }
    }

    private func stopRecording() {
        Haptics.recordingTap()
        guard let result = service.stop() else { return }
        guard result.duration >= 0.4, result.refusal == nil else {
            try? FileManager.default.removeItem(at: result.url)
            if result.refusal != nil { micUnavailable = true }
            return
        }
        transcribing = true
        Task { @MainActor in
            // The full on-device pass over the clip; the live caption is the fallback.
            let full = try? await TranscriberFactory.make().transcribe(audioURL: result.url, imageManifest: []).text
            let outcome = VoiceAnnotationOutcome.resolve(live: result.liveCaption, full: full)
            if case .append(let text) = outcome {
                let base = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                draft = base.isEmpty ? text : base + "\n\n" + text
            }
            noWordsHeard = !outcome.deletesClip
            // The newest clip is the one kept on the highlight; an unsaved older one goes.
            if let old = pendingClip { try? FileManager.default.removeItem(at: old) }
            pendingClip = result.url
            transcribing = false
            if outcome.firesSuccessHaptic { Haptics.success() }
        }
    }
}

/// Plays a spoken comment's clip.
@MainActor
final class CommentClipPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playing = false
    private var player: AVAudioPlayer?

    func toggle(_ url: URL) {
        if playing { stop(); return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        playing = player?.play() ?? false
    }

    func stop() {
        player?.stop()
        player = nil
        playing = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playing = false }
    }

    static func duration(of url: URL) -> TimeInterval {
        (try? AVAudioPlayer(contentsOf: url))?.duration ?? 0
    }
}
