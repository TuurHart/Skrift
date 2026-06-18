import SwiftUI
import UniformTypeIdentifiers

/// The audiobook Library (mock state 1, Bound-inspired): import from
/// Files/iCloud, covers + sort, per-book resume with time-left, swipe-delete
/// (captures survive — they're ordinary memos with their own audio). Lives
/// behind the book toolbar icon on the memos list (mounted by the list lane).
/// No mini-player here — the Playing row IS the session on this screen.
struct AudiobookLibraryView: View {
    @ObservedObject private var store = AudiobookLibraryStore.shared
    @ObservedObject private var session = AudiobookSession.shared
    @ObservedObject private var cloudSync = CloudSyncMonitor.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showImporter = false
    @State private var importing = false
    @State private var pendingImport: PendingAudiobookImport?
    @State private var importError: String?
    @State private var showPlayer = false
    /// Long-press → "Transcribe book" target (presents the transcribe sheet for
    /// any library book without opening it first).
    @State private var transcribeBook: Audiobook?
    /// Bumped when a book's sync toggle flips, so the row's cloud glyph re-renders
    /// (sync state lives in the repository, not in `store.books`).
    @State private var syncToggleTick = 0

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
        .fileImporter(isPresented: $showImporter, allowedContentTypes: Self.importTypes, allowsMultipleSelection: true) { result in
            // Multi-select imports ONE book: a file-per-chapter folder's mp3s
            // become its ordered chapters (Bound-style).
            if case .success(let urls) = result, !urls.isEmpty {
                Task { await runImport(urls) }
            }
        }
        .sheet(item: $pendingImport) { pending in
            AudiobookImportConfirmSheet(
                pending: pending,
                onConfirm: { book in
                    store.add(book)
                    pendingImport = nil
                },
                onCancel: {
                    store.remove(pending.book)   // clears the copied folder
                    pendingImport = nil
                }
            )
            .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $showPlayer) {
            AudiobookPlayerView()
        }
        .sheet(item: $transcribeBook) { book in
            TranscribeBookView(book: book)
        }
        .alert("Import failed", isPresented: .init(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("audiobook-library")
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Memos")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundStyle(Color.skAccentText)
            }
            .accessibilityIdentifier("library-back")

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
            Text("Library")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(Color.skText)
            HStack {
                Text("Recently played")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.skTextDim)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.skElev, in: .rect(cornerRadius: 8, style: .continuous))
                Spacer()
                // The mock's header "Syncing…" chip — in the header row, so it never
                // overlaps a book title (the per-book bar shows what's in flight).
                if cloudSync.isSyncing {
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

    // MARK: - List

    private var bookList: some View {
        List {
            ForEach(store.sortedByRecent) { book in
                row(book)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: Theme.Space.margin, bottom: 4, trailing: Theme.Space.margin))
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            delete(book)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        // Long-press → transcribe straight from the library (no need
                        // to open the book → ⋯). Feeds read-along + instant capture.
                        Button { transcribeBook = book } label: {
                            Label("Transcribe book", systemImage: "text.book.closed")
                        }
                        // Per-book sync (Phase 1h): opt this book into cross-device
                        // sync — its state + audio ride CloudKit so it resumes on your
                        // other devices. The upload runs via the reconcile (pull-to-
                        // refresh / launch); flipping it on kicks one off immediately.
                        if AudiobookCloudSync.isSynced(bookID: book.id) {
                            Button { AudiobookCloudSync.disableSync(bookID: book.id); syncToggleTick += 1 } label: {
                                Label("Stop syncing to my devices", systemImage: "icloud.slash")
                            }
                        } else {
                            Button { AudiobookCloudSync.enableSync(book: book); AudiobookCloudSync.reconcile(); syncToggleTick += 1 } label: {
                                Label("Sync this book to my devices", systemImage: "icloud.and.arrow.up")
                            }
                        }
                        Button(role: .destructive) { delete(book) } label: {
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
    /// = just opted in, CKAsset export in flight (source). `downloading` = synced, audio
    /// not here yet + materializing (receiver). `downloadAvailable` = synced but the
    /// user freed this device's copy. `synced` = opted in + audio is here. CloudKit
    /// exposes no upload %, so uploading/downloading render an honest INDETERMINATE bar,
    /// not a fake percentage. Reads `syncToggleTick` so the row re-renders after toggles.
    private func bookSyncState(_ book: Audiobook) -> BookSyncState? {
        _ = syncToggleTick
        guard AudiobookCloudSync.isSynced(bookID: book.id) else { return nil }
        if cloudSync.uploadingBookIDs.contains(book.id) { return .uploading }
        let folder = store.folder(for: book.id)
        let present = !book.files.isEmpty && book.files.allSatisfy {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        if present { return .synced }
        return AudiobookCloudSync.isDownloadRemoved(bookID: book.id) ? .downloadAvailable : .downloading
    }

    private func row(_ book: Audiobook) -> some View {
        let isCurrent = session.book?.id == book.id
        let syncState = bookSyncState(book)
        return Button {
            session.open(book)
            showPlayer = true
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
                        // In-flight sync: an INDETERMINATE bar on the book itself (no
                        // fake %, since CloudKit gives none) + a clear label.
                        HStack(spacing: 7) {
                            ProgressView()
                                .progressViewStyle(.linear)
                                .tint(Color.skAccent)
                                .frame(maxWidth: 110)
                                .scaleEffect(x: 1, y: 0.7, anchor: .center)
                            Text(syncState == .uploading ? "Uploading audio…" : "Downloading…")
                                .font(.system(size: 10.5))
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

                if isCurrent {
                    Text(session.isPlaying ? "PLAYING" : "PAUSED")
                        .font(.system(size: 9.5, weight: .bold))
                        .kerning(0.5)
                        .foregroundStyle(session.isPlaying ? Color.skGreen : Color.skAmber)
                }
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

    private func runImport(_ urls: [URL]) async {
        importing = true
        defer { importing = false }
        do {
            let pending = try await AudiobookImporter.importBook(from: urls, libraryDirectory: store.directory)
            if pending.needsConfirmation {
                pendingImport = pending
            } else {
                store.add(pending.book)
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
