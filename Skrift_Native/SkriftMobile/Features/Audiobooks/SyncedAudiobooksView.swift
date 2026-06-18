import SwiftUI

/// Settings → "Synced audiobooks": the books opted into cross-device sync, their
/// iCloud size, and per-book management — **Remove download** (free this device's copy
/// but keep it synced, Apple Books style), **Download** (re-fetch a freed one), and
/// **Stop syncing** (unshare; local copies stay). The honest counterpart to the
/// per-book toggle, so the user can see + reclaim what audiobook sync is using.
struct SyncedAudiobooksView: View {
    @ObservedObject private var store = AudiobookLibraryStore.shared
    private let repository = NotesRepository.shared
    /// Bumped after an action so the list re-reads sync/removed state (lives in the repo
    /// + UserDefaults, not in `store.books`).
    @State private var tick = 0

    private var syncedBooks: [Audiobook] {
        _ = tick
        return store.sortedByRecent.filter { AudiobookCloudSync.isSynced(bookID: $0.id) }
    }

    private func sizeBytes(_ book: Audiobook) -> Int {
        repository.audiobookAssets(bookID: book.id).reduce(0) { $0 + $1.byteCount }
    }
    private func fmt(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    var body: some View {
        List {
            if syncedBooks.isEmpty {
                Text("No audiobooks synced yet. Long-press a book in your library → “Sync this book to my devices.”")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.skTextFaint)
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(syncedBooks) { book in row(book) }
                } footer: {
                    let total = syncedBooks.reduce(0) { $0 + sizeBytes($1) }
                    Text("\(syncedBooks.count) book\(syncedBooks.count == 1 ? "" : "s") · \(fmt(total)) in iCloud. “Remove download” frees this device’s copy but keeps the book synced; manage your overall storage in iCloud Settings.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.skBg.ignoresSafeArea())
        .navigationTitle("Synced audiobooks")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ book: Audiobook) -> some View {
        let removed = AudiobookCloudSync.isDownloadRemoved(bookID: book.id)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.skText).lineLimit(1)
                Text("\(book.author) · \(fmt(sizeBytes(book)))" + (removed ? " · not on this device" : ""))
                    .font(.system(size: 11.5)).foregroundStyle(Color.skTextDim).lineLimit(1)
            }
            Spacer()
            Menu {
                if removed {
                    Button { AudiobookCloudSync.restoreDownload(bookID: book.id); tick += 1 } label: {
                        Label("Download to this device", systemImage: "icloud.and.arrow.down")
                    }
                } else {
                    Button { AudiobookCloudSync.removeDownload(bookID: book.id); tick += 1 } label: {
                        Label("Remove download", systemImage: "arrow.down.circle.dotted")
                    }
                }
                Button(role: .destructive) { AudiobookCloudSync.disableSync(bookID: book.id); tick += 1 } label: {
                    Label("Stop syncing", systemImage: "icloud.slash")
                }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(Color.skTextDim)
            }
        }
        .listRowBackground(Color.skSurface)
    }
}
