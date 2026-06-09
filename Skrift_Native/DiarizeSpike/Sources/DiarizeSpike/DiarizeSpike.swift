import Foundation
import FluidAudio

@main
struct DiarizeSpike {
    static func main() async {
        func err(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
        guard CommandLine.arguments.count > 1 else {
            err("usage: DiarizeSpike <path-to-audio>"); exit(2)
        }
        let path = CommandLine.arguments[1]
        let threshold = CommandLine.arguments.count > 2 ? (Float(CommandLine.arguments[2]) ?? 0.7) : 0.7
        do {
            err("⏳ downloading/loading diarization models…")
            let models = try await DiarizerModels.downloadIfNeeded()
            var config = DiarizerConfig()
            config.clusteringThreshold = threshold
            err("   clusteringThreshold=\(threshold)")
            let manager = DiarizerManager(config: config)
            manager.initialize(models: models)

            err("⏳ loading audio \(path)…")
            let samples = try AudioConverter(sampleRate: 16000).resampleAudioFile(URL(fileURLWithPath: path))
            err("   \(samples.count) samples (~\(samples.count / 16000)s @16k)")

            err("⏳ diarizing…")
            let result = try manager.performCompleteDiarization(samples, sampleRate: 16000)

            print("segments: \(result.segments.count)")
            for s in result.segments {
                print(String(format: "  %@  %6.2f–%6.2f s  (%.1fs)  quality=%.2f  emb=%d",
                             s.speakerId, s.startTimeSeconds, s.endTimeSeconds,
                             s.durationSeconds, s.qualityScore, s.embedding.count))
            }
            let speakers = Set(result.segments.map(\.speakerId)).sorted()
            print("distinct speakers: \(speakers.count) → \(speakers)")
            if let db = result.speakerDatabase {
                print("speaker DB embeddings: \(db.mapValues { $0.count })")
            }
        } catch {
            err("❌ ERROR: \(error)")
            exit(1)
        }
    }
}
