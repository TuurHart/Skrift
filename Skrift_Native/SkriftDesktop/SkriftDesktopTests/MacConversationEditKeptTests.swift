import XCTest
import SwiftData

/// Q508 (C261, C47): a Mac edit to a CONVERSATION note survives every re-derivation, like a
/// monologue edit does since Q489: a phone tag edit's recompile, a roster re-link, the open note's
/// refresh and the Redo write-back. Speaker turns keep their headers; the edit is de-linked turn
/// by turn into the copy-edit, the same text the cloud gets.
@MainActor
final class MacConversationEditKeptTests: XCTestCase {

    private let bruno = Person(canonical: "[[Bruno Costa]]", aliases: ["Bruno"], short: "Bruno",
                               lastModifiedAt: "2026-09-25T09:00:00Z")
    private let renamed = Person(canonical: "[[Bruno Almeida]]", aliases: ["Bruno"], short: "Bruno",
                                 lastModifiedAt: "2026-09-26T09:00:00Z")
    private let lotte = Person(canonical: "[[Lotte Vos]]", aliases: ["Lotte"], short: "Lotte",
                               lastModifiedAt: "2026-09-01T09:00:00Z")

    /// The diarized transcript (a conversation copy-edit IS the transcript, `BatchRunner`).
    private let turns = "**Bruno:** We fire the platters on Thursday.\n\n**Lotte:** The kiln is booked then."
    private let editedTurns = "**Bruno:** We fire the platters and the shelves on Thursday.\n\n**Lotte:** The kiln is booked then."

    private func processedConversation() -> PipelineFile {
        let pf = PipelineFile(id: UUID().uuidString, filename: "memo.m4a", sourceType: .audio)
        pf.transcript = turns
        pf.enhancedCopyedit = turns
        pf.enhancedTitle = "Kiln week"
        pf.enhanceStatus = .done
        MemoCloudUpdate.resanitiseAndCompile(pf, people: [bruno, lotte], author: "Tuur")
        XCTAssertTrue(pf.sanitised?.contains("**[[Bruno Costa]]:**") == true, "a linked header: \(pf.sanitised ?? "")")
        return pf
    }

    /// The review editor's body binding: his edit lands in `sanitised`, the linked turns.
    private func typeOnTheMac(_ pf: PipelineFile) {
        pf.sanitised = Sanitiser.processConversation(text: editedTurns, people: [bruno, lotte]).sanitised
    }

    private func cloud(for pf: PipelineFile) throws -> ModelContext {
        let c = try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self, MemoEditHead.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(c)
        ctx.insert(Memo(id: try XCTUnwrap(UUID(uuidString: pf.id)), audioFilename: pf.filename, recordedAt: Date(),
                        transcript: pf.transcript, transcriptStatus: .done, transcriptConfidence: 0.9,
                        significance: 0.6))
        try ctx.save()
        return ctx
    }

    private func cloudCopy(_ pf: PipelineFile, _ ctx: ModelContext) throws -> String? {
        let id = try XCTUnwrap(UUID(uuidString: pf.id))
        return try ctx.fetch(FetchDescriptor<MemoEnhancement>(predicate: #Predicate { $0.memoID == id })).first?.copyedit
    }

    private func assertKept(_ pf: PipelineFile, header: String, file: StaticString = #filePath, line: UInt = #line) {
        let s = pf.sanitised ?? ""
        XCTAssertTrue(s.contains("and the shelves"), "his edit in sanitised: \(s)", file: file, line: line)
        XCTAssertTrue(pf.compiledText?.contains("and the shelves") == true, "and in the compile", file: file, line: line)
        XCTAssertTrue(s.hasPrefix("**\(header):**"), "the turns keep their headers: \(s)", file: file, line: line)
        XCTAssertTrue(s.contains("**[[Lotte Vos]]:** The kiln is booked then."), "the other turn intact: \(s)", file: file, line: line)
        XCTAssertTrue(pf.enhancedCopyedit?.contains("**Bruno:** We fire the platters and the shelves") == true,
                      "de-linked per turn into the copy-edit: \(pf.enhancedCopyedit ?? "nil")", file: file, line: line)
    }

    // MARK: - the four paths

    func testARosterRenameKeepsHisConversationEdit() throws {
        let pf = processedConversation()
        let ctx = try cloud(for: pf)
        typeOnTheMac(pf)

        RosterRelink.relink([pf], linkedWith: [bruno, lotte], people: [renamed, lotte], author: "Tuur")

        assertKept(pf, header: "[[Bruno Almeida]]")
        try MacCloudWriteBack.upsert(for: pf, into: ctx, deviceID: "mac-test")
        XCTAssertTrue(try cloudCopy(pf, ctx)?.contains("and the shelves") == true, "the cloud copy is his edit")
    }

    func testAPhoneTagEditKeepsHisConversationEdit() throws {
        let pf = processedConversation()
        typeOnTheMac(pf)
        let m = Memo(id: try XCTUnwrap(UUID(uuidString: pf.id)), audioFilename: pf.filename, recordedAt: Date(),
                     transcript: pf.transcript, transcriptStatus: .done, transcriptConfidence: 0.9,
                     significance: 0.6)
        m.tags = ["studio"]

        XCTAssertTrue(MemoCloudUpdate.apply(memo: m, enhancement: nil, to: pf, people: [bruno, lotte],
                                            author: "Tuur", thisDeviceID: "mac-test"))

        XCTAssertEqual(pf.tags, ["studio"])
        assertKept(pf, header: "[[Bruno Costa]]")
    }

    func testTheOpenNoteKeepsHisConversationEditOnASyncedRename() {
        let center = NotificationCenter()
        var roster = [bruno, lotte]
        let refresh = OpenNoteRosterRefresh(center: center, people: { roster }, author: { "Tuur" })
        let pf = processedConversation()
        refresh.open(pf)
        typeOnTheMac(pf)

        roster = [renamed, lotte]
        center.post(name: .namesDidChangeFromSync, object: nil)

        XCTAssertEqual(refresh.refreshCount, 1)
        assertKept(pf, header: "[[Bruno Almeida]]")
    }

    func testARedoWriteBackSendsHisConversationEdit() throws {
        let pf = processedConversation()
        let ctx = try cloud(for: pf)
        typeOnTheMac(pf)

        MacEditRoundTrip.settle(pf, linkedWith: [bruno, lotte])
        try MacCloudWriteBack.upsert(for: pf, into: ctx, deviceID: "mac-test", passRan: true)

        let copy = try XCTUnwrap(try cloudCopy(pf, ctx))
        XCTAssertTrue(copy.contains("and the shelves"), copy)
        XCTAssertTrue(copy.hasPrefix("**Bruno:**"), "turns, de-linked: \(copy)")
    }

    // MARK: - nothing edited

    func testAnUneditedConversationKeepsItsTurnsByteForByte() {
        let pf = processedConversation()
        MacEditRoundTrip.settle(pf, linkedWith: [bruno, lotte])
        XCTAssertEqual(pf.enhancedCopyedit, turns, "no edit, so the copy-edit is not rewritten")
        RosterRelink.relink([pf], linkedWith: [bruno, lotte], people: [renamed, lotte], author: "Tuur")
        XCTAssertEqual(pf.enhancedCopyedit, turns)
        XCTAssertTrue(pf.sanitised?.hasPrefix("**[[Bruno Almeida]]:**") == true)
    }

    func testTheEditWriteBackSeesNoMoveOnAnUneditedConversation() {
        // `MacCloudEditSync.flush` compares through the turn linker too, so a title-only flush on
        // a diarized note is not counted as a words edit (C98).
        let pf = processedConversation()
        let trip = MacEditRoundTrip.compute(body: pf.sanitised ?? "", before: turns, people: [bruno, lotte],
                                            neverLink: [], namePicks: [:], conversation: true)
        XCTAssertFalse(trip.bodyMoved)
    }
}
