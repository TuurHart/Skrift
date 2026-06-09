import Foundation
import SwiftData

/// Test-only data seeder for the XCUITest harness. Gated on launch flags and
/// idempotent (skips if memos already exist). **Not for production.**
@MainActor
enum DemoDataSeeder {
    static func seedIfRequested(_ repo: NotesRepository) {
        guard repo.allMemos().isEmpty else { return }
        if LaunchFlags.seedLongMemo { repo.insert(longMemo()); return }
        guard LaunchFlags.seedDemoMemos else { return }
        for memo in demoMemos() { repo.insert(memo) }
    }

    /// One memo whose transcript is long enough to scroll content (text + an image
    /// placeholder) UNDER the glass player bar — for the glass-refraction screenshot.
    static func longMemo() -> Memo {
        let now = Date()
        let body = (1...18).map { "Line \($0): the harbour was quiet at dawn and the light came in sideways across the water." }
            .joined(separator: "\n\n")
        return Memo(
            audioFilename: "memo_long.m4a",
            duration: 240,
            recordedAt: now,
            tags: ["glass"],
            syncStatus: .waiting,
            transcript: body + "\n\n[[img_001]]\n\n" + "And then the ferry crossed and everyone went quiet.",
            transcriptStatus: .done,
            transcriptConfidence: 0.95,
            metadata: MemoMetadata(
                capturedAt: ISO8601.string(from: now),
                imageManifest: [ImageManifestEntry(filename: "missing_glass_demo.jpg", offsetSeconds: 30)]
            )
        )
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
