import Foundation

/// The pure label/fraction rules the Books list row AND the iPad shelf tile share, so the
/// two surfaces say the same thing about a book (parity audit P49). No SwiftUI here.
enum BookTileState {
    /// The transfer bar's caption: "Uploading audio · 38%" / "Downloading · 61%". The % drops
    /// out in the brief pre-first-byte window (`fraction == nil`) so we never show a misleading "0%".
    static func transferLabel(uploading: Bool, fraction: Double?) -> String {
        guard let fraction else { return uploading ? "Uploading audio…" : "Downloading…" }
        return "\(uploading ? "Uploading audio" : "Downloading") · \(percent(fraction))%"
    }

    static func percent(_ fraction: Double) -> Int {
        Int((min(max(fraction, 0), 1) * 100).rounded())
    }

    /// Fallback line for a running re-align when the runner has no stage text yet.
    static let realignFallback = "Matching up your book text…"

    /// The re-align line for a book, or nil when no re-align runs for it.
    static func realignLine(active: Bool, stage: String?) -> String? {
        active ? (stage ?? realignFallback) : nil
    }

    /// Spoken sync state, nil when the book is local-only (no sync record).
    static func syncPhrase(_ state: AudiobookLibraryView.BookSyncState?) -> String? {
        switch state {
        case .synced: return "synced to your devices"
        case .downloadAvailable: return "synced, download to this device"
        case .uploading: return "uploading"
        case .downloading: return "downloading"
        case .none: return nil
        }
    }

    /// The tile's / row's VoiceOver label: title, author, time left, then sync state, transfer % and re-align.
    static func accessibilityLabel(title: String, author: String, timeLeft: String,
                                   syncState: AudiobookLibraryView.BookSyncState?,
                                   transferFraction: Double?, realign: String?) -> String {
        var label = author.isEmpty ? title : "\(title) by \(author)"
        label += ", \(timeLeft) left"
        if let phrase = syncPhrase(syncState) {
            if let f = transferFraction, syncState == .uploading || syncState == .downloading {
                label += ", \(phrase) \(percent(f)) percent"
            } else {
                label += ", \(phrase)"
            }
        }
        if let realign { label += ", \(realign)" }
        return label
    }

    // MARK: Delete dialog copy: "this device", never "this iPhone" (the shelf is the iPad's).

    static let removeThisDeviceTitle = "Remove from this device only"

    static func deleteMessage(synced: Bool) -> String {
        synced
            ? "It's synced to your devices. Removing everywhere deletes the audio + read-along text from all of them. Your bookmarks and captured notes are kept."
            : "This removes the book and its audio from this device. Your bookmarks and captured notes are kept."
    }
}
