import SwiftUI
import SwiftData
import UIKit
import FluidAudio

/// The "note" screen (mockup2). Swipe left/right between memos (a SwiftUI-native
/// horizontal paging `ScrollView` — NOT `TabView(.page)`, whose UIKit page host
/// broke `.glassEffect` refraction, the significance drag, and word tap-to-seek on
/// device), each page = editable title + RAW transcript (with inline `[[img_NNN]]`
/// embeds) + context/tags. A single playback bar is pinned at the bottom and
/// re-targets as you swipe. Title, tags, and the transcript are hand-editable
/// (save-now post-record flow); copy + delete live in the ⋯ menu.
struct MemoDetailView: View {
    let initialID: UUID

    // Trashed memos (deletedAt != nil) are excluded so a soft-deleted memo
    // drops out of the pager immediately (same filter as MemosListView).
    @Query(filter: #Predicate<Memo> { $0.deletedAt == nil },
           sort: \Memo.recordedAt, order: .reverse) private var memos: [Memo]
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?   // bound to .scrollPosition(id:) — optional per the API
    @State private var showActions = false
    @State private var showSplitOptions = false
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
            // Add a follow-up recording to this memo — a visible top-right affordance
            // (the same action also lives in the ⋯ menu). Records → transcribes →
            // appends text + merges audio in MemoSaver.appendRecording.
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAppendRecorder = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(Color.skTextDim)
                }
                .accessibilityIdentifier("add-recording-button")
                .accessibilityLabel("Add recording")
            }
            // Split into speakers — a deliberate post-transcript action (no pre-record
            // toggle). Shown once there's a transcript + audio to diarize.
            ToolbarItem(placement: .topBarTrailing) {
                if let memo = currentMemo, !(memo.transcript ?? "").isEmpty, memo.audioURL != nil {
                    Button { showSplitOptions = true } label: {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .foregroundStyle(Color.skTextDim)
                    }
                    .accessibilityIdentifier("split-speakers-button")
                }
            }
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
        // "How many speakers?" — Auto trusts the diarizer; a number forces exactly that
        // count by merging the most voice-similar slots (the over-segmentation fix).
        .confirmationDialog("How many speakers?", isPresented: $showSplitOptions, titleVisibility: .visible) {
            Button("Auto") { splitSpeakers(nil) }
            ForEach([2, 3, 4, 5], id: \.self) { n in
                Button("\(n) speakers") { splitSpeakers(n) }
            }
            Button("Cancel", role: .cancel) {}
        }
        // A confirmationDialog is presented by the view controller (not anchored
        // to the toolbar item), so the paged TabView can't swallow it — unlike a
        // toolbar `Menu`, which silently failed to present on device.
        .confirmationDialog("Memo", isPresented: $showActions, titleVisibility: .hidden) {
            Button("Add recording", action: { showAppendRecorder = true })
            Button("Copy transcript", action: copyTranscript)
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

    /// Split the current memo into speakers (Auto, or force `count`). Re-runs diarization
    /// over the saved audio + word-timings; the model loads on first use here (the slow
    /// step now happens only when you ask, not after every recording).
    private func splitSpeakers(_ count: Int?) {
        guard let id = currentMemo?.id else { return }
        Task { await MemoSaver().diarizeExisting(id: id, targetSpeakers: count) }
    }

    /// Soft-delete: move the memo to Recently Deleted, same as every list delete
    /// path (MemosListView.deleteMemo). Audio, photos, and sidecars stay on disk
    /// so Restore is lossless; the startup purge removes them after the retention
    /// window. The pager's @Query excludes trashed memos, so the page disappears
    /// and we move to the next one (or dismiss when it was the last).
    private func deleteCurrent() {
        guard let memo = currentMemo else { return }
        let next = memos.first { $0.id != memo.id }?.id
        player.stopAndClear()
        repository.softDelete(memo)
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
    @State private var assignTarget: AssignTarget?   // the tapped turn (index + speaker) → assign sheet

    /// A tapped speaker turn: its position (for per-line merge) + label (for whole-speaker naming).
    struct AssignTarget: Identifiable { let id = UUID(); let index: Int; let speaker: String }
    @ObservedObject private var diarStatus = DiarizationStatus.shared
    @State private var timings: [WordTiming] = []   // for karaoke highlight in the turn view
    @AppStorage("karaokeTapToSeek") private var tapToSeek = false

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

                // The 10-circle significance control (SignificanceCircles.swift —
                // mocks/significance-circles.html): tap circle N → 0.N, re-tap →
                // Not rated. Flag-to-send: 0 stays on the phone, >0 syncs, 0.8+
                // is past the refine wall.
                SignificanceCircles(value: $memo.significance) { repository.save() }
                    .padding(.top, 14)

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
        // Dragging the page itself dismisses the keyboard (the inner TranscriptEditor
        // already has its own interactive dismiss; this covers scrolling the OUTER
        // page when the title/transcript field has focus).
        .scrollDismissesKeyboard(.interactively)
        .task(id: memo.id) { timings = WordTimingsStore().load(for: memo.id) ?? [] }
        .alert("Add tag", isPresented: $showAddTag) {
            TextField("tag", text: $newTag)
            Button("Add", action: addTag)
            Button("Cancel", role: .cancel) { newTag = "" }
        }
        // Tap a speaker → an assign sheet: pick a known Person (links + enrolls the
        // voiceprint), merge into another speaker in this convo (fixes a mis-split), or
        // type a new name. Replaces the old free-text alert.
        .sheet(item: $assignTarget) { target in
            SpeakerAssignSheet(
                speaker: target.speaker,
                otherSpeakers: SpeakerTranscript.speakers(in: memo.transcript).filter { $0 != target.speaker },
                people: NamesStore.shared.livePeople(),
                onAssignPerson: { assign(target.speaker, to: NamesDisplay.name($0), enroll: true) },
                onMergeInto: { mergeTurn(at: target.index, into: $0) },
                onNewName: { assign(target.speaker, to: $0, enroll: true) }
            )
        }
    }

    private func startAssigning(_ index: Int, _ speaker: String) {
        assignTarget = AssignTarget(index: index, speaker: speaker)
    }

    /// Merge ONLY the tapped turn into another speaker (per-line) + re-fuse — fixes a
    /// mis-split line without collapsing the whole speaker. No enrollment (not a naming).
    private func mergeTurn(at index: Int, into other: String) {
        guard let updated = SpeakerTranscript.reassign(memo.transcript, turnAt: index, to: other) else { return }
        memo.transcript = updated
        memo.transcriptUserEdited = true
        repository.save()
    }

    /// Commit an inline edit to one turn's text (fix a word, move a boundary word).
    private func editTurnText(at index: Int, to newText: String) {
        guard let updated = SpeakerTranscript.setText(memo.transcript, turnAt: index, to: newText),
              updated != memo.transcript else { return }
        memo.transcript = updated
        memo.transcriptUserEdited = true       // Mac trusts the edited transcript
        repository.save()
    }

    /// Resolve a turn's `[[img_NNN]]` marker (1-based) → its photo file (same mapping as
    /// the non-conversation transcript). Lets photos render inline within speaker turns.
    private func turnImageURL(_ n: Int) -> URL? {
        guard let manifest = memo.metadata?.imageManifest, n >= 1, n <= manifest.count else { return nil }
        return AppPaths.recordingsDirectory.appendingPathComponent(manifest[n - 1].filename)
    }

    /// Karaoke tap-to-seek: jump playback to the tapped word.
    private func seekToWord(_ i: Int) {
        guard i >= 0, i < timings.count else { return }
        player.seek(to: timings[i].start)
        if !player.isPlaying { player.play() }
    }

    /// Apply a speaker assignment: relabel every `**old:**` turn → `**new:**`, re-fuse
    /// adjacent same-speaker turns (so a merged blip folds into its neighbour), and — when
    /// assigning to a real person (not merging into another Speaker N) — learn the
    /// voiceprint under `new` so future recordings auto-label them (syncs → "Voice enrolled").
    private func assign(_ old: String, to newName: String, enroll: Bool) {
        let new = newName.trimmingCharacters(in: .whitespaces)
        guard let transcript = memo.transcript, !new.isEmpty, new != old else { return }
        let relabeled = transcript.replacingOccurrences(of: "**\(old):**", with: "**\(new):**")
        memo.transcript = SpeakerTranscript.mergeAdjacentTurns(relabeled)
        memo.transcriptUserEdited = true
        repository.save()
        if enroll {
            Task { await Self.learnVoice(memoID: memo.id, audioURL: memo.audioURL, old: old, new: new) }
        }
    }

    /// Extract `old`'s audio from the diar sidecar, embed it, and store the voiceprint
    /// under `new`. `static` so it isn't tied to the transient (paged) view's lifetime.
    private static func learnVoice(memoID: UUID, audioURL: URL?, old: String, new: String) async {
        guard let audioURL, let data = DiarizationStore().load(for: memoID),
              let slotStr = data.slotNames.first(where: { $0.value == old })?.key,
              let slot = Int(slotStr) else { return }
        // Keep the sidecar's slot name current so a later re-enroll finds this slot.
        var updated = data; updated.slotNames[slotStr] = new
        DiarizationStore().write(updated, for: memoID)

        await MainActor.run { DiarizationStatus.shared.begin(memoID, phase: .enrolling) }
        defer { Task { @MainActor in DiarizationStatus.shared.finish() } }

        guard let samples = try? AudioConverter(sampleRate: 16000).resampleAudioFile(audioURL) else { return }
        let clip = DiarizationService.clip(data.segments.filter { $0.speaker == slot }, from: samples)
        await VoiceEnroller.enroll(name: new, clip: clip, using: EmbedderFactory.make())
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
            // Conversation note → speaker-attributed turns. Tap the NAME to assign/merge;
            // paused → tap the TEXT to edit it (fix a word, move a boundary word); playing
            // → karaoke highlight (+ tap-to-seek) like the rest of the app.
            SpeakerTurnsView(
                turns: turns,
                onTag: startAssigning(_:_:),
                activeWord: (player.isPlaying && !timings.isEmpty) ? Karaoke.activeWordIndex(timings, at: player.currentTime) : nil,
                tapToSeek: tapToSeek,
                onSeek: seekToWord,
                onEditText: editTurnText,
                imageURL: turnImageURL
            )
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
struct ImageEmbed: View {
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
