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
        .onChange(of: settings) { _, new in SettingsStore.shared.save(new) }
        .task { reloadNames() }
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
        let people = displayPeople
        return nameQuery.isEmpty ? people : people.filter {
            NamesMerge.keyName($0.canonical).localizedCaseInsensitiveContains(nameQuery)
                || $0.aliases.contains { $0.localizedCaseInsensitiveContains(nameQuery) }
        }
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
                folderRow("Obsidian vault", \.noteFolder)
                subfolderRow("Audio subfolder", \.audioFolder, placeholder: "Voice Memos")
                subfolderRow("Attachments subfolder", \.attachmentsFolder, placeholder: "Attachments")
            }
            section("Enhancement") {
                textRow("Model (HuggingFace repo)", \.enhancementModelRepo)
                promptRow("Copy-edit prompt", \.prompts.copyEdit)
                promptRow("Title prompt", \.prompts.title)
                promptRow("Summary prompt", \.prompts.summary)
            }
            section("Transcription") {
                sliderRow("High-pass filter", value: highpassBinding, range: 0...200, unit: " Hz")
                Text(highpassHelp).font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                customWordsEditor
            }
            section("Sync") {
                toggleRow("CloudKit sync with the Mac", \.cloudKitMacSync,
                          help: "Process memos your phone synced over iCloud — no Wi-Fi pairing, no app foregrounded — and sync the Mac's polished title/summary/copy-edit back to your phone. Needs the Mac signed into the same iCloud account. The local-network “Pair a Mac” path still works as a fallback when this is off.")
                if settings.cloudKitMacSync ?? false {
                    toggleRow("Process every synced memo", \.processAllSyncedMemos,
                              help: "By default the Mac only processes memos you rated (significance > 0), matching the phone's flag-to-send. Turn this on to process every synced memo regardless of rating.")
                }
            }
            section("Names · \(displayPeople.count)") {
                Text("Tap a person to edit their full name, aliases, short name, and voice. Aliases are the spoken nicknames that link to them; the full name becomes the [[link]].")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if interactive && displayPeople.count > 6 {
                    RingedField(placeholder: "Filter names…", text: $nameQuery)
                }
                if displayPeople.isEmpty {
                    Text("No people yet — add the ones your notes are about.")
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
    /// A label + switch over an OPTIONAL Bool setting (nil → off), with help text below.
    /// Renders the state as "On"/"Off" text in snapshot mode (ImageRenderer can't draw a switch).
    private func toggleRow(_ label: String, _ key: WritableKeyPath<AppSettings, Bool?>, help: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                Spacer()
                if interactive {
                    Toggle("", isOn: Binding(
                        get: { settings[keyPath: key] ?? false },
                        set: { settings[keyPath: key] = $0 }
                    ))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                } else {
                    Text((settings[keyPath: key] ?? false) ? "On" : "Off")
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
                    Button("Choose…") { chooseFolder(key) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12)).foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.hairline.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }

    private func promptRow(_ label: String, _ key: WritableKeyPath<AppSettings, String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            Group {
                if interactive {
                    TextEditor(text: bind(key))
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

    /// A names LIST row (mocks/opt-in-naming.html panel 4): avatar initials · full name ·
    /// "aka" alias summary · voice chip. Tapping it (interactive) opens the detail editor.
    private func nameListRow(_ person: Person) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.16)).frame(width: 30, height: 30)
                Text(Self.initials(person.displayName))
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(person.displayName).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                if !person.aliases.isEmpty {
                    Text("aka " + person.aliases.joined(separator: ", "))
                        .font(.system(size: 11)).foregroundStyle(Theme.textMuted).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            voiceTag(!(person.voiceEmbeddings?.isEmpty ?? true))
        }
        .padding(.vertical, 5).padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    /// One- or two-letter avatar initials from a full name.
    private static func initials(_ name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        let s = words.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return s.isEmpty ? "?" : s
    }

    /// Voice-enrollment indicator (parity with the phone's Names & voices). Green
    /// "Voice" when the person has a synced voiceprint → Conversation mode can attribute
    /// speech to them; a faint "No voice" otherwise.
    @ViewBuilder private func voiceTag(_ enrolled: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform").font(.system(size: 9, weight: .semibold))
            Text(enrolled ? "Voice" : "No voice").font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(enrolled ? Theme.green : Theme.textMuted)
        .help(enrolled ? "A voiceprint is enrolled — Conversation mode can recognise this person."
                       : "No voiceprint yet — name them in a conversation (phone or Mac) to enroll their voice.")
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

    private var highpassBinding: Binding<Double> {
        Binding(get: { Double(settings.highpassFreqHz) }, set: { settings.highpassFreqHz = Int($0) })
    }

    // MARK: - Custom words (vocabulary boost)

    /// Settings → Transcription → Custom words: the vocabulary-boost list
    /// (`VocabularyBooster` CTC spot + rescore). Mirrors the phone's editor.
    @ViewBuilder private var customWordsEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Custom words — names the transcriber mis-hears (“Skrift”, people, products), spelled as they should be written. First transcription after adding words downloads a ~100 MB spotter model.")
                .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if interactive {
                HStack(spacing: 6) {
                    RingedField(placeholder: "Add a word…", text: $newCustomWord)
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

    // A subfolder NAME (relative to the vault), with a picker rooted at the vault. (ST3)
    private func subfolderRow(_ label: String, _ key: WritableKeyPath<AppSettings, String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
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
                if interactive {
                    Button("Choose…") { chooseSubfolder(key) }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.hairline.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                        .disabled(settings.noteFolder.isEmpty)
                }
            }
        }
    }

    /// Pick a subfolder rooted at the vault; store the path RELATIVE to the vault
    /// (a name like "Voice Memos"), or the folder name if chosen elsewhere.
    private func chooseSubfolder(_ key: WritableKeyPath<AppSettings, String>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if !settings.noteFolder.isEmpty { panel.directoryURL = URL(fileURLWithPath: settings.noteFolder) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let vault = settings.noteFolder
        if !vault.isEmpty, url.path.hasPrefix(vault) {
            let rel = String(url.path.dropFirst(vault.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            settings[keyPath: key] = rel.isEmpty ? url.lastPathComponent : rel
        } else {
            settings[keyPath: key] = url.lastPathComponent
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
