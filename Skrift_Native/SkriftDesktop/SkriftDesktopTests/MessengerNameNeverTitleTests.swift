import XCTest
import Foundation

/// Q457 (C126, D211): a messenger or machine file name is never a note title on ANY door. The
/// share sheet decides through `IngressDispatch.clipTitle`; the Files importer, Open-in, AirDrop
/// and the Mac drop / folder ingest decide through `NoteTitle.importName` (the phone stores it
/// as `importFileName`, the Mac reads the working file's own name). Both now share one rule.
final class MessengerNameNeverTitleTests: XCTestCase {

    private let machineNames = [
        "PTT-20241003-WA0007.opus", "AUD-20241003-WA0002.m4a",
        "WhatsApp Audio 2025-12-18 at 18.30.44.opus", "signal-2024-10-03-120001.aac",
        "voice_1.ogg", "audio_2024-10-03_12-00-01.ogg", "Voice message.m4a",
        "shared_8F2C1B7A-0000-4000-8000-123456789ABC.m4a",
        "capture_8F2C1B7A-0000-4000-8000-123456789ABC.m4a",
        "shared_import_8F2C1B7A-0000-4000-8000-123456789ABC_0.m4a",
    ]

    /// Files / Open-in / AirDrop: the name the phone's importer would store.
    func testFilesDoorNeverTitlesAMessengerName() {
        for name in machineNames {
            XCTAssertNil(NoteTitle.importName(name), name)
        }
    }

    /// A real name still becomes the title, on the same doors.
    func testRealNameStillTitles() {
        XCTAssertEqual(NoteTitle.importName("kiln idea.m4a"), "kiln idea")
        XCTAssertEqual(NoteTitle.importName("Rua Augusta 12.m4a"), "Rua Augusta 12")
        XCTAssertEqual(NoteTitle.importName("Dinner idea"), "Dinner idea")
    }

    /// The Mac drop / folder ingest: the working file keeps the dropped file's own name, and the
    /// row's title ladder reads it. A messenger name falls to "Voice note"; a real one shows.
    func testMacDropNeverTitlesAMessengerName() {
        func title(_ working: String) -> String {
            let raw = NoteTitle.importFileName(metadataJSON: nil, workingFilename: working, isCapture: false)
            return NoteTitle.display(userTitle: nil, suggestedTitle: nil, body: nil, shared: nil,
                                     importFileName: raw, emptyFallback: "Voice note")
        }
        for name in machineNames { XCTAssertEqual(title(name), "Voice note", name) }
        XCTAssertEqual(title("kiln idea.m4a"), "kiln idea")
        // Words always win over any file name.
        XCTAssertEqual(NoteTitle.display(userTitle: nil, suggestedTitle: nil, body: "So we met at noon",
                                         shared: nil, importFileName: "PTT-20241003-WA0007.opus",
                                         emptyFallback: "Voice note"), "So we met at noon")
    }

    /// Every door agrees: the share sheet's `clipTitle` and the importers' `importName` give the
    /// same yes/no on a messenger or machine name.
    func testShareSheetAndImportersAgree() {
        for name in machineNames + ["kiln idea.m4a", "Rua Augusta 12.m4a"] {
            XCTAssertEqual(IngressDispatch.clipTitle(name) == nil, NoteTitle.importName(name) == nil, name)
        }
    }
}
