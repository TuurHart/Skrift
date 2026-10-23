import XCTest
import SwiftData
import Foundation

/// Q491 (C284, D12): the vault frontmatter carries `editedAt` — the note's last content edit,
/// local time like `date:` — right after `date:`, written by the ONE shared compiler for both
/// exporters. Never edited → `editedAt:` empty. The portfolio profile keeps C130's key list, so
/// it has no `editedAt`.
final class EditedAtFrontmatterTests: XCTestCase {

    private let edited = ISO8601DateFormatter().date(from: "2026-09-13T20:00:00Z")!

    private func input(editedAt: Date?) -> CompilerInput {
        var i = CompilerInput(filename: "memo.m4a", transcript: "Kiln loaded again.", enhancedTitle: "Kiln",
                              rawRecordedAt: "2026-09-12T18:00:00Z")
        i.editedAt = editedAt
        return i
    }

    private func frontmatter(_ md: String) -> [String] {
        let lines = md.components(separatedBy: "\n")
        let close = lines.dropFirst().firstIndex(of: "---") ?? lines.count
        return Array(lines[1..<close])
    }

    func testEditedAtSitsRightAfterDateInLocalTime() {
        let fm = frontmatter(Compiler.compile(input(editedAt: edited), author: "Tiuri"))
        let keys = fm.compactMap { $0.split(separator: ":").first.map(String.init) }
        let date = try? XCTUnwrap(keys.firstIndex(of: "date"))
        XCTAssertEqual(keys.firstIndex(of: "editedAt"), date.map { $0 + 1 }, "stable order: title, date, editedAt, author")
        XCTAssertEqual(keys.firstIndex(of: "author"), date.map { $0 + 2 })
        XCTAssertTrue(fm.contains("editedAt: \(ExportNaming.localDateTime(edited))"), fm.joined(separator: "\n"))
        XCTAssertEqual(ExportNaming.localDateTime(edited, timeZone: TimeZone(identifier: "Europe/Lisbon")!),
                       "2026-09-13T21:00:00", "local wall time, to the second")
    }

    func testNeverEditedWritesTheKeyEmpty() {
        let fm = frontmatter(Compiler.compile(input(editedAt: nil), author: "Tiuri"))
        XCTAssertTrue(fm.contains("editedAt:"), fm.joined(separator: "\n"))
    }

    func testThePortfolioProfileHasNoEditedAt() {
        var i = input(editedAt: edited)
        i.destination = .portfolio
        let fm = frontmatter(Compiler.compile(i, author: "Tiuri", profile: .portfolio))
        XCTAssertFalse(fm.contains { $0.hasPrefix("editedAt") }, "C130: the portfolio's own key list")
    }

    func testTheSameNoteWritesTheSameEditedAtOnPhoneAndMac() throws {
        // The phone path: the shared builder over the memo's `editedAt`.
        let phone = CompilerInput.make(filename: "memo", raw: "Kiln loaded again.", copyedit: nil, title: "Kiln",
                                       summary: nil, tags: [], significance: 0.5, sourceType: .audio,
                                       mediaSource: nil, metadata: nil, sharedContent: nil,
                                       rawRecordedAt: "2026-09-12T18:00:00Z", editedAt: edited,
                                       destination: .personal, spoken: true)
        // The Mac path: the sweep mirrors `Memo.editedAt` onto the row, the row compiles.
        let id = UUID()
        let memo = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a")
        memo.editedAt = edited
        let pf = PipelineFile(id: id.uuidString, filename: "memo_\(id.uuidString).m4a", sourceType: .audio)
        let field = try XCTUnwrap(MirroredNoteFields.all.first { $0.name == "editedAt" })
        XCTAssertTrue(field.pull(memo, pf))
        XCTAssertFalse(field.pull(memo, pf), "idempotent")
        XCTAssertEqual(pf.memoEditedAt, edited)
        let line = { (md: String) in md.components(separatedBy: "\n").first { $0.hasPrefix("editedAt") } }
        XCTAssertEqual(line(Compiler.compile(pf.compilerInput, author: "Tiuri")),
                       line(Compiler.compile(phone, author: "Tiuri")))
        XCTAssertEqual(line(Compiler.compile(phone, author: "Tiuri")), "editedAt: \(ExportNaming.localDateTime(edited))")
    }
}
