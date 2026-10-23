import Foundation

extension ReconcileV2 {

    /// Phone → Mac on an existing row, field by field and by CONTENT, never by timestamp (C47):
    /// a no-op sweep changes nothing, and a race between two stamps cannot hide a change. A phone
    /// edit re-links and recompiles; it never runs the model.
    enum Reflect {

        struct Result: Equatable {
            /// Something on the row changed (the row is a re-export candidate).
            var changed = false
            /// The raw transcript changed — the diarization heal looks again (R57).
            var transcriptChanged = false
        }

        /// `freshRow`: the row was made this sweep, so an enhancement this Mac wrote is adopted
        /// (it may be the only copy of the polish, C46); on an existing row it is our own echo.
        static func apply(memo: Memo, enhancement: MemoEnhancement?, to row: PipelineFile,
                          context ctx: Context, freshRow: Bool = false) -> Result {
            var result = Result()
            // Trash, watermarked: a phone trash/restore arrives; a Mac-only trash is not undone.
            var trashChanged = false
            if memo.deletedAt != row.syncedSourceDeletedAt {
                row.deletedAt = memo.deletedAt
                row.syncedSourceDeletedAt = memo.deletedAt
                trashChanged = true
            }
            guard memo.deletedAt == nil else {
                if trashChanged { row.lastActivityAt = ctx.now }
                result.changed = trashChanged
                return result
            }

            // Q489: the body before this reflect, so a Mac edit still only in `sanitised` is
            // settled into the copy-edit before the recompile rebuilds the body from it.
            let before = (body: row.sanitised,
                          working: CompilerInput.workingBody(raw: row.transcript, copyedit: row.enhancedCopyedit).text,
                          neverLink: Set(row.unlinkedNames), namePicks: row.namePicks)
            let phone: MemoEnhancement? = {
                guard let e = enhancement, e.hasContent, freshRow || e.enhancedByDeviceID != ctx.thisDeviceID else { return nil }
                return e
            }()
            var content = false, meta = false
            var copyeditAdopted = false, rawWins = false

            if let e = phone {
                // Q486 / C153: a copy-edit older than the raw words is of words that are gone.
                if row.enhancedCopyedit != e.copyedit, !e.isStale(for: memo) {
                    row.enhancedCopyedit = e.copyedit; content = true; copyeditAdopted = true
                }
                let pending = e.pendingBlock.isEmpty ? nil : e.pendingBlock   // C152
                if row.pendingPolishBlock != pending {
                    row.pendingPolishBlock = pending
                    if pending != nil, row.enhanceStatus == .done { row.enhanceStatus = .pending }
                    content = true
                }
                if !e.title.isEmpty, row.enhancedTitle != e.title { row.enhancedTitle = e.title; content = true }
                if !e.summary.isEmpty, row.enhancedSummary != e.summary { row.enhancedSummary = e.summary; content = true }
            }
            // C188: a title chosen on another device is adopted; nil or blank never clears one.
            if let chosen = memo.title?.trimmingCharacters(in: .whitespacesAndNewlines), !chosen.isEmpty,
               row.enhancedTitle != chosen {
                row.enhancedTitle = chosen; content = true
            }
            if let t = memo.transcript, row.transcript != t {
                row.transcript = t
                row.transcriptLanguageMode = memo.transcriptLanguageMode
                content = true
                result.transcriptChanged = true
                // C153: a raw edit newer than the polish sends a polished row back to pending and
                // stops the stale copy-edit being the body. A run in flight keeps its own guard.
                if !copyeditAdopted, let e = enhancement, e.hasContent, row.enhanceStatus == .done,
                   (memo.transcriptEditedAt ?? memo.lastEditedAt) > e.enhancedAt {
                    row.enhanceStatus = .pending
                    row.enhancedCopyedit = nil
                    row.pendingPolishBlock = nil
                    rawWins = true
                }
            }
            let blob = Ingest.metadataJSON(for: memo)
            if row.audioMetadataJSON != blob { row.audioMetadataJSON = blob; content = true }
            for field in Fields.all where field.pull(memo, row) {
                if field.recompiles { content = true } else { meta = true }
            }
            if NameResolutionsMirror.pull(memo, into: row) { content = true }
            if ExportAudioMirror.pull(memo, into: row) { meta = true }
            let ocr = Ingest.ocrText(for: memo)
            if row.imageOCRText != ocr { row.imageOCRText = ocr; meta = true }   // C188: never recompiles

            guard content || meta || trashChanged else { return result }
            if content {
                if !copyeditAdopted && !rawWins {
                    MacEditRoundTrip.settle(row, body: before.body, working: before.working, linkedWith: ctx.people,
                                            neverLink: before.neverLink, namePicks: before.namePicks)
                }
                recompile(row, context: ctx)
                row.syncedSourceEditedAt = max(memo.lastEditedAt, phone?.enhancedAt ?? .distantPast)
            }
            row.lastActivityAt = ctx.now
            result.changed = true
            return result
        }

        /// Re-link + recompile over the working body (copy-edit, else transcript); no model.
        static func recompile(_ row: PipelineFile, context ctx: Context) {
            let working = CompilerInput.workingBody(raw: row.transcript, copyedit: row.enhancedCopyedit).text
            guard !working.isEmpty else { return }
            row.relinkNames(working: working, isConversation: SpeakerTranscript.isConversation(working, source: row.noteSource),
                            people: ctx.people)
            row.sanitiseStatus = .done
            row.compiledText = Compiler.compile(file: row, author: ctx.author, knownPeople: ctx.people)
        }
    }

    // MARK: - the fields both stores carry

    /// The plain fields that live on the row AND the memo, declared once for v2. `recompiles`:
    /// the field reaches the frontmatter (C188: lock and reminder never recompile). `adopt` is
    /// first contact, where an empty phone tag list must not wipe tags the row already carries.
    /// The Mac → phone direction is `Writers` (events, never a passive mirror of a nil).
    struct Field {
        let name: String
        let recompiles: Bool
        let pull: (Memo, PipelineFile) -> Bool
        var adopt: (Memo, PipelineFile) -> Bool

        init(_ name: String, recompiles: Bool, pull: @escaping (Memo, PipelineFile) -> Bool,
             adopt: ((Memo, PipelineFile) -> Bool)? = nil) {
            (self.name, self.recompiles, self.pull) = (name, recompiles, pull)
            self.adopt = adopt ?? pull
        }
    }

    enum Fields {
        /// Set `row[keyPath]` from the memo when different; true = it changed.
        private static func set<V: Equatable>(_ row: PipelineFile, _ key: ReferenceWritableKeyPath<PipelineFile, V>,
                                              _ value: V) -> Bool {
            guard row[keyPath: key] != value else { return false }
            row[keyPath: key] = value
            return true
        }

        static let all: [Field] = [
            Field("tags", recompiles: true, pull: { set($1, \.tags, $0.tags) },
                  adopt: { memo, row in !memo.tags.isEmpty && set(row, \.tags, memo.tags) }),
            Field("significance", recompiles: true, pull: { set($1, \.significance, Optional($0.significance)) }),
            Field("destination", recompiles: true, pull: { set($1, \.destination, $0.destination) }),
            Field("locked", recompiles: false, pull: { set($1, \.locked, $0.locked) }),
            Field("editedAt", recompiles: true, pull: { set($1, \.memoEditedAt, $0.editedAt) }),   // C284
            Field("remindAt", recompiles: false, pull: { set($1, \.remindAt, $0.remindAt) }),
        ]
    }
}
