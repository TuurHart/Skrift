import Foundation
import AVFoundation

/// Reads an audio file's embedded RECORDING date (the m4a `creation_time` /
/// QuickTime `creationDate` metadata). This lives inside the file, so it survives
/// copies — unlike the filesystem date, which becomes the import/copy time. Used so a
/// ported or dropped recording shows when it was recorded, not when it was imported.
enum AudioMetadata {
    static func recordingDate(of url: URL) async -> Date? {
        let asset = AVURLAsset(url: url)
        guard let item = (try? await asset.load(.creationDate)) ?? nil else { return nil }
        if let d = (try? await item.load(.dateValue)) ?? nil { return d }
        if let s = (try? await item.load(.stringValue)) ?? nil, let d = parse(s) { return d }
        return nil
    }

    private static func parse(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }
}
