import Foundation

/// The CloudKit container identifier both apps use — the phone's SwiftData store, its raw
/// audiobook transport and the Mac's `MemoCloudStore` MUST all name the same container so
/// they share the user's private zone. Per-config like the entitlement: Debug = Dev,
/// Release = prod. One definition so the three can't drift.
enum SkriftCloudContainer {
    #if DEBUG
    static let id = "iCloud.com.skrift.mobile.dev"
    #else
    static let id = "iCloud.com.skrift.mobile"
    #endif
}
