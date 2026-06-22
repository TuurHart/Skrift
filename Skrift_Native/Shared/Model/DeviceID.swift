import Foundation

/// A stable per-install identifier, used to mark which device recorded a memo
/// (`Memo.recordingDeviceID`). With CloudKit sync, a memo can arrive on another
/// device still `.transcribing`; the receiver must NOT re-transcribe it (the
/// recording device owns that, and its transcript will sync) — so the stuck-
/// transcription recovery only acts on memos this device recorded (or legacy
/// memos with no id). Persisted once in UserDefaults; survives relaunches, distinct
/// per device.
enum DeviceID {
    static let defaultsKey = "skriftDeviceID"

    static func current(defaults: UserDefaults = .standard) -> String {
        if let id = defaults.string(forKey: defaultsKey) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: defaultsKey)
        return id
    }
}
