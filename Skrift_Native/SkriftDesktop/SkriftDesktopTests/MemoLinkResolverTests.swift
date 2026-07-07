import XCTest
import SwiftData
import Foundation

/// The Mac side of memo↔memo link export (phone chunk 5 parity): the desktop
/// `Compiler.compile(file:)` shim supplies `CompilerInput.memoLinkResolver` from the
/// queue's own exported stems (`MemoLinkStems` over `VaultExporter.noteStem`), so
/// `[[memo:UUID|Title]]` leaves the Mac as a resolver-precise `[[<stem>|Title]]` —
/// not the title-snapshot fallback the Mac used to emit (nil resolver).
@MainActor
final class MemoLinkResolverTests: XCTestCase {

    private func memoryContext() throws -> ModelContext {
        let container = try ModelContainer(for: PipelineFile.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    func testCompileResolvesMemoLinkToTargetStem() throws {
        let ctx = try memoryContext()
        let targetID = UUID()

        let target = PipelineFile(id: targetID.uuidString, filename: "memo_b.m4a")
        target.enhancedTitle = "Target Note"
        ctx.insert(target)

        let source = PipelineFile(id: UUID().uuidString, filename: "memo_a.m4a")
        source.sanitised = "See [[memo:\(targetID.uuidString)|Old Snapshot]] for context."
        ctx.insert(source)
        try ctx.save()

        let md = Compiler.compile(file: source, author: "Tiuri")
        XCTAssertTrue(md.contains("[[Target Note|Old Snapshot]]"),
                      "link resolves to the TARGET's exported stem, keeping the display title")
        XCTAssertFalse(md.contains("memo:"), "raw syntax never reaches the vault")
    }

    func testCompileFallsBackToTitleWhenTargetUnknown() throws {
        let ctx = try memoryContext()
        let source = PipelineFile(id: UUID().uuidString, filename: "memo_a.m4a")
        source.sanitised = "See [[memo:\(UUID().uuidString)|Vanished Note]]."
        ctx.insert(source)
        try ctx.save()

        let md = Compiler.compile(file: source, author: "Tiuri")
        XCTAssertTrue(md.contains("[[Vanished Note]]"), "unknown target → readable title fallback")
        XCTAssertFalse(md.contains("memo:"))
    }
}
