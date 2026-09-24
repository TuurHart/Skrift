import XCTest

/// Q23 (gate+): the R25/R33/R74 corpus fixtures SPEC.md's required-difference table names
/// but the generated corpus never had (see `_missing_fixtures` in `expected-differences.json`).
/// `manifest.json`, `expected-differences.json` and `generate.py` are protected and additive-
/// only for this item, so the 4 new note folders (`pic-during-pause-two-shots`,
/// `pic-burst-same-offset`, `ingress-p3-five-clips-one-picture`, `migrated-stale-name-offsets`)
/// are NOT listed in `manifest.json` — this is a SECOND, additive harness reading
/// `manifest-q23.json` / `expected-differences-q23.json` instead, mirroring
/// `BodyGoldenTests`/`BodyDiffHarnessTests`'s v1-body recipe and C5 classification exactly
/// (kept as its own copy for the same reason those two are: this file may ADD tests but
/// never reach into the protected ones).
final class BodyGoldenQ23Tests: XCTestCase {

    static var manifestURL: URL { BodyGoldenTests.corpusRoot.appendingPathComponent("manifest-q23.json") }
    static var expectedDifferencesURL: URL { BodyGoldenTests.corpusRoot.appendingPathComponent("expected-differences-q23.json") }
    /// New golden files only — never touches an existing `goldens/v1-body/<slug>.txt`.
    static var goldenDir: URL { BodyGoldenTests.goldenDir }

    private static let markerLiteral = try! NSRegularExpression(pattern: #"\[\[img_\d{3}\]\]"#)

    private func bareTranscript(_ t: String) -> String {
        let ns = t as NSString
        return Self.markerLiteral.stringByReplacingMatches(
            in: t, range: NSRange(location: 0, length: ns.length), withTemplate: "")
    }

    private func manifestEntries(from metadata: CorpusSeed.JSONValue) -> [ImageManifestEntry] {
        guard let data = metadata.data,
              let decoded = try? JSONDecoder().decode(MemoMetadata.self, from: data)
        else { return [] }
        return decoded.imageManifest ?? []
    }

    /// v1's body for one note — identical recipe to `BodyGoldenTests.v1Body` /
    /// `BodyDiffHarnessTests.V1Engine.body`: markers via `ImageMarkers.insert` from the real
    /// word timings + manifest, then the stored-transcript paragrapher (no-ops on marker-
    /// bearing text), then the shared display/export snap.
    private func v1Body(note: CorpusSeed.Note, folder: URL) throws -> String {
        let bare = bareTranscript(note.transcript ?? "")
        var timings: [WordTiming] = []
        if let wt = note.wordTimings {
            let data = try Data(contentsOf: folder.appendingPathComponent(wt))
            timings = try JSONDecoder().decode([WordTiming].self, from: data)
        }
        let words = timings.map { TimedWord(text: $0.word, start: $0.start, end: $0.end) }
        let manifest = manifestEntries(from: note.metadata)
        let withMarkers = ImageMarkers.insert(transcript: bare, words: words, manifest: manifest)
        let stored = timings.isEmpty ? withMarkers : Paragrapher.paragraphed(transcript: withMarkers, words: timings)
        return BodyTransform.snappedImageBody(stored)
    }

    static func loadExpectedDifferences() throws -> [String: [String]] {
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: expectedDifferencesURL)) as? [String: Any] ?? [:]
        var out: [String: [String]] = [:]
        for (key, value) in obj where !key.hasPrefix("_") {
            out[key] = (value as? [String]) ?? []
        }
        return out
    }

    /// Records (`SKRIFT_RECORD_GOLDENS=1`, same env var and same recipe as `BodyGoldenTests`)
    /// or verifies v1's body for the 4 Q23 fixtures.
    func testV1BodyGoldensQ23() throws {
        let root = BodyGoldenTests.corpusRoot
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.manifestURL.path),
                          "Q23 fixtures not present — manifest-q23.json missing")
        let manifest = try JSONDecoder().decode(CorpusSeed.Manifest.self, from: Data(contentsOf: Self.manifestURL))
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

    /// C5's v1-only half, over the Q23 fixtures: v1's own computed body must mismatch a
    /// note's `expect_body.txt` if and only if the slug is registered in
    /// `expected-differences-q23.json`. `migrated-stale-name-offsets` carries no
    /// `expect_body.txt` (documented in `_not_registered` there) so it's silently skipped,
    /// same as every other corpus note without one.
    func testV1MismatchesExpectBodyExactlyOnRegisteredSlugsQ23() throws {
        let root = BodyGoldenTests.corpusRoot
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.manifestURL.path),
                          "Q23 fixtures not present — manifest-q23.json missing")
        let manifest = try JSONDecoder().decode(CorpusSeed.Manifest.self, from: Data(contentsOf: Self.manifestURL))
        let expected = try Self.loadExpectedDifferences()

        var mismatchedButUnregistered: [String] = []
        var registeredButActuallyMatches: [String] = []

        for entry in manifest.notes {
            let folder = root.appendingPathComponent("notes").appendingPathComponent(entry.folder)
            let expectURL = folder.appendingPathComponent("expect_body.txt")
            guard let expectedBody = try? String(contentsOf: expectURL, encoding: .utf8) else { continue }
            let note = try JSONDecoder().decode(CorpusSeed.Note.self,
                                                from: Data(contentsOf: folder.appendingPathComponent("note.json")))
            let computed = try v1Body(note: note, folder: folder)
            let trimmedExpected = expectedBody.trimmingCharacters(in: .newlines)
            let isRegistered = !(expected[entry.slug] ?? []).isEmpty

            if computed == trimmedExpected {
                if isRegistered {
                    registeredButActuallyMatches.append("\(entry.slug): registered as a v1 bug but v1 already matches expect_body.txt")
                }
            } else if !isRegistered {
                mismatchedButUnregistered.append("\(entry.slug): v1 fails its expect_body.txt with no R id in expected-differences-q23.json")
            }
        }

        XCTAssertTrue(mismatchedButUnregistered.isEmpty, mismatchedButUnregistered.joined(separator: "\n"))
        XCTAssertTrue(registeredButActuallyMatches.isEmpty, registeredButActuallyMatches.joined(separator: "\n"))
    }
}
