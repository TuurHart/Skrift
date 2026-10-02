import SwiftUI

/// 📦 "Share book…" — the outgoing half (mock `book-sharing.html` screens 2, 2b, 3).
///
/// One file, one button. There is deliberately nothing to configure: the audio
/// always goes, the book text goes if there is one, and your bookmarks, position
/// and playback speed never do. So the sheet's whole job is to say what will be
/// sent and how big it is, then get out of the way.
struct BookShareSheet: View {
    let book: Audiobook

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .ready
    @State private var packagedURL: URL?
    @State private var failure: String?
    @State private var task: Task<Void, Never>?
    /// The estimated bundle size, stat'ed once when the sheet is built (not per progress callback).
    private let totalBytes: Int64

    private enum Phase: Equatable {
        case ready
        case packaging(Double)
    }

    init(book: Audiobook) {
        self.book = book
        totalBytes = BookBundle.estimatedSize(book: book, folder: AudiobookLibraryStore.shared.folder(for: book.id))
    }

    var body: some View {
        BookTransferSheet(
            id: "book-share-sheet", detent: 280,
            title: book.title,
            subtitle: BookShareCopy.subtitle(author: book.author, duration: book.duration),
            failure: failure,
            cover: { BookCoverView(book: book) }
        ) {
            switch phase {
            case .ready:
                Text(BookShareCopy.contents(hasText: !book.attachedTextFilenames.isEmpty, bytes: totalBytes))
                    .font(.system(size: 13)).foregroundStyle(Color.skTextDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 14)
                    .monospacedDigit()

                Button { package() } label: {
                    Text("Share")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(Color.skAccent, in: RoundedRectangle.sk(13))
                }
                .padding(.top, 14)
                .accessibilityIdentifier("book-share-start")

            case .packaging(let fraction):
                // Real byte progress, not a spinner — 797 MB takes long enough
                // that an honest number is the difference between waiting and
                // wondering whether it hung.
                Text(BookShareCopy.packagingProgress(written: Int64(Double(totalBytes) * fraction), total: totalBytes))
                    .font(.system(size: 13)).foregroundStyle(Color.skTextDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 14)
                    .monospacedDigit()

                ThinProgressBar(fraction: fraction)
                    .padding(.top, 14)

                Button {
                    task?.cancel()
                    phase = .ready
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15)).foregroundStyle(Color.skTextDim)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .padding(.top, 2)
            }
        }
        // The system share sheet is the destination picker — AirDrop, Messages,
        // Save to Files all come free, so Skrift never grows one of its own.
        .sheet(item: Binding(get: { packagedURL.map(SharePayload.init) },
                             set: { if $0 == nil { packagedURL = nil; dismiss() } })) { payload in
            ShareSheet(items: [payload.url])
        }
        .onDisappear { task?.cancel() }
    }

    private func package() {
        failure = nil
        phase = .packaging(0)
        let book = self.book
        let folder = AudiobookLibraryStore.shared.folder(for: book.id)
        let destination = BookBundle.stagedURL(for: book)

        task = Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try BookBundle.write(book: book, folder: folder, to: destination) { fraction in
                        Task { @MainActor in
                            // Blocks a late callback after Cancel put the phase back to .ready.
                            guard case .packaging = phase else { return }
                            phase = .packaging(fraction)
                        }
                    }
                }.value
                guard !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: destination)
                    return
                }
                // The ready layout stays under the system share sheet.
                phase = .ready
                packagedURL = destination
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: destination)
            } catch {
                phase = .ready
                failure = (error as? LocalizedError)?.errorDescription
                    ?? "Couldn't package this book."
            }
        }
    }

    private struct SharePayload: Identifiable {
        let url: URL
        var id: String { url.path }
    }
}

// MARK: - Pure copy (unit-tested — BookShareCopyTests.swift)

/// The sheet's strings, as plain functions of their inputs so the wording is
/// assertable without a view.
enum BookShareCopy {

    /// "Homer · Emily Wilson · 28 h 04" (the length is `BookTextDisplay.durationText`;
    /// the signed mock draws "28h 04m", the pinned tests fix the spaced form).
    static func subtitle(author: String, duration: TimeInterval) -> String {
        let length = BookTextDisplay.durationText(duration)
        return author.isEmpty ? length : "\(author) · \(length)"
    }

    /// "Audio + book text · 797 MB", or "Audio · 164 MB" when there is no ePub.
    /// The transcript and alignment ride along unmentioned: they are plumbing
    /// that saves the recipient hours of transcription, not a thing to decide
    /// about.
    static func contents(hasText: Bool, bytes: Int64) -> String {
        "\(hasText ? "Audio + book text" : "Audio") · \(size(bytes))"
    }

    /// "486 of 797 MB"
    static func packagingProgress(written: Int64, total: Int64) -> String {
        "\(ByteCountFormatter.string(fromByteCount: written, countStyle: .file).replacingOccurrences(of: " MB", with: "")) of \(size(total))"
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
