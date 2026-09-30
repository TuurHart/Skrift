import XCTest
import SwiftData

/// The arrival path — and specifically the two things a CAPTURE does that an IMPORT does not.
///
/// Both were built on 2026-07-28 and shipped without ever being seen working: they lived
/// inside a SwiftUI view, reachable only through a microphone that had stopped being granted.
/// The pieces each had unit tests (`MacMemoAuthorSignificanceTests`, `BatchRunnerTests`); what
/// nothing covered was whether the Record button actually CALLS them, which is exactly the
/// kind of gap a broken mic hides indefinitely.
@MainActor
final class ArrivalPathTests: XCTestCase {

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

    /// A stand-in for a take. Ingest only needs a real file with a known extension — the
    /// bytes never reach an audio engine on this path.
    private func fakeTake(in dir: URL, named name: String = "memo_TEST.m4a") throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(repeating: 0, count: 4096).write(to: url)
        return url
    }

    // MARK: - a capture

    /// The whole recording contract in one run: the note exists, it is UNRATED on the synced
    /// Memo, and its words were asked for immediately — without anyone pressing Process.
    func testARecordingArrivesUnratedAndIsTranscribedAtOnce() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let ctx = try pipelineContext()
        let cloud = try cloudContext()

        var transcribed: [String] = []
        var hooks = ArrivalPath.Hooks.inert
        hooks.transcribe = { transcribed = $0 }

        let created = try await ArrivalPath.run(
            urls: [try fakeTake(in: work)], asRecording: true, into: ctx, cloudContext: cloud,
            hooks: hooks, service: IngestService(outputDir: work.appendingPathComponent("out")))

        let pf = try XCTUnwrap(created.first)
        XCTAssertEqual(transcribed, [pf.id],
                       "a take must get its words on stop — process() skips unrated notes, so nothing else ever would")

        let memos = try cloud.fetch(FetchDescriptor<Memo>())
        XCTAssertEqual(memos.count, 1, "a capture authors its Memo now, not at the next sweep")
        XCTAssertEqual(memos.first?.significance, 0,
                       "the rating is consent — capturing a thought isn't judging it")
    }

    /// `author` runs BEFORE anything can floor the rating. The ordering is the mechanism (it
    /// is idempotent, so whoever gets there first wins), so pin that the row is already in the
    /// cloud store by the time transcription is asked for.
    func testTheUnratedMemoExistsBeforeTranscriptionIsRequested() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let ctx = try pipelineContext()
        let cloud = try cloudContext()

        var memosAtTranscribeTime = -1
        var hooks = ArrivalPath.Hooks.inert
        hooks.transcribe = { _ in
            memosAtTranscribeTime = (try? cloud.fetchCount(FetchDescriptor<Memo>())) ?? -1
        }

        _ = try await ArrivalPath.run(
            urls: [try fakeTake(in: work)], asRecording: true, into: ctx, cloudContext: cloud,
            hooks: hooks, service: IngestService(outputDir: work.appendingPathComponent("out")))

        XCTAssertEqual(memosAtTranscribeTime, 1)
    }

    /// The row must be selectable the instant it exists — a note that only appears once its
    /// words do makes stopping a recording look like it did nothing.
    func testTheRowIsHandedBackBeforeTranscriptionRuns() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let ctx = try pipelineContext()

        var order: [String] = []
        var hooks = ArrivalPath.Hooks.inert
        hooks.transcribe = { _ in order.append("transcribe") }

        _ = try await ArrivalPath.run(
            urls: [try fakeTake(in: work)], asRecording: true, into: ctx, cloudContext: nil,
            hooks: hooks, service: IngestService(outputDir: work.appendingPathComponent("out")),
            onCreated: { _ in order.append("created") })

        XCTAssertEqual(order, ["created", "transcribe"])
    }

    /// A take that reached disk is never lost to a missing CloudKit container — the file is
    /// already safe and the sweep picks it up later.
    func testACaptureWithNoCloudContainerStillLandsAndTranscribes() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let ctx = try pipelineContext()

        var transcribed: [String] = []
        var hooks = ArrivalPath.Hooks.inert
        hooks.transcribe = { transcribed = $0 }

        let created = try await ArrivalPath.run(
            urls: [try fakeTake(in: work)], asRecording: true, into: ctx, cloudContext: nil,
            hooks: hooks, service: IngestService(outputDir: work.appendingPathComponent("out")))

        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(transcribed.count, 1)
    }

    // MARK: - an import

    /// The other edge: an import arrives unrated too (D159) and never goes through the CAPTURE
    /// transcribe hook — its words come from `transcribeImport` (Q77, MacImportUnratedTests).
    func testAnImportIsNotTranscribedAsACaptureOnArrival() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let ctx = try pipelineContext()
        let cloud = try cloudContext()

        var transcribeCalls = 0
        var hooks = ArrivalPath.Hooks.inert
        hooks.transcribe = { _ in transcribeCalls += 1 }

        _ = try await ArrivalPath.run(
            urls: [try fakeTake(in: work, named: "some import.m4a")], asRecording: false,
            into: ctx, cloudContext: cloud,
            hooks: hooks, service: IngestService(outputDir: work.appendingPathComponent("out")))

        XCTAssertEqual(transcribeCalls, 0, "an import has its own transcribe hook; the capture one is not called")
        XCTAssertTrue(try cloud.fetch(FetchDescriptor<Memo>()).isEmpty,
                      "an import's Memo is the reconcile sweep's job (authored unrated, D159)")
    }

    // MARK: - shared behaviour

    /// The recording date comes out of the audio, not the filesystem — a copy is not a
    /// re-recording. Applies to both doors.
    func testTheRecordingDateIsBackfilledFromTheAudio() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let ctx = try pipelineContext()

        let spoken = Date(timeIntervalSince1970: 1_700_000_000)
        var hooks = ArrivalPath.Hooks.inert
        hooks.recordingDate = { _ in spoken }

        let created = try await ArrivalPath.run(
            urls: [try fakeTake(in: work)], asRecording: true, into: ctx, cloudContext: nil,
            hooks: hooks, service: IngestService(outputDir: work.appendingPathComponent("out")))

        XCTAssertEqual(created.first?.uploadedAt, spoken)
    }

    func testTheReconcileSweepIsKickedForBothDoors() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        for asRecording in [true, false] {
            let ctx = try pipelineContext()
            var kicks = 0
            var hooks = ArrivalPath.Hooks.inert
            hooks.reconcileSoon = { kicks += 1 }

            _ = try await ArrivalPath.run(
                urls: [try fakeTake(in: work, named: "\(UUID().uuidString).m4a")],
                asRecording: asRecording, into: ctx, cloudContext: nil,
                hooks: hooks, service: IngestService(outputDir: work.appendingPathComponent("out")))

            XCTAssertEqual(kicks, 1, "asRecording: \(asRecording)")
        }
    }

    /// The flag must be on the row and SAVED before anything else runs — it is what makes the
    /// reconcile sweep agree with us about the rating when it gets there first.
    func testACaptureStampsTheRowBeforeHandingItBack() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let ctx = try pipelineContext()

        var stampedAtHandback: Bool?
        _ = try await ArrivalPath.run(
            urls: [try fakeTake(in: work)], asRecording: true, into: ctx, cloudContext: nil,
            hooks: .inert, service: IngestService(outputDir: work.appendingPathComponent("out")),
            onCreated: { stampedAtHandback = $0.first?.isLocalRecording })

        XCTAssertEqual(stampedAtHandback, true,
                       "stamped after the sweep could already have seen the row is stamped too late")
    }

    func testAnImportIsNotStampedAsARecording() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let ctx = try pipelineContext()
        let created = try await ArrivalPath.run(
            urls: [try fakeTake(in: work, named: "dropped.m4a")], asRecording: false, into: ctx,
            cloudContext: nil, hooks: .inert,
            service: IngestService(outputDir: work.appendingPathComponent("out")))
        XCTAssertEqual(created.first?.isLocalRecording, false)
    }

    func testNoURLsIsANoOp() async throws {
        let ctx = try pipelineContext()
        var transcribeCalls = 0
        var hooks = ArrivalPath.Hooks.inert
        hooks.transcribe = { _ in transcribeCalls += 1 }

        let created = try await ArrivalPath.run(urls: [], asRecording: true, into: ctx,
                                                  cloudContext: nil, hooks: hooks)
        XCTAssertTrue(created.isEmpty)
        XCTAssertEqual(transcribeCalls, 0)
    }
}
