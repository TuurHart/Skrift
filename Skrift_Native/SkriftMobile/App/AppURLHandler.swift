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
        // skrift://record (Lock Screen widget / Siri / any deep link) → start a
        // recording via the same bridge the Record App Intent uses.
        if url.scheme == "skrift", url.host == "record" {
            RecordingIntentBridge.shared.requestStart()
        }
    }
}
