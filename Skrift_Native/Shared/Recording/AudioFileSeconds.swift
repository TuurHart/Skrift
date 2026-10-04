import AVFoundation

// Q219 / C239: the ONE "how long is this audio file" rule, for every open AVAudioFile on
// both apps (record, recovery, import, share, ingest, audiobook import). An extension on
// the OPEN file, not a URL helper: the recorder asks its still-open writing file too.
// Deliberately not folded in: `MacMemoAuthor.audioDuration` (AVURLAsset, nil on failure).
extension AVAudioFile {
    /// Duration in seconds from the file's frame count and native sample rate; 0 when the
    /// format reports no sample rate.
    var seconds: Double {
        let rate = fileFormat.sampleRate
        guard rate > 0 else { return 0 }
        return Double(length) / rate
    }
}
