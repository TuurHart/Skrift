import XCTest

/// Q14 (gate+): the one-time body normalisation (C10, D4, R25, C203). Legacy bodies are the
/// v1 goldens AND the body v1 actually STORED (markers at the photo's moment, before the
/// render-time snap), for every corpus note. Each must come out in v2's shape with its words
/// and markers intact, a second run must be a no-op, C203 shapes stay untouched, and undo must
/// put the original back.
final class BodyNormaliseMigrationTests: XCTestCase {

    // MARK: corpus

    private struct Legacy { let label: String; let body: String; let manifestCount: Int }

    private static let markerLiteral = try! NSRegularExpression(pattern: #"\[\[img_\d+\]\]"#)

    private func folders() throws -> [String: URL] {
        let root = BodyGoldenTests.corpusRoot
        var out: [String: URL] = [:]
        for name in ["manifest.json", "manifest-q23.json"] {
            let url = root.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let m = try JSONDecoder().decode(CorpusSeed.Manifest.self, from: Data(contentsOf: url))
            for e in m.notes { out[e.slug] = root.appendingPathComponent("notes").appendingPathComponent(e.folder) }
        }
        return out
    }

    private func note(_ folder: URL) throws -> CorpusSeed.Note {
        try JSONDecoder().decode(CorpusSeed.Note.self, from: Data(contentsOf: folder.appendingPathComponent("note.json")))
    }

    private func manifest(_ n: CorpusSeed.Note) -> [ImageManifestEntry] {
        guard let data = n.metadata.data, let m = try? JSONDecoder().decode(MemoMetadata.self, from: data) else { return [] }
        return m.imageManifest ?? []
    }

    /// What v1 STORED: markers inserted at each photo's moment from the word timings, then the
    /// stored-transcript paragrapher (the same recipe as `BodyGoldenTests`, minus the snap).
    private func v1Stored(_ n: CorpusSeed.Note, folder: URL) throws -> String {
        let t = n.transcript ?? ""
        let bare = Self.markerLiteral.stringByReplacingMatches(
            in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "")
        var timings: [WordTiming] = []
        if let wt = n.wordTimings {
            timings = try JSONDecoder().decode([WordTiming].self, from: Data(contentsOf: folder.appendingPathComponent(wt)))
        }
        let words = timings.map { TimedWord(text: $0.word, start: $0.start, end: $0.end) }
        let withMarkers = ImageMarkers.insert(transcript: bare, words: words, manifest: manifest(n))
        return timings.isEmpty ? withMarkers : Paragrapher.paragraphed(transcript: withMarkers, words: timings)
    }

    private func legacyBodies() throws -> [Legacy] {
        let folders = try folders()
        let goldenDir = BodyGoldenTests.goldenDir
        let goldens = try FileManager.default.contentsOfDirectory(atPath: goldenDir.path).filter { $0.hasSuffix(".txt") }.sorted()
        XCTAssertFalse(goldens.isEmpty, "no v1 goldens found")
        var out: [Legacy] = []
        for file in goldens {
            let slug = String(file.dropLast(4))
            guard let folder = folders[slug] else { continue }
            let n = try note(folder)
            let count = manifest(n).count
            let golden = try String(contentsOf: goldenDir.appendingPathComponent(file), encoding: .utf8)
            out.append(Legacy(label: "golden \(slug)", body: golden, manifestCount: count))
            out.append(Legacy(label: "v1-stored \(slug)", body: try v1Stored(n, folder: folder), manifestCount: count))
            if let stored = n.transcript, stored.contains("[[img_") {
                out.append(Legacy(label: "corpus-stored \(slug)", body: stored, manifestCount: count))
            }
            if let offsets = CorpusSeed.nameOffsets(folder: folder) {
                out.append(Legacy(label: "name-offsets \(slug)", body: offsets.legacyBody, manifestCount: count))
            }
        }
        return out
    }

    private func isV2Shape(_ body: String, manifestCount: Int) -> Bool {
        !BodyNormaliseMigration.needsNormalise(body, manifestCount: manifestCount)
    }

    // MARK: every legacy body → v2

    func testEveryLegacyBodyComesOutInV2ShapeWithWordsAndMarkersKept() throws {
        let legacy = try legacyBodies()
        var rewritten = 0
        var failures: [String] = []
        for l in legacy {
            for machine in [true, false] {
                let before = BodyNormaliseMigration.needsNormalise(l.body, manifestCount: l.manifestCount)
                let out = BodyNormaliseMigration.rewrite(l.body, manifestCount: l.manifestCount, machineText: machine)
                guard before else {
                    if out != nil { failures.append("\(l.label) machine=\(machine): already v2 but rewritten") }
                    continue
                }
                guard let out else { failures.append("\(l.label) machine=\(machine): legacy body left unnormalised"); continue }
                rewritten += 1
                if !isV2Shape(out, manifestCount: l.manifestCount) { failures.append("\(l.label): still breaks C10\n\(out)") }
                if BodyNormaliseMigration.words(out) != BodyNormaliseMigration.words(l.body) {
                    failures.append("\(l.label) machine=\(machine): words changed")
                }
                if BodyV2Marker.numbers(in: out).sorted() != BodyV2Marker.numbers(in: l.body).sorted() {
                    failures.append("\(l.label) machine=\(machine): markers changed")
                }
                // Second run: a no-op.
                if BodyNormaliseMigration.rewrite(out, manifestCount: l.manifestCount, machineText: machine) != nil {
                    failures.append("\(l.label) machine=\(machine): second run rewrote again")
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n---\n"))
        XCTAssertGreaterThan(rewritten, 0, "no legacy body in the corpus needed normalising — the test would be vacuous")
    }

    func testV1MidSentenceMarkerMovesToTheSentenceEnd() {
        let body = "The kiln sat\n\n[[img_001]]\n\n down. Then we left."
        let out = BodyNormaliseMigration.rewrite(body, manifestCount: 1, machineText: false)
        XCTAssertEqual(out, "The kiln sat down.\n\n[[img_001]]\n\nThen we left.")
    }

    func testEditedBodyOnlyMovesTheMarker() {
        // A user-edited body keeps its own whitespace; only the picture paragraph moves.
        let body = "Kept  two  spaces [[img_001]] here. Next line."
        let out = BodyNormaliseMigration.rewrite(body, manifestCount: 1, machineText: false)
        XCTAssertEqual(out, "Kept  two  spaces here.\n\n[[img_001]]\n\nNext line.")
    }

    func testMarkerPastTheManifestIsTheAuthorsText() {
        XCTAssertNil(BodyNormaliseMigration.rewrite("Text [[img_004]] inline.", manifestCount: 1, machineText: true))
        XCTAssertNil(BodyNormaliseMigration.rewrite("Text [[img_001]] inline.", manifestCount: 0, machineText: true))
    }

    func testPreservationCheckCatchesALostWord() {
        XCTAssertFalse(BodyNormaliseMigration.preserves("a b [[img_001]] c.", "a b c"))
        XCTAssertFalse(BodyNormaliseMigration.preserves("a [[img_001]] b.", "a b."))
        XCTAssertTrue(BodyNormaliseMigration.preserves("a [[img_001]] b.", "a b.\n\n[[img_001]]"))
    }

    // MARK: once-flag, C203, undo

    private func tempLedger() -> BodyNormaliseMigration.Ledger {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("q14-ledger-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return .init(directory: dir)
    }

    private final class Box { var text: String?; init(_ t: String?) { text = t } }

    private func body(_ box: Box, _ name: String = "transcript") -> BodyNormaliseMigration.Body {
        .init(name: name, get: { box.text }, set: { box.text = $0 })
    }

    func testRunsOnceAndASecondRunIsANoOp() throws {
        let ledger = tempLedger()
        let original = "We sat\n\n[[img_001]]\n\n down by the kiln."
        let box = Box(original)
        let first = BodyNormaliseMigration.run(id: "n1", bodies: [body(box)], manifestCount: 1,
                                               machineText: true, legacyShape: false, ledger: ledger)
        XCTAssertEqual(first, .rewritten)
        let migrated = try XCTUnwrap(box.text)
        XCTAssertTrue(isV2Shape(migrated, manifestCount: 1))
        XCTAssertEqual(ledger.record(for: "n1")?.fields["transcript"]?.original, original)

        // Even if the body is put back into a v1 shape by someone else, the flag holds.
        box.text = original
        XCTAssertNil(BodyNormaliseMigration.run(id: "n1", bodies: [body(box)], manifestCount: 1,
                                                machineText: true, legacyShape: false, ledger: ledger))
        XCTAssertEqual(box.text, original)
    }

    func testAlreadyV2NoteIsFlaggedCleanAndUntouched() {
        let ledger = tempLedger()
        let v2 = "We sat down.\n\n[[img_001]]\n\nThen we left."
        let box = Box(v2)
        XCTAssertEqual(BodyNormaliseMigration.run(id: "n2", bodies: [body(box)], manifestCount: 1,
                                                  machineText: true, legacyShape: false, ledger: ledger), .clean)
        XCTAssertEqual(box.text, v2)
        XCTAssertTrue(ledger.hasRun("n2"))
    }

    func testC203ShapesAreLeftAlone() {
        let old = Date(timeIntervalSince1970: 1_780_000_000)      // 2026-05-28
        let new = Date(timeIntervalSince1970: 1_790_000_000)      // 2026-09-21
        let image: [String: Any] = ["type": "image"]
        let pdf: [String: Any] = ["type": "file", "fileName": "Report.pdf", "mimeType": "application/pdf"]
        let txt: [String: Any] = ["type": "file", "fileName": "notes.txt", "mimeType": "text/plain"]
        XCTAssertTrue(BodyNormaliseMigration.isC203Legacy(sharedContent: image, madeAt: old))
        XCTAssertFalse(BodyNormaliseMigration.isC203Legacy(sharedContent: image, madeAt: new))
        XCTAssertTrue(BodyNormaliseMigration.isC203Legacy(sharedContent: pdf, madeAt: old))
        XCTAssertFalse(BodyNormaliseMigration.isC203Legacy(sharedContent: pdf, madeAt: new))
        XCTAssertFalse(BodyNormaliseMigration.isC203Legacy(sharedContent: txt, madeAt: old))
        XCTAssertFalse(BodyNormaliseMigration.isC203Legacy(sharedContent: nil, madeAt: old))
        // Cutoffs: 18da97ad (round 3) and b41ec828 (build 76).
        XCTAssertFalse(BodyNormaliseMigration.isC203Legacy(sharedContent: image, madeAt: BodyNormaliseMigration.imageCaptureCutoff))
        XCTAssertTrue(BodyNormaliseMigration.isC203Legacy(sharedContent: pdf,
                                                          madeAt: BodyNormaliseMigration.pdfCaptureCutoff.addingTimeInterval(-1)))

        let ledger = tempLedger()
        let broken = "A photo [[img_001]] inside a sentence."
        let box = Box(broken)
        XCTAssertEqual(BodyNormaliseMigration.run(id: "legacy", bodies: [body(box)], manifestCount: 1,
                                                  machineText: false, legacyShape: true, ledger: ledger), .legacyShape)
        XCTAssertEqual(box.text, broken)
        XCTAssertNil(BodyNormaliseMigration.run(id: "legacy", bodies: [body(box)], manifestCount: 1,
                                                machineText: false, legacyShape: false, ledger: ledger))
        XCTAssertEqual(box.text, broken)
    }

    func testUndoRestoresTheOriginalAndNeverMigratesAgain() {
        let ledger = tempLedger()
        let original = "We sat\n\n[[img_001]]\n\n down by the kiln."
        let box = Box(original)
        BodyNormaliseMigration.run(id: "u1", bodies: [body(box)], manifestCount: 1,
                                   machineText: true, legacyShape: false, ledger: ledger)
        XCTAssertNotEqual(box.text, original)
        XCTAssertEqual(BodyNormaliseMigration.undo(id: "u1", bodies: [body(box)], ledger: ledger), ["transcript"])
        XCTAssertEqual(box.text, original)
        XCTAssertEqual(ledger.record(for: "u1")?.outcome, .undone)
        XCTAssertNil(BodyNormaliseMigration.run(id: "u1", bodies: [body(box)], manifestCount: 1,
                                                machineText: true, legacyShape: false, ledger: ledger))
        XCTAssertEqual(box.text, original)
    }

    func testUndoLeavesALaterEditAlone() {
        let ledger = tempLedger()
        let box = Box("We sat\n\n[[img_001]]\n\n down by the kiln.")
        BodyNormaliseMigration.run(id: "u2", bodies: [body(box)], manifestCount: 1,
                                   machineText: true, legacyShape: false, ledger: ledger)
        box.text = "Edited after the migration.\n\n[[img_001]]"
        XCTAssertEqual(BodyNormaliseMigration.undo(id: "u2", bodies: [body(box)], ledger: ledger), [])
        XCTAssertEqual(box.text, "Edited after the migration.\n\n[[img_001]]")
    }

    // MARK: R25 — name offsets re-derived

    func testMigratedStaleNameOffsetsAreRederived() throws {
        let folders = try folders()
        let folder = try XCTUnwrap(folders["migrated-stale-name-offsets"], "R25 fixture missing")
        let fixture = try XCTUnwrap(CorpusSeed.nameOffsets(folder: folder), "name_offsets.json missing")
        let count = manifest(try note(folder)).count
        XCTAssertTrue(BodyNormaliseMigration.needsNormalise(fixture.legacyBody, manifestCount: count),
                      "the fixture's stored body must be v1-shaped")
        let migrated = try XCTUnwrap(BodyNormaliseMigration.rewrite(fixture.legacyBody, manifestCount: count, machineText: true))
        let ns = migrated as NSString
        let roster = try JSONDecoder().decode([Person].self, from: Data(contentsOf:
            BodyGoldenTests.corpusRoot.appendingPathComponent("names.json")))
        let rederived = Sanitiser.nameSpans(inRaw: migrated, people: roster)

        for name in fixture.names {
            XCTAssertEqual((fixture.legacyBody as NSString).substring(with: NSRange(location: name.offset, length: name.length)), name.alias)
            // Stale before: the stored offset no longer reads as the name in the new body.
            let stale = NSRange(location: name.offset, length: name.length)
            XCTAssertFalse(stale.location + stale.length <= ns.length && ns.substring(with: stale) == name.alias,
                           "fixture would not prove staleness")
            let occ = AmbiguousOccurrence(alias: name.alias, offset: name.offset, length: name.length,
                                          contextBefore: "", contextAfter: "", candidates: [])
            let moved = BodyNormaliseMigration.remap([occ], from: fixture.legacyBody, to: migrated)
            XCTAssertEqual(moved.map(\.offset), [name.offsetAfter])
            XCTAssertEqual(ns.substring(with: NSRange(location: name.offsetAfter, length: name.length)), name.alias)
            // Re-sanitising the new body finds the name at the same place.
            XCTAssertTrue(rederived.contains { $0.offset == name.offsetAfter && $0.length == name.length },
                          "re-sanitised spans: \(rederived.map { ($0.alias, $0.offset) })")
        }
    }

    func testMacNoteMigratesItsBodiesAndNameOffsetsAndUndoesThem() throws {
        let ledger = tempLedger()
        let legacy = "We checked the crack near the handle\n\n[[img_001]]\n\n and Lotte thought it might still be fireable."
        let pf = PipelineFile(id: "mac-r25", filename: "memo.m4a", path: "/tmp/x", size: 0, sourceType: .audio)
        pf.transcript = legacy
        pf.sanitised = legacy
        pf.audioMetadataJSON = try JSONSerialization.data(withJSONObject: [
            "imageManifest": [["filename": "p.jpg", "offsetSeconds": 1.6]],
            "recordedAt": "2026-08-14T09:35:00Z"])
        pf.ambiguousNames = [AmbiguousOccurrence(alias: "Lotte", offset: 56, length: 5,
                                                 contextBefore: "", contextAfter: "", candidates: [])]

        XCTAssertEqual(pf.normaliseBodyOnce(ledger: ledger), .rewritten)
        let s = try XCTUnwrap(pf.sanitised)
        XCTAssertTrue(isV2Shape(s, manifestCount: 1))
        XCTAssertEqual(pf.transcript, s)
        let occ = try XCTUnwrap(pf.ambiguousNames?.first)
        XCTAssertEqual((s as NSString).substring(with: NSRange(location: occ.offset, length: occ.length)), "Lotte")
        XCTAssertNil(pf.normaliseBodyOnce(ledger: ledger), "second open must be a no-op")

        XCTAssertTrue(pf.undoBodyNormalise(ledger: ledger))
        XCTAssertEqual(pf.transcript, legacy)
        XCTAssertEqual(pf.sanitised, legacy)
        XCTAssertEqual(pf.ambiguousNames?.first?.offset, 56)
        XCTAssertNil(pf.normaliseBodyOnce(ledger: ledger), "an undone note is never migrated again")
    }
}
