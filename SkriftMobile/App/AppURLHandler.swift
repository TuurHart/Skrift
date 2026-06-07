import Foundation

/// Routes incoming URLs to the right action:
/// - a shared audio file ("Open in Skrift" / Share Sheet) → import as a memo
/// - the `skrift://record` deep link → start recording (wired in 8d)
@MainActor
enum AppURLHandler {
    private static let audioExtensions: Set<String> =
        ["m4a", "mp3", "wav", "aac", "caf", "aiff", "aif", "mp4", "mov", "opus"]

    static func handle(_ url: URL) {
        if url.isFileURL {
            if audioExtensions.contains(url.pathExtension.lowercased()) {
                _ = MemoSaver().importAudio(from: url)
            }
            return
        }
        // skrift://record → start recording (wired in Phase 8d).
    }
}
