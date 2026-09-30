import XCTest
import SwiftData

/// Q90 / D159 (Tuur 2026-09-30, "yes it should"): a Mac import arrives UNRATED, exactly like a
/// Mac recording. Reverses the July rule "an import is consent, floors to 0.1" (C49).
/// Words are not polish, so it is still transcribed on arrival (Q77); it enters the Process
/// queue / polish / export only once rated.
@MainActor
final class MacImportUnratedTests: XCTestCase {

    private func pipelineContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: PipelineFile.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func cloudContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Memo.self, MemoAsset.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                           cloudKitDatabase: .none)))
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func fakeAudio(in dir: URL, named name: String = "imported memo.m4a") throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(repeating: 0, count: 4096).write(to: url)
        return url
    }

    /// Run one import through the real arrival path.
    private func importOne(work: URL, ctx: ModelContext, cloud: ModelContext? = nil,
                           onTranscribe: @escaping ([String]) -> Void = { _ in }) async throws -> PipelineFile {
        var hooks = ArrivalPath.Hooks.inert
        hooks.transcribeImport = onTranscribe
        let created = try await ArrivalPath.run(
            urls: [try fakeAudio(in: work)], asRecording: false, into: ctx, cloudContext: cloud,
            hooks: hooks, service: IngestService(outputDir: work.appendingPathComponent("out")))
        return try XCTUnwrap(created.first)
    }

    /// The row an import leaves behind reads UNRATED, and it is not a recording.
    func testAnImportRowIsUnrated() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let ctx = try pipelineContext()
        let pf = try await importOne(work: work, ctx: ctx)
        XCTAssertFalse(pf.isLocalRecording)
        XCTAssertFalse(NoteConsent.isRated(pf), "an import is not judged by being added")
    }

    /// Words are not polish: an unrated import is still handed to transcription on arrival.
    func testAnUnratedImportIsStillTranscribedOnArrival() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let ctx = try pipelineContext()
        var transcribed: [String] = []
        let pf = try await importOne(work: work, ctx: ctx) { transcribed += $0 }
        XCTAssertEqual(transcribed, [pf.id])
    }

    /// Absent from the process queue while unrated; a quiet row, not a lit queue row.
    func testAnUnratedImportIsNotInTheProcessQueue() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let ctx = try pipelineContext()
        let pf = try await importOne(work: work, ctx: ctx)
        pf.transcribeStatus = .done   // its words have landed
        XCTAssertFalse(WayOutRules.needsProcessing(pf), "unrated → refused by the Process gate")
        XCTAssertTrue(WayOutRules.isQuietLocalTake(pf), "unrated → quiet row, not a queue row")
        XCTAssertFalse(NoteConsent.joinsConnectionsIndex(pf))
    }

    /// Once rated it enters the queue like any rated note.
    func testARatedImportEntersTheProcessQueue() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let ctx = try pipelineContext()
        let pf = try await importOne(work: work, ctx: ctx)
        pf.transcribeStatus = .done
        pf.significance = 0.1
        XCTAssertTrue(NoteConsent.isRated(pf))
        XCTAssertTrue(WayOutRules.needsProcessing(pf))
        XCTAssertFalse(WayOutRules.isQuietLocalTake(pf))
    }

    /// The Memo an import authors (the reconcile sweep does it) is unrated too, so the phone
    /// does not see it pre-rated "passing".
    func testTheSweepAuthorsAnImportsMemoUnrated() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let ctx = try pipelineContext()
        let cloud = try cloudContext()
        let pf = try await importOne(work: work, ctx: ctx)
        XCTAssertEqual(try MacMemoAuthor.backfill(files: [pf], into: cloud), 1)
        XCTAssertEqual(try cloud.fetch(FetchDescriptor<Memo>()).first?.significance, 0)
    }

    /// A row from before this change (nil significance, never stamped as a local take — an old
    /// import) stays rated: its Memo carries the 0.1 floor it was authored with.
    func testALegacyInsertedRowWithNilSignificanceStaysRated() throws {
        let ctx = try pipelineContext()
        let pf = PipelineFile(id: UUID().uuidString)
        ctx.insert(pf)
        XCTAssertTrue(NoteConsent.isRated(pf))
        XCTAssertTrue(WayOutRules.needsProcessing(pf))
    }
}
