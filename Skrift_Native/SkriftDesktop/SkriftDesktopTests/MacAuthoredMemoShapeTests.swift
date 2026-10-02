import XCTest
import SwiftData
import Foundation

/// Q139 (R36, C71, C124): a memo the Mac authors carries what a phone memo of the same kind
/// would — the metadata blob (media marker, clip manifest, picture manifest), one `photo` asset
/// per picture under the phone's `photo_<uuid>_NNN` name, and an `audioFilename` only when the
/// row has audio. Each case builds the working folder `IngestService` writes for that kind.
///
/// The authored memos are also the phone's fixture: `testFixtureMatchesTheMacAuthoredShape`
/// compares them to `test-fixtures/mac-authored-memos/memos.json`, which the phone's
/// `MacAuthoredMemoReadTests` reads. A shape change here fails until the fixture is refreshed
/// (the test writes the actual file to a temp path and names it).
@MainActor
final class MacAuthoredMemoShapeTests: XCTestCase {

    // Fixed ids so the fixture is reproducible.
    static let videoID = UUID(uuidString: "11111111-1111-4111-8111-000000000001")!
    static let noteID = UUID(uuidString: "11111111-1111-4111-8111-000000000002")!
    static let pictureID = UUID(uuidString: "11111111-1111-4111-8111-000000000003")!
    static let mergedID = UUID(uuidString: "11111111-1111-4111-8111-000000000004")!
    static let clipPictureID = UUID(uuidString: "11111111-1111-4111-8111-000000000005")!
    static let movID = UUID(uuidString: "11111111-1111-4111-8111-000000000006")!
    static let recordedAt = Date(timeIntervalSince1970: 1_700_000_000)

    static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test-fixtures/mac-authored-memos/memos.json")
    }

    private func cloudContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                           cloudKitDatabase: .none)))
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mams-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func write(_ text: String, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func writeImages(_ names: [(String, Double)], in folder: URL) throws {
        for (name, _) in names { try write("PIXELS \(name)", folder.appendingPathComponent("images/\(name)")) }
        let entries = names.map { ImageManifestEntry(filename: $0.0, offsetSeconds: $0.1) }
        try JSONEncoder().encode(entries).write(to: folder.appendingPathComponent("image_manifest.json"))
    }

    static let clips = [
        ClipManifestEntry(filename: "PTT-20240101-WA0001.opus", startSeconds: 0, recordedAt: "2024-01-01T09:00:00Z"),
        ClipManifestEntry(filename: "PTT-20240101-WA0002.opus", startSeconds: 4.5, recordedAt: "2024-01-01T09:02:00Z"),
        ClipManifestEntry(filename: "PTT-20240101-WA0003.opus", startSeconds: 9.25, recordedAt: nil),
    ]

    /// One row per kind, in the on-disk shape `IngestService` writes for it.
    private func rows(in root: URL) throws -> [(PipelineFile, URL?)] {
        var out: [(PipelineFile, URL?)] = []

        // Video: audio stripped to original.m4a, one frame as images/img_001.jpg at offset 0.
        let v = root.appendingPathComponent("video")
        try write("AUDIO video", v.appendingPathComponent("original.m4a"))
        try writeImages([("img_001.jpg", 0)], in: v)
        let video = PipelineFile(id: Self.videoID.uuidString, filename: "IMG_0001.MOV",
                                 path: v.appendingPathComponent("original.m4a").path,
                                 sourceType: .audio, uploadedAt: Self.recordedAt)
        video.mediaSource = "video"
        out.append((video, URL(fileURLWithPath: video.path)))

        // Apple Note: markdown body, no audio.
        let n = root.appendingPathComponent("note")
        try write("# Groceries\n\nmilk", n.appendingPathComponent("original.md"))
        let note = PipelineFile(id: Self.noteID.uuidString, filename: "Groceries.md",
                                path: n.appendingPathComponent("original.md").path,
                                sourceType: .note, uploadedAt: Self.recordedAt)
        note.transcript = "# Groceries\n\nmilk"
        note.transcribeStatus = .done
        out.append((note, URL(fileURLWithPath: note.path)))

        // Picture-only note: a capture folder, one picture paragraph each.
        let p = root.appendingPathComponent("capture_pictures")
        try writeImages([("img_001.jpg", 0), ("img_002.png", 0)], in: p)
        let picture = PipelineFile(id: Self.pictureID.uuidString, filename: "capture_pictures",
                                   path: p.path, sourceType: .capture, uploadedAt: Self.recordedAt)
        picture.transcript = MixedBundle.pictureOnlyBody(count: 2)
        picture.transcribeStatus = .done
        out.append((picture, URL(fileURLWithPath: picture.path)))

        // Merged clips: original.m4a + clip_manifest.json beside it (C124).
        let m = root.appendingPathComponent("merged")
        try write("AUDIO merged", m.appendingPathComponent("original.m4a"))
        try JSONEncoder().encode(Self.clips).write(to: m.appendingPathComponent(IngestService.clipManifestName))
        let merged = PipelineFile(id: Self.mergedID.uuidString, filename: "PTT-20240101-WA0001.opus",
                                  path: m.appendingPathComponent("original.m4a").path,
                                  sourceType: .audio, uploadedAt: Self.recordedAt)
        out.append((merged, URL(fileURLWithPath: merged.path)))

        // Clip + picture: the picture rides at its moment in the clip.
        let c = root.appendingPathComponent("clip_picture")
        try write("AUDIO clip", c.appendingPathComponent("original.m4a"))
        try writeImages([("img_001.jpg", 2.5)], in: c)
        let clipPicture = PipelineFile(id: Self.clipPictureID.uuidString, filename: "voice.m4a",
                                       path: c.appendingPathComponent("original.m4a").path,
                                       sourceType: .audio, uploadedAt: Self.recordedAt)
        out.append((clipPicture, URL(fileURLWithPath: clipPicture.path)))

        // An audio-only .mov: ingested as plain audio, keeps its own name.
        let a = root.appendingPathComponent("mov")
        try write("AUDIO mov", a.appendingPathComponent("original.mov"))
        let mov = PipelineFile(id: Self.movID.uuidString, filename: "talk.mov",
                               path: a.appendingPathComponent("original.mov").path,
                               sourceType: .audio, uploadedAt: Self.recordedAt)
        out.append((mov, URL(fileURLWithPath: mov.path)))
        return out
    }

    private func authorAll() throws -> ModelContext {
        let ctx = try cloudContext()
        for (pf, audio) in try rows(in: try tempDir()) {
            XCTAssertNotNil(try MacMemoAuthor.author(for: pf, audioURL: audio, into: ctx), pf.filename)
        }
        return ctx
    }

    private func memo(_ id: UUID, _ ctx: ModelContext) throws -> Memo {
        try XCTUnwrap(try ctx.fetch(FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })).first)
    }

    private func assets(_ id: UUID, _ ctx: ModelContext) throws -> [MemoAsset] {
        try ctx.fetch(FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.memoID == id }))
            .sorted { ($0.kind, $0.filename) < ($1.kind, $1.filename) }
    }

    private func rawMeta(_ memo: Memo) -> [String: Any] {
        memo.metadataData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }

    // MARK: - Per kind

    func testVideoCarriesItsMarkerFrameAndAnAudioName() throws {
        let ctx = try authorAll()
        let m = try memo(Self.videoID, ctx)
        XCTAssertEqual(SourceKind.of(m), .video, "capture-source-07: a Mac video reads as a video on the phone")
        XCTAssertEqual(rawMeta(m)["mediaSource"] as? String, "video")
        XCTAssertEqual(m.metadata?.sourceType, MemoMetadata.Source.video, "the phone's own key too (C71)")
        XCTAssertEqual(m.audioFilename, "memo_\(Self.videoID.uuidString).m4a",
                       "the blob is the extracted m4a, not the movie: it must not carry the .MOV name")
        let frame = "photo_\(Self.videoID.uuidString)_001.jpg"
        XCTAssertEqual(m.metadata?.imageManifest?.map(\.filename), [frame])
        let a = try assets(Self.videoID, ctx)
        XCTAssertEqual(a.map(\.kind), [MemoAsset.Kind.audio, MemoAsset.Kind.photo])
        XCTAssertEqual(a.map(\.filename), [m.audioFilename, frame])
        XCTAssertEqual(a[1].blob, Data("PIXELS img_001.jpg".utf8))
    }

    func testAppleNoteHasNoAudio() throws {
        let ctx = try authorAll()
        let m = try memo(Self.noteID, ctx)
        XCTAssertEqual(m.audioFilename, "", "capture-source-08: a note has no audio name")
        XCTAssertEqual(m.duration, 0)
        XCTAssertEqual(SourceKind.of(m), .appleNote)
        XCTAssertNil(m.metadataData, "nothing to say beyond the row fields")
        XCTAssertTrue(try assets(Self.noteID, ctx).isEmpty, "the markdown is never shipped as audio")
    }

    func testPictureNoteShipsEveryPictureAsAPhotoAsset() throws {
        let ctx = try authorAll()
        let m = try memo(Self.pictureID, ctx)
        XCTAssertEqual(m.audioFilename, "")
        XCTAssertNotEqual(SourceKind.of(m), .voiceMemo, "capture-source-08")
        let names = ["photo_\(Self.pictureID.uuidString)_001.jpg", "photo_\(Self.pictureID.uuidString)_002.png"]
        XCTAssertEqual(m.metadata?.imageManifest?.map(\.filename), names)
        let a = try assets(Self.pictureID, ctx)
        XCTAssertEqual(a.map(\.kind), [MemoAsset.Kind.photo, MemoAsset.Kind.photo], "capture-source-20")
        XCTAssertEqual(a.map(\.filename), names)
        XCTAssertEqual(a.map(\.blob), [Data("PIXELS img_001.jpg".utf8), Data("PIXELS img_002.png".utf8)])
    }

    func testMergedNoteCarriesItsClipManifest() throws {
        let ctx = try authorAll()
        let m = try memo(Self.mergedID, ctx)
        XCTAssertEqual(m.metadata?.clipManifest, Self.clips, "C124: the clip starts ride to the phone")
        XCTAssertEqual(MixedBundle.breakStarts(m.metadata?.clipManifest ?? []), [4.5, 9.25])
        XCTAssertEqual(SourceKind.of(m), .voiceMemo)
        XCTAssertEqual(m.audioFilename, "memo_\(Self.mergedID.uuidString).m4a",
                       "the stitched blob is m4a: the first clip's .opus name would lie about it")
        XCTAssertEqual(try assets(Self.mergedID, ctx).map(\.filename), [m.audioFilename])
    }

    func testClipPlusPictureKeepsThePictureMoment() throws {
        let ctx = try authorAll()
        let m = try memo(Self.clipPictureID, ctx)
        let entry = try XCTUnwrap(m.metadata?.imageManifest?.first)
        XCTAssertEqual(entry.filename, "photo_\(Self.clipPictureID.uuidString)_001.jpg")
        XCTAssertEqual(entry.offsetSeconds, 2.5)
        XCTAssertEqual(try assets(Self.clipPictureID, ctx).map(\.kind), [MemoAsset.Kind.audio, MemoAsset.Kind.photo])
    }

    func testAudioOnlyMovKeepsItsName() throws {
        let ctx = try authorAll()
        let m = try memo(Self.movID, ctx)
        XCTAssertEqual(m.audioFilename, "talk.mov")
        XCTAssertEqual(try assets(Self.movID, ctx).map(\.filename), ["talk.mov"])
    }

    /// The real import path: a picture-only drop through `IngestService`, then the sweep's author.
    func testIngestedPictureDropAuthorsPhotoAssets() async throws {
        let src = try tempDir()
        let pics = [src.appendingPathComponent("a.jpg"), src.appendingPathComponent("b.jpg")]
        for p in pics { try write("PIXELS \(p.lastPathComponent)", p) }
        let local = ModelContext(try ModelContainer(for: PipelineFile.self,
                                                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let report = try await IngestService(outputDir: try tempDir()).ingestReport(localURLs: pics, into: local)
        let pf = try XCTUnwrap(report.created.first)
        XCTAssertEqual(pf.sourceType, .capture)

        let cloud = try cloudContext()
        XCTAssertEqual(try MacMemoAuthor.backfill(files: [pf], into: cloud), 1)
        let id = try XCTUnwrap(UUID(uuidString: pf.id))
        let m = try memo(id, cloud)
        XCTAssertEqual(m.audioFilename, "")
        XCTAssertNotEqual(SourceKind.of(m), .voiceMemo)
        let a = try assets(id, cloud)
        XCTAssertEqual(a.count, 2)
        XCTAssertEqual(Set(a.map(\.kind)), [MemoAsset.Kind.photo])
        XCTAssertEqual(m.metadata?.imageManifest?.map(\.filename), a.map(\.filename))
    }

    // MARK: - The phone's fixture

    func testFixtureMatchesTheMacAuthoredShape() throws {
        let ctx = try authorAll()
        let memos = try ctx.fetch(FetchDescriptor<Memo>()).sorted { $0.id.uuidString < $1.id.uuidString }
        let allAssets = try ctx.fetch(FetchDescriptor<MemoAsset>())
            .sorted { ($0.memoID.uuidString, $0.kind, $0.filename) < ($1.memoID.uuidString, $1.kind, $1.filename) }
        var memoRows: [[String: Any]] = []
        for m in memos {
            var row: [String: Any] = [
                "id": m.id.uuidString,
                "audioFilename": m.audioFilename,
                "duration": m.duration,
                "recordedAt": ISO8601.string(from: m.recordedAt),
                "transcriptStatus": m.transcriptStatus.rawValue,
                "significance": m.significance,
            ]
            if let t = m.transcript { row["transcript"] = t }
            if let d = m.metadataData { row["metadata"] = String(decoding: d, as: UTF8.self) }
            memoRows.append(row)
        }
        let assetRows: [[String: Any]] = allAssets.map {
            ["memoID": $0.memoID.uuidString, "kind": $0.kind, "filename": $0.filename,
             "blob": $0.blob.base64EncodedString()]
        }
        let actual = try JSONSerialization.data(withJSONObject: ["memos": memoRows, "assets": assetRows],
                                                options: [.sortedKeys, .prettyPrinted])
        let expected = try? Data(contentsOf: Self.fixtureURL)
        if expected != actual {
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("mac-authored-memos.actual.json")
            try actual.write(to: out)
            XCTFail("the Mac-authored shape changed; the phone reads \(Self.fixtureURL.path). Actual written to \(out.path)")
        }
    }
}
