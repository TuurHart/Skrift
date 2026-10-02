import SwiftUI
import SwiftData

/// The note header, at the iPad's weight (signed mock `mocks/mac-note-header.html`,
/// 2026-07-25): an editable TITLE line with the suggested-vs-recording choice as two
/// quiet words · ONE chips row carrying every fact the old four-row properties table
/// listed, flowing straight into the tags · the significance circles · a small
/// include-audio switch. Edits mutate the SwiftData model directly (autosaves).
/// Significance is the shared rating pill (`NoteRatingRow`).
struct NoteProperties: View {
    @Bindable var file: PipelineFile
    /// Live app = true (editable TextFields). Snapshot = false (Text, since
    /// ImageRenderer can't draw AppKit-backed TextFields).
    var interactive = true
    /// False for an unrated note (`MemoNoteProjection`), which hides the
    /// include-audio-in-export switch: the note can't be exported at all yet, so a
    /// switch governing what export copies would be a control over nothing (a projection
    /// has no `PipelineFile` to hold it; the synced `Memo.includeAudioInExport` reaches the
    /// row once the note is rated).
    var canExport = true
    /// Q87: the coordinator behind the Split speakers switch (queue, progress, flatten). nil on
    /// hosts with no pipeline (the switch then only reads the note).
    var coordinator: ProcessingCoordinator? = nil
    /// Reports a tag removal so the CALLER can show the Undo pill at the note-column
    /// level (Q41) — `TagEditorRow`'s own bounds run narrower than the column.
    var onTagToast: (TagEditorRow.TagToast?) -> Void = { _ in }
    /// Q85: the header pill's step toast, hoisted to the note column like the tag Undo pill.
    var onRatingToast: (RatingToast) -> Void = { _ in }

    /// Which title card is selected — EXPLICIT state, not derived from comparing
    /// `enhancedTitle` to a candidate (that flipped the active card the instant you
    /// typed, and discarded the edit — the T1 bug). Re-seeded when the note changes.
    @State private var selectedTitle: TitleKind = .suggested

    private var suggested: String { (file.titleSuggested ?? "").trimmingCharacters(in: .whitespaces) }
    /// C181: the first-transcript-line cut, the phone's "From the recording: …" — never the
    /// filename (`memo_<uuid>.m4a` would be written as the title and synced).
    private var original: String { MacTitleSuggestion.fromRecording(transcript: file.transcript) }
    private var showChooser: Bool {
        file.steps.transcribe == .done
            && MacTitleSuggestion.showChooser(suggested: suggested, recording: original)
    }

    /// Q56/R90: `TagLibrary.counts` was a full `PipelineFile` fetch called TWICE
    /// as a body expression (once inside `mostUsedFirst`, once directly for
    /// `libraryCounts`) — on every render. Cached instead; refreshed on note
    /// switch and on this note's own tag edits (the `.onChange(of: file.tags)`
    /// below already fires for those).
    @State private var tagCounts: [String: Int] = [:]
    private var tagLibrary: [String] { TagRules.mostUsedFirst(tagCounts) }
    private func refreshTagCounts() { tagCounts = TagLibrary.counts(file.modelContext) }

    /// Q85: the orange "starts fading … — rate it to keep it" line beside the pill. Only
    /// an unrated note has one; the spine one-liner needs the backing `Memo` (the fade
    /// clock lives there), so it is looked up once per note switch / rating change, never
    /// in `body`. nil when there is no backing memo (a Mac-local upload) or it never fades.
    @State private var fadingLine: String?
    private func refreshFadingLine() {
        fadingLine = nil
        guard interactive, !NoteConsent.isRated(file.significance),
              let id = UUID(uuidString: file.id),
              let cloud = MemoCloudStore.container,
              let memos = try? ModelContext(cloud).fetch(FetchDescriptor<Memo>()),
              let memo = memos.first(where: { $0.id == id }),
              memo.deletedAt == nil, memo.transcriptStatus == .done else { return }
        let backlinked = MemoLifecycle.backlinkedIDs(
            in: memos, copyedits: Backlinks.copyeditsByMemoID(in: ModelContext(cloud)))
        guard !MemoLifecycle.neverFades(memo, backlinked: backlinked) else { return }
        fadingLine = SharedCopy.fadingLine(WayOut.oneLiner(for: memo, backlinked: backlinked))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            titleSection
            // Facts row — date · place · weather · daypart · source · duration ·
            // reminder/lock. Signed mock `mocks/mac-note-header.html` (Tuur
            // 2026-07-25, at the iPad's weight): this replaces the four-row
            // properties table, which repeated what the chips, the player and the
            // sidebar glyph already said.
            FlowLayout(spacing: 6) {
                ForEach(metaChips) { c in
                    MacContextChip(text: c.text, systemImage: c.symbol, tint: c.tint)
                }
            }
            // Tags — their OWN row (D139 pick 3, signed mock `mocks/tag-ui-revamp.html`):
            // an inline field (no sheet), `✕` on hover, library-wide case fold (C93/D139).
            // `.onChange(of: file.tags)` below already mirrors any tag edit to the
            // phone — no extra sync call needed here.
            TagEditorRow(tags: $file.tags, library: tagLibrary,
                         style: .mac, libraryCounts: tagCounts,
                         onToast: onTagToast)
            // Q85 (signed mock Q75-note-header-final, behaviour A): importance is ONE pill,
            // each tap steps Not rated → Passing → Useful → Important → Not rated (C88), a
            // toast names the step; the orange fading line sits beside it when unrated.
            NoteRatingRow(value: $file.significance, style: .mac,
                          fadingLine: fadingLine, lineFont: 11.5,
                          lineColor: Theme.amber.opacity(0.9),
                          onToast: onRatingToast)
            // WHERE this note goes when it leaves — the SHARED `DestinationRowView`, in
            // the same place as the phone's (signed mock note-destination-tags.html,
            // version B collapsed). Hidden until destinations are switched on.
            if DestinationSettings.isEnabled {
                DestinationRowView(
                    destination: Binding(get: { file.destination },
                                         set: { file.destination = $0 }),
                    folderLabel: { $0.portfolioFolder.map { "\($0)/" } },
                    onPick: { MacCloudMetaSync.setDestination($0, for: file) },
                    style: .mac)
            }
            if canExport, file.sourceType == .audio { audioExportRow }
            // Q87: Split speakers, the header's last row (greyed "Rate the note first" when unrated).
            if file.sourceType == .audio {
                SplitSpeakersRow(file: file, coordinator: coordinator, canSplit: canExport,
                                 interactive: interactive)
            }
        }
        .onChange(of: file.id, initial: true) { _, _ in
            selectedTitle = (file.enhancedTitle ?? "").trimmingCharacters(in: .whitespaces) == original ? .original : .suggested
            refreshTagCounts()
            refreshFadingLine()
        }
        // Push a Mac tag / importance edit to the phone (widen the Mac→phone channel).
        .onChange(of: file.tags) { refreshTagCounts(); MacCloudMetaSync.mirror([file]) }
        // The rating goes through its OWN call, not the passive mirror: only here do we
        // know a nil means "the user cleared it" rather than "never rated" — and the
        // mirror can't tell those apart, so it declines to guess.
        .onChange(of: file.significance) { _, new in
            MacCloudMetaSync.setRating(new, for: file)
            refreshFadingLine()
        }
    }

    /// Everything the old properties table listed, as chips: the note's date, the
    /// ambient context the phone captured (place · weather · daypart), what kind of
    /// thing this is, how long it runs, and the conditional reminder / lock / url
    /// facts. `author` is GONE — `NoteDisplayView` passes the Settings author, so it
    /// was the same name on every note and is written into the exported frontmatter
    /// regardless.
    private var metaChips: [MacChip] {
        var chips: [MacChip] = [MacChip(text: SkriftFormat.breadcrumbDate(file.uploadedAt),
                                        symbol: "calendar")]
        // Q85: the signed header drops the daypart chip (date · place · weather only).
        chips += file.contextChips(includeDayPeriod: false)
            .map { MacChip(text: $0.text, symbol: $0.symbol) }
        // `sourceSymbol` is the SAME descriptor the sidebar row draws, so the chip's
        // glyph and the list glyph can never disagree.
        chips.append(MacChip(text: sourceLabel, symbol: file.sourceSymbol))
        if file.durationSeconds > 0 {
            chips.append(MacChip(text: SkriftFormat.duration(seconds: file.durationSeconds), symbol: "waveform"))
        }
        if let urlVal = captureURLDisplayValue {
            chips.append(MacChip(text: urlVal, symbol: "link", tint: .link))
        }
        if let remind = file.remindAt {
            chips.append(MacChip(text: remind.formatted(date: .abbreviated, time: .shortened),
                                 symbol: "bell"))
        }
        // m5 of the live-recording surface: the ONLY trace a mid-take edit leaves on the
        // resting note. The flag also means the transcript is user-trusted pipeline-wide.
        if file.transcriptUserEdited {
            chips.append(MacChip(text: "edited while recording", symbol: "pencil"))
        }
        if file.locked {
            chips.append(MacChip(text: "Locked — stays out of the vault", symbol: "lock.fill", tint: .warn))
        }
        return chips
    }

    // ── Title ───────────────────────────────────────────────
    /// ONE editable line, with the suggested-vs-recording choice as two quiet words
    /// beneath it (signed mock `mocks/mac-note-header.html`). It used to be two large
    /// cards — the widest thing on the screen — to choose between two strings.
    @ViewBuilder private var titleSection: some View {
        if showChooser {
            VStack(alignment: .leading, spacing: 6) {
                titleLine
                HStack(spacing: 14) {
                    titleSourceButton(.suggested, "Suggested", value: suggested)
                    titleSourceButton(.original, "From recording", value: original)
                }
            }
        } else {
            titleLine
        }
    }

    private enum TitleKind { case suggested, original }

    /// The title itself — editable in place, the same line whichever source it came from.
    @ViewBuilder private var titleLine: some View {
        if interactive {
            TextField("", text: titleBinding,
                      prompt: Text(titlePrompt).foregroundStyle(Theme.textMuted), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        } else {
            Text(titleBinding.wrappedValue.isEmpty ? file.displayTitle : titleBinding.wrappedValue)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "Suggested" / "From recording" — a plain word that fills the title line when
    /// picked, accent while it's the active source. Tapping REPLACES the title, which
    /// is the whole decision the two cards used to occupy a third of the screen for.
    private func titleSourceButton(_ kind: TitleKind, _ label: String, value: String) -> some View {
        let isActive = selectedTitle == kind
        return Button {
            selectedTitle = kind
            file.enhancedTitle = value
            MacCloudEditSync.shared.note(file)
            // An explicit CHOICE is the note's title everywhere, not a Mac-local
            // preference: the enhancement carrier above is only a suggestion the phone
            // never auto-applies (Tuur 2026-07-27).
            MacCloudMetaSync.setTitle(value, for: file)
        } label: {
            HStack(spacing: 4) {
                Circle().fill(isActive ? Theme.accentText : Theme.textMuted)
                    .frame(width: 5, height: 5)
                Text(label)
                    .font(.system(size: 11.5, weight: isActive ? .semibold : .regular))
            }
            .foregroundStyle(isActive ? Theme.accentText : Theme.textMuted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isActive ? "This is the current title" : "Use “\(value)”")
        .accessibilityIdentifier(kind == .suggested ? "title-use-suggested" : "title-use-recording")
    }

    /// "Add a title" on a brand-new note (shared copy); an untitled note with words ghosts
    /// its first line instead. Not `displayTitle`: its filename fallback is `memo_<UUID>`
    /// or empty (Q177, capture-quick-09).
    private var titlePrompt: String {
        SharedCopy.titlePrompt(ghosts: [file.titleGhost])
    }

    private var titleBinding: Binding<String> {
        Binding(get: { file.enhancedTitle ?? "" },
                set: {
                    file.enhancedTitle = $0
                    MacCloudEditSync.shared.note(file)          // Part B live sync (debounced)
                    // Typing your own title is as explicit a choice as picking a source,
                    // so it reaches every device too. `setTitle` no-ops when unchanged,
                    // so per-keystroke calls don't churn CloudKit.
                    MacCloudMetaSync.setTitle($0, for: file)
                })
    }

    /// Per-note opt-out for copying the audio into the vault on export (ST8). Kept a
    /// REAL switch — Tuur 2026-07-25: "the include audio should still be a toggle i
    /// think. but can be small." It's a decision you flip while looking at the note,
    /// so it doesn't belong behind a menu; `.mini` at 11pt is enough presence.
    @ViewBuilder private var audioExportRow: some View {
        HStack(spacing: 8) {
            if interactive {
                // Q186: the choice is synced (`Memo.includeAudioInExport`), so the phone's
                // publisher honours it too — written out the moment it is flipped.
                Toggle("", isOn: Binding(get: { file.includeAudioInExport },
                                         set: { file.includeAudioInExport = $0
                                                MacCloudMetaSync.setIncludeAudio(for: file) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(Theme.accent)
            } else {
                // ImageRenderer can't draw a switch — the snapshot path states it.
                Text(file.includeAudioInExport ? "ON" : "OFF")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.accent)
            }
            Text("Include audio in export").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
        }
    }

    /// URL row value for url captures — the host + path without the scheme for
    /// brevity (mirrors the mock: "swiftwithmajid.com/2026/05/rich-text-editing").
    private var captureURLDisplayValue: String? {
        guard file.sourceType == .capture else { return nil }
        let sc = file.sharedContent
        guard sc?.type == .url, let urlStr = sc?.url, !urlStr.isEmpty else { return nil }
        if let u = URL(string: urlStr) {
            return (u.host ?? "") + u.path
        }
        return urlStr
    }

    private var sourceLabel: String {
        // The unified source taxonomy label — SAME descriptor as the sidebar glyph
        // (`file.sourceTypeLabel`: Voice memo / Video / Audiobook quote / Link /
        // Image / Text / File / Apple Note) — plus the extras this surface shows:
        // the book title for an audiobook quote, and the provenance for a capture.
        let base = file.sourceTypeLabel
        if let book = file.bookCapture { return SharedCopy.quoteChip(bookTitle: book.title) }
        if file.sourceType == .capture {
            let metaObj = (try? JSONSerialization.jsonObject(with: file.audioMetadataJSON ?? Data())) as? [String: Any]
            let sourceStr = (metaObj?["source"] as? String).map { " · \($0)" } ?? " · phone"
            return base + sourceStr
        }
        return base
    }

}

// ── Tag library ─────────────────────────────────────────────
/// Every live tag across the library, most-used first — ONE source for the
/// properties typeahead AND the body's inline `#` completion, so the two
/// suggestion surfaces can't disagree.
@MainActor enum TagLibrary {
    static func mostUsedFirst(_ context: ModelContext?) -> [String] {
        TagRules.mostUsedFirst(counts(context))   // the phone's ranking too (Q172)
    }

    /// How many (non-deleted) notes carry each tag — the Mac menu's trailing usage
    /// count (Q41, mock `LIBN`), and the sort key `mostUsedFirst` already used.
    static func counts(_ context: ModelContext?) -> [String: Int] {
        guard let context else { return [:] }
        let files = (try? context.fetch(FetchDescriptor<PipelineFile>())) ?? []
        return TagRules.counts(files.lazy.filter { $0.deletedAt == nil }.map(\.tags))
    }
}

// ── Context chip (date · place · weather · daypart · source · duration · …) ──
/// One fact about the note, as a chip. `tint` carries the two exceptions the old
/// properties table coloured: a capture's url (link blue) and the lock warning.
struct MacChip: Identifiable {
    enum Tint { case plain, link, warn }
    let text: String
    var symbol: String?
    var tint: Tint = .plain
    var id: String { text }
}

/// The Mac mirror of the phone's `ContextChip` (Components.swift): a small pill,
/// icon + text, so the note's facts read identically across the two apps.
struct MacContextChip: View {
    let text: String
    var systemImage: String?
    var tint: MacChip.Tint = .plain

    private var fg: Color {
        switch tint {
        case .plain: return Theme.textSecondary
        case .link:  return Theme.blue
        case .warn:  return Theme.amber
        }
    }

    var body: some View {
        ContextChipView(text: text, systemImage: systemImage,
                        style: ContextChipStyle(text: fg, fill: Theme.hairline.opacity(0.06)))
    }
}

