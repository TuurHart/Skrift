// Writes a 61-minute near-silent AAC m4a (tiny file, real duration) for the
// E2 Books-chooser eyeball. usage: swift mklongm4a.swift <out.m4a> [minutes]
import AVFoundation

let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: mklongm4a <out.m4a> [minutes]"); exit(1) }
let out = URL(fileURLWithPath: args[1])
let minutes = args.count >= 3 ? Double(args[2]) ?? 61 : 61

let sampleRate = 22_050.0
let settings: [String: Any] = [
    AVFormatIDKey: kAudioFormatMPEG4AAC,
    AVSampleRateKey: sampleRate,
    AVNumberOfChannelsKey: 1,
    AVEncoderBitRateKey: 16_000,
]
try? FileManager.default.removeItem(at: out)
// Scoped so the AVAudioFile deinits (finalizing the m4a header) BEFORE exit —
// a top-level writer never deinits and leaves a broken container.
func writeFile() throws {
    let file = try AVAudioFile(forWriting: out, settings: settings)
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let chunkFrames = AVAudioFrameCount(sampleRate * 10)   // 10s per write
    let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames)!
    buf.frameLength = chunkFrames
    // A faint 55 Hz hum instead of pure digital silence — some players/encoders
    // treat all-zero streams oddly, and a hum proves audio is really flowing.
    let data = buf.floatChannelData![0]
    for i in 0..<Int(chunkFrames) {
        data[i] = sinf(Float(i) * 2 * .pi * 55 / Float(sampleRate)) * 0.002
    }
    let totalChunks = Int(minutes * 60 / 10)
    for _ in 0..<totalChunks { try file.write(from: buf) }
}
try writeFile()
print("wrote \(minutes) min → \(out.lastPathComponent)")
