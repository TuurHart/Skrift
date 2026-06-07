import Foundation
import SwiftData

/// Seeds a handful of representative notes into an empty store so the review UI
/// renders during development (before `BatchRunner` → SwiftData wiring lands).
/// No-op once any real note exists.
enum DemoSeed {
    @MainActor
    static func seedIfEmpty(_ ctx: ModelContext) {
        let existing = (try? ctx.fetch(FetchDescriptor<PipelineFile>())) ?? []
        guard existing.isEmpty else { return }
        for f in demoFiles() { ctx.insert(f) }
        try? ctx.save()
    }

    /// Detached demo objects (no ModelContext) for headless `ImageRenderer` snapshots.
    static func snapshotFiles() -> [PipelineFile] { demoFiles() }

    private static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12) -> Date {
        var c = DateComponents(); c.year = y; c.month = mo; c.day = d; c.hour = h
        return Calendar.current.date(from: c) ?? Date()
    }

    private static func meta(_ dict: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: dict)
    }

    private static func demoFiles() -> [PipelineFile] {
        // 1 — Ready voice memo, full content for the later build chunks.
        let f1 = PipelineFile(id: "demo-1", filename: "Voice Memo 09-14.m4a", sourceType: .audio, uploadedAt: date(2026, 6, 6, 9))
        f1.transcribeStatus = .done; f1.sanitiseStatus = .done; f1.enhanceStatus = .done
        f1.enhancedTitle = "Rethinking the desktop rewrite as one native app"
        f1.titleSuggested = f1.enhancedTitle
        f1.enhancedSummary = "Reflecting on collapsing the two-process app into one native Swift process — leaning toward FluidAudio plus mlx-swift in-process, and what that means for the sync with the phone."
        f1.sanitised = """
        So I was talking with [[Nick Jansen]] this morning about collapsing the whole thing into one native app. Jack brought the new mock and we argued about the sidebar for an hour — het voelt nu eindelijk goed, no Python backend that won't start.

        Later Jack texted that the build's green again. De transcription en de enhancement draaien al, dus de vraag is echt hoe de review-kant aanvoelt.

        Idea: keep the body exactly what exports to Obsidian — brackets visible, karaoke on the real words. If Sam can test it next week, even better.
        """
        f1.enhancedCopyedit = f1.sanitised
        f1.tags = ["work", "ideas"]
        f1.tagSuggestions = ["rewrite", "swift"]
        f1.significance = 0.7
        f1.audioMetadataJSON = meta([
            "duration": "00:02:14",
            "phone_location": ["placeName": "Amsterdam"],
            "phone_weather": ["conditions": "Cloudy", "temperature": 14, "temperatureUnit": "°C"],
        ])
        // Ambiguous names for the review resolver: "Sam" (one mention, two people)
        // and "Jack" (two mentions — the smart per-occurrence case).
        let samCands = [NameCandidate(id: "1", canonical: "[[Sam Smith]]", short: "Sam"),
                        NameCandidate(id: "2", canonical: "[[Sam Jones]]", short: "Sam")]
        let jackCands = [NameCandidate(id: "3", canonical: "[[Jack Timmons]]", short: "Jack"),
                         NameCandidate(id: "4", canonical: "[[Jack de Vries]]", short: "Jack")]
        f1.ambiguousNames = [
            AmbiguousOccurrence(alias: "Sam", offset: 300, length: 3, contextBefore: "If ", contextAfter: " can test it", candidates: samCands),
            AmbiguousOccurrence(alias: "Jack", offset: 40, length: 4, contextBefore: "met with ", contextAfter: " about the plan", candidates: jackCands),
            AmbiguousOccurrence(alias: "Jack", offset: 180, length: 4, contextBefore: "and then ", contextAfter: " said he'd help", candidates: jackCands),
        ]

        // 2 — Ready shared PDF (phone capture, no audio).
        let f2 = PipelineFile(id: "demo-2", filename: "Project brief.pdf", sourceType: .capture, uploadedAt: date(2026, 6, 6, 11))
        f2.transcribeStatus = .skipped; f2.sanitiseStatus = .done; f2.enhanceStatus = .done
        f2.enhancedTitle = "Project brief.pdf"
        f2.audioMetadataJSON = meta(["shared_content": ["type": "file"], "source": "phone"])

        // 3 — Exported shared link.
        let f3 = PipelineFile(id: "demo-3", filename: "shared-link.url", sourceType: .capture, uploadedAt: date(2026, 6, 5, 16))
        f3.transcribeStatus = .skipped; f3.sanitiseStatus = .done; f3.enhanceStatus = .done; f3.exportStatus = .done
        f3.enhancedTitle = "SwiftUI rich text — shared link"
        f3.audioMetadataJSON = meta(["shared_content": ["type": "url"]])

        // 4 — Mid-enhancement voice memo.
        let f4 = PipelineFile(id: "demo-4", filename: "Standup notes.m4a", sourceType: .audio, uploadedAt: Date())
        f4.transcribeStatus = .done; f4.enhanceStatus = .processing
        f4.enhancedTitle = "Standup notes"
        f4.audioMetadataJSON = meta(["duration": "00:01:02"])

        // 5 — Queued voice memo (waiting to be processed).
        let f5 = PipelineFile(id: "demo-5", filename: "Voice memo 14:02.m4a", sourceType: .audio, uploadedAt: Date())
        f5.audioMetadataJSON = meta(["duration": "00:00:48"])

        // 6 — Exported Apple Note.
        let f6 = PipelineFile(id: "demo-6", filename: "Groceries en het plan.md", sourceType: .note, uploadedAt: date(2026, 6, 3, 18))
        f6.transcribeStatus = .done; f6.sanitiseStatus = .done; f6.enhanceStatus = .done; f6.exportStatus = .done
        f6.enhancedTitle = "Groceries en het plan"

        return [f1, f2, f3, f4, f5, f6]
    }
}
