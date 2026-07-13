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

    #if DEBUG
    /// `-naming-demo`: a focused, self-consistent example for eyeballing the opt-out naming
    /// review (mocks/naming-review.html) in the LIVE NSTextView. Non-destructively upserts a
    /// small test roster into the dev names DB (so person links color + the popovers populate),
    /// then seeds ONE memo whose body is run through the REAL `Sanitiser` — so the linked /
    /// suggested / plain tiers + the `ambiguousNames` offsets are guaranteed consistent. Dev
    /// data only; the 6 test people are deletable in Settings → Names.
    @MainActor
    static func seedNamingDemo(_ ctx: ModelContext) {
        let roster: [(String, [String], String)] = [
            ("[[Hendri van Niekerk]]", ["Hendri"], "Hendri"),
            ("[[Bruno Aragorn]]", ["Bruno"], "Bruno"),
            ("[[Jack Hutton]]", ["Jack"], "Jack"),     // two Jacks → "Jack" is ambiguous
            ("[[Jack Tanner]]", ["Jack"], "Jack"),
            ("[[Rose Baker]]", ["Rose"], "Rose"),       // common word → suggested
            ("[[Will Smith]]", ["Will"], "Will"),       // common word → "will" stays plain
        ]
        for (c, a, s) in roster {
            NamesStore.shared.upsert(Person(canonical: c, aliases: a, short: s, lastModifiedAt: ISO8601.now()), replacing: nil)
        }
        // Reset on every launch so the demo always starts pristine (clears prior picks).
        let existing = (try? ctx.fetch(FetchDescriptor<PipelineFile>())) ?? []
        for old in existing where old.id == "naming-demo" { ctx.delete(old) }

        let text = "Long studio session today. Hendri showed up early and we nailed the mix with Bruno. Then Jack swung by with notes — sharp as ever. Hendri reckons we're close to done. I'll send Rose the stems tonight, and I will double-check the levels. Mariam wants in on the next one."
        let f = PipelineFile(id: "naming-demo", filename: "Naming demo.m4a", sourceType: .audio, uploadedAt: Date())
        f.transcript = text
        f.enhancedCopyedit = text
        f.enhancedTitle = "Naming review demo"
        f.titleSuggested = f.enhancedTitle
        f.enhancedSummary = "Tap a tan dotted name (Jack / Rose) to pick a person; click a purple linked name (Hendri / Bruno) to unlink or change it."
        let san = Sanitiser.process(text: text, people: NamesStore.shared.livePeople())
        f.sanitised = san.sanitised
        f.ambiguousNames = san.ambiguous.isEmpty ? nil : san.ambiguous
        f.transcribeStatus = .done; f.sanitiseStatus = .done; f.enhanceStatus = .done
        f.tags = ["demo"]
        f.compiledText = Compiler.compile(file: f, author: SettingsStore.shared.load().authorName,
                                          knownPeople: NamesStore.shared.livePeople())
        f.audioMetadataJSON = meta(["duration": "00:01:30"])
        ctx.insert(f)
        try? ctx.save()
    }
    #endif

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

        Same trust-gate reasoning as [[memo:9E8B7C6D-1111-4222-8333-444455556666|Late-night audiobook capture flow]] — worth re-reading before the build.

        Prep before the push:
        - [x] Bump the build number
        - [ ] Archive from Organizer (CLI export fails)
        - [ ] Verify vocab sync on both devices
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

        // 2 — Ready url capture (CAPTURE_CONTRACT.md literal fixture, C3).
        // This is the item shown in the -snapshot-capture flag (mock state 3).
        let f2 = PipelineFile(id: "demo-capture-url", filename: "capture_2026-06-11",
                              sourceType: .capture, uploadedAt: date(2026, 6, 11, 14))
        f2.transcribeStatus = .done; f2.sanitiseStatus = .done; f2.enhanceStatus = .done
        f2.enhancedTitle = "Rich text editing in SwiftUI"
        f2.titleSuggested = "Rich text editing in SwiftUI"
        f2.enhancedSummary = "A note about the desktop body editor — the NSTextView approach Nick suggested for attributed-string round-tripping."
        // sanitised = annotation with name-link (Nick Jansen linked).
        f2.sanitised = "Try this for the desktop body editor — the NSTextView part maps onto what [[Nick Jansen]] suggested. Especially the bit on attributed-string round-tripping; check it against our [[link]] styling before committing to the approach."
        f2.tags = ["swift", "editor"]
        f2.tagSuggestions = ["nstextview", "reading"]
        f2.significance = 0.6
        // Metadata follows the contract fixture exactly (sharedContent camelCase, C3 §fixture).
        f2.audioMetadataJSON = meta([
            "sharedContent": [
                "type": "url",
                "url": "https://swiftwithmajid.com/2026/05/rich-text-editing",
                "urlTitle": "Rich text editing in SwiftUI — strategies that work",
            ],
            "annotationText": "Try this for the desktop body editor — the NSTextView part maps onto what Nick suggested.",
            "source": "mobile",
            "recordedAt": "2026-06-11T14:02:00Z",
            "significance": 0.6,
        ])

        // 3 — Exported image capture.
        let f3 = PipelineFile(id: "demo-capture-img", filename: "capture_2026-06-05",
                              sourceType: .capture, uploadedAt: date(2026, 6, 5, 16))
        f3.transcribeStatus = .done; f3.sanitiseStatus = .done; f3.enhanceStatus = .done; f3.exportStatus = .done
        f3.enhancedTitle = "Whiteboard — sync flow"
        f3.audioMetadataJSON = meta([
            "sharedContent": ["type": "image", "fileName": "whiteboard.jpg", "mimeType": "image/jpeg"],
            "annotationText": "Photo from Nick's session — the arrows are the retry paths.",
            "source": "mobile",
        ])

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

        // 7 — Memo-link TARGET (fixed UUID id so f1's [[memo:…]] chip resolves and this
        // note's LINKED FROM strip lists f1). UUID-string id like a real synced memo.
        let f7 = PipelineFile(id: "9E8B7C6D-1111-4222-8333-444455556666",
                              filename: "Voice Memo 22-30.m4a", sourceType: .audio,
                              uploadedAt: date(2026, 6, 7, 22))
        f7.transcribeStatus = .done; f7.sanitiseStatus = .done; f7.enhanceStatus = .done
        f7.enhancedTitle = "Late-night audiobook capture flow"
        f7.titleSuggested = f7.enhancedTitle
        f7.sanitised = "The quote + ramble pairing works. The reading mode should feel like an e-reader, not a player."
        f7.audioMetadataJSON = meta(["duration": "00:04:07"])

        return [f1, f2, f3, f4, f5, f6, f7]
    }
}
