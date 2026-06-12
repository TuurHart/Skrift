import XCTest
@testable import SkriftMobile

final class NamesAutoSyncTests: XCTestCase {

    /// Rapid enrolls (naming several speakers in one conversation) must coalesce
    /// into ONE sync attempt — and an unpaired Mac (nil transport) is a no-op.
    @MainActor
    func testKicksCoalesceIntoOneAttempt() async {
        NamesAutoSync.debounce = .milliseconds(40)
        var providerCalls = 0
        for _ in 0..<5 {
            NamesAutoSync.kick(transportProvider: { providerCalls += 1; return nil })
        }
        await NamesAutoSync.flush()
        XCTAssertEqual(providerCalls, 1, "5 rapid kicks must coalesce into one debounced attempt")
    }
}
