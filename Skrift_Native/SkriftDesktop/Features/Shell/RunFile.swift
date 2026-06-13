#if DEBUG
import AVFoundation
import Foundation
import SwiftData

/// Headless end-to-end pipeline run. Launched with `-runfile <audioPath>`, builds
/// a transient PipelineFile, runs the real BatchRunner (FluidAudio + mlx-swift) on
/// it, prints the result to stderr, and exits. Validates the whole pipeline without
/// GUI automation or SwiftData. (DEBUG only; transient — writes nothing.)
///
/// IMPORTANT: do NOT block the main thread waiting for the run — FluidAudio's ASR
/// posts completion callbacks to main, so blocking main deadlocks at inference.
/// We schedule a detached Task, let `init` return so the run loop spins, and
/// `exit(0)` when finished.
enum RunFile {
    /// Unique-word-anchor drift of `cand` vs the reference `whole` transcribe.
    /// Anchors = words appearing exactly once in both, ≥5 chars (unambiguous).
    nonisolated static func anchorDrift(_ cand: [WordTiming], vs whole: [WordTiming])
        -> (n: Int, median: Double, mean: Double, startAvg: Double, midAvg: Double, endAvg: Double) {
        func norm(_ s: String) -> String {
            String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        }
        let cN = cand.map { norm($0.word) }, wN = whole.map { norm($0.word) }
        var cF: [String: Int] = [:], wF: [String: Int] = [:]
        for w in cN where !w.isEmpty { cF[w, default: 0] += 1 }
        for w in wN where !w.isEmpty { wF[w, default: 0] += 1 }
        var cAt: [String: Int] = [:], wAt: [String: Int] = [:]
        for (k, w) in cN.enumerated() where cF[w] == 1 && w.count >= 5 { cAt[w] = k }
        for (k, w) in wN.enumerated() where wF[w] == 1 && w.count >= 5 { wAt[w] = k }
        var rows: [(d: Double, t: Double)] = []
        for (w, wi) in wAt { if let ci = cAt[w] { rows.append((cand[ci].start - whole[wi].start, whole[wi].start)) } }
        rows.sort { $0.t < $1.t }
        guard rows.count > 6 else { return (rows.count, 0, 0, 0, 0, 0) }
        let d = rows.map(\.d), s = d.sorted()
        let t = max(1, rows.count / 3)
        func avg(_ x: ArraySlice<Double>) -> Double { x.isEmpty ? 0 : x.reduce(0, +) / Double(x.count) }
        return (rows.count, s[s.count / 2], d.reduce(0, +) / Double(d.count),
                avg(d[0..<t]), avg(d[t..<2 * t]), avg(d[(2 * t)...]))
    }

    /// `-chunksim <audio>` → reproduce the read-along drift headlessly + prove the
    /// fix. Whole-transcribes the file (reference), then re-builds it the
    /// chunker's way two ways — (A) `AVAssetExportSession` per 60 s span (today's
    /// `exportSpan`), (B) sample-accurate `AVAudioFile` frame read — and reports
    /// each one's drift vs whole. If A drifts and B doesn't, the per-chunk
    /// compressed-seek is the bug and B is the fix. DEBUG only.
    nonisolated static func runChunkSimIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-chunksim"), i + 1 < args.count else { return }
        let url = URL(fileURLWithPath: args[i + 1])
        Task.detached(priority: .userInitiated) {
            func log(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
            log("== CHUNKSIM \(url.lastPathComponent) ==")
            let svc = TranscriptionService.shared
            guard let whole = try? await svc.transcribe(audioURL: url) else { log("whole transcribe failed"); exit(1) }
            let dur = CMTimeGetSeconds(AVURLAsset(url: url).duration)
            log(String(format: "duration %.1fs, whole words %d", dur, whole.wordTimings.count))

            func chunked(_ label: String, extract: (Double, Double, URL) async throws -> Void) async -> [WordTiming] {
                var out: [WordTiming] = []
                var s = 0.0
                while s < dur - 0.1 {
                    let e = min(s + 60, dur)
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cs_\(UUID().uuidString).wav")
                    defer { try? FileManager.default.removeItem(at: tmp) }
                    do {
                        try await extract(s, e, tmp)
                        if let r = try? await svc.transcribe(audioURL: tmp) {
                            out += r.wordTimings.map { WordTiming(word: $0.word, start: $0.start + s, end: $0.end + s) }
                        }
                    } catch { log("  [\(label)] chunk \(Int(s))s failed: \(error)") }
                    s = e
                }
                return out
            }

            // (A) AVAssetExportSession (today's exportSpan).
            let a = await chunked("export") { st, en, dst in
                let asset = AVURLAsset(url: url)
                guard let ex = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { return }
                let m4a = dst.deletingPathExtension().appendingPathExtension("m4a")
                ex.timeRange = CMTimeRange(start: CMTime(seconds: st, preferredTimescale: 600),
                                           end: CMTime(seconds: en, preferredTimescale: 600))
                try? FileManager.default.removeItem(at: m4a)
                try await ex.export(to: m4a, as: .m4a)
                try? FileManager.default.moveItem(at: m4a, to: dst)
            }
            // (B) sample-accurate AVAudioFile frame read.
            let b = await chunked("pcm") { st, en, dst in
                let f = try AVAudioFile(forReading: url)
                let sr = f.processingFormat.sampleRate
                f.framePosition = AVAudioFramePosition(st * sr)
                let n = AVAudioFrameCount((en - st) * sr)
                guard let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: n) else { return }
                try f.read(into: buf, frameCount: n)
                let out = try AVAudioFile(forWriting: dst, settings: f.processingFormat.settings)
                try out.write(from: buf)
            }
            let da = anchorDrift(a, vs: whole.wordTimings)
            let db = anchorDrift(b, vs: whole.wordTimings)
            log(String(format: "(A) AVAssetExportSession: words=%d anchors=%d  median=%+.3f  thirds %+.2f/%+.2f/%+.2f",
                       a.count, da.n, da.median, da.startAvg, da.midAvg, da.endAvg))
            log(String(format: "(B) AVAudioFile PCM:      words=%d anchors=%d  median=%+.3f  thirds %+.2f/%+.2f/%+.2f",
                       b.count, db.n, db.median, db.startAvg, db.midAvg, db.endAvg))
            exit(0)
        }
    }

    /// `-readalongcheck <audio> <sidecar.json>` → diagnose the player read-along
    /// sync. Decodes the phone's `BookTranscript` sidecar, transcribes the SAME
    /// audio WHOLE on the Mac (same Parakeet engine = the reference for whether
    /// CHUNKING shifted the word times), aligns words, and reports the
    /// `phone.start − mac.start` offset + drift across the file. median≈0 ⇒ the
    /// chunker is accurate (any device trailing is playback latency → tune the
    /// lead); a non-zero/growing offset ⇒ a chunker bug to fix. DEBUG only.
    nonisolated static func runReadAlongCheckIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-readalongcheck"), i + 2 < args.count else { return }
        let audioPath = args[i + 1], sidecarPath = args[i + 2]
        Task.detached(priority: .userInitiated) {
            func log(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
            struct SW: Codable { let word: String; let start: Double; let end: Double }
            struct Sidecar: Codable { let words: [SW]; let coveredUpTo: Double }
            log("== READALONGCHECK \(URL(fileURLWithPath: audioPath).lastPathComponent) ==")
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: sidecarPath)),
                  let side = try? JSONDecoder().decode(Sidecar.self, from: data) else { log("can't read sidecar"); exit(1) }
            log("sidecar: \(side.words.count) words, coveredUpTo \(String(format: "%.1f", side.coveredUpTo))s")
            guard let r = try? await TranscriptionService.shared.transcribe(audioURL: URL(fileURLWithPath: audioPath)) else {
                log("mac transcribe failed"); exit(1)
            }
            let mac = r.wordTimings
            log("mac whole-transcribe: \(mac.count) words")

            func norm(_ s: String) -> String {
                String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
            }
            let macN = mac.map { norm($0.word) }
            let sideN = side.words.map { norm($0.word) }
            // Align ONLY on words that appear EXACTLY ONCE in both transcripts and
            // are ≥5 chars — unambiguous anchors. Greedy matching slips on repeated
            // common words ("to"/"you") in a long transcript and fabricates offsets.
            var macFreq: [String: Int] = [:], sideFreq: [String: Int] = [:]
            for w in macN where !w.isEmpty { macFreq[w, default: 0] += 1 }
            for w in sideN where !w.isEmpty { sideFreq[w, default: 0] += 1 }
            var macAt: [String: Int] = [:], sideAt: [String: Int] = [:]
            for (k, w) in macN.enumerated() where macFreq[w] == 1 && w.count >= 5 { macAt[w] = k }
            for (k, w) in sideN.enumerated() where sideFreq[w] == 1 && w.count >= 5 { sideAt[w] = k }
            // (Δ, macStart, word)
            var rows: [(d: Double, t: Double, word: String, ps: Double)] = []
            for (w, mi) in macAt { if let si = sideAt[w] {
                rows.append((side.words[si].start - mac[mi].start, mac[mi].start, mac[mi].word, side.words[si].start))
            } }
            rows.sort { $0.t < $1.t }
            guard rows.count > 10 else { log("too few unique anchors (\(rows.count))"); exit(1) }
            let diffs = rows.map(\.d)
            let sorted = diffs.sorted()
            func pct(_ p: Double) -> Double { sorted[min(sorted.count - 1, max(0, Int(p * Double(sorted.count)))) ] }
            let mean = diffs.reduce(0, +) / Double(diffs.count)
            log(String(format: "unique-word anchors: %d", rows.count))
            log(String(format: "phone.start − mac.start (s):  median=%+.3f  mean=%+.3f  p10=%+.3f  p90=%+.3f  min=%+.3f  max=%+.3f",
                       pct(0.5), mean, pct(0.1), pct(0.9), sorted.first!, sorted.last!))
            let t = max(1, rows.count / 3)
            func avg(_ s: ArraySlice<Double>) -> Double { s.isEmpty ? 0 : s.reduce(0, +) / Double(s.count) }
            log(String(format: "drift (avg Δ by third):  start=%+.3f  mid=%+.3f  end=%+.3f",
                       avg(diffs[0..<t]), avg(diffs[t..<2 * t]), avg(diffs[(2 * t)...])))
            log("anchors across the file:")
            for (k, r) in rows.enumerated() where k % max(1, rows.count / 12) == 0 {
                log(String(format: "    %6.1fs  '%@'  mac=%.2f  phone=%.2f  Δ=%+.2f", r.t, r.word, r.t, r.ps, r.d))
            }
            exit(0)
        }
    }

    /// `-asrbench <audio>` → measure the ASR latency SPLIT (model load/warm-up vs
    /// per-call inference) so the audiobook-capture design isn't built on guessed
    /// numbers. Times ensureLoaded() once, then transcribes the file TWICE (first
    /// warm call vs steady-state). DEBUG only. NOTE: Mac (M-series) magnitudes ≠
    /// phone (A15) — this measures the SHAPE (load vs inference ratio), which
    /// transfers; the phone's absolute number needs the same timing via devlog.
    nonisolated static func runAsrBenchIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-asrbench"), i + 1 < args.count else { return }
        let path = args[i + 1]
        Task.detached(priority: .userInitiated) {
            func log(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { log("ASRBENCH: file not found"); exit(1) }

            let t0 = Date()
            try? await TranscriptionService.shared.ensureLoaded()
            let loadMs = Int(Date().timeIntervalSince(t0) * 1000)
            log("ASRBENCH load(ensureLoaded, cold)= \(loadMs) ms")

            let t1 = Date()
            let r1 = try? await TranscriptionService.shared.transcribe(audioURL: url, imageManifest: [])
            let inf1 = Int(Date().timeIntervalSince(t1) * 1000)
            log("ASRBENCH inference#1(warm engine)= \(inf1) ms  (\(r1?.wordTimings.count ?? 0) words)")

            let t2 = Date()
            _ = try? await TranscriptionService.shared.transcribe(audioURL: url, imageManifest: [])
            let inf2 = Int(Date().timeIntervalSince(t2) * 1000)
            log("ASRBENCH inference#2(steady)   = \(inf2) ms")
            log("ASRBENCH audio length ~= read the file; ratio load:inf = \(loadMs):\(inf1)")
            exit(0)
        }
    }

    /// `-audiodate <path>` → print the embedded recording date AudioMetadata reads
    /// (verifies the date-backfill works before relying on it). DEBUG only.
    nonisolated static func runAudioDateProbeIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-audiodate"), i + 1 < args.count else { return }
        let path = args[i + 1]
        Task.detached(priority: .userInitiated) {
            let d = await AudioMetadata.recordingDate(of: URL(fileURLWithPath: path))
            let out = d.map { ISO8601DateFormatter().string(from: $0) } ?? "nil"
            FileHandle.standardError.write(Data("AUDIODATE \(path) -> \(out)\n".utf8))
            exit(0)
        }
    }

    /// `-voiceloop <enrollAudio> <recognizeAudio>` → prove the conversation-mode IDENTITY
    /// loop end-to-end on REAL audio, headlessly (the Mac runs the same wespeaker model as
    /// the phone): diarize A, enroll its dominant speaker as [[VoiceLoopTest]], then diarize
    /// B and report whether B auto-labels that voice (+ the raw cosine). Isolates the dev
    /// names store (backs up → clears → restores) so only the test voiceprint exists. DEBUG.
    nonisolated static func runVoiceLoopIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-voiceloop"), i + 2 < args.count else { return }
        let aPath = args[i + 1], bPath = args[i + 2]
        Task.detached(priority: .userInitiated) {
            func log(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
            log("== VOICELOOP enroll=\((aPath as NSString).lastPathComponent) recognize=\((bPath as NSString).lastPathComponent) ==")
            let svc = DiarizationService.shared
            let namesURL = AppPaths.namesFile
            let backup = try? Data(contentsOf: namesURL)
            try? FileManager.default.removeItem(at: namesURL)   // isolate: only our test voiceprint
            do {
                let a = try await svc.diarize(audioURL: URL(fileURLWithPath: aPath))
                guard let aSlot = dominantSlot(a.segments),
                      let aEmb = try await svc.embedSpeaker(audioURL: URL(fileURLWithPath: aPath), segments: a.segments, slot: aSlot) else {
                    log(">>> couldn't enroll A's dominant speaker"); restore(backup, namesURL, log); exit(1)
                }
                NamesStore.shared.addVoiceEmbedding(canonical: "VoiceLoopTest",
                    embedding: VoiceEmbedding(vector: aEmb.map(Double.init), condition: "voiceloop", addedAt: ISO8601.now()))
                log(">>> enrolled A spk\(aSlot) as [[VoiceLoopTest]]")

                let b = try await svc.diarize(audioURL: URL(fileURLWithPath: bPath))
                if let bSlot = dominantSlot(b.segments),
                   let bEmb = try await svc.embedSpeaker(audioURL: URL(fileURLWithPath: bPath), segments: b.segments, slot: bSlot) {
                    log(String(format: ">>> cosine(A spk%d, B spk%d) = %.4f  (threshold %.2f)", aSlot, bSlot,
                               VoiceMatcher.cosine(aEmb, bEmb), VoiceMatcher.threshold))
                }
                let matched = b.slotNames.values.contains("VoiceLoopTest")
                log(">>> B slotNames: \(b.slotNames)")
                log(matched ? ">>> RECOGNIZED — B auto-labeled the enrolled voice" : ">>> NOT recognized in B")
            } catch { log(">>> ERROR: \(error)") }
            restore(backup, namesURL, log)
            exit(0)
        }
    }

    private static func dominantSlot(_ segs: [DiarizedSegment]) -> Int? {
        Dictionary(grouping: segs, by: \.speaker)
            .mapValues { $0.reduce(0.0) { $0 + ($1.end - $1.start) } }
            .max(by: { $0.value < $1.value })?.key
    }
    private static func restore(_ backup: Data?, _ url: URL, _ log: (String) -> Void) {
        if let backup { try? backup.write(to: url) } else { try? FileManager.default.removeItem(at: url) }
        log(">>> dev names store restored")
    }

    nonisolated static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-runfile"), i + 1 < args.count else { return }
        let path = args[i + 1]

        Task.detached(priority: .userInitiated) {
            func log(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

            log("== RUNFILE \(path) ==")
            guard FileManager.default.fileExists(atPath: path) else { log("audio not found"); exit(1) }

            let pf = PipelineFile(id: "runfile", filename: URL(fileURLWithPath: path).lastPathComponent,
                                  path: path, sourceType: .audio)

            // Trusted-mobile path: `-transcript <file>` pre-loads a phone transcript
            // and marks transcribe done, so BatchRunner SKIPS ASR — exactly what the
            // Mac does for a trusted phone upload (confidence ≥ 0.7 / user-edited).
            // Validates name-link → enhance → compile → export on a REAL synced memo
            // (markers already injected on-device; the audio + images stay on disk
            // for export). Without it, this stays a normal raw-audio run.
            var trustedMobile = false
            var inputTranscript: String?
            if let ti = args.firstIndex(of: "-transcript"), ti + 1 < args.count,
               let text = try? String(contentsOfFile: args[ti + 1], encoding: .utf8) {
                pf.transcript = text
                pf.transcribeStatus = .done
                trustedMobile = true
                inputTranscript = text
                log(">>> MODE: trusted-mobile (ASR skipped) — transcript \(text.count) chars")
            }

            // `-vocab "Word1; Canonical: alias1, alias2; Word3"` → persist custom-
            // vocabulary words before the run (the transcriber reads them from
            // SettingsStore), so the CTC boost pass can be exercised headlessly.
            // Entries split on ';' so an entry's aliases can use ','. They stay set
            // afterwards — same store the Settings panel edits.
            //
            // CRITICAL: the production booster is NON-BLOCKING (it skips the first,
            // model-loading transcribe). A one-shot `-runfile` only transcribes
            // once, so without a synchronous prewarm the boost would never run.
            // We `prewarm` (await) here so this single transcribe IS boosted —
            // exactly what the device gets once the booster is warm.
            if let vi = args.firstIndex(of: "-vocab"), vi + 1 < args.count {
                var s = SettingsStore.shared.load()
                s.customVocabulary = args[vi + 1].split(separator: ";").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }.filter { !$0.isEmpty }
                SettingsStore.shared.save(s)
                log(">>> VOCAB: \(s.customWords.joined(separator: " | "))")
                log(">>> VOCAB: prewarming CTC spotter/rescorer (synchronous for the headless run)…")
                await VocabularyBooster.shared.prewarm(words: s.customWords)
                log(">>> VOCAB: prewarm done")
            }

            let settings = SettingsStore.shared.load()
            let runner = BatchRunner(
                transcriber: TranscriptionService.shared,
                enhancer: EnhancementService.shared,
                settings: settings,
                people: NamesStore.shared.livePeople(),
                tagWhitelist: [],
                diarizer: DiarizationService.shared
            )
            let t0 = Date()
            do {
                try await runner.run(pf, audioURL: URL(fileURLWithPath: path))
                log(String(format: ">>> elapsed: %.1fs", Date().timeIntervalSince(t0)))
                log(">>> steps: transcribe=\(pf.transcribeStatus.rawValue) enhance=\(pf.enhanceStatus.rawValue)")
                log(">>> word_timings: \(pf.wordTimings.count) (drives karaoke)")
                if trustedMobile {
                    // Proof the trust path held: the transcript is byte-for-byte the
                    // phone's (ASR never ran and overwrote it).
                    let preserved = (pf.transcript == inputTranscript)
                    log(">>> TRUST CHECK: ASR skipped, phone transcript preserved = \(preserved)")
                }
                log(">>> TRANSCRIPT:\n\(pf.transcript ?? "(nil)")")
                log(">>> TITLE: \(pf.enhancedTitle ?? "(nil)")")
                log(">>> SUMMARY: \(pf.enhancedSummary ?? "(nil)")")
                log(">>> TAG SUGGESTIONS: \(pf.tagSuggestions ?? [])")
                log(">>> AMBIGUOUS NAMES: \((pf.ambiguousNames ?? []).map { $0.alias })")
                log(">>> SANITISED:\n\(pf.sanitised ?? "(nil)")")
                log(">>> COMPILED (\((pf.compiledText ?? "").count) chars):\n\(pf.compiledText ?? "(nil)")")

                // Optional: -vault <path> exports to a real (test) vault.
                if let vi = args.firstIndex(of: "-vault"), vi + 1 < args.count {
                    var s = settings
                    s.noteFolder = args[vi + 1]
                    if s.audioFolder.isEmpty { s.audioFolder = "Voice Memos" }
                    if s.attachmentsFolder.isEmpty { s.attachmentsFolder = "Attachments" }
                    let r = try VaultExporter.export(pf, settings: s)
                    log(">>> EXPORTED md: \(r.markdownURL.path)")
                    log(">>> EXPORTED audio: \(r.audioURL?.path ?? "(none)")  images: \(r.imageCount)")
                }
            } catch {
                log(">>> ERROR: \(error)")
            }
            exit(0)
        }
    }

    /// `-processfile <id> [-exportafter]` → run the REAL Process verb (enhance /
    /// name-link / compile; ASR only for audio sources) over ONE PipelineFile in
    /// the REAL SwiftData store, optionally export it to the configured vault,
    /// print the resulting statuses, and exit. Closes the headless loop for
    /// phone-synced uploads (e.g. C3 captures) without GUI automation.
    /// QUIT the GUI app first — a second instance races the shared store.
    nonisolated static func runProcessFileIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-processfile"), i + 1 < args.count else { return }
        let id = args[i + 1]
        let doExport = args.contains("-exportafter")
        Task { @MainActor in
            func log(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
            let ctx = SharedStore.container.mainContext
            func fetch() -> PipelineFile? {
                ((try? ctx.fetch(FetchDescriptor<PipelineFile>())) ?? []).first { $0.id == id }
            }
            guard let before = fetch() else { log(">>> no PipelineFile with id \(id)"); exit(1) }
            log("== PROCESSFILE \(before.filename) (\(before.sourceType.rawValue)) ==")
            let coordinator = ProcessingCoordinator()
            await coordinator.process(fileIDs: [id], context: ctx)
            if let runErr = coordinator.lastError { log(">>> RUN ERROR: \(runErr)") }
            guard let pf = fetch() else { log(">>> file vanished mid-run"); exit(1) }
            log("steps: transcribe=\(pf.transcribeStatus.rawValue) sanitise=\(pf.sanitiseStatus.rawValue) enhance=\(pf.enhanceStatus.rawValue) export=\(pf.exportStatus.rawValue)")
            log("title: \(pf.enhancedTitle ?? "(nil)")  suggested: \(pf.titleSuggested ?? "(nil)")")
            log("tags: \(pf.tags)  suggestions: \(pf.tagSuggestions ?? [])")
            log("summary: \(pf.enhancedSummary ?? "(nil)")")
            if let err = pf.error { log("error: \(err)") }
            log(">>> COMPILED (\((pf.compiledText ?? "").count) chars):\n\(pf.compiledText ?? "(nil)")")
            if doExport {
                coordinator.export(pf, context: ctx)
                if let exportErr = coordinator.lastError { log(">>> EXPORT ERROR: \(exportErr)") }
                log(">>> EXPORTED: \(pf.exported ?? "(nil)")  status=\(pf.exportStatus.rawValue)")
            }
            exit(0)
        }
    }
}
#endif
