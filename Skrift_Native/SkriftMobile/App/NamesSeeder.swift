import Foundation

/// Test-only names seeder. On `-seedDemoNames` it OVERWRITES the local names.json
/// with a deterministic set (reset + seed) so the Names UI test starts from a
/// known state every launch. **Not for production.**
@MainActor
enum NamesSeeder {
    static func seedIfRequested() {
        if LaunchFlags.resetNames {
            NamesStore.shared.save(NamesData(lastModifiedAt: ISO8601.now(), people: []))
        }
        guard LaunchFlags.seedDemoNames else { return }
        let now = ISO8601.now()
        NamesStore.shared.save(NamesData(lastModifiedAt: now, people: [
            Person(canonical: "[[Jane Doe]]", aliases: ["Janey"], short: "Jane",
                   voiceEmbeddings: [VoiceEmbedding(vector: [0.1, 0.2, 0.3], condition: "demo", addedAt: now)],
                   lastModifiedAt: now),
            Person(canonical: "[[Bob Smith]]", aliases: ["Bobby"], short: "Bob", lastModifiedAt: now),
        ]))
    }
}
