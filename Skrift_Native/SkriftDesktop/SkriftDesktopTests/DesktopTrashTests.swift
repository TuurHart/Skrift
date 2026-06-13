import XCTest
import SwiftData

@MainActor
final class DesktopTrashTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PipelineFile.self, configurations: config)
        return ModelContext(container)
    }

    /// A file with no working folder on disk (path empty) so deleteForever's
    /// folder-trash is a no-op — keeps the test filesystem-free.
    private func makeFile(_ id: String) -> PipelineFile {
        PipelineFile(id: id, filename: "\(id).m4a", path: "", size: 0, sourceType: .audio)
    }

    func testSoftDeleteSetsFlagAndRestoreClearsIt() throws {
        let ctx = try makeContext()
        let f = makeFile("a"); ctx.insert(f)

        DesktopTrash.softDelete([f], in: ctx)
        XCTAssertNotNil(f.deletedAt, "soft-delete flags the file")

        DesktopTrash.restore([f], in: ctx)
        XCTAssertNil(f.deletedAt, "restore clears it")
    }

    func testSoftDeleteIsIdempotentOnDate() throws {
        let ctx = try makeContext()
        let f = makeFile("a"); ctx.insert(f)
        let firstDate = Date(timeIntervalSince1970: 1_000_000)
        DesktopTrash.softDelete([f], at: firstDate, in: ctx)
        DesktopTrash.softDelete([f], at: Date(), in: ctx)   // second call must NOT bump the clock
        XCTAssertEqual(f.deletedAt, firstDate, "re-deleting keeps the original trash time (countdown stable)")
    }

    func testPurgeRemovesOnlyExpired() throws {
        let ctx = try makeContext()
        let fresh = makeFile("fresh"); ctx.insert(fresh)
        let old = makeFile("old"); ctx.insert(old)
        let now = Date()
        DesktopTrash.softDelete([fresh], at: now.addingTimeInterval(-3 * 86_400), in: ctx)   // 3 days
        DesktopTrash.softDelete([old], at: now.addingTimeInterval(-15 * 86_400), in: ctx)     // 15 days > 14

        let purged = DesktopTrash.purgeExpired(now: now, in: ctx)
        XCTAssertEqual(purged, 1)
        let ids = ((try? ctx.fetch(FetchDescriptor<PipelineFile>())) ?? []).map(\.id)
        XCTAssertEqual(ids, ["fresh"], "the 15-day-old file is gone; the 3-day-old one survives")
    }

    func testPurgeIgnoresLiveFiles() throws {
        let ctx = try makeContext()
        let live = makeFile("live"); ctx.insert(live)   // never deleted
        XCTAssertEqual(DesktopTrash.purgeExpired(in: ctx), 0)
        XCTAssertNil(live.deletedAt)
    }

    func testDaysRemainingCountdown() {
        let f = makeFile("a")
        f.deletedAt = Date(timeIntervalSinceNow: -2 * 86_400)   // 2 days ago
        XCTAssertEqual(f.trashDaysRemaining(), DesktopTrashPolicy.retentionDays - 2)
        f.deletedAt = Date(timeIntervalSinceNow: -100 * 86_400) // long expired
        XCTAssertEqual(f.trashDaysRemaining(), 0, "never negative")
    }
}
