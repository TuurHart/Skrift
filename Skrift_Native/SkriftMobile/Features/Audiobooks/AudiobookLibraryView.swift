import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The Library tab (Q6 mock; was the Books tab, Bound-inspired; root tab since 2026-06-19,
/// Library→Books 2026-07-06, Books→Library Q352): import from Files/iCloud, covers,
/// sort + status filters (default: recently played), per-book resume with
/// time-left, swipe-delete (captures survive — they're ordinary memos with
/// their own audio). Tapping a book PLAYS it (2026-07-06) — the full player
/// opens already running. The global mini-player capsule (AppTabView) shows
/// the session here too, so the row keeps only the current-book tint.
struct AudiobookLibraryView: View {
    @ObservedObject private var store = AudiobookLibraryStore.shared
    private var session = AudiobookSession.shared
    @ObservedObject private var cloudSync = CloudSyncMonitor.shared
    /// iPad wave: regular width trades the 54pt rows for a cover shelf (grid).
    /// Compact (incl. a split-view/Stage-Manager iPad) keeps today's List.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isRegular: Bool { horizontalSizeClass == .regular }
    /// Live re-align state, so a matching-up book never reads as a frozen app.
    @ObservedObject private var textActivity = BookTextActivity.shared

    /// Sort choice, persisted app-wide; the header chip is the control.
    @AppStorage("bookSortRaw") private var sortRaw = BookSort.recentlyPlayed.rawValue
    /// Status filter (transient, like the Notes funnel): nil = all books.
    @State private var statusFilter: BookStatusFilter?
    private var sort: BookSort { BookSort(rawValue: sortRaw) ?? .recentlyPlayed }

    @State private var showImporter = false
    /// Q353: the "Podcast or episode" door: paste a link, Skrift finds the public feed.
    @State private var showPodcastSheet = false
    @State private var importing = false
    @ObservedObject private var openInBridge = BookFileImportBridge.shared
    @State private var openInQueue: [URL] = []
    @State private var pendingImport: PendingAudiobookImport?
    @State private var importError: String?
    /// Partial-import notice: the book imported but N parts were skipped (unreadable).
    @State private var importNotice: String?
    @State private var showPlayer = false
    /// Q354: the "ePub or PDF" door's picker, and the PDF a tapped tile opens (`LibraryPDFHost`).
    @State private var showPDFImporter = false
    @State private var pdfReaderBook: Audiobook?
    /// A0 (mock book-text-unified.html): the once-per-book "Give this book text"
    /// prompt, presented right after an import confirms. `a0Candidate` parks the
    /// just-imported book until the confirm sheet is off-screen — presenting from
    /// the import sheet's onDismiss avoids the iOS sheet-swap race.
    @State private var giveTextBook: Audiobook?
    @State private var a0Candidate: Audiobook?
    @State private var a0AddHandoff: Audiobook?
    /// Bumped when a book's sync toggle flips, so the row's cloud glyph re-renders
    /// (sync state lives in the repository, not in `store.books`).
    @State private var syncToggleTick = 0
    /// Long-press → the "Turn it on" sync sheet (mock screen 1) for this book.
    @State private var syncSheetBook: Audiobook?
    @State private var shareSheetBook: Audiobook?
    /// Delete needs a confirm (device feedback: one swipe = gone). Holds the book
    /// awaiting confirmation; the dialog is sync-aware (mock screen 7).
    @State private var pendingDelete: Audiobook?

    // MARK: - D127: per-book "❝ N" notes (Q6 mock)

    /// Per-book note counts. The live-memo `@Query` lives in `BookNoteCountsFeed` (a zero-size
    /// background view), NOT here: a query on this view re-evaluated the whole Books body (hidden
    /// behind the editor) on every note save (Q322). `BookNotesJoin` counts them once per memo-set
    /// version, never one fetch per tile — the frozen-library trap.
    /// The pill's target: the book whose notes sheet is open.
    @State private var notesSheetBook: Audiobook?
    /// Q317: per-book counts, computed once per memo-set version off the main actor
    /// (`BookNotesCountCache`) — NOT per row per render. Seeded from the last pass so
    /// re-opening the tab shows the pills at once. Written only when the counts differ (Q322).
    @State private var noteCounts: [UUID: Int] = BookNotesCountCache.shared.counts

    /// A row of the notes sheet opens the note in Notes (they live there).
    private func openNote(_ memo: Memo) {
        notesSheetBook = nil
        TabSelectionBridge.shared.select(.notes)
        MemoOpenBridge.shared.open(memo.id)
    }

    // MARK: - 📖 Book text (spike 6 / multi-text)

    /// Long-press → "Book text…" target; the whole flow (sheet + picker + alerts)
    /// is `BookTextFlow`, shared verbatim with the player's ⋯ menu.
    @State private var bookTextSheetBook: Audiobook?

    private static let importTypes: [UTType] = {
        var types: [UTType] = [.audio]
        if let m4b = UTType(filenameExtension: "m4b") { types.append(m4b) }
        return types
    }()

    var body: some View {
        ZStack {
            Color.skBg.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                // The empty tab (Q6 mock) is title + doors only: no sort chip or count.
                if !store.books.isEmpty { header }
                booksContent
            }
        }
        // The FULL mini-player bar lives on Books (2026-07-07 bottom-chrome
        // redesign): mounted INSIDE the screen so the inset actually reaches the
        // list (the tab-level mount didn't, on iOS 26). Notes carries the compact
        // pill beside the record button; Journal/Settings carry nothing.
        .safeAreaInset(edge: .bottom) {
            if session.isActive {
                AudiobookMiniPlayerBar()
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.spring, value: session.isActive)
        .libraryPDFs(isImporting: $showPDFImporter, reader: $pdfReaderBook)   // Q354
        .fileImporter(isPresented: $showImporter, allowedContentTypes: Self.importTypes, allowsMultipleSelection: true) { result in
            // Multi-select imports ONE book: a file-per-chapter folder's mp3s
            // become its ordered chapters (Bound-style).
            if case .success(let urls) = result, !urls.isEmpty {
                Task { await runImport(urls) }
            }
        }
        // Q255: an `.m4b` opened from Files / another app runs the SAME import the Add
        // button runs; one book at a time, the next waits for the confirm sheet.
        .onAppear { takeOpenIn() }
        .background { BookNoteCountsFeed(counts: $noteCounts) }
        .onChange(of: openInBridge.requestID) { _, _ in takeOpenIn() }
        .onChange(of: pendingImport?.id) { _, id in if id == nil { startNextOpenIn() } }
        .sheet(item: $pendingImport, onDismiss: {
            // A0 fires here — after the confirm sheet is fully down (a direct
            // sheet-to-sheet swap drops the second presentation on iOS 26). Only
            // when a skipped-parts alert isn't about to claim the presentation.
            if let book = a0Candidate {
                a0Candidate = nil
                if importNotice == nil, !BookTextPrompt.seen(book.id) {
                    BookTextPrompt.markSeen(book.id)
                    giveTextBook = book
                }
            }
        }) { pending in
            AudiobookImportConfirmSheet(
                pending: pending,
                onConfirm: { book in
                    store.add(book)
                    a0Candidate = book
                    pendingImport = nil
                    importNotice = Self.skippedNotice(pending.skippedParts)
                },
                onCancel: {
                    store.remove(pending.book)   // clears the copied folder
                    pendingImport = nil
                }
            )
            .presentationDetents([.medium])
        }
        // A0: the once-per-book "Give this book text" prompt; its "Add book text…"
        // hands off to the unified Text sheet (which owns the picker) — parked
        // through onDismiss, same sheet-swap-race rule as above.
        .sheet(item: $giveTextBook, onDismiss: {
            if let book = a0AddHandoff {
                a0AddHandoff = nil
                bookTextSheetBook = book
            }
        }) { book in
            BookTextPromptSheet(book: book) {
                a0AddHandoff = book
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            AudiobookPlayerView()
        }
        // Q353: the podcast door. The finished episode joins the shelf like any other source.
        .sheet(isPresented: $showPodcastSheet) {
            PodcastLinkSheet { episode in store.add(episode) }
        }
        .sheet(item: $syncSheetBook, onDismiss: { syncToggleTick += 1 }) { book in
            AudiobookSyncSheet(book: book)
        }
        // 📦 Share a book (outgoing). Same sheet from the player's ⋯ — the locked
        // convention that a verb reachable from both places shows one screen.
        .sheet(item: $shareSheetBook) { book in
            BookShareSheet(book: book)
        }
        // 📖 The "Book text" flow (sheet + picker + alerts) — shared with the player.
        .bookTextFlow(book: $bookTextSheetBook)
        // ❝ N: the book's capture notes (D127).
        .sheet(item: $notesSheetBook) { book in
            BookNotesSheetHost(book: book, onOpen: openNote)
                .presentationDetents([.medium, .large])
        }
        .alert("Import failed", isPresented: $importError.isPresent) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        // Partial import: the book landed, but some parts couldn't be decoded and
        // were skipped — say so, never a silent gap (device finding 2026-07-05).
        .alert("Imported with skipped parts", isPresented: $importNotice.isPresent) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importNotice ?? "")
        }
        .confirmationDialog(
            pendingDelete.map { "Remove \u{201C}\($0.title)\u{201D}?" } ?? "",
            isPresented: $pendingDelete.isPresent,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { book in
            if AudiobookCloudSync.isSynced(bookID: book.id) {
                // Synced → two destructive choices (mock screen 7).
                Button("Remove from all devices", role: .destructive) {
                    // Remove locally FIRST so the row + playback commit immediately
                    // (the cloud delete can be a multi-second round-trip); the carrier
                    // survives store.remove, so disableSync still finds the cloud
                    // records to delete.
                    delete(book)
                    Task { await AudiobookCloudSync.disableSync(bookID: book.id) }
                }
                // Demoted/neutral: free this device's copy but keep it synced + on
                // your other devices (Apple Books model). Stays in the library as
                // download-available, not deleted. End the session first if this is
                // the playing book — its audio is about to vanish from disk.
                Button(BookTileState.removeThisDeviceTitle) {
                    if session.book?.id == book.id { session.endSession() }
                    AudiobookCloudSync.removeDownload(bookID: book.id)
                    syncToggleTick += 1
                }
            } else {
                Button("Remove", role: .destructive) { delete(book) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { book in
            Text(BookTileState.deleteMessage(synced: AudiobookCloudSync.isSynced(bookID: book.id)))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("audiobook-library")
    }

    // MARK: - Chrome

    private var topBar: some View {
        // ONE header line (device round 4: unified 30pt titles on all four
        // tabs): "Books" + the import action inline — the separate title row
        // below is gone.
        HStack {
            ScreenTitle("Library")
            Spacer()

            Menu {
                Button { showImporter = true } label: {
                    Label("Audiobook from Files…", systemImage: "books.vertical")
                }
                .accessibilityIdentifier("library-add-audiobook")
                Button { showPodcastSheet = true } label: {
                    Label("Podcast link…", systemImage: "antenna.radiowaves.left.and.right")
                }
                .accessibilityIdentifier("library-add-podcast")
                Button { showPDFImporter = true } label: {   // Q354
                    Label("PDF from Files…", systemImage: "doc.text")
                }
                .accessibilityIdentifier("library-add-pdf")
            } label: {
                if importing {
                    ProgressView()
                        .frame(width: 30, height: 30)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.skAccentText)
                        .frame(width: 30, height: 30)
                        .background(Color.skAccentSoft, in: .rect(cornerRadius: 9, style: .continuous))
                }
            }
            .disabled(importing)
            .accessibilityIdentifier("library-import")
            .accessibilityLabel("Add to Library — an audiobook or a PDF from Files, or a podcast episode from a link")
        }
        .padding(.horizontal, Theme.Space.margin)
        .padding(.top, 8)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sortFilterChip
                Spacer()
                // The mock's header "Syncing…" chip — in the header row, so it never
                // overlaps a book title (the per-book bar shows what's in flight). Shows
                // for the SwiftData mirror AND a raw audiobook-audio transfer (which
                // doesn't fire eventChangedNotification).
                if cloudSync.isSyncing || cloudSync.isTransferringBooks {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text("Syncing…").font(.system(size: 10.5))
                    }
                    .foregroundStyle(Color.skAccentText)
                    .padding(.trailing, 8)
                    .transition(.opacity)
                }
                Text(countLine)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.skTextFaint)
            }
            // The mock's one-line hint (Q6): what a tap, a hold and the ❝ pill each do.
            if !isRegular {
                Text("Tap a cover to open it. Hold a cover for its menu. Tap ❝ for its notes.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.skTextFaint)
                    .accessibilityIdentifier("library-shelf-hint")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.margin)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .animation(.easeInOut(duration: 0.2), value: cloudSync.isSyncing)
    }

    private var countLine: String {
        let n = store.books.count
        let sources = "\(n) source\(n == 1 ? "" : "s")"
        return session.isActive ? sources + " · 1 listening" : sources
    }

    /// The header chip IS the sort/filter control (it used to be a static
    /// "Recently played" label that merely looked tappable). Label = active
    /// filter (if any) + sort; menu = sorts, then status-filter toggles.
    private var sortFilterChip: some View {
        Menu {
            Picker("Sort", selection: Binding(get: { sort }, set: { sortRaw = $0.rawValue })) {
                ForEach(BookSort.allCases, id: \.self) { s in Text(s.label).tag(s) }
            }
            Divider()
            ForEach(BookStatusFilter.allCases, id: \.self) { f in
                Button {
                    statusFilter = statusFilter == f ? nil : f
                } label: {
                    if statusFilter == f { Label(f.label, systemImage: "checkmark") }
                    else { Text(f.label) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(chipLabel)
                    .font(.system(size: 11.5, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(statusFilter == nil ? Color.skTextDim : Color.skAccentText)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(statusFilter == nil ? Color.skElev : Color.skAccentSoft,
                        in: .rect(cornerRadius: 8, style: .continuous))
        }
        .accessibilityIdentifier("books-sort-filter")
        .accessibilityLabel("Sort and filter books")
    }

    private var chipLabel: String {
        if let statusFilter { return "\(statusFilter.label) · \(sort.label)" }
        return sort.label
    }

    /// The list the rows render: status-filtered, then sorted by the chip's choice.
    private var visibleBooks: [Audiobook] {
        let filtered = statusFilter.map { f in store.books.filter { f.matches($0) } } ?? store.books
        return sort.sorted(filtered)
    }

    // MARK: - Shelf (Q6 mock `Q6-library-tab.html`; iPad wave mock `ipad-app.html` m6)

    /// Q352: the shelf of tiles at EVERY width (the phone's 54pt row list is gone). Phone = the
    /// mock's two columns (18 across, 26 down); regular width keeps its adaptive grid (C229).
    private var booksContent: some View { bookShelf }

    private var shelfColumns: [GridItem] {
        isRegular
            ? [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 20)]
            : [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)]
    }

    /// Same books, same sort/filter, same tap-to-play + long-press menu.
    private var bookShelf: some View {
        ScrollView {
            if store.books.isEmpty {
                LibraryEmptyView { door in openDoor(door) }
                    .padding(.horizontal, Theme.Space.margin)
                    .padding(.top, 18)
            } else if visibleBooks.isEmpty {
                Text("No \(statusFilter?.label.lowercased() ?? "matching") books.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.skTextFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Space.margin)
                    .padding(.top, 10)
            } else {
                LazyVGrid(columns: shelfColumns, spacing: 26) {
                    ForEach(visibleBooks) { book in
                        let isCurrent = session.book?.id == book.id
                        let syncState = bookSyncState(book)
                        BookShelfTile(book: book, isCurrent: isCurrent, syncState: syncState,
                                      transferFraction: cloudSync.bookTransfers[book.id]?.fraction,
                                      realign: BookTileState.realignLine(active: textActivity.isActive(book.id),
                                                                         stage: textActivity.stage),
                                      noteCount: noteCounts[book.id] ?? 0,
                                      onNotes: { notesSheetBook = book }) {
                            openOrPlay(book, syncState: syncState)
                        }
                        .contextMenu { contextMenuItems(book) }
                    }
                }
                .padding(.horizontal, Theme.Space.margin)
                .padding(.top, 6)
                // Clears the floating mini-player bar (safeAreaInset already reserves
                // room, but the grid's own scroll content wants its own breathing room
                // at the very bottom row too).
                .padding(.bottom, 24)
            }
        }
        .scrollIndicators(.hidden)
        .animation(.easeInOut(duration: 0.2), value: cloudSync.isSyncing)
        .accessibilityIdentifier("ipad-library-book-shelf")
    }

    /// An empty-tab door opens its importer. Only built doors are shown (`LibraryDoor.visible`).
    private func openDoor(_ door: LibraryDoor) {
        switch door {
        case .audiobook: showImporter = true
        case .podcast: showPodcastSheet = true
        case .epubOrPDF: showPDFImporter = true       // Q354
        case .article: break   // hidden until Q355 lands its importer
        }
    }

    /// Tap-to-play/resume (2026-07-06 convention) — the shelf tile's tap.
    private func openOrPlay(_ book: Audiobook, syncState: BookSyncState?) {
        if book.sourceKind == .pdf { pdfReaderBook = book; return }   // Q354: a PDF opens its reader
        if session.open(book, autoplay: true) {
            showPlayer = true
        } else if syncState == .downloadAvailable {
            // Audio was freed on this device — tap to re-download. open() already
            // bailed without tearing down current playback or opening a dead player.
            Task {
                await AudiobookCloudSync.restoreDownload(bookID: book.id)
                syncToggleTick += 1
            }
        }
        // .downloading / genuinely-missing: leave the current session intact; the
        // reconcile sweep is already fetching the audio.
    }

    /// ONE long-press menu for the compact rows AND the iPad shelf tiles (merge
    /// 2026-07-23: contents = main's unified-Text-sheet verbs; the extraction is the
    /// iPad wave's, so the two presentations can't drift).
    private func contextMenuItems(_ book: Audiobook) -> some View {
        // 📖 ONE "Text…" verb (mock book-text-unified.html, signed off
        // 2026-07-23): the unified sheet owns BOTH levels — transcribe
        // (Level 1, inline job controls) and book text (Level 2: Add /
        // Re-check / Remove, fileImporter presents over it).
        Group {
            if book.sourceKind != .pdf {   // Q354: a PDF has no transcript, book text or audio to sync
            Button {
                bookTextSheetBook = book
            } label: {
                Label("Text…", systemImage: "text.book.closed")
            }
            // 📦 Share a book with another PERSON — one file, one button. Sits
            // directly above Sync on purpose: the two read as opposites (Share =
            // give it away · Sync = keep it across your own devices).
            Button { shareSheetBook = book } label: {
                Label("Share book…", systemImage: "square.and.arrow.up")
            }
            // Per-book sync (Phase 1h): open the "Turn it on" sheet (cover +
            // size + the toggle + a live transfer %). The sheet owns the
            // enable/disable + iCloud-storage explainer (mock screen 1).
            Button { syncSheetBook = book } label: {
                Label(AudiobookCloudSync.isSynced(bookID: book.id) ? "Sync settings…" : "Sync this book…",
                      systemImage: "icloud")
            }
            }   // end: not a PDF
            Button(role: .destructive) { pendingDelete = book } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    enum BookSyncState { case uploading, downloading, downloadAvailable, synced }

    /// Per-book sync state, shown ON the row. nil = local-only (no record). `uploading`
    /// = audio export in flight (source). `downloading` = synced, audio not here yet +
    /// materializing (receiver). `downloadAvailable` = synced but the user freed this
    /// device's copy. `synced` = opted in + audio is here. The raw-CloudKit transport
    /// publishes a REAL % into `cloudSync.bookTransfers`, so uploading/downloading now
    /// render a DETERMINATE bar. Reads `syncToggleTick` so the row re-renders after toggles.
    private func bookSyncState(_ book: Audiobook) -> BookSyncState? {
        _ = syncToggleTick
        guard AudiobookCloudSync.isSynced(bookID: book.id) else { return nil }
        if let transfer = cloudSync.bookTransfers[book.id] {
            return transfer.direction == .up ? .uploading : .downloading
        }
        let folder = store.folder(for: book.id)
        let present = !book.files.isEmpty && book.files.allSatisfy {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        if present { return .synced }
        return AudiobookCloudSync.isDownloadRemoved(bookID: book.id) ? .downloadAvailable : .downloading
    }

    // MARK: - Actions

    /// The partial-import notice text, or nil when nothing was skipped. Static +
    /// pure so the skip-surfacing behaviour is unit-testable.
    static func skippedNotice(_ skipped: [String]) -> String? {
        guard !skipped.isEmpty else { return nil }
        let n = skipped.count
        return "\(n) part\(n == 1 ? "" : "s") couldn’t be read by iOS and \(n == 1 ? "was" : "were") skipped:\n"
            + skipped.joined(separator: "\n")
            + "\n\nThe book plays with a gap there — re-download or re-rip \(n == 1 ? "that file" : "those files") and re-import to fill it."
    }

    private func takeOpenIn() {
        openInQueue += openInBridge.consume()
        startNextOpenIn()
    }

    private func startNextOpenIn() {
        guard !importing, pendingImport == nil, !openInQueue.isEmpty else { return }
        let url = openInQueue.removeFirst()
        Task {
            await runImport([url])
            startNextOpenIn()
        }
    }

    private func runImport(_ urls: [URL]) async {
        importing = true
        defer { importing = false }
        do {
            let pending = try await AudiobookImporter.importBook(from: urls, libraryDirectory: store.directory)
            if pending.needsConfirmation {
                pendingImport = pending   // skipped-parts notice fires after the sheet resolves
            } else {
                store.add(pending.book)
                importNotice = Self.skippedNotice(pending.skippedParts)
            }
        } catch {
            importError = error.localizedDescription
        }
    }

    private func delete(_ book: Audiobook) {
        if session.book?.id == book.id {
            session.endSession()
        }
        store.remove(book)
    }
}
