import XCTest

/// v1's body output for every corpus note, recorded once as the change-detector
/// baseline (C5, C253/Q9): strip any pre-baked `[[img_NNN]]` markers from the stored
/// transcript (a few notes are authored already in the v2 shape — see their `expect`),
/// re-place them with v1's REAL `ImageMarkers.insert` — `word_timings.json` for the
/// words, the note's `imageManifest` for the offsets, exactly the call
/// `ASRPostProcess.finish` makes — then run `BodyTransform.snappedImageBody`, the ONE
/// mid-sentence photo-snap pass shared by both renderers AND the Obsidian export
/// (`VaultExporter.swift`), so this one golden covers "display + export body".
///
/// `SKRIFT_RECORD_GOLDENS=1` (re)writes `test-fixtures/corpus/goldens/v1-body/<slug>.txt`
/// for every corpus note; otherwise every note's computed body is diffed against its
/// recorded file — a later v2 pass reads these goldens to classify its own output as
/// identical / expected-different / unexplained (C5), never to judge v1 itself (some
/// goldens ARE v1's known bugs, on purpose — see each note's `expect.bug`).
///
/// RE-RECORDING: `xcodebuild test ... TEST_RUNNER_SKRIFT_RECORD_GOLDENS=1` does NOT
/// reach this host-less `bundle.unit-test` target (verified 2026-09-24 — the
/// `TEST_RUNNER_` env-forwarding convention needs a test HOST, which this bundle has
/// none of). Build once (`xcodebuild build-for-testing -scheme UnitTests -destination
/// 'platform=macOS' -derivedDataPath build`), then run the compiled bundle directly:
/// `SKRIFT_RECORD_GOLDENS=1 xcrun xctest -XCTest SkriftDesktopTests.BodyGoldenTests
/// build/Build/Products/Debug/SkriftDesktopTests.xctest` (plain env vars DO reach a
/// process launched this way).
final class BodyGoldenTests: XCTestCase {

    static var corpusRoot: URL {
        // Skrift_Native/SkriftDesktop/SkriftDesktopTests/<this file> → repo root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test-fixtures/corpus", isDirectory: true)
    }

    static var goldenDir: URL {
        corpusRoot.appendingPathComponent("goldens/v1-body", isDirectory: true)
    }

    /// A pre-baked marker LITERAL only — never the whitespace around it, so removing
    /// it leaves whatever gap the author's prose had (a real ASR transcript never
    /// contained the marker in the first place).
    private static let markerLiteral = try! NSRegularExpression(pattern: #"\[\[img_\d{3}\]\]"#)

    private func bareTranscript(_ t: String) -> String {
        let ns = t as NSString
        return Self.markerLiteral.stringByReplacingMatches(
            in: t, range: NSRange(location: 0, length: ns.length), withTemplate: "")
    }

    /// The note's `imageManifest`, decoded from the same `metadataData` JSON blob a
    /// seeded `Memo.metadata` would carry.
    private func manifestEntries(from metadata: CorpusSeed.JSONValue) -> [ImageManifestEntry] {
        guard let data = metadata.data,
              let decoded = try? JSONDecoder().decode(MemoMetadata.self, from: data)
        else { return [] }
        return decoded.imageManifest ?? []
    }

    /// v1's body for one note. `ImageMarkers.insert` self-guards on empty words/manifest,
    /// so a note with no `word_timings.json` (no engine ever ran on it) or no manifest
    /// simply passes the bare transcript through untouched — the same no-op
    /// `ASRPostProcess.finish` performs.
    private func v1Body(note: CorpusSeed.Note, folder: URL) throws -> String {
        let bare = bareTranscript(note.transcript ?? "")
        var words: [TimedWord] = []
        if let wt = note.wordTimings {
            let data = try Data(contentsOf: folder.appendingPathComponent(wt))
            let timings = try JSONDecoder().decode([WordTiming].self, from: data)
            words = timings.map { TimedWord(text: $0.word, start: $0.start, end: $0.end) }
        }
        let manifest = manifestEntries(from: note.metadata)
        let withMarkers = ImageMarkers.insert(transcript: bare, words: words, manifest: manifest)
        return BodyTransform.snappedImageBody(withMarkers)
    }

    func testV1BodyGoldens() throws {
        let root = Self.corpusRoot
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path),
                          "corpus not generated — run test-fixtures/corpus/generate.py")
        let manifest = try JSONDecoder().decode(CorpusSeed.Manifest.self,
                                                from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        let record = ProcessInfo.processInfo.environment["SKRIFT_RECORD_GOLDENS"] == "1"
        if record {
            try FileManager.default.createDirectory(at: Self.goldenDir, withIntermediateDirectories: true)
        }

        var mismatches: [String] = []
        for entry in manifest.notes {
            let folder = root.appendingPathComponent("notes").appendingPathComponent(entry.folder)
            let note = try JSONDecoder().decode(CorpusSeed.Note.self,
                                                from: Data(contentsOf: folder.appendingPathComponent("note.json")))
            let body = try v1Body(note: note, folder: folder)
            let goldenURL = Self.goldenDir.appendingPathComponent("\(entry.slug).txt")

            if record {
                try body.write(to: goldenURL, atomically: true, encoding: .utf8)
                continue
            }
            guard let recorded = try? String(contentsOf: goldenURL, encoding: .utf8) else {
                mismatches.append("\(entry.slug): no golden recorded — run with SKRIFT_RECORD_GOLDENS=1")
                continue
            }
            if recorded != body {
                mismatches.append("\(entry.slug): computed body differs from the recorded golden")
            }
        }
        if !record {
            XCTAssertTrue(mismatches.isEmpty, mismatches.joined(separator: "\n"))
        } else {
            XCTAssertEqual(manifest.count, manifest.notes.count)
        }
    }
}
