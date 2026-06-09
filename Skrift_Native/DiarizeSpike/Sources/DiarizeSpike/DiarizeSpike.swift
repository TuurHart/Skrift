import Foundation
import FluidAudio

// Sortformer spike: NVIDIA's Parakeet-coupled diarizer (vs the legacy pyannote
// DiarizerManager). Run: swift run DiarizeSpike <path-to-audio>
@main
struct DiarizeSpike {
    static func main() async {
        func err(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
        guard CommandLine.arguments.count > 1 else { err("usage: DiarizeSpike <audio>"); exit(2) }
        let path = CommandLine.arguments[1]
        do {
            let config = SortformerConfig.default
            err("⏳ loading Sortformer models…")
            let models = try await SortformerModels.loadFromHuggingFace(config: config)
            let diarizer = SortformerDiarizer(config: config)
            diarizer.initialize(models: models)

            err("⏳ loading audio \(path)…")
            let samples = try AudioConverter(sampleRate: 16000).resampleAudioFile(URL(fileURLWithPath: path))
            err("   \(samples.count) samples (~\(samples.count / 16000)s @16k)")

            err("⏳ diarizing (Sortformer)…")
            let result = try diarizer.processComplete(samples)

            // result.speakers: [Int: speaker timeline]; each slot has finalizedSegments.
            var perSlot: [Int: [DiarizerSegment]] = [:]
            for (index, speaker) in result.speakers { perSlot[index] = speaker.finalizedSegments }
            let active = perSlot.filter { !$0.value.isEmpty }.sorted { $0.key < $1.key }

            print("distinct speakers (with speech): \(active.count) → slots \(active.map(\.key))")
            for (slot, segs) in active {
                for s in segs.sorted(by: { $0.startTime < $1.startTime }) {
                    print(String(format: "  spk %d  %6.2f–%6.2f s  (%.1fs)",
                                 slot, Double(s.startTime), Double(s.endTime),
                                 Double(s.endTime - s.startTime)))
                }
            }
        } catch {
            err("❌ ERROR: \(error)")
            exit(1)
        }
    }
}
