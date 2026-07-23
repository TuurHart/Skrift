import XCTest
@testable import SkriftMobile

/// The alignment apply-latch (device catch 2026-07-23, Tuur's iPad): the receiver
/// held a valid 9.5 MB alignment sidecar with all 29 real TOC marks, derived the
/// chapters, wrote them — and build 106's `Audiobook` encoder dropped
/// `epubChapters` on the way to disk. The old latch recorded "applied" anyway, so
/// the device never retried and the sheet kept showing file-split parts.
/// The marker now carries the OUTCOME, so a lost write re-derives (locally, no
/// download) while a genuinely mark-less alignment still latches once.
final class AlignmentApplyLatchTests: XCTestCase {

    private let sig = "0:aligned:7506:1"

    func testNoMarkerDownloadsAndApplies() {
        XCTAssertEqual(AudiobookCloudSync.alignmentStep(applied: nil, signature: sig,
                                                        localHasEpubChapters: false),
                       .downloadAndApply)
    }

    func testNewSignatureDownloadsEvenWhenChaptersExist() {
        XCTAssertEqual(AudiobookCloudSync.alignmentStep(applied: "older#29", signature: sig,
                                                        localHasEpubChapters: true),
                       .downloadAndApply)
    }

    func testLegacyMarkerReDerivesOnceWithoutDownloading() {
        // Exactly Tuur's iPad: build 106 wrote a bare-signature marker and lost the
        // chapters. The outcome is unknown, so re-derive from the sidecar on disk.
        XCTAssertEqual(AudiobookCloudSync.alignmentStep(applied: sig, signature: sig,
                                                        localHasEpubChapters: false),
                       .applyOnly)
    }

    func testLegacyMarkerAlsoReDerivesWhenChaptersHappenToExist() {
        // Cheap and idempotent — a stale legacy marker gets upgraded to the new
        // outcome-carrying format on the next pass either way.
        XCTAssertEqual(AudiobookCloudSync.alignmentStep(applied: sig, signature: sig,
                                                        localHasEpubChapters: true),
                       .applyOnly)
    }

    func testAppliedWithChaptersPresentSkips() {
        XCTAssertEqual(AudiobookCloudSync.alignmentStep(applied: "\(sig)#29", signature: sig,
                                                        localHasEpubChapters: true),
                       .skip)
    }

    func testAppliedWithChaptersLostReApplies() {
        // The heal: the marker remembers it produced 29, the record has none.
        XCTAssertEqual(AudiobookCloudSync.alignmentStep(applied: "\(sig)#29", signature: sig,
                                                        localHasEpubChapters: false),
                       .applyOnly)
    }

    func testMarklessAlignmentLatchesAndStaysSkipped() {
        // An aligned sidecar with no TOC marks legitimately derives nothing — it must
        // NOT re-decode a multi-megabyte sidecar on every reconcile.
        XCTAssertEqual(AudiobookCloudSync.alignmentStep(applied: "\(sig)#0", signature: sig,
                                                        localHasEpubChapters: false),
                       .skip)
    }
}
