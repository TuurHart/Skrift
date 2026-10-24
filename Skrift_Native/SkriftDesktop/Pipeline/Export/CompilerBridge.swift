import Foundation
import SwiftData

// Desktop bridge to the shared export compile (`ExportV2`, fed the neutral `CompilerInput` the
// phone builds too). This file keeps the desktop-only pieces:
//   • `PhoneMetadata` — the metadata decode helper several desktop surfaces still use
//     directly (BatchRunner, QueueDerivations, NoteProperties, NoteDisplayView,
//     CaptureViews, tests). It mirrors the PHONE's metadata shape. (`SharedContent`
//     itself is the ONE shared wire struct now — Shared/Model/SharedContent.swift.)
//   • `PipelineFile.compilerInput` — maps a queue item into the neutral DTO.
//   • `PipelineFile.compiledMarkdown` — the review draft / copy-as-markdown, compiled by v2.

/// Phone-sent metadata, decoded from `PipelineFile.audioMetadataJSON` for the export
/// frontmatter. Q172 (books-102): the lenient reader now lives in Shared beside the
/// schema it reads (`MemoMetadata.Lenient`, `MemoMetadata.lenient(from:)`); this name
/// stays for the Mac call sites and tests.
typealias PhoneMetadata = MemoMetadata.Lenient

extension PipelineFile {
    /// Map this queue item into the neutral `CompilerInput` export v2 consumes, decoding the
    /// metadata blob through the desktop `PhoneMetadata`/`SharedContent` helpers.
    var compilerInput: CompilerInput { compilerInput(people: []) }

    /// Q471: `people` (the live roster) links a voice / video share's sender line, which the
    /// stored `sanitised` never carries. The rest of the body is never re-linked here.
    func compilerInput(people: [Person]) -> CompilerInput {
        let meta = MemoMetadata.lenient(from: audioMetadataJSON)
        let sc = SharedContent.decode(from: audioMetadataJSON)
        // The ONE shared builder (Q155): body source, voice and link stems follow the phone's
        // rules. `linked` is the stored `sanitised` — linked at processing time with this
        // row's picks, and the text the user edits on the Mac — never re-derived here
        // (nil stays nil: an unprocessed row falls through to copy-edit → transcript).
        return CompilerInput.make(
            filename: filename,
            raw: transcript,
            copyedit: enhancedCopyedit,
            linked: .some(sanitised),
            people: people,
            resolutions: nameResolutions,
            // The stored title (rungs 1+2 of the C25 ladder), NOT `exportTitle`: the Mac
            // always sets it before export (BatchRunner), so it equals the filename's title
            // in practice; feeding the ladder here put an un-titled capture's annotation line
            // into `title:` above the shared block (CaptureCompilerTests). The FILE name
            // uses `exportTitle` (VaultExporter).
            title: enhancedTitle,
            summary: enhancedSummary,
            tags: NoteDestination.exportTags(tags, raw: destinationRaw),
            significance: significance,
            sourceType: noteSource,
            mediaSource: mediaSource,
            metadata: meta.map { m in
                CompilerMetadata(
                    location: m.location.map { .init(placeName: $0.placeName) },
                    weather: m.weather.map { .init(conditions: $0.conditions, temperature: $0.temperature, temperatureUnit: $0.temperatureUnit) },
                    pressure: m.pressure.map { .init(hPa: $0.hPa, trend: $0.trend) },
                    dayPeriod: m.dayPeriod,
                    daylight: m.daylight.map { .init(sunrise: $0.sunrise, sunset: $0.sunset, hoursOfLight: $0.hoursOfLight) },
                    steps: m.steps,
                    recordedAt: m.recordedAt,
                    bookTitle: m.bookTitle,
                    bookAuthor: m.bookAuthor,
                    bookChapter: m.bookChapter,
                    bookPosition: m.bookPosition,  // a link note's place (Q372)
                    bookURL: m.bookURL             // an article quote's page (Q355)
                )
            },
            sharedContent: sc,
            rawRecordedAt: Self.rawMetaString(audioMetadataJSON, key: "recordedAt"),
            editedAt: memoEditedAt,
            destination: destination,
            spoken: sourceType == .audio && !path.isEmpty,
            // The ONE classifier the phone's exporter uses too (Q142): a typed row is
            // `.note` + `mediaSource: "typed"` here, which alone would read `Apple-Note`.
            kind: SourceKind.classify(hasBook: !(meta?.bookTitle ?? "").isEmpty,
                                      pdfPage: SourceKind.isPDFPageLabel(meta?.bookChapter),
                                      article: meta?.bookKind?.lowercased() == "article",
                                      // Q372: a "Send to a note" / "Move to Library" link
                                      sourceLink: SourceKind.sourceLink(metadataData: audioMetadataJSON,
                                                                        body: transcript),
                                      media: mediaSource, sharedType: sc?.type.rawValue,
                                      isCaptureRow: sourceType == .capture,
                                      hasAudio: sourceType == .audio && !path.isEmpty),
            // Q471: a voice / video share's sender rides the synced lead text (C123); the
            // phone's `Memo.annotationText` reaches this row inside the metadata JSON.
            lead: sourceType == .capture ? nil : Self.rawMetaString(audioMetadataJSON, key: "annotationText"))
    }

    /// The export title — the shared C25 ladder (`ExportNaming.title`, the iPad's rule too).
    /// `enhancedTitle` carries rungs 1+2 on the Mac: a title chosen on any device
    /// (`ReconcileV2.Reflect` adopts `Memo.title`), else the Mac's own suggestion. The body is
    /// the RAW text (`transcript` — a capture's annotation lives there too), the same text
    /// the iPad reads its first line from.
    var exportTitle: String {
        let shared = sourceType == .capture ? SharedContent.decode(from: audioMetadataJSON) : nil
        return ExportNaming.title(userTitle: nil, suggestedTitle: enhancedTitle, body: transcript,
                                  shared: shared,
                                  isVoice: sourceType == .audio && mediaSource != "typed")
    }

    /// Extract a top-level string from the raw metadata JSON without Codable (for keys
    /// PhoneMetadata doesn't have — e.g. `recordedAt` on captures).
    static func rawMetaString(_ data: Data?, key: String) -> String? {
        guard let data,
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let v = obj[key] as? String else { return nil }
        return v
    }
}

extension PipelineFile {
    /// The note as export v2 compiles it for the vault, nothing placed: the review draft
    /// (`compiledText`) and copy-as-markdown. Memo-links resolve to the derived stems (no ledger).
    func compiledMarkdown(author: String, people: [Person]) -> String {
        ExportV2.compile(VaultExporter.v2Note(self, people: people, author: author),
                         profile: .obsidian, stem: VaultExporter.noteStem(self)).markdown
    }
}

/// UUID → exported-note stem over the whole queue — what `[[memo:UUID|Title]]` resolves
/// against on the Mac (the phone resolves against ITS published filenames; each sink's
/// links stay self-consistent, and Obsidian resolves `[[stem]]` vault-wide).
enum MemoLinkStems {
    /// `ledger` (the export path passes its vault's) wins over the derived stem: the
    /// file on disk is STICKY across retitles, so a link must follow the FILE, not
    /// the title. nil (copy-markdown, previews) falls back to the derived names.
    static func map(_ context: ModelContext, ledger: ExportLedger? = nil) -> [UUID: String] {
        let files = (try? context.fetch(FetchDescriptor<PipelineFile>())) ?? []
        var out: [UUID: String] = [:]
        for f in files {
            guard let id = UUID(uuidString: f.id) else { continue }
            if let rel = ledger?.relativePath(for: id) {
                out[id] = ((rel as NSString).lastPathComponent as NSString).deletingPathExtension
            } else {
                out[id] = VaultExporter.noteStem(f)
            }
        }
        return out
    }
}
