import Foundation

/// Who may re-run a memo stuck in `.transcribing` — the ONE age rule both apps use
/// (C264, C154, C97, R75).
///
/// - This device's own memos (and legacy memos with no `recordingDeviceID`) are
///   recoverable at once: no transcription `Task` survives a relaunch, so a memo still
///   `.transcribing` at launch is orphaned by definition.
/// - Another device's memo is in flight on THAT device (C97) until it has been quiet for
///   `takeoverAge`. After that the owner is taken to be gone (wiped, sold, never opened
///   again), and any device may adopt it (C154) — the phone at launch, the Mac sweep as
///   the backstop — so it never spins forever (C264).
///
/// The quiet clock is `Memo.lastEditedAt`: a new memo is stamped at creation, and an
/// append stamps `editedAt` when it flips the memo back to `.transcribing`.
/// The callers still check the rest: audio present, and never a `transcriptUserEdited`
/// memo (C263).
enum OrphanedTranscribing {
    /// C154: another device's `.transcribing` memo is taken over after 30 minutes.
    static let takeoverAge: TimeInterval = 30 * 60

    /// True when `memo` is `.transcribing` and THIS device may recover it now.
    static func mayRecover(_ memo: Memo, thisDevice: String = DeviceID.current(), now: Date = Date()) -> Bool {
        memo.transcriptStatus == .transcribing
            && mayRecover(recordingDeviceID: memo.recordingDeviceID, quietSince: memo.lastEditedAt,
                          thisDevice: thisDevice, now: now)
    }

    /// The rule on plain values.
    static func mayRecover(recordingDeviceID: String?, quietSince: Date,
                           thisDevice: String, now: Date) -> Bool {
        if recordingDeviceID == nil || recordingDeviceID == thisDevice { return true }
        return now.timeIntervalSince(quietSince) >= takeoverAge
    }
}
