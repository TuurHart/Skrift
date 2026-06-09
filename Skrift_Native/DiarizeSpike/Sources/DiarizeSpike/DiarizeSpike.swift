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

            // Optional fusion: assign each transcribed word (from a wt_*.json sidecar)
            // to the speaker whose segment covers its midpoint, group consecutive words
            // into turns → the real `**Speaker N:**` attributed transcript.
            if CommandLine.arguments.count > 2 {
                struct Seg { let slot: Int; let start: Double; let end: Double }
                struct WT: Decodable { let word: String; let start: Double; let end: Double }
                let flat = active.flatMap { slot, segs in segs.map { Seg(slot: slot, start: Double($0.startTime), end: Double($0.endTime)) } }
                    .sorted { $0.start < $1.start }
                let words = try JSONDecoder().decode([WT].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
                func speaker(at t: Double) -> Int {
                    if let s = flat.first(where: { t >= $0.start && t <= $0.end }) { return s.slot }
                    return flat.min(by: { abs(($0.start + $0.end) / 2 - t) < abs(($1.start + $1.end) / 2 - t) })?.slot ?? 0
                }
                var turns: [(Int, [String])] = []
                for w in words {
                    let spk = speaker(at: (w.start + w.end) / 2)
                    if turns.last?.0 == spk { turns[turns.count - 1].1.append(w.word) }
                    else { turns.append((spk, [w.word])) }
                }
                print("\n=== fused attributed transcript (\(turns.count) turns) ===")
                for (slot, ws) in turns { print("**Speaker \(slot + 1):** \(ws.joined(separator: " "))\n") }
            }
        } catch {
            err("❌ ERROR: \(error)")
            exit(1)
        }
    }
}
