import XCTest
@testable import SkriftMobile

/// Q464 / C123 / D37: the share sheet's "From" row. The name rides the capture inbox entry
/// (`senderName`), and the drain writes it into the note as a person mention: linked by the
/// shared `Sanitiser` when the name is on the roster (so it reaches `people:`), plain otherwise.
final class ShareSheetSenderTests: XCTestCase {

    private let marta = Person(canonical: "[[Marta Silva]]", aliases: ["Marta"],
                               lastModifiedAt: "2026-10-01T00:00:00Z")

    @MainActor
    private func cleanInbox() throws {
        guard let inbox = CaptureInbox.inboxURL else {
            throw XCTSkip("no App Group container in this test host")
        }
        try? FileManager.default.removeItem(at: inbox)
    }

    private func linkEntry(sender: String?) -> CaptureInboxEntry {
        var e = CaptureInboxEntry(
            id: UUID(), type: "url", url: "https://example.com/kiln", urlTitle: "Kiln",
            text: nil, imageFileName: nil, mimeType: nil,
            annotationText: "Look at this glaze", significance: 0.4,
            sharedAt: ISO8601.string(from: Date()))
        e.senderName = sender
        return e
    }

    // MARK: - Drain → note

    @MainActor
    func testSenderReachesCaptureBodyAsLinkedMention() async throws {
        try cleanInbox()
        let repo = NotesRepository(inMemory: true)
        let entry = linkEntry(sender: "Marta Silva")
        XCTAssertTrue(CaptureInbox.write(entry))

        await CaptureInboxDrainer.drain(into: repo)

        let memo = try XCTUnwrap(repo.memo(id: entry.id), "the share became a note")
        XCTAssertEqual(memo.annotationText, "Look at this glaze\n\nFrom Marta Silva",
                       "the sender is a mention after his own words")

        // On the roster: the shared Sanitiser links it, so the export carries it in `people:`.
        let input = MemoExporter.compilerInput(for: memo, people: [marta])
        let linked = try XCTUnwrap(input.sanitised)
        XCTAssertTrue(linked.contains("From [[Marta Silva]]"), linked)
        XCTAssertEqual(Compiler.peopleLinks(in: linked, knownPeople: [marta]), ["Marta Silva"])
        _ = MemoOpenBridge.shared.consume()
    }

    @MainActor
    func testSenderNotOnRosterStaysPlain() async throws {
        try cleanInbox()
        let repo = NotesRepository(inMemory: true)
        let entry = linkEntry(sender: "Joana Reis")
        XCTAssertTrue(CaptureInbox.write(entry))

        await CaptureInboxDrainer.drain(into: repo)

        let memo = try XCTUnwrap(repo.memo(id: entry.id))
        let input = MemoExporter.compilerInput(for: memo, people: [marta])
        let body = input.sanitised ?? memo.annotationText ?? ""
        XCTAssertTrue(body.contains("From Joana Reis"), body)
        XCTAssertFalse(body.contains("[["), "an unknown sender is plain text, never a link")
        XCTAssertEqual(Compiler.peopleLinks(in: body, knownPeople: [marta]), [])
        _ = MemoOpenBridge.shared.consume()
    }

    @MainActor
    func testNoSenderLeavesBodyAlone() async throws {
        try cleanInbox()
        let repo = NotesRepository(inMemory: true)
        let entry = linkEntry(sender: "   ")
        XCTAssertTrue(CaptureInbox.write(entry))

        await CaptureInboxDrainer.drain(into: repo)

        XCTAssertEqual(repo.memo(id: entry.id)?.annotationText, "Look at this glaze")
        _ = MemoOpenBridge.shared.consume()
    }

    /// A WhatsApp voice note (ingress P1) with a sender: the mention leads the audio note.
    @MainActor
    func testSenderLeadsSharedVoiceNote() async throws {
        try cleanInbox()
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        var entry = CaptureInboxEntry(
            id: id, type: "audio", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil, annotationText: nil,
            significance: 0, sharedAt: ISO8601.string(from: Date()),
            audioFileNames: ["audio_\(id.uuidString)_0.m4a"],
            audioOriginalNames: ["PTT-20261014-WA0001.opus"])
        entry.senderName = "Marta Silva"
        let src = FileManager.default.temporaryDirectory.appendingPathComponent("src_\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: src.path, contents: Data("AAC-ish".utf8))
        XCTAssertTrue(CaptureInbox.write(entry, audioFileURLs: [src]))

        await CaptureInboxDrainer.drain(into: repo)

        let memo = try XCTUnwrap(repo.allMemos().first { $0.audioFilename.hasPrefix("memo_") })
        XCTAssertEqual(memo.annotationText, "From Marta Silva")
        if let f = memo.audioURL { try? FileManager.default.removeItem(at: f) }
        try? FileManager.default.removeItem(at: src)
        _ = MemoOpenBridge.shared.consume()
    }

    // MARK: - The entry field

    func testOldEntryWithoutSenderDecodes() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","type":"text","text":"hi","significance":0,"sharedAt":"2026-10-15T10:00:00Z"}"#
        let e = try JSONDecoder().decode(CaptureInboxEntry.self, from: Data(json.utf8))
        XCTAssertNil(e.senderName)
    }

    func testSenderRoundTripsThroughEntryJSON() throws {
        let e = linkEntry(sender: "Marta Silva")
        let back = try JSONDecoder().decode(CaptureInboxEntry.self, from: JSONEncoder().encode(e))
        XCTAssertEqual(back.senderName, "Marta Silva")
    }

    // MARK: - Rules

    func testCleanAndResolve() {
        XCTAssertNil(ShareSender.clean("  \n "))
        XCTAssertEqual(ShareSender.clean("  marta   [[Silva]] "), "marta Silva")
        let roster = [ShareRosterName(name: "Marta Silva", aliases: ["Marta"])]
        XCTAssertEqual(ShareSender.resolved("marta", roster: roster), "Marta Silva", "an alias takes the canonical")
        XCTAssertEqual(ShareSender.resolved("Joana", roster: roster), "Joana")
        XCTAssertEqual(ShareSender.appending("Marta", to: nil), "From Marta")
        XCTAssertEqual(ShareSender.appending(nil, to: "body"), "body")
    }

    func testRosterAutocomplete() {
        let roster = [ShareRosterName(name: "Marta Silva", aliases: ["Marta"]),
                      ShareRosterName(name: "Mark de Vries", aliases: []),
                      ShareRosterName(name: "Mãe", aliases: []),
                      ShareRosterName(name: "Joana", aliases: [])]
        let hits = ShareSender.suggestions(for: "ma", roster: roster, remembered: ["WhatsApp|Marta": "Marta Silva"])
        XCTAssertEqual(hits.map(\.name), ["Marta Silva", "Mark de Vries", "Mãe"])
        XCTAssertEqual(hits.first?.detail, "WhatsApp: Marta", "a remembered chat labels its name")
        XCTAssertEqual(hits[1].detail, "on your roster")
        XCTAssertEqual(ShareSender.suggestions(for: "silv", roster: roster).map(\.name), ["Marta Silva"])
        XCTAssertTrue(ShareSender.suggestions(for: "", roster: roster).isEmpty)
    }

    func testMessengerFileNamesOfferTheFromRow() {
        XCTAssertTrue(IngressDispatch.isMessengerFileName("PTT-20261014-WA0001.opus"))
        XCTAssertTrue(IngressDispatch.isMessengerFileName("WhatsApp Audio 2026-10-14 at 14.02.11.ogg"))
        XCTAssertTrue(IngressDispatch.isMessengerFileName("IMG-20261014-WA0003.jpg"))
        XCTAssertTrue(IngressDispatch.isMessengerFileName("signal-2026-10-14-140211.jpg"))
        XCTAssertFalse(IngressDispatch.isMessengerFileName("IMG_1234.JPG"))
        XCTAssertFalse(IngressDispatch.isMessengerFileName("kiln idea.m4a"))
        XCTAssertFalse(IngressDispatch.isMessengerFileName(nil))
    }

    func testPerChatMemoryAndRosterSnapshot() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("q464-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let memory = try XCTUnwrap(ShareSenderMemory.inContainer(dir))
        let hint = ShareChatHint.key(app: "WhatsApp", conversation: "Marta")
        XCTAssertNil(memory.name(for: hint))
        memory.remember("Marta Silva", for: hint)
        XCTAssertEqual(memory.name(for: hint), "Marta Silva")
        XCTAssertNil(memory.name(for: nil), "no hint, nothing remembered")
        memory.remember("", for: hint)
        XCTAssertNil(memory.name(for: hint), "clearing the row forgets the chat")

        let names = [ShareRosterName(name: "Marta Silva", aliases: ["Marta"])]
        XCTAssertTrue(ShareRosterSnapshot.write(names, container: dir))
        XCTAssertEqual(ShareRosterSnapshot.read(container: dir), names)
    }

    @MainActor
    func testDrainMirrorsRosterNamesForTheExtension() throws {
        guard CaptureInbox.containerURL != nil else { throw XCTSkip("no App Group container in this test host") }
        let gone = Person(canonical: "[[Old Friend]]", aliases: [], lastModifiedAt: "2026-10-01T00:00:00Z", deleted: true)
        CaptureInboxDrainer.mirrorRosterForShareSheet(people: [marta, gone])
        XCTAssertEqual(ShareRosterSnapshot.read(container: CaptureInbox.containerURL),
                       [ShareRosterName(name: "Marta Silva", aliases: ["Marta"])],
                       "bare names only, deleted people left out")
    }
}
