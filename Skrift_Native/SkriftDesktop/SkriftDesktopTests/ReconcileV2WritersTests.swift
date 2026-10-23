import XCTest
import SwiftData
import Foundation

/// Q512: the v2 helpers the app calls instead of v1's `MacCloudWriteBack`, `MirroredNoteFields`
/// and `MemoCloudUpdate.resanitiseAndCompile` — the memo-id candidates (C186), the passive meta
/// push (C47: a nil rating never rides it) and the people/author recompile.
@MainActor
final class ReconcileV2WritersTests: XCTestCase {

    private var container: ModelContainer!
    private var cloud: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        cloud = ModelContext(container)
    }

    private func row(id: UUID, fileUUID: UUID, local: Bool) -> PipelineFile {
        let pf = PipelineFile(id: id.uuidString, filename: "memo_\(fileUUID.uuidString).m4a", sourceType: .audio)
        pf.isLocalRecording = local
        return pf
    }

    /// A phone row is named after its memo; a Mac recording's filename carries the recorder's
    /// UUID, so its row id comes first.
    func testCandidatesOrderByRowKind() {
        let id = UUID(), file = UUID()
        XCTAssertEqual(ReconcileV2.Writers.candidates(for: row(id: id, fileUUID: file, local: false)), [file, id])
        XCTAssertEqual(ReconcileV2.Writers.candidates(for: row(id: id, fileUUID: file, local: true)), [id, file])
        XCTAssertEqual(ReconcileV2.Writers.memoID(for: row(id: id, fileUUID: file, local: true)), id)
        XCTAssertEqual(ReconcileV2.Writers.candidates(for: row(id: id, fileUUID: id, local: false)), [id])
    }

    /// The store decides: a Mac recording authored before `isLocalRecording` existed still
    /// resolves to the memo under its row id.
    func testResolveAsksTheStore() throws {
        let id = UUID()
        cloud.insert(Memo(id: id, audioFilename: "", recordedAt: Date(), createdAt: Date()))
        try cloud.save()
        XCTAssertEqual(ReconcileV2.Writers.resolve(row(id: id, fileUUID: UUID(), local: false), in: cloud)?.id, id)
        XCTAssertNil(ReconcileV2.Writers.resolve(row(id: UUID(), fileUUID: UUID(), local: false), in: cloud))
    }

    /// Tags always mirror; a rating only when set, so a nil row never un-rates its memo.
    func testPushMetaNeverWritesANilRating() {
        let memo = Memo(id: UUID(), audioFilename: "", recordedAt: Date(), significance: 0.1, createdAt: Date())
        let pf = row(id: memo.id, fileUUID: memo.id, local: false)
        pf.tags = ["kiln"]
        pf.significance = nil
        XCTAssertTrue(ReconcileV2.Writers.pushMeta(pf, to: memo))
        XCTAssertEqual(memo.tags, ["kiln"])
        XCTAssertEqual(memo.significance, 0.1)
        XCTAssertFalse(ReconcileV2.Writers.pushMeta(pf, to: memo), "already mirrored: no change")
        pf.significance = 0.8
        XCTAssertTrue(ReconcileV2.Writers.pushMeta(pf, to: memo))
        XCTAssertEqual(memo.significance, 0.8)
    }

    /// The recompile the app's relink, append and batch paths call: links over the working body
    /// and compiles, no model.
    func testRecompileLinksAndCompiles() {
        let pf = row(id: UUID(), fileUUID: UUID(), local: false)
        pf.transcript = "Ate lunch with Mats today."
        let mats = Person(canonical: "[[Mats Berg]]", aliases: ["Mats"], short: "Mats",
                          lastModifiedAt: "2026-09-01T09:00:00Z")
        ReconcileV2.Reflect.recompile(pf, people: [mats], author: "A")
        XCTAssertEqual(pf.sanitiseStatus, .done)
        XCTAssertTrue(pf.sanitised?.contains("[[Mats Berg") ?? false, pf.sanitised ?? "nil")
        XCTAssertFalse((pf.compiledText ?? "").isEmpty)
    }
}
