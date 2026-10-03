import XCTest

/// Q120: ONE backlink scan (Shared/Pipeline/Backlinks) over transcript + copy-edit. Same
/// file in both suites (mobile adds the @testable import); the fixture is identical.
final class BacklinkScanTests: XCTestCase {

    private let now = Date()
    private func memo(_ transcript: String, days: Int = 90) -> Memo {
        Memo(audioFilename: "m.m4a", recordedAt: now.addingTimeInterval(-Double(days) * 86_400),
             transcript: transcript, transcriptStatus: .done)
    }
    private func link(_ id: UUID) -> String { MemoLinkSyntax.link(id: id, title: "Old thought") }

    func testScanFindsATranscriptLinkAndACopyeditLink() {
        let target = UUID(), viaTranscript = UUID(), viaCopyedit = UUID(), unrelated = UUID()
        let rows = [
            Backlinks.Row(id: viaTranscript, transcript: "see \(link(target))", copyedit: nil),
            Backlinks.Row(id: viaCopyedit, transcript: "just words", copyedit: "polished \(link(target))"),
            Backlinks.Row(id: unrelated, transcript: "links elsewhere \(link(UUID()))", copyedit: "plain"),
            Backlinks.Row(id: target, transcript: "self \(link(target))", copyedit: nil),
        ]
        XCTAssertEqual(Backlinks.scan(for: target, in: rows), [viaTranscript, viaCopyedit],
                       "transcript and copy-edit both count; the note itself and other targets do not")
    }

    func testScanIgnoresATextualMentionThatIsNotALink() {
        let target = UUID()
        let rows = [Backlinks.Row(id: UUID(), transcript: "memo:\(target.uuidString) is not a link", copyedit: nil)]
        XCTAssertEqual(Backlinks.scan(for: target, in: rows), [])
    }

    /// The bug: a Mac-made link syncs into the copy-edit, so a transcript-only scan let the
    /// linked note fade while the panel listed the backlink.
    func testALinkOnlyInTheCopyeditStopsTheNoteFading() {
        let old = memo("old and unlinked")             // 90 days, untouched → would fade
        let linker = memo("just words", days: 1)
        let copyedits = [linker.id: "polished \(link(old.id))"]

        XCTAssertTrue(MemoLifecycle.isFading(old, backlinked: MemoLifecycle.backlinkedIDs(in: [old, linker]), now: now),
                      "transcript-only scan misses the copy-edit link")
        let ids = MemoLifecycle.backlinkedIDs(in: [old, linker], copyedits: copyedits)
        XCTAssertEqual(ids, [old.id])
        XCTAssertFalse(MemoLifecycle.isFading(old, backlinked: ids, now: now))
        XCTAssertEqual(Set(MemoLifecycle.partition([old, linker], copyedits: copyedits, now: now).fading.map(\.id)), [])
    }

    func testATrashedLinkerDoesNotHoldANoteOff() {
        let old = memo("old")
        let linker = memo("see \(link(old.id))", days: 1)
        linker.deletedAt = now
        XCTAssertEqual(MemoLifecycle.backlinkedIDs(in: [old, linker]), [])
    }

    func testCopyeditMapDropsEmptyPolishes() {
        let a = UUID(), b = UUID()
        let map = Backlinks.copyeditsByMemoID([MemoEnhancement(memoID: a, copyedit: "x"),
                                               MemoEnhancement(memoID: b, copyedit: "")])
        XCTAssertEqual(map, [a: "x"])
    }
}
