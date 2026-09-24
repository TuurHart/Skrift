import XCTest

/// C9/C253/Q10: runs every REGISTERED body-generation engine (v1 now — v2 registers
/// here in Q11+) over the whole corpus and classes each note against v1's own recorded
/// golden (`BodyGoldenTests`) — never against v1 the person, v1 the CODE is only the
/// change detector (C5). Three buckets per note:
///   - identical      engine output == v1's golden. Fine, nothing to check further.
///   - expected-different  engine output != golden AND the slug carries the matching
///     R id in `expected-differences.json` — the fixed bug we set out to fix. PASS.
///   - unexplained     engine output != golden with NO registered R id — a regression
///     nobody signed off on. FAILS the harness (C5).
/// The mirror failure also fails: a slug registered for an R id whose engine output
/// STILL equals v1's golden (the bug is still there, unfixed) is "matched-bug" — also
/// a hard failure, because a pre-registered bug that v2 doesn't move is not expected
/// to still be identical.
///
/// A second, v1-only check needs no v2 engine to run today: for every note that carries
/// a Q9 `expect_body.txt` (the settled v2 target text), v1's own computed body must
/// MISMATCH it if and only if that slug is registered in `expected-differences.json`
/// (C5 "For v1 itself, the notes failing their expect_body must be exactly the
/// registered set") — an unregistered mismatch is an unexplained failure, and a
/// registered slug that secretly already matches means the registration is stale.
final class BodyDiffHarnessTests: XCTestCase {

    // MARK: - the engine protocol

    /// One body-generation pipeline runnable over a corpus note. v2 engines register
    /// themselves in `Self.engines` below as they're built (Q11+).
    protocol BodyEngine {
        var name: String { get }
        func body(for note: CorpusSeed.Note, folder: URL) throws -> String
    }

    /// v1's pipeline, matching `MemoSaver.runTranscription`'s own order exactly as
    /// `BodyGoldenTests.v1Body` records it (markers inserted from the REAL word
    /// timings + manifest, THEN the stored-transcript paragrapher — which no-ops on
    /// the marker-bearing text, R95 — then the shared display/export snap). Kept as
    /// its own copy rather than calling into `BodyGoldenTests` (a protected test file
    /// this item may not modify): the golden test's private `v1Body` isn't reachable
    /// from here, and re-deriving it is the only way to keep the two in lockstep
    /// without editing a protected file.
    struct V1Engine: BodyEngine {
        let name = "v1"

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

        func body(for note: CorpusSeed.Note, folder: URL) throws -> String {
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
    }

    /// Registered engines — v2 additions land here, never by editing `V1Engine`.
    static let engines: [BodyEngine] = [V1Engine()]

    // MARK: - expected-differences.json (slug -> [R id])

    /// Keys starting with `_` are documentation (`_schema` is a string, `_missing_fixtures`
    /// an object) — never a slug, and not `[String]`-shaped, so this reads the file as
    /// loose JSON rather than decoding it as one homogeneous dictionary type.
    static func loadExpectedDifferences() throws -> [String: [String]] {
        let url = BodyGoldenTests.corpusRoot.appendingPathComponent("expected-differences.json")
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        var out: [String: [String]] = [:]
        for (key, value) in obj where !key.hasPrefix("_") {
            out[key] = (value as? [String]) ?? []
        }
        return out
    }

    // MARK: - the three-way classification (C5)

    func testEngineClassificationAgainstV1Golden() throws {
        let root = BodyGoldenTests.corpusRoot
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path),
                          "corpus not generated — run test-fixtures/corpus/generate.py")
        let manifest = try JSONDecoder().decode(CorpusSeed.Manifest.self,
                                                from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        let expected = try Self.loadExpectedDifferences()

        var unexplained: [String] = []
        var matchedBug: [String] = []
        var v1DriftedFromItsOwnGolden: [String] = []

        for entry in manifest.notes {
            let folder = root.appendingPathComponent("notes").appendingPathComponent(entry.folder)
            let note = try JSONDecoder().decode(CorpusSeed.Note.self,
                                                from: Data(contentsOf: folder.appendingPathComponent("note.json")))
            let goldenURL = BodyGoldenTests.goldenDir.appendingPathComponent("\(entry.slug).txt")
            guard let golden = try? String(contentsOf: goldenURL, encoding: .utf8) else {
                continue   // BodyGoldenTests itself already fails a missing golden; don't double-report here.
            }
            let ids = expected[entry.slug] ?? []

            for engine in Self.engines {
                let computed = try engine.body(for: note, folder: folder)
                if engine.name == "v1" {
                    // v1 is the detector, never the judge: it must reproduce its OWN
                    // recorded golden byte-for-byte (this engine and the golden's
                    // recipe are required to stay identical), but it is never itself
                    // classed identical/expected-different/unexplained.
                    if computed != golden {
                        v1DriftedFromItsOwnGolden.append("\(entry.slug): V1Engine no longer matches its recorded golden")
                    }
                    continue
                }
                if computed == golden {
                    if !ids.isEmpty {
                        matchedBug.append("\(entry.slug) (\(engine.name)): still matches v1's pre-registered bug \(ids) — unfixed")
                    }
                } else if ids.isEmpty {
                    unexplained.append("\(entry.slug) (\(engine.name)): differs from v1 with no registered R id")
                }
            }
        }

        XCTAssertTrue(v1DriftedFromItsOwnGolden.isEmpty, v1DriftedFromItsOwnGolden.joined(separator: "\n"))
        XCTAssertTrue(unexplained.isEmpty, "unexplained diffs (C5):\n" + unexplained.joined(separator: "\n"))
        XCTAssertTrue(matchedBug.isEmpty, "unfixed pre-registered bugs (C5):\n" + matchedBug.joined(separator: "\n"))
    }

    /// C5, v1-only half: "the notes failing their expect_body must be exactly the
    /// registered set." No v2 engine needed — this compares v1's own computed body
    /// (== its golden, asserted above) to each note's `expect_body.txt` where one is
    /// recorded, and requires the mismatch set to equal the registered-slug set exactly.
    func testV1MismatchesExpectBodyExactlyOnRegisteredSlugs() throws {
        let root = BodyGoldenTests.corpusRoot
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path),
                          "corpus not generated — run test-fixtures/corpus/generate.py")
        let manifest = try JSONDecoder().decode(CorpusSeed.Manifest.self,
                                                from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        let expected = try Self.loadExpectedDifferences()
        let v1 = V1Engine()

        // C19 (whitespace normalisation at commit) is a "drafter's proposal", not a
        // confirmed D-decision, and has no R-row in SPEC.md's required-difference table —
        // Q10's assignment is R1/R2/R25/R33/R74/R95 only. Its two corpus notes
        // (typed-crlf-tabs-nbsp, voice-en-triple-blank-lines) carry an expect_body.txt
        // from Q9 but registering them here would be inventing a SPEC row this item was
        // never asked to settle; skip them rather than guess.
        let outOfScopeForThisItem: Set<String> = ["typed-crlf-tabs-nbsp", "voice-en-triple-blank-lines"]

        var mismatchedButUnregistered: [String] = []
        var registeredButActuallyMatches: [String] = []

        for entry in manifest.notes where !outOfScopeForThisItem.contains(entry.slug) {
            let folder = root.appendingPathComponent("notes").appendingPathComponent(entry.folder)
            let expectURL = folder.appendingPathComponent("expect_body.txt")
            guard let expectedBody = try? String(contentsOf: expectURL, encoding: .utf8) else { continue }
            let note = try JSONDecoder().decode(CorpusSeed.Note.self,
                                                from: Data(contentsOf: folder.appendingPathComponent("note.json")))
            let computed = try v1.body(for: note, folder: folder)
            let trimmedExpected = expectedBody.trimmingCharacters(in: .newlines)
            let isRegistered = !(expected[entry.slug] ?? []).isEmpty

            if computed == trimmedExpected {
                if isRegistered {
                    registeredButActuallyMatches.append("\(entry.slug): registered as a v1 bug but v1 already matches expect_body.txt")
                }
            } else if !isRegistered {
                mismatchedButUnregistered.append("\(entry.slug): v1 fails its expect_body.txt with no R id in expected-differences.json")
            }
        }

        XCTAssertTrue(mismatchedButUnregistered.isEmpty, mismatchedButUnregistered.joined(separator: "\n"))
        XCTAssertTrue(registeredButActuallyMatches.isEmpty, registeredButActuallyMatches.joined(separator: "\n"))
    }
}
