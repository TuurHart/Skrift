import XCTest
import CoreLocation
@testable import SkriftMobile

/// Onboarding's permission cards show a check only for a real grant (Q173 / P74).
final class OnboardingPermissionStateTests: XCTestCase {
    func testMediaGrantedOnlyWhenBothGranted() {
        XCTAssertEqual(OnboardingPermissionState.media(microphone: true, camera: true), .granted)
    }

    func testMediaDeniedWhenEitherRefused() {
        XCTAssertEqual(OnboardingPermissionState.media(microphone: false, camera: true), .denied)
        XCTAssertEqual(OnboardingPermissionState.media(microphone: true, camera: false), .denied)
        XCTAssertEqual(OnboardingPermissionState.media(microphone: false, camera: false), .denied)
    }

    func testMediaNotAskedWhileUnanswered() {
        XCTAssertEqual(OnboardingPermissionState.media(microphone: nil, camera: nil), .notAsked)
        XCTAssertEqual(OnboardingPermissionState.media(microphone: true, camera: nil), .notAsked)
    }

    func testLocationFollowsAuthorizationStatus() {
        XCTAssertEqual(OnboardingPermissionState.location(.notDetermined), .notAsked)
        XCTAssertEqual(OnboardingPermissionState.location(.authorizedWhenInUse), .granted)
        XCTAssertEqual(OnboardingPermissionState.location(.authorizedAlways), .granted)
        XCTAssertEqual(OnboardingPermissionState.location(.denied), .denied)
        XCTAssertEqual(OnboardingPermissionState.location(.restricted), .denied)
    }
}
