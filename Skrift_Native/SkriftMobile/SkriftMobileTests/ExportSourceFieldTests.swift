import XCTest
@testable import SkriftMobile

/// Q142 (D65, C57), the phone's half: a TYPED note exports `source: Typed-note` through
/// `MemoExporter`, the value the Mac row writes for the same note (the Mac's
/// `ExportSourceFieldTests`). Before the fix the phone rode typed as `.audio` and wrote
/// `source: Voice-memo`, the Mac `source: Apple-Note`.
final class ExportSourceFieldTests: XCTestCase {

    /// The typed-note fixture: the shape `Memo.newTyped` writes.
    private func typedMemo() -> Memo {
        let marker = try? JSONSerialization.data(withJSONObject: ["mediaSource": "typed"],
                                                 options: [.sortedKeys])
        return Memo(recordedAt: Date(), title: "Lamp parts", transcript: "Buy the brass fittings.",
                    transcriptStatus: .done, significance: 0.5, metadataData: marker)
    }

    private func sourceLine(_ md: String) -> String? {
        md.components(separatedBy: "\n").first { $0.hasPrefix("source: ") || $0.hasPrefix("capture: ") }
    }

    func testTypedNoteSaysTypedNote() {
        let m = typedMemo()
        XCTAssertEqual(MemoExporter.compilerInput(for: m, people: []).kind, .typedNote)
        let md = MemoExporter.markdown(for: m, people: [])
        XCTAssertEqual(sourceLine(md), "source: \(Compiler.typedSource)", md)
        XCTAssertFalse(md.contains("Voice-memo"), md)
    }

    func testPortfolioCaptureKeyCarriesTheTypedValue() {
        let m = typedMemo()
        m.destination = .idea
        let md = MemoExporter.markdown(for: m, people: [], profile: .portfolio)
        XCTAssertEqual(sourceLine(md), "capture: Typed-note", md)
    }

    func testAVoiceMemoStaysAVoiceMemo() {
        let m = Memo(audioFilename: "memo.m4a", recordedAt: Date(), transcript: "Said aloud.",
                     transcriptStatus: .done, significance: 0.5)
        XCTAssertEqual(sourceLine(MemoExporter.markdown(for: m, people: [])), "source: Voice-memo")
    }
}
