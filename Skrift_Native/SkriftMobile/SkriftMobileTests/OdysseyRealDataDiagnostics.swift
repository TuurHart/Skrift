import XCTest
@testable import SkriftMobile

/// Real-data alignment diagnostics (📖 rounds 5–7 device verify, 2026-07-23).
///
/// Runs the EXACT device align path (`parseBookFile` → `mergeBlocksByFile` →
/// `AlignmentCore.align` → `assembleSentences`) against the user's actual
/// Odyssey ePub + on-device transcript sidecar, pulled off the phone. Repro
/// target: the round-7 BRIDGE produced 0 bridged sentences on device while
/// both known holes (165.8–181.9 s, 334.0–340.9 s) plainly satisfy its
/// corroboration gate on paper.
///
/// Env-gated: set `SKRIFT_ODYSSEY_DIR` to a folder holding `The Odyssey.epub`
/// + `transcript_f0.json` (skipped otherwise — the book is copyrighted and
/// never enters the repo). The slow full-align pass caches `matchedRanges` to
/// `matched_ranges_cache.json` in that folder so the pure `assembleSentences`
/// step can be iterated in seconds.
final class OdysseyRealDataDiagnostics: XCTestCase {

    private struct CachedWordTime: Codable {
        var start: Double
        var end: Double
        var direct: Bool
    }

    private struct CachedRange: Codable {
        var sourceFile: String
        var bookWordStart: Int
        var bookWordEnd: Int
        var start: Double
        var end: Double
        var wordTimes: [CachedWordTime]
    }

    private func dataDir() throws -> URL {
        guard let p = ProcessInfo.processInfo.environment["SKRIFT_ODYSSEY_DIR"] else {
            throw XCTSkip("SKRIFT_ODYSSEY_DIR not set — real-data diagnostics only")
        }
        return URL(fileURLWithPath: p, isDirectory: true)
    }

    func testFullAlignAndDumpCache() throws {
        let dir = try dataDir()
        let cacheURL = dir.appendingPathComponent("matched_ranges_cache.json")
        try XCTSkipIf(FileManager.default.fileExists(atPath: cacheURL.path),
                      "cache already present — delete it to re-run the slow pass")

        let epub = try BookAlignmentRunner.parseBookFile(at: dir.appendingPathComponent("The Odyssey.epub"))
        let blocks = BookAlignmentRunner.mergeBlocksByFile(epub.blocks)
        let ft = try JSONDecoder().decode(FileTranscript.self,
            from: Data(contentsOf: dir.appendingPathComponent("transcript_f0.json")))
        let transcript = ft.words.map { AlignmentCore.Word(text: $0.word, start: $0.start, end: $0.end) }

        let result = AlignmentCore.align(transcript: transcript, book: blocks)
        print("DIAG verdict=\(result.verdict) coverage=\(result.coverageBook) ranges=\(result.matchedRanges.count)")

        let cached = result.matchedRanges.map {
            CachedRange(sourceFile: $0.sourceFile,
                        bookWordStart: $0.bookWordStart, bookWordEnd: $0.bookWordEnd,
                        start: $0.start, end: $0.end,
                        wordTimes: $0.wordTimes.map { CachedWordTime(start: $0.start, end: $0.end, direct: $0.direct) })
        }
        try JSONEncoder().encode(cached).write(to: cacheURL)
    }

    func testAssembleSentencesFromCache() throws {
        let dir = try dataDir()
        let cacheURL = dir.appendingPathComponent("matched_ranges_cache.json")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: cacheURL.path),
                      "no cache — run testFullAlignAndDumpCache first")

        let epub = try BookAlignmentRunner.parseBookFile(at: dir.appendingPathComponent("The Odyssey.epub"))
        let blocks = BookAlignmentRunner.mergeBlocksByFile(epub.blocks)
        let ft = try JSONDecoder().decode(FileTranscript.self,
            from: Data(contentsOf: dir.appendingPathComponent("transcript_f0.json")))
        let cached = try JSONDecoder().decode([CachedRange].self, from: Data(contentsOf: cacheURL))
        let ranges = cached.map {
            AlignmentCore.Result.MatchedRange(
                sourceFile: $0.sourceFile,
                bookWordStart: $0.bookWordStart, bookWordEnd: $0.bookWordEnd,
                start: $0.start, end: $0.end,
                wordTimes: $0.wordTimes.map { AlignmentCore.Result.WordTime(start: $0.start, end: $0.end, direct: $0.direct) })
        }

        var all: [AlignedSentence] = []
        for block in blocks {
            all += BookAlignmentRunner.assembleSentences(
                text: block.text, sourceFile: block.sourceFile,
                matchedRanges: ranges, transcriptWords: ft.words, textFile: "The Odyssey.epub")
        }
        all.sort { $0.start < $1.start }
        let bridged = all.filter { $0.bridged == true }
        print("DIAG sentences=\(all.count) bridged=\(bridged.count)")

        for (lo, hi, label) in [(150.0, 200.0, "3:00 hole"), (320.0, 355.0, "5:35 hole")] {
            print("DIAG --- \(label) ---")
            for s in all where s.start >= lo && s.start <= hi {
                let flag = s.bridged == true ? " BRIDGED" : ""
                print(String(format: "DIAG %7.1f-%7.1f conf=%.2f%@ %@",
                             s.start, s.end, s.confidence, flag, String(s.text.prefix(70))))
            }
        }
        // Full dump for offline diffing against the device-written sidecar.
        try JSONEncoder().encode(all).write(to: dir.appendingPathComponent("sim_sentences.json"))

        // The device-equivalent tail: run the fresh batch through the same merge the
        // sidecar write uses. THIS is where the 196 sentences died (within-batch
        // collision contest, fixed 2026-07-23) — assemble alone never showed it.
        let fa = BookAlignmentRunner.mergedFileAlignment(
            existing: nil, fileIndex: 0, textFilename: "The Odyssey.epub", title: epub.title,
            verdict: .aligned, coverage: 0.8, sentences: all,
            transcriptSignature: "t", epubSignature: "e", textRank: ["The Odyssey.epub": 0])
        print("DIAG merged=\(fa.sentences.count) of \(all.count)")
        XCTAssertEqual(fa.sentences.count, all.count,
                       "the merge must not eat same-text seam overlaps")

        XCTAssertTrue(all.contains { $0.text.contains("It is not the start of the Trojan War") },
                      "the 5:35 book sentence must be emitted — it was missing on device")
        XCTAssertTrue(fa.sentences.contains { $0.text.contains("It is not the start of the Trojan War") },
                      "…and it must SURVIVE the merge (the actual device-path bug)")
    }
}
