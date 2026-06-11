import SwiftUI

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
        VStack(alignment: .leading, spacing: 18) {
            titleSection
            propertiesCard
        }
        .onChange(of: file.id, initial: true) { _, _ in
            selectedTitle = (file.enhancedTitle ?? "").trimmingCharacters(in: .whitespaces) == original ? .original : .suggested
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
            TextField("", text: titleBinding, prompt: Text(file.filename).foregroundStyle(Theme.textMuted), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        } else {
            Text(file.enhancedTitle?.isEmpty == false ? file.enhancedTitle! : file.filename)
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
        Binding(get: { file.enhancedTitle ?? "" }, set: { file.enhancedTitle = $0 })
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
            SignificanceCircles(value: $file.significance, enabled: file.steps.enhance == .done)
            divider
            TagEditor(file: file)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Theme.hairline.opacity(0.022), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline.opacity(0.07), lineWidth: 1))
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
        }
    }

    private var metadataRows: [(String, String)] {
        var rows: [(String, String)] = [("date", SkriftFormat.breadcrumbDate(file.uploadedAt))]
        if !author.isEmpty { rows.append(("author", author)) }
        rows.append(("source", sourceLabel))
        if file.durationSeconds > 0 { rows.append(("duration", SkriftFormat.clock(file.durationSeconds))) }
        let meta = (try? JSONSerialization.jsonObject(with: file.audioMetadataJSON ?? Data())) as? [String: Any]
        if let loc = (meta?["phone_location"] as? [String: Any])?["placeName"] as? String, !loc.isEmpty {
            var s = loc
            if let w = meta?["phone_weather"] as? [String: Any],
               let c = w["conditions"] as? String, let t = w["temperature"] {
                let unit = (w["temperatureUnit"] as? String) ?? "°C"
                s += " · \(c), \(t)\(unit)"
            }
            rows.append(("location", s))
        }
        return rows
    }

    private var sourceLabel: String {
        switch file.sourceType {
        case .audio: return "Voice memo"
        case .note: return "Apple Note"
        case .capture: return "Capture"
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline.opacity(0.07)).frame(height: 0.5).padding(.vertical, 13)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 10)).tracking(0.7).foregroundStyle(Theme.textMuted)
    }
}

// ── Tags ────────────────────────────────────────────────────
private struct TagEditor: View {
    @Bindable var file: PipelineFile
    @State private var adding = false
    @State private var draft = ""

    private var suggestions: [String] {
        (file.tagSuggestions ?? []).filter { !file.tags.contains($0) }
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
            TextField("tag…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 80)
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
        let t = draft.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "#", with: "")
        if !t.isEmpty && !file.tags.contains(t) { file.tags.append(t) }
        draft = ""; adding = false
    }
}
