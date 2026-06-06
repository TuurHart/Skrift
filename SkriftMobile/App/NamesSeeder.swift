import Foundation

/// Test-only names seeder. On `-seedDemoNames` it OVERWRITES the local names.json
/// with a deterministic set (reset + seed) so the Names UI test starts from a
/// known state every launch. **Not for production.**
@MainActor
enum NamesSeeder {
    static func seedIfRequested() {
        guard LaunchFlags.seedDemoNames else { return }
        let now = ISO8601.now()
        NamesStore.shared.save(NamesData(lastModifiedAt: now, people: [
            Person(canonical: "[[Jane Doe]]", aliases: ["Janey"], short: "Jane", lastModifiedAt: now),
            Person(canonical: "[[Bob Smith]]", aliases: ["Bobby"], short: "Bob", lastModifiedAt: now),
        ]))
    }
}
