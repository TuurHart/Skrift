import XCTest
@testable import SkriftMobile

/// Q255 / C199: an `.m4b` or `.epub` opened from Files or another app goes to Books, never to a
/// note and never silently dropped. The pure routing decision, plus the bridge the library reads.
final class BookOpenInRoutingTests: XCTestCase {

    private func file(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/\(name)") }

    func testM4bIsImportedAsAnAudiobook() {
        XCTAssertEqual(BookOpenInRouting.decision(for: file("Dune.m4b")), .importAudiobook)
        XCTAssertEqual(BookOpenInRouting.decision(for: file("DUNE.M4B")), .importAudiobook)
    }

    func testEpubNeedsAnAudiobookToAttachTo() {
        XCTAssertEqual(BookOpenInRouting.decision(for: file("Dune.epub")), .needsAudiobook)
    }

    func testSkriftbookKeepsItsOwnOfferPath() {
        XCTAssertEqual(BookOpenInRouting.decision(for: file("Dune.skriftbook")), .notAudiobookFile)
    }

    func testNonBooksAndNonFileURLsAreNotBookRouted() {
        XCTAssertEqual(BookOpenInRouting.decision(for: file("memo.m4a")), .notAudiobookFile)
        XCTAssertEqual(BookOpenInRouting.decision(for: file("scan.pdf")), .notAudiobookFile)
        XCTAssertEqual(BookOpenInRouting.decision(for: URL(string: "https://x.test/Dune.m4b")!), .notAudiobookFile)
    }

    /// An .m4b is a `.book` kind, so it is not a voice note: it never joins the One note / N
    /// notes chooser.
    @MainActor
    func testM4bIsNotAVoiceNoteClip() {
        XCTAssertTrue(AppURLHandler.audioClips(in: [file("Dune.m4b"), file("Dune.epub")]).isEmpty)
    }

    @MainActor
    func testBridgeQueuesAndConsumesOnce() {
        let bridge = BookFileImportBridge.shared
        _ = bridge.consume()
        let before = bridge.requestID
        bridge.offer(file("A.m4b"))
        bridge.offer(file("B.m4b"))
        XCTAssertEqual(bridge.requestID, before + 2)
        XCTAssertEqual(bridge.consume().map(\.lastPathComponent), ["A.m4b", "B.m4b"])
        XCTAssertTrue(bridge.consume().isEmpty)
    }

    /// Open-in of an .m4b hands it to the bridge and brings Books forward; an .epub brings Books
    /// forward and says why it was not added.
    @MainActor
    func testHandleRoutesM4bToTheBridgeAndEpubToASkipNote() {
        let bridge = BookFileImportBridge.shared
        _ = bridge.consume()
        TabSelectionBridge.shared.requestedTab = nil

        AppURLHandler.handle(file("Dune.m4b"))
        XCTAssertEqual(bridge.consume().map(\.lastPathComponent), ["Dune.m4b"])
        XCTAssertEqual(TabSelectionBridge.shared.requestedTab, .books)

        TabSelectionBridge.shared.requestedTab = nil
        AppURLHandler.handle(file("Dune.epub"))
        XCTAssertTrue(bridge.consume().isEmpty)
        XCTAssertEqual(TabSelectionBridge.shared.requestedTab, .books)
        TabSelectionBridge.shared.requestedTab = nil
    }
}
