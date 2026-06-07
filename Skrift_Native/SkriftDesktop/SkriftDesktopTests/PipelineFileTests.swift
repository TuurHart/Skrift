import XCTest
import SwiftData
import Foundation

final class PipelineFileTests: XCTestCase {

    /// Insert → save → fresh fetch. The fetch forces a SwiftData read-back, which
    /// is exactly where raw Codable-struct attributes trap — so this also guards
    /// the steps/ambiguousNames accessor design.
    func testInsertFetchAndCodableAccessorsSurviveReadBack() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PipelineFile.self, configurations: config)
        let ctx = ModelContext(container)

        let f = PipelineFile(id: "memo-1", filename: "memo.m4a", path: "/tmp/memo.m4a", size: 42, sourceType: .audio)
        f.transcript = "hello world"
        f.steps.transcribe = .done
        f.steps.enhance = .processing
        f.ambiguousNames = [
            AmbiguousOccurrence(
                alias: "Nick", offset: 0, length: 4, contextBefore: "", contextAfter: " said",
                candidates: [
                    NameCandidate(id: "1", canonical: "[[Nick A]]", short: "Nick"),
                    NameCandidate(id: "2", canonical: "[[Nick B]]", short: "Nick"),
                ]
            )
        ]
        f.tags = ["work", "ideas"]
        ctx.insert(f)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<PipelineFile>())
        XCTAssertEqual(fetched.count, 1)
        let g = try XCTUnwrap(fetched.first)
        XCTAssertEqual(g.filename, "memo.m4a")
        XCTAssertEqual(g.steps.transcribe, .done)
        XCTAssertEqual(g.steps.enhance, .processing)
        XCTAssertEqual(g.steps.sanitise, .pending)         // default preserved
        XCTAssertEqual(g.ambiguousNames?.count, 1)
        XCTAssertEqual(g.ambiguousNames?.first?.candidates.count, 2)
        XCTAssertEqual(g.tags, ["work", "ideas"])
    }
}
