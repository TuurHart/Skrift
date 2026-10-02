import SwiftUI

/// 📦 The incoming half — a `.skriftbook` someone AirDropped, offered rather
/// than imported (mock `book-sharing.html` screens 4, 4b).
///
/// Arrival never writes to the library on its own. A shared book is hundreds of
/// megabytes and a title the receiver didn't choose, so the only thing that
/// happens unasked is this sheet.
struct BookImportSheet: View {
    let pending: BookImportBridge.Pending

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .offering
    @State private var unpackedFraction: Double = 0
    @State private var failure: String?
    @State private var task: Task<Void, Never>?
    /// The bundle's size on disk, stat'ed once when the sheet is built.
    private let bundleBytes: Int64

    private enum Phase: Equatable { case offering, unpacking }

    private var book: Audiobook { pending.manifest.book }

    init(pending: BookImportBridge.Pending) {
        self.pending = pending
        bundleBytes = (try? FileManager.default.attributesOfItem(atPath: pending.url.path)[.size] as? Int64) as? Int64 ?? 0
    }

    var body: some View {
        BookTransferSheet(
            id: "book-import-sheet", detent: pending.alreadyHave ? 210 : 290,
            title: book.title,
            subtitle: pending.alreadyHave
                ? "Already in your books"
                : BookShareCopy.subtitle(author: book.author, duration: book.duration),
            failure: failure,
            cover: { BundleCover(manifest: pending.manifest, url: pending.url) }
        ) {
            if pending.alreadyHave {
                // Nothing to decide: the id already exists, so importing again
                // would only duplicate what's there.
                actionButton("OK") { dismiss() }
                    .padding(.top, 18)
            } else {
                switch phase {
                case .offering:
                    Text(BookShareCopy.contents(hasText: !pending.manifest.textFilenames.isEmpty,
                                                bytes: bundleBytes))
                        .font(.system(size: 13)).foregroundStyle(Color.skTextDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 14)
                        .monospacedDigit()

                    actionButton("Add to my books") { unpack() }
                        .padding(.top, 14)
                        .accessibilityIdentifier("book-import-accept")

                    Button { dismiss() } label: {
                        Text("Not now")
                            .font(.system(size: 15)).foregroundStyle(Color.skTextDim)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .padding(.top, 2)

                case .unpacking:
                    Text("Adding…")
                        .font(.system(size: 13)).foregroundStyle(Color.skTextDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 14)
                    ThinProgressBar(fraction: unpackedFraction)
                        .padding(.top, 14)
                }
            }
        }
        .onDisappear { task?.cancel() }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(Color.skAccent, in: RoundedRectangle.sk(13))
        }
    }

    private func unpack() {
        failure = nil
        phase = .unpacking
        let url = pending.url
        let manifest = pending.manifest
        let library = AudiobookLibraryStore.shared
        let folder = library.folder(for: manifest.book.id)

        task = Task {
            do {
                let landed = try await Task.detached(priority: .userInitiated) {
                    try BookBundle.unpack(at: url, manifest: manifest, into: folder,
                                          library: library) { fraction in
                        Task { @MainActor in unpackedFraction = fraction }
                    }
                }.value
                guard !Task.isCancelled else { return }
                library.add(landed)
                dismiss()
            } catch {
                phase = .offering
                failure = (error as? LocalizedError)?.errorDescription
                    ?? "Couldn't add this book."
            }
        }
    }
}

/// The cover pulled straight out of the bundle, so the sheet can show the real
/// book before anything is unpacked. One small entry out of a 797 MB archive;
/// falls back to the same gradient placeholder the library uses.
private struct BundleCover: View {
    let manifest: BookBundleManifest
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                // Same placeholder the library uses. The book isn't on disk yet, so
                // the cover cache misses and this is what shows until the entry
                // above is pulled out of the archive.
                BookCoverView(book: manifest.book)
            }
        }
        .task {
            guard manifest.coverFilename != nil, image == nil else { return }
            let url = self.url, manifest = self.manifest
            image = await Task.detached(priority: .userInitiated) {
                BookBundle.coverImageData(at: url, manifest: manifest).flatMap(UIImage.init(data:))
            }.value
        }
    }
}
