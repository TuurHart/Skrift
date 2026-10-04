import XCTest
import UIKit
@testable import SkriftMobile

/// Q310: the photo-OCR sweep, split from MemoSaverTests' save -> searchable
/// contract (which now runs on a fake recognizer). Here: a trigger that lands
/// mid-sweep is not dropped, and the REAL Vision pass still indexes a saved
/// photo end to end, with a window wide enough for Vision's cold start.
final class PhotoTextIndexerTests: XCTestCase {

    /// A save that fires the sweep while another sweep is still running used to
    /// be dropped by the reentrancy guard; its photo stayed unsearchable until
    /// the next launch/foreground. The running sweep must re-run for it.
    @MainActor
    func testTriggerDuringRunningSweepIsNotDropped() async throws {
        let original = PhotoTextIndexer.recognizer
        addTeardownBlock { await MainActor.run { PhotoTextIndexer.recognizer = original } }
        PhotoTextIndexer.recognizer = { url in
            try? await Task.sleep(for: .milliseconds(300))   // slow: B arrives mid-sweep
            return url.lastPathComponent.contains("q310a") ? "ALPHA" : "BRAVO"
        }

        let repoA = NotesRepository(inMemory: true)
        let repoB = NotesRepository(inMemory: true)
        let a = try insertPhotoMemo(into: repoA, tag: "q310a")
        PhotoTextIndexer.run(repoA)
        let b = try insertPhotoMemo(into: repoB, tag: "q310b")
        PhotoTextIndexer.run(repoB)   // sweep A is still sleeping in the recognizer

        var text: String?
        for _ in 0..<100 {
            text = repoB.memo(id: b.id)?.metadata?.imageManifest?.first?.text
            if text != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(text, "BRAVO", "a sweep requested mid-sweep must still run")
        XCTAssertEqual(repoB.memo(id: b.id)?.matches(query: "bravo"), true)

        for f in [a.file, b.file] {
            try? FileManager.default.removeItem(at: AppPaths.recordingsDirectory.appendingPathComponent(f))
        }
    }

    /// The real Vision pass, end to end through a save: rendered text on a
    /// captured photo becomes searchable without relaunch. Tolerant of Vision's
    /// cold start on a freshly erased simulator (60 s, not the old 10 s).
    @MainActor
    func testRealVisionIndexesSavedPhoto() async throws {
        let repo = NotesRepository(inMemory: true)
        let saver = MemoSaver(
            repository: repo,
            transcriber: SeededTranscriber(text: "note with a photo"),
            wordTimings: WordTimingsStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)),
            metadataProvider: MockMetadataService()
        )
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("rec_\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: temp.path, contents: Data())
        let photoTemp = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo-\(UUID().uuidString).jpg")
        try renderedText("GATE B7 LISBOA").write(to: photoTemp)

        let id = await saver.saveAndTranscribe(tempURL: temp, duration: 3,
                                               photos: [(url: photoTemp, offset: 1.0)])

        var matched = false
        for _ in 0..<600 {
            if repo.memo(id: id)?.matches(query: "lisboa") == true { matched = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(matched, "real Vision OCR must make the photo searchable — manifest: \(String(describing: repo.memo(id: id)?.metadata?.imageManifest))")

        if let f = repo.memo(id: id)?.metadata?.imageManifest?.first?.filename {
            try? FileManager.default.removeItem(at: AppPaths.recordingsDirectory.appendingPathComponent(f))
        }
        try? FileManager.default.removeItem(at: AppPaths.recordingsDirectory.appendingPathComponent("memo_\(id.uuidString).m4a"))
    }

    // MARK: - Helpers

    @MainActor
    private func insertPhotoMemo(into repo: NotesRepository, tag: String) throws -> (id: UUID, file: String) {
        try FileManager.default.createDirectory(at: AppPaths.recordingsDirectory, withIntermediateDirectories: true)
        let id = UUID()
        let file = "photo_\(tag)_\(id.uuidString)_001.jpg"
        try Data([0xFF, 0xD8, 0xFF]).write(to: AppPaths.recordingsDirectory.appendingPathComponent(file))
        let memo = Memo(id: id, audioFilename: "", duration: 0, recordedAt: Date(),
                        transcript: "note", transcriptStatus: .done)
        memo.metadata = MemoMetadata(imageManifest: [ImageManifestEntry(filename: file, offsetSeconds: 0)])
        repo.insert(memo)
        return (id, file)
    }

    private func renderedText(_ text: String) -> Data {
        let size = CGSize(width: 600, height: 200)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            (text as NSString).draw(
                at: CGPoint(x: 40, y: 70),
                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 48),
                                 .foregroundColor: UIColor.black])
        }
        return image.jpegData(compressionQuality: 0.9)!
    }
}
