import SwiftUI
import AppKit

/// Preferences — Obsidian vault paths, author, enhancement model + prompts,
/// transcription preprocessing, and a names overview. Bound to `SettingsStore`
/// (autosaves on change). `interactive: false` renders text fields as plain Text
/// for snapshot verification (ImageRenderer can't draw AppKit TextFields).
struct SettingsView: View {
    var onClose: () -> Void = {}
    var interactive = true

    @State private var settings = SettingsStore.shared.load()
    @State private var people: [Person] = NamesStore.shared.livePeople()

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
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("Vault & author") {
                textRow("Author", \.authorName, placeholder: "Your name")
                folderRow("Obsidian vault", \.noteFolder)
                textRow("Audio subfolder", \.audioFolder, placeholder: "Voice Memos")
                textRow("Attachments subfolder", \.attachmentsFolder, placeholder: "Attachments")
            }
            section("Enhancement") {
                textRow("Model (HuggingFace repo)", \.enhancementModelRepo)
                promptRow("Copy-edit prompt", \.prompts.copyEdit)
                promptRow("Title prompt", \.prompts.title)
                promptRow("Summary prompt", \.prompts.summary)
            }
            section("Transcription") {
                sliderRow("Noise reduction", value: noiseBinding, range: -30...0, unit: " dB")
                sliderRow("High-pass filter", value: highpassBinding, range: 0...200, unit: " Hz")
            }
            section("Names · \(people.count)") {
                if people.isEmpty {
                    Text("No people yet — names link automatically once added.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                } else {
                    ForEach(people, id: \.canonical) { person in nameRow(person) }
                    Text("Edited in names.json / the phone app · full editing here is a follow-up.")
                        .font(.system(size: 11)).foregroundStyle(Theme.textMuted).padding(.top, 2)
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
            fieldBox {
                if interactive {
                    TextField(placeholder, text: bind(key)).textFieldStyle(.plain)
                } else {
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
            GeometryReader { geo in
                let frac = (value.wrappedValue - range.lowerBound) / (range.upperBound - range.lowerBound)
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline.opacity(0.12)).frame(height: 4)
                    Capsule().fill(Theme.accent).frame(width: max(0, geo.size.width * frac), height: 4)
                    Circle().fill(.white).frame(width: 13, height: 13)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        .offset(x: geo.size.width * frac - 6.5)
                }
                .frame(maxHeight: .infinity).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    let f = min(1, max(0, g.location.x / geo.size.width))
                    value.wrappedValue = (range.lowerBound + f * (range.upperBound - range.lowerBound)).rounded()
                })
            }
            .frame(height: 14)
        }
    }

    private func nameRow(_ person: Person) -> some View {
        let canonical = person.canonical.replacingOccurrences(of: "[[", with: "").replacingOccurrences(of: "]]", with: "")
        return HStack(spacing: 8) {
            Text(canonical).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textPrimary)
            if !person.aliases.isEmpty {
                Text(person.aliases.joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            }
            Spacer()
        }
        .padding(.vertical, 3)
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

    private var noiseBinding: Binding<Double> {
        Binding(get: { Double(settings.noiseReductionDB) }, set: { settings.noiseReductionDB = Int($0) })
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
}
