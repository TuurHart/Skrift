import XCTest
import Foundation

/// Q426 (C2, C28, C38, C39): the Mac's Process and Redo call copy-edit v2 through the
/// `Enhancing` seam, telling it typed from spoken; a stale local prompt copy in
/// `user_settings.json` is migrated away once, at first launch. MLX-free: the live engine
/// (`EnhancementService`) is app-only, so these drive the seam and the shared v2 pieces it calls.
final class CopyEditV2SwapTests: XCTestCase {

    // MARK: - typed vs spoken reaches the engine

    final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [Bool] = []
        func add(_ b: Bool) { lock.lock(); list.append(b); lock.unlock() }
        var all: [Bool] { lock.lock(); defer { lock.unlock() }; return list }
    }

    private struct SpokenRecorder: Enhancing {
        let seen: Seen
        func copyEdit(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
            XCTFail("the batch path must ask with spoken:"); return t
        }
        func copyEdit(_ t: String, spoken: Bool, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
            seen.add(spoken); return t
        }
        func title(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "T" }
        func summary(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "" }
    }

    /// A stub with only the old three methods still works: the spoken variant defaults to it.
    private struct OldStub: Enhancing {
        func copyEdit(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { t.uppercased() }
        func title(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "T" }
        func summary(_ t: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String { "" }
    }

    private struct NeverTranscriber: Transcribing {
        struct Asked: Error {}
        func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult { throw Asked() }
    }

    private func row(_ type: SourceType, _ text: String) -> PipelineFile {
        let pf = PipelineFile(id: UUID().uuidString, filename: "n", path: "", size: 0, sourceType: type)
        pf.transcript = text
        pf.transcribeStatus = .done
        return pf
    }

    @MainActor
    func testTheBatchPathTellsTheEngineTypedFromSpoken() async throws {
        let seen = Seen()
        let runner = BatchRunner(transcriber: NeverTranscriber(), enhancer: SpokenRecorder(seen: seen),
                                 settings: .default, people: [], tagWhitelist: [])
        try await runner.run(row(.audio, "A spoken memo about the kiln."), audioURL: nil)
        try await runner.run(row(.note, "A typed note about the kiln."), audioURL: nil)
        XCTAssertEqual(seen.all, [true, false])
    }

    func testAnOldStubAnswersTheSpokenVariant() async throws {
        let out = try await OldStub().copyEdit("abc", spoken: false, prompts: .init(), modelRepo: "m")
        XCTAssertEqual(out, "ABC")
    }

    // MARK: - the title/summary turn both polishers share

    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [String] = []
        func add(_ s: String) { lock.lock(); list.append(s); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return list }
    }

    func testTheTurnReadsProseAndTrims() async throws {
        let calls = Calls()
        let out = try await CopyEditV2.turn(prompt: "P", body: "See [[Lotte Vos|Lotte]] [[img_002]] today.", maxTokens: 64) { _, t, _ in
            calls.add(t); return "  Seeing Lotte \n"
        }
        XCTAssertEqual(out, "Seeing Lotte")
        XCTAssertEqual(calls.all, ["See Lotte today."])
    }

    func testNoWordsNoCall() async throws {
        let calls = Calls()
        let out = try await CopyEditV2.turn(prompt: "P", body: "[[img_001]]\n\n", maxTokens: 256) { _, t, _ in
            calls.add(t); return "invented"
        }
        XCTAssertEqual(out, "")
        XCTAssertTrue(calls.all.isEmpty)
    }

    // MARK: - C39: a stale local prompt copy is migrated away once

    func testANeverEditedStaleCopyIsResetToTodaysDefault() throws {
        var s = AppSettings.default
        s.prompts.copyEdit = "An old default copy-edit prompt from an earlier build."
        s.prompts.title = "An old title prompt."
        XCTAssertNil(s.promptsModifiedAt)
        let (m, reset) = try XCTUnwrap(s.migratingStalePrompts())
        XCTAssertEqual(m.prompts, AppSettings.Prompts(), "the ONE source wins: PolishPrompts")
        XCTAssertEqual(m.prompts.copyEdit, PolishPrompts.copyEdit)
        XCTAssertEqual(reset, ["copy-edit", "title"])
        XCTAssertEqual(m.promptsSchema, AppSettings.currentPromptsSchema)
        XCTAssertNil(m.migratingStalePrompts(), "once: a migrated file is left alone")
    }

    func testAnEditedPromptIsHisOverrideAndStays() throws {
        var s = AppSettings.default
        s.prompts.copyEdit = "Keep my Dutch exactly as I said it."
        s.promptsModifiedAt = Date(timeIntervalSince1970: 1_790_000_000)
        let (m, reset) = try XCTUnwrap(s.migratingStalePrompts())
        XCTAssertEqual(m.prompts.copyEdit, "Keep my Dutch exactly as I said it.")
        XCTAssertEqual(reset, [])
        XCTAssertEqual(m.promptsSchema, AppSettings.currentPromptsSchema)
    }

    func testTheMigrationIsSavedAndNoSecondPromptStringRemains() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("c39_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SettingsStore(fileURL: dir.appendingPathComponent("user_settings.json"))
        var s = AppSettings.default
        s.prompts.summary = "Stale summary prompt."
        store.save(s)

        store.migrateStalePromptsOnce()
        let json = try String(contentsOf: dir.appendingPathComponent("user_settings.json"), encoding: .utf8)
        XCTAssertFalse(json.contains("Stale summary prompt."), "no second prompt string after migration")
        XCTAssertEqual(store.load().prompts, AppSettings.Prompts())
        XCTAssertEqual(store.load().promptsSchema, AppSettings.currentPromptsSchema)
    }
}
