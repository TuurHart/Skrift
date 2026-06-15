import SwiftUI

/// The review "People in this note" chip bar (opt-in naming, mocks/opt-in-naming.html).
/// Shows every DETECTED person (alias-matched in the note) as a chip; tapping toggles
/// whether the note is ABOUT them — which links/unlinks them in the body LIVE and adds
/// them to the `people:` frontmatter. A note links NOBODY until a chip is tapped; a
/// conversation's matched SPEAKERS are auto-linked and shown as locked-on chips ("always
/// linked"). All of the linking is deterministic (no LLM) via `coordinator.toggleAbout`.
struct PeopleChipBar: View {
    @Bindable var file: PipelineFile
    var coordinator: ProcessingCoordinator
    var interactive = true
    /// Live app: the names DB. Tests/snapshots inject a known list. nil = the shared store.
    var peopleOverride: [Person]? = nil
    /// "Someone else…" — open the person editor for a name the note doesn't mention. nil hides it.
    var onAddPerson: (() -> Void)? = nil
    @Environment(\.modelContext) private var ctx

    /// One chip's resolved state.
    private struct Chip: Identifiable {
        let id: String          // lowercased canonical key
        let canonical: String   // "[[Full Name]]"
        let full: String        // display name (full) — the on-state label
        let short: String       // short label — the off-state label
        let isOn: Bool          // currently linked in the body
        let isSpeaker: Bool     // matched turn speaker → locked on
    }

    /// Detected candidates (+ anyone already linked) → chips, recomputed from the file.
    private var chips: [Chip] {
        let working = file.enhancedCopyedit ?? file.transcript ?? ""
        let body = file.bestBodyText
        guard !working.isEmpty else { return [] }
        let people = peopleOverride ?? NamesStore.shared.livePeople()
        let isConv = file.sourceType == .audio && SpeakerTranscript.isAttributed(working)
        let speakers = isConv ? Sanitiser.matchedSpeakers(in: working, people: people) : []

        // Candidates: detected (alias-matched) in the pristine working text, plus anyone
        // already linked in the body (e.g. a speaker whose only surface is the turn header).
        var detected = Sanitiser.detectedPeople(in: working, people: people)
        var seen = Set(detected.map { NamesMerge.keyName($0.canonical).lowercased() })
        for p in people where !p.isDeleted {
            let key = NamesMerge.keyName(p.canonical).lowercased()
            if !seen.contains(key), !Sanitiser.linkOccurrences(of: p.canonical, in: body).isEmpty {
                detected.append(p); seen.insert(key)
            }
        }
        return detected.map { p in
            let key = NamesMerge.keyName(p.canonical).lowercased()
            return Chip(id: key,
                        canonical: p.canonical,
                        full: p.displayName,
                        short: Self.shortLabel(p),
                        isOn: !Sanitiser.linkOccurrences(of: p.canonical, in: body).isEmpty,
                        isSpeaker: speakers.contains(key))
        }
    }

    var body: some View {
        let items = chips
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                header(anyOn: items.contains { $0.isOn })
                FlowLayout(spacing: 7, lineSpacing: 7) {
                    ForEach(items) { chipView($0) }
                    if interactive, let onAddPerson { addChip(onAddPerson) }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.hairline.opacity(0.10), lineWidth: 0.5))
        }
    }

    private func header(anyOn: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "person.crop.circle").font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            Text("People in this note").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            if !anyOn {
                Text("· tap to link the ones it’s about").font(.system(size: 11.5)).foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 0)
        }
    }

    private func chipView(_ chip: Chip) -> some View {
        Button {
            guard interactive, !chip.isSpeaker else { return }
            coordinator.toggleAbout(chip.canonical, for: file, context: ctx)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: chip.isOn ? "checkmark" : "plus")
                    .font(.system(size: 9, weight: .bold))
                Text(chip.isOn ? chip.full : chip.short)
                    .font(.system(size: 12, weight: chip.isOn ? .semibold : .regular))
            }
            .foregroundStyle(chip.isOn ? Theme.accent : Theme.textSecondary)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(chip.isOn ? Theme.accent.opacity(0.15) : Theme.hairline.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(chip.isOn ? Theme.accent.opacity(0.4) : Theme.hairline.opacity(0.10), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(!interactive || chip.isSpeaker)
        .help(chip.isSpeaker ? "Speaker — always linked"
              : (chip.isOn ? "Linked — this note is about \(chip.full)" : "Tap to link \(chip.full)"))
    }

    /// The dashed "Someone else…" chip — opens the editor for a name not yet mentioned.
    private func addChip(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                Text("Someone else…").font(.system(size: 12))
            }
            .foregroundStyle(Theme.textMuted)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 0.6, dash: [3, 2]))
                .foregroundStyle(Theme.hairline.opacity(0.22)))
        }
        .buttonStyle(.plain)
        .help("Add a person this note is about who isn’t detected")
    }

    /// The off-state label — the person's short name, falling back to the first word.
    private static func shortLabel(_ p: Person) -> String {
        let s = (p.short ?? "").trimmingCharacters(in: .whitespaces)
        if !s.isEmpty { return s }
        return p.displayName.split(separator: " ").first.map(String.init) ?? p.displayName
    }
}
