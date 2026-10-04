import Foundation

/// PRIVACY: a headless `-snapshot*` render must never read Tuur's live Dev store (Q33 and
/// Q285 both put real note titles into PNGs). Every `-snapshot*` mode, plus `-isolatedRun`,
/// makes `SharedStore.container` and `MemoCloudStore.container` in-memory, so even a view
/// that reaches for a store directly sees an empty one; the renders then draw only
/// `DemoSeed` content. Pure so the host-less unit tests can drive it.
enum HeadlessIsolation {
    static func isRequested(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains { $0 == "-isolatedRun" || $0.hasPrefix("-snapshot") }
    }
}
