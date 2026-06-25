import Foundation
import SwiftData
import UIKit

/// Test-only data seeder for the XCUITest harness. Gated on launch flags and
/// idempotent (skips if memos already exist). **Not for production.**
@MainActor
enum DemoDataSeeder {
    /// Fixed id for the name-linking demo memo so the screenshot route can open it directly.
    static let nameLinkingMemoID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    static func seedIfRequested(_ repo: NotesRepository) {
        guard repo.allMemos().isEmpty else { return }
        if LaunchFlags.seedLongMemo { repo.insert(longMemo()); return }
        if LaunchFlags.seedConversationMemo { repo.insert(conversationMemo()); return }
        if LaunchFlags.seedVideoMemo { repo.insert(videoMemo()); return }
        if LaunchFlags.seedNameLinking { repo.insert(nameLinkingMemo()); return }
        guard LaunchFlags.seedDemoMemos else { return }
        for memo in demoMemos() { repo.insert(memo) }
    }

    /// The mock's "Studio afternoon" memo (`mocks/phone-name-linking.html`): "Jack" is
    /// shared by two roster people (ambiguous), "Hendri" is distinctive (auto-linked),
    /// "Rose" is a common word (suggested), "Marcus" isn't on the roster (plain). Seeded
    /// with `NamesSeeder`'s matching roster under `-seedNameLinking`.
    static func nameLinkingMemo() -> Memo {
        let now = Date()
        let transcript = """
        Met up with Jack this morning at the studio and we ran the whole set twice. \
        Hendri wants the commonplace angle up front, so I'll carve out an hour for it tomorrow.

        Later Rose dropped by with the proofs — she thinks the cover's nearly there. \
        Hendri said he'd loop in Marcus from the print shop, but I still owe him the final spreads.
        """
        return Memo.make(
            id: nameLinkingMemoID,
            audioFilename: "memo_\(nameLinkingMemoID.uuidString).m4a",
            duration: 96,
            recordedAt: now,
            tags: ["studio"],
            syncStatus: .waiting,
            title: "Studio afternoon",
            transcript: transcript,
            transcriptStatus: .done,
            transcriptConfidence: 0.95,
            significance: 0.5,
            metadata: MemoMetadata(capturedAt: ISO8601.string(from: now), dayPeriod: .afternoon)
        )
    }

    /// One VIDEO-import memo with a REAL PORTRAIT (9:16, 1080×1920 — like an iPhone
    /// clip) frame written to the recordings dir, so the video source glyph + the
    /// inline-image aspect handling are screenshot-verifiable. The frame draws a
    /// centered circle: a correct aspect-preserving render keeps it circular, a
    /// stretch (the device "wider than it needs to be" bug, when the editor capped
    /// the height but pinned full width) turns it into a wide ellipse.
    static func videoMemo() -> Memo {
        let id = UUID()
        let photoName = "photo_\(id.uuidString)_001.jpg"
        writePortraitDiagnosticFrame(to: AppPaths.recordingsDirectory.appendingPathComponent(photoName))
        return Memo.make(
            id: id,
            audioFilename: "memo_\(id.uuidString).m4a",
            duration: 42,
            recordedAt: Date().addingTimeInterval(-5_400),
            syncStatus: .waiting,
            transcript: "[[img_001]]\n\nAdvice to my future self, recorded as a video on the balcony.",
            transcriptStatus: .done,
            transcriptConfidence: 0.9,
            metadata: MemoMetadata(
                imageManifest: [ImageManifestEntry(filename: photoName, offsetSeconds: 0)],
                sourceType: MemoMetadata.Source.video
            )
        )
    }

    /// Draw a 1080×1920 (9:16 portrait) JPEG: a centered circle + corner ticks, so any
    /// horizontal stretch reads as an obvious wide ellipse in the thumbnail/embed.
    private static func writePortraitDiagnosticFrame(to url: URL) {
        let size = CGSize(width: 1080, height: 1920)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor(red: 0.10, green: 0.16, blue: 0.22, alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            // Centered circle — diameter 760, fits the center-crop square.
            let d: CGFloat = 760
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineWidth(28)
            cg.strokeEllipse(in: CGRect(x: (size.width - d) / 2, y: (size.height - d) / 2, width: d, height: d))
            // Corner ticks so left/right cropping (vs squishing) is also visible.
            cg.setFillColor(UIColor.systemTeal.cgColor)
            for x in [CGFloat(40), size.width - 120] {
                cg.fill(CGRect(x: x, y: 40, width: 80, height: 80))
            }
        }
        try? image.jpegData(compressionQuality: 0.9)?.write(to: url)
    }

    /// A speaker-attributed (`**Name:**`) conversation memo — one tagged speaker + one
    /// still "Speaker 2" — so the detail's `SpeakerTurnsView` render is verifiable.
    static func conversationMemo() -> Memo {
        let now = Date()
        let transcript = """
        **Tiuri Hartog:** If conversation mode works, if I talk, then what if you talk?

        **Speaker 2:** And now if I talk, it will only split it afterwards I'm assuming, but not yeah.

        **Tiuri Hartog:** I don't know. I'm not too sure yet. Supposedly parakeet can do conversation mode.

        **Speaker 2:** Yeah, but can we split the conversation during this pre-recording as well? Because now you'll see if it saves. But it would be cool if it noticed while you were talking.
        """
        return Memo.make(
            audioFilename: "memo_conversation.m4a",
            duration: 28,
            recordedAt: now,
            tags: ["conversation"],
            syncStatus: .waiting,
            transcript: transcript,
            transcriptStatus: .done,
            transcriptConfidence: 0.95,
            metadata: MemoMetadata(capturedAt: ISO8601.string(from: now),
                                   location: LocationInfo(latitude: 38.71, longitude: -9.14, placeName: "Alfama, Lisbon"))
        )
    }

    /// One memo whose transcript is long enough to scroll content (text + an image
    /// placeholder) UNDER the glass player bar — for the glass-refraction screenshot.
    static func longMemo() -> Memo {
        let now = Date()
        let body = (1...18).map { "Line \($0): the harbour was quiet at dawn and the light came in sideways across the water." }
            .joined(separator: "\n\n")
        return Memo.make(
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
            Memo.make(
                audioFilename: "memo_demo1.m4a",
                duration: 134,
                recordedAt: now.addingTimeInterval(-3_600),
                tags: ["ideas"],
                syncStatus: .waiting,
                transcript: "First seeded memo about the harbor at dawn.",
                transcriptStatus: .done,
                transcriptConfidence: 0.92,
                significance: 0.5,
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
                transcriptConfidence: 0.81,
                significance: 0.5
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
