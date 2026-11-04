import XCTest
import SwiftData
import Foundation

/// Q548: the Mac froze (rainbow cursor, several seconds) on launch until the picture Tuur had
/// just taken on the phone appeared. This times the main-actor work of a reconcile pass on an
/// ON-DISK store (blobs live inline in SQLite, so a blob fetch costs real I/O, unlike the
/// in-memory stores most tests use) with phone-sized media: a 5 MB voice memo, a 4 MB photo.
@MainActor
final class MacArrivalMainThreadTests: XCTestCase {

    private lazy var root = FileManager.default.temporaryDirectory
        .appendingPathComponent("q548_\(UUID().uuidString)", isDirectory: true)
    private var upload: URL { root.appendingPathComponent("upload", isDirectory: true) }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func randomData(_ bytes: Int) -> Data {
        var d = Data(count: bytes)
        d.withUnsafeMutableBytes { arc4random_buf($0.baseAddress!, bytes) }
        return d
    }

    private func stores() throws -> (container: ModelContainer, cloud: ModelContext, local: ModelContext) {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cloud = try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self, MemoEditHead.self,
                                       configurations: ModelConfiguration(url: root.appendingPathComponent("cloud.store")))
        let local = try ModelContainer(for: PipelineFile.self,
                                       configurations: ModelConfiguration(url: root.appendingPathComponent("local.store")))
        return (cloud, ModelContext(cloud), ModelContext(local))
    }

    private func memo(_ i: Int, audioName: String? = nil, metadata: Data? = nil) -> Memo {
        Memo(id: UUID(), audioFilename: audioName ?? "memo_\(i).m4a",
             recordedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(i)),
             transcript: "Words of note \(i).", transcriptStatus: .done,
             transcriptConfidence: 0.9, significance: 0.5,
             metadataData: metadata ?? Data(#"{"dayPeriod":"morning","steps":1200}"#.utf8),
             recordingDeviceID: "iphone-test")
    }

    private func ms(_ block: () throws -> Void) rethrows -> Double {
        let t = CFAbsoluteTimeGetCurrent()
        try block()
        return (CFAbsoluteTimeGetCurrent() - t) * 1000
    }

    /// A library of voice notes (0.5 MB audio each) already on the Mac, plus one 5 MB note whose
    /// photo (4 MB) syncs in AFTER the row was made. The pass that sees the photo is the one that
    /// froze the app.
    func testMeasureLatePhotoOnExistingNote() throws {
        let s = try stores()
        for i in 0..<150 {
            let m = memo(i)
            s.cloud.insert(m)
            s.cloud.insert(MemoAsset(memoID: m.id, kind: MemoAsset.Kind.audio, filename: m.audioFilename, blob: randomData(512_000)))
        }
        let target = memo(999)
        s.cloud.insert(target)
        s.cloud.insert(MemoAsset(memoID: target.id, kind: MemoAsset.Kind.audio, filename: target.audioFilename,
                                 blob: randomData(5_000_000)))
        try s.cloud.save()
        _ = V2.pass(ModelContext(s.container), into: s.local, device: "mac-test", outputDir: upload)

        // Steady-state baseline.
        let base = ms { _ = V2.pass(ModelContext(s.container), into: s.local, device: "mac-test", outputDir: upload) }

        // The photo arrives: the memo's manifest names it, its asset row follows.
        let photoName = "photo_\(target.id.uuidString)_001.jpg"
        let c2 = ModelContext(s.container)
        let t2 = try c2.fetch(FetchDescriptor<Memo>(predicate: #Predicate { $0.id == target.id })).first!
        t2.metadataData = Data(#"{"dayPeriod":"morning","steps":1200,"imageManifest":[{"filename":"\#(photoName)","offsetSeconds":0}]}"#.utf8)
        c2.insert(MemoAsset(memoID: target.id, kind: MemoAsset.Kind.photo, filename: photoName, blob: randomData(4_000_000)))
        try c2.save()

        ReconcileWork.reset()
        var out: ReconcileV2.PassOutcome?
        let withPhoto = ms { out = V2.pass(ModelContext(s.container), into: s.local, device: "mac-test", outputDir: upload) }
        let work = ReconcileWork.counts
        print("Q548 MEASURE late-photo: steady pass \(Int(base)) ms; pass that heals the photo \(Int(withPhoto)) ms; blob fetches \(work.assetBlobFetches); updated \(out?.sweep.updatedIDs.count ?? -1)")
        let again = ms { _ = V2.pass(ModelContext(s.container), into: s.local, device: "mac-test", outputDir: upload) }
        print("Q548 MEASURE late-photo: pass after the heal \(Int(again)) ms")
    }

    /// A new 5 MB note with a 4 MB photo: the app's deferred path (sweep, then prepare off main,
    /// then commit on main).
    func testMeasureNewNoteWithPhoto() throws {
        let s = try stores()
        for i in 0..<150 {
            let m = memo(i)
            s.cloud.insert(m)
            s.cloud.insert(MemoAsset(memoID: m.id, kind: MemoAsset.Kind.audio, filename: m.audioFilename, blob: randomData(512_000)))
        }
        try s.cloud.save()
        _ = V2.pass(ModelContext(s.container), into: s.local, device: "mac-test", outputDir: upload)

        let photoName = "photo_x_001.jpg"
        let newMemo = memo(1000, metadata: Data(#"{"imageManifest":[{"filename":"\#(photoName)","offsetSeconds":0}]}"#.utf8))
        let c2 = ModelContext(s.container)
        c2.insert(newMemo)
        c2.insert(MemoAsset(memoID: newMemo.id, kind: MemoAsset.Kind.audio, filename: newMemo.audioFilename, blob: randomData(5_000_000)))
        c2.insert(MemoAsset(memoID: newMemo.id, kind: MemoAsset.Kind.photo, filename: photoName, blob: randomData(4_000_000)))
        try c2.save()

        var out: ReconcileV2.PassOutcome?
        let sweep = ms { out = V2.pass(ModelContext(s.container), into: s.local, device: "mac-test", outputDir: upload, deferNew: true) }
        print("Q548 MEASURE new-note: main-thread sweep \(Int(sweep)) ms, pending \(out?.sweep.pendingNewIDs.count ?? -1)")
    }
}
