import SwiftUI
import SwiftData
import UIKit
import QuickLook
import PhotosUI
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
    @State private var showShare = false
    /// ⋯ → "Remind me…" for the current page (chunk 7).
    @State private var reminderMemo: Memo?
    /// Transient "n / total" that ghosts in while swiping between memos —
    /// replaces the permanent page-dots row (compact-player spec).
    @State private var pageFlash = false
    @StateObject private var player = AudioPlayerModel()
    @ObservedObject private var lockGate = LockGate.shared
    @State private var lockVaultNotice = false
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
                        MemoPageView(memo: memo, player: player, isCurrent: memo.id == selection,
                                     onOpenMemo: { id in
                                         guard memos.contains(where: { $0.id == id }) else { return }
                                         withAnimation(Theme.Motion.snappy) { selection = id }
                                     })
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
        .confirmationDialog(memoStatsLine, isPresented: $showActions, titleVisibility: .visible) {
            Button("Add recording", action: { showAppendRecorder = true })
            Button("Remind me…", action: { reminderMemo = currentMemo })
            if let memo = currentMemo {
                Button(memo.locked ? "Remove Lock" : "Lock Note", action: { toggleLock(memo) })
            }
            Button("Share note…", action: { showShare = true })
            Button("Copy transcript", action: copyTranscript)
            Button("Delete", role: .destructive, action: deleteCurrent)
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $reminderMemo) { memo in
            ReminderSheet(memo: memo) { repository.save() }
        }
        .alert("Already in your vault", isPresented: $lockVaultNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This note was published to Obsidian before you locked it. Skrift never deletes vault files — remove it there if you want it gone. New publishes will skip it.")
        }
        .sheet(isPresented: $showShare) {
            if let memo = currentMemo {
                ActivityShareSheet(items: shareItems(for: memo))
                    .presentationDetents([.medium, .large])
            }
        }
        // Append a follow-up recording to the current memo (records → transcribes →
        // appends text + merges audio in MemoSaver.appendRecording). Transcript
        // updates in place via @Query when it lands.
        .fullScreenCover(isPresented: $showAppendRecorder) {
            RecordView(appendTo: selection)
        }
        .onAppear { loadCurrentAudio() }
        .onChange(of: selection) { old, newID in
            // Re-target the bar when paging settles; ignore the transient nil the
            // paging scroll reports between snap points (don't stop audio mid-swipe).
            guard let newID else { return }
            loadCurrentAudio()
            if old != nil, old != newID, memos.count > 1 { pageFlash = true }
        }
        // Unlocking (or re-locking on background) re-derives what the player
        // may touch — a locked memo's audio never loads.
        .onChange(of: lockGate.unlockedMemoIDs) { _, _ in loadCurrentAudio() }
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
        PlayerBar(player: player, clock: player.clock)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .overlay(alignment: .top) {
                if pageFlash, let idx = memos.firstIndex(where: { $0.id == selection }) {
                    Text("\(idx + 1) / \(memos.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.skTextDim)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Color.skSurface, in: .capsule)
                        .overlay(Capsule().strokeBorder(Color.skBorder, lineWidth: 0.5))
                        .offset(y: -30)
                        .transition(.opacity)
                        .task(id: selection) {
                            try? await Task.sleep(for: .seconds(1.1))
                            withAnimation(.easeOut(duration: 0.3)) { pageFlash = false }
                        }
                }
            }
    }

    private func copyTranscript() {
        guard let text = currentMemo?.transcript, !text.isEmpty else { return }
        UIPasteboard.general.string = text
    }

    /// "512 words · 3:07" — the ⋯ sheet's title doubles as the note's stats line.
    private var memoStatsLine: String {
        guard let memo = currentMemo else { return "Memo" }
        let words = MemoShare.wordCount(of: memo.transcript)
        var parts: [String] = [words == 1 ? "1 word" : "\(words) words"]
        if memo.duration > 0 {
            let total = Int(memo.duration)
            parts.append(String(format: "%d:%02d", total / 60, total % 60))
        }
        return parts.joined(separator: " · ")
    }

    /// Share OUT (survey fold, user-approved): the note as markdown text, plus
    /// the recording file when there is one.
    private func shareItems(for memo: Memo) -> [Any] {
        var items: [Any] = [MemoShare.markdown(title: memo.title ?? memo.firstTranscriptLine,
                                               body: memo.transcript ?? "")]
        if let url = memo.audioURL, FileManager.default.fileExists(atPath: url.path) {
            items.append(url)
        }
        return items
    }

    /// Load the CURRENT memo's audio — unless its content is lock-gated
    /// (chunk 8: the bar must not play a locked note around the placeholder).
    private func loadCurrentAudio() {
        guard let memo = currentMemo else { return }
        player.load(lockGate.isLocked(memo) ? nil : memo.audioURL)
    }

    /// Lock from ⋯ (instant, + vault notice when already published); removing
    /// the lock requires device-owner auth (Apple Notes idiom).
    private func toggleLock(_ memo: Memo) {
        if memo.locked {
            Task {
                guard await LockGate.shared.authorizeRemoveLock() else { return }
                memo.locked = false
                memo.markEdited()
                repository.save()
            }
        } else {
            guard LockGate.shared.canAuthenticate() else { return }
            memo.locked = true
            memo.markEdited()
            repository.save()
            player.stopAndClear()
            if ExportStateStore.shared.record(for: memo.id) != nil { lockVaultNotice = true }
        }
    }

    /// Re-point the player at the current memo's audio if an earlier `load()` failed
    /// because the file wasn't on disk yet (the async video-import extraction case).
    /// A no-op once audio is loaded, so it never disturbs active playback.
    private func reloadIfAudioMissing() {
        guard !player.hasAudio else { return }
        loadCurrentAudio()
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
    /// Whether this page is the pager's current page — off-screen neighbours
    /// hide their UIKit editor subtree from accessibility (see NoteBodyView).
    var isCurrent: Bool = true
    private let repository = NotesRepository.shared
    @State private var showTagEditor = false
    @State private var libraryTags: [String] = []
    /// What the QuickLook viewer is showing: an inline photo (marker set — an
    /// edit re-mirrors + re-OCRs it) or a shared-document capture (marker nil).
    struct QuickLookTarget: Identifiable {
        let url: URL
        var marker: Int?
        var id: String { url.path }
    }
    @State private var quickLookTarget: QuickLookTarget?
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

    /// Name spans over the active body — MEMOIZED (@State) and recomputed off-main
    /// only when the text / roster / resolutions actually change. (Was an uncached
    /// computed property that re-ran the full Sanitiser scan 2–3× per body eval —
    /// per keystroke — note-editing study 2026-07-06.)
    @State private var spans: [NameSpan] = []
    /// Photo-at-caret (accessory 📷): the page presents the picker, the proxy
    /// hands the image to the live editor coordinator.
    @State private var bodyProxy = NoteBodyProxy()
    @State private var showPhotoPicker = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showPhotoSourceDialog = false
    @State private var showCameraCapture = false
    /// Memo↔memo links (chunk 5): the "[[" picker + who links here.
    @State private var showMemoLinkPicker = false
    /// Reminder chip → the sheet (chunk 7).
    @State private var showReminderSheet = false
    @State private var backlinks: [(id: UUID, title: String)] = []
    /// Jump the pager to another memo (link chips + backlink rows).
    var onOpenMemo: (UUID) -> Void = { _ in }

    @ObservedObject private var lockGate = LockGate.shared

    var body: some View {
        // Note-editing overhaul (spec mocks/note-editor-redesign.html): B2 pinned
        // title above every page kind; monologue memos (incl. audiobook captures +
        // polished bodies) get the re-founded scrolling editor page — the text view
        // owns the scroll, the metadata header scrolls inside it. Conversations and
        // C3 share-captures keep their legacy scroll layout for now (phase 2).
        Group {
            if lockGate.isLocked(memo) {
                lockedPlaceholder
            } else if memo.isShareCapture {
                legacyScrollPage { captureContent }
            } else if SpeakerTranscript.parse(memo.transcript) != nil {
                legacyScrollPage { conversationContent }
            } else {
                editorPage
            }
        }
        .task(id: memo.id) {
            timings = WordTimingsStore().load(for: memo.id) ?? []
            people = NamesStore.shared.livePeople()
            enhancement = repository.enhancement(forMemo: memo.id)
            recomputeSpans()
            recomputeBacklinks()
        }
        // A polish can arrive via CloudKit after the screen opens — re-fetch when a sync settles.
        .onChange(of: sync.isSyncing) { _, syncing in
            if !syncing {
                enhancement = repository.enhancement(forMemo: memo.id)
                recomputeSpans()
            }
        }
        // Transcript can change outside the editor (transcription lands, append,
        // speaker edits) — re-derive the tiers.
        .onChange(of: memo.transcript) { _, _ in recomputeSpans() }
        .sheet(isPresented: $showReminderSheet) {
            ReminderSheet(memo: memo) { repository.save() }
        }
        // Tag CHIP editor (chunk 3): chips with explicit ✕, comma input kept,
        // autocomplete from every tag in the library.
        .sheet(isPresented: $showTagEditor) {
            TagEditorSheet(memo: memo, allTags: libraryTags) { repository.save() }
        }
        // Shared-document (.file) capture → preview the PDF/doc in QuickLook —
        // and the editor's inline photos (tap a photo → viewer).
        // Markup-enabled QuickLook (P2#10): draw on a photo → saves back into
        // the file → re-mirror to CloudKit (size-change capture), fresh OCR
        // (text reset to un-scanned), and a rebuilt inline thumbnail.
        .fullScreenCover(item: $quickLookTarget) { target in
            MarkupPreviewView(url: target.url) {
                photoWasEdited(target)
            }
            .ignoresSafeArea()
        }
        // "[[" typed → pick a note to link; the chip lands at the trigger.
        .sheet(isPresented: $showMemoLinkPicker) {
            MemoLinkPickerSheet(candidates: memoLinkCandidates()) { id, title in
                bodyProxy.insertMemoLink(id: id, title: title)
            }
        }
        // Accessory 📷 → camera or library (round-1 P2: Notes offers both) →
        // insert at the caret + register the new file for CloudKit (same
        // manifest/asset conventions as recording). Camera-less environments
        // (simulator) skip the dialog and go straight to the library.
        .confirmationDialog("Add photo", isPresented: $showPhotoSourceDialog, titleVisibility: .visible) {
            Button("Take Photo") { showCameraCapture = true }
            Button("Choose from Library") { showPhotoPicker = true }
        }
        .fullScreenCover(isPresented: $showCameraCapture) {
            CameraImagePicker { insertPickedPhoto($0) }
                .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    insertPickedPhoto(image)
                }
                pickedPhoto = nil
            }
        }
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
                    recomputeSpans()
                },
                onDeleted: {
                    people = NamesStore.shared.livePeople()
                    recomputeSpans()
                }
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

    // MARK: - Page kinds (B2 pinned title + body)

    /// The whole page while lock-gated: title + 🔒 + Unlock. Content, header
    /// chips, photos, and audio all stay behind Face ID; swiping to a locked
    /// neighbour lands here too (the pager can't bypass it).
    private var lockedPlaceholder: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.skTextDim)
            Text(memo.title?.isEmpty == false ? memo.title! : "Locked note")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.skText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text("Locked notes stay out of Obsidian publish and need Face ID here. They're hidden, not encrypted.")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.skTextFaint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Button {
                Task { _ = await lockGate.unlock(memo.id) }
            } label: {
                Label("Unlock", systemImage: "faceid")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22).padding(.vertical, 11)
                    .background(Color.skAccent, in: .capsule)
            }
            .accessibilityIdentifier("unlock-note-button")
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Space.margin)
    }

    /// The B2 pinned title row — always visible above the scrolling note, so you
    /// know which memo you're in while swiping between memos. The ✦ chooser rides
    /// along when the Mac sent a suggested title.
    private var pinnedTitleRow: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField("", text: titleBinding, prompt: titlePrompt)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.skText)
                .tint(.skAccent)
                .submitLabel(.done)
                .focused($titleFocused)
                .onSubmit { repository.save() }
                .accessibilityIdentifier("detail-title")
            if macPolish?.title.trimmingCharacters(in: .whitespaces).isEmpty == false {
                Button { showTitleChooser = true } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.skAccent)
                        .frame(width: 28, height: 28)
                        .background(Color.skAccentSoft, in: .rect(cornerRadius: 8, style: .continuous))
                }
                .accessibilityIdentifier("title-chooser-button")
            }
        }
        .padding(.horizontal, Theme.Space.margin)
        .padding(.top, 4)
        .padding(.bottom, 9)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.skBorder).frame(height: 0.5)
        }
    }

    /// The re-founded monologue page: ONE scrolling text view is the body; the
    /// metadata header (chips/importance/summary/diar/quote) and the people-row
    /// footer scroll INSIDE it. Native selection/caret/undo mechanics throughout.
    private var editorPage: some View {
        VStack(spacing: 0) {
            pinnedTitleRow
            NoteBodyView(
                memo: memo,
                player: player,
                nameSpans: spans,
                onTapName: { resolveTarget = NameResolveTarget(span: $0) },
                polishedBinding: polishedBinding,
                onCommit: {
                    memo.markEdited()
                    repository.save()
                    recomputeSpans()
                },
                header: AnyView(noteHeaderCore(isCurrent: isCurrent)
                    .padding(.horizontal, Theme.Space.margin).padding(.top, 6)
                    .accessibilityHidden(!isCurrent)),
                footer: AnyView(noteFooter(isCurrent: isCurrent).accessibilityHidden(!isCurrent)),
                a11yHidden: !isCurrent,
                onTapImage: { n in
                    if let url = memo.imageURL(markerIndex: n) {
                        quickLookTarget = QuickLookTarget(url: url, marker: n)
                    }
                },
                onTapMemoLink: { id in onOpenMemo(id) },
                onRequestMemoLink: { showMemoLinkPicker = true },
                onRequestPhoto: {
                    if CameraImagePicker.isAvailable { showPhotoSourceDialog = true }
                    else { showPhotoPicker = true }
                },
                proxy: bodyProxy
            )
        }
    }

    /// Conversations + C3 share-captures keep the legacy outer-scroll layout for
    /// now (phase 2), under the same pinned title row.
    private func legacyScrollPage<C: View>(@ViewBuilder content: () -> C) -> some View {
        VStack(spacing: 0) {
            pinnedTitleRow
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    noteHeaderCore(isCurrent: true)
                    content()
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, Theme.Space.margin)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    /// The shared metadata header — everything between the pinned title and the
    /// body, in the locked order chips → importance → summary → status → quote.
    /// Each piece guards itself, so all page kinds reuse it.
    /// `isCurrent` drives the hosted elements' accessibility identifiers:
    /// accessibility-hiding does NOT cross the UIKit hosting boundary (iOS 26
    /// toolchain), so an off-screen pager page suffixes its identifiers instead —
    /// XCUITest and VoiceOver then resolve exactly one "add-tag-button" etc.
    private func noteHeaderCore(isCurrent: Bool) -> some View {
        let suffix = isCurrent ? "" : "-offscreen"
        return VStack(alignment: .leading, spacing: 0) {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(metaChips) { chip in
                    ContextChip(text: chip.text, systemImage: chip.symbol)
                }
                ForEach(memo.tags, id: \.self) { tag in
                    // Opens the tag editor — the old tap DELETED the tag
                    // silently (review-1 finding).
                    Button { openTagEditor() } label: {
                        Text("#\(tag)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.skAccentText)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.skAccentSoft, in: .rect(cornerRadius: 7, style: .continuous))
                    }
                }
                // Reminder chip — visible whenever a reminder is set (future =
                // accent bell, past = faint); tap to change/remove.
                if let at = memo.remindAt {
                    Button { showReminderSheet = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: at > Date() ? "bell.fill" : "bell")
                                .font(.system(size: 9, weight: .semibold))
                            Text(at.formatted(.dateTime.day().month().hour().minute()))
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(at > Date() ? Color.skAccentText : Color.skTextFaint)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(at > Date() ? Color.skAccentSoft : Color.skElev,
                                    in: .rect(cornerRadius: 7, style: .continuous))
                    }
                    .accessibilityIdentifier("reminder-chip")
                }
                Button { openTagEditor() } label: {
                    Text("+ Tag")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.skTextDim)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.skElev, in: .rect(cornerRadius: 7, style: .continuous))
                }
                .accessibilityIdentifier("add-tag-button" + suffix)
            }

            // The 10-circle significance control (SignificanceCircles.swift —
            // mocks/significance-circles.html): tap circle N → 0.N, re-tap →
            // Not rated. Flag-to-send: 0 stays on the phone, >0 syncs.
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
                .accessibilityIdentifier("diarization-status" + suffix)
            }

            // Reading mode: transcription in flight → the body is read-only and
            // this pill says why (the old view-swap's status, now in the header).
            if !memo.isShareCapture, memo.transcriptStatus == .transcribing {
                StatusPill(style: .working, label: "Transcribing")
                    .padding(.top, 14)
            }

            if !memo.isShareCapture, memo.transcriptStatus == .failed,
               (memo.transcript ?? "").isEmpty {
                transcriptionFailedMessage
                    .padding(.top, 14)
            }

            // Audiobook capture: the styled, QUOTE-PROTECTED block above the
            // editable ramble — with live karaoke through the quote's words
            // during playback (they run from sidecar index 0).
            if let quote = memo.captureQuote {
                Group {
                    if player.isPlaying, !timings.isEmpty {
                        CaptureQuoteFrame(attribution: memo.quoteAttributionLabel) {
                            QuoteKaraokeText(text: quote.displayText, timings: timings,
                                             player: player, clock: player.clock)
                        }
                    } else {
                        CaptureQuoteBlock(quote: quote.displayText, attribution: memo.quoteAttributionLabel)
                    }
                }
                .padding(.top, 18)
            }
        }
    }

    private var transcriptionFailedMessage: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatusPill(style: .error, label: "Transcription failed", systemImage: "exclamationmark.triangle.fill")
            Text("It'll be transcribed on your Mac when you sync — or type it yourself below.")
                .font(.footnote).foregroundStyle(Color.skTextDim)
        }
    }

    /// Below-the-body footer inside the editor's scroll: the people row +
    /// "Linked from" backlinks.
    private func noteFooter(isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !spans.isEmpty {
                peopleInNoteRow
                    .accessibilityIdentifier(isCurrent ? "people-in-note-row" : "people-in-note-row-offscreen")
            }
            if !backlinks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("LINKED FROM")
                    ForEach(backlinks, id: \.id) { link in
                        Button { onOpenMemo(link.id) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.turn.up.left")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.skTextFaint)
                                Text(link.title)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.skText)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.skTextFaint)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(Color.skSurface, in: .rect(cornerRadius: Theme.Radius.field, style: .continuous))
                            .overlay(RoundedRectangle.sk(Theme.Radius.field).stroke(Color.skBorder, lineWidth: 1))
                        }
                        .accessibilityIdentifier(isCurrent ? "backlink-row" : "backlink-row-offscreen")
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Space.margin)
        .padding(.top, 4)
    }

    /// Who links HERE: scan every live memo's transcript for this memo's id.
    /// Cheap contains() pre-filter, exact via MemoLinkSyntax; off-main.
    private func recomputeBacklinks() {
        let myID = memo.id
        let others: [(UUID, String, String?)] = repository.allMemos()
            .filter { $0.id != myID }
            .map { ($0.id, $0.title ?? $0.firstTranscriptLine ?? "Untitled", $0.transcript) }
        Task.detached(priority: .utility) {
            let marker = "[[memo:\(myID.uuidString)"
            let found: [(id: UUID, title: String)] = others.compactMap { id, title, transcript in
                guard let t = transcript, t.contains(marker),
                      MemoLinkSyntax.targets(in: t).contains(myID) else { return nil }
                return (id: id, title: String(title.prefix(60)))
            }
            await MainActor.run { backlinks = Array(found.prefix(6)) }
        }
    }

    /// One downstream for both photo sources (camera + library): insert at the
    /// caret the accessory captured, mirror to CloudKit, OCR for search.
    private func insertPickedPhoto(_ image: UIImage) {
        bodyProxy.insertPhoto(image)
        AssetMaterializer.capture(memoID: memo.id, repository: repository)
        PhotoTextIndexer.run(repository)
    }

    /// Markup saved back into a photo/file: re-mirror to CloudKit (the
    /// size-change capture), re-OCR an inline photo (its manifest text resets
    /// to un-scanned), and rebuild the editor's thumbnail (mtime-keyed cache
    /// decodes fresh).
    private func photoWasEdited(_ target: QuickLookTarget) {
        if let n = target.marker,
           var meta = memo.metadata, var manifest = meta.imageManifest,
           n >= 1, n <= manifest.count {
            manifest[n - 1].text = nil
            meta.imageManifest = manifest
            memo.metadata = meta
            repository.save()
        }
        AssetMaterializer.capture(memoID: memo.id, repository: repository)
        PhotoTextIndexer.run(repository)
        bodyProxy.refreshAttachments()
    }

    /// Everything linkable from here: most recent first, self excluded.
    private func memoLinkCandidates() -> [(id: UUID, title: String, subtitle: String)] {
        repository.allMemos()
            .filter { $0.id != memo.id }
            .map { m in
                (id: m.id,
                 title: (m.title ?? m.firstTranscriptLine ?? "Untitled").trimmingCharacters(in: .whitespaces),
                 subtitle: MemoDate.label(m.recordedAt))
            }
    }

    /// Conversation body — speaker-attributed turns. The per-tick karaoke state
    /// is isolated in `ConversationTurnsSection` so only that subtree re-renders
    /// on the player clock, not this page.
    @ViewBuilder private var conversationContent: some View {
        if let turns = SpeakerTranscript.parse(memo.transcript) {
            ConversationTurnsSection(
                player: player, clock: player.clock, timings: timings, turns: turns,
                tapToSeek: tapToSeek,
                onTag: startAssigning(_:_:),
                onSeek: seekToWord,
                onEditText: editTurnText,
                imageURL: turnImageURL
            )
            .padding(.top, 18)
        }
    }

    /// C3 capture-item body — pinned source block + annotation editor (legacy).
    @ViewBuilder private var captureContent: some View {
        captureSourceBlock
            .padding(.top, 18)
        captureAnnotationSection
            .padding(.top, 14)
    }

    /// Re-derive the name tiers off-main (pure Sanitiser scan). Ordinary voice
    /// memos only — captures show a quote block, conversations route to
    /// SpeakerTurnsView.
    private func recomputeSpans() {
        guard !people.isEmpty, !memo.isShareCapture, memo.captureQuote == nil,
              SpeakerTranscript.parse(memo.transcript) == nil else {
            spans = []
            return
        }
        let text = activeBodyText
        let roster = people
        let never = Set(memo.nameResolutions.unlinkedNames)
        let picks = memo.nameResolutions.namePicks
        Task.detached(priority: .userInitiated) {
            let result = Sanitiser.nameSpans(inRaw: text, people: roster,
                                             neverLink: never, namePicks: picks)
            await MainActor.run { spans = result }
        }
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

    private func openTagEditor() {
        libraryTags = repository.allTags()
        showTagEditor = true
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
        recomputeSpans()
    }
    private func applyKeepPlain(_ alias: String) {
        memo.keepNamePlain(alias: alias); repository.save()
        recomputeSpans()
    }
    /// Unlink a LINKED name → plain, with a reversible Undo toast restoring the exact
    /// prior resolutions (the pick / auto-link), not just the default tier.
    private func applyUnlink(_ span: NameSpan) {
        let prior = memo.nameResolutions
        memo.keepNamePlain(alias: span.alias); repository.save()
        recomputeSpans()
        let alias = span.alias
        withAnimation(Theme.Motion.spring) {
            undoToast = NameUndoToast(message: "Unlinked — “\(alias)” is plain text here") {
                memo.nameResolutions = prior
                memo.markEdited(); repository.save()
                recomputeSpans()
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
        Set(spans.filter { $0.tier == .linked }.compactMap { $0.canonical?.lowercased() }).count
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
    }

    /// One candidate person for the note, with the alias they go by here + whether they're
    /// currently linked. Built from the spans (union of every span's candidates).
    private struct PersonChip: Identifiable {
        let id: String; let canonical: String; let display: String; let alias: String; let linked: Bool
    }

    private var noteCandidateChips: [PersonChip] {
        var aliasFor: [String: String] = [:], displayFor: [String: String] = [:]
        var order: [String] = [], linkedSet = Set<String>()
        for span in spans {
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
        recomputeSpans()
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
                Button {
                    if let url = memo.sharedFileURL {
                        quickLookTarget = QuickLookTarget(url: url, marker: nil)
                    }
                } label: {
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

// MARK: - Conversation turns (per-tick isolation)

/// Hosts `SpeakerTurnsView` and owns the karaoke tick: it observes the player
/// CLOCK, so during playback only this subtree re-evaluates per position change —
/// the page above it re-renders only on rare player state (play/pause).
private struct ConversationTurnsSection: View {
    @ObservedObject var player: AudioPlayerModel
    @ObservedObject var clock: PlayerClock
    let timings: [WordTiming]
    let turns: [SpeakerTranscript.Turn]
    let tapToSeek: Bool
    let onTag: (Int, String) -> Void
    let onSeek: (Int) -> Void
    let onEditText: (Int, String) -> Void
    let imageURL: (Int) -> URL?

    var body: some View {
        SpeakerTurnsView(
            turns: turns,
            onTag: onTag,
            activeWord: (player.isPlaying && !timings.isEmpty)
                ? Karaoke.activeWordIndex(timings, at: clock.time) : nil,
            tapToSeek: tapToSeek,
            onSeek: onSeek,
            onEditText: onEditText,
            imageURL: imageURL
        )
    }
}

// MARK: - Player bar

private struct PlayerBar: View {
    @ObservedObject var player: AudioPlayerModel
    // Position ticks are observed HERE only — the page tree above stays out of
    // the 20 Hz re-render loop (note-editing study 2026-07-06).
    @ObservedObject var clock: PlayerClock

    var body: some View {
        // The COMPACT pill (signed-off spec, −60% height): play · ±10 s ·
        // scrubber with times · speed — one ~44 pt row. The whole scrubber
        // zone is the drag target (no more fishing for a 3-pt slider).
        HStack(spacing: 10) {
            Button { player.togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.skAccent, in: .circle)
                    .shadow(color: .skAccent.opacity(0.38), radius: 5, y: 3)
            }
            .accessibilityIdentifier("play-button")
            .disabled(!player.hasAudio)

            Button { player.skip(-10) } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.skText)
                    .frame(width: 26, height: 32)
            }
            .accessibilityIdentifier("skip-back-button")

            Button { player.skip(10) } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.skText)
                    .frame(width: 26, height: 32)
            }
            .accessibilityIdentifier("skip-fwd-button")

            Text(timeString(clock.time))
                .font(.system(size: 10.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.skTextDim)

            scrubber

            Text(timeString(player.duration))
                .font(.system(size: 10.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.skTextDim)

            Button { player.cycleRate() } label: {
                Text(rateLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.skText)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(Color.skSurface, in: .rect(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle.sk(8).stroke(Color.skBorder, lineWidth: 1))
            }
            .accessibilityIdentifier("speed-button")
        }
        .frame(height: 40)
    }

    /// Thin progress line with a knob; the FULL-HEIGHT zone around it accepts
    /// the scrub drag.
    private var scrubber: some View {
        GeometryReader { geo in
            let progress = player.duration > 0 ? min(max(clock.time / player.duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14)).frame(height: 3.5)
                Capsule().fill(Color.skAccent)
                    .frame(width: max(3.5, geo.size.width * progress), height: 3.5)
                Circle().fill(.white)
                    .frame(width: 11, height: 11)
                    .offset(x: geo.size.width * progress - 5.5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard player.duration > 0 else { return }
                        player.seek(to: (v.location.x / geo.size.width) * player.duration)
                    }
            )
        }
        .frame(height: 40)
        .disabled(!player.hasAudio)
        .accessibilityIdentifier("player-scrubber")
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

// MARK: - Share sheet (share note OUT — survey fold)

/// Markdown/word-count helpers for sharing a note out. Pure, unit-testable.
enum MemoShare {
    /// "# Title\n\nbody" with `[[img_NNN]]` markers stripped (they mean
    /// nothing outside the app; the photos travel as files when needed).
    static func markdown(title: String?, body: String) -> String {
        let cleaned = body
            .replacingOccurrences(of: #"\[\[img_\d+\]\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title = title?.trimmingCharacters(in: .whitespaces), !title.isEmpty else { return cleaned }
        return "# \(title)\n\n\(cleaned)"
    }

    /// Spoken-word count — markers aren't words.
    static func wordCount(of transcript: String?) -> Int {
        guard let t = transcript else { return 0 }
        return t.replacingOccurrences(of: #"\[\[img_\d+\]\]"#, with: " ", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace }).count
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
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
