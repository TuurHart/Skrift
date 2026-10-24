import XCTest
import Foundation

/// Q471 (C123): a voice or video share's sender reaches `people:` like a capture's. The phone's
/// drain writes the share sheet's From name into an audio note's lead text (`annotationText`,
/// "From Marta Silva"), which the transcript never carries. The ONE shared builder
/// (`CompilerInput.make`, `lead:`) appends that mention to the exported body, name-linked, so a
/// roster sender lands in `people:` on the Mac's export and the phone's alike.
@MainActor
final class SenderPeopleExportTests: XCTestCase {

    private let mac = "q471-mac"
    private let marta = Person(canonical: "[[Marta Silva]]", aliases: ["Marta"],
                               lastModifiedAt: "2026-10-01T00:00:00Z")
    private let raw = "the kiln needs a new element before the weekend"

    private func voiceShare(lead: String?, transcript: String? = nil) -> Memo {
        let id = UUID()
        let m = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", recordedAt: Date(),
                     transcript: transcript ?? raw, transcriptStatus: .done, transcriptConfidence: 0.9,
                     significance: 0.6)
        m.annotationText = lead
        m.markEdited(Date().addingTimeInterval(10))
        return m
    }

    /// The Mac's side: the synced memo reflected into its queue row.
    private func macRow(_ m: Memo) -> PipelineFile {
        let pf = PipelineFile(id: m.id.uuidString, filename: m.audioFilename)
        pf.path = "/tmp/\(m.audioFilename)"
        pf.transcript = m.transcript
        pf.transcribeStatus = .done
        pf.syncedSourceEditedAt = Date()
        _ = V2.reflect(m, enhancement: nil, to: pf, people: [marta], author: "Me", device: mac, freshRow: true)
        return pf
    }

    /// The Mac's export input: the row compiled with the live roster, as `Compiler.compile(file:)` does.
    private func macInput(_ m: Memo) -> CompilerInput { macRow(m).compilerInput(people: [marta]) }

    /// The phone's side, as `MemoExporter.compilerInput` builds it (that type is phone-only).
    private func phoneInput(_ m: Memo) -> CompilerInput {
        CompilerInput.make(
            filename: "memo", raw: m.transcript, copyedit: nil, people: [marta],
            title: "T", summary: nil, tags: m.tags, significance: m.significance,
            sourceType: .audio, mediaSource: nil, metadata: nil, sharedContent: nil,
            rawRecordedAt: nil, destination: m.destination, spoken: true,
            lead: m.annotationText)
    }

    private func markdown(_ input: CompilerInput) -> String {
        Compiler.compile(input, author: "Me", date: "2026-10-15", knownPeople: [marta])
    }

    private func peopleLine(_ md: String) -> String? {
        md.components(separatedBy: "\n").first { $0.hasPrefix("people:") }
    }

    func testRosterSenderOfVoiceShareExportsInPeopleOnTheMac() {
        let md = markdown(macInput(voiceShare(lead: "From Marta Silva")))
        XCTAssertEqual(peopleLine(md), "people: [[Marta Silva]]", md)
        XCTAssertTrue(md.contains("From [[Marta Silva]]"), md)
        XCTAssertTrue(md.contains(raw), "the transcript stays the body: \(md)")
    }

    func testPhoneAndMacExportTheSameSender() {
        let m = voiceShare(lead: "From Marta Silva")
        let phone = markdown(phoneInput(m))
        let macMD = markdown(macInput(m))
        XCTAssertEqual(peopleLine(phone), "people: [[Marta Silva]]", phone)
        XCTAssertEqual(peopleLine(phone), peopleLine(macMD))
    }

    func testAliasSenderTakesTheCanonical() {
        let md = markdown(macInput(voiceShare(lead: "From Marta")))
        XCTAssertEqual(peopleLine(md), "people: [[Marta Silva]]", md)
    }

    func testUnknownSenderStaysPlain() {
        let md = markdown(macInput(voiceShare(lead: "From Joana Reis")))
        XCTAssertEqual(peopleLine(md), "people:", md)
        XCTAssertTrue(md.contains("From Joana Reis"), md)
        XCTAssertFalse(md.contains("[[Joana"), md)
    }

    func testSenderAlreadyLinkedInTranscriptIsNotLinkedTwice() {
        let m = voiceShare(lead: "From Marta", transcript: "Marta says the kiln is broken")
        let md = markdown(macInput(m))
        XCTAssertEqual(peopleLine(md), "people: [[Marta Silva]]", md)
        XCTAssertEqual(md.components(separatedBy: "[[Marta Silva").count - 1, 2,
                       "one link in people:, one in the body: \(md)")
        XCTAssertTrue(md.contains("From Marta"), md)
    }

    func testThoughtAboveTheSenderStillFindsIt() {
        let md = markdown(macInput(voiceShare(lead: "Listen to the end\n\nFrom Marta Silva")))
        XCTAssertEqual(peopleLine(md), "people: [[Marta Silva]]", md)
        XCTAssertFalse(md.contains("Listen to the end"), "only the sender exports from the lead")
    }

    func testNoSenderLeavesExportAlone() {
        let plain = markdown(macInput(voiceShare(lead: nil)))
        let thought = markdown(macInput(voiceShare(lead: "From the top of the hill")))
        XCTAssertFalse(plain.contains("From "), plain)
        XCTAssertEqual(peopleLine(plain), "people:")
        XCTAssertEqual(ShareSender.name(inLead: "From Marta Silva"), "Marta Silva")
        XCTAssertNil(ShareSender.name(inLead: "From Marta\nand more"))
        XCTAssertNil(ShareSender.name(inLead: "Marta Silva"))
        XCTAssertNil(ShareSender.name(inLead: nil))
        // A one-line thought that happens to start "From " reads as a sender; it is plain text
        // unless it names someone on the roster.
        XCTAssertEqual(peopleLine(thought), "people:", thought)
    }
}
