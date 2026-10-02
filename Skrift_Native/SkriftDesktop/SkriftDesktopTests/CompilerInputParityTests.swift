import XCTest
import Foundation

/// Q155 (C196, C81, R37): ONE `CompilerInput` builder on both exporters. The phone's
/// `MemoExporter.compilerInput` calls `CompilerInput.make` with the memo's raw text, the Mac's
/// copy-edit and the memo's own name decisions; the Mac's `PipelineFile.compilerInput` calls
/// the same `make` with its stored `sanitised`. For one synced note the two must export the
/// same body and the same `voice:`. Before the fix a TITLE-ONLY polish read `cleaned` on the
/// phone and `raw` on the Mac (setexp-88), and the phone's export ignored the note's unlink
/// decisions (R37). The phone target's twin class runs the same cases through `MemoExporter`.
final class CompilerInputParityTests: XCTestCase {

    private let mac = "q155-mac"
    private let hendri = Person(canonical: "[[Hendri van Niekerk]]",
                               aliases: ["Hendri van Niekerk", "Hendri"], short: "Hendri",
                               lastModifiedAt: "2026-01-01T00:00:00Z")
    private let raw = "um so i met hendri today you know"

    private func memo(_ id: UUID, resolutions: NameResolutions = NameResolutions()) -> Memo {
        let m = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", recordedAt: Date(),
                     transcript: raw, transcriptStatus: .done, transcriptConfidence: 0.9,
                     significance: 0.6, nameResolutionsData: resolutions.encoded)
        m.markEdited(Date().addingTimeInterval(10))
        return m
    }

    /// The phone's side, as `MemoExporter.compilerInput` builds it (that type is phone-only).
    private func phoneInput(_ m: Memo, _ enh: MemoEnhancement?) -> CompilerInput {
        let e = (enh?.hasContent == true) ? enh : nil
        return CompilerInput.make(
            filename: "memo", raw: m.transcript, copyedit: e?.copyedit,
            people: [hendri], resolutions: NameResolutions.decode(m.nameResolutionsData),
            title: "T", summary: e?.summary, tags: m.tags, significance: m.significance,
            sourceType: .audio, mediaSource: nil, metadata: nil, sharedContent: nil,
            rawRecordedAt: nil, destination: m.destination, spoken: !m.audioFilename.isEmpty)
    }

    /// The Mac's side: an ingested row the synced memo + enhancement are reflected into.
    private func macRow(_ m: Memo, _ enh: MemoEnhancement?) -> PipelineFile {
        let pf = PipelineFile(id: m.id.uuidString, filename: m.audioFilename)
        pf.path = "/tmp/\(m.audioFilename)"
        pf.transcript = raw
        pf.transcribeStatus = .done
        pf.syncedSourceEditedAt = Date()
        _ = MemoCloudUpdate.apply(memo: m, enhancement: enh, to: pf, people: [hendri],
                                  author: "Me", thisDeviceID: mac, isFreshRow: true)
        return pf
    }

    /// Everything after the closing frontmatter fence.
    private func body(_ input: CompilerInput) -> String {
        let md = Compiler.compile(input, author: "Me", date: "2026-08-19", knownPeople: [hendri])
        let parts = md.components(separatedBy: "\n---\n")
        return parts.dropFirst().joined(separator: "\n---\n")
    }

    func testTitleOnlyPolishIsRawOnBothDevices() {
        let id = UUID()
        let m = memo(id)
        let enh = MemoEnhancement(memoID: id, copyedit: "", title: "Meeting Hendri", summary: "",
                                  enhancedByDeviceID: "phone")
        let phone = phoneInput(m, enh)
        let macIn = macRow(m, enh).compilerInput
        XCTAssertEqual(phone.voice, .raw, "a title is not a copy-edit: the body is the transcript")
        XCTAssertEqual(macIn.voice, .raw)
        XCTAssertEqual(body(phone), body(macIn))
        XCTAssertTrue(body(phone).contains("[[Hendri van Niekerk]]"), body(phone))
    }

    func testCopyeditPolishIsCleanedAndOneBodyOnBothDevices() {
        let id = UUID()
        let m = memo(id)
        let enh = MemoEnhancement(memoID: id, copyedit: "I met Hendri today.", title: "Meeting Hendri",
                                  summary: "A note.", enhancedByDeviceID: "phone")
        let phone = phoneInput(m, enh)
        let macIn = macRow(m, enh).compilerInput
        XCTAssertEqual(phone.voice, .cleaned)
        XCTAssertEqual(macIn.voice, .cleaned)
        XCTAssertEqual(body(phone), body(macIn))
        XCTAssertTrue(body(phone).contains("I met [[Hendri van Niekerk]] today."), body(phone))
        XCTAssertFalse(body(phone).contains("um so"))
    }

    /// R37: the note's own "unlink" decision is honoured by BOTH exporters.
    func testUnlinkDecisionIsHonouredOnBothDevices() {
        let id = UUID()
        var r = NameResolutions()
        r.unlinkedNames = ["Hendri van Niekerk"]
        let m = memo(id, resolutions: r)
        let phone = phoneInput(m, nil)
        let macIn = macRow(m, nil).compilerInput
        XCTAssertEqual(body(phone), body(macIn))
        XCTAssertFalse(body(phone).contains("[["), "an unlinked person stays plain: \(body(phone))")
    }

    func testWrittenNoteAndBodySourceRule() {
        XCTAssertEqual(CompilerInput.workingBody(raw: "r", copyedit: "  \n").text, "r")
        XCTAssertFalse(CompilerInput.workingBody(raw: "r", copyedit: nil).fromCopyedit)
        XCTAssertTrue(CompilerInput.workingBody(raw: "r", copyedit: "c").fromCopyedit)
        let typed = CompilerInput.make(filename: "n", raw: "Hello", copyedit: "Hello.", title: "n",
                                       summary: nil, tags: [], significance: nil, sourceType: .note,
                                       mediaSource: nil, metadata: nil, sharedContent: nil,
                                       rawRecordedAt: nil, destination: .personal, spoken: false)
        XCTAssertEqual(typed.voice, .written)
    }

    func testLinkStemsRideTheBuilder() {
        let target = UUID()
        var input = CompilerInput.make(filename: "n", raw: "see [[memo:\(target.uuidString)|Old]]",
                                       copyedit: nil, title: "n", summary: nil, tags: [],
                                       significance: nil, sourceType: .audio, mediaSource: nil,
                                       metadata: nil, sharedContent: nil, rawRecordedAt: nil,
                                       destination: .personal, spoken: true,
                                       linkStems: [target: "Linked note"])
        XCTAssertEqual(input.memoLinkResolver?(target), "Linked note")
        input.setLinkStems([:])
        XCTAssertNil(input.memoLinkResolver)
    }
}
