import XCTest
import SwiftData
import Foundation

/// Q553 (gate+): a note holding BOTH an old inline picture marker AND a clean picture paragraph
/// that follows unpunctuated text. The one-time rewrite (`BodyNormaliseMigration.rewrite`) and
/// the Mac's first transcript write (`ReconcileV2.Author`'s `markTranscribed`, reached through
/// `reflectTranscripts` for machine text and `author` for a typed/edited take) must keep every
/// paragraph break that is not next to a marker they moved, or refuse and leave the note as it was.
@MainActor
final class BodyNormaliseMixedShapeTests: XCTestCase {

    /// img_001 sits inside a sentence (v1's wrap); img_002 is already its own paragraph after
    /// a paragraph that ends without punctuation.
    private let mixed = "He sat\n\n[[img_001]]\n\n down and kept walking along the road\n\n[[img_002]]\n\nThen the second paragraph begins here."
    /// The same with a list line between the inline picture's sentence and the clean one.
    private let mixedList = "She wrote\n\n[[img_001]]\n\n a note\n\n- milk and eggs\n\n[[img_002]]\n\nThen she left."

    private func paragraphs(_ s: String) -> [String] {
        s.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func prose(_ s: String) -> [String] { paragraphs(s).filter { !$0.hasPrefix("[[img_") } }

    private let expectedMixedProse = ["He sat down and kept walking along the road", "Then the second paragraph begins here."]

    /// Passes when the rewrite was refused (nil), or every prose paragraph survived whole.
    private func assertKeepsBreaks(_ out: String?, input: String, expectedProse: [String],
                                   _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let out else { return }   // refusing is the safe outcome
        XCTAssertEqual(prose(out), expectedProse, "\(label): paragraph breaks lost.\nin:  \(input.debugDescription)\nout: \(out.debugDescription)", file: file, line: line)
        XCTAssertEqual(BodyV2Marker.numbers(in: out).sorted(), [1, 2], "\(label): markers", file: file, line: line)
        XCTAssertFalse(BodyNormaliseMigration.needsNormalise(out, manifestCount: 2), "\(label): not v2 shape", file: file, line: line)
    }

    // MARK: BodyNormaliseMigration.rewrite

    func testRewriteMachineTextKeepsParagraphBreak() {
        let out = BodyNormaliseMigration.rewrite(mixed, manifestCount: 2, machineText: true)
        print("Q553 machine out: \(String(describing: out?.debugDescription))")
        assertKeepsBreaks(out, input: mixed, expectedProse: expectedMixedProse, "machine")
    }

    func testRewriteUserEditedKeepsParagraphBreak() {
        let out = BodyNormaliseMigration.rewrite(mixed, manifestCount: 2, machineText: false)
        print("Q553 edited out: \(String(describing: out?.debugDescription))")
        assertKeepsBreaks(out, input: mixed, expectedProse: expectedMixedProse, "edited")
    }

    func testRewriteWithListLineKeepsBreaks() {
        let expected = ["She wrote a note", "- milk and eggs", "Then she left."]
        for machine in [true, false] {
            let out = BodyNormaliseMigration.rewrite(mixedList, manifestCount: 2, machineText: machine)
            print("Q553 list machine=\(machine) out: \(String(describing: out?.debugDescription))")
            assertKeepsBreaks(out, input: mixedList, expectedProse: expected, "list machine=\(machine)")
        }
    }

    /// The v1-wrap repair still works (the guard must not refuse the plain case).
    func testV1WrapStillRepaired() throws {
        let body = "The cat sat\n\n[[img_001]]\n\n down."
        for machine in [true, false] {
            let out = try XCTUnwrap(BodyNormaliseMigration.rewrite(body, manifestCount: 1, machineText: machine))
            XCTAssertEqual(out, "The cat sat down.\n\n[[img_001]]", "machine=\(machine)")
        }
    }

    /// The preservation guard itself: a result that glued two prose paragraphs is refused.
    func testGuardRefusesAGluedParagraph() {
        let old = "One line\n\nTwo line\n\n[[img_001]]"
        XCTAssertFalse(BodyNormaliseMigration.keepsBreaks(old, "One line Two line\n\n[[img_001]]"))
        XCTAssertTrue(BodyNormaliseMigration.keepsBreaks(old, "One line\n\nTwo line\n\n[[img_001]]"))
        // The mixed shape as the old code produced it: the break next to the CLEAN picture is gone.
        XCTAssertFalse(BodyNormaliseMigration.keepsBreaks(
            mixed, "He sat down and kept walking along the road Then the second paragraph begins here.\n\n[[img_001]]\n\n[[img_002]]",
            manifestCount: 2))
        // The v1 wrap's own breaks may go.
        XCTAssertTrue(BodyNormaliseMigration.keepsBreaks(
            "The cat sat\n\n[[img_001]]\n\n down.", "The cat sat down.\n\n[[img_001]]", manifestCount: 1))
    }

    // MARK: markTranscribed

    private func cloudContext() throws -> ModelContext {
        let c = try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(c)
    }

    private let manifest = [ImageManifestEntry(filename: "a.jpg", offsetSeconds: 1),
                            ImageManifestEntry(filename: "b.jpg", offsetSeconds: 5)]

    func testReflectTranscriptsMachineKeepsParagraphBreak() throws {
        let cloud = try cloudContext()
        let id = UUID()
        let memo = Memo(id: id, audioFilename: "n.m4a", recordingDeviceID: DeviceID.current())
        var meta = MemoMetadata(); meta.imageManifest = manifest
        memo.metadata = meta
        cloud.insert(memo)
        let pf = PipelineFile(id: id.uuidString, filename: "n.m4a", sourceType: .audio)
        pf.transcript = mixed
        pf.transcribeStatus = .done
        XCTAssertEqual(try ReconcileV2.Author.reflectTranscripts([pf], into: cloud), 1)
        print("Q553 markTranscribed machine out: \(String(describing: memo.transcript?.debugDescription))")
        assertKeepsBreaksOrAsIs(memo.transcript, label: "markTranscribed machine")
    }

    func testAuthorEditedKeepsParagraphBreak() throws {
        let cloud = try cloudContext()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("q553_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("image_manifest.json"))
        let id = UUID()
        let pf = PipelineFile(id: id.uuidString, filename: "n.m4a", sourceType: .audio)
        pf.path = folder.appendingPathComponent("n.m4a").path
        pf.isLocalRecording = true          // → markTranscribed(userEdited: true)
        pf.transcript = mixed
        let memo = try XCTUnwrap(try ReconcileV2.Author.author(pf, into: cloud))
        XCTAssertEqual(memo.metadata?.imageManifest?.count, 2)
        print("Q553 markTranscribed edited out: \(String(describing: memo.transcript?.debugDescription))")
        assertKeepsBreaksOrAsIs(memo.transcript, label: "markTranscribed edited")
    }

    /// `markTranscribed` writes the Mac's own fresh words: a result is fine when every prose
    /// paragraph survived whole, or when the text was stored as it came.
    private func assertKeepsBreaksOrAsIs(_ out: String?, label: String, line: UInt = #line) {
        guard let out else { return XCTFail("\(label): no transcript", line: line) }
        if out == mixed { return }
        XCTAssertEqual(prose(out), expectedMixedProse, "\(label): paragraph breaks lost.\nout: \(out.debugDescription)", line: line)
        XCTAssertEqual(BodyV2Marker.numbers(in: out).sorted(), [1, 2], "\(label): markers", line: line)
    }
}
