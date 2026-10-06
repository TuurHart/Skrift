import Foundation
import CloudKit
import CoreData
import Observation
import AppKit

/// Reads the Mac's iCloud sync state for display (Q327, D182, mock `Q162-mac-icloud-state.html`).
/// Three inputs, none of which anything on the Mac read for display before:
///   - the `cloudKitMacSync` switch (settings.json),
///   - whether `MemoCloudStore.container` opened (nil = "Couldn't start"),
///   - `CKContainer.accountStatus` (signed out / restricted).
/// Plus CloudKit event traffic (`NSPersistentCloudKitContainer.eventChangedNotification`), the same
/// rule the phone's `CloudSyncMonitor` uses: in flight → syncing, hidden after one quiet second.
/// The sync-off Mac never touches `MemoCloudStore.container` (it would build CloudKit), nor asks
/// for the account.
@MainActor @Observable
final class MacSyncMonitor {
    static let shared = MacSyncMonitor()

    private(set) var state: MacSyncState = .upToDate
    private(set) var failureDetail = MacSyncState.failureDetail(account: .unknown)

    private var switchOn = true
    private var account: MacSyncAccount = .unknown
    private var inFlight: Set<UUID> = []
    private var syncing = false
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        // Hosted tests, headless snapshots and the perf library never talk to real CloudKit.
        var inert = LaunchArgs.isXCTest || HeadlessIsolation.isRequested()
        #if DEBUG
        if PerfLibrary.isActive { inert = true }
        #endif
        guard !inert else { return }

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification,
                                        object: nil, queue: .main) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            let id = event.identifier
            let ended = event.endDate != nil
            MainActor.assumeIsolated { self?.apply(id: id, ended: ended) }
        })
        observers.append(nc.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        observers.append(nc.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        refresh()
    }

    /// Re-read the switch, the container and the account. `switchOn` lets Settings pass the value
    /// the user just flipped (the file may not be written yet).
    func refresh(switchOn newValue: Bool? = nil) {
        switchOn = newValue ?? SettingsStore.shared.load().cloudKitMacSyncEnabled
        guard switchOn else { recompute(); return }
        recompute()
        Task { [weak self] in
            let status = try? await CKContainer(identifier: MemoCloudStore.cloudContainerID).accountStatus()
            guard let self else { return }
            self.account = Self.map(status)
            self.recompute()
        }
    }

    static func map(_ status: CKAccountStatus?) -> MacSyncAccount {
        switch status {
        case .available:  return .available
        case .noAccount:  return .noAccount
        case .restricted: return .restricted
        default:          return .unknown   // nil, couldNotDetermine, temporarilyUnavailable
        }
    }

    private func apply(id: UUID, ended: Bool) {
        if ended { inFlight.remove(id) } else { inFlight.insert(id) }
        if !inFlight.isEmpty {
            hideTask?.cancel()
            syncing = true
            recompute()
        } else {
            // CloudKit fires import/export in bursts; hide only after a quiet second.
            hideTask?.cancel()
            hideTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.syncing = false
                self?.recompute()
            }
        }
    }

    private func recompute() {
        let opened = switchOn ? (MemoCloudStore.container != nil) : true
        let new = MacSyncState.resolve(switchOn: switchOn, containerOpened: opened,
                                       account: account, inFlight: syncing)
        let detail = MacSyncState.failureDetail(account: account)
        if state != new { state = new }
        if failureDetail != detail { failureDetail = detail }
    }
}
