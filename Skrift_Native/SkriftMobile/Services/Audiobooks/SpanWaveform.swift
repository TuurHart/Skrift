import AVFoundation
import Foundation

/// RMS bars for the capture micro-scrubber's waveform strip: read ONLY the
/// visible window (`AVAssetReader.timeRange`) of the book's audio off the main
/// actor and bucket it into bar heights (0…1). Falls back to a deterministic
/// placeholder when the audio can't be read (the strip is informative
/// decoration — the handles + grains are the real tools).
enum SpanWaveform {
    static func bars(url: URL, start: TimeInterval, end: TimeInterval, count: Int = 96) async -> [Float] {
        guard end > start, count > 0 else { return placeholder(count: max(1, count)) }
        let result = await Task.detached(priority: .userInitiated) { () -> [Float]? in
            await read(url: url, start: start, end: end, count: count)
        }.value
        return result ?? placeholder(count: count)
    }

    /// Deterministic pseudo-waveform (stable across renders, like the mock).
    static func placeholder(count: Int) -> [Float] {
        (0..<count).map { i in
            let f = Double(i)
            let h = 0.18 + 0.32 * abs(sin(f * 0.55)) + 0.24 * abs(sin(f * 0.21 + 2)) + Double((i * 7919) % 13) / 90
            return Float(min(0.9, max(0.08, h)))
        }
    }

    // MARK: - Reader

    private static func read(url: URL, start: TimeInterval, end: TimeInterval, count: Int) async -> [Float]? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
        guard reader.startReading() else { return nil }

        // One RMS value per sample buffer, resampled to `count` bars after.
        var chunkRMS: [Float] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<CChar>?
            guard CMBlockBufferGetDataPointer(
                block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer
            ) == kCMBlockBufferNoErr, let pointer, length >= MemoryLayout<Float>.size else { continue }

            let sampleCount = length / MemoryLayout<Float>.size
            var sumSquares: Double = 0
            pointer.withMemoryRebound(to: Float.self, capacity: sampleCount) { floats in
                for i in 0..<sampleCount {
                    let v = Double(floats[i])
                    sumSquares += v * v
                }
            }
            chunkRMS.append(Float((sumSquares / Double(sampleCount)).squareRoot()))
        }
        guard !chunkRMS.isEmpty else { return nil }

        // Resample chunk RMS → `count` bars, normalized to the loudest bar.
        var bars = [Float](repeating: 0, count: count)
        for barIndex in 0..<count {
            let lo = barIndex * chunkRMS.count / count
            let hi = max(lo + 1, (barIndex + 1) * chunkRMS.count / count)
            let slice = chunkRMS[lo..<min(hi, chunkRMS.count)]
            bars[barIndex] = slice.isEmpty ? 0 : slice.reduce(0, +) / Float(slice.count)
        }
        let peak = bars.max() ?? 0
        guard peak > 0 else { return bars }
        return bars.map { max(0.06, $0 / peak) }
    }
}
