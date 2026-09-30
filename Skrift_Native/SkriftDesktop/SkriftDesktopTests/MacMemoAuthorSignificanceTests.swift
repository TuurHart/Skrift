import XCTest
import SwiftData

/// `MacMemoAuthor` never floors the rating (D159, 2026-09-30): an import authors unrated like a
/// recording. (Before D159 an import floored to 0.1.)
final class MacMemoAuthorSignificanceTests: XCTestCase {

    private func ctx() throws -> ModelContext {
        let c = try ModelContainer(for: Memo.self, MemoAsset.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                      cloudKitDatabase: .none))
        return ModelContext(c)
    }

    /// An IMPORT arrives unrated too (D159): adding a file is not judging it.
    func testImportStaysUnrated() throws {
        let c = try ctx()
        let pf = PipelineFile(id: UUID().uuidString, filename: "a.m4a", path: "", size: 1, sourceType: .audio)
        let memo = try MacMemoAuthor.author(for: pf, audioURL: nil, into: c)
        XCTAssertEqual(memo?.significance, 0)
    }

    /// A RECORDING does NOT. Capturing a thought is not judging it — under the unrated model
    /// the rating is consent, so a Mac take must arrive unrated exactly like a phone one.
    /// (Tuur, 2026-07-28, on the first real Mac recording: "it shouldn't be. Because it's an
    /// unrated note.")
    func testRecordingStaysUnrated() throws {
        let c = try ctx()
        let pf = PipelineFile(id: UUID().uuidString, filename: "memo_x.m4a", path: "", size: 1, sourceType: .audio)
        let memo = try MacMemoAuthor.author(for: pf, audioURL: nil, into: c)
        XCTAssertEqual(memo?.significance, 0, "a recording is unrated until it's judged")
    }

    /// An EXPLICIT rating passes through unchanged.
    func testAnExplicitRatingIsNeverOverwritten() throws {
        let c = try ctx()
        let pf = PipelineFile(id: UUID().uuidString, filename: "b.m4a", path: "", size: 1, sourceType: .audio)
        pf.significance = 0.7
        let memo = try MacMemoAuthor.author(for: pf, audioURL: nil, into: c)
        XCTAssertEqual(memo?.significance, 0.7)
    }
}
