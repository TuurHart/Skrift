import XCTest
import SwiftData
import Foundation

/// Q507 (same bug class as Q505): `IngestService` is a `Sendable` struct, and in Swift 5.9 mode its
/// async methods ran on the global executor, inserting `PipelineFile` rows into the CALLER'S
/// context (the Sidebar passes `mainContext`) from a background thread. Rows now enter only through
/// the `@MainActor` `insert(_:into:)`, while copies, merges and reads stay on detached tasks so a
/// big import never parks the main thread. Deliberately NOT `@MainActor`: the imports are called
/// from off the main actor, the way a nonisolated caller would.
final class IngestIsolationTests: XCTestCase {

    private final class Probe: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [(IngestService.ThreadProbeEvent, Bool)] = []
        func record(_ e: IngestService.ThreadProbeEvent, _ onMain: Bool) { lock.lock(); events.append((e, onMain)); lock.unlock() }
        func threads(_ e: IngestService.ThreadProbeEvent) -> [Bool] {
            lock.lock(); defer { lock.unlock() }
            return events.filter { $0.0 == e }.map(\.1)
        }
    }

    private var scratch: URL!
    private var container: ModelContainer!   // kept alive as long as its context
    private var probe: Probe!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("q507-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        container = try ModelContainer(for: PipelineFile.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let probe = Probe()
        self.probe = probe
        IngestService.threadProbe = { probe.record($0, $1) }
    }

    override func tearDownWithError() throws {
        IngestService.threadProbe = nil
        try? FileManager.default.removeItem(at: scratch)
    }

    private var corpus: URL { CorpusSeed.fixtureRoot(file: #filePath) }

    /// The import files, copied into the scratch drop folder under realistic names.
    private func drop(_ name: String, from fixture: String) throws -> URL {
        let url = scratch.appendingPathComponent("drop", isDirectory: true).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: corpus.appendingPathComponent(fixture), to: url)
        return url
    }

    private func importAll(_ urls: [URL]) async throws -> IngestService.IngestReport {
        let context = await MainActor.run { ModelContext(container) }   // like `mainContext`
        return try await IngestService(outputDir: scratch.appendingPathComponent("out"))
            .ingestReport(localURLs: urls, into: context)
    }

    private func assertInsertsOnMainAndFileWorkOff(_ label: String) {
        let inserts = probe.threads(.insert), files = probe.threads(.fileWork)
        XCTAssertFalse(inserts.isEmpty, "\(label): rows were inserted")
        XCTAssertEqual(Set(inserts), [true], "\(label): a row was inserted off the main thread")
        XCTAssertFalse(files.isEmpty, "\(label): file work ran")
        XCTAssertEqual(Set(files), [false], "\(label): file work ran ON the main thread (the old import freeze)")
    }

    func testEveryKindOfImportInsertsOnTheMainThread() async throws {
        XCTAssertFalse(Thread.isMainThread, "precondition: the caller is off the main actor")
        let audio = try drop("Kiln pricing 2026-09-20.m4a", from: "notes/028-voice-en-pricing-ramble/audio.m4a")
        let note = scratch.appendingPathComponent("drop/Glaze order.md")
        try "# Glaze order\n\nTwo kilos of celadon.".write(to: note, atomically: true, encoding: .utf8)
        let picture = try drop("IMG_0001.jpg", from: "notes/058-pic-three-spread/photo_001.jpg")

        for (label, urls) in [("audio", [audio]), ("note", [note]), ("picture", [picture]),
                              ("clip + picture", [audio, picture])] {
            let before = probe.threads(.insert).count
            let report = try await importAll(urls)
            XCTAssertFalse(report.created.isEmpty, "\(label): a note was created")
            XCTAssertGreaterThan(probe.threads(.insert).count, before, label)
        }
        assertInsertsOnMainAndFileWorkOff("all")
    }

    func testAnImportFromADetachedTaskStillInsertsOnMain() async throws {
        let audio = try drop("Voice 2026-09-21.m4a", from: "notes/028-voice-en-pricing-ramble/audio.m4a")
        let report = try await Task.detached { try await self.importAll([audio]) }.value
        XCTAssertEqual(report.created.count, 1)
        assertInsertsOnMainAndFileWorkOff("detached")
    }
}
