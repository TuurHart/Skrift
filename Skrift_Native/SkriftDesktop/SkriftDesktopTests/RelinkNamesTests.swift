import XCTest
import Foundation

/// Q207: `PipelineFile.relinkNames` (the one relink block) and `bestBodyText` (the one body rule).
final class RelinkNamesTests: XCTestCase {

    private let nick = Person(canonical: "[[Nick Jansen]]", aliases: ["Nick"], short: "Nick",
                              lastModifiedAt: "2026-01-01T00:00:00.000Z")

    func testMonologueLinksTheFirstMentionAndWritesSanitised() {
        let pf = PipelineFile(id: UUID().uuidString, filename: "a.m4a")
        pf.relinkNames(working: "I met Nick today.", isConversation: false, people: [nick])
        XCTAssertTrue((pf.sanitised ?? "").contains("[[Nick Jansen]]"), pf.sanitised ?? "nil")
        XCTAssertNil(pf.ambiguousNames, "empty means nil")
    }

    func testAlreadyUnlinkedNameStaysPlain() {
        let pf = PipelineFile(id: UUID().uuidString, filename: "a.m4a")
        pf.unlinkedNames = ["Nick Jansen"]
        pf.relinkNames(working: "I met Nick today.", isConversation: false, people: [nick])
        XCTAssertFalse((pf.sanitised ?? "").contains("[["), pf.sanitised ?? "nil")
    }

    func testConversationFlagRoutesToTheTurnLinker() {
        let pf = PipelineFile(id: UUID().uuidString, filename: "a.m4a")
        let text = "**Nick:** Hello there.\n\n**Speaker 2:** Hi."
        pf.relinkNames(working: text, isConversation: true, people: [nick])
        XCTAssertTrue((pf.sanitised ?? "").contains("[[Nick Jansen]]"), "matched speaker links in its header: \(pf.sanitised ?? "nil")")
    }

    func testBestBodyTextPrecedence() {
        let pf = PipelineFile(id: UUID().uuidString, filename: "a.m4a")
        XCTAssertEqual(pf.bestBodyText, "")
        pf.transcript = "raw"
        XCTAssertEqual(pf.bestBodyText, "raw")
        pf.enhancedCopyedit = "edited"
        XCTAssertEqual(pf.bestBodyText, "edited")
        pf.sanitised = "linked"
        XCTAssertEqual(pf.bestBodyText, "linked")
    }
}
