import SwiftUI
import AppKit

/// Preferences — Obsidian vault paths, author, enhancement model + prompts,
/// transcription preprocessing, and a names overview. Bound to `SettingsStore`
/// (autosaves on change). `interactive: false` renders text fields as plain Text
/// for snapshot verification (ImageRenderer can't draw AppKit TextFields).
struct SettingsView: View {
    var onClose: () -> Void = {}
    var interactive = true

    @AppStorage(AppTheme.key) private var appTheme = "dark"
    @State private var settings = SettingsStore.shared.load()
    @State private var people: [Person] = NamesStore.shared.livePeople()
    @State private var editablePeople: [EditablePerson] = []
    @State private var namesDirty = false
    @State private var nameQuery = ""

    /// Stable-identity editor row (Person has no id; its canonical changes mid-edit).
    struct EditablePerson: Identifiable {
        let id = UUID()
        var canonical: String   // display form (no [[ ]])
        var aliases: String     // comma-separated
        var short: String
        var lastModifiedAt: String
        var enrolled: Bool      // has ≥1 synced voiceprint (Conversation mode can recognise them)
        init(_ p: Person) {
            canonical = NamesMerge.keyName(p.canonical)
            aliases = p.aliases.joined(separator: ", ")
            short = p.short ?? ""
            lastModifiedAt = p.lastModifiedAt
            enrolled = !(p.voiceEmbeddings?.isEmpty ?? true)
        }
        init() { canonical = ""; aliases = ""; short = ""; lastModifiedAt = ""; enrolled = false }
        func matches(_ q: String) -> Bool {
            canonical.localizedCaseInsensitiveContains(q) || aliases.localizedCaseInsensitiveContains(q)
        }
    }

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
        .task { editablePeople = people.map(EditablePerson.init)
            .sorted { $0.canonical.localizedCaseInsensitiveCompare($1.canonical) == .orderedAscending } }
        .accessibilityIdentifier("settings.root")
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
            }
            section("Names · \(interactive ? editablePeople.count : people.count)") {
                if interactive {
                    Text("Aliases (comma-separated) are the spoken nicknames that link to a person; the full name becomes the [[link]].")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    if editablePeople.count > 5 {
                        RingedField(placeholder: "Filter names…", text: $nameQuery)
                    }
                    ForEach($editablePeople) { $ep in
                        if nameQuery.isEmpty || ep.matches(nameQuery) {
                            nameEditRow($ep)
                        }
                    }
                    HStack {
                        Button { editablePeople.append(EditablePerson()); namesDirty = true } label: {
                            Label("Add person", systemImage: "plus")
                                .font(.system(size: 12)).foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button("Save names") { saveNames() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(namesDirty ? .white : Theme.textMuted)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(namesDirty ? Theme.accent : Theme.hairline.opacity(0.06),
                                        in: RoundedRectangle(cornerRadius: 7))
                            .disabled(!namesDirty)
                    }
                    .padding(.top, 4)
                } else if people.isEmpty {
                    Text("No people yet — names link automatically once added.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                } else {
                    ForEach(people, id: \.canonical) { person in nameRow(person) }
                }
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

    private func nameEditRow(_ ep: Binding<EditablePerson>) -> some View {
        HStack(spacing: 8) {
            // Boxed, primary-text fields (ST2: the bare dim fields were hard to read) + focus rings.
            RingedField(placeholder: "Full name", text: Binding(
                get: { ep.wrappedValue.canonical },
                set: { ep.wrappedValue.canonical = $0; namesDirty = true }))
            RingedField(placeholder: "aliases, comma-separated", text: Binding(
                get: { ep.wrappedValue.aliases },
                set: { ep.wrappedValue.aliases = $0; namesDirty = true }), font: .system(size: 11))
            // The display "nickname": what mentions AFTER the first linked one render
            // as (e.g. Jack Hutton → "Jank"). Empty = first word of the full name.
            RingedField(placeholder: "short", text: Binding(
                get: { ep.wrappedValue.short },
                set: { ep.wrappedValue.short = $0; namesDirty = true }), font: .system(size: 11))
                .frame(width: 96)
            voiceTag(ep.wrappedValue.enrolled)
            Button {
                editablePeople.removeAll { $0.id == ep.wrappedValue.id }; namesDirty = true
            } label: {
                Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func saveNames() {
        let now = ISO8601.now()
        let result = editablePeople.compactMap { ep -> Person? in
            let canon = NamesMerge.normaliseCanonical(ep.canonical.trimmingCharacters(in: .whitespaces))
            guard !NamesMerge.keyName(canon).isEmpty else { return nil }
            let aliases = ep.aliases.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let short = ep.short.trimmingCharacters(in: .whitespaces)
            return Person(canonical: canon, aliases: aliases, short: short.isEmpty ? nil : short,
                          lastModifiedAt: ep.lastModifiedAt.isEmpty ? now : ep.lastModifiedAt)
        }
        _ = NamesStore.shared.writeWithSmartBumps(result)
        people = NamesStore.shared.livePeople()
        namesDirty = false
    }

    private func nameRow(_ person: Person) -> some View {
        return HStack(spacing: 8) {
            Text(person.displayName).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textPrimary)
            if !person.aliases.isEmpty {
                Text(person.aliases.joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            }
            Spacer()
            voiceTag(!(person.voiceEmbeddings?.isEmpty ?? true))
        }
        .padding(.vertical, 3)
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
