#if DEBUG
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
