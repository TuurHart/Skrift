import XCTest
import Foundation

/// The phone's `diarization` asset blob in its real wire shape (`DiarizationData` in
/// `SkriftMobile/Services/Diarization/DiarizationStore.swift`): `segments` + string-keyed
/// `slotNames` + optional `turnSlots`. Tests that need a phone blob build it here, so the
/// Mac never owns an encoder for it (Q213: the Mac writes no `diar_<id>.json`).
enum PhoneDiarizationFixture {
    private struct Wire: Encodable {
        let segments: [DiarizedSegment]
        let slotNames: [String: String]
        let turnSlots: [Int]?
    }

    static func blob(segments: [DiarizedSegment], slotNames: [String: String] = [:],
                     turnSlots: [Int]? = nil) throws -> Data {
        try JSONEncoder().encode(Wire(segments: segments, slotNames: slotNames, turnSlots: turnSlots))
    }
}

final class PhoneDiarizationBlobTests: XCTestCase {
    func testDecodesSegmentsAndIgnoresTheRestOfThePhoneBlob() throws {
        let segs = [DiarizedSegment(speaker: 0, start: 0, end: 1.5),
                    DiarizedSegment(speaker: 1, start: 1.5, end: 3.25)]
        let blob = try PhoneDiarizationFixture.blob(segments: segs,
                                                    slotNames: ["0": "Tiuri Hartog"], turnSlots: [0, 1, 0])
        XCTAssertEqual(try JSONDecoder().decode(PhoneDiarizationBlob.self, from: blob).segments, segs)
    }

    func testDecodesAnOldBlobWithoutTurnSlots() throws {
        let old = Data(#"{"segments":[{"speaker":0,"start":0.0,"end":1.0}],"slotNames":{}}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(PhoneDiarizationBlob.self, from: old).segments.count, 1)
    }

    func testGarbageBlobFailsToDecode() {
        XCTAssertNil(try? JSONDecoder().decode(PhoneDiarizationBlob.self, from: Data("not json".utf8)))
    }
}
