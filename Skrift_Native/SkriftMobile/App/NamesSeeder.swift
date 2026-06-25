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
        let now = ISO8601.now()
        if LaunchFlags.seedNameLinking {
            // The mock's roster: two Jacks (ambiguous), distinctive Hendri (auto-links),
            // common-word Rose (suggested).
            NamesStore.shared.save(NamesData(lastModifiedAt: now, people: [
                Person(canonical: "[[Jack Hutton]]", aliases: ["Jack"], short: nil, lastModifiedAt: now),
                Person(canonical: "[[Jack Tanner]]", aliases: ["Jack"], short: nil, lastModifiedAt: now),
                Person(canonical: "[[Hendri van Niekerk]]", aliases: ["Hendri"], short: "Hendri", lastModifiedAt: now),
                Person(canonical: "[[Rose]]", aliases: ["Rose"], short: "Rose", lastModifiedAt: now),
            ]))
            return
        }
        guard LaunchFlags.seedDemoNames else { return }
        NamesStore.shared.save(NamesData(lastModifiedAt: now, people: [
            Person(canonical: "[[Jane Doe]]", aliases: ["Janey"], short: "Jane",
                   voiceEmbeddings: [VoiceEmbedding(vector: [0.1, 0.2, 0.3], condition: "demo", addedAt: now)],
                   lastModifiedAt: now),
            Person(canonical: "[[Bob Smith]]", aliases: ["Bobby"], short: "Bob", lastModifiedAt: now),
        ]))
    }
}
