import XCTest

/// Q468 (C63, C71, D210): a video note's kept movie never reaches the vault, but its poster frame
/// does, as an image embed in the movie's place; and a machine-named share's card is titled by
/// the date it was filmed, not by the bare word "Video".
final class VideoNoteVaultFrameTests: XCTestCase {

    /// A working folder the way a Mac video import leaves it: the manifest naming the kept movie,
    /// and `source.mov` beside it.
    private func workingFolder(movie: Bool = true, capturedAt: Date? = nil) throws -> URL {
        let work = makeTempDir()
        let entry = NoteAttachment.keptMovieEntry(
            filename: VideoKeep.filename(memoID: UUID(), sourceExtension: "mov"),
            originalName: "Video", byteCount: 5, durationSeconds: 1, capturedAt: capturedAt)
        try JSONEncoder().encode([entry]).write(to: work.appendingPathComponent(MacNoteAttachments.manifestName))
        if movie { NoteAttachmentFixture.writeMovie(to: work.appendingPathComponent("source.mov"), seconds: 1) }
        else { try Data("not a movie".utf8).write(to: work.appendingPathComponent("source.mov")) }
        return work
    }

    /// A placer that copies like the real one and remembers what it was asked to place.
    private final class Recorder {
        var placed: [(source: String, name: String)] = []
        func place(_ src: URL, _ name: String, _ dir: URL) -> URL? {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(name)
            guard (try? FileManager.default.copyItem(at: src, to: dest)) != nil else { return nil }
            placed.append((src.lastPathComponent, name))
            return dest
        }
    }

    func testTheKeptMovieMarkerBecomesItsPosterFrameEmbed() throws {
        let work = try workingFolder(); defer { try? FileManager.default.removeItem(at: work) }
        let att = work.appendingPathComponent("att")
        let rec = Recorder()
        let (md, count) = MacNoteAttachments.convertMarkers(
            "[[vid_001]]\n\nSaid something.", working: work, safe: "Kiln", into: att, profile: .obsidian, place: rec.place)

        XCTAssertEqual(count, 1)
        XCTAssertEqual(md, "![[Kiln_frame.jpg]]\n\nSaid something.", "the frame sits where the movie's marker was")
        XCTAssertEqual(rec.placed.map(\.name), ["Kiln_frame.jpg"], "only the frame is placed, never the movie")
        let jpeg = try Data(contentsOf: att.appendingPathComponent("Kiln_frame.jpg"))
        XCTAssertEqual(Array(jpeg.prefix(3)), [0xFF, 0xD8, 0xFF], "a real JPEG")
        XCTAssertFalse(FileManager.default.fileExists(atPath: att.appendingPathComponent("source.mov").path))
    }

    func testThePortfolioGetsTheFrameToo() throws {
        let work = try workingFolder(); defer { try? FileManager.default.removeItem(at: work) }
        let rec = Recorder()
        let (md, count) = MacNoteAttachments.convertMarkers(
            "[[vid_001]]\n\nwords", working: work, safe: "Kiln", into: work.appendingPathComponent("att"),
            profile: .portfolio, place: rec.place)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(md, "![](Kiln_frame.jpg)\n\nwords")
    }

    func testTheFrameIsMadeOnceAndReused() throws {
        let work = try workingFolder(); defer { try? FileManager.default.removeItem(at: work) }
        let first = try XCTUnwrap(MacNoteAttachments.posterFrame(in: work))
        let bytes = try Data(contentsOf: first)
        let second = try XCTUnwrap(MacNoteAttachments.posterFrame(in: work))
        XCTAssertEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: second), bytes, "the dry run and the real write place the same bytes")
    }

    func testAMovieWithNoReadableFrameDropsTheMarker() throws {
        let work = try workingFolder(movie: false); defer { try? FileManager.default.removeItem(at: work) }
        let rec = Recorder()
        let (md, count) = MacNoteAttachments.convertMarkers(
            "[[vid_001]]\n\nwords", working: work, safe: "Kiln", into: work.appendingPathComponent("att"),
            profile: .obsidian, place: rec.place)
        XCTAssertEqual(count, 0)
        XCTAssertTrue(rec.placed.isEmpty)
        XCTAssertFalse(md.contains("[[vid_"), "a dangling marker is dropped, never printed")
        XCTAssertTrue(md.contains("words"))
    }

    func testAnEngineWithoutAFrameDropsTheKeptMovieInTheSharedConversion() {
        let entry = NoteAttachment.keptMovieEntry(filename: VideoKeep.filename(memoID: UUID(), sourceExtension: "mov"),
                                                  originalName: "Video", byteCount: 5, durationSeconds: 1)
        let r = ExportBody.convertAttachmentMarkers("[[vid_001]]\n\nwords", manifest: [entry], stem: "Kiln",
                                                    profile: .obsidian) { _, _ in "never" }
        XCTAssertEqual(r.placed, 0)
        XCTAssertFalse(r.markdown.contains("vid_001"))
        XCTAssertFalse(r.markdown.contains("never"), "the movie is never placed")
    }

    func testABodyAttachedVideoStillGoesBesideTheNote() throws {
        // `video_<uuid>_NNN.<ext>` is a video the person attached in the body, not the kept movie.
        let body = NoteAttachmentEntry(kind: NoteAttachment.Kind.video, filename: "video_\(UUID().uuidString)_002.mov",
                                       name: "clip.mov", uti: "com.apple.quicktime-movie", byteCount: 3)
        var seen: [String] = []
        let r = ExportBody.convertAttachmentMarkers("[[vid_001]]", manifest: [body], stem: "Kiln", profile: .obsidian,
                                                    poster: { _, _ in "frame.jpg" }) { source, preferred in
            seen.append(source); return preferred
        }
        XCTAssertEqual(r.placed, 1)
        XCTAssertEqual(seen, [body.filename])
        XCTAssertTrue(r.markdown.contains("Kiln_video_001.mov"))
    }

    // MARK: the card's title

    func testAMachineNamedShareIsTitledByTheDateItWasFilmed() throws {
        let when = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-15T12:00:00Z"))
        let entry = NoteAttachment.keptMovieEntry(filename: VideoKeep.filename(memoID: UUID(), sourceExtension: "mov"),
                                                  originalName: "Video", byteCount: 5, durationSeconds: 6, capturedAt: when)
        let card = NoteAttachment.card(entry)
        XCTAssertEqual(card.title, when.formatted(.dateTime.day().month(.abbreviated).year()))
        XCTAssertNotEqual(card.title, "Video")
        XCTAssertTrue(card.subtitle.hasPrefix("Video · 0:06"), card.subtitle)
        XCTAssertEqual(entry.name, "Video", "the stored name is unchanged")
    }

    func testANamedShareKeepsItsName() {
        let entry = NoteAttachment.keptMovieEntry(filename: VideoKeep.filename(memoID: UUID(), sourceExtension: "mov"),
                                                  originalName: "kiln test.mov", byteCount: 5, durationSeconds: 6,
                                                  capturedAt: Date())
        XCTAssertEqual(NoteAttachment.card(entry).title, "kiln test.mov")
    }

    func testAnEntryWithNoDateStillReadsVideo() {
        let entry = NoteAttachment.keptMovieEntry(filename: VideoKeep.filename(memoID: UUID(), sourceExtension: "mov"),
                                                  originalName: "Video", byteCount: 5, durationSeconds: 6)
        XCTAssertEqual(NoteAttachment.card(entry).title, "Video")
        // An older synced entry (no date key) decodes.
        let json = #"{"kind":"video","filename":"video_x.mov","name":"Video","uti":"com.apple.quicktime-movie","byteCount":1}"#
        XCTAssertNoThrow(try JSONDecoder().decode(NoteAttachmentEntry.self, from: Data(json.utf8)))
    }
}
