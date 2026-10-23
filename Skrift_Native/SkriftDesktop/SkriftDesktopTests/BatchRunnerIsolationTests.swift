import XCTest
import Foundation

/// Q505: `BatchRunner` mutates `PipelineFile` rows owned by a main-actor `ModelContext`, so its own
/// code must run on the main actor wherever it is called from. As a plain nonisolated struct its
/// `async run` ran on the global executor (Swift 5.9 mode, SE-0338) and wrote SwiftData rows off
/// their context's thread: the SwiftData-dealloc crashes in the copy-edit corpus harnesses (5 of 100
/// stressed runs before, 0 of 90 after). This class is deliberately NOT `@MainActor`: it calls
/// `run` from the global executor, the way a nonisolated caller would.
final class BatchRunnerIsolationTests: XCTestCase {

    /// Words for any file; the run never reads it.
    private struct StubTranscriber: Transcribing {
        func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
            TranscriptionResult(text: "Kiln loaded again.", confidence: 0.9, durationMs: 0,
                                wordTimings: [WordTiming(word: "Kiln", start: 0, end: 0.4)], markersInjected: false)
        }
    }

    private struct StubEnhancer: Enhancing {
        func copyEdit(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { t }
        func title(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "T" }
        func summary(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "" }
    }

    /// Records which thread `run`'s own body was on: `cancelCheck` is called synchronously
    /// inside `run` (the Split-speakers path), so it executes on `run`'s executor.
    private final class Probe: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [Bool] = []
        func record() { lock.lock(); seen.append(Thread.isMainThread); lock.unlock() }
        var observations: [Bool] { lock.lock(); defer { lock.unlock() }; return seen }
    }

    private func runSplit(_ probe: Probe) async throws {
        let (runner, pf) = await MainActor.run {
            let pf = PipelineFile(id: UUID().uuidString, filename: "memo.m4a", path: "/tmp/x.m4a", size: 0, sourceType: .audio)
            pf.transcript = "Before."
            pf.transcribeStatus = .done
            return (BatchRunner(transcriber: StubTranscriber(), enhancer: StubEnhancer(),
                                settings: .default, people: [], tagWhitelist: []), pf)
        }
        do {
            try await runner.run(pf, audioURL: URL(fileURLWithPath: "/tmp/x.m4a"), retranscribe: true,
                                 requireSplit: true, cancelCheck: { probe.record(); return false })
            XCTFail("no diarizer: the split must refuse with one voice")
        } catch let e as BatchRunnerError {
            XCTAssertEqual(e, .oneVoice)
        }
    }

    func testRunExecutesOnTheMainThreadWhenCalledOffTheMainActor() async throws {
        XCTAssertFalse(Thread.isMainThread, "precondition: this caller is off the main actor")
        let probe = Probe()
        try await runSplit(probe)
        XCTAssertFalse(probe.observations.isEmpty, "the probe ran inside run")
        XCTAssertEqual(Set(probe.observations), [true], "BatchRunner.run's own code ran off the main thread")
    }

    func testRunExecutesOnTheMainThreadFromADetachedTask() async throws {
        let probe = Probe()
        try await Task.detached { try await self.runSplit(probe) }.value
        XCTAssertEqual(Set(probe.observations), [true])
    }
}
