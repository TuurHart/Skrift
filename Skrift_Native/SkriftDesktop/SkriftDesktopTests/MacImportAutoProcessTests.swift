import XCTest
import SwiftData

/// Q77 / C49: Tuur, 2026-09-30, prod Mac — "when I uploaded the voice memos they didn't auto
/// transcribe. I had to process them with right mouse button, which worked flaky."
///
/// (b) An import floors to 0.1 (a request to process) but `ArrivalPath.run` only transcribed a
/// RECORDING, so an imported voice memo sat wordless until someone pressed Process.
@MainActor
final class MacImportAutoProcessTests: XCTestCase {

    private func pipelineContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: PipelineFile.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func fakeMemo(in dir: URL, named name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(repeating: 0, count: 4096).write(to: url)
        return url
    }

    /// Two synthetic voice memos come in through the Import seam; both are handed to
    /// transcription with no Process call anywhere in the test.
    func testTwoImportedVoiceMemosAreQueuedForTranscriptionWithoutProcess() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let ctx = try pipelineContext()

        var imported: [String] = []
        var hooks = ArrivalPath.Hooks.inert
        hooks.transcribeImport = { imported += $0 }

        let created = try await ArrivalPath.run(
            urls: [try fakeMemo(in: work, named: "Memo one 2026-09-01.m4a"),
                   try fakeMemo(in: work, named: "Memo two 2026-09-02.m4a")],
            asRecording: false, into: ctx, cloudContext: nil, hooks: hooks,
            service: IngestService(outputDir: work.appendingPathComponent("out")))

        XCTAssertEqual(created.count, 2)
        XCTAssertEqual(Set(imported), Set(created.map(\.id)),
                       "an import is a request to process — it must enter the pipeline on its own")
        XCTAssertTrue(created.allSatisfy { !$0.isLocalRecording }, "an import is not a recording")
    }

    /// The transcription request lands AFTER the rows exist and were handed back, so the list
    /// shows them at once and only the words arrive later.
    func testImportRowsAreHandedBackBeforeTheirTranscriptionIsRequested() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let ctx = try pipelineContext()
        var order: [String] = []
        var hooks = ArrivalPath.Hooks.inert
        hooks.transcribeImport = { _ in order.append("transcribe") }
        _ = try await ArrivalPath.run(
            urls: [try fakeMemo(in: work, named: "a.m4a")], asRecording: false, into: ctx,
            cloudContext: nil, hooks: hooks,
            service: IngestService(outputDir: work.appendingPathComponent("out")),
            onCreated: { _ in order.append("created") })
        XCTAssertEqual(order, ["created", "transcribe"])
    }

    /// A markdown note arrives already "transcribed" and a recording has its own hook — neither
    /// is sent through the import transcription.
    func testOnlyImportedAudioIsSentToImportTranscription() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let ctx = try pipelineContext()
        let note = work.appendingPathComponent("Plan.md")
        try "hello".write(to: note, atomically: true, encoding: .utf8)
        var imported: [String] = []
        var hooks = ArrivalPath.Hooks.inert
        hooks.transcribeImport = { imported += $0 }
        let created = try await ArrivalPath.run(
            urls: [note, try fakeMemo(in: work, named: "b.m4a")], asRecording: false, into: ctx,
            cloudContext: nil, hooks: hooks,
            service: IngestService(outputDir: work.appendingPathComponent("out")))
        let audio = created.filter { $0.sourceType == .audio }
        XCTAssertEqual(audio.count, 1)
        XCTAssertEqual(imported, audio.map(\.id))

        var recImported: [String] = []
        var recHooks = ArrivalPath.Hooks.inert
        recHooks.transcribeImport = { recImported += $0 }
        _ = try await ArrivalPath.run(
            urls: [try fakeMemo(in: work, named: "c.m4a")], asRecording: true, into: try pipelineContext(),
            cloudContext: nil, hooks: recHooks,
            service: IngestService(outputDir: work.appendingPathComponent("out2")))
        XCTAssertTrue(recImported.isEmpty, "a recording goes through `transcribe`, not the import hook")
    }
}
