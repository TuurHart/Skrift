import SwiftUI

/// Voice-first Names (mockup3): people + a voice-fingerprint status (enrolled vs
/// "Add voice"). NO alias editing on the phone (the Mac owns aliases; the phone
/// syncs them silently) and NO "synced on Mac" footer. The phone never links
/// names into transcripts — it's just a peer editor + the place to enroll voices.
struct NamesListView: View {
    @State private var people: [Person] = []
    @State private var search = ""
    @State private var showAdd = false
    private let store = NamesStore.shared

    /// Pushed from Settings → relies on the parent NavigationStack (no own stack).
    var body: some View {
        ZStack {
            Color.skBg.ignoresSafeArea()
            content
        }
        .navigationTitle("Names")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityIdentifier("add-person-button")
            }
        }
        .sheet(isPresented: $showAdd) { AddPersonView { reload() } }
        .onAppear(perform: reload)
    }

    @ViewBuilder private var content: some View {
        if people.isEmpty {
            ContentUnavailableView(
                "No people yet",
                systemImage: "person.2",
                description: Text("Add people so the Mac can link their names in your notes.")
            )
            .accessibilityIdentifier("names-empty")
        } else {
            ScrollView {
                Text("Enroll a voice so Conversation mode can tell who's speaking.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.skTextFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.top, 4)

                SearchField(text: $search, prompt: "Search people")
                    .padding(.horizontal, 16).padding(.top, 8)

                LazyVStack(spacing: 0) {
                    ForEach(filtered, id: \.canonical) { person in
                        NavigationLink {
                            PersonDetailView(canonical: person.canonical, onChange: reload)
                        } label: {
                            PersonRow(person: person)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("person-\(NamesDisplay.name(person))")
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8)
            }
        }
    }

    private var filtered: [Person] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return people }
        return people.filter { NamesDisplay.name($0).lowercased().contains(q) }
    }

    private func reload() { people = store.livePeople() }
}

// MARK: - Row

private struct PersonRow: View {
    let person: Person

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: NamesDisplay.name(person))
            VStack(alignment: .leading, spacing: 5) {
                Text(NamesDisplay.name(person))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.skText)
                voiceStatus
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.skTextFaint)
        }
        .padding(.vertical, 11).padding(.horizontal, 6)
        // A plain 0.5pt rule — NOT `Divider()` in an overlay, which renders as a full-height
        // VERTICAL line (SwiftUI quirk, visible as a stray center line down the list on iOS 26).
        .overlay(alignment: .bottom) { Rectangle().fill(Color.skBorder).frame(height: 0.5) }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var voiceStatus: some View {
        if NamesDisplay.isEnrolled(person) {
            HStack(spacing: 6) {
                VoiceBars()
                Text("Voice enrolled")
            }
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.skGreen)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "waveform").font(.system(size: 12))
                Text("Add voice")
            }
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.skAccent)
        }
    }
}

/// Initials avatar with a name-derived gradient.
struct Avatar: View {
    let name: String
    var size: CGFloat = 42

    private static let palettes: [[Color]] = [
        [Color(hex: 0x7c6bf5), Color(hex: 0x9d8bff)],
        [Color(hex: 0x34d399), Color(hex: 0x10b981)],
        [Color(hex: 0xf59e0b), Color(hex: 0xf97316)],
        [Color(hex: 0x38bdf8), Color(hex: 0x3b82f6)],
    ]

    var body: some View {
        let palette = Self.palettes[abs(name.hashValue) % Self.palettes.count]
        Circle()
            .fill(LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(.white)
            )
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.count > 1 ? (parts.last?.first.map(String.init) ?? "") : ""
        return (first + last).uppercased()
    }
}

/// Static 5-bar voice glyph for the "enrolled" state.
struct VoiceBars: View {
    private let heights: [CGFloat] = [5, 11, 7, 13, 6]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(heights.indices, id: \.self) { i in
                Capsule().fill(Color.skGreen).frame(width: 2.5, height: heights[i])
            }
        }
    }
}

/// Name/enrollment helpers.
enum NamesDisplay {
    static func name(_ person: Person) -> String { person.displayName }
    static func isEnrolled(_ person: Person) -> Bool { !(person.voiceEmbeddings?.isEmpty ?? true) }
}

// MARK: - Add person (name only; aliases are Mac-side)

struct AddPersonView: View {
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var short = ""
    private let store = NamesStore.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Full name", text: $name)
                        .accessibilityIdentifier("person-name-field")
                    TextField("Short name (optional)", text: $short)
                        .accessibilityIdentifier("person-short-field")
                } footer: {
                    Text("Aliases and name-linking are managed on your Mac — the phone keeps them in sync.")
                }
            }
            .navigationTitle("Add Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("save-person-button")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        store.upsert(canonical: name, aliases: [], short: short.isEmpty ? nil : short)
        onSave()
        dismiss()
    }
}
