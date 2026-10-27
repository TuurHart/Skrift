import XCTest
import SwiftData
import Foundation

/// Q530: editing an UNRATED Mac note carries only what was typed into the memo's raw transcript.
/// A word he said as an alias ("Nik" for Nick Jansen) must stay "Nik" after an unrelated edit.
@MainActor
final class UnratedEditKeepsSpokenWordsTests: XCTestCase {

    private let nick = Person(canonical: "[[Nick Jansen]]", aliases: ["Nik", "Nick"], short: "Nick",
                              lastModifiedAt: "2026-01-01T00:00:00.000Z")
    private let bruno = Person(canonical: "[[Bruno Aragorn]]", aliases: ["Bruno"], short: "Bruno",
                               lastModifiedAt: "2026-01-01T00:00:00.000Z")
    private var people: [Person] { [nick, bruno] }

    private func memo(_ text: String) -> Memo {
        Memo(id: UUID(), audioFilename: "memo_x.m4a", duration: 12,
             recordedAt: Date(timeIntervalSince1970: 1_700_000_000), tags: [],
             title: nil, transcript: text, transcriptStatus: .done, significance: 0)
    }

    /// What the pane does on a body edit: the body binding writes `sanitised`, the mirror derives
    /// the raw transcript, `commit` writes it to the memo.
    private func open(_ text: String) -> (Memo, PipelineFile) {
        let m = memo(text)
        let pf = MemoNoteProjection.file(for: m)
        MemoNoteProjection.linkNames(pf, memo: m, people: people)
        return (m, pf)
    }

    private func edit(_ m: Memo, _ pf: PipelineFile, _ transform: (String) -> String) {
        pf.sanitised = transform(pf.sanitised ?? "")
        if let raw = MemoNoteProjection.rawTranscript(ofLinked: pf, people: people), raw != pf.transcript {
            pf.transcript = raw
        }
        MemoNoteProjection.writeBack(pf, to: m)
    }

    func testAnUnrelatedEditLeavesTheAliasAndTheOtherNameByteIdentical() {
        let (m, pf) = open("Nik called me. I saw Bruno at lunch.")
        XCTAssertEqual(pf.sanitised, "[[Nick Jansen]] called me. I saw [[Bruno Aragorn]] at lunch.",
                       "premise: both names are shown linked")
        edit(m, pf) { $0 + " Done." }
        XCTAssertEqual(m.transcript, "Nik called me. I saw Bruno at lunch. Done.")
    }
}
