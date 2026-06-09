import Foundation
import FluidAudio

// Sortformer spike: NVIDIA's Parakeet-coupled diarizer (vs the legacy pyannote
// DiarizerManager). Run: swift run DiarizeSpike <path-to-audio> [wt.json] [--embed]
//
// `--embed` runs the IDENTITY experiment (the conversation-mode voice layer): after
// diarizing it loads the wespeaker embedding model (DiarizerModels) and extracts a
// per-speaker embedding, then prints the cosine MATRIX (cross-speaker similarity) and a
// same-speaker self-similarity (each slot's first half vs second half). That gives the
// empirical band to pick the auto-match threshold from — same-speaker cosine should sit
// clearly ABOVE cross-speaker cosine; the threshold goes between them.
@main
struct DiarizeSpike {
    static func main() async {
        func err(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
        let allArgs = Array(CommandLine.arguments.dropFirst())
        let embedMode = allArgs.contains("--embed")
        // Cross-recording check: embed the dominant speaker of <audio> and of <fileB>
        // and print their cosine — the real "name in A, recognize in B" signal.
        let pairFile: String? = allArgs.firstIndex(of: "--pair").flatMap { i in
            i + 1 < allArgs.count ? allArgs[i + 1] : nil
        }
        var positionals: [String] = []
        var skipNext = false
        for a in allArgs {
            if skipNext { skipNext = false; continue }
            if a == "--pair" { skipNext = true; continue }
            if a.hasPrefix("--") { continue }
            positionals.append(a)
        }
        guard let path = positionals.first else {
            err("usage: DiarizeSpike <audio> [wt.json] [--embed] [--pair <fileB>]"); exit(2)
        }
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

            if embedMode {
                try await runEmbedExperiment(aPath: path, samples: samples, active: active, pairFile: pairFile, err: err)
            }

            // Optional fusion: assign each transcribed word (from a wt_*.json sidecar)
            // to the speaker whose segment covers its midpoint, group consecutive words
            // into turns → the real `**Speaker N:**` attributed transcript.
            if positionals.count > 1 {
                struct Seg { let slot: Int; let start: Double; let end: Double }
                struct WT: Decodable { let word: String; let start: Double; let end: Double }
                let flat = active.flatMap { slot, segs in segs.map { Seg(slot: slot, start: Double($0.startTime), end: Double($0.endTime)) } }
                    .sorted { $0.start < $1.start }
                let words = try JSONDecoder().decode([WT].self, from: Data(contentsOf: URL(fileURLWithPath: positionals[1])))
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

    // MARK: - Identity experiment (wespeaker embedding + cosine)

    /// 10s @16k — the wespeaker model's fixed waveform window (EmbeddingExtractor pads
    /// shorter, and clips longer would overflow the buffer). Cap per-speaker clips here.
    static let maxEmbedSamples = 160_000

    static func runEmbedExperiment(aPath: String, samples: [Float], active: [(key: Int, value: [DiarizerSegment])],
                                   pairFile: String?, err: (String) -> Void) async throws {
        err("⏳ loading wespeaker embedding model (DiarizerModels)…")
        let diarModels = try await DiarizerModels.downloadIfNeeded()
        let manager = DiarizerManager()
        manager.initialize(models: diarModels)

        // Concatenate a slot's segment audio (time-ordered), capped at 10s.
        func clip(_ segs: [DiarizerSegment], from offset: Int = 0) -> [Float] {
            var out: [Float] = []
            for s in segs.sorted(by: { $0.startTime < $1.startTime }) {
                let a = max(0, Int(Double(s.startTime) * 16000)), b = min(samples.count, Int(Double(s.endTime) * 16000))
                if a < b { out.append(contentsOf: samples[a..<b]) }
            }
            if offset > 0 { out = out.count > offset ? Array(out[offset...]) : [] }
            return Array(out.prefix(maxEmbedSamples))
        }

        // Whole-speaker embedding per slot.
        var whole: [(slot: Int, emb: [Float])] = []
        for (slot, segs) in active {
            let c = clip(segs)
            guard c.count >= 8000 else { err("  spk \(slot): too little audio (\(c.count) samples), skip"); continue }
            let emb = try manager.extractSpeakerEmbedding(from: c)
            whole.append((slot, emb))
            err("  spk \(slot): embedded \(c.count) samples → dim \(emb.count), |v|=\(String(format: "%.4f", norm(emb)))")
        }

        print("\n=== CROSS-speaker cosine (different people → want LOW) ===")
        for i in 0..<whole.count {
            for j in (i + 1)..<whole.count {
                print(String(format: "  spk %d ↔ spk %d : cos = %.4f",
                             whole[i].slot, whole[j].slot, cosine(whole[i].emb, whole[j].emb)))
            }
        }

        print("\n=== SAME-speaker cosine (one person, 1st-half ↔ 2nd-half → want HIGH) ===")
        for (slot, segs) in active {
            let full = clip(segs)
            guard full.count >= 16000 else { continue }
            let half = full.count / 2
            let a = Array(full[0..<half]), b = Array(full[half...])
            guard a.count >= 8000, b.count >= 8000 else { continue }
            let ea = try manager.extractSpeakerEmbedding(from: a)
            let eb = try manager.extractSpeakerEmbedding(from: b)
            print(String(format: "  spk %d : cos = %.4f", slot, cosine(ea, eb)))
        }
        print("\n→ pick the match threshold BETWEEN the cross-speaker max and the same-speaker min.")

        // Cross-RECORDING: dominant speaker of this file ↔ dominant speaker of fileB.
        // The real auto-match signal (same person in two different recordings).
        if let pairFile {
            err("⏳ diarizing + embedding dominant speaker of \(pairFile)…")
            let sortformer = SortformerDiarizer(config: .default)
            sortformer.initialize(models: try await SortformerModels.loadFromHuggingFace(config: .default))
            let bSamples = try AudioConverter(sampleRate: 16000).resampleAudioFile(URL(fileURLWithPath: pairFile))
            let bActive = try sortformer.processComplete(bSamples).speakers
                .filter { !$0.value.finalizedSegments.isEmpty }.mapValues { $0.finalizedSegments }
            guard let aDom = active.max(by: { duration($0.value) < duration($1.value) }),
                  let aClip = clipSamples(aDom.value, from: samples),
                  let bDom = bActive.max(by: { duration($0.value) < duration($1.value) }),
                  let bClip = clipSamples(bDom.value, from: bSamples) else {
                print("\n(pair) couldn't isolate a dominant speaker in one of the files"); return
            }
            let aEmb = try manager.extractSpeakerEmbedding(from: aClip)
            let bEmb = try manager.extractSpeakerEmbedding(from: bClip)
            print(String(format: "\n=== CROSS-RECORDING dominant-speaker cosine ===\n  %@ (spk %d, %.1fs)  ↔  %@ (spk %d, %.1fs) : cos = %.4f",
                         (aPath as NSString).lastPathComponent, aDom.key, duration(aDom.value),
                         (pairFile as NSString).lastPathComponent, bDom.key, duration(bDom.value),
                         cosine(aEmb, bEmb)))
        }
    }

    static func duration(_ segs: [DiarizerSegment]) -> Double {
        segs.reduce(0) { $0 + Double($1.endTime - $1.startTime) }
    }

    /// Concatenate a slot's segment audio from `src`, time-ordered, capped at 10s.
    static func clipSamples(_ segs: [DiarizerSegment], from src: [Float]) -> [Float]? {
        var out: [Float] = []
        for s in segs.sorted(by: { $0.startTime < $1.startTime }) {
            let a = max(0, Int(Double(s.startTime) * 16000)), b = min(src.count, Int(Double(s.endTime) * 16000))
            if a < b { out.append(contentsOf: src[a..<b]) }
        }
        let c = Array(out.prefix(maxEmbedSamples))
        return c.count >= 8000 ? c : nil
    }

    static func norm(_ v: [Float]) -> Float { (v.reduce(0) { $0 + $1 * $1 }).squareRoot() }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }
}
