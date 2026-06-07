import Foundation
import SwiftData

/// Test-only data seeder for the XCUITest harness. Gated on launch flags and
/// idempotent (skips if memos already exist). **Not for production.**
@MainActor
enum DemoDataSeeder {
    static func seedIfRequested(_ repo: NotesRepository) {
        guard LaunchFlags.seedDemoMemos else { return }
        guard repo.allMemos().isEmpty else { return }
        for memo in demoMemos() { repo.insert(memo) }
    }

    static func demoMemos() -> [Memo] {
        let now = Date()
        return [
            Memo(
                audioFilename: "memo_demo1.m4a",
                duration: 134,
                recordedAt: now.addingTimeInterval(-3_600),
                tags: ["ideas"],
                syncStatus: .waiting,
                transcript: "First seeded memo about the harbor at dawn.",
                transcriptStatus: .done,
                transcriptConfidence: 0.92,
                metadata: MemoMetadata(
                    capturedAt: ISO8601.string(from: now.addingTimeInterval(-3_600)),
                    location: LocationInfo(latitude: 38.71, longitude: -9.14, placeName: "Alfama, Lisbon"),
                    dayPeriod: .morning,
                    steps: 1_200,
                    tags: ["ideas"]
                )
            ),
            Memo(
                audioFilename: "memo_demo2.m4a",
                duration: 47,
                recordedAt: now.addingTimeInterval(-7_200),
                tags: [],
                syncStatus: .synced,
                transcript: "Second seeded memo, a quick reminder to call the plumber.",
                transcriptStatus: .done,
                transcriptConfidence: 0.81
            ),
            Memo(
                audioFilename: "memo_demo3.m4a",
                duration: 12,
                recordedAt: now.addingTimeInterval(-90_000),
                tags: ["todo", "house"],
                syncStatus: .waiting,
                transcriptStatus: .pending
            ),
            // Status-pill coverage: a transcribing one and a failed one (oldest,
            // so the row-0 assertions in other tests stay stable).
            Memo(
                audioFilename: "memo_demo4.m4a",
                duration: 33,
                recordedAt: now.addingTimeInterval(-100_000),
                syncStatus: .waiting,
                transcriptStatus: .transcribing
            ),
            Memo(
                audioFilename: "memo_demo5.m4a",
                duration: 18,
                recordedAt: now.addingTimeInterval(-110_000),
                syncStatus: .waiting,
                transcriptStatus: .failed
            ),
        ]
    }
}
