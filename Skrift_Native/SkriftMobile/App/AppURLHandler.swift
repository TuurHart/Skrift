import Foundation

/// Routes incoming URLs to the right action:
/// - a shared audio file ("Open in Skrift" / Share Sheet) → import as a memo
/// - a shared VIDEO file → extract audio + a frame thumbnail → import as a memo
/// - the `skrift://record` deep link → start recording (wired in 8d)
@MainActor
enum AppURLHandler {
    // `.mp4`/`.mov` are deliberately NOT here — those container extensions are
    // checked for a video track first (`MemoSaver.isVideoFile`), and only fall
    // through to audio when audio-only. Pure-audio extensions stay direct.
    private static let audioExtensions: Set<String> =
        ["m4a", "mp3", "wav", "aac", "caf", "aiff", "aif", "opus"]

    static func handle(_ url: URL) {
        if url.isFileURL {
            let ext = url.pathExtension.lowercased()
            // Land the user on the imported memo (A9): it relocates to the media's
            // embedded date, so without the jump it "vanishes" down the list — the
            // same rule the share-sheet drain path already follows.
            if MemoSaver.isVideoFile(url) {
                // A video container (.mov/.mp4/…): strip the audio + grab a frame.
                if let id = MemoSaver().importVideo(from: url) {
                    MemoOpenBridge.shared.open(id)
                }
            } else if audioExtensions.contains(ext) {
                if let id = MemoSaver().importAudio(from: url) {
                    MemoOpenBridge.shared.open(id)
                }
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
