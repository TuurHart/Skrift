import SwiftUI
import SwiftData
import UIKit
import QuickLook
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
        // Playback bar is only meaningful when there's audio. Capture items
        // (audioURL == nil) have no audio — hide the bar entirely so the
        // scroll content isn't needlessly padded.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if currentMemo?.isShareCapture != true {
                bottomChrome
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Add a follow-up recording — hidden for C3 capture items (no audio to append to).
            ToolbarItem(placement: .topBarTrailing) {
                if currentMemo?.isShareCapture != true {
                    Button { showAppendRecorder = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .foregroundStyle(Color.skTextDim)
                    }
                    .accessibilityIdentifier("add-recording-button")
                    .accessibilityLabel("Add recording")
                }
            }
            // Split into speakers — hidden for captures (no audio, no diarization).
            ToolbarItem(placement: .topBarTrailing) {
                if let memo = currentMemo, !(memo.transcript ?? "").isEmpty,
                   memo.audioURL != nil, !memo.isShareCapture {
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
        // A VIDEO import inserts the memo and opens this screen BEFORE its audio
        // has been extracted (extraction is async), so the initial load() hit a
        // file that didn't exist yet and left the player with no audio — tapping
        // Play then did nothing. When extraction lands (the duration fills in, then
        // transcription finishes) reload so Play works. Guarded on !hasAudio so a
        // normal append — which also moves the duration — never interrupts playback.
        .onChange(of: currentMemo?.duration) { _, _ in reloadIfAudioMissing() }
        .onChange(of: currentMemo?.transcriptStatus) { _, _ in reloadIfAudioMissing() }
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

    /// Re-point the player at the current memo's audio if an earlier `load()` failed
    /// because the file wasn't on disk yet (the async video-import extraction case).
    /// A no-op once audio is loaded, so it never disturbs active playback.
    private func reloadIfAudioMissing() {
        guard !player.hasAudio else { return }
        player.load(currentMemo?.audioURL)
    }

    /// Split the current memo into speakers (Auto, or force `count`). Re-runs diarization
    /// over the saved audio + word-timings; the model loads on first use here (the slow
    /// step now happens only when you ask, not after every recording).
    private func splitSpeakers(_ count: Int?) {
        guard let id = currentMemo?.id else { return }
        // Keep the diarization alive if the user backgrounds the app mid-identify
        // (they often do — it can take a while). If iOS suspends/kills it anyway, the
        // launch sweep recoverStuckDiarizations re-runs it (2026-06-21 "I switched out
        // of the app and then I think it stopped").
        Task {
            await BackgroundTask.run(name: "diarize") {
                await MemoSaver().diarizeExisting(id: id, targetSpeakers: count)
            }
        }
    }

    /// Soft-delete: move the memo to Recently Deleted, same as every list delete
    /// path (MemosListView.deleteMemo). Audio, photos, and sidecars stay on disk
    /// so Restore is lossless; the startup purge removes them after the retention
    /// window. The pager's @Query excludes trashed memos, so the page disappears
    /// and we move to the next one (or dismiss when it was the last).
    private func deleteCurrent() {
        guard let memo = currentMemo,
              let idx = memos.firstIndex(where: { $0.id == memo.id }) else { return }
        // Land on the ADJACENT page after delete — the next memo, else the previous
        // — not the top of the list. Dismiss when it was the only one.
        let neighbor: UUID?
        if idx + 1 < memos.count { neighbor = memos[idx + 1].id }
        else if idx - 1 >= 0 { neighbor = memos[idx - 1].id }
        else { neighbor = nil }
        player.stopAndClear()
        repository.softDelete(memo)
        if let neighbor { selection = neighbor } else { dismiss() }
    }
}

// MARK: - One page

private struct MemoPageView: View {
    @Bindable var memo: Memo
    @ObservedObject var player: AudioPlayerModel
    private let repository = NotesRepository.shared
    @State private var showAddTag = false
    @State private var newTag = ""
    @State private var quickLookURL: URL?            // shared-document (.file) capture → QuickLook preview
    @State private var assignTarget: AssignTarget?   // the tapped turn (index + speaker) → assign sheet

    /// A tapped speaker turn: its position (for per-line merge), label (for whole-speaker
    /// naming), the diarization slot (so a same-named twin isn't relabeled/enrolled too),
    /// and the per-turn slot map it was validated against. Both are resolved by reading the
    /// diar sidecar FRESH at tap time (not a cached copy) so an in-place re-diarize ("Split
    /// speakers", which renumbers slots under the same memo id) can't leave a stale map.
    struct AssignTarget: Identifiable {
        let id = UUID(); let index: Int; let speaker: String; let slot: Int?; let turnSlots: [Int]
    }
    @ObservedObject private var diarStatus = DiarizationStatus.shared
    @State private var timings: [WordTiming] = []   // for karaoke highlight in the turn view
    @AppStorage("karaokeTapToSeek") private var tapToSeek = true   // default ON — must match TranscriptBodyView

    // Name-linking (mocks/phone-name-linking.html): the live names roster, the tapped
    // span's resolve sheet, the unlink-undo toast, and the person-card / new-person editor.
    @State private var people: [Person] = []
    @State private var resolveTarget: NameResolveTarget?
    @State private var undoToast: NameUndoToast?
    @State private var personSheet: PersonSheetRequest?
    @State private var showPeopleSheet = false
    // Phase 4 — the Mac's polish (CloudKit write-back), shown as the editable body.
    @State private var enhancement: MemoEnhancement?
    @State private var showTitleChooser = false
    @FocusState private var titleFocused: Bool
    @ObservedObject private var sync = CloudSyncMonitor.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    TextField("", text: titleBinding, prompt: titlePrompt)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.skText)
                        .tint(.skAccent)
                        .submitLabel(.done)
                        .focused($titleFocused)
                        .onSubmit { repository.save() }
                        .accessibilityIdentifier("detail-title")
                    // ✦ title chooser — only when the Mac sent a suggested title.
                    if macPolish?.title.trimmingCharacters(in: .whitespaces).isEmpty == false {
                        Button { showTitleChooser = true } label: {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.skAccent)
                                .frame(width: 30, height: 30)
                                .background(Color.skAccentSoft, in: .rect(cornerRadius: 8, style: .continuous))
                        }
                        .padding(.top, 3)
                        .accessibilityIdentifier("title-chooser-button")
                    }
                }

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

                // Mac's polish: the summary card (when present) above the body.
                if let summary = macPolish?.summary.trimmingCharacters(in: .whitespacesAndNewlines),
                   !summary.isEmpty {
                    summaryCard(summary)
                        .padding(.top, 16)
                }

                if let label = diarStatus.label(for: memo.id) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            // Diarization is opaque (no real %) — show an honest
                            // ticking elapsed time so it's clearly still working.
                            TimelineView(.periodic(from: .now, by: 1)) { _ in
                                Text(diarStatus.labelWithElapsed(for: memo.id) ?? label)
                                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.skTextDim)
                            }
                        }
                        if diarStatus.isIdentifying(memo.id) {
                            Text("This can take a while — it keeps going if you leave.")
                                .font(.system(size: 11)).foregroundStyle(Color.skTextFaint)
                        }
                    }
                    .padding(.top, 14)
                    .accessibilityIdentifier("diarization-status")
                }

                // C3 capture items: pinned source block (link card / text quote / image)
                // above the annotation body. The transcript section is replaced entirely
                // for captures — there's no voice transcript to show.
                if memo.isShareCapture {
                    captureSourceBlock
                        .padding(.top, 18)
                    captureAnnotationSection
                        .padding(.top, 14)
                } else {
                    transcriptSection
                        .padding(.top, 18)
                    if !transcriptNameSpans.isEmpty {
                        peopleInNoteRow
                            .padding(.top, 14)
                    }
                }

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
        .task(id: memo.id) {
            timings = WordTimingsStore().load(for: memo.id) ?? []
            people = NamesStore.shared.livePeople()
            enhancement = repository.enhancement(forMemo: memo.id)
        }
        // A polish can arrive via CloudKit after the screen opens — re-fetch when a sync settles.
        .onChange(of: sync.isSyncing) { _, syncing in
            if !syncing { enhancement = repository.enhancement(forMemo: memo.id) }
        }
        .alert("Add tags", isPresented: $showAddTag) {
            TextField("tag, tag, tag", text: $newTag)
            Button("Add", action: addTag)
            Button("Cancel", role: .cancel) { newTag = "" }
        } message: {
            Text("Separate multiple tags with commas.")
        }
        // Shared-document (.file) capture → preview the PDF/doc in QuickLook.
        .quickLookPreview($quickLookURL)
        // Tap a speaker → an assign sheet: pick a known Person (links + enrolls the
        // voiceprint), merge into another speaker in this convo (fixes a mis-split), or
        // type a new name. Replaces the old free-text alert.
        .sheet(item: $assignTarget) { target in
            SpeakerAssignSheet(
                speaker: target.speaker,
                otherSpeakers: SpeakerTranscript.speakers(in: memo.transcript).filter { $0 != target.speaker },
                people: NamesStore.shared.livePeople(),
                onAssignPerson: { assign(target.speaker, to: NamesDisplay.name($0), enroll: true, slot: target.slot, turnSlots: target.turnSlots) },
                onMergeInto: { mergeTurn(at: target.index, into: $0) },
                onNewName: { assign(target.speaker, to: $0, enroll: true, slot: target.slot, turnSlots: target.turnSlots) }
            )
        }
        // Tap a name in the transcript → resolve it (the native confirmationDialog idiom,
        // mocks/phone-name-linking.html). Buttons depend on the tapped span's tier.
        .confirmationDialog(resolveDialogTitle, isPresented: resolveDialogPresented,
                            titleVisibility: .visible, presenting: resolveTarget) { target in
            resolveActions(for: target.span)
        } message: { target in
            if let msg = resolveDialogMessage(for: target.span) { Text(msg) }
        }
        // "Open … person card" / "New person…" → the editable person card (mock state 5).
        .sheet(item: $personSheet) { req in
            PersonEditorView(
                canonical: req.canonical, prefillName: req.prefillAlias ?? "",
                onSaved: { canonical in
                    if let alias = req.prefillAlias {        // a New-person flow links the tapped word
                        memo.linkName(alias: alias, to: canonical)
                        repository.save()
                    }
                    people = NamesStore.shared.livePeople()
                },
                onDeleted: { people = NamesStore.shared.livePeople() }
            )
        }
        // People-in-this-note chip surface (mock state 4) — link / re-link via chips.
        .sheet(isPresented: $showPeopleSheet) { peopleSheetView }
        // Title chooser (Phase 4): Suggested (Mac) / From the recording / your own.
        .confirmationDialog("Title", isPresented: $showTitleChooser, titleVisibility: .visible) {
            if let suggested = macPolish?.title.trimmingCharacters(in: .whitespaces), !suggested.isEmpty {
                Button(suggested) { memo.title = suggested; memo.markEdited(); repository.save() }
            }
            if let line = recordingFirstLine {
                Button("From the recording: \(line)") { memo.title = line; memo.markEdited(); repository.save() }
            }
            Button("Type your own…") { titleFocused = true }
        } message: {
            Text("Choose what heads this note.")
        }
        // Unlink → an Undo toast (reversible; mock build note #6).
        .overlay(alignment: .bottom) { undoToastView }
    }

    private func startAssigning(_ index: Int, _ speaker: String) {
        // Read the per-turn slot map FRESH from the sidecar (an in-place re-diarize may
        // have renumbered slots under the same memo id). Only trusted when it still lines
        // up with the current turns (no structural edit since diarize). Stale/absent →
        // nil slot → the assign falls back to name-based relabeling.
        let slots = DiarizationStore().load(for: memo.id)?.turnSlots ?? []
        let count = SpeakerTranscript.parse(memo.transcript)?.count ?? 0
        let slot = (slots.count == count && index >= 0 && index < slots.count) ? slots[index] : nil
        assignTarget = AssignTarget(index: index, speaker: speaker, slot: slot, turnSlots: slots)
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
        memo.imageURL(markerIndex: n)
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
    private func assign(_ old: String, to newName: String, enroll: Bool, slot: Int?, turnSlots: [Int]) {
        let new = newName.trimmingCharacters(in: .whitespaces)
        guard let transcript = memo.transcript, !new.isEmpty, new != old else { return }
        // Slot-aware when the per-turn slot map still lines up — relabels ONLY this
        // speaker's slot, so a same-named twin (one voice split into two slots, both
        // "Tiuri") is left alone. Otherwise relabel every `**old:**` header (the prior
        // behaviour) — correct when the name is unique.
        if let slot, let bySlot = SpeakerTranscript.relabelSlot(transcript, turnSlots: turnSlots, slot: slot, to: new) {
            memo.transcript = bySlot
        } else {
            let relabeled = transcript.replacingOccurrences(of: "**\(old):**", with: "**\(new):**")
            memo.transcript = SpeakerTranscript.mergeAdjacentTurns(relabeled)
        }
        memo.transcriptUserEdited = true
        repository.save()
        if enroll {
            Task { await Self.learnVoice(memoID: memo.id, audioURL: memo.audioURL, old: old, new: new, slot: slot) }
        }
    }

    /// Extract `old`'s audio from the diar sidecar, embed it, and store the voiceprint
    /// under `new`. `static` so it isn't tied to the transient (paged) view's lifetime.
    private static func learnVoice(memoID: UUID, audioURL: URL?, old: String, new: String, slot: Int?) async {
        guard let audioURL, let data = DiarizationStore().load(for: memoID) else { return }
        // Prefer the EXACT slot the user tapped (correct even when two slots share the
        // name — the wrong-voiceprint bug); fall back to the first slot named `old`.
        guard let slot = slot ?? data.slotNames.first(where: { $0.value == old }).flatMap({ Int($0.key) }) else { return }
        // Keep the sidecar's slot name current so a later re-enroll finds this slot, and
        // DROP turnSlots — the rename just merged turns, so the diarize-time map no longer
        // matches the transcript (a stale map must not be persisted or uploaded).
        var updated = data; updated.slotNames[String(slot)] = new; updated.turnSlots = nil
        DiarizationStore().write(updated, for: memoID)

        await MainActor.run { DiarizationStatus.shared.begin(memoID, phase: .enrolling) }
        defer { Task { @MainActor in DiarizationStatus.shared.finish() } }

        guard let samples = try? AudioConverter(sampleRate: 16000).resampleAudioFile(audioURL) else { return }
        let clip = DiarizationService.clip(data.segments.filter { $0.speaker == slot }, from: samples)
        await VoiceEnroller.enroll(name: new, clip: clip, using: EmbedderFactory.make())
    }

    private var titleBinding: Binding<String> {
        // Prefer the user's title; else default to the Mac's suggested title (so a polished
        // memo reads nicely instead of falling back to the um-filled first line). Editing
        // writes the user title.
        Binding(get: { memo.title ?? macPolish?.title ?? "" },
                set: { memo.title = $0.isEmpty ? nil : $0; memo.markEdited() })
    }

    private var titlePrompt: Text {
        // C3 captures: use the resolved capture title as the prompt (urlTitle /
        // text snippet / "Image") — there's no transcript line to fall back to.
        if memo.isShareCapture {
            let hint = memo.shareCaptureTitle
            return Text(hint.isEmpty ? "Add a title" : hint).foregroundStyle(Color.skTextFaint)
        }
        // Strip a leading `**Speaker:** ` prefix (conversation note) or `> `
        // blockquote marker (capture memo) so the title prompt shows the
        // actual first words, not the Markdown.
        let line = (memo.firstTranscriptLine ?? "Add a title")
            .replacingOccurrences(of: #"^\*\*.+?:\*\*\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^>\s*"#, with: "", options: .regularExpression)
        return Text(line.isEmpty ? "Add a title" : line).foregroundStyle(Color.skTextFaint)
    }

    private func addTag() {
        // Accept several comma-separated tags in one go (device ask: "select a lot
        // of tags"); de-duped against the memo's existing tags.
        let incoming = Memo.parseTagInput(newTag)
        newTag = ""
        var added = false
        for t in incoming where !memo.tags.contains(t) { memo.tags.append(t); added = true }
        guard added else { return }
        memo.markEdited()
        repository.save()
    }

    private func removeTag(_ tag: String) {
        memo.tags.removeAll { $0 == tag }
        memo.markEdited()
        repository.save()
    }

    // MARK: - Transcript (always editable in place; karaoke on playback)

    /// Conversation notes render as speaker-attributed turns (their own karaoke +
    /// inline editing); everything else — ordinary memos AND audiobook captures —
    /// goes through `TranscriptBodyView`, ONE component with three explicit modes
    /// (editing / playing full-text karaoke / reading while transcribing).
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
        } else {
            TranscriptBodyView(
                memo: memo, player: player,
                onCommit: { memo.markEdited(); repository.save() },
                nameSpans: transcriptNameSpans,
                onTapName: { resolveTarget = NameResolveTarget(span: $0) },
                polishedBinding: polishedBinding
            )
        }
    }

    /// Tiered name spans for the in-place linking surface — over the ACTIVE body (the
    /// polished copy-edit when present, else the raw transcript). Ordinary voice memos only
    /// (captures show a quote block; conversations route to `SpeakerTurnsView`), and skipped
    /// during playback (the editor is swapped for karaoke; recomputing every tick is waste).
    private var transcriptNameSpans: [NameSpan] {
        guard !player.isPlaying, !people.isEmpty,
              !memo.isShareCapture, memo.captureQuote == nil,
              SpeakerTranscript.parse(memo.transcript) == nil else { return [] }
        return Sanitiser.nameSpans(inRaw: activeBodyText, people: people,
                                   neverLink: Set(memo.nameResolutions.unlinkedNames),
                                   namePicks: memo.nameResolutions.namePicks)
    }

    // MARK: - Mac polish (Phase 4)

    /// The Mac's polish to SHOW — only for an ordinary monologue voice memo (captures keep
    /// their quote block; conversations route to `SpeakerTurnsView`). nil = show raw.
    private var macPolish: MemoEnhancement? {
        guard let e = enhancement, e.hasContent,
              !memo.isShareCapture, memo.captureQuote == nil,
              SpeakerTranscript.parse(memo.transcript) == nil else { return nil }
        return e
    }

    /// The body the editor/karaoke/name-linking act on: the polished copy-edit when present,
    /// else the raw transcript.
    private var activeBodyText: String { macPolish?.copyedit ?? (memo.transcript ?? "") }

    /// Binding the editor writes when showing the polished body — persists the copy-edit +
    /// stamps provenance (this phone, now) so the edit syncs as the source of truth. The Mac
    /// won't re-polish an already-done memo, so it's never clobbered.
    private var polishedBinding: Binding<String>? {
        guard let e = macPolish else { return nil }
        return Binding(
            get: { e.copyedit },
            set: { newValue in
                e.copyedit = newValue
                e.enhancedByDeviceID = DeviceID.current()
                e.enhancedAt = Date()
            }
        )
    }

    /// The recording's first line (markers/speaker-prefix stripped) — the "From the
    /// recording" title option.
    private var recordingFirstLine: String? {
        memo.firstTranscriptLine.map { String($0.prefix(60)) }
    }

    private func summaryCard(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles").font(.system(size: 10, weight: .bold))
                Text("SUMMARY").font(.system(size: 11, weight: .bold)).kerning(0.5)
            }
            .foregroundStyle(Color.skAccent)
            Text(summary)
                .font(.system(size: 13.5))
                .foregroundStyle(Color.skTextDim)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.skAccentSoft.opacity(0.5), in: .rect(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle.sk(13).stroke(Color.skAccent.opacity(0.22), lineWidth: 1))
        .accessibilityIdentifier("polish-summary-card")
    }

    // MARK: - Name resolution (the tapped-name sheet)

    private var resolveDialogPresented: Binding<Bool> {
        Binding(get: { resolveTarget != nil }, set: { if !$0 { resolveTarget = nil } })
    }

    private var resolveDialogTitle: String {
        guard let span = resolveTarget?.span else { return "" }
        switch span.tier {
        case .linked:    return personDisplay(span.canonical) ?? span.alias
        case .suggested: return "Link this name?"
        case .ambiguous: return "Which \(span.alias)?"
        case .plain:     return "Link “\(span.alias)”?"
        }
    }

    private func resolveDialogMessage(for span: NameSpan) -> String? {
        switch span.tier {
        case .linked:    return "Linked in this note — only the first “\(span.alias)” carries the link."
        case .suggested: return "Tap to link “\(span.alias)” to this person."
        case .ambiguous: return "\(span.candidates.count) people in your Names go by “\(span.alias)”."
        case .plain:     return "Kept as plain text here."
        }
    }

    @ViewBuilder private func resolveActions(for span: NameSpan) -> some View {
        switch span.tier {
        case .linked:
            // Change person — only when the alias is shared (an ambiguous force-pick).
            ForEach(span.candidates.filter { candidateKey($0.canonical) != candidateKey(span.canonical ?? "") }, id: \.id) { c in
                Button("Switch to \(candidateLabel(c))") { applyLink(span.alias, to: c.canonical) }
            }
            Button("Unlink — keep as plain text") { applyUnlink(span) }
            if let canonical = span.canonical {
                Button("Open \(firstName(canonical))’s person card") {
                    personSheet = PersonSheetRequest(canonical: canonical, prefillAlias: nil)
                }
            }
        case .suggested, .plain:
            ForEach(span.candidates, id: \.id) { c in
                Button("Link to \(candidateLabel(c))") { applyLink(span.alias, to: c.canonical) }
            }
            Button("New person…") { personSheet = PersonSheetRequest(canonical: nil, prefillAlias: span.alias) }
            if span.tier == .suggested {
                Button("Keep as plain text") { applyKeepPlain(span.alias) }
            }
        case .ambiguous:
            ForEach(span.candidates, id: \.id) { c in
                Button(candidateLabel(c)) { applyLink(span.alias, to: c.canonical) }
            }
            Button("New person…") { personSheet = PersonSheetRequest(canonical: nil, prefillAlias: span.alias) }
            Button("Keep as plain text") { applyKeepPlain(span.alias) }
        }
    }

    private func candidateKey(_ canonical: String) -> String { NamesMerge.keyName(canonical).lowercased() }
    private func candidateLabel(_ c: NameCandidate) -> String { NamesMerge.keyName(c.canonical) }
    private func firstName(_ canonical: String) -> String {
        NamesMerge.keyName(canonical).split(separator: " ").first.map(String.init) ?? NamesMerge.keyName(canonical)
    }
    private func personDisplay(_ canonical: String?) -> String? { canonical.map { NamesMerge.keyName($0) } }

    private func applyLink(_ alias: String, to canonical: String) {
        memo.linkName(alias: alias, to: canonical); repository.save()
    }
    private func applyKeepPlain(_ alias: String) {
        memo.keepNamePlain(alias: alias); repository.save()
    }
    /// Unlink a LINKED name → plain, with a reversible Undo toast restoring the exact
    /// prior resolutions (the pick / auto-link), not just the default tier.
    private func applyUnlink(_ span: NameSpan) {
        let prior = memo.nameResolutions
        memo.keepNamePlain(alias: span.alias); repository.save()
        let alias = span.alias
        withAnimation(Theme.Motion.spring) {
            undoToast = NameUndoToast(message: "Unlinked — “\(alias)” is plain text here") {
                memo.nameResolutions = prior
                memo.markEdited(); repository.save()
                withAnimation(Theme.Motion.spring) { undoToast = nil }
            }
        }
    }

    @ViewBuilder private var undoToastView: some View {
        if let toast = undoToast {
            HStack(spacing: 10) {
                Text(toast.message).font(.system(size: 13)).foregroundStyle(Color.skText).lineLimit(2)
                Spacer(minLength: 4)
                Button("Undo", action: toast.undo)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.skAccent)
                    .accessibilityIdentifier("name-unlink-undo")
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Color.skSurface, in: .rect(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle.sk(12).stroke(Color.skBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 14, y: 5)
            .padding(.horizontal, Theme.Space.margin)
            .padding(.bottom, 96)                          // clear the floating player bar
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: toast.id) {
                try? await Task.sleep(for: .seconds(4))
                if undoToast?.id == toast.id { withAnimation(Theme.Motion.spring) { undoToast = nil } }
            }
        }
    }

    // MARK: - People in this note (chip surface, mock state 4)

    private var linkedCount: Int {
        Set(transcriptNameSpans.filter { $0.tier == .linked }.compactMap { $0.canonical?.lowercased() }).count
    }

    private var peopleInNoteRow: some View {
        Button { showPeopleSheet = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle").font(.system(size: 15)).foregroundStyle(Color.skTextDim)
                (Text("People in this note").fontWeight(.semibold).foregroundStyle(Color.skText)
                 + Text(" · \(linkedCount) linked").foregroundStyle(Color.skTextDim))
                    .font(.system(size: 13))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.skTextFaint)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(Color.skSurface, in: .rect(cornerRadius: Theme.Radius.field, style: .continuous))
            .overlay(RoundedRectangle.sk(Theme.Radius.field).stroke(Color.skBorder, lineWidth: 1))
        }
        .accessibilityIdentifier("people-in-note-row")
    }

    /// One candidate person for the note, with the alias they go by here + whether they're
    /// currently linked. Built from the spans (union of every span's candidates).
    private struct PersonChip: Identifiable {
        let id: String; let canonical: String; let display: String; let alias: String; let linked: Bool
    }

    private var noteCandidateChips: [PersonChip] {
        var aliasFor: [String: String] = [:], displayFor: [String: String] = [:]
        var order: [String] = [], linkedSet = Set<String>()
        for span in transcriptNameSpans {
            if span.tier == .linked, let c = span.canonical { linkedSet.insert(c.lowercased()) }
            for cand in span.candidates {
                let key = cand.canonical.lowercased()
                if aliasFor[key] == nil {
                    aliasFor[key] = span.alias
                    displayFor[key] = NamesMerge.keyName(cand.canonical)
                    order.append(cand.canonical)
                }
            }
        }
        return order.map { canonical in
            let key = canonical.lowercased()
            return PersonChip(id: canonical, canonical: canonical, display: displayFor[key] ?? canonical,
                              alias: aliasFor[key] ?? "", linked: linkedSet.contains(key))
        }
    }

    private var peopleSheetView: some View {
        NavigationStack {
            ZStack {
                Color.skBg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Tap to link the people this note is about. Linking writes the [[wikilink]] at the first mention.")
                            .font(.system(size: 13)).foregroundStyle(Color.skTextDim)
                        FlowLayout(spacing: 8, lineSpacing: 8) {
                            ForEach(noteCandidateChips) { chip in
                                Button { togglePersonChip(chip) } label: { chipLabel(chip) }
                            }
                            Button { personSheet = PersonSheetRequest(canonical: nil, prefillAlias: nil) } label: {
                                Text("＋ Someone else…")
                                    .font(.system(size: 13)).foregroundStyle(Color.skTextDim)
                                    .padding(.horizontal, 11).padding(.vertical, 7)
                                    .overlay(Capsule().strokeBorder(Color.skBorder, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                            }
                            .accessibilityIdentifier("people-someone-else")
                        }
                    }
                    .padding(Theme.Space.margin)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("People in this note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPeopleSheet = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func chipLabel(_ chip: PersonChip) -> some View {
        HStack(spacing: 6) {
            Image(systemName: chip.linked ? "checkmark" : "plus").font(.system(size: 11, weight: .bold))
            Text(chip.display).font(.system(size: 13, weight: chip.linked ? .semibold : .regular))
        }
        .foregroundStyle(chip.linked ? Color.skAccent : Color.skTextDim)
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background((chip.linked ? Color.skAccentSoft : Color.white.opacity(0.05)),
                    in: .capsule)
        .overlay(Capsule().strokeBorder(chip.linked ? Color.skAccent.opacity(0.45) : Color.skBorder, lineWidth: 1))
    }

    /// Chip tap: link a candidate's first mention, or unlink (→ a dotted, re-linkable token).
    private func togglePersonChip(_ chip: PersonChip) {
        guard !chip.alias.isEmpty else { return }
        if chip.linked { memo.keepNamePlain(alias: chip.alias) }
        else { memo.linkName(alias: chip.alias, to: chip.canonical) }
        repository.save()
    }

    private struct MetaChip: Identifiable { let id = UUID(); let text: String; let symbol: String? }

    private var metaChips: [MetaChip] {
        var chips: [MetaChip] = [MetaChip(text: MemoDate.label(memo.recordedAt), symbol: nil)]
        // C3 captures: show the source type label instead of location/weather chips.
        if memo.isShareCapture {
            chips.append(MetaChip(text: memo.shareCaptureTypeLabel, symbol: memo.shareCaptureGlyph))
            return chips
        }
        // Video imports show a "Video" source chip (no location/weather was captured).
        if memo.isVideoImport {
            chips.append(MetaChip(text: "Video", symbol: "video.fill"))
        }
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

    // MARK: - Capture detail (C3 mock state 2)

    /// The pinned source block shown above the annotation body for captures:
    /// URL → link card with "Open ↗" button; text → blockquote; image → photo embed.
    @ViewBuilder private var captureSourceBlock: some View {
        if let sc = memo.sharedContent {
            switch sc.type {
            case .url:
                captureURLCard(sc: sc)
            case .text:
                if let text = sc.text, !text.isEmpty {
                    captureTextQuote(text: text)
                }
            case .image:
                captureImageEmbed
            case .file:
                captureFileCard(sc: sc)
            }
        }
    }

    /// A shared document (PDF/etc.) capture: a card showing the filename + an Open
    /// button that previews it in QuickLook. (2026-06-21 "share a PDF and have it
    /// live in there".)
    private func captureFileCard(sc: SharedContent) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.skAccent.opacity(0.13))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "doc.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.skAccent)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(sc.fileName ?? "Document")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.skText)
                    .lineLimit(2)
                Text(memo.shareCaptureTypeLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.skTextFaint)
            }

            Spacer(minLength: 4)

            if memo.sharedFileURL != nil {
                Button { quickLookURL = memo.sharedFileURL } label: {
                    Text("Open")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.skAccent)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Color.skAccentSoft, in: .rect(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.skAccent.opacity(0.35), lineWidth: 0.5)
                        )
                }
                .accessibilityIdentifier("capture-open-file")
                .accessibilityLabel("Open document")
            }
        }
        .padding(13)
        .background(Color.skSurface, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle.sk(Theme.Radius.card).stroke(Color.skBorder, lineWidth: 1)
        )
        .accessibilityIdentifier("capture-file-card")
    }

    private func captureURLCard(sc: SharedContent) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.skAccent.opacity(0.13))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "globe")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.skAccent)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(sc.urlTitle ?? memo.shareCaptureURLDomain ?? "Link")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.skText)
                    .lineLimit(2)
                if let domain = memo.shareCaptureURLDomain {
                    Text(domain)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.skTextFaint)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if let urlStr = sc.url, let url = URL(string: urlStr) {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    Text("Open ↗")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.skAccent)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Color.skAccentSoft, in: .rect(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.skAccent.opacity(0.35), lineWidth: 0.5)
                        )
                }
                .accessibilityIdentifier("capture-open-link")
                .accessibilityLabel("Open link")
            }
        }
        .padding(13)
        .background(Color.skSurface, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle.sk(Theme.Radius.card).stroke(Color.skBorder, lineWidth: 1)
        )
        .accessibilityIdentifier("capture-link-card")
    }

    private func captureTextQuote(text: String) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.skAccent.opacity(0.5))
                .frame(width: 2)
            Text(text)
                .font(.system(size: 14).italic())
                .foregroundStyle(Color.skTextDim)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.skSurface, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle.sk(Theme.Radius.card).stroke(Color.skBorder, lineWidth: 1)
        )
        .accessibilityIdentifier("capture-text-quote")
    }

    @ViewBuilder private var captureImageEmbed: some View {
        if let filename = memo.sharedContent?.fileName,
           let img = UIImage(contentsOfFile: AppPaths.recordingsDirectory.appendingPathComponent(filename).path) {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle.sk(Theme.Radius.card).stroke(Color.skBorder, lineWidth: 1)
                )
                .accessibilityIdentifier("capture-image-embed")
        } else if let manifest = memo.metadata?.imageManifest?.first {
            // Fallback: look up via the image manifest (the drain copies the image
            // to the recordings dir under the manifest filename).
            let manifestURL = AppPaths.recordingsDirectory.appendingPathComponent(manifest.filename)
            if let img = UIImage(contentsOfFile: manifestURL.path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle.sk(Theme.Radius.card).stroke(Color.skBorder, lineWidth: 1)
                    )
                    .accessibilityIdentifier("capture-image-embed")
            }
        }
    }

    /// The annotation body for C3 captures — editable, writes back to
    /// `memo.annotationText` (NOT the transcript). If no annotation yet,
    /// shows a placeholder prompt. While a dictated voice note is still
    /// transcribing, the editor is swapped for a status row — an open draft
    /// would clobber the landing text (same window the append flow closes).
    @ViewBuilder private var captureAnnotationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("ANNOTATION")

            if memo.transcriptStatus == .transcribing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Transcribing your voice note…")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.skTextDim)
                }
                .padding(.vertical, 10)
                .accessibilityIdentifier("capture-dictation-transcribing")
                if let typed = memo.annotationText, !typed.isEmpty {
                    Text(typed)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.skText)
                }
            } else {
                // Use TranscriptEditor's existing editable TextEditor pattern for
                // consistency — but backed by annotationText, not transcript.
                CaptureAnnotationEditor(
                    text: Binding(
                        get: { memo.annotationText ?? "" },
                        set: { memo.annotationText = $0.isEmpty ? nil : $0; repository.save() }
                    )
                )
            }
        }
    }
}

// MARK: - Capture annotation editor

/// Simple editable body for C3 capture annotations — no karaoke, no markers.
/// Matches the transcript-editor style (dark surface, tint accent, dismiss on drag).
private struct CaptureAnnotationEditor: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Add a note about this capture…")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.skTextFaint)
                    .padding(.top, 9)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $text)
                .font(.system(size: 15))
                .foregroundStyle(Color.skText)
                .tint(.skAccent)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .focused($focused)
        }
        .padding(4)
        .background(Color.skSurface, in: .rect(cornerRadius: Theme.Radius.editBox, style: .continuous))
        .overlay(
            RoundedRectangle.sk(Theme.Radius.editBox)
                .stroke(focused ? Color.skAccent.opacity(0.45) : Color.skBorder, lineWidth: 1)
        )
        .accessibilityIdentifier("capture-annotation-editor")
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

// MARK: - Name-linking presentation state

/// A transcript name span the user tapped → drives the resolve confirmationDialog.
struct NameResolveTarget: Identifiable { let id = UUID(); let span: NameSpan }

/// The reversible "unlink" toast (mock build note #6) — `undo` restores the exact prior
/// resolutions.
struct NameUndoToast: Identifiable { let id = UUID(); let message: String; let undo: () -> Void }

/// Routes to the person editor (mock state 5): `canonical` set = open an existing card;
/// `prefillAlias` set = a "New person…" / "Someone else…" flow seeded with the spoken word.
struct PersonSheetRequest: Identifiable {
    let id = UUID()
    let canonical: String?
    let prefillAlias: String?
}
