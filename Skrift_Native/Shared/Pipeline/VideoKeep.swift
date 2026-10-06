import Foundation

/// C63 / C148 / D44 / D172: a video filed Inspiration / Idea / Project keeps its movie as a
/// synced `MemoAsset` (`Kind.video`), so the portfolio export can copy it from whichever device
/// exports. A Personal video never syncs and is never exported. ONE rule for both apps and the
/// share extension, so the cap, the file name and the wording cannot drift.
/// Foundation only: the share extension compiles this file.
enum VideoKeep {

    /// The most a kept movie may weigh (~200 MB, D44). A larger one is refused: the note and its
    /// transcript still import, the movie is not kept.
    static let maxBytes: Int64 = 200 * 1_000_000

    /// True when a movie of this size may be kept.
    static func fits(byteCount: Int64) -> Bool { byteCount <= maxBytes }

    /// The size of a file, nil when it is not there.
    static func byteCount(of url: URL) -> Int64? {
        guard let n = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
        else { return nil }
        return n.int64Value
    }

    /// The synced movie's file name (one flat recordings folder on the phone, so the memo id keeps
    /// it unique). The extension is the source movie's, `mov` when it has none.
    static func filename(memoID: UUID, sourceExtension: String) -> String {
        let ext = sourceExtension.trimmingCharacters(in: .whitespaces).lowercased()
        return "video_\(memoID.uuidString).\(ext.isEmpty ? "mov" : ext)"
    }

    /// The working-folder name the Mac keeps a note's movie under (`source.<ext>`), from the
    /// synced asset's file name.
    static func macSourceName(forAssetFilename name: String) -> String {
        let ext = (name as NSString).pathExtension
        return "source." + (ext.isEmpty ? "mov" : ext)
    }

    /// The share card's honest line (replaces "the video file itself isn't kept").
    static let shareCardLine =
        "Transcribes on-device · the movie is kept only if you file the note Inspiration, Idea or Project"

    /// The share card's line for a movie over the cap.
    static let tooLargeMessage =
        "This video is over 200 MB, so the movie can't be kept. The transcript still is."

    /// The share card's line for a given movie size.
    static func shareCardLine(byteCount: Int64?) -> String {
        if let byteCount, !fits(byteCount: byteCount) { return tooLargeMessage }
        return shareCardLine
    }
}
