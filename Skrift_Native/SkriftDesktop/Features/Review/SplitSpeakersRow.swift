import SwiftUI
import SwiftData

/// The note header's LAST row: the Split speakers switch (Q87, signed mock
/// `mocks/Q86-split-speakers.html`, "Do the switch in header" — Tuur 2026-09-30).
///
/// Under "Include audio in export", parted from it by a hairline. Off by default. The switch
/// never flips on its own: turning it on (or off) opens a confirm first, and only the confirm's
/// button changes anything. ON re-transcribes from the audio (so it replaces hand edits) and
/// queues through `RunQueue`; OFF is the existing Flatten to monologue. The switch's state is the
/// note's truth: on exactly when its words ARE turns (`SplitSpeakers.isSplit`).
struct SplitSpeakersRow: View {
    @Bindable var file: PipelineFile
    var coordinator: ProcessingCoordinator?
    /// False on an unrated note: the Mac has no pipeline row for it (C187), so the switch is
    /// greyed and says why. Rating the note wakes it up.
    var canSplit: Bool
    /// False on the ImageRenderer snapshot path, which cannot draw a switch.
    var interactive = true
    @Environment(\.modelContext) private var ctx

    enum Confirm { case on, off }
    @State private var confirm: Confirm? = SplitSpeakersRow.debugInitial
    /// The note's last edit, read once when the confirm opens (it needs the synced Memo).
    @State private var editedAt: Date?

    #if DEBUG
    /// `-splitPreview on|off`: open a confirm at launch, for the headless snapshots.
    static var debugInitial: Confirm? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-splitPreview"), i + 1 < a.count else { return nil }
        return a[i + 1] == "on" ? .on : (a[i + 1] == "off" ? .off : nil)
    }
    #else
    static var debugInitial: Confirm? { nil }
    #endif

    private var phase: ProcessingCoordinator.SplitPhase? { coordinator?.splitPhases[file.id] }
    private var notice: String? { coordinator?.splitNotices[file.id] }
    private var isOn: Bool { phase != nil || SplitSpeakers.isSplit(file) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Rectangle().fill(Theme.hairline.opacity(0.10)).frame(height: 1)
                .padding(.top, 2)
            HStack(alignment: .top, spacing: 8) {
                switchView
                VStack(alignment: .leading, spacing: 2) {
                    Text("Split speakers")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(canSplit ? Theme.textSecondary : Theme.textMuted)
                    statusLine
                }
                Spacer(minLength: 0)
            }
        }
        .overlay(alignment: .topLeading) {
            if let confirm { card(confirm).offset(y: 34) }
        }
        .zIndex(2)
        .animation(.easeOut(duration: 0.12), value: confirm == nil)
    }

    // MARK: the switch

    @ViewBuilder private var switchView: some View {
        if interactive {
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { wantsOn in
                    if wantsOn { editedAt = lastEditDate() }
                    confirm = wantsOn ? .on : .off
                }))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(Theme.accent)
                .disabled(!canSplit || phase != nil)
                .accessibilityIdentifier("split-speakers-switch")
        } else {
            Text(isOn ? "ON" : "OFF")
                .font(.system(size: 9, weight: .bold)).foregroundStyle(canSplit ? Theme.accent : Theme.textMuted)
        }
    }

    // MARK: the one line under the label

    @ViewBuilder private var statusLine: some View {
        if !canSplit {
            line(SplitSpeakersCopy.rateFirst)
        } else if let phase {
            HStack(spacing: 8) {
                switch phase {
                case .waiting:
                    line(SplitSpeakersCopy.queued)
                case .running(let since):
                    TimelineView(.periodic(from: since, by: 1)) { tl in
                        Text("Splitting…  \(Self.clock(tl.date.timeIntervalSince(since)))")
                            .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                    }
                }
                Button("Cancel") { coordinator?.cancelSplit(file, context: ctx) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accentText)
                    .accessibilityIdentifier("split-speakers-cancel")
            }
        } else if let notice {
            Text(notice).font(.system(size: 11)).foregroundStyle(Theme.amber.opacity(0.9))
        } else if SplitSpeakers.isSplit(file) {
            line(SplitSpeakersCopy.splitHint)
        } else {
            line(SplitSpeakersCopy.switchOffHint)
        }
    }

    private func line(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let t = max(0, Int(seconds))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    // MARK: confirm cards (drawn inline, not a system popover, so the headless snapshot can see them)

    @ViewBuilder private func card(_ kind: Confirm) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch kind {
            case .on:
                Text(SplitSpeakersCopy.confirmTitle).font(.system(size: 12.5, weight: .semibold))
                Text(SplitSpeakersCopy.confirmBody(durationSeconds: file.durationSeconds))
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                if let warn = SplitSpeakersCopy.editWarning(editedAt: editedAt) {
                    Text(warn).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.amber)
                }
                buttons(cancel: "Cancel", go: SplitSpeakersCopy.confirmSplit) {
                    confirm = nil
                    Task { await coordinator?.splitSpeakers(file, context: ctx) }
                }
            case .off:
                Text(SplitSpeakersCopy.flattenTitle).font(.system(size: 12.5, weight: .semibold))
                Text(SplitSpeakersCopy.flattenBodyMac(
                        person: SplitSpeakers.namedPerson(in: file, people: NamesStore.shared.livePeople())))
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                buttons(cancel: SplitSpeakersCopy.flattenKeep, go: SplitSpeakersCopy.flattenConfirm) {
                    confirm = nil
                    Task { await coordinator?.flattenToMonologue(file, context: ctx) }
                }
            }
        }
        .padding(12)
        .frame(width: 330, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.hairline.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
        .onExitCommand { confirm = nil }
    }

    private func buttons(cancel: String, go: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Spacer()
            Button(cancel) { confirm = nil }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
            Button(action: action) {
                Text(go).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }

    /// The note's last edit, when the transcript was hand-edited (the synced `Memo` carries it).
    private func lastEditDate() -> Date? {
        guard let id = UUID(uuidString: file.id) else { return nil }
        let memo = MemoCloudStore.container.flatMap {
            try? ModelContext($0).fetch(FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })).first
        }
        guard file.transcriptUserEdited || memo?.transcriptUserEdited == true else { return nil }
        return memo?.editedAt ?? file.syncedSourceEditedAt
    }
}

/// The band above the body while a split runs: what is happening, and that the text is read-only
/// until it finishes (mock step 3). The body itself is dimmed by the caller.
struct SplitSpeakersBand: View {
    let since: Date?
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                if let since {
                    TimelineView(.periodic(from: since, by: 1)) { tl in
                        Text("\(SplitSpeakersCopy.listening) · \(SplitSpeakersRow.clock(tl.date.timeIntervalSince(since)))")
                            .monospacedDigit()
                    }
                } else {
                    Text(SplitSpeakersCopy.queued)
                }
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textSecondary)
            Text(SplitSpeakersCopy.keepsGoing).font(.system(size: 11)).foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Who is Speaker 2?" as a Mac popover off the gutter name (mock step 5): the phone's
/// `SpeakerAssignSheet` sections, same words. A person names ALL of the speaker's turns; the
/// merge section moves ONE line.
struct SpeakerAssignPopover: View {
    let speaker: String
    let turnCount: Int
    let others: [String]
    let people: [String]
    var onName: (String) -> Void
    var onMoveLine: (String) -> Void
    var onCancel: () -> Void
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Who is \(speaker)?").font(.system(size: 13, weight: .semibold))
            Text(SplitSpeakersCopy.namesAllTurns(count: turnCount, speaker: speaker))
                .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
            if !people.isEmpty {
                section("PEOPLE") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(people, id: \.self) { name in
                                Button { onName(name) } label: { personRow(name) }.buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 140)
                }
            }
            if !others.isEmpty {
                section("MERGE INTO") {
                    Text(SplitSpeakersCopy.mergeHint).font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                    ForEach(others, id: \.self) { other in
                        Button { onMoveLine(other) } label: {
                            HStack(spacing: 8) {
                                Text("\u{21DD}").foregroundStyle(Theme.accentText)
                                Text(other).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textPrimary)
                                Spacer()
                            }
                            .padding(.vertical, 4).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            section("NEW PERSON") {
                HStack(spacing: 8) {
                    TextField("Full name", text: $newName)
                        .textFieldStyle(.roundedBorder).onSubmit(addNew)
                    Button("Add", action: addNew).disabled(trimmed.isEmpty)
                }
            }
            HStack { Spacer(); Button("Cancel", action: onCancel) }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var trimmed: String { newName.trimmingCharacters(in: .whitespaces) }
    private func addNew() { if !trimmed.isEmpty { onName(trimmed) } }

    private func personRow(_ name: String) -> some View {
        HStack(spacing: 8) {
            Text(String(name.split(separator: " ").compactMap(\.first).prefix(2)))
                .font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.accentText)
                .frame(width: 24, height: 24)
                .background(Theme.accent.opacity(0.16), in: Circle())
            Text(name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textPrimary)
            Spacer()
        }
        .padding(.vertical, 4).contentShape(Rectangle())
    }

    @ViewBuilder private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10, weight: .bold)).tracking(0.6).foregroundStyle(Theme.textMuted)
            content()
        }
    }
}
