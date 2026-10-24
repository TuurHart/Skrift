import Foundation
import os

/// The one fact every sync gate reads, from any thread (C155, R47): syncing is stopped because the
/// device is on a different iCloud account. `SyncHealthMonitor` keeps it current.
enum SyncStopFlag {
    private static let state = OSAllocatedUnfairLock(initialState: SyncHealthStore.load().isStopped)

    static var isStopped: Bool {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}
