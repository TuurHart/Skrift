import XCTest
import Foundation

/// Q142 (D65, C57): the exported `source:` of a TYPED note is one value on both devices. Before
/// the fix the shared source map had no typed value: the phone's `MemoExporter` rode typed as
/// `.audio` (`source: Voice-memo`) and the Mac row as `.note` (`source: Apple-Note`,
/// capture-source-11). Both exporters now set `CompilerInput.kind` from `SourceKind`, and the
/// Compiler maps `.typedNote` to `Typed-note`. One typed-note fixture, both exporters' inputs;
/// the phone target's twin class runs the same fixture through `MemoExporter` itself.
final class ExportSourceFieldTests: XCTestCase {

    /// The typed-note fixture: the shape `Memo.newTyped` writes (no audio, the
    /// `mediaSource: "typed"` marker, nothing to transcribe).
    private func typedMemo() -> Memo {
        let marker = try? JSONSerialization.data(withJSONObject: ["mediaSource": "typed"],
                                                 options: [.sortedKeys])
        return Memo(recordedAt: Date(), title: "Lamp parts", transcript: "Buy the brass fittings.",
                    transcriptStatus: .done, significance: 0.5, metadataData: marker)
    }

    /// The phone's side, as `MemoExporter.compilerInput` builds it (that type is phone-only).
    private func phoneInput(_ m: Memo) -> CompilerInput {
        CompilerInput.make(
            filename: "memo", raw: m.transcript, copyedit: nil, title: m.title, summary: nil,
            tags: m.tags, significance: m.significance, sourceType: .audio, mediaSource: nil,
            metadata: nil, sharedContent: nil, rawRecordedAt: nil, destination: m.destination,
            spoken: !m.audioFilename.isEmpty, kind: SourceKind.of(m))
    }

    private func sourceLine(_ md: String) -> String? {
        md.components(separatedBy: "\n").first { $0.hasPrefix("source: ") || $0.hasPrefix("capture: ") }
    }

    func testTypedNoteSaysTypedNoteOnTheMac() {
        let pf = MemoNoteProjection.file(for: typedMemo())
        XCTAssertEqual(pf.sourceType, .note, "the Mac row rides typed as a text-born note")
        let md = Compiler.compile(file: pf, author: "Me", date: "2026-10-03")
        XCTAssertEqual(sourceLine(md), "source: Typed-note", md)
        XCTAssertFalse(md.contains("Apple-Note"), md)
    }

    func testTypedNoteSaysTheSameThingFromPhoneAndMac() {
        let m = typedMemo()
        let phone = Compiler.compile(phoneInput(m), author: "Me", date: "2026-10-03")
        let mac = Compiler.compile(file: MemoNoteProjection.file(for: m), author: "Me", date: "2026-10-03")
        XCTAssertEqual(sourceLine(phone), "source: \(Compiler.typedSource)", phone)
        XCTAssertEqual(sourceLine(phone), sourceLine(mac))
        XCTAssertFalse(phone.contains("Voice-memo"), phone)
    }

    /// The portfolio writes the same value under its own key (`capture:`).
    func testPortfolioCaptureKeyCarriesTheTypedValue() {
        let pf = MemoNoteProjection.file(for: typedMemo())
        pf.destination = .idea
        let md = Compiler.compile(file: pf, author: "Me", date: "2026-10-03", profile: .portfolio)
        XCTAssertEqual(sourceLine(md), "capture: Typed-note", md)
    }

    /// The other kinds keep their values: an Apple Note import and a voice memo.
    func testOtherKindsAreUnchanged() {
        let note = PipelineFile(id: UUID().uuidString, filename: "n.md", sourceType: .note)
        note.transcript = "From Notes."
        XCTAssertEqual(sourceLine(Compiler.compile(file: note, author: "Me")), "source: Apple-Note")

        let voice = PipelineFile(id: UUID().uuidString, filename: "v.m4a", sourceType: .audio)
        voice.path = "/tmp/v.m4a"
        voice.transcript = "Said aloud."
        XCTAssertEqual(sourceLine(Compiler.compile(file: voice, author: "Me")), "source: Voice-memo")
    }
}
