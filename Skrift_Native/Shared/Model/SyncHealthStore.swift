import Foundation

/// Where `SyncHealth` lives between launches: one JSON value in this app's own defaults (Dev and
/// prod have separate containers, so separate records).
enum SyncHealthStore {
    static let key = "syncHealth.v1"

    static func load(_ defaults: UserDefaults = .standard) -> SyncHealth {
        guard let data = defaults.data(forKey: key),
              let health = try? JSONDecoder().decode(SyncHealth.self, from: data) else { return SyncHealth() }
        return health
    }

    static func save(_ health: SyncHealth, _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(health) { defaults.set(data, forKey: key) }
    }
}
