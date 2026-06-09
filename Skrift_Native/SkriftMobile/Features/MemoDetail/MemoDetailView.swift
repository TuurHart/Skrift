import SwiftUI
import SwiftData
import UIKit

/// The "note" screen (mockup2). Swipe left/right between memos (a SwiftUI-native
/// horizontal paging `ScrollView` — NOT `TabView(.page)`, whose UIKit page host
/// broke `.glassEffect` refraction, the significance drag, and word tap-to-seek on
/// device), each page = editable title + RAW transcript (with inline `[[img_NNN]]`
/// embeds) + context/tags. A single playback bar is pinned at the bottom and
/// re-targets as you swipe. Title, tags, and the transcript are hand-editable
/// (save-now post-record flow); copy + delete live in the ⋯ menu.
struct MemoDetailView: View {
    let initialID: UUID

    @Query(sort: \Memo.recordedAt, order: .reverse) private var memos: [Memo]
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?   // bound to .scrollPosition(id:) — optional per the API
    @State private var showActions = false
    @State private var showAppendRecorder = false
    @StateObject private var player = AudioPlayerModel()
    private let repository = NotesRepository.shared

    init(initialID: UUID) {
        self.initialID = initialID
        _selection = State(initialValue: initialID)
    }

    private var currentMemo: Memo? { memos.first { $0.id == selection } }

    var body: some View {
        ScrollViewReader { proxy in
            // SwiftUI-native horizontal pager. `.scrollPosition(id:)` tracks the page;
            // the ScrollViewReader does the initial jump (the binding's initial value
            // isn't reliably honoured on first layout).
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(memos) { memo in
                        MemoPageView(memo: memo, player: player)
                            .containerRelativeFrame(.horizontal)
                            // The LazyHStack realises adjacent pages; hide the
                            // off-screen ones from VoiceOver (and XCUITest) so
                            // their controls/text aren't duplicate matches.
                            .accessibilityHidden(memo.id != selection)
                            .id(memo.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selection)
            .scrollIndicators(.hidden)
            .onAppear {
                guard let selection else { return }
                DispatchQueue.main.async { proxy.scrollTo(selection, anchor: .center) }
            }
        }
        .background(Color.skBg.ignoresSafeArea())
        // The floating glass player bar lives in the bottom safe-area inset, NOT a
        // ZStack overlay. That's the fix for "glass shows nothing": a detached overlay
        // only samples the flat background behind everything, so Liquid Glass had no
        // scroll content to refract. As a safeAreaInset the scroll content renders
        // BEHIND the bar in the same backdrop, so the transcript/photos genuinely
        // refract through the glass as they pass under it (and content insets to clear
        // it at rest).
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomChrome }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showActions = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(Color.skTextDim)
                }
                .accessibilityIdentifier("detail-menu")
            }
        }
        // A confirmationDialog is presented by the view controller (not anchored
        // to the toolbar item), so the paged TabView can't swallow it — unlike a
        // toolbar `Menu`, which silently failed to present on device.
        .confirmationDialog("Memo", isPresented: $showActions, titleVisibility: .hidden) {
            Button("Add recording", action: { showAppendRecorder = true })
            Button("Copy transcript", action: copyTranscript)
            // Retro "split speakers" — for a memo recorded without conversation mode.
            if let memo = currentMemo, !(memo.transcript ?? "").isEmpty, memo.audioURL != nil,
               SpeakerTranscript.parse(memo.transcript) == nil {
                Button("Split speakers") { Task { await MemoSaver().diarizeExisting(id: memo.id) } }
            }
            Button("Delete", role: .destructive, action: deleteCurrent)
            Button("Cancel", role: .cancel) {}
        }
        // Append a follow-up recording to the current memo (records → transcribes →
        // appends text + merges audio in MemoSaver.appendRecording). Transcript
        // updates in place via @Query when it lands.
        .fullScreenCover(isPresented: $showAppendRecorder) {
            RecordView(appendTo: selection)
        }
        .onAppear { player.load(currentMemo?.audioURL) }
        .onChange(of: selection) { _, newID in
            // Re-target the bar when paging settles; ignore the transient nil the
            // paging scroll reports between snap points (don't stop audio mid-swipe).
            guard let newID else { return }
            player.load(memos.first { $0.id == newID }?.audioURL)
        }
        .onDisappear { player.stopAndClear(); repository.save() }
    }

    @ViewBuilder private var bottomChrome: some View {
        // REAL iOS-26 Liquid Glass on the floating playback bar (device + SDK are 26):
        // the transcript/photos refract through it as they scroll under (the bar is a
        // safeAreaInset, so the scroll content is in the same backdrop). A
        // GlassEffectContainer gives the glass a proper shared sampling region.
        // `.ultraThinMaterial` is only the fallback for iOS < 26.
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                playerBarStack
                    // .clear (not .regular) = the lensed, refractive look — .regular
                    // reads as frosted. (Device must have full Liquid Glass on: Reduce
                    // Motion / Reduce Transparency OFF, Liquid Glass = Clear.)
                    .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    // A hairline + top specular highlight so the glass reads as an EDGE.
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.04)],
                                               startPoint: .top, endPoint: .bottom),
                                lineWidth: 0.8)
                    )
            }
            .padding(.horizontal, Theme.Space.margin)
            .padding(.bottom, 6)
        } else {
            playerBarStack
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.28), radius: 18, y: 6)
                .padding(.horizontal, Theme.Space.margin)
                .padding(.bottom, 6)
        }
    }

    private var playerBarStack: some View {
        VStack(spacing: 7) {
            if memos.count > 1, memos.count <= 8 {
                PageDots(count: memos.count, index: memos.firstIndex { $0.id == selection } ?? 0)
            }
            PlayerBar(player: player)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }

    private func copyTranscript() {
        guard let text = currentMemo?.transcript, !text.isEmpty else { return }
        UIPasteboard.general.string = text
    }

    private func deleteCurrent() {
        guard let memo = currentMemo else { return }
        let next = memos.first { $0.id != memo.id }?.id
        if let url = memo.audioURL { try? FileManager.default.removeItem(at: url) }
        memo.metadata?.imageManifest?.forEach {
            try? FileManager.default.removeItem(at: AppPaths.recordingsDirectory.appendingPathComponent($0.filename))
        }
        WordTimingsStore().delete(for: memo.id)
        player.stopAndClear()
        repository.delete(memo)
        if let next { selection = next } else { dismiss() }
    }
}

// MARK: - One page

private struct MemoPageView: View {
    @Bindable var memo: Memo
    @ObservedObject var player: AudioPlayerModel
    private let repository = NotesRepository.shared
    @State private var showAddTag = false
    @State private var newTag = ""
    @State private var namingSpeaker: String?       // the speaker label being (re)named
    @State private var speakerNameDraft = ""
    @ObservedObject private var diarStatus = DiarizationStatus.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TextField("", text: titleBinding, prompt: titlePrompt)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.skText)
                    .tint(.skAccent)
                    .submitLabel(.done)
                    .onSubmit { repository.save() }
                    .accessibilityIdentifier("detail-title")

                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(metaChips) { chip in
                        ContextChip(text: chip.text, systemImage: chip.symbol)
                    }
                    ForEach(memo.tags, id: \.self) { tag in
                        Button { removeTag(tag) } label: {
                            Text("#\(tag)")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.skAccentText)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Color.skAccentSoft, in: .rect(cornerRadius: 7, style: .continuous))
                        }
                    }
                    Button { showAddTag = true } label: {
                        Text("+ Tag")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.skTextDim)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.skElev, in: .rect(cornerRadius: 7, style: .continuous))
                    }
                    .accessibilityIdentifier("add-tag-button")
                }
                .padding(.top, 12)

                SignificanceRow(value: $memo.significance) { repository.save() }
                    .padding(.top, 10)

                if let label = diarStatus.label(for: memo.id) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.skTextDim)
                    }
                    .padding(.top, 14)
                    .accessibilityIdentifier("diarization-status")
                }

                transcriptSection
                    .padding(.top, 18)

                // Small breathing room; the bar's own height is reserved by the
                // parent's .safeAreaInset, so content rests just clear of the glass.
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, Theme.Space.margin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Add tag", isPresented: $showAddTag) {
            TextField("tag", text: $newTag)
            Button("Add", action: addTag)
            Button("Cancel", role: .cancel) { newTag = "" }
        }
        .alert("Name this speaker", isPresented: Binding(get: { namingSpeaker != nil },
                                                         set: { if !$0 { namingSpeaker = nil } })) {
            TextField("Name", text: $speakerNameDraft)
            Button("Set", action: renameSpeaker)
            Button("Cancel", role: .cancel) { namingSpeaker = nil }
        } message: {
            Text("Assign this speaker to a name. It links to a person on your Mac, and Skrift can learn the voice for next time.")
        }
    }

    /// Start (re)naming a speaker — prefill with the current name unless it's the
    /// "Speaker N" placeholder.
    private func startNaming(_ speaker: String) {
        speakerNameDraft = SpeakerTranscript.isUnnamed(speaker) ? "" : speaker
        namingSpeaker = speaker
    }

    /// Rewrite every `**old:**` turn prefix → `**new:**` (the speaker label is the key),
    /// so assigning/correcting one turn relabels all of that speaker's turns.
    private func renameSpeaker() {
        defer { namingSpeaker = nil; speakerNameDraft = "" }
        guard let old = namingSpeaker, let transcript = memo.transcript else { return }
        let new = speakerNameDraft.trimmingCharacters(in: .whitespaces)
        guard !new.isEmpty, new != old else { return }
        memo.transcript = transcript.replacingOccurrences(of: "**\(old):**", with: "**\(new):**")
        memo.transcriptUserEdited = true
        repository.save()
    }

    private var titleBinding: Binding<String> {
        Binding(get: { memo.title ?? "" }, set: { memo.title = $0.isEmpty ? nil : $0 })
    }

    private var titlePrompt: Text {
        // Strip a leading `**Speaker:** ` prefix so a conversation note's title prompt
        // shows the actual first words, not the Markdown.
        let line = (memo.firstTranscriptLine ?? "Add a title")
            .replacingOccurrences(of: #"^\*\*.+?:\*\*\s*"#, with: "", options: .regularExpression)
        return Text(line.isEmpty ? "Add a title" : line).foregroundStyle(Color.skTextFaint)
    }

    private func addTag() {
        let t = newTag.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        newTag = ""
        guard !t.isEmpty, !memo.tags.contains(t) else { return }
        memo.tags.append(t)
        repository.save()
    }

    private func removeTag(_ tag: String) {
        memo.tags.removeAll { $0 == tag }
        repository.save()
    }

    // MARK: - Transcript (always editable in place; karaoke on playback)

    /// No Edit button / no separate field. Paused → an inline, always-editable body
    /// (`TranscriptEditor` — keeps inline photos, writes back + flags
    /// `transcriptUserEdited` on every change). Playing → the read-only karaoke view
    /// (highlight + tap-to-seek). Transcribing → its status pill. The editor and the
    /// idle karaoke view render the same, so play/pause swaps seamlessly.
    @ViewBuilder private var transcriptSection: some View {
        if let turns = SpeakerTranscript.parse(memo.transcript) {
            // Conversation note → speaker-attributed turns; tap a speaker to assign or
            // correct the name (relabels all that speaker's turns).
            SpeakerTurnsView(turns: turns, onTag: startNaming)
        } else if player.isPlaying || memo.transcriptStatus == .transcribing {
            TranscriptContentView(memo: memo, player: player)
        } else {
            TranscriptEditor(memo: memo, onCommit: { repository.save() })
        }
    }

    private struct MetaChip: Identifiable { let id = UUID(); let text: String; let symbol: String? }

    private var metaChips: [MetaChip] {
        var chips: [MetaChip] = [MetaChip(text: MemoDate.label(memo.recordedAt), symbol: nil)]
        if let place = memo.metadata?.location?.placeName, !place.isEmpty {
            chips.append(MetaChip(text: place, symbol: "mappin.circle.fill"))
        }
        if let w = memo.metadata?.weather {
            chips.append(MetaChip(text: "\(w.temperature)°", symbol: "cloud.sun.fill"))
        }
        if let period = memo.metadata?.dayPeriod {
            chips.append(MetaChip(text: period.label, symbol: period.symbol))
        }
        return chips
    }
}

// MARK: - Significance (flag-to-send: 0 = stays on phone, > 0 = syncs to the Mac)

/// Mirrors the desktop review slider (0–1, snap 0.1, Passing/Useful/Significant) but
/// frames it around sync: at 0 the memo stays on the phone; any rating > 0 flags it
/// to upload (and the value rides along to pre-fill the Mac's own slider).
private struct SignificanceRow: View {
    @Binding var value: Double
    var onCommit: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Text("Significance")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.skTextFaint)
                .fixedSize()
            SignificanceSlider(value: $value, onCommit: onCommit)
            // Mirror the desktop slider's label: "0.7 · Significant" (Passing <0.34,
            // Useful <0.67, Significant). 0 = "Not rated" (desktop shows this for an
            // unrated note — and it's still the flag-to-send gate: 0 won't sync).
            Text(value > 0 ? String(format: "%.1f · %@", value, tier) : "Not rated")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(value > 0 ? Color.skAccent : Color.skTextFaint)
                .fixedSize()
        }
    }

    private var tier: String { value >= 0.67 ? "Significant" : value >= 0.34 ? "Useful" : "Passing" }
}

/// Custom 0–1 (snap 0.1) drag slider. A `minimumDistance: 0` `.highPriorityGesture`
/// claims the touch on contact, so the horizontal paging ScrollView can't steal the
/// drag (the old `TabView(.page)` page-pan did, which is why this was a tap-to-set
/// stopgap). A plain tap still works — a 0-distance drag fires `onChanged` on contact.
private struct SignificanceSlider: View {
    @Binding var value: Double
    var onCommit: () -> Void
    /// Live drag position, local only. Writing `value` (→ memo.significance) on every
    /// drag tick re-ran the detail `@Query` and re-rendered the page each frame, which
    /// is what made the slider lag. Track the drag here and commit to the model once,
    /// on release.
    @State private var dragging: Double?

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let shown = CGFloat(dragging ?? value)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.skBorder).frame(height: 4)
                Capsule().fill(Color.skAccent).frame(width: max(0, min(w, w * shown)), height: 4)
                Circle().fill(.white)
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .offset(x: max(0, min(w - 20, w * shown - 10)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let frac = max(0, min(1, g.location.x / w))
                        dragging = (Double(frac) * 10).rounded() / 10
                    }
                    .onEnded { _ in
                        if let d = dragging { value = d; onCommit() }
                        dragging = nil
                    }
            )
        }
        .frame(height: 24)
        .accessibilityIdentifier("significance-slider")
    }
}

// MARK: - Transcript (RAW + inline image markers)

private struct TranscriptContentView: View {
    let memo: Memo
    @ObservedObject var player: AudioPlayerModel
    @State private var timings: [WordTiming] = []
    @AppStorage("karaokeTapToSeek") private var tapToSeek = false

    /// Active spoken-word index during playback (nil when paused / no timings) — the
    /// transcript highlights that word. Word-accurate via the on-device timings.
    private var activeWord: Int? {
        guard player.isPlaying, !timings.isEmpty else { return nil }
        return Karaoke.activeWordIndex(timings, at: player.currentTime)
    }

    var body: some View {
        if memo.transcriptStatus == .failed, (memo.transcript ?? "").isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                StatusPill(style: .error, label: "Transcription failed", systemImage: "exclamationmark.triangle.fill")
                Text("It'll be transcribed on your Mac when you sync — or tap Edit to type it yourself.")
                    .font(.footnote).foregroundStyle(Color.skTextDim)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // Show the pill whenever transcribing so the state is visible.
                if memo.transcriptStatus == .transcribing {
                    StatusPill(style: .working, label: "Transcribing")
                }
                let active = activeWord
                ForEach(Array(segmentsWithOffsets.enumerated()), id: \.offset) { _, item in
                    switch item.seg {
                    case .text(let s):
                        if tapToSeek {
                            karaokeWords(s, wordOffset: item.wordOffset, active: active)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            karaokeText(s, wordOffset: item.wordOffset, active: active)
                                .font(.system(size: 15.5))
                                .lineSpacing(4)
                                .foregroundStyle(Color.skText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    case .image(let n):
                        ImageEmbed(url: imageURL(markerIndex: n))
                    }
                }
            }
            .task(id: memo.id) { timings = WordTimingsStore().load(for: memo.id) ?? [] }
        }
    }

    /// Each segment paired with the count of spoken words before it, so karaoke maps
    /// the global active-word index into the right segment (image markers aren't words).
    private var segmentsWithOffsets: [(seg: Segment, wordOffset: Int)] {
        var offset = 0
        var out: [(seg: Segment, wordOffset: Int)] = []
        for seg in segments {
            out.append((seg: seg, wordOffset: offset))
            if case .text(let s) = seg { offset += s.split(whereSeparator: { $0.isWhitespace }).count }
        }
        return out
    }

    /// Render a text segment, highlighting the active word (accent + semibold) via an
    /// AttributedString. The word index advances per whitespace-delimited run so it
    /// aligns with the on-device word timings; whitespace/newlines are preserved.
    private func karaokeText(_ text: String, wordOffset: Int, active: Int?) -> Text {
        guard let active else { return Text(text) }   // not playing → plain text
        var attr = AttributedString()
        var wordIndex = wordOffset
        var buffer = ""
        func flush() {
            guard !buffer.isEmpty else { return }
            var piece = AttributedString(buffer)
            // Played words dim, the current word accents, upcoming stay default — so a
            // glance shows where playback is (matches desktop). NO weight change: bold
            // widened the word and made the next one jump, so colour only.
            if wordIndex < active { piece.foregroundColor = .skTextDim }
            else if wordIndex == active { piece.foregroundColor = .skAccent }
            attr += piece
            wordIndex += 1
            buffer = ""
        }
        for ch in text {
            if ch.isWhitespace { flush(); attr += AttributedString(String(ch)) }
            else { buffer.append(ch) }
        }
        flush()
        return Text(attr)
    }

    /// Tap-to-seek mode: each word is its own tappable view (a flowing wrap), so a
    /// tap jumps playback to that word. Same grey-out colouring. Opt-in (Settings)
    /// since per-word views lose exact paragraph spacing vs the AttributedString.
    @ViewBuilder private func karaokeWords(_ text: String, wordOffset: Int, active: Int?) -> some View {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        FlowLayout(spacing: 5, lineSpacing: 6) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                let gi = wordOffset + i
                Text(word)
                    .font(.system(size: 15.5))
                    .foregroundStyle(active.map { gi < $0 ? Color.skTextDim : (gi == $0 ? Color.skAccent : Color.skText) } ?? Color.skText)
                    .contentShape(Rectangle())
                    .onTapGesture { seekToWord(gi) }
            }
        }
    }

    private func seekToWord(_ i: Int) {
        guard i >= 0, i < timings.count else { return }
        player.seek(to: timings[i].start)
        if !player.isPlaying { player.play() }
    }

    private enum Segment { case text(String); case image(Int) }

    private var segments: [Segment] {
        guard let text = memo.transcript, !text.isEmpty else { return [] }
        var result: [Segment] = []
        let ns = text as NSString
        let regex = try? NSRegularExpression(pattern: #"\[\[img_(\d+)\]\]"#)
        var last = 0
        regex?.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            if match.range.location > last {
                let chunk = ns.substring(with: NSRange(location: last, length: match.range.location - last))
                if !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.text(chunk.trimmingCharacters(in: .whitespacesAndNewlines))) }
            }
            let num = Int(ns.substring(with: match.range(at: 1))) ?? 0
            result.append(.image(num))
            last = match.range.location + match.range.length
        }
        if last < ns.length {
            let tail = ns.substring(from: last)
            if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.text(tail.trimmingCharacters(in: .whitespacesAndNewlines))) }
        }
        return result.isEmpty ? [.text(text)] : result
    }

    private func imageURL(markerIndex: Int) -> URL? {
        guard let manifest = memo.metadata?.imageManifest, markerIndex >= 1, markerIndex <= manifest.count else { return nil }
        return AppPaths.recordingsDirectory.appendingPathComponent(manifest[markerIndex - 1].filename)
    }
}

/// An inline photo from the transcript markers; placeholder if the file is gone
/// (e.g. seeded demo memos).
private struct ImageEmbed: View {
    let url: URL?

    var body: some View {
        Group {
            if let url, let image = MemoImageLoader.thumbnail(at: url, maxWidth: UIScreen.main.bounds.width) {
                Image(uiImage: image)
                    .resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(hex: 0x2b3350), Color(hex: 0x161a29)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Image(systemName: "photo").font(.title).foregroundStyle(Color.skTextFaint))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle.sk(14).stroke(Color.skBorder, lineWidth: 1))
    }
}

// MARK: - Player bar

private struct PlayerBar: View {
    @ObservedObject var player: AudioPlayerModel

    var body: some View {
        VStack(spacing: 6) {
            Slider(value: Binding(
                get: { player.currentTime },
                set: { player.seek(to: $0) }
            ), in: 0...max(player.duration, 0.01))
            .tint(.skAccent)
            .disabled(!player.hasAudio)

            HStack {
                Text(timeString(player.currentTime))
                Spacer()
                Text(timeString(player.duration))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.skTextDim)

            HStack(spacing: 34) {
                Button { player.skip(-10) } label: {
                    skipLabel("gobackward.10")
                }
                .accessibilityIdentifier("skip-back-button")

                Button { player.togglePlay() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Color.skAccent, in: .circle)
                        .shadow(color: .skAccent.opacity(0.4), radius: 7, y: 4)
                }
                .accessibilityIdentifier("play-button")
                .disabled(!player.hasAudio)

                Button { player.skip(10) } label: {
                    skipLabel("goforward.10")
                }
                .accessibilityIdentifier("skip-fwd-button")
            }
            .foregroundStyle(Color.skText)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                Button { player.cycleRate() } label: {
                    Text(rateLabel)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.skText)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Color.skSurface, in: .rect(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle.sk(9).stroke(Color.skBorder, lineWidth: 1))
                }
                .accessibilityIdentifier("speed-button")
            }
        }
    }

    private func skipLabel(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 21))
    }

    private var rateLabel: String {
        player.rate == 1 ? "1×" : (player.rate == 1.5 ? "1.5×" : "2×")
    }

    private func timeString(_ t: TimeInterval) -> String {
        guard t.isFinite else { return "0:00" }
        let total = Int(t)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Page dots

private struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Color.skAccent : Color.skTextFaint)
                    .frame(width: i == index ? 18 : 6, height: 6)
            }
        }
        .animation(Theme.Motion.snappy, value: index)
    }
}
