#if DEBUG
import AVFoundation
import Foundation
import SwiftData

/// Q423: the Process verb over the whole synthetic corpus, on an in-memory scratch store
/// (never the live Dev store, C166). One driver for both sides of the copy-edit harness:
/// the DEBUG `-recordcopyeditv2` flag runs it with the live MLX model wrapped in
/// `ModelOutputCache.recording`; the copy-edit harness tests run it MLX-free with the
/// recorded outputs replayed.
///
/// Per note: an unrated note gets Process pressed first, which floors it to 0.1 (C40); the
/// reconcile sweep makes the Mac row; the row runs through `BatchRunner` when
/// `WayOutRules.needsProcessing` says the Mac would take it (C38: a done row is never
/// re-polished). ASR never runs: a note the Mac would transcribe gets the corpus's own
/// transcript + word timings back from `CorpusTranscriber`, so the harness isolates copy-edit.
@MainActor
enum CopyEditCorpusRun {

    /// Fixed inputs, so a golden never depends on the clock, the machine or a temp path.
    static let author = "Corpus Author"
    static let device = "corpus-mac"
    static let now = Date(timeIntervalSince1970: 1_767_225_600)   // 2026-01-01T00:00:00Z

    /// One note's outcome.
    struct Result {
        let slug: String
        /// Rated after Process (C40 floor); nil when the note is trashed (Process refused).
        let significance: Double?
        let hasRow: Bool
        /// What the model read: the row's transcript (after any corpus "ASR"; nil without a row).
        let input: String?
        let title: String?
        let summary: String?
        /// The shipped body: sanitised → copy-edit → transcript (the compiler's precedence).
        let body: String?
        let error: String?
        /// The Process pass ran on this row (it still needed processing).
        var processed = false
        /// The row would still be picked up after the pass (C40: never, the Mac never re-polishes).
        var needsProcessingAfter = false

        /// The golden text (`goldens/v1-copyedit/<slug>.txt`).
        var record: String {
            var s = "slug: \(slug)\n"
            s += "row: \(hasRow ? "yes" : "none")\n"
            s += "significance: \(significance.map { String($0) } ?? "nil")\n"
            s += "error: \(error ?? "nil")\n"
            s += "--- title\n\(title ?? "(nil)")\n"
            s += "--- summary\n\(summary ?? "(nil)")\n"
            s += "--- body\n\(body ?? "(nil)")\n"
            return s
        }

        /// Parse a golden back into its fields (the inverse of `record`).
        static func fields(of record: String) -> [String: String] {
            var out: [String: String] = [:]
            var section: String?
            var buf: [String] = []
            func flush() { if let section { out[section] = buf.joined(separator: "\n") }; buf = [] }
            for line in record.components(separatedBy: "\n") {
                if line.hasPrefix("--- ") { flush(); section = String(line.dropFirst(4)); continue }
                if section == nil, let colon = line.firstIndex(of: ":") {
                    out[String(line[..<colon])] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                } else if section != nil { buf.append(line) }
            }
            flush()
            if let body = out["body"], body.hasSuffix("\n") { out["body"] = String(body.dropLast()) }
            return out
        }
    }

    struct RowlessNotes: LocalizedError {
        let slugs: [String]
        let outcome: String
        var errorDescription: String? { "live notes without a Mac row after the sweep: \(slugs) (\(outcome))" }
    }

    /// Hands a row back the corpus's own words (no ASR in the copy-edit harness).
    struct CorpusTranscriber: Transcribing {
        let text: String
        let words: [WordTiming]
        func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
            TranscriptionResult(text: text, confidence: 1, durationMs: Int((words.last?.end ?? 0) * 1000),
                                wordTimings: words, markersInjected: false)
        }
        func transcribe(buffer: AVAudioPCMBuffer) async throws -> TranscriptionResult {
            try await transcribe(audioURL: URL(fileURLWithPath: "/dev/null"), imageManifest: [])
        }
    }

    /// One row's Process: (row, the runner, audio, picture manifest, clip starts). nil =
    /// `BatchRunner.run` with `enhancer`; the v2 harness passes `CopyEditV2Mac.corpusStep` (Q424).
    typealias RowStep = @MainActor (PipelineFile, BatchRunner, URL?, [ImageManifestEntry], [Double]) async throws -> Void

    /// Run every manifest note of `corpus` through Process with `enhancer` (or `step`).
    /// `scratch` holds the in-memory store's media + the Mac rows' working folders.
    static func run(corpus: URL, enhancer: Enhancing, scratch: URL, step: RowStep? = nil,
                    progress: (String) -> Void = { _ in }) async throws -> [Result] {
        let cloud = ModelContext(try ModelContainer(
            for: Memo.self, MemoAsset.self, MemoEnhancement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)))
        let local = ModelContext(try ModelContainer(
            for: PipelineFile.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)))
        try CorpusSeed.seed(from: corpus, into: cloud, recordingsDirectory: scratch.appendingPathComponent("rec"))
        let people = try JSONDecoder().decode([Person].self,
                                              from: Data(contentsOf: corpus.appendingPathComponent("names.json")))
        let manifest = try JSONDecoder().decode(CorpusSeed.Manifest.self,
                                                from: Data(contentsOf: corpus.appendingPathComponent("manifest.json")))

        // Process pressed on every live note: an unrated one is floored to 0.1 (C40).
        let memos = try cloud.fetch(FetchDescriptor<Memo>())
        for memo in memos where memo.deletedAt == nil && !NoteConsent.isRated(memo) {
            memo.significance = NoteConsent.flooredByProcess(memo.significance)
        }
        try cloud.save()
        // Q431: the sweep is reconcile v2 (its rows are field-identical to v1's on the corpus).
        let outcome = ReconcileV2.sweep(cloud: cloud, local: local,
                                        context: .init(people: people, author: author, thisDeviceID: device, now: now,
                                                       outputDir: scratch.appendingPathComponent("out")))

        let memoByID = Dictionary(memos.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        let rows = try local.fetch(FetchDescriptor<PipelineFile>())
        let rowByID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // Every live memo is rated now, so every one must hold a row. A missing row means the
        // sweep skipped it (e.g. the app's own launch ingest still had the same corpus ids in
        // flight) — a golden recorded from that would be wrong, so stop.
        let rowless = manifest.notes.filter { e in
            memoByID[e.id].map { $0.deletedAt == nil } == true && rowByID[e.id] == nil
        }.map(\.slug)
        guard rowless.isEmpty else { throw RowlessNotes(slugs: rowless, outcome: String(describing: outcome)) }
        var settings = AppSettings()
        settings.authorName = author
        var out: [Result] = []
        for entry in manifest.notes {
            let memo = memoByID[entry.id]
            let significance = memo.flatMap { $0.deletedAt == nil ? $0.significance : nil }
            guard let pf = rowByID[entry.id] else {
                out.append(Result(slug: entry.slug, significance: significance, hasRow: false, input: nil,
                                  title: nil, summary: nil, body: nil, error: nil))
                continue
            }
            progress(entry.slug)
            let folder = corpus.appendingPathComponent("notes").appendingPathComponent(entry.folder)
            let note = try JSONDecoder().decode(CorpusSeed.Note.self,
                                                from: Data(contentsOf: folder.appendingPathComponent("note.json")))
            let words: [WordTiming] = note.wordTimings.flatMap {
                try? JSONDecoder().decode([WordTiming].self, from: Data(contentsOf: folder.appendingPathComponent($0)))
            } ?? []
            let runner = BatchRunner(transcriber: CorpusTranscriber(text: note.transcript ?? "", words: words),
                                     enhancer: enhancer, settings: settings, people: people, tagWhitelist: [])
            var failure: String?
            let processed = WayOutRules.needsProcessing(pf)
            if processed {
                let hasAudio = pf.sourceType == .audio && !pf.path.isEmpty
                    && FileManager.default.fileExists(atPath: pf.path)
                let audioURL = hasAudio ? URL(fileURLWithPath: pf.path) : nil
                let manifest = hasAudio ? imageManifest(for: pf.path) : []
                let clips = hasAudio ? IngestService.clipStarts(forAudioAt: pf.path) : []
                do {
                    if let step {
                        try await step(pf, runner, audioURL, manifest, clips)
                    } else {
                        try await runner.run(pf, audioURL: audioURL, imageManifest: manifest, clipStarts: clips)
                    }
                } catch let miss as ModelOutputCache.Miss {
                    throw miss
                } catch {
                    failure = String(describing: error)
                }
            }
            out.append(Result(slug: entry.slug, significance: significance, hasRow: true,
                              input: pf.transcript,
                              title: pf.enhancedTitle, summary: pf.enhancedSummary,
                              body: pf.sanitised ?? pf.enhancedCopyedit ?? pf.transcript, error: failure,
                              processed: processed, needsProcessingAfter: WayOutRules.needsProcessing(pf)))
        }
        return out
    }

    /// The row's `image_manifest.json` next to its audio (`ProcessingCoordinator.imageManifest`).
    private static func imageManifest(for path: String) -> [ImageManifestEntry] {
        let url = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("image_manifest.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ImageManifestEntry].self, from: data)) ?? []
    }
}
#endif
