import XCTest
import AVFoundation
@testable import SkriftMobile

final class RouteChangeNameTests: XCTestCase {

    func testEveryDocumentedReasonHasItsName() {
        let expected: [(UInt, String)] = [
            (0, "unknown"),
            (1, "newDeviceAvailable"),
            (2, "oldDeviceUnavailable"),
            (3, "categoryChange"),
            (4, "override"),
            (6, "wakeFromSleep"),
            (7, "noSuitableRouteForCategory"),
            (8, "routeConfigurationChange"),
        ]
        for (raw, name) in expected {
            XCTAssertEqual(RouteChangeName.reason(rawValue: raw), name, "raw \(raw)")
        }
    }

    func testEnumOverloadMatchesRawOverload() {
        XCTAssertEqual(RouteChangeName.reason(.categoryChange), "categoryChange")
        XCTAssertEqual(RouteChangeName.reason(.routeConfigurationChange), "routeConfigurationChange")
    }

    func testMissingOrUndocumentedReasonIsUnknown() {
        XCTAssertEqual(RouteChangeName.reason(rawValue: nil), "unknown")
        XCTAssertEqual(RouteChangeName.reason(rawValue: 99), "unknown(99)")
    }

    func testNeverPrintsTheRawEnumDescription() {
        for raw in UInt(0)...10 {
            XCTAssertFalse(RouteChangeName.reason(rawValue: raw).contains("rawValue"), "raw \(raw)")
        }
    }

    func testCategoryAndModeLoseTheirAVAudioSessionPrefix() {
        XCTAssertEqual(RouteChangeName.category(.playAndRecord), "PlayAndRecord")
        XCTAssertEqual(RouteChangeName.category(.playback), "Playback")
        XCTAssertEqual(RouteChangeName.mode(.default), "Default")
        XCTAssertEqual(RouteChangeName.mode(.spokenAudio), "SpokenAudio")
        XCTAssertEqual(RouteChangeName.strip("Custom", prefix: "AVAudioSessionMode"), "Custom")
    }
}
