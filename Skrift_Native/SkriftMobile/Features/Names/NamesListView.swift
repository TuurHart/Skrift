import SwiftUI

/// Voice-first Names (mockup3): people + a voice-fingerprint status (enrolled vs
/// "Add voice"). The phone is a full peer editor: `PersonEditorView` edits aliases and short
/// names through `PersonEditCore`, new people are born through `PersonEditCore.createIfNeeded`
/// (aliases `[full, first]`), and names sync over CloudKit. The phone links names into
/// transcripts itself (C80/D77 — it is not the Mac's job) and is the place to enroll voices.
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
        // A names reconcile merged people in/out (R67) — re-read, do not wait for the next appear.
        .onReceive(NotificationCenter.default.publisher(for: .namesDidChangeFromSync)) { _ in reload() }
    }

    @ViewBuilder private var content: some View {
        if people.isEmpty {
            ContentUnavailableView(
                NamesCopy.emptyTitle,
                systemImage: "person.2",
                description: Text(NamesCopy.emptyBody)
            )
            .accessibilityIdentifier("names-empty")
        } else {
            ScrollView {
                Text("Enroll a voice so Conversation mode can tell who's speaking.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.skTextFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.top, 4)

                SearchField(text: $search, prompt: NamesCopy.searchPlaceholder)
                    .padding(.horizontal, 16).padding(.top, 8)

                LazyVStack(spacing: 0) {
                    ForEach(filtered, id: \.canonical) { person in
                        NavigationLink {
                            PersonDetailView(canonical: person.canonical, onChange: reload)
                        } label: {
                            PersonRow(person: person)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("person-\(person.displayName)")
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8)
            }
        }
    }

    private var filtered: [Person] {
        NamesFilter.apply(people, query: search)
    }

    private func reload() { people = store.livePeople() }
}

// MARK: - Row

private struct PersonRow: View {
    let person: Person

    var body: some View {
        HStack(spacing: NameRowLook.rowSpacing) {
            Avatar(name: person.displayName, size: NameRowLook.avatarSize)
            VStack(alignment: .leading, spacing: NameRowLook.textSpacing) {
                Text(person.displayName)
                    .font(.system(size: NameRowLook.nameSize, weight: .semibold))
                    .foregroundStyle(Color.skText)
                voiceStatus
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: NameRowLook.chevronSize, weight: .semibold)).foregroundStyle(Color.skTextFaint)
        }
        .padding(.vertical, NameRowLook.verticalPadding).padding(.horizontal, NameRowLook.horizontalPadding)
        // A plain 0.5pt rule — NOT `Divider()` in an overlay, which renders as a full-height
        // VERTICAL line (SwiftUI quirk, visible as a stray center line down the list on iOS 26).
        .overlay(alignment: .bottom) { Rectangle().fill(Color.skBorder).frame(height: 0.5) }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var voiceStatus: some View {
        if PersonEditCore.isEnrolled(person) {
            HStack(spacing: 6) {
                VoiceBars()
                Text(NamesCopy.voiceEnrolled)
            }
            .font(.system(size: NameRowLook.statusSize, weight: .semibold)).foregroundStyle(Color.skGreen)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "waveform").font(.system(size: NameRowLook.statusSize))
                Text(NamesCopy.voiceMissing)
            }
            .font(.system(size: NameRowLook.statusSize, weight: .semibold)).foregroundStyle(Color.skAccent)
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
        let palette = Self.palettes[StableHash.index(name, count: Self.palettes.count)]
        Circle()
            .fill(LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(.white)
            )
    }

    private var initials: String { StableHash.initials(name) }
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

// MARK: - Add person (full name + optional short; aliases default to [full, first])

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
                    TextField(NamesCopy.fullNamePlaceholder, text: $name)
                        .accessibilityIdentifier("person-name-field")
                    TextField("Short name (optional)", text: $short)
                        .accessibilityIdentifier("person-short-field")
                } footer: {
                    Text("The first name is added as an alias so the person links in your notes. Edit aliases from the person's page.")
                }
            }
            .navigationTitle(NamesCopy.newPersonTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NamesCopy.doneVerb, action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("save-person-button")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(NamesCopy.cancelVerb) { dismiss() }
                }
            }
        }
    }

    private func save() {
        PersonEditCore.createIfNeeded(fullName: name, short: short, in: store)
        NamesCloudSync.run(NotesRepository.shared)   // push to CloudKit so the Mac/iPad get it now
        onSave()
        dismiss()
    }
}
