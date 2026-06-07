import Foundation
import AVFoundation

/// Offline audio preprocessing before ASR: a high-pass filter (cuts low-frequency
/// rumble/handling noise that hurts transcription) + a modest peak normalize,
/// rendered to a 16 kHz mono WAV (Parakeet's native rate). Mirrors the high-pass +
/// loudness parts of the old ffmpeg chain. The afftdn adaptive denoiser has NO
/// faithful native equivalent, so it's intentionally dropped (A4 decision) — this
/// stays pure-AVFoundation with no external ffmpeg dependency.
///
/// Self-contained (only AVFoundation) so it can be verified standalone without the
/// app/MLX. Returns false on any failure; the caller then keeps the original file.
enum AudioPreprocessor {
    static let asrSampleRate = 16000.0

    @discardableResult
    static func process(input: URL, output: URL, highpassHz: Int, targetPeak: Float = 0.89) -> Bool {
        guard let scheduleFile = try? AVAudioFile(forReading: input) else { return false }
        let inFormat = scheduleFile.processingFormat
        guard inFormat.sampleRate > 0, scheduleFile.length > 0 else { return false }

        // Gain to lift a quiet source toward `targetPeak` (clamped + measured on a
        // separate file handle so it doesn't disturb the scheduled read position).
        var gainDB: Float = 0
        if let peakFile = try? AVAudioFile(forReading: input) {
            let peak = measurePeak(peakFile)
            if peak > 1e-6 { gainDB = max(-6, min(18, 20 * log10f(targetPeak / peak))) }
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 1)
        let band = eq.bands[0]
        band.filterType = .highPass
        band.frequency = Float(max(20, highpassHz))
        band.bandwidth = 0.5
        band.bypass = highpassHz <= 0
        eq.globalGain = gainDB
        engine.attach(player)
        engine.attach(eq)
        engine.connect(player, to: eq, format: inFormat)
        engine.connect(eq, to: engine.mainMixerNode, format: inFormat)

        guard let renderFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: asrSampleRate, channels: 1, interleaved: false) else {
            return false
        }
        let maxFrames: AVAudioFrameCount = 4096
        guard (try? engine.enableManualRenderingMode(.offline, format: renderFormat, maximumFrameCount: maxFrames)) != nil,
              let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: maxFrames),
              (try? engine.start()) != nil else {
            return false
        }
        player.scheduleFile(scheduleFile, at: nil)
        player.play()

        let outSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: asrSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        guard let outFile = try? AVAudioFile(forWriting: output, settings: outSettings) else {
            engine.stop(); return false
        }

        let outLength = AVAudioFramePosition(Double(scheduleFile.length) / inFormat.sampleRate * asrSampleRate)
        var framesWritten: AVAudioFramePosition = 0
        render: while engine.manualRenderingSampleTime < outLength {
            let remaining = outLength - engine.manualRenderingSampleTime
            let frames = AVAudioFrameCount(min(Int64(maxFrames), remaining))
            do {
                switch try engine.renderOffline(frames, to: buffer) {
                case .success:
                    try outFile.write(from: buffer)
                    framesWritten += AVAudioFramePosition(buffer.frameLength)
                case .insufficientDataFromInputNode: break render  // input fully consumed
                case .cannotDoInCurrentContext: continue
                case .error: break render
                @unknown default: break render
                }
            } catch { break render }
        }
        player.stop()
        engine.stop()

        // Judge success by frames actually written (NOT by re-reading `output` —
        // the writer hasn't flushed yet here). Accept within ~1 s of expected, so
        // benign end-of-stream statuses after all real audio is written don't fail it.
        return framesWritten >= outLength - AVAudioFramePosition(asrSampleRate)
    }

    /// Peak |sample| across all channels (chunked, never fully loaded).
    private static func measurePeak(_ file: AVAudioFile) -> Float {
        let cap: AVAudioFrameCount = 16384
        guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: cap) else { return 0 }
        let channels = Int(file.processingFormat.channelCount)
        var peak: Float = 0
        while (try? file.read(into: buf, frameCount: cap)) != nil, buf.frameLength > 0 {
            let n = Int(buf.frameLength)
            if let data = buf.floatChannelData {
                for c in 0..<channels {
                    let s = data[c]
                    var i = 0
                    while i < n { peak = max(peak, abs(s[i])); i += 1 }
                }
            }
            if buf.frameLength < cap { break }
        }
        return peak
    }
}
