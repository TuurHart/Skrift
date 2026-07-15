import AVFoundation

/// RMS amplitude measurement for the phantom-transcript guard. Both apps run the
/// same Parakeet models, so the energy reading that gates
/// `BPEMerge.shouldDropAsPhantom` must be identical on phone and Mac — each
/// previously carried a hand-mirrored copy of `averageRMS` (the phone's inline in
/// its TranscriptionService), a fresh drift surface once the guard itself went
/// shared. One physical copy here removes it.
enum AudioRMS {

    /// Mean RMS amplitude across the whole file, chunked so a long recording is
    /// never fully loaded into memory. Consulted only for tiny transcripts (the
    /// caller gates it lazily). nil if unreadable.
    static func averageRMS(url: URL) -> Float? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let cap: AVAudioFrameCount = 16384
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: cap) else { return nil }
        var sumSquares = 0.0
        var total = 0.0
        while (try? file.read(into: buffer, frameCount: cap)) != nil {
            let n = Int(buffer.frameLength)
            if n == 0 { break }
            guard let ch = buffer.floatChannelData else { break }
            let s = ch[0]
            var i = 0
            while i < n { let v = Double(s[i]); sumSquares += v * v; i += 1 }
            total += Double(n)
        }
        return total == 0 ? nil : Float((sumSquares / total).squareRoot())
    }

    /// RMS of an already-decoded PCM buffer (first channel) — the whole-book chunk
    /// path measures energy without the temp-file round-trip. nil if empty/unreadable.
    static func rms(of buffer: AVAudioPCMBuffer) -> Float? {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return nil }
        let n = Int(buffer.frameLength)
        let samples = channels[0]
        var sumSquares: Double = 0
        for i in 0..<n {
            let s = Double(samples[i])
            sumSquares += s * s
        }
        return Float((sumSquares / Double(n)).squareRoot())
    }
}
