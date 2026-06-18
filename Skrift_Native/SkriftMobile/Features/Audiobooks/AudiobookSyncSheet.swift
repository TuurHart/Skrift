import SwiftUI

/// The "Turn it on" sheet for per-book audiobook sync (mock
/// `standalone-audiobook-sync.html`, screen 1). Replaces the bare menu-item toggle:
/// cover + title/author/duration, a single "Sync this book to my devices" switch, the
/// per-book SIZE (summed from local files — on-device, no CloudKit), a live transfer
/// card while audio is uploading/downloading (the REAL % from the raw-CloudKit
/// transport), and an iCloud-storage note. Presented from BOTH the library long-press
/// and the player ⋯ (locked: same sheet from either).
struct AudiobookSyncSheet: View {
    let book: Audiobook
    @ObservedObject private var cloudSync = CloudSyncMonitor.shared
    @State private var isOn: Bool
    @Environment(\.dismiss) private var dismiss

    init(book: Audiobook) {
        self.book = book
        _isOn = State(initialValue: AudiobookCloudSync.isSynced(bookID: book.id))
    }

    private var sizeText: String {
        let bytes = AudiobookCloudSync.localSize(of: book)
        guard bytes > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private var durationText: String {
        let total = Int(max(0, book.duration).rounded())
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }

    private var transfer: CloudSyncMonitor.AudiobookTransfer? { cloudSync.bookTransfers[book.id] }

    var body: some View {
        ZStack {
            Color.skSurface.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(Color.skBorder).frame(width: 34, height: 4)
                    .frame(maxWidth: .infinity).padding(.top, 8).padding(.bottom, 16)

                bookRow.padding(.bottom, 4)
                toggleRow
                if let transfer { progressCard(transfer).padding(.top, 14) }
                note.padding(.top, 14)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.margin)
            .padding(.bottom, 8)
        }
        .presentationDetents([.height(transfer == nil ? 320 : 400)])
        .accessibilityIdentifier("audiobook-sync-sheet")
    }

    private var bookRow: some View {
        HStack(spacing: 12) {
            BookCoverView(book: book)
                .frame(width: 50, height: 50)
                .clipShape(.rect(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.skText).lineLimit(1)
                Text(sizeText.isEmpty ? book.author : "\(book.author) · \(durationText) · \(sizeText)")
                    .font(.system(size: 12)).foregroundStyle(Color.skTextDim).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var toggleRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sync this book to my devices")
                    .font(.system(size: 14)).foregroundStyle(Color.skText)
                Text("Resume on any device. Audio uploads to iCloud.")
                    .font(.system(size: 12)).foregroundStyle(Color.skTextDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { isOn }, set: { toggle(to: $0) }))
                .labelsHidden()
                .tint(Color.skAccent)
                .accessibilityIdentifier("audiobook-sync-toggle")
        }
        .padding(.top, 13)
        .overlay(alignment: .top) { Rectangle().fill(Color.skBorder).frame(height: 0.5) }
    }

    private func progressCard(_ transfer: CloudSyncMonitor.AudiobookTransfer) -> some View {
        let up = transfer.direction == .up
        let pct = Int((transfer.fraction * 100).rounded())
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(up ? "Uploading audio…" : "Downloading…")
                    .font(.system(size: 12)).foregroundStyle(Color.skTextDim)
                Spacer()
                Text(sizeText.isEmpty ? "\(pct)%" : "\(pct)% · \(sizeText)")
                    .font(.system(size: 12)).monospacedDigit().foregroundStyle(Color.skTextDim)
            }
            ProgressView(value: transfer.fraction)
                .progressViewStyle(.linear).tint(Color.skAccent)
        }
        .padding(.horizontal, 13).padding(.vertical, 12)
        .background(Color.skElev, in: .rect(cornerRadius: 12, style: .continuous))
    }

    private var note: some View {
        Text(noteText)
            .font(.system(size: 11.5)).foregroundStyle(Color.skTextFaint)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(1.5)
    }

    private var noteText: String {
        let size = sizeText.isEmpty ? "the audio" : sizeText
        return "Position & bookmarks sync the moment this is on. Audio (\(size)) uploads once, then your other devices download it. Uses your iCloud storage — only for books you turn on."
    }

    private func toggle(to on: Bool) {
        guard on != isOn else { return }
        isOn = on
        if on {
            AudiobookCloudSync.enableSync(book: book)
            Task { await AudiobookCloudSync.reconcile() }
        } else {
            Task { await AudiobookCloudSync.disableSync(bookID: book.id) }
        }
    }
}
