import os

/// The Mac's shared loggers. One construction per category instead of one per call site
/// (16 inline `Logger(subsystem: "com.skrift.desktop", category: "cloudkit")` before Q242).
enum AppLog {
    /// Everything CloudKit: the reconcile sweep, the cloud adapters, write-backs.
    static let cloudkit = Logger(subsystem: "com.skrift.desktop", category: "cloudkit")
}
