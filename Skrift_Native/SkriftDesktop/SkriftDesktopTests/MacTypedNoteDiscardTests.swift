import XCTest
import SwiftData
import Foundation

/// Q131 (C43, D91, C112, D151): the Mac's new typed note runs the phone quick note's draft
/// rules. Clicking New note creates NOTHING; the first non-empty edit creates the Memo with
/// the id the pane already shows; leaving a note that is empty again deletes it; and the
/// created note records its place like a voice recording does.
@MainActor
final class MacTypedNoteDiscardTests: XCTestCase {

    private func cloudContext() throws -> ModelContext {
        let c = try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(c)
    }

    private struct FakePlace: MetadataProviding {
        func capture() async -> MemoMetadata {
            MemoMetadata(capturedAt: "2026-10-02T09:00:00Z",
                         location: LocationInfo(latitude: 38.72, longitude: -9.14, placeName: "Lisbon"),
                         dayPeriod: .morning, tags: [])
        }
    }

    private func count(_ ctx: ModelContext) throws -> Int {
        try ctx.fetchCount(FetchDescriptor<Memo>())
    }

    /// Click, then leave without typing: no Memo ever existed, nothing is listed.
    func testClickThenLeaveLeavesNoRowAndNoMemo() throws {
        let ctx = try cloudContext()
        let session = MacTypedNoteSession(metadataProvider: { nil })

        let id = session.begin(context: ctx)
        XCTAssertTrue(session.isDraft(id.uuidString), "the pane's id is the draft's")
        XCTAssertEqual(try count(ctx), 0, "the click itself creates no Memo")

        session.leave(context: ctx)
        XCTAssertEqual(try count(ctx), 0)
        let memos = try ctx.fetch(FetchDescriptor<Memo>())
        XCTAssertTrue(WayOutRules.unpipelined(memos: memos, files: []).isEmpty, "no quiet row")
        XCTAssertFalse(session.isDraft(id.uuidString), "the draft ends on leave")
    }

    /// An empty edit (a cleared field firing onChange) still creates nothing.
    func testEmptyEditCreatesNothing() throws {
        let ctx = try cloudContext()
        let session = MacTypedNoteSession(metadataProvider: { nil })
        session.begin(context: ctx)
        XCTAssertNil(session.edited(title: "", body: "", context: ctx))
        XCTAssertEqual(try count(ctx), 0)
    }

    /// The first keystroke creates one unrated typed Memo, under the id minted at the click.
    func testFirstKeystrokeCreatesTheMemoUnderTheDraftsId() throws {
        let ctx = try cloudContext()
        let session = MacTypedNoteSession(metadataProvider: { nil })
        let id = session.begin(context: ctx)

        let memo = try XCTUnwrap(session.edited(title: "", body: "G", context: ctx))
        XCTAssertEqual(memo.id, id, "the open pane's id never changes under the cursor")
        XCTAssertEqual(try count(ctx), 1)
        XCTAssertEqual(memo.transcript, "G")
        XCTAssertEqual(SourceKind.of(memo), .typedNote)
        XCTAssertFalse(NoteConsent.isRated(memo), "born unrated")

        // Later keystrokes update the same row, never a second one.
        session.edited(title: "", body: "Groceries", context: ctx)
        XCTAssertEqual(try count(ctx), 1)
        XCTAssertEqual(memo.transcript, "Groceries")
        XCTAssertTrue(memo.transcriptUserEdited, "what he typed is his words")
    }

    /// Typed something, deleted it all, left: the row is dropped.
    func testTypedThenEmptiedThenLeftIsDiscarded() throws {
        let ctx = try cloudContext()
        let session = MacTypedNoteSession(metadataProvider: { nil })
        session.begin(context: ctx)
        session.edited(title: "", body: "x", context: ctx)
        XCTAssertEqual(try count(ctx), 1)
        session.edited(title: "", body: "", context: ctx)
        session.leave(context: ctx)
        XCTAssertEqual(try count(ctx), 0)
    }

    /// A note with words survives leaving.
    func testNoteWithWordsSurvivesLeaving() throws {
        let ctx = try cloudContext()
        let session = MacTypedNoteSession(metadataProvider: { nil })
        session.begin(context: ctx)
        session.edited(title: "", body: "keep me", context: ctx)
        session.leave(context: ctx)
        XCTAssertEqual(try count(ctx), 1)
    }

    /// Pressing New note again while the first is still empty drops the first draft.
    func testBeginningASecondDraftLeavesTheFirst() throws {
        let ctx = try cloudContext()
        let session = MacTypedNoteSession(metadataProvider: { nil })
        let first = session.begin(context: ctx)
        session.edited(title: "", body: "a", context: ctx)
        session.edited(title: "", body: "", context: ctx)
        let second = session.begin(context: ctx)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try count(ctx), 0, "the emptied first note went when the second opened")
        XCTAssertTrue(session.isDraft(second.uuidString))
        XCTAssertFalse(session.isDraft(first.uuidString))
    }

    /// D151: the created note records its place, keeping the typed marker.
    func testCreatedNoteStampsPlaceAndKeepsTheTypedMarker() async throws {
        let ctx = try cloudContext()
        let session = MacTypedNoteSession(metadataProvider: { FakePlace() })
        session.begin(context: ctx)
        let memo = try XCTUnwrap(session.edited(title: "", body: "Lunch at the river", context: ctx))
        await session.draft?.captureTask?.value

        XCTAssertEqual(memo.metadata?.location?.placeName, "Lisbon")
        XCTAssertEqual(memo.metadata?.dayPeriod, .morning)
        XCTAssertEqual(SourceKind.of(memo), .typedNote, "the typed marker survives the merge")
    }

    /// An untouched note never starts a capture (nothing to stamp, nothing to cancel).
    func testUntouchedDraftStartsNoCapture() throws {
        let ctx = try cloudContext()
        let session = MacTypedNoteSession(metadataProvider: { FakePlace() })
        session.begin(context: ctx)
        XCTAssertNil(session.draft?.captureTask)
        XCTAssertNil(session.draft?.memo)
    }
}
