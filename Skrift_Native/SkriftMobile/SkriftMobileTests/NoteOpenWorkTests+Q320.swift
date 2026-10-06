import XCTest
import SwiftData
@testable import SkriftMobile

/// Q320 — the "[[" picker builds its titles once per memo-set version, off the main actor, and
/// they equal what the per-memo ladder (`Memo.ladderTitle`) gives; the ladder's empty fallback and
/// the source-kind classifier no longer run for a note that has words.
extension NoteOpenWorkTests {

    /// One note of every ladder rung: a title, words, a typed note with nothing yet, a link capture,
    /// a text capture with an annotation, an imported file with a real name, a generic import name,
    /// an empty voice note, a book capture.
    private func q320Library() -> NotesRepository {
        let repo = NotesRepository(inMemory: true)
        let now = Date()
        var minutes = 0.0
        func add(_ m: Memo) { minutes += 1; m.recordedAt = now.addingTimeInterval(-minutes * 60); repo.context.insert(m) }
        func json(_ obj: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) }
        func shared(_ sc: SharedContent) -> Data { try! JSONEncoder().encode(sc) }

        add(Memo(audioFilename: "a.m4a", title: "Garden plans", transcript: "words", transcriptStatus: .done))
        add(Memo(audioFilename: "b.m4a", transcript: "A long first line about the morning walk\nsecond line",
                 transcriptStatus: .done))
        add(Memo(audioFilename: "", transcriptStatus: .done, metadataData: json(["mediaSource": "typed", "tags": [String]()])))
        add(Memo(audioFilename: "", transcriptStatus: .done,
                 sharedContentData: shared(SharedContent(type: .url, url: "https://www.example.com/a", urlTitle: "An article"))))
        add(Memo(audioFilename: "", transcriptStatus: .done,
                 sharedContentData: shared(SharedContent(type: .text, text: "Quoted words from somewhere else entirely, long enough to clip")),
                 annotationText: "My own reaction"))
        add(Memo(audioFilename: "c.m4a", transcriptStatus: .done,
                 metadataData: json(["importFileName": "Standup with Dana.m4a", "tags": [String]()])))
        add(Memo(audioFilename: "d.m4a", transcriptStatus: .done,
                 metadataData: json(["importFileName": "New Recording 22.m4a", "tags": [String]()])))
        add(Memo(audioFilename: "e.m4a", transcriptStatus: .done))
        add(Memo(audioFilename: "f.m4a", transcriptStatus: .done,
                 metadataData: json(["bookTitle": "Some Book", "tags": [String]()])))
        repo.allMemos().first?.duration += 1; repo.save()
        return repo
    }

    func testThePickersTitlesEqualTheOldBuilderAndBuildOffMainOncePerVersion() async {
        let repo = q320Library()
        let old = repo.allMemos().map { (id: $0.id, title: $0.ladderTitle(), subtitle: MemoDate.label($0.recordedAt)) }
        XCTAssertEqual(old.count, 9)

        let builds = NoteOpenWork.candidateBuilds
        await NoteOpenWork.warmLinkCandidates(repository: repo)
        await NoteOpenWork.warmLinkCandidates(repository: repo)
        let a = NoteOpenWork.linkCandidates(excluding: UUID(), repository: repo)
        XCTAssertEqual(NoteOpenWork.candidateBuilds, builds + 1, "warmed twice and read once: one build")
        XCTAssertEqual(a.map(\.id), old.map(\.id))
        XCTAssertEqual(a.map(\.title), old.map(\.title))
        XCTAssertEqual(a.map(\.subtitle), old.map(\.subtitle))
        XCTAssertTrue(a.map(\.title).contains("Garden plans"))
        XCTAssertTrue(a.map(\.title).contains("Standup with Dana"), "a real import name shows")
        XCTAssertTrue(a.map(\.title).contains("Note"), "the typed note's empty fallback")
        XCTAssertTrue(a.map(\.title).contains("Voice note"))

        // A concurrent pair shares one build.
        repo.allMemos().first?.duration += 1; repo.save()
        async let w1: Void = NoteOpenWork.warmLinkCandidates(repository: repo)
        async let w2: Void = NoteOpenWork.warmLinkCandidates(repository: repo)
        _ = await (w1, w2)
        XCTAssertEqual(NoteOpenWork.candidateBuilds, builds + 2, "a save rebuilds once, however many callers")
        // The cold, on-main path still gives the same rows.
        let cold = NoteOpenWork.buildCandidates(NoteOpenWork.candidateInputs(repository: repo))
        XCTAssertEqual(cold.map(\.title), old.map(\.title))
    }

    func testTheEmptyFallbackIsOnlyEvaluatedWhenTheNoteHasNothingElse() {
        var fallbackRuns = 0, importRuns = 0
        func title(body: String?, importName: String?) -> String {
            NoteTitle.display(userTitle: nil, suggestedTitle: nil, body: body, shared: nil,
                              importFileName: { importRuns += 1; return importName }(),
                              emptyFallback: { fallbackRuns += 1; return "Voice note" }())
        }
        XCTAssertEqual(title(body: "Some words here", importName: "Real name.m4a"), "Some words here")
        XCTAssertEqual(fallbackRuns, 0, "a note with words never asks for its source kind")
        XCTAssertEqual(importRuns, 0)
        XCTAssertEqual(title(body: nil, importName: "Real name.m4a"), "Real name")
        XCTAssertEqual(fallbackRuns, 0)
        XCTAssertEqual(title(body: nil, importName: nil), "Voice note")
        XCTAssertEqual(fallbackRuns, 1)
    }

    func testTheSourceKindClassifierRunsOncePerNoteContent() {
        // A per-run nonce keeps the bytes unique: the content-keyed cache is process-global, so a
        // fixed blob may already be cached by an earlier test (order-dependent "4 vs 5").
        let blob = try! JSONSerialization.data(withJSONObject: ["mediaSource": "typed", "tags": [String](), "nonce": UUID().uuidString])
        let m = Memo(audioFilename: "", transcriptStatus: .done, metadataData: blob)
        let before = SourceKind.classifyRuns
        XCTAssertEqual(SourceKind.of(m), .typedNote)
        XCTAssertEqual(SourceKind.of(m), .typedNote)
        XCTAssertEqual(SourceKind.of(metadataData: blob, sharedContentData: nil, hasAudio: false), .typedNote)
        XCTAssertEqual(SourceKind.classifyRuns, before + 1, "same bytes, same answer, one parse")
        // An edit is a new key, never a stale answer.
        m.metadataData = try! JSONSerialization.data(withJSONObject: ["mediaSource": "video", "tags": [String](), "nonce": UUID().uuidString])
        XCTAssertEqual(SourceKind.of(m), .video)
        XCTAssertEqual(SourceKind.classifyRuns, before + 2)
    }
}
