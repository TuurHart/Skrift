import SwiftUI
import SwiftData

/// The editable properties block: two-title chooser, grouped metadata + significance
/// + tags card. Ported from `NoteProperties.tsx`. Edits mutate the SwiftData model
/// directly (autosaves). Significance is the 10-circle star-rating control
/// (`SignificanceCircles`, per mocks/significance-circles.html — replaced the slider).
struct NoteProperties: View {
    @Bindable var file: PipelineFile
    var author: String = ""
    /// Live app = true (editable TextFields). Snapshot = false (Text, since
    /// ImageRenderer can't draw AppKit-backed TextFields).
    var interactive = true

    /// Which title card is selected — EXPLICIT state, not derived from comparing
    /// `enhancedTitle` to a candidate (that flipped the active card the instant you
    /// typed, and discarded the edit — the T1 bug). Re-seeded when the note changes.
    @State private var selectedTitle: TitleKind = .suggested

    private var suggested: String { (file.titleSuggested ?? "").trimmingCharacters(in: .whitespaces) }
    private var original: String { SkriftFormat.cleanFilename(file.filename) }
    private var showChooser: Bool {
        file.steps.transcribe == .done && !suggested.isEmpty && !original.isEmpty && suggested != original
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            titleSection
            contextChipRow          // place · weather · daypart (phone parity)
            propertiesCard
        }
        .onChange(of: file.id, initial: true) { _, _ in
            selectedTitle = (file.enhancedTitle ?? "").trimmingCharacters(in: .whitespaces) == original ? .original : .suggested
        }
    }

    /// The ambient context chips the phone shows under the title (place · weather ·
    /// daypart). Hidden when the memo carries no context (captures, older uploads).
    @ViewBuilder private var contextChipRow: some View {
        let chips = file.contextChips
        if !chips.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(chips, id: \.text) { chip in
                    MacContextChip(text: chip.text, systemImage: chip.symbol)
                }
            }
        }
    }

    // ── Title ───────────────────────────────────────────────
    @ViewBuilder private var titleSection: some View {
        if showChooser {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Title — pick one")
                HStack(spacing: 10) {
                    titleCard(.suggested, icon: "sparkles", label: "Suggested", value: suggested)
                    titleCard(.original, icon: "waveform", label: "From recording", value: original)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        } else if interactive {
            TextField("", text: titleBinding, prompt: Text(file.displayTitle).foregroundStyle(Theme.textMuted), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        } else {
            Text(file.displayTitle)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private enum TitleKind { case suggested, original }

    private func titleCard(_ kind: TitleKind, icon: String, label: String, value: String) -> some View {
        let isActive = selectedTitle == kind
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 10))
                Text(label.uppercased()).font(.system(size: 10, weight: .medium)).tracking(0.5)
            }
            .foregroundStyle(isActive ? Theme.accent : Theme.textMuted)

            if isActive && interactive {
                TextField("", text: titleBinding, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            } else if isActive {
                Text(titleBinding.wrappedValue.isEmpty ? value : titleBinding.wrappedValue)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(value.isEmpty ? "—" : value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: kind == .suggested ? .infinity : 220, alignment: .leading)
        .frame(minHeight: 64, alignment: .top)
        .background(isActive ? Theme.accent.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .stroke(isActive ? Theme.accent.opacity(0.5) : Theme.hairline.opacity(0.08), lineWidth: 1))
        .overlay(alignment: .topTrailing) { radio(isActive).padding(12) }
        .opacity(isActive ? 1 : 0.6)
        .contentShape(Rectangle())
        .onTapGesture { if !isActive { selectedTitle = kind; file.enhancedTitle = value } }
    }

    private func radio(_ on: Bool) -> some View {
        Circle()
            .strokeBorder(on ? Theme.accent : Theme.hairline.opacity(0.18), lineWidth: 2)
            .background(Circle().fill(on ? Theme.accent : .clear).padding(3.5))
            .frame(width: 13, height: 13)
    }

    private var titleBinding: Binding<String> {
        Binding(get: { file.enhancedTitle ?? "" },
                set: { file.enhancedTitle = $0; MacCloudEditSync.shared.note(file) })   // Part B live sync
    }

    // ── Properties card ─────────────────────────────────────
    private var propertiesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            metadataGrid
            if file.sourceType == .audio {
                divider
                audioExportRow
            }
            divider
            // Importance is editable ANY time (phone parity + it now syncs back via
            // MacCloudMetaSync) — not gated behind enhancement, which left synced-but-unenhanced
            // notes unratable on the Mac (2026-07-15 device finding).
            SignificanceCircles(value: $file.significance)
            divider
            TagEditor(file: file)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Theme.hairline.opacity(0.022), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline.opacity(0.07), lineWidth: 1))
        // Push a Mac tag / importance edit to the phone (widen the Mac→phone channel).
        .onChange(of: file.tags) { MacCloudMetaSync.mirror([file]) }
        .onChange(of: file.significance) { MacCloudMetaSync.mirror([file]) }
    }

    /// Per-note opt-out for copying the audio into the vault on export (ST8).
    @ViewBuilder private var audioExportRow: some View {
        HStack {
            Text("Include audio file in export").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            Spacer()
            if interactive {
                Toggle("", isOn: $file.includeAudioInExport)
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(Theme.accent)
            } else {
                Text(file.includeAudioInExport ? "Yes" : "No")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
            }
        }
    }

    private var metadataGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
            ForEach(metadataRows, id: \.0) { row in
                GridRow {
                    Text(row.0).font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                    Text(row.1).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
            }
            // URL row for url captures — link-colored per mock state 3.
            if let urlVal = captureURLDisplayValue {
                GridRow {
                    Text("url").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                    Text(urlVal).font(.system(size: 11)).foregroundStyle(Theme.blue)
                        .lineLimit(1)
                }
            }
            // Synced note reminder (set on the phone; the alarm rings per-device).
            if let remind = file.remindAt {
                GridRow {
                    Text("reminder").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                    (Text(Image(systemName: "bell")) + Text(" \(remind.formatted(date: .abbreviated, time: .shortened))"))
                        .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
            }
            // Synced lock flag — the row stays visible even while the body is gated.
            if file.locked {
                GridRow {
                    Text("locked").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                    (Text(Image(systemName: "lock.fill")) + Text(" Stays inside Skrift — excluded from export"))
                        .font(.system(size: 11)).foregroundStyle(Theme.amber)
                }
            }
        }
    }

    private var metadataRows: [(String, String)] {
        var rows: [(String, String)] = [("date", SkriftFormat.breadcrumbDate(file.uploadedAt))]
        if !author.isEmpty { rows.append(("author", author)) }
        rows.append(("source", sourceLabel))
        if file.durationSeconds > 0 { rows.append(("duration", SkriftFormat.clock(file.durationSeconds))) }
        // Place / weather / daypart now render as CONTEXT CHIPS above the card
        // (`contextChipRow` → `PipelineFile.contextChips`) — phone parity. The old
        // `phone_location` row only ever matched demo data, so real memos showed nothing.
        return rows
    }

    /// URL row value for url captures — the host + path without the scheme for
    /// brevity (mirrors the mock: "swiftwithmajid.com/2026/05/rich-text-editing").
    private var captureURLDisplayValue: String? {
        guard file.sourceType == .capture else { return nil }
        let sc = SharedContent.decode(from: file.audioMetadataJSON)
        guard sc?.type == "url", let urlStr = sc?.url, !urlStr.isEmpty else { return nil }
        if let u = URL(string: urlStr) {
            let host = u.host ?? ""
            let path = u.path.isEmpty ? "" : u.path
            return host + path
        }
        return urlStr
    }

    private var sourceLabel: String {
        // The unified source taxonomy label — SAME descriptor as the sidebar glyph
        // (`file.sourceTypeLabel`: Voice memo / Video / Audiobook quote / Link /
        // Image / Text / File / Apple Note) — plus the extras this surface shows:
        // the book title for an audiobook quote, and the provenance for a capture.
        let base = file.sourceTypeLabel
        if let book = file.bookCapture { return "\(base) · \(book.title)" }
        if file.sourceType == .capture {
            let metaObj = (try? JSONSerialization.jsonObject(with: file.audioMetadataJSON ?? Data())) as? [String: Any]
            let sourceStr = (metaObj?["source"] as? String).map { " · \($0)" } ?? " · phone"
            return base + sourceStr
        }
        return base
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline.opacity(0.07)).frame(height: 0.5).padding(.vertical, 13)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 10)).tracking(0.7).foregroundStyle(Theme.textMuted)
    }
}

// ── Context chip (place · weather · daypart) ────────────────
/// The Mac mirror of the phone's `ContextChip` (Components.swift): a small pill,
/// icon + text, so the ambient metadata reads identically across the two apps.
private struct MacContextChip: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 10)) }
            Text(text).lineLimit(1).truncationMode(.tail)
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Theme.hairline.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

// ── Tags ────────────────────────────────────────────────────
private struct TagEditor: View {
    @Bindable var file: PipelineFile
    @State private var adding = false
    @State private var draft = ""

    /// The note's own AI tag suggestions (always offered as quick-add chips).
    private var suggestions: [String] {
        (file.tagSuggestions ?? []).filter { !file.tags.contains($0) }
    }

    /// Every tag across the library, most-used first — the phone's "FROM YOUR NOTES"
    /// autocomplete source (the Mac only offered the note's own AI suggestions before).
    private var libraryTags: [String] {
        let files = (try? file.modelContext?.fetch(FetchDescriptor<PipelineFile>())) ?? []
        var counts: [String: Int] = [:]
        for f in files where f.deletedAt == nil {
            for t in f.tags { counts[t, default: 0] += 1 }
        }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
    }

    /// Library autocomplete shown WHILE adding: library tags the note lacks (and that
    /// aren't already an AI chip), prefix-filtered by what's typed, capped so the card
    /// stays compact. Phone parity (`TagEditorSheet` "FROM YOUR NOTES").
    private var librarySuggestions: [String] {
        let typed = draft.trimmingCharacters(in: .whitespaces).lowercased()
        let exclude = Set(file.tags).union(suggestions)
        return libraryTags
            .filter { !exclude.contains($0) && (typed.isEmpty || $0.lowercased().hasPrefix(typed)) }
            .prefix(10).map { $0 }
    }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(file.tags, id: \.self) { tag in
                chip(tag)
            }
            ForEach(suggestions, id: \.self) { s in
                suggestionChip(s)
            }
            addControl
            if adding {
                ForEach(librarySuggestions, id: \.self) { s in
                    suggestionChip(s)
                }
            }
        }
    }

    private func chip(_ tag: String) -> some View {
        HStack(spacing: 5) {
            Text("#\(tag)").font(.system(size: 11, weight: .medium))
            Button { file.tags.removeAll { $0 == tag } } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).opacity(0.5)
                    .frame(width: 15, height: 15)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(Theme.accent.opacity(0.15), in: Capsule())
    }

    private func suggestionChip(_ s: String) -> some View {
        Button { file.tags.append(s) } label: {
            Text("+ #\(s)").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .overlay(Capsule().stroke(Theme.hairline.opacity(0.2), style: StrokeStyle(lineWidth: 0.5, dash: [3])))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var addControl: some View {
        if adding {
            TextField("tag, tag", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 110)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Theme.hairline.opacity(0.06), in: Capsule())
                .onSubmit { commit() }
        } else {
            Button { adding = true } label: {
                Text("+ add tag").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .overlay(Capsule().stroke(Theme.hairline.opacity(0.2), style: StrokeStyle(lineWidth: 0.5, dash: [3])))
            }
            .buttonStyle(.plain)
        }
    }

    private func commit() {
        // Comma-separated multi-tag input, shared with the phone (`Memo.parseTagInput`).
        for t in Memo.parseTagInput(draft) where !file.tags.contains(t) { file.tags.append(t) }
        draft = ""; adding = false
    }
}
