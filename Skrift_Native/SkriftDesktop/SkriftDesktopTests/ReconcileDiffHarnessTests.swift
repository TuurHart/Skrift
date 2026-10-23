import XCTest
import SwiftData

/// Q428 (gate+): the reconcile harness — the Mac-row twin of `BodyDiffHarnessTests` (Q9/Q10).
///
/// C44: every corpus note's Mac row, recorded field by field from v1's sweep, lives in
/// `test-fixtures/corpus/goldens/v1-rows/<slug>.json` (DATA, not code; a note that gets no row
/// records `"row": null`). C5: every registered sweep engine runs over the seeded corpus and each
/// row is classed identical / expected-different / unexplained against that golden; a slug
/// registered in `expected-differences-rows.json` whose row still equals v1's FAILS (matched bug).
/// C41: a second sweep changes nothing. C52 / R40: launch, activation and CloudKit import each
/// ask ONE coalescer, the sweep reads through a fresh context, no timer, and a failed cloud
/// fetch is logged and surfaced.
///
/// Re-record (v1 only, synthetic corpus only, never a real store):
/// `TEST_RUNNER_SKRIFT_RECORD_ROW_GOLDENS=1 xcodebuild test -scheme UnitTests
///  -only-testing:SkriftDesktopTests/ReconcileDiffHarnessTests/testEveryRowAgainstV1Golden_C5_C44`
@MainActor
final class ReconcileDiffHarnessTests: XCTestCase {

    // MARK: - the engine protocol

    /// One sweep implementation runnable over the seeded corpus (v1 today; v2 registers here).
    protocol SweepEngine {
        var name: String { get }
        @MainActor func sweep(cloud: ModelContext, local: ModelContext, people: [Person],
                              upload: UploadService, now: Date) -> MemoCloudReconciler.SweepOutcome
    }

    /// v1 = the shipping `MemoCloudReconciler.sweep` (the change detector, never the judge).
    struct V1SweepEngine: SweepEngine {
        let name = "v1"
        func sweep(cloud: ModelContext, local: ModelContext, people: [Person],
                   upload: UploadService, now: Date) -> MemoCloudReconciler.SweepOutcome {
            MemoCloudReconciler.sweep(from: cloud, into: local, people: people,
                                      author: ReconcileDiffHarnessTests.author,
                                      thisDeviceID: ReconcileDiffHarnessTests.device, now: now, upload: upload)
        }
    }

    static let engines: [SweepEngine] = [V1SweepEngine()]

    // MARK: - fixed inputs (the golden must not depend on the clock, the machine or a temp path)

    static let author = "Corpus Author"
    static let device = "corpus-mac"
    static let now = Date(timeIntervalSince1970: 1_767_225_600)   // 2026-01-01T00:00:00Z

    static var corpusRoot: URL { CorpusSeed.fixtureRoot(file: #filePath) }
    static var goldenDir: URL { corpusRoot.appendingPathComponent("goldens/v1-rows", isDirectory: true) }

    static func loadExpectedDifferences() throws -> [String: [String]] {
        let url = corpusRoot.appendingPathComponent("expected-differences-rows.json")
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        var out: [String: [String]] = [:]
        for (key, value) in obj where !key.hasPrefix("_") { out[key] = (value as? [String]) ?? [] }
        return out
    }

    // MARK: - one seeded run

    struct Run {
        let cloud: ModelContext
        let local: ModelContext
        let upload: UploadService
        let people: [Person]
        let manifest: CorpusSeed.Manifest
    }

    private var tempDirs: [URL] = []

    override func tearDown() {
        for dir in tempDirs { try? FileManager.default.removeItem(at: dir) }
        tempDirs = []
        super.tearDown()
    }

    private func temp(_ tag: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("q428_\(tag)_\(UUID().uuidString)", isDirectory: true)
        tempDirs.append(url)
        return url
    }

    private func seededRun() throws -> Run {
        let root = Self.corpusRoot
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path),
                          "corpus not generated — run test-fixtures/corpus/generate.py")
        _ = Self.wallClockFloor
        let cloud = ModelContext(try ModelContainer(
            for: Memo.self, MemoAsset.self, MemoEnhancement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)))
        let local = ModelContext(try ModelContainer(
            for: PipelineFile.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CorpusSeed.seed(from: root, into: cloud, recordingsDirectory: temp("rec"))
        let people = try JSONDecoder().decode([Person].self, from: Data(contentsOf: root.appendingPathComponent("names.json")))
        let manifest = try JSONDecoder().decode(CorpusSeed.Manifest.self,
                                                from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        return Run(cloud: cloud, local: local, upload: UploadService(outputDir: temp("out")),
                   people: people, manifest: manifest)
    }

    // MARK: - the row, field by field

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Taken before the first seed. A date at or after it came from the wall clock during the
    /// run, not from the corpus or `now`: v1 stamps a capture row's `uploadedAt` with
    /// `Date()` at ingest (`UploadService.commit` keeps the `PipelineFile` default when the
    /// capture path sets none). Recorded as `$WALL_CLOCK`, so the golden says "ingest time".
    static let wallClockFloor = Date()

    private static func date(_ d: Date?) -> Any {
        guard let d else { return NSNull() }
        return d >= wallClockFloor ? "$WALL_CLOCK" : iso.string(from: d)
    }
    private static func opt(_ v: Any?) -> Any { v ?? NSNull() }
    /// A JSON blob column recorded as the JSON it holds (readable diffs); anything else base64.
    private static func blob(_ d: Data?) -> Any {
        guard let d else { return NSNull() }
        if let obj = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]) { return obj }
        return ["base64": d.base64EncodedString()]
    }

    /// Every stored `PipelineFile` attribute. `testRowRecordCoversEveryStoredField` fails when
    /// the model grows a field this does not record.
    static func fields(of pf: PipelineFile) -> [String: Any] {
        [
            "id": pf.id, "filename": pf.filename, "path": pf.path, "size": pf.size,
            "sourceType": pf.sourceType.rawValue, "mediaSource": opt(pf.mediaSource),
            "transcribeStatus": pf.transcribeStatus.rawValue, "sanitiseStatus": pf.sanitiseStatus.rawValue,
            "enhanceStatus": pf.enhanceStatus.rawValue, "exportStatus": pf.exportStatus.rawValue,
            "uploadedAt": date(pf.uploadedAt), "lastActivityAt": date(pf.lastActivityAt),
            "syncedSourceEditedAt": date(pf.syncedSourceEditedAt), "memoEditedAt": date(pf.memoEditedAt),
            "syncedSourceDeletedAt": date(pf.syncedSourceDeletedAt),
            "locked": pf.locked, "remindAt": date(pf.remindAt), "imageOCRText": opt(pf.imageOCRText),
            "transcript": opt(pf.transcript), "sanitised": opt(pf.sanitised),
            "transcriptLanguageMode": opt(pf.transcriptLanguageMode),
            "ambiguousNamesJSON": blob(pf.ambiguousNamesJSON), "nameResolutionsData": blob(pf.nameResolutionsData),
            "legacyUnlinkedNames": pf.legacyUnlinkedNames, "legacyNamePicksJSON": blob(pf.legacyNamePicksJSON),
            "wordTimingsJSON": blob(pf.wordTimingsJSON), "diarizationSegmentsJSON": blob(pf.diarizationSegmentsJSON),
            "enhancedTitle": opt(pf.enhancedTitle), "titleSuggested": opt(pf.titleSuggested),
            "enhancedCopyedit": opt(pf.enhancedCopyedit), "enhancedSummary": opt(pf.enhancedSummary),
            "pendingPolishBlock": opt(pf.pendingPolishBlock),
            "tags": pf.tags, "tagSuggestions": opt(pf.tagSuggestions), "significance": opt(pf.significance),
            "destinationRaw": pf.destinationRaw, "exported": opt(pf.exported), "compiledText": opt(pf.compiledText),
            "includeAudioInExport": pf.includeAudioInExport, "error": opt(pf.error),
            "audioMetadataJSON": blob(pf.audioMetadataJSON), "transcriptUserEdited": pf.transcriptUserEdited,
            "isLocalRecording": pf.isLocalRecording, "isLocalImport": pf.isLocalImport,
            "appleNoteID": opt(pf.appleNoteID), "diarizeRequested": pf.diarizeRequested,
            "deletedAt": date(pf.deletedAt),
        ]
    }

    /// The row's working folder: every file (relative path) and its byte count.
    static func folderListing(_ pf: PipelineFile) -> [[String: Any]] {
        guard let folder = pf.workingFolder else { return [] }
        let base = folder.resolvingSymlinksInPath()
        guard let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
        else { return [] }
        var out: [[String: Any]] = []
        for case let url as URL in e {
            let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard v?.isRegularFile == true else { continue }
            let full = url.resolvingSymlinksInPath().path
            guard full.hasPrefix(base.path + "/") else { continue }
            let rel = String(full.dropFirst(base.path.count + 1))
            out.append(["file": rel, "bytes": v?.fileSize ?? 0])
        }
        return out.sorted { ($0["file"] as? String ?? "") < ($1["file"] as? String ?? "") }
    }

    /// One note's full record, normalised: serialised with the temp output dir replaced by
    /// `$OUT`, then parsed back — the exact shape a golden file decodes to.
    static func record(slug: String, memoID: String, expectsRow: Bool, row: PipelineFile?,
                       outDir: URL) throws -> [String: Any] {
        let raw: [String: Any] = [
            "slug": slug, "memoID": memoID, "expectsRow": expectsRow,
            "row": row.map { fields(of: $0) } ?? NSNull(),
            "folder": row.map { folderListing($0) } ?? [],
        ]
        var text = String(decoding: try JSONSerialization.data(
            withJSONObject: raw, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
        for prefix in Set([outDir.path, outDir.standardizedFileURL.path, outDir.resolvingSymlinksInPath().path]) {
            text = text.replacingOccurrences(of: prefix, with: "$OUT")
        }
        return try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] ?? [:]
    }

    static func serialise(_ record: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: record,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }

    /// Every manifest note's record after one sweep of `engine`, keyed by slug.
    private func records(_ run: Run) throws -> [String: [String: Any]] {
        let memos = try run.cloud.fetch(FetchDescriptor<Memo>())
        let memoByID = Dictionary(memos.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        let rows = try run.local.fetch(FetchDescriptor<PipelineFile>())
        let rowByID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [String: [String: Any]] = [:]
        for entry in run.manifest.notes {
            let memo = memoByID[entry.id]
            let expectsRow = memo.map { $0.deletedAt == nil && NoteConsent.isRated($0) } ?? false
            out[entry.slug] = try Self.record(slug: entry.slug, memoID: entry.id, expectsRow: expectsRow,
                                              row: rowByID[entry.id], outDir: run.upload.outputDir)
        }
        return out
    }

    /// The field names (top-level keys of `row`, plus `row`/`folder` themselves) that differ.
    static func differingFields(_ a: [String: Any], _ b: [String: Any]) -> [String] {
        var diffs: [String] = []
        let rowA = a["row"] as? [String: Any], rowB = b["row"] as? [String: Any]
        if (rowA == nil) != (rowB == nil) { return ["row (present vs absent)"] }
        if let rowA, let rowB {
            for key in Set(rowA.keys).union(rowB.keys).sorted()
            where !(rowA[key].map { $0 as AnyObject }?.isEqual(rowB[key]) ?? (rowB[key] == nil)) {
                diffs.append(key)
            }
        }
        if !((a["folder"] as AnyObject?)?.isEqual(b["folder"]) ?? false) { diffs.append("folder") }
        if !((a["expectsRow"] as AnyObject?)?.isEqual(b["expectsRow"]) ?? false) { diffs.append("expectsRow") }
        return diffs
    }

    // MARK: - C5 / C44: every engine's rows against v1's golden

    func testEveryRowAgainstV1Golden_C5_C44() throws {
        let recording = ProcessInfo.processInfo.environment["SKRIFT_RECORD_ROW_GOLDENS"] == "1"
        let expected = try Self.loadExpectedDifferences()
        for engine in Self.engines {
            let run = try seededRun()
            let outcome = engine.sweep(cloud: run.cloud, local: run.local, people: run.people,
                                       upload: run.upload, now: Self.now)
            XCTAssertNil(outcome.fetchFailure, "\(engine.name): the corpus store must read")
            XCTAssertEqual(outcome.ingestFailures, 0, "\(engine.name)")
            let recs = try records(run)

            if recording, engine.name == "v1" {
                try FileManager.default.createDirectory(at: Self.goldenDir, withIntermediateDirectories: true)
                for (slug, rec) in recs {
                    try Self.serialise(rec).write(to: Self.goldenDir.appendingPathComponent("\(slug).json"))
                }
                print("ReconcileDiffHarness: recorded \(recs.count) v1 row goldens")
                continue
            }

            var identical = 0, expectedDifferent = 0
            var unexplained: [String] = [], matchedBug: [String] = [], missing: [String] = []
            for entry in run.manifest.notes {
                let url = Self.goldenDir.appendingPathComponent("\(entry.slug).json")
                guard let data = try? Data(contentsOf: url),
                      let golden = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    missing.append(entry.slug); continue
                }
                let diffs = Self.differingFields(try XCTUnwrap(recs[entry.slug]), golden)
                let registered = expected[entry.slug] ?? []
                if diffs.isEmpty {
                    identical += 1
                    if !registered.isEmpty { matchedBug.append("\(entry.slug): still equals v1 on registered \(registered)") }
                } else if registered.isEmpty {
                    unexplained.append("\(entry.slug): \(diffs.joined(separator: ", "))")
                } else {
                    expectedDifferent += 1
                }
            }
            print("ReconcileDiffHarness[\(engine.name)]: identical \(identical), expected-different \(expectedDifferent), unexplained \(unexplained.count)")
            XCTAssertTrue(missing.isEmpty, "\(engine.name): no golden for \(missing) — record with SKRIFT_RECORD_ROW_GOLDENS=1")
            XCTAssertTrue(unexplained.isEmpty, "\(engine.name) unexplained (C5):\n" + unexplained.joined(separator: "\n"))
            XCTAssertTrue(matchedBug.isEmpty, "\(engine.name) unfixed registered bugs (C5):\n" + matchedBug.joined(separator: "\n"))
            XCTAssertGreaterThanOrEqual(identical + expectedDifferent, 100, "\(engine.name): the whole corpus is classed")
        }
    }

    /// The goldens are one per manifest note, and the ones that should hold a row do (C41's
    /// rate→row rule, read straight off the recorded data).
    func testGoldensCoverTheCorpusAndHoldTheRateToRowRule() throws {
        let manifest = try JSONDecoder().decode(CorpusSeed.Manifest.self,
                                                from: Data(contentsOf: Self.corpusRoot.appendingPathComponent("manifest.json")))
        var withRow = 0
        for entry in manifest.notes {
            let data = try Data(contentsOf: Self.goldenDir.appendingPathComponent("\(entry.slug).json"))
            let golden = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any], entry.slug)
            let expects = try XCTUnwrap(golden["expectsRow"] as? Bool, entry.slug)
            let row = golden["row"] as? [String: Any]
            XCTAssertEqual(row != nil, expects, "\(entry.slug): rated+live ⇔ a row")
            if let row { withRow += 1; XCTAssertEqual(row["id"] as? String, entry.id, "\(entry.slug): row id = memo id") }
        }
        XCTAssertGreaterThan(withRow, 60)
    }

    /// The record misses no stored attribute (a new `PipelineFile` field must reach the golden).
    func testRowRecordCoversEveryStoredField() throws {
        let entity = try XCTUnwrap(Schema([PipelineFile.self]).entities.first { $0.name == "PipelineFile" })
        let stored = Set(entity.attributes.map(\.name))
        let recorded = Set(Self.fields(of: PipelineFile()).keys)
        XCTAssertEqual(stored.subtracting(recorded), [], "stored but not recorded")
        XCTAssertEqual(recorded.subtracting(stored), [], "recorded but not stored")
    }

    // MARK: - C41: a second sweep changes nothing

    /// Known C41 violations in v1, each self-expiring (the test fails once the note settles on
    /// the second sweep, so the entry must then be removed).
    /// - pic-missing-file: the memo's manifest names a photo whose blob never synced. v1's first
    ///   ingest writes no `image_manifest.json` (`UploadService.saveImages` returns early with zero
    ///   photos); the second sweep's `MemoPhotoMaterializer` writes it, reports a heal and bumps
    ///   `lastActivityAt`. The third sweep is a no-op.
    static let secondSweepConflicts: [String: Set<String>] = [
        "pic-missing-file": ["lastActivityAt", "folder"],
    ]

    func testSecondSweepChangesNothing_C41() throws {
        for engine in Self.engines {
            let run = try seededRun()
            _ = engine.sweep(cloud: run.cloud, local: run.local, people: run.people, upload: run.upload, now: Self.now)
            let first = try records(run)
            let again = engine.sweep(cloud: run.cloud, local: run.local, people: run.people, upload: run.upload,
                                     now: Self.now.addingTimeInterval(3600))
            let conflictIDs = Set(run.manifest.notes.filter { Self.secondSweepConflicts[$0.slug] != nil }.map(\.id))
            XCTAssertEqual(again.created, 0, "\(engine.name): second sweep created rows")
            XCTAssertEqual(Set(again.updatedIDs).subtracting(conflictIDs), [], "\(engine.name): second sweep rewrote rows")
            XCTAssertEqual(again.ingestFailures, 0, "\(engine.name)")
            XCTAssertEqual(again.stranded, 0, "\(engine.name)")
            let second = try records(run)
            for (slug, rec) in first {
                let diffs = Self.differingFields(rec, try XCTUnwrap(second[slug]))
                if let known = Self.secondSweepConflicts[slug] {
                    XCTAssertEqual(Set(diffs), known,
                                   "\(engine.name) \(slug): known C41 conflict changed shape or was fixed — update secondSweepConflicts")
                } else {
                    XCTAssertEqual(diffs, [], "\(engine.name) \(slug): second sweep changed \(diffs)")
                }
            }
            // Every note, the known conflicts included, is settled by the third sweep.
            let third = engine.sweep(cloud: run.cloud, local: run.local, people: run.people, upload: run.upload,
                                     now: Self.now.addingTimeInterval(7200))
            XCTAssertEqual(third.created, 0)
            XCTAssertEqual(third.updatedIDs, [], "\(engine.name): third sweep still rewrote rows")
            let thirdRecs = try records(run)
            for (slug, rec) in second {
                let diffs = Self.differingFields(rec, try XCTUnwrap(thirdRecs[slug]))
                XCTAssertEqual(diffs, [], "\(engine.name) \(slug): third sweep changed \(diffs)")
            }
            // One row per rated live memo, id = memo id; none for a never-rated or trashed one.
            let rows = try run.local.fetch(FetchDescriptor<PipelineFile>())
            XCTAssertEqual(rows.count, Set(rows.map(\.id)).count, "\(engine.name): duplicate rows")
            for memo in try run.cloud.fetch(FetchDescriptor<Memo>()) {
                let have = rows.contains { $0.id == memo.id.uuidString }
                XCTAssertEqual(have, memo.deletedAt == nil && NoteConsent.isRated(memo),
                               "\(engine.name) \(memo.title ?? memo.id.uuidString)")
            }
        }
    }

    // MARK: - R40: a failed cloud fetch is logged and surfaced, never swallowed

    struct InjectedFetchError: LocalizedError {
        var errorDescription: String? { "injected store read failure" }
    }

    func testFailedCloudFetchIsReportedNotSwallowed_R40() throws {
        let run = try seededRun()
        let failing: (ModelContext) throws -> [Memo] = { _ in throw InjectedFetchError() }
        let outcome = MemoCloudReconciler.sweep(from: run.cloud, into: run.local, people: run.people,
                                                author: Self.author, thisDeviceID: Self.device, now: Self.now,
                                                upload: run.upload, fetchMemos: failing)
        let failure = try XCTUnwrap(outcome.fetchFailure, "a failed fetch must not read as an empty store")
        XCTAssertTrue(failure.contains("injected store read failure"), failure)
        XCTAssertEqual(outcome.created, 0)
        XCTAssertEqual(try run.local.fetchCount(FetchDescriptor<PipelineFile>()), 0)

        let pass = try MemoCloudReconciler.pass(from: run.cloud, into: run.local, people: run.people,
                                                author: Self.author, thisDeviceID: Self.device, now: Self.now,
                                                upload: run.upload, firstImportDone: true, fetchMemos: failing)
        XCTAssertNotNil(pass.sweep.fetchFailure)
        XCTAssertEqual(pass.authored, 0)

        // Shown: the sync state turns "couldn't start" and its detail line carries the error.
        XCTAssertEqual(MacSyncState.resolve(switchOn: true, containerOpened: true, account: .available,
                                            inFlight: false, sweepFailed: true), .failed)
        XCTAssertNotNil(MacSyncState.failed.capsuleText)
        let detail = MacSyncState.failureDetail(account: .available, sweepFailure: failure)
        XCTAssertTrue(detail.contains("injected store read failure"), detail)
        XCTAssertEqual(MacSyncState.resolve(switchOn: true, containerOpened: true, account: .available,
                                            inFlight: false, sweepFailed: false), .upToDate,
                       "a good sweep clears it")

        // The same store, read normally, ingests: the failure was the fetch, not the data.
        let ok = MemoCloudReconciler.sweep(from: run.cloud, into: run.local, people: run.people,
                                           author: Self.author, thisDeviceID: Self.device, now: Self.now,
                                           upload: run.upload)
        XCTAssertNil(ok.fetchFailure)
        XCTAssertGreaterThan(ok.created, 60)
    }

    // MARK: - C52: triggers, coalescing, fresh context, no timer

    func testTriggersCoalesceIntoOneSweep_C52() async throws {
        var ran = 0
        let c = ReconcileCoalescer(delay: .milliseconds(100)) { ran += 1 }
        for trigger in ReconcileTrigger.external { c.request(trigger) }
        XCTAssertEqual(c.requestedSinceRun, ReconcileTrigger.external)
        XCTAssertEqual(ran, 0, "nothing runs synchronously")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(ran, 1, "launch + activation + import inside the window = ONE sweep")
        XCTAssertEqual(c.runs, 1)
        XCTAssertNil(c.pending)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(ran, 1, "no further sweep without a trigger (no heartbeat)")

        // Each trigger on its own, outside the window, gets its own sweep.
        for (i, trigger) in ReconcileTrigger.external.enumerated() {
            c.request(trigger)
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertEqual(ran, 2 + i, "\(trigger) runs one sweep")
        }
    }

    func testSweepReadsThroughAFreshContext_C52() throws {
        let container = try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                              cloudKitDatabase: .none))
        let long = container.mainContext
        let fresh1 = MemoCloudReconciler.freshCloudContext(container)
        let fresh2 = MemoCloudReconciler.freshCloudContext(container)
        XCTAssertFalse(fresh1 === long)
        XCTAssertFalse(fresh1 === fresh2, "a new context per sweep")

        // A memo another context (the CloudKit import) wrote after the fresh one was made is seen.
        let writer = ModelContext(container)
        let memo = try Memo.newTyped(into: writer)
        memo.transcript = "typed on the phone"
        memo.transcriptUserEdited = true
        memo.significance = 0.5
        try writer.save()
        let local = ModelContext(try ModelContainer(for: PipelineFile.self,
                                                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let outcome = MemoCloudReconciler.sweep(from: MemoCloudReconciler.freshCloudContext(container), into: local,
                                                thisDeviceID: Self.device, now: Self.now,
                                                upload: UploadService(outputDir: temp("fresh")))
        XCTAssertEqual(outcome.created, 1)
    }

    /// The app wiring itself: the three triggers go through `reconcileSoon(<trigger>)`, the
    /// sweep reads `freshCloudContext`, a failure reaches `reportSweep`, and nothing is on a timer.
    func testWiringRegistersTheThreeTriggersAndNoTimer_C52() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        // Code only: comments may name what the code must not do.
        func code(_ path: String) throws -> String {
            try String(contentsOf: app.appendingPathComponent(path), encoding: .utf8)
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
        }
        let wiring = try code("App/MemoCloudReconciler+Wiring.swift")
        for trigger in ReconcileTrigger.external {
            XCTAssertTrue(wiring.contains("reconcileSoon(.\(trigger.rawValue))"), "\(trigger) not wired")
        }
        XCTAssertTrue(wiring.contains("NSApplication.didBecomeActiveNotification"))
        XCTAssertTrue(wiring.contains("NSPersistentCloudKitContainer.eventChangedNotification"))
        XCTAssertTrue(wiring.contains("MemoCloudReconciler.freshCloudContext(cloud)"))
        XCTAssertFalse(wiring.contains("cloud.mainContext"), "the sweep must not read a long-lived context")
        XCTAssertTrue(wiring.contains("reportSweep(failure: outcome.fetchFailure)"))
        for timer in ["Timer.", "Timer(", "makeTimerSource", "scheduledTimer"] {
            XCTAssertFalse(wiring.contains(timer), "C52: no heartbeat timers (\(timer))")
        }
        let core = try code("Pipeline/Ingest/MemoCloudReconciler.swift")
        XCTAssertFalse(core.contains("try? cloudContext.fetch(FetchDescriptor<Memo>())"), "R40: the memo fetch is never try?'d")
    }
}
