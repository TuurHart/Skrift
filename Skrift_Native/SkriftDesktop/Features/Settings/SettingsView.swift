import SwiftUI
import AppKit

/// Preferences — Obsidian vault paths, author, enhancement model + prompts,
/// transcription preprocessing, and a names overview. Bound to `SettingsStore`
/// (autosaves on change). `interactive: false` renders text fields as plain Text
/// for snapshot verification (ImageRenderer can't draw AppKit TextFields).
struct SettingsView: View {
    var onClose: () -> Void = {}
    var interactive = true
    /// Snapshot/test injection of the names list (default nil → the shared store).
    var peopleOverride: [Person]? = nil

    @AppStorage(AppTheme.key) private var appTheme = "dark"
    @State private var settings = SettingsStore.shared.load()
    /// What this sheet last loaded or saved. The CloudKit runners write vocab/language/prompts
    /// to disk behind an open sheet, so a save persists only the diff from this (Q241 bug 6).
    @State private var savedBaseline = SettingsStore.shared.load()
    /// Mirrors `DestinationSettings.isEnabled` so the section redraws when the switch moves
    /// (that flag is UserDefaults, not an `@Published` settings field).
    @State private var destinationsOn = DestinationSettings.isEnabled
    @State private var people: [Person] = NamesStore.shared.livePeople()
    @State private var nameQuery = ""
    @State private var newCustomWord = ""
    /// Drives the shared person editor sheet (mocks/opt-in-naming.html panel 3): nil = closed,
    /// `.person == nil` = adding, else editing that row.
    @State private var editorRequest: PersonEditorRequest?

    var body: some View {
        VStack(spacing: 0) {
            header
            // No ScrollView in snapshot mode (ImageRenderer can't lay out scroll
            // contents); the live app scrolls.
            if interactive {
                ScrollView { sections }
            } else {
                sections
                Spacer(minLength: 0)
            }
        }
        .frame(width: 560, height: interactive ? 660 : nil)   // snapshot sizes to full content
        .background(Theme.bg)
        .onChange(of: settings) { _, _ in persist() }
        // Prompt edits push to the synced carrier once, when the window goes away
        // (the autosave above already persisted text + stamp per keystroke).
        // A prompt left blank IS the default (Q157): write the default text back before the
        // push so the field, the polisher and the carrier all say the same thing.
        .onDisappear {
            if settings.prompts != settings.prompts.effective {
                settings.prompts = settings.prompts.effective
                persist()
            }
            PolishPromptsCloudSync.run()
        }
        .task { reloadNames() }
        // Live-refresh when a CloudKit names reconcile merges in a person from the phone/iPad,
        // so the list doesn't sit stale while it's open.
        .onReceive(NotificationCenter.default.publisher(for: .namesDidChangeFromSync)) { _ in reloadNames() }
        .sheet(item: $editorRequest) { req in
            PersonEditor(request: req,
                         onSave: { original, person in
                             NamesStore.shared.upsert(person, replacing: original)
                             NamesCloudSync.run()   // push the edit to CloudKit now (no-op if CloudKit-Mac sync off)
                             reloadNames()
                         },
                         onDelete: { canonical in
                             NamesStore.shared.delete(canonical: canonical)
                             NamesCloudSync.run()   // push the tombstone to CloudKit
                             reloadNames()
                         },
                         onClose: { editorRequest = nil })
        }
        .accessibilityIdentifier("settings.root")
    }

    /// Reload the names list from the store, sorted by full name.
    private func reloadNames() {
        people = NamesStore.shared.livePeople().sorted {
            NamesMerge.keyName($0.canonical).localizedCaseInsensitiveCompare(NamesMerge.keyName($1.canonical)) == .orderedAscending
        }
    }

    /// The list source — injected people (snapshot/test) or the loaded store.
    private var displayPeople: [Person] { peopleOverride ?? people }

    private var visiblePeople: [Person] {
        NamesFilter.apply(displayPeople, query: nameQuery)
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("Appearance") {
                if interactive {
                    Picker("", selection: $appTheme) {
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                        Text("Auto").tag("auto")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 280, alignment: .leading)
                } else {
                    Text(appTheme.capitalized).font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                }
            }
            section("Vault & author") {
                textRow("Author", \.authorName, placeholder: "Your name")
                // ONE pick, like the phone and iPad (signed mock vault-folder-model.html,
                // 2026-08-14). The two subfolder fields are gone: they were settings only
                // the Mac had, so the same vault received `1 Recordings`/`0 Images` from
                // here and `Voice Memos`/`Attachments` from iOS. Skrift owns the layout now
                // — Recordings/ Images/ Documents/ inside the folder it resolves to.
                folderRow(SettingsCopy.obsidianFolderLabel, \.noteFolder)
                // The shared sentence (what this device does with the folder) + a Mac-only extra:
                // the resolve rule carries information the phone's picker never needs.
                Text(SettingsCopy.obsidianHelp(
                        folderName: settings.noteFolder.isEmpty ? nil
                            : (settings.noteFolder as NSString).lastPathComponent,
                        canProcess: true))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Point at a folder and it uses its own Skrift folder inside — or point straight at that folder.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            section("Destinations") {
                // OFF by default — most people want one folder, and the four destinations
                // are Tuur's own way of keeping his thoughts out of a repo an AI reads. The
                // switch is `DestinationSettings` (UserDefaults) and SYNCS to the other
                // devices through the vocabulary carrier (Q98 / D162); the portfolio FOLDER
                // below stays per device.
                HStack {
                    Text(SettingsCopy.destinationsToggleLabel).font(.system(size: 12))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if interactive {
                        Toggle("", isOn: Binding(get: { DestinationSettings.isEnabled },
                                                 set: {
                                                     DestinationSettings.isEnabled = $0
                                                     destinationsOn = $0
                                                     VocabularyCloudSync.run()   // push the switch now (Q98)
                                                 }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    } else {
                        Text(destinationsOn ? "On" : "Off")
                            .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                }
                if destinationsOn {
                    folderRow(SettingsCopy.portfolioFolderLabel, \.portfolioRoot)
                    if !settings.portfolioRoot.isEmpty {
                        let root = (settings.portfolioRoot as NSString).lastPathComponent
                        ForEach(NoteDestination.allCases.filter(\.isPortfolio), id: \.self) { d in
                            HStack {
                                Text(d.label).font(.system(size: 11))
                                    .foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Text("\(root)/\(d.portfolioFolder ?? "")")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.textMuted)
                            }
                        }
                    }
                }
                Text(SettingsCopy.destinationsHelp(on: destinationsOn,
                                                   hasFolder: !settings.portfolioRoot.isEmpty))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    // A value synced in from another device lands in UserDefaults; follow it.
                    .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                        let stored = DestinationSettings.storedEnabled()
                        if stored != destinationsOn { destinationsOn = stored }
                    }
            }
            section("Enhancement") {
                textRow("Model (HuggingFace repo)", \.enhancementModelRepo)
                promptRow("Copy-edit prompt", \.prompts.copyEdit, default: PolishPrompts.copyEdit)
                promptRow("Title prompt", \.prompts.title, default: PolishPrompts.title)
                promptRow("Summary prompt", \.prompts.summary, default: PolishPrompts.summary)
            }
            section("Transcription") {
                languageRow
                sliderRow("High-pass filter", value: highpassBinding, range: 0...200, unit: " Hz")
                Text(highpassHelp).font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                customWordsEditor
            }
            section("Sync") {
                toggleRow("CloudKit sync with the Mac", \.cloudKitMacSync, defaultOn: true,
                          help: "\(SharedCopy.syncWhatSyncs) \(SharedCopy.syncSameAccount) The Mac processes the memos your phone synced and sends its polished title, summary and copy-edit back. This is the only phone↔Mac transport: with it off, neither happens.")
            }
            section(RetrievalGate.Copy.settingTitle) { connectionsSection }
            section("Names · \(displayPeople.count)") {
                Text("Tap a person to edit their full name, aliases, short name, and voice. Aliases are the spoken nicknames that link to them; the full name becomes the [[link]].")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if interactive && !displayPeople.isEmpty {
                    RingedField(placeholder: NamesCopy.searchPlaceholder, text: $nameQuery)
                }
                if displayPeople.isEmpty {
                    Text("\(NamesCopy.emptyTitle) — \(NamesCopy.emptyBody)")
                        .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                } else {
                    ForEach(visiblePeople, id: \.canonical) { person in
                        if interactive {
                            Button { editorRequest = PersonEditorRequest(person: person) } label: { nameListRow(person) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("settings.name.\(NamesMerge.keyName(person.canonical))")
                        } else {
                            nameListRow(person)
                        }
                    }
                }
                Group {
                    Button { editorRequest = PersonEditorRequest() } label: {
                        HStack(spacing: 9) {
                            ZStack {
                                Circle().fill(Theme.accent.opacity(0.10)).frame(width: 30, height: 30)
                                Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                            }
                            Text("Add person…").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.accent)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.name.add")
                }
                .disabled(!interactive)   // rendered in snapshots too, only live taps act
            }
        }
        .padding(20)
    }

    private var header: some View {
        HStack {
            Text("Settings").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Button(action: onClose) {
                Text("Done").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.done")
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline.opacity(0.07)).frame(height: 0.5) }
    }

    // ── Connections consent (Q161) ─────────────────────────
    /// The Mac's twin of the phone's Settings switch: same name, same copy, same states
    /// (`RetrievalGate.Copy`). OFF withdraws consent: sweeps stop and the panel,
    /// search-by-meaning and the journal rail hide; the model stays on disk.
    @ViewBuilder private var connectionsSection: some View {
        let svc = ConnectionsIndexService.shared
        let on = svc.isEnabled
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(RetrievalGate.Copy.settingTitle).font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                Spacer()
                if interactive {
                    Toggle("", isOn: Binding(
                        get: { svc.isEnabled },
                        set: { svc.setConsent($0, SharedStore.container.mainContext) }
                    ))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .accessibilityIdentifier("setting-connections")
                } else {
                    Text(on ? "On" : "Off").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
            }
            Text(RetrievalGate.Copy.gateBody(device: "Mac"))
                .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let f = svc.downloadFraction {
                Text(f >= 0.999 ? RetrievalGate.Copy.preparingTitle : RetrievalGate.Copy.downloadingTitle)
                    .font(.system(size: 11)).foregroundStyle(Theme.textPrimary)
                if f < 0.999 {
                    Text(RetrievalGate.Copy.downloadingSub(fraction: f))
                        .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
                }
            } else if on, let p = svc.sweepProgress {
                Text(RetrievalGate.Copy.indexingTitle).font(.system(size: 11)).foregroundStyle(Theme.textPrimary)
                Text(RetrievalGate.Copy.indexingSub(done: p.done, total: p.total))
                    .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
            } else if let err = svc.lastError {
                // Failures are red on the phone too; a failed download also flips the switch off.
                Text(err).font(.system(size: 10.5)).foregroundStyle(Theme.destructive)
            } else if on && svc.isModelDownloaded {
                Text(RetrievalGate.Copy.readyLine)
                    .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
            } else if !on && svc.isModelDownloaded {
                Text(RetrievalGate.Copy.pausedLine)
                    .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
            }
        }
    }

    // ── Section card ────────────────────────────────────────
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.system(size: 10)).tracking(0.7).foregroundStyle(Theme.textMuted)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.hairline.opacity(0.022), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline.opacity(0.07), lineWidth: 1))
    }

    // ── Rows ────────────────────────────────────────────────
    /// A label + switch over an OPTIONAL Bool setting, with help text below.
    /// Renders the state as "On"/"Off" text in snapshot mode (ImageRenderer can't draw a switch).
    ///
    /// `defaultOn` MUST match the setting's own `…Enabled` fallback — the switch reads nil
    /// through the same default the behavior does, so the UI can never say Off while the
    /// feature runs (which is what a hardcoded `?? false` did to `cloudKitMacSync` once its
    /// default flipped on).
    private func toggleRow(_ label: String, _ key: WritableKeyPath<AppSettings, Bool?>,
                           defaultOn: Bool = false, help: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                Spacer()
                if interactive {
                    Toggle("", isOn: Binding(
                        get: { settings[keyPath: key] ?? defaultOn },
                        set: { settings[keyPath: key] = $0 }
                    ))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                } else {
                    Text((settings[keyPath: key] ?? defaultOn) ? "On" : "Off")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
            }
            Text(help).font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func textRow(_ label: String, _ key: WritableKeyPath<AppSettings, String>, placeholder: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            if interactive {
                RingedField(placeholder: placeholder, text: bind(key))
            } else {
                fieldBox {
                    let v = settings[keyPath: key]
                    Text(v.isEmpty ? placeholder : v)
                        .foregroundStyle(v.isEmpty ? Theme.textMuted : Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func folderRow(_ label: String, _ key: WritableKeyPath<AppSettings, String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                fieldBox {
                    let v = settings[keyPath: key]
                    Text(v.isEmpty ? "Not set" : v)
                        .foregroundStyle(v.isEmpty ? Theme.textMuted : Theme.textPrimary)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if interactive {
                    Button(SettingsCopy.chooseVerb) { chooseFolder(key) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12)).foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.hairline.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }

    private func promptRow(_ label: String, _ key: WritableKeyPath<AppSettings, String>,
                           default defaultText: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                Spacer()
                // Same wording as the iPad's Settings. Shown while the text differs from
                // the shared default (a blank counts as the default, so no button then).
                if interactive && PolishPrompts.effective(settings[keyPath: key], fallback: defaultText) != defaultText {
                    Button("Reset to default") {
                        settings[keyPath: key] = defaultText
                        settings.promptsModifiedAt = Date()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("settings.prompt-reset")
                }
            }
            Group {
                if interactive {
                    TextEditor(text: bindPrompt(key))
                        .textEditorStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textPrimary)
                } else {
                    Text(settings[keyPath: key])
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: 84, alignment: .topLeading)
            .padding(8)
            .background(Theme.hairline.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline.opacity(0.08), lineWidth: 1))
            if interactive && settings[keyPath: key].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Blank — the default prompt is used.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
            }
        }
    }

    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(Int(value.wrappedValue))\(unit)")
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.accent)
            }
            TrackSlider(fraction: (value.wrappedValue - range.lowerBound) / (range.upperBound - range.lowerBound)) { f in
                value.wrappedValue = (range.lowerBound + f * (range.upperBound - range.lowerBound)).rounded()
            }
        }
    }

    /// A names LIST row — parity with the phone's Names tab (mocks/names-mac.html): a
    /// colourful name-gradient avatar, the full name, and a voice-enrollment status line.
    /// Tapping it (interactive) opens the detail editor.
    private func nameListRow(_ person: Person) -> some View {
        HStack(spacing: NameRowLook.rowSpacing) {
            nameAvatar(person.displayName, size: NameRowLook.avatarSize)
            VStack(alignment: .leading, spacing: NameRowLook.textSpacing) {
                Text(person.displayName).font(.system(size: NameRowLook.nameSize, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                voiceStatus(PersonEditCore.isEnrolled(person))
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: NameRowLook.chevronSize, weight: .semibold))
                .foregroundStyle(Theme.textMuted.opacity(0.6))
        }
        .padding(.vertical, NameRowLook.verticalPadding).padding(.horizontal, NameRowLook.horizontalPadding)
        .contentShape(Rectangle())
    }

    /// Colourful initials avatar (name-gradient) — the phone's `Avatar`, ported so both
    /// apps' Names screens read as one product.
    private func nameAvatar(_ name: String, size: CGFloat) -> some View {
        let palette = Self.avatarPalettes[Self.avatarIndex(name)]
        return Circle()
            .fill(LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(Text(StableHash.initials(name))
                .font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(.white))
    }

    private static let avatarPalettes: [[Color]] = [
        [srgb(124, 107, 245), srgb(157, 139, 255)],   // purple
        [srgb( 52, 211, 153), srgb( 16, 185, 129)],   // green
        [srgb(245, 158,  11), srgb(249, 115,  22)],   // amber
        [srgb( 56, 189, 248), srgb( 59, 130, 246)],   // blue
    ]
    private static func srgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: 1)
    }
    /// Stable per-name palette pick (consistent across launches, unlike `hashValue`).
    private static func avatarIndex(_ name: String) -> Int {
        StableHash.index(name, count: avatarPalettes.count)
    }

    /// Voice-enrollment status for a names row (the phone's row): "Voice enrolled" (green +
    /// bar glyph) when a voiceprint is synced, else "Add voice" (accent + waveform).
    @ViewBuilder private func voiceStatus(_ enrolled: Bool) -> some View {
        if enrolled {
            HStack(spacing: 6) {
                voiceBars
                Text(NamesCopy.voiceEnrolled)
            }
            .font(.system(size: NameRowLook.statusSize, weight: .semibold)).foregroundStyle(Theme.green)
            .help("A voiceprint is enrolled — Conversation mode can recognise this person.")
        } else {
            HStack(spacing: 6) {
                Image(systemName: "waveform").font(.system(size: 11))
                Text(NamesCopy.voiceMissing)
            }
            .font(.system(size: NameRowLook.statusSize, weight: .semibold)).foregroundStyle(Theme.accent)
            .help(NamesCopy.voiceMissingHint)
        }
    }

    /// Static 5-bar voice glyph (the phone's `VoiceBars`).
    private var voiceBars: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array([CGFloat(5), 11, 7, 13, 6].enumerated()), id: \.offset) { _, h in
                Capsule().fill(Theme.green).frame(width: 2.5, height: h)
            }
        }
    }

    // ── Helpers ─────────────────────────────────────────────
    private func fieldBox<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.system(size: 12))
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(Theme.hairline.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline.opacity(0.08), lineWidth: 1))
    }

    private func bind(_ key: WritableKeyPath<AppSettings, String>) -> Binding<String> {
        Binding(get: { settings[keyPath: key] }, set: { settings[keyPath: key] = $0 })
    }

    /// Prompt edits are dated LWW writes (the iPad prompt sync): the setter stamps
    /// `promptsModifiedAt` so the autosave persists text + stamp together. The
    /// CloudKit push rides the window-close hook (per keystroke would spam).
    private func bindPrompt(_ key: WritableKeyPath<AppSettings, String>) -> Binding<String> {
        Binding(get: { settings[keyPath: key] },
                set: { settings[keyPath: key] = $0; settings.promptsModifiedAt = Date() })
    }

    // MARK: - Transcription language

    /// The Mac's half of the language mode (2026-07-26). It had NO such control: it
    /// always built the English-tuned config, so Dutch transcribed measurably worse here
    /// than on the phone. Picking a mode stamps it and pushes, so it reaches the other
    /// devices; `TranscriptionService` rebuilds its manager when the flag changes.
    @ViewBuilder private var languageRow: some View {
        HStack {
            Text("Language").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Picker("", selection: languageBinding) {
                ForEach(ASRLanguageMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityIdentifier("setting-transcription-language")
        }
        Text(ASRLanguageMode.footer)
            .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var languageBinding: Binding<ASRLanguageMode> {
        Binding(
            get: { .from(multilingual: settings.transcriptionIsMultilingual) },
            set: { mode in
                settings.transcriptionMultilingual = mode.isMultilingual
                // Stamp = "chosen here", which is what wins LWW over a device that never
                // picked; then push so the phone/iPad see it without waiting for a sweep.
                settings.transcriptionLanguageModifiedAt = Date()
                persist()
                VocabularyCloudSync.run()
                // The config is baked into the loaded manager — drop it so the next
                // transcription rebuilds with the chosen mode.
                Task { await TranscriptionService.shared.unload() }
            })
    }

    private var highpassBinding: Binding<Double> {
        Binding(get: { Double(settings.highpassFreqHz) }, set: { settings.highpassFreqHz = Int($0) })
    }

    // MARK: - Custom words (vocabulary boost)

    /// Settings → Transcription → Custom words: the vocabulary-boost list
    /// (`VocabularyBooster` CTC spot + rescore). Mirrors the phone's editor.
    @ViewBuilder private var customWordsEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(SettingsCopy.customWordsHelp)
                .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if interactive {
                HStack(spacing: 6) {
                    RingedField(placeholder: SettingsCopy.customWordPlaceholder, text: $newCustomWord)
                        .frame(maxWidth: 220)
                        .onSubmit { addCustomWord() }
                    Button { addCustomWord() } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(newCustomWord.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("settings.customword.add")
                }
            }
            ForEach(settings.customWords, id: \.self) { word in
                HStack(spacing: 8) {
                    Text(word).font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if interactive {
                        Button {
                            settings.customVocabulary = settings.customWords.filter { $0 != word }
                            commitVocabEdit()
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.textMuted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(word)")
                    }
                }
                .frame(maxWidth: 280, alignment: .leading)
            }
        }
        .padding(.top, 4)
    }

    private func addCustomWord() {
        let trimmed = newCustomWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !settings.customWords.contains(where: { $0.lowercased() == trimmed.lowercased() })
        else { newCustomWord = ""; return }
        settings.customVocabulary = settings.customWords + [trimmed]
        newCustomWord = ""
        commitVocabEdit()
    }

    /// A vocab edit is a dated LWW write: stamp it, persist NOW (`.onChange` fires only
    /// after this event), and push it to CloudKit (no-op if CloudKit-Mac sync is off) —
    /// mirroring the names push-on-edit above.
    private func commitVocabEdit() {
        settings.customVocabularyModifiedAt = Date()
        persist()
        VocabularyCloudSync.run()
    }

    /// Autosave: write only what changed since the last save, over whatever is on disk NOW
    /// (`SettingsStore.saveEdit`), so a stale open sheet can't overwrite a vocab/language/prompt
    /// value a CloudKit runner just landed (Q241 bug 6).
    private func persist() {
        SettingsStore.shared.saveEdit(from: savedBaseline, to: settings)
        savedBaseline = settings
    }

    private func chooseFolder(_ key: WritableKeyPath<AppSettings, String>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            settings[keyPath: key] = url.path
        }
    }


    private var highpassHelp: String {
        let hz = settings.highpassFreqHz
        return hz == 0
            ? "Off — no filtering. Raise it to cut low-frequency rumble (AC hum, handling noise) before transcription."
            : "Cuts everything below \(hz) Hz before transcription — removes low rumble/hum. 80 Hz is a safe default; drag to 0 to turn it off."
    }
}

/// A boxed plain text field with a visible accent focus ring — `.plain` suppresses
/// the system focus ring, so keyboard focus was invisible in the forms (AUD-P2b).
struct RingedField: View {
    var placeholder: String = ""
    @Binding var text: String
    var font: Font = .system(size: 12)
    @FocusState private var focused: Bool
    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain).font(font).foregroundStyle(Theme.textPrimary)
            .focused($focused)
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(Theme.hairline.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(focused ? Theme.accent.opacity(0.6) : Theme.hairline.opacity(0.08), lineWidth: focused ? 1.5 : 1))
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}
