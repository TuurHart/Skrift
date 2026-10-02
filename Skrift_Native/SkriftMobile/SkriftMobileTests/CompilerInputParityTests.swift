import XCTest
@testable import SkriftMobile

/// Q155 (C196, C81, R37), the phone's half: `MemoExporter.compilerInput` goes through the ONE
/// shared `CompilerInput.make`, so a title-only polish reads `voice: raw` (the body is the
/// transcript), a copy-edit polish reads `cleaned`, and the note's own unlink decision is
/// honoured. The Mac's `CompilerInputParityTests` asserts the same bodies through the Mac row.
final class CompilerInputParityTests: XCTestCase {

    private let hendri = Person(canonical: "[[Hendri van Niekerk]]",
                               aliases: ["Hendri van Niekerk", "Hendri"], short: "Hendri",
                               lastModifiedAt: "2026-01-01T00:00:00Z")

    private func memo(_ resolutions: NameResolutions = NameResolutions()) -> Memo {
        Memo(audioFilename: "memo.m4a", recordedAt: Date(),
             transcript: "um so i met hendri today you know", significance: 0.5,
             nameResolutionsData: resolutions.encoded)
    }

    func testTitleOnlyPolishIsRaw() {
        let m = memo()
        let enh = MemoEnhancement(memoID: m.id, copyedit: "", title: "Meeting Hendri", summary: "")
        let input = MemoExporter.compilerInput(for: m, people: [hendri], enhancement: enh)
        XCTAssertEqual(input.voice, .raw, "a title is not a copy-edit: the body is the transcript")
        m.destination = .idea
        let md = MemoExporter.markdown(for: m, people: [hendri], enhancement: enh, profile: .portfolio)
        XCTAssertTrue(md.contains("voice: raw"), md)
        XCTAssertTrue(md.contains("um so i met [[Hendri van Niekerk]] today"), md)
    }

    func testCopyeditPolishIsCleaned() {
        let m = memo()
        let enh = MemoEnhancement(memoID: m.id, copyedit: "I met Hendri today.", title: "Meeting Hendri",
                                  summary: "A note.")
        let input = MemoExporter.compilerInput(for: m, people: [hendri], enhancement: enh)
        XCTAssertEqual(input.voice, .cleaned)
        let md = MemoExporter.markdown(for: m, people: [hendri], enhancement: enh)
        XCTAssertTrue(md.contains("I met [[Hendri van Niekerk]] today."), md)
        XCTAssertFalse(md.contains("um so"), md)
    }

    /// R37: the phone's own export honours the note's unlink decision (it ignored it).
    func testUnlinkDecisionIsHonoured() {
        var r = NameResolutions()
        r.unlinkedNames = ["Hendri van Niekerk"]
        let md = MemoExporter.markdown(for: memo(r), people: [hendri])
        let body = md.components(separatedBy: "\n---\n").dropFirst().joined()
        XCTAssertFalse(body.contains("[["), "an unlinked person stays plain: \(md)")
        XCTAssertTrue(body.contains("hendri"), md)
    }

    func testLinkStemsRideTheBuilder() {
        let target = UUID()
        let m = Memo(audioFilename: "memo.m4a", recordedAt: Date(),
                     transcript: "see [[memo:\(target.uuidString)|Old]]", significance: 0.5)
        let md = MemoExporter.markdown(for: m, people: [], linkStems: [target: "Linked note"])
        XCTAssertTrue(md.contains("[[Linked note|Old]]"), md)
    }
}
