import AVFoundation
import Foundation

/// The ONE clip-stitcher both apps use for "N voice notes → One note" (C68, C145, C238).
///
/// Lifted out of the phone's `MemoSaver` (2026-09-30, Q74) so a Mac drop of three clips and a
/// phone share of the same three yield the same audio. Nothing about the algorithm changed:
/// SAMPLE-ACCURATE `AVAudioFile` frame reads, re-encoded once to AAC. The
/// AVMutableComposition + export path produced a phantom silent tail on WhatsApp voice notes
/// (device round 2: `merged ok; duration=287.5s` with the real content ending early) — the
/// same compressed-audio weakness as the audiobook chunk-drift gotcha.
enum AudioClipMerge {

    enum MergeError: Error, Equatable { case noAudio }

    /// Concatenate the audio of `sources` (in array order) into a single m4a at `dest`.
    /// Unreadable clips are skipped (reported through `log`); throws `noAudio` when none
    /// contribute a frame. Synchronous and CPU-heavy: call it OFF the main actor.
    static func merge(sources: [URL], to dest: URL, log: (String) -> Void = { _ in }) throws {
        try? FileManager.default.removeItem(at: dest)
        var out: AVAudioFile?
        var outFormat: AVAudioFormat?
        var wroteFrames = false

        for src in sources {
            guard let file = try? AVAudioFile(forReading: src) else {
                log("mergeAudio: skipping unreadable clip \(src.lastPathComponent)")
                continue
            }
            let proc = file.processingFormat
            if out == nil {
                // AAC output at the first readable clip's rate/channels.
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: proc.sampleRate,
                    AVNumberOfChannelsKey: proc.channelCount,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                ]
                out = try AVAudioFile(forWriting: dest, settings: settings)
                outFormat = proc
            }
            guard let out, let outFormat else { continue }

            // Later clips in a different PCM format get converted to the first
            // clip's (rare — a WhatsApp batch is uniform). Per-file converter so
            // its internal state never crosses clip boundaries.
            let converter = proc == outFormat ? nil : AVAudioConverter(from: proc, to: outFormat)
            let chunkFrames: AVAudioFrameCount = 32_768
            // framePosition guard: AVAudioFile.read THROWS (-50) when asked to
            // read at EOF rather than returning zero frames.
            while file.framePosition < file.length {
                guard let buf = AVAudioPCMBuffer(pcmFormat: proc, frameCapacity: chunkFrames) else { break }
                try file.read(into: buf)
                guard buf.frameLength > 0 else { break }
                if let converter {
                    let ratio = outFormat.sampleRate / proc.sampleRate
                    let cap = AVAudioFrameCount(Double(buf.frameLength) * ratio) + 64
                    guard let cbuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: cap) else { break }
                    var fed = false
                    var convErr: NSError?
                    converter.convert(to: cbuf, error: &convErr) { _, status in
                        if fed { status.pointee = .noDataNow; return nil }
                        fed = true
                        status.pointee = .haveData
                        return buf
                    }
                    if convErr != nil {
                        log("mergeAudio: convert failed on \(src.lastPathComponent): \(convErr!)")
                        break
                    }
                    if cbuf.frameLength > 0 {
                        try out.write(from: cbuf)
                        wroteFrames = true
                    }
                } else {
                    try out.write(from: buf)
                    wroteFrames = true
                }
            }
        }
        guard wroteFrames else { throw MergeError.noAudio }
    }
}

/// What to do with several voice notes that arrive together (C68): ONE note (default — the
/// clips stitched in order, one transcription pass) or N notes. The wording is the phone's
/// share-sheet chooser word for word, so the Mac sheet cannot drift from it.
enum AudioImportChoice: String, CaseIterable, Sendable {
    case oneNote
    case separateNotes

    /// The chooser only exists when there is something to choose between.
    static func needsChoice(clipCount: Int) -> Bool { clipCount >= 2 }

    static let `default`: AudioImportChoice = .oneNote

    func title(clipCount: Int) -> String {
        switch self {
        case .oneNote: return "One note"
        case .separateNotes: return "\(clipCount) notes"
        }
    }

    var subtitle: String {
        switch self {
        case .oneNote: return "Clips stitched in order — one story, one transcript"
        case .separateNotes: return "Each voice note becomes its own memo"
        }
    }

    func confirmTitle(clipCount: Int) -> String {
        switch self {
        case .oneNote: return "Save as one note"
        case .separateNotes: return "Save \(clipCount) notes"
        }
    }

    var combines: Bool { self == .oneNote }
}
