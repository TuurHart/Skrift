import SwiftUI
import SwiftData
import UIKit
import QuickLook
import PhotosUI
import FluidAudio

// MARK: - One page

private struct MemoPageView: View {
    @Bindable var memo: Memo
    @ObservedObject var player: AudioPlayerModel
    /// Whether this page is the pager's current page — off-screen neighbours
    /// hide their UIKit editor subtree from accessibility (see NoteBodyView).
    var isCurrent: Bool = true
    /// iPad: at regular width the Connections panel stands beside the page, so the
    /// inline footer omits related/backlinks and the body caps to the reading measure.
    @Environment(\.horizontalSizeClass) private var hSize
    private let repository = NotesRepository.shared
    /// One corpus scan per open (never per row) — feeds the lifecycle line's
    /// touch check (backlinked notes never fade).
    @State private var detailBacklinkedIDs: Set<UUID> = []
    /// What the QuickLook viewer is showing: an inline photo (marker set — an
    /// edit re-mirrors + re-OCRs it) or a shared-document capture (marker nil).
    struct QuickLookTarget: Identifiable {
        let url: URL
        var marker: Int?
        var id: String { url.path }
    }
    /// UIKit-presented viewer (P2#12): zoom transition off the tapped photo +
    /// markup save-back; edits are reported on dismissal only (erase-crash fix).
    @State private var markupQuickLook = MarkupQuickLook()
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
    /// A tag removal's Undo pill — hoisted here (Q41) so it renders at the PAGE
    /// level (`tagToastView`'s own `.overlay`), not `TagEditorRow`'s own bounds
    /// (which ran the pill off the left screen edge, Q36 finding).
    @State private var tagToast: TagEditorRow.TagToast?
    /// Q44: the tag toast's own screen already backs off for the keyboard (standard
    /// SwiftUI avoidance shrinks this Group's frame), so the fixed 96pt "clear the
    /// player" padding must drop to a hairline once a keyboard is up — otherwise the
    /// two paddings stack and the pill floats mid-screen over the Importance card.
    @State private var keyboardVisible = false
    @State private var personSheet: PersonSheetRequest?
    @State private var showPeopleSheet = false
    // Phase 4 — the polish (Mac write-back / phone edits), shown as the editable body.
    // A LIVE @Query, not @State + .task: the pager's LazyHStack can realize a page
    // during a programmatic scroll WITHOUT delivering its appear events (devlog-proven
    // on device: search-result opens never ran the .task, so the body stayed RAW —
    // the 2026-07-10 "truncated transcript" P0). @Query renders right on the first
    // body eval and live-updates when a polish arrives over CloudKit, which also
    // retires the onChange(sync.isSyncing) refetch hack.
    @Query private var enhancements: [MemoEnhancement]
    @State private var showTitleChooser = false
    @FocusState private var titleFocused: Bool

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
    /// Track B: the full extracted-PDF-text reader (wave-2 mock m3).
    @State private var showPDFTextReader = false
    /// Reminder chip → the sheet (chunk 7).
    @State private var showReminderSheet = false
    @State private var backlinks: [(id: UUID, title: String)] = []
    /// P8 Related card (chunk 7): semantic neighbours — loaded only while the
    /// journal index is active; the card is HIDDEN when nothing clears the floor
    /// (never an empty placeholder).
    @State private var relatedMemos: [Memo] = []
    /// Jump the pager to another memo (link chips + backlink rows).
    var onOpenMemo: (UUID) -> Void = { _ in }

    @ObservedObject private var lockGate = LockGate.shared

    init(memo: Memo, player: AudioPlayerModel, isCurrent: Bool = true,
         onOpenMemo: @escaping (UUID) -> Void = { _ in }) {
        self.memo = memo
        self.player = player
        self.isCurrent = isCurrent
        self.onOpenMemo = onOpenMemo
        let id = memo.id
        _enhancements = Query(filter: #Predicate<MemoEnhancement> { $0.memoID == id },
                              sort: \MemoEnhancement.enhancedAt, order: .reverse)
    }

    var body: some View {
        // Note-editing overhaul (spec mocks/note-editor-redesign.html): B2 pinned
        // title above every page kind; monologue memos (incl. audiobook captures +
        // polished bodies) get the re-founded scrolling editor page — the text view
        // owns the scroll, the metadata header scrolls inside it. Conversations and
        // C3 share-captures keep their legacy scroll layout for now (phase 2).
        Group {
            if lockGate.isLocked(memo) {
                lockedPlaceholder
            } else if memo.isShareCapture && !isInlineImageCapture {
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
            recomputeSpans()
            recomputeBacklinks()
            // One corpus scan for the lifecycle line's touch check.
            detailBacklinkedIDs = MemoLifecycle.backlinkedIDs(in: repository.allMemos())
            await loadRelated()
        }
        // The arc of this idea (P8) — from the Related card's CTA.
        // A polish can arrive/change via CloudKit while the screen is open — the
        // @Query updates the body live; re-derive the name tiers over the new text.
        .onChange(of: macPolish?.copyedit) { _, _ in recomputeSpans() }
        // Transcript can change outside the editor (transcription lands, append,
        // speaker edits) — re-derive the tiers.
        .onChange(of: memo.transcript) { _, _ in recomputeSpans() }
        .sheet(isPresented: $showReminderSheet) {
            ReminderSheet(memo: memo) { repository.save() }
        }
        // Shared-document (.file) capture → preview the PDF/doc in QuickLook —
        // and the editor's inline photos (tap a photo → viewer).
        // The photo/file viewer is UIKit-presented (MarkupQuickLook, P2#12) —
        // no SwiftUI cover here: the zoom transition needs transitionViewFor,
        // which a cover can't provide. Markup + the dismissal-deferred edit
        // chain live in the presenter.
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
        // Tag removal → its own Undo toast (Q41), centred on the whole page.
        .overlay(alignment: .bottom) { tagToastView }
        // Q44: the toast anchors above the player (keyboard down) OR above the
        // keyboard's accessory bar (keyboard up) — never floating mid-screen.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
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

    /// COMPACT-width processing line. At regular width the note BAR owns this
    /// (signed mock A) — here it stays as the phone/narrow surface.
    @ViewBuilder private var polishStatusBand: some View {
        let phase = PolishCenter.shared.phase(for: memo.id)
        if hSize != .regular, let line = phase.line {
            HStack(spacing: 8) {
                if case .failed = phase {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .semibold))
                    Text(line).font(.system(size: 12))
                    Spacer(minLength: 4)
                    Button("Retry") { PolishCenter.shared.polishNow(memo) }
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityIdentifier("ipad-polish-retry")
                } else {
                    if let f = phase.fraction {
                        ProgressView(value: f).progressViewStyle(.linear)
                            .frame(width: 70).tint(Color.skAccentText)
                    }
                    Text(line).font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.skAccentText)
                }
            }
            .foregroundStyle({ if case .failed = phase { Color.skRed } else { Color.skAccentText } }())
            .padding(.horizontal, Theme.Space.margin)
            .padding(.top, 8).padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("ipad-polish-status")
        }
    }


    /// An image capture whose text has landed renders through the NORMAL note
    /// body (round-2 device spec 2026-07-10: photos inline in the text via the
    /// [[img_NNN]] pipeline, "like my Monday 22:34 note — just do that"). The
    /// drain writes the markers into the annotation; `captureAnnotationBinding`
    /// makes the body edit annotationText instead of the transcript.
    private var isInlineImageCapture: Bool {
        memo.sharedContent?.type == .image && memo.transcriptStatus == .done
    }

    private var captureAnnotationBinding: Binding<String> {
        Binding(
            get: { memo.annotationText ?? "" },
            set: { memo.annotationText = $0.isEmpty ? nil : $0 }
        )
    }

    /// The re-founded monologue page: ONE scrolling text view is the body; the
    /// metadata header (chips/importance/summary/diar/quote) and the people-row
    /// footer scroll INSIDE it. Native selection/caret/undo mechanics throughout.
    private var editorPage: some View {
        VStack(spacing: 0) {
            pinnedTitleRow
            polishStatusBand
            NoteBodyView(
                memo: memo,
                player: player,
                nameSpans: spans,
                onTapName: { resolveTarget = NameResolveTarget(span: $0) },
                polishedBinding: isInlineImageCapture ? captureAnnotationBinding : polishedBinding,
                onCommit: { wordsChanged in
                    // C98: a `.polished` commit already stamped itself via
                    // `recordPolishedEdit` — don't ALSO stamp the untouched raw words.
                    memo.markEdited(stampWords: wordsChanged)
                    repository.save()
                    // recomputeSpans() is NOT called here (Q53/C277/C282): committing
                    // sets either `memo.transcript` (.raw) or `macPolish?.copyedit`
                    // (.polished) above, and `.onChange` on each (932/935) already
                    // fires it — calling it here too ran the name-span scan twice
                    // per commit.
                },
                header: AnyView(VStack(alignment: .leading, spacing: 0) {
                    noteHeaderCore(isCurrent: isCurrent)
                        .padding(.horizontal, Theme.Space.margin).padding(.top, 6)
                    // E1/B3: the typed thought (video sheet) or bundled chat text
                    // (mixed share) LEADS the note, above the transcript — signed
                    // mock share-ingest-wave2 m1. Captures keep their own layout
                    // (there the annotation IS the body).
                    if !memo.isShareCapture, let thought = memo.annotationText,
                       !thought.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(thought)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.skTextDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Theme.Space.margin)
                            .padding(.top, 10)
                            .accessibilityIdentifier("annotation-lead")
                    }
                }
                    .accessibilityHidden(!isCurrent)),
                footer: AnyView(noteFooter(isCurrent: isCurrent, includeConnections: hSize != .regular)
                    .accessibilityHidden(!isCurrent)),
                a11yHidden: !isCurrent,
                onTapImage: { n in
                    guard let url = memo.imageURL(markerIndex: n) else { return }
                    let target = QuickLookTarget(url: url, marker: n)
                    markupQuickLook.present(url: url, anchor: bodyProxy.photoAnchor(marker: n)) { edited in
                        if edited { photoWasEdited(target) }
                    }
                },
                onTapMemoLink: { id in onOpenMemo(id) },
                onRequestMemoLink: { showMemoLinkPicker = true },
                linkTitle: { liveLinkTitle($0) },
                onRequestPhoto: {
                    if CameraImagePicker.isAvailable { showPhotoSourceDialog = true }
                    else { showPhotoPicker = true }
                },
                proxy: bodyProxy,
                // iPad regular width: size inline images to the 640 reading column,
                // not the full screen (the note column is reading-measure-capped).
                readingWidthCap: hSize == .regular ? Adaptive.readingMaxWidth : nil
            )
        }
    }

    /// Conversations + C3 share-captures keep the legacy outer-scroll layout for
    /// now (phase 2), under the same pinned title row.
    private func legacyScrollPage<C: View>(@ViewBuilder content: () -> C) -> some View {
        VStack(spacing: 0) {
            pinnedTitleRow
            polishStatusBand
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
            }

            // Tags — their OWN row under the title (D139 pick 3, signed mock
            // `mocks/tag-ui-revamp.html`), no sheet: `+ tag` turns into an inline
            // field, comma/Return commits, tap-arms-then-removes with a 4 s Undo.
            TagEditorRow(tags: $memo.tags, library: repository.allTags(),
                         style: .phone, onChanged: { memo.markEdited(); repository.save() },
                         idSuffix: suffix,
                         // Q41: the toast is HOISTED to the page's own overlay
                         // (`tagToastView`, below) so it centres on the whole
                         // screen, not this row's own narrower bounds.
                         onToast: { tagToast = $0 })
                .padding(.top, 8)

            // The 10-circle significance control (SignificanceCircles.swift —
            // mocks/significance-circles.html): tap circle N → 0.N, re-tap →
            // Not rated. Flag-to-process: 0 = the Mac ignores it, >0 = polish.
            SignificanceCircles(value: $memo.significance) {
                repository.save()
                // Print-to-wall: an orange-tier rating enqueues a card (once, ever).
                WallPrinter.shared.ratingCommitted(memo, repository: repository)
            }
                .padding(.top, 14)

            // WHERE this note goes when it leaves — the shared `DestinationRowView`
            // (signed mock note-destination-tags.html, version B collapsed). It sits
            // HERE, right under importance, because the two are the same kind of
            // decision: importance says whether a note may leave Skrift, destination
            // says where. Hidden entirely until destinations are switched on, so the
            // default build is unchanged.
            if DestinationSettings.isEnabled, memo.deletedAt == nil {
                DestinationRowView(
                    destination: Binding(get: { memo.destination },
                                         set: { memo.destination = $0 }),
                    folderLabel: { $0.archiveFolder.map { "\($0)/" } },
                    onPick: { _ in
                        memo.markEdited(stampWords: false)   // destination isn't title/body/tags (C98)
                        repository.save()
                    },
                    style: .phone)
                    .padding(.top, 12)
                    .accessibilityIdentifier("destination-row")
            }

            // The note narrates its own lifecycle (2026-07-21 — new-user
            // discoverability without a tour): a clock-run note quietly says
            // when it starts fading and how to keep it, exactly where the rule
            // applies. One clock (2026-07-22): touches only restart the clock,
            // so the line stays for touched notes too — only rating/holds hide it.
            if memo.deletedAt == nil, memo.transcriptStatus == .done,
               !MemoLifecycle.neverFades(memo, backlinked: detailBacklinkedIDs) {
                Text("\(MemoSpine.oneLiner(for: MemoSpine.station(for: .from(memo, backlinked: detailBacklinkedIDs)))) — rate it to keep it")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.skAmber.opacity(0.9))
                    .padding(.top, 8)
                    .accessibilityIdentifier("detail-lifecycle-line")
            }

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
    /// "Linked from" backlinks + the Related card. `includeConnections` is false
    /// at regular width — related + backlinks move into the standing Connections
    /// panel (the people row always stays with the note).
    private func noteFooter(isCurrent: Bool, includeConnections: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !spans.isEmpty {
                peopleInNoteRow
                    .accessibilityIdentifier(isCurrent ? "people-in-note-row" : "people-in-note-row-offscreen")
            }
            if includeConnections, !backlinks.isEmpty {
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
            if includeConnections, !relatedMemos.isEmpty {
                relatedSection(isCurrent: isCurrent)
            }
        }
        .padding(.horizontal, Theme.Space.margin)
        .padding(.top, 4)
    }

    /// P8 Related card (mock screen 6): up to `relatedK` semantic neighbours.
    /// The "View thread" CTA is GONE (Tuur 2026-07-25, after the iPad retirement:
    /// "remove it from the phone too, keep the apps looking the same") — Date mode
    /// in Connections is the arc, on every platform.
    private func relatedSection(isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("RELATED")
            ForEach(relatedMemos, id: \.id) { rel in
                Button { onOpenMemo(rel.id) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.skTextFaint)
                        Text(rel.displayTitle)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.skText)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(LookbackProvider.journalDate(rel).formatted(.dateTime.day().month(.abbreviated)))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.skTextFaint)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Color.skSurface, in: .rect(cornerRadius: Theme.Radius.field, style: .continuous))
                    .overlay(RoundedRectangle.sk(Theme.Radius.field).stroke(Color.skBorder, lineWidth: 1))
                }
                .accessibilityIdentifier(isCurrent ? "related-row" : "related-row-offscreen")
            }
        }
    }

    /// Semantic neighbours for the Related card — no-op unless the journal
    /// index is active (the card stays invisible for everyone else).
    private func loadRelated() async {
        guard JournalIndexService.shared.isActive else { return }
        let scores = await JournalIndexService.shared.relatedScores(to: memo.id, repository: repository)
        let byID = Dictionary(repository.allMemos().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        relatedMemos = JournalIndexService.relatedResults(
            scores: scores, excluding: [memo.id], memosByID: byID,
            floor: RetrievalTuning.relatedFloor, limit: RetrievalTuning.relatedK)
    }

    /// Who links HERE: scan every live memo's transcript for this memo's id.
    /// Cheap contains() pre-filter, exact via MemoLinkSyntax; off-main.
    private func recomputeBacklinks() {
        let myID = memo.id
        // A memo-link can live in the raw transcript OR the Mac's polished copyedit — a Mac-made
        // link syncs into the enhancement, not the transcript (2026-07-15 device finding: the Mac
        // showed the backlink, the phone didn't because it only scanned transcripts). Scan BOTH.
        let copyeditByID = Dictionary(
            repository.allEnhancements().map { ($0.memoID, $0.copyedit) },
            uniquingKeysWith: { a, _ in a })
        let others: [(UUID, String, String)] = repository.allMemos()
            .filter { $0.id != myID }
            .map { m in
                let body = [m.transcript, copyeditByID[m.id]]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: "\n")
                return (m.id, m.title ?? m.firstTranscriptLine ?? "Untitled", body)
            }
        Task.detached(priority: .utility) {
            let marker = "[[memo:\(myID.uuidString)"
            let found: [(id: UUID, title: String)] = others.compactMap { id, title, body in
                guard body.contains(marker), MemoLinkSyntax.targets(in: body).contains(myID) else { return nil }
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

    /// A memo-link target's CURRENT title (same rule as the picker), so chips show the live
    /// title instead of the snapshot frozen at creation. nil when the target isn't in the
    /// library → the chip keeps its snapshot. Called on display rebuild, not per keystroke.
    private func liveLinkTitle(_ id: UUID) -> String? {
        guard let m = repository.allMemos().first(where: { $0.id == id }) else { return nil }
        // Only a REAL title overrides the chip's snapshot. A capture / Maps note with no title +
        // no transcript would otherwise resolve to "Untitled" and CLOBBER the good snapshot the
        // link was made with (2026-07-15 device finding) — return nil so the snapshot stays.
        let t = (m.title ?? m.firstTranscriptLine)?.trimmingCharacters(in: .whitespaces)
        return (t?.isEmpty == false) ? t : nil
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
                // Resolved HERE, where the roster already lives: the shared slot rule needs
                // `people` to know that a speaker's `[[Tiuri Hartog]]` header and their later
                // `Tiuri` are one voice. Off the per-tick path (the section isolates that).
                speakerSlots: SpeakerTurnStyle.slots(forParsedNames: turns.map(\.name), people: people),
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
    /// Image captures invert the order (round-1 device feedback 2026-07-10:
    /// photos read as huge banners stacked ABOVE the text — "I want them in
    /// line"): the annotation reads first, the photos flow below it at
    /// note-body size, like a recorded memo's inline photos.
    @ViewBuilder private var captureContent: some View {
        if memo.sharedContent?.type == .image {
            captureAnnotationSection
                .padding(.top, 18)
            captureSourceBlock
                .padding(.top, 14)
        } else {
            captureSourceBlock
                .padding(.top, 18)
            captureAnnotationSection
                .padding(.top, 14)
        }
        // Track B (wave-2 mock m4): ramble by VOICE — the words append to the
        // annotation. Audio-less captures only; a transcribing dictation keeps
        // its own status row above.
        if memo.audioFilename.isEmpty, memo.transcriptStatus != .transcribing {
            CaptureVoiceAnnotate(memo: memo, repository: repository)
                .padding(.top, 16)
        }
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
        memo.markEdited()
        repository.save()
    }

    /// Commit an inline edit to one turn's text (fix a word, move a boundary word).
    private func editTurnText(at index: Int, to newText: String) {
        guard let updated = SpeakerTranscript.setText(memo.transcript, turnAt: index, to: newText),
              updated != memo.transcript else { return }
        memo.transcript = updated
        memo.transcriptUserEdited = true       // Mac trusts the edited transcript
        memo.markEdited()
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
        memo.markEdited()
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
        let clip = SpeakerAudio.clip(data.segments.filter { $0.speaker == slot }, from: samples)
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

    // MARK: - Mac polish (Phase 4)

    /// The polish to SHOW — only for an ordinary monologue voice memo (captures keep
    /// their quote block; conversations route to `SpeakerTurnsView`). nil = show raw.
    /// Newest `enhancedAt` first via the @Query sort — mirrors `repository.enhancement`.
    private var macPolish: MemoEnhancement? {
        guard let e = enhancements.first, e.hasContent,
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
                guard newValue != e.copyedit else { return }
                e.copyedit = newValue
                e.enhancedByDeviceID = DeviceID.current()
                e.enhancedAt = Date()
                // C98 (Q38): a typed edit of the polished body is a words edit for
                // conflict detection. Next main-queue turn, like `markEdited`'s stamp.
                let m = self.memo
                DispatchQueue.main.async {
                    guard !m.isDeleted, let ctx = m.modelContext else { return }
                    if EditConflicts.recordPolishedEdit(m, in: ctx), ctx.hasChanges { try? ctx.save() }
                }
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
                memo.markEdited(stampWords: false); repository.save()   // nameResolutions (C98)
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

    @ViewBuilder private var tagToastView: some View {
        if let toast = tagToast {
            TagUndoToastView(tag: toast.tag, style: .phone, onUndo: {
                toast.undo()
                withAnimation(Theme.Motion.spring) { tagToast = nil }
            })
            // Keyboard down: this Group's frame runs to the real screen bottom, so
            // 96pt clears the floating player bar. Keyboard up: standard SwiftUI
            // avoidance already shrinks the Group's frame to end right above the
            // keyboard's accessory bar; MORE padding here moves the pill UP the
            // screen (toward the note body, not away from it) — 96 stacked on top of
            // that shrink is what put it mid-screen over the Importance card (Q41
            // finding). A hairline hugs the player bar, the correct direction to
            // clear scrolled-up transcript text below it.
            .padding(.bottom, keyboardVisible ? 6 : 96)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: toast.id) {
                try? await Task.sleep(for: .seconds(4))
                if tagToast?.id == toast.id { withAnimation(Theme.Motion.spring) { tagToast = nil } }
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
            chips.append(MetaChip(text: SourceKind.video.label, symbol: SourceKind.video.glyph))
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
                // A PDF (doc scan / shared) renders INLINE — first page as a
                // block, "N pages" chip, tap → viewer (signed-off mock
                // pdf-inline-capture.html A: "text, PDF, text", Notes idiom).
                // Non-PDF files and unreadable PDFs keep the card.
                if let url = memo.sharedFileURL, url.pathExtension.lowercased() == "pdf",
                   let entry = PDFThumbnailLoader.firstPage(
                       at: url, maxWidth: UIScreen.main.bounds.width - 2 * Theme.Space.margin) {
                    CapturePDFInlineBlock(entry: entry) {
                        let target = QuickLookTarget(url: url, marker: nil)
                        markupQuickLook.present(url: url, anchor: nil) { edited in
                            if edited { photoWasEdited(target) }
                        }
                    }
                    // Track B (wave-2 mock m3): the A6-extracted text, in the
                    // note — collapsed by default, reader on "Show all".
                    if let pdfText = sc.text, !pdfText.isEmpty {
                        PDFTextDisclosure(text: pdfText, pageCount: entry.pageCount) {
                            showPDFTextReader = true
                        }
                        .sheet(isPresented: $showPDFTextReader) {
                            PDFTextReaderView(title: sc.fileName ?? "PDF text", text: pdfText)
                        }
                    }
                } else {
                    captureFileCard(sc: sc)
                }
            }
        }
    }

    /// A NON-PDF shared document capture (or an unreadable PDF): a card showing
    /// the filename + an Open button that previews it in QuickLook.
    /// (2026-06-21 "share a PDF and have it live in there"; PDFs themselves
    /// render inline since 2026-07-07 — CapturePDFInlineBlock.)
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
                    guard let url = memo.sharedFileURL else { return }
                    let target = QuickLookTarget(url: url, marker: nil)
                    markupQuickLook.present(url: url, anchor: nil) { edited in
                        if edited { photoWasEdited(target) }
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

    /// A shared link's thumbnail, downloaded on drain (A1 enrichment). The field
    /// holds a RELATIVE recordings filename; legacy remote-url values are ignored
    /// (offline rule — never fetch at render).
    private var linkThumbnail: UIImage? {
        guard let name = memo.sharedContent?.urlThumbnailUrl, !name.isEmpty,
              !name.contains("://") else { return nil }
        return UIImage(contentsOfFile: AppPaths.recordingsDirectory.appendingPathComponent(name).path)
    }

    private func captureURLCard(sc: SharedContent) -> some View {
        HStack(spacing: 10) {
            // A1: the og:image thumb when enrichment fetched one; globe otherwise.
            if let thumb = linkThumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.skAccent.opacity(0.13))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "globe")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.skAccent)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(sc.urlTitle ?? memo.shareCaptureURLDomain ?? "Link")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.skText)
                    .lineLimit(2)
                // A1: the page's own description, when enrichment found one.
                if let desc = sc.urlDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.skTextDim)
                        .lineLimit(2)
                }
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

    /// Shared text renders as the AUDIOBOOK-QUOTE idiom (locked rule 2026-07-12:
    /// shared inputs NEVER get bubble/box chrome): accent left bar, italic quote
    /// at note-body size, borderless — it flows in the note, not in a card.
    private func captureTextQuote(text: String) -> some View {
        Text(text)
            .font(.system(size: 15).italic())
            .lineSpacing(4)
            .foregroundStyle(Color.skText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 14)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.25)
                    .fill(Color.skAccent.opacity(0.6))
                    .frame(width: 2.5)
            }
            .accessibilityIdentifier("capture-text-quote")
    }

    @ViewBuilder private var captureImageEmbed: some View {
        if let filename = memo.sharedContent?.fileName,
           let img = UIImage(contentsOfFile: AppPaths.recordingsDirectory.appendingPathComponent(filename).path) {
            captureImage(img)
        } else if let manifest = memo.metadata?.imageManifest, !manifest.isEmpty {
            // Look up via the image manifest (the drain copies the images to the
            // recordings dir under the manifest filenames). A multi-photo share
            // (B2 — always one note) stacks EVERY photo in order.
            VStack(alignment: .leading, spacing: 8) {
                ForEach(manifest, id: \.filename) { entry in
                    let manifestURL = AppPaths.recordingsDirectory.appendingPathComponent(entry.filename)
                    if let img = UIImage(contentsOfFile: manifestURL.path) {
                        captureImage(img)
                    }
                }
            }
        }
    }

    /// One capture photo at note-body size (≤320 pt tall, same cap as inline
    /// [[img]] photos — round-1: full-width scaledToFit portraits were huge).
    private func captureImage(_ img: UIImage) -> some View {
        Image(uiImage: img)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 320)
            .clipShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle.sk(Theme.Radius.card).stroke(Color.skBorder, lineWidth: 1)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("capture-image-embed")
    }

    /// The annotation body for C3 captures — editable, writes back to
    /// `memo.annotationText` (NOT the transcript). If no annotation yet,
    /// shows a placeholder prompt. While a dictated voice note is still
    /// transcribing, the editor is swapped for a status row — an open draft
    /// would clobber the landing text (same window the append flow closes).
    @ViewBuilder private var captureAnnotationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // NO section label, NO box (locked rule 2026-07-12: shared inputs
            // never get bubble chrome) — the annotation IS the note body and
            // reads like one.
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
