import XCTest
@testable import SkriftMobile

/// Q191/C239: the transcript and alignment sidecar sets share one `SidecarKind`; the
/// record-name infixes and filenames are CloudKit WIRE names, so they are pinned here
/// byte-for-byte. Also covers the shared removed-download setter, the carrier's `book`
/// accessor and the single container-id constant.
@MainActor
final class AudiobookSyncSidecarKindTests: XCTestCase {

    private let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private func book(files: [String]) -> Audiobook {
        var b = Audiobook(id: id, audioFilename: files[0], title: "T", author: "A", duration: 10)
        b.files = files
        return b
    }

    func testWireNamesAreByteIdentical() {
        let t = AudiobookCloudSync.transcriptSidecars
        let a = AudiobookCloudSync.alignmentSidecars
        XCTAssertEqual(t.recordName(bookID: id, index: 2), "ab_11111111-2222-3333-4444-555555555555_t2")
        XCTAssertEqual(a.recordName(bookID: id, index: 0), "ab_11111111-2222-3333-4444-555555555555_al0")
        XCTAssertEqual(t.filename(3), "transcript_f3.json")
        XCTAssertEqual(a.filename(1), "alignment_f1.json")
    }

    func testRecordNamesAndRefsFollowFileOrder() {
        let b = book(files: ["a.m4a", "b.m4a"])
        XCTAssertEqual(AudiobookCloudSync.recordNames(AudiobookCloudSync.transcriptSidecars, for: b),
                       ["ab_\(id.uuidString)_t0", "ab_\(id.uuidString)_t1"])
        let refs = AudiobookCloudSync.refs(AudiobookCloudSync.alignmentSidecars, for: b)
        XCTAssertEqual(refs.map(\.recordName), ["ab_\(id.uuidString)_al0", "ab_\(id.uuidString)_al1"])
        XCTAssertEqual(refs.map(\.filename), ["alignment_f0.json", "alignment_f1.json"])
    }

    func testCarrierSignatureKeyPathsTargetTheRightField() {
        let rec = AudiobookSyncRecord(bookID: id, blob: Data())
        rec[keyPath: AudiobookCloudSync.transcriptSidecars.carrierSignature] = "T"
        rec[keyPath: AudiobookCloudSync.alignmentSidecars.carrierSignature] = "A"
        XCTAssertEqual(rec.transcriptSignature, "T")
        XCTAssertEqual(rec.alignmentSignature, "A")
    }

    func testSetDownloadRemovedInsertsAndDrops() {
        let suite = "q191_\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        let other = UUID()
        AudiobookCloudSync.setDownloadRemoved(id, true, defaults: d)
        AudiobookCloudSync.setDownloadRemoved(other, true, defaults: d)
        XCTAssertTrue(AudiobookCloudSync.isDownloadRemoved(bookID: id, defaults: d))
        AudiobookCloudSync.setDownloadRemoved(id, false, defaults: d)
        XCTAssertFalse(AudiobookCloudSync.isDownloadRemoved(bookID: id, defaults: d))
        XCTAssertTrue(AudiobookCloudSync.isDownloadRemoved(bookID: other, defaults: d), "other books untouched")
    }

    func testRecordBookAccessorDecodesBlob() throws {
        let b = book(files: ["a.m4a"])
        let rec = AudiobookSyncRecord(bookID: id, blob: try JSONEncoder().encode(b))
        XCTAssertEqual(rec.book?.id, id)
        XCTAssertNil(AudiobookSyncRecord(bookID: id, blob: Data("nope".utf8)).book)
    }

    func testContainerIDIsTheOneConstant() {
        XCTAssertEqual(AudiobookCloudSync.containerID, SkriftCloudContainer.id)
        #if DEBUG
        XCTAssertEqual(SkriftCloudContainer.id, "iCloud.com.skrift.mobile.dev")
        #else
        XCTAssertEqual(SkriftCloudContainer.id, "iCloud.com.skrift.mobile")
        #endif
    }
}
