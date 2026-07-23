import SwiftUI
import UniformTypeIdentifiers

/// The Books tab (mock state 1, Bound-inspired; root tab since 2026-06-19,
/// renamed Library→Books 2026-07-06): import from Files/iCloud, covers,
/// sort + status filters (default: recently played), per-book resume with
/// time-left, swipe-delete (captures survive — they're ordinary memos with
/// their own audio). Tapping a book PLAYS it (2026-07-06) — the full player
/// opens already running. The global mini-player capsule (AppTabView) shows
/// the session here too, so the row keeps only the current-book tint.
struct AudiobookLibraryView: View {
    @ObservedObject private var store = AudiobookLibraryStore.shared
    @ObservedObject private var session = AudiobookSession.shared
    @ObservedObject private var cloudSync = CloudSyncMonitor.shared

    /// Sort choice, persisted app-wide; the header chip is the control.
    @AppStorage("bookSortRaw") private var sortRaw = BookSort.recentlyPlayed.rawValue
    /// Status filter (transient, like the Notes funnel): nil = all books.
    @State private var statusFilter: BookStatusFilter?
    private var sort: BookSort { BookSort(rawValue: sortRaw) ?? .recentlyPlayed }

    @State private var showImporter = false
    @State private var importing = false
    @State private var pendingImport: PendingAudiobookImport?
    @State private var importError: String?
    /// Partial-import notice: the book imported but N parts were skipped (unreadable).
    @State private var importNotice: String?
    @State private var showPlayer = false
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
    /// Delete needs a confirm (device feedback: one swipe = gone). Holds the book
    /// awaiting confirmation; the dialog is sync-aware (mock screen 7).
    @State private var pendingDelete: Audiobook?

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
                header
                bookList
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
        .fileImporter(isPresented: $showImporter, allowedContentTypes: Self.importTypes, allowsMultipleSelection: true) { result in
            // Multi-select imports ONE book: a file-per-chapter folder's mp3s
            // become its ordered chapters (Bound-style).
            if case .success(let urls) = result, !urls.isEmpty {
                Task { await runImport(urls) }
            }
        }
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
        .sheet(item: $syncSheetBook, onDismiss: { syncToggleTick += 1 }) { book in
            AudiobookSyncSheet(book: book)
        }
        // 📖 The "Book text" flow (sheet + picker + alerts) — shared with the player.
        .bookTextFlow(book: $bookTextSheetBook)
        .alert("Import failed", isPresented: .init(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        // Partial import: the book landed, but some parts couldn't be decoded and
        // were skipped — say so, never a silent gap (device finding 2026-07-05).
        .alert("Imported with skipped parts", isPresented: .init(
            get: { importNotice != nil },
            set: { if !$0 { importNotice = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importNotice ?? "")
        }
        .confirmationDialog(
            pendingDelete.map { "Remove \u{201C}\($0.title)\u{201D}?" } ?? "",
            isPresented: Binding(get: { pendingDelete != nil },
                                 set: { if !$0 { pendingDelete = nil } }),
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
                Button("Remove from this iPhone only") {
                    if session.book?.id == book.id { session.endSession() }
                    AudiobookCloudSync.removeDownload(bookID: book.id)
                    syncToggleTick += 1
                }
            } else {
                Button("Remove", role: .destructive) { delete(book) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { book in
            if AudiobookCloudSync.isSynced(bookID: book.id) {
                Text("It's synced to your devices. Removing everywhere deletes the audio + read-along text from all of them. Your bookmarks and captured notes are kept.")
            } else {
                Text("This removes the book and its audio from this iPhone. Your bookmarks and captured notes are kept.")
            }
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
            ScreenTitle("Books")
            Spacer()

            Button {
                showImporter = true
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
            .accessibilityLabel("Import an audiobook from Files — select every part of a multi-file book at once")
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.margin)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .animation(.easeInOut(duration: 0.2), value: cloudSync.isSyncing)
    }

    private var countLine: String {
        let n = store.books.count
        let books = "\(n) book\(n == 1 ? "" : "s")"
        return session.isActive ? books + " · 1 listening" : books
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

    // MARK: - List

    private var bookList: some View {
        List {
            ForEach(visibleBooks) { book in
                row(book)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: Theme.Space.margin, bottom: 4, trailing: Theme.Space.margin))
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDelete = book
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        // 📖 ONE "Text…" verb (mock book-text-unified.html, signed off
                        // 2026-07-23): the unified sheet owns BOTH levels — transcribe
                        // (Level 1, inline job controls) and book text (Level 2: Add /
                        // Re-check / Remove, fileImporter presents over it).
                        Button {
                            bookTextSheetBook = book
                        } label: {
                            Label("Text…", systemImage: "text.book.closed")
                        }
                        // Per-book sync (Phase 1h): open the "Turn it on" sheet (cover +
                        // size + the toggle + a live transfer %). The sheet owns the
                        // enable/disable + iCloud-storage explainer (mock screen 1).
                        Button { syncSheetBook = book } label: {
                            Label(AudiobookCloudSync.isSynced(bookID: book.id) ? "Sync settings…" : "Sync this book…",
                                  systemImage: "icloud")
                        }
                        Button(role: .destructive) { pendingDelete = book } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            // ONE import affordance — the toolbar +. The empty library keeps a
            // passive hint line only (no second button).
            if store.books.isEmpty {
                emptyHint
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: Theme.Space.margin, bottom: 12, trailing: Theme.Space.margin))
            } else if visibleBooks.isEmpty {
                // A status filter with no matches must say so, not show a blank list.
                Text("No \(statusFilter?.label.lowercased() ?? "matching") books.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.skTextFaint)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: Theme.Space.margin, bottom: 12, trailing: Theme.Space.margin))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Sync feedback lives ON each book row (uploading/downloading bar) — no floating
        // pill here, so nothing overlaps the titles.
        .animation(.easeInOut(duration: 0.2), value: cloudSync.isSyncing)
    }

    private var emptyHint: some View {
        Text("No audiobooks yet — import from **Files / iCloud** with the **+** above. Select every file of a file-per-chapter book at once; title, author & chapters come from the tags (you only confirm if they’re missing).")
            .font(.system(size: 11))
            .foregroundStyle(Color.skTextFaint)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
            .accessibilityIdentifier("library-empty-hint")
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

    /// The mock's row label: "Uploading audio · 38%" / "Downloading · 61%" (the % drops
    /// out in the brief pre-first-byte window so we never show a misleading "0%").
    private func transferLabel(uploading: Bool, pct: Int?) -> String {
        let verb = uploading ? "Uploading audio" : "Downloading"
        guard let pct else { return uploading ? "Uploading audio…" : "Downloading…" }
        return "\(verb) · \(pct)%"
    }

    private func row(_ book: Audiobook) -> some View {
        let isCurrent = session.book?.id == book.id
        let syncState = bookSyncState(book)
        return Button {
            // Tapping a book PLAYS it (2026-07-06 — the audiobook-app convention;
            // an open-paused player was a dead extra tap). open() no-ops the
            // teardown for the already-loaded book and just resumes it.
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
        } label: {
            HStack(spacing: 12) {
                BookCoverView(book: book)
                    .frame(width: 54, height: 54)
                    .clipShape(.rect(cornerRadius: 9, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 5, y: 2)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(book.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Color.skText)
                            .lineLimit(1)
                        // Per-book sync glyph (Phase 1h): ✓ when the audio is here, or a
                        // download cloud when it's freed on this device. Uploading /
                        // downloading show as a bar on the progress line below instead.
                        switch syncState {
                        case .synced:
                            Image(systemName: "checkmark.icloud")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.skTextDim)
                                .accessibilityLabel("Synced to your devices")
                        case .downloadAvailable:
                            Image(systemName: "icloud.and.arrow.down")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.skTextDim)
                                .accessibilityLabel("Synced — download to this device")
                        case .uploading, .downloading, .none:
                            EmptyView()
                        }
                    }
                    Text(book.author)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.skTextDim)
                        .lineLimit(1)
                    if syncState == .uploading || syncState == .downloading {
                        // In-flight sync: a DETERMINATE bar on the book itself, fed by the
                        // raw-CloudKit transport's real per-record progress. Falls back to
                        // indeterminate only in the brief window before the first byte (a
                        // received phantom waiting on the source's audioUploadedAt push).
                        let transfer = cloudSync.bookTransfers[book.id]
                        let pct = transfer.map { Int(($0.fraction * 100).rounded()) }
                        HStack(spacing: 7) {
                            Group {
                                if let fraction = transfer?.fraction {
                                    ProgressView(value: fraction)
                                } else {
                                    ProgressView()
                                }
                            }
                            .progressViewStyle(.linear)
                            .tint(Color.skAccent)
                            .frame(maxWidth: 110)
                            .scaleEffect(x: 1, y: 0.7, anchor: .center)
                            Text(transferLabel(uploading: syncState == .uploading, pct: pct))
                                .font(.system(size: 10.5))
                                .monospacedDigit()
                                .foregroundStyle(Color.skAccentText)
                        }
                        .padding(.top, 3)
                    } else {
                        HStack(spacing: 7) {
                            ProgressView(value: book.progress)
                                .progressViewStyle(.linear)
                                .tint(Color.skAccent.opacity(0.65))
                                .frame(maxWidth: 110)
                                .scaleEffect(x: 1, y: 0.7, anchor: .center)
                            Text(AudiobookTime.clock(book.timeLeft) + " left")
                                .font(.system(size: 10.5))
                                .monospacedDigit()
                                .foregroundStyle(Color.skTextFaint)
                        }
                        .padding(.top, 3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            }
            .padding(EdgeInsets(top: 11, leading: 12, bottom: 11, trailing: 12))
            .background(
                isCurrent ? Color.skAccent.opacity(0.07) : Color.skSurface,
                in: .rect(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle.sk(14)
                    .stroke(isCurrent ? Color.skAccent.opacity(0.3) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library-book-row")
        .accessibilityLabel("\(book.title) by \(book.author), \(AudiobookTime.clock(book.timeLeft)) left")
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

    // MARK: - 📖 Attach book text (spike 6)

    /// Copy the picked file in, align every covered transcript file against
    /// it, and route the outcome to whichever of the three surfaces fits
    /// (BASE.md's `AttachSummary`): a plain toast when it aligned (fully or
    /// partially) or when there's no transcript yet to align against, or the
    /// reject-confirm alert when every file came back rejected.

    /// "Remove" on the reject alert: clears the ePub fields only (re-fetches
    /// the current record by id rather than trusting the captured `book`, in
    /// case something else changed it while the alignment ran). The alignment
    /// sidecars themselves are left in place — a `.rejected` verdict is honest
    /// data, not corruption, and re-attaching later can only overwrite it.
}

/// One-time editable confirm sheet, shown ONLY when the file's tags were
/// missing (locked design: import asks nothing otherwise).
struct AudiobookImportConfirmSheet: View {
    let pending: PendingAudiobookImport
    var onConfirm: (Audiobook) -> Void
    var onCancel: () -> Void

    @State private var title: String
    @State private var author: String

    init(pending: PendingAudiobookImport,
         onConfirm: @escaping (Audiobook) -> Void,
         onCancel: @escaping () -> Void) {
        self.pending = pending
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _title = State(initialValue: pending.book.title)
        _author = State(initialValue: pending.book.author)
    }

    var body: some View {
        ZStack {
            Color.skBg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    BookCoverView(book: pending.book)
                        .frame(width: 54, height: 54)
                        .clipShape(.rect(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Confirm book details")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.skText)
                        Text("This file’s tags were incomplete — fill in what’s missing.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.skTextDim)
                    }
                }

                field("Title", text: $title, id: "import-title")
                field("Author", text: $author, id: "import-author")

                HStack(spacing: 8) {
                    Button("Cancel") { onCancel() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.skTextDim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .overlay(RoundedRectangle.sk(11).stroke(Color.skBorder, lineWidth: 1))
                        .accessibilityIdentifier("import-cancel")

                    Button {
                        var book = pending.book
                        book.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        book.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
                        if book.title.isEmpty { book.title = pending.book.title }
                        onConfirm(book)
                    } label: {
                        Text("Add to Library")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.skAccent, in: .rect(cornerRadius: 11, style: .continuous))
                    }
                    .accessibilityIdentifier("import-confirm")
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Space.margin)
        }
        .interactiveDismissDisabled()
    }

    private func field(_ label: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(Color.skTextFaint)
            TextField(label, text: text)
                .font(.system(size: 14))
                .foregroundStyle(Color.skText)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color.skElev, in: .rect(cornerRadius: Theme.Radius.field, style: .continuous))
                .accessibilityIdentifier(id)
        }
    }
}
