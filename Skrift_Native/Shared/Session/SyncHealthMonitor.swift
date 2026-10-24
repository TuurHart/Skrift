import Foundation
import CloudKit
import CoreData
import SwiftData
import Observation

/// Feeds `SyncHealth` on both apps (C155, R47, D217): local saves to the CloudKit store become
/// pending notes, every finished export clears or fails them, and the account check notices a
/// different iCloud account. Persisted on every change (`SyncHealthStore`), so a stop survives a
/// relaunch (D218: the store still opens with CloudKit; the stop gates Skrift's own sync work).
///
/// Inert until `attach`: hosted tests, headless runs and the perf library never attach.
@MainActor @Observable
final class SyncHealthMonitor {
    static let shared = SyncHealthMonitor()

    private(set) var health: SyncHealth
    /// Re-read when a pending note's grace runs out, so its pill appears without another event.
    private(set) var now = Date()

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var tick: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults
    /// Each app's own log (the phone's DevLog trace, the Mac's AppLog), set before `attach`.
    @ObservationIgnored var log: (String) -> Void = { _ in }
    /// Called when syncing stops or resumes (the Mac voids its first-import stamp on a stop).
    @ObservationIgnored var onStopChanged: (Bool) -> Void = { _ in }
    /// Called when the problem the banner shows changes (the Mac's Settings row follows it).
    @ObservationIgnored var onProblemChanged: () -> Void = {}

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        health = SyncHealthStore.load(defaults)
    }

    var isStopped: Bool { health.isStopped }
    var unsynced: Set<UUID> { health.unsynced(now: now) }
    func banner(device: String) -> SyncHealth.Banner? { health.banner(unsyncedCount: unsynced.count, device: device) }
    func noteLine(for id: UUID) -> String? {
        unsynced.contains(id) ? "\(SyncHealth.pillText) · \(health.noteReason)" : nil
    }

    /// Start watching `container` (the app's CloudKit store). Called once, after it opened.
    func attach(_ container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] note in
            let ids = SyncHealthSaves.identifiers(in: note)
            let saver = (note.object as? ModelContext)?.container
            MainActor.assumeIsolated { self?.saved(ids, in: saver) }
        })
        observers.append(nc.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification,
                                        object: nil, queue: .main) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  event.type == .export, event.endDate != nil else { return }
            let started = event.startDate
            let error = event.succeeded ? nil : (event.error ?? CKError(.internalError))
            MainActor.assumeIsolated { self?.exportEnded(startedAt: started, error: error) }
        })
        for name in [Notification.Name.CKAccountChanged, .NSUbiquityIdentityDidChange] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkAccount() }
            })
        }
        checkAccount()
        scheduleTick()
    }

    private func saved(_ ids: [PersistentIdentifier], in saver: ModelContainer?) {
        guard let container, saver === container, !ids.isEmpty else { return }
        let notes = SyncHealthSaves.noteIDs(for: ids, in: container.mainContext)
        guard !notes.isEmpty else { return }
        update { $0.noteChanged(notes, at: Date()) }
    }

    private func exportEnded(startedAt: Date, error: Error?) {
        if let error {
            let ns = error as NSError
            log("sync health: export failed \(ns.domain) \(ns.code) \(ns.userInfo)")
        }
        update { $0.exportEnded(startedAt: startedAt, error: error) }
    }

    /// `CKContainer.userRecordID` names the account (one per Apple ID, per container).
    func checkAccount() {
        Task { [weak self] in
            let ck = CKContainer(identifier: SkriftCloudContainer.id)
            let status = try? await ck.accountStatus()
            let account: SyncHealth.Account
            switch status {
            case .available?:
                if let id = try? await ck.userRecordID() { account = .available(recordName: id.recordName) }
                else { account = .unknown }
            case .noAccount?: account = .noAccount
            default: account = .unknown
            }
            self?.update { $0.accountSeen(account) }
        }
    }

    /// D218: the user's tap on the Mac, never automatic. Adopts the new account; the caller then
    /// copies its rows (`ReconcileV2.AccountCopy`).
    func adoptCurrentAccount() {
        update { $0.adoptCurrentAccount() }
    }

    #if DEBUG
    /// Headless snapshots draw a given state (never saved, nothing attached).
    func debugInject(_ h: SyncHealth, now: Date = Date()) { health = h; self.now = now }
    #endif

    private func update(_ change: (inout SyncHealth) -> Void) {
        var next = health
        change(&next)
        guard next != health else { return }
        let stopChanged = next.isStopped != health.isStopped
        let problemBefore = health.problem
        if stopChanged {
            log("sync health: syncing \(next.isStopped ? "STOPPED (account switch)" : "resumed")")
        }
        health = next
        SyncHealthStore.save(next, defaults)
        SyncStopFlag.isStopped = next.isStopped
        if stopChanged { onStopChanged(next.isStopped) }
        if next.problem != problemBefore { onProblemChanged() }
        now = Date()
        scheduleTick()
    }

    /// Wake when the oldest still-fresh pending change turns late (`SyncHealth.grace`).
    private func scheduleTick() {
        tick?.cancel()
        let due = health.pending.values.map { $0.addingTimeInterval(SyncHealth.grace) }.filter { $0 > Date() }.min()
        guard let due else { return }
        tick = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, due.timeIntervalSinceNow + 0.5)))
            guard !Task.isCancelled else { return }
            self?.now = Date()
            self?.scheduleTick()
        }
    }
}
