import XCTest
import Foundation

/// Q293 (C25 amended by D176): an import with a REAL file name shows that name until it has
/// words; a generic default ("New Recording N", "Audio N") or a synthetic `memo_<uuid>` name
/// falls back to "Voice note". The rule lives once, in `NoteTitle` (Shared). The phone's
/// `ImportFileNameTitlePhoneTests` runs the same table through the phone's `Memo` adapter.
final class ImportFileNameTitleTests: XCTestCase {

    func testRealNamesAreKeptWithoutTheExtension() {
        XCTAssertEqual(NoteTitle.importName("Interview with Jan.m4a"), "Interview with Jan")
        XCTAssertEqual(NoteTitle.importName("Hotel Du Vin.mp3"), "Hotel Du Vin")
        XCTAssertEqual(NoteTitle.importName("WhatsApp Audio 2025-12-18 at 18.30.44.opus"),
                       "WhatsApp Audio 2025-12-18 at 18.30.44")
        XCTAssertEqual(NoteTitle.importName("Dinner idea"), "Dinner idea", "no extension is fine")
    }

    func testGenericAndSyntheticNamesAreNotNames() {
        for n in ["New Recording 22.m4a", "New Recording.m4a", "Audio 3.m4a", "audio.wav", "Recording 7.caf",
                  "Voice Memo 4.m4a", "Untitled.m4a", "memo_8F2C1B7A-0000-4000-8000-123456789ABC.m4a",
                  "8F2C1B7A-0000-4000-8000-123456789ABC.m4a", "", "   "] {
            XCTAssertNil(NoteTitle.importName(n), n)
        }
        XCTAssertNil(NoteTitle.importName(nil))
    }

    func testDisplayShowsTheNameUntilWordsThenTheWords() {
        func title(user: String? = nil, suggested: String? = nil, body: String? = nil, name: String?) -> String {
            NoteTitle.display(userTitle: user, suggestedTitle: suggested, body: body, shared: nil,
                              importFileName: name, emptyFallback: "Voice note")
        }
        XCTAssertEqual(title(name: "Interview with Jan.m4a"), "Interview with Jan")
        XCTAssertEqual(title(body: "  \n", name: "Interview with Jan.m4a"), "Interview with Jan")
        XCTAssertEqual(title(body: "So we met at noon", name: "Interview with Jan.m4a"), "So we met at noon")
        XCTAssertEqual(title(suggested: "Polished", name: "Interview with Jan.m4a"), "Polished")
        XCTAssertEqual(title(user: "Mine", name: "Interview with Jan.m4a"), "Mine")
        XCTAssertEqual(title(name: "New Recording 22.m4a"), "Voice note")
        XCTAssertEqual(title(name: nil), "Voice note")
    }

    func testMacRowPrefersTheStoredPhoneNameOverTheSyntheticWorkingFile() throws {
        let meta = try JSONSerialization.data(withJSONObject: ["importFileName": "Interview with Jan"])
        let stored = NoteTitle.importFileName(metadataJSON: meta, workingFilename: "memo_ABC.m4a", isCapture: false)
        XCTAssertEqual(NoteTitle.importName(stored), "Interview with Jan")
        // a Mac-local import: the working file IS the user's file
        let local = NoteTitle.importFileName(metadataJSON: nil, workingFilename: "Hotel Du Vin.m4a", isCapture: false)
        XCTAssertEqual(NoteTitle.importName(local), "Hotel Du Vin")
        // a phone memo without a stored name: the synthetic file never shows
        let bare = NoteTitle.importFileName(metadataJSON: nil, workingFilename: "memo_ABC.m4a", isCapture: false)
        XCTAssertNil(NoteTitle.importName(bare))
        // a capture never offers a file name here
        XCTAssertNil(NoteTitle.importFileName(metadataJSON: meta, workingFilename: "x.m4a", isCapture: true))
    }

    func testMemoAdapterReadsTheStoredName() throws {
        let meta = try JSONEncoder().encode(MemoMetadata(importFileName: "Interview with Jan"))
        let named = Memo(audioFilename: "memo_x.m4a", metadataData: meta)
        XCTAssertEqual(named.ladderTitle(), "Interview with Jan")
        let withWords = Memo(audioFilename: "memo_x.m4a", transcript: "So we met at noon", metadataData: meta)
        XCTAssertEqual(withWords.ladderTitle(), "So we met at noon")
        XCTAssertEqual(Memo(audioFilename: "memo_x.m4a").ladderTitle(), "Voice note")
        let generic = try JSONEncoder().encode(MemoMetadata(importFileName: "New Recording 22"))
        XCTAssertEqual(Memo(audioFilename: "memo_x.m4a", metadataData: generic).ladderTitle(), "Voice note")
        // the header ghost stays "Add a title": a file name is not a derived title
        XCTAssertNil(named.ladderGhost())
    }
}
