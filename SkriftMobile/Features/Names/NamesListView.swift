import SwiftUI

/// Phase 5 **placeholder** Names screen — plain list/add/delete over the existing
/// `NamesStore` (the bidirectional Mac sync already shipped in Phase 1). Delete
/// writes a tombstone. The designed version comes in the visual-polish pass.
struct NamesListView: View {
    @State private var people: [Person] = []
    @State private var showAdd = false
    @Environment(\.dismiss) private var dismiss
    private let store = NamesStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if people.isEmpty {
                    ContentUnavailableView(
                        "No people yet",
                        systemImage: "person.2",
                        description: Text("Add people so the Mac can link their names in your notes.")
                    )
                    .accessibilityIdentifier("names-empty")
                } else {
                    List {
                        ForEach(people, id: \.canonical) { person in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Self.displayName(person)).font(.headline)
                                if !person.aliases.isEmpty {
                                    Text(person.aliases.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                            .accessibilityIdentifier("person-row")
                        }
                        .onDelete(perform: delete)
                    }
                    .accessibilityIdentifier("names-list")
                }
            }
            .navigationTitle("Names")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityIdentifier("add-person-button")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddPersonView { reload() }
            }
            .onAppear(perform: reload)
        }
    }

    private func reload() { people = store.livePeople() }

    private func delete(at offsets: IndexSet) {
        for index in offsets { store.delete(canonical: people[index].canonical) }
        reload()
    }

    static func displayName(_ person: Person) -> String {
        let canonical = person.canonical
        return (canonical.hasPrefix("[[") && canonical.hasSuffix("]]"))
            ? String(canonical.dropFirst(2).dropLast(2))
            : canonical
    }
}

struct AddPersonView: View {
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var short = ""
    @State private var aliasText = ""
    private let store = NamesStore.shared

    var body: some View {
        NavigationStack {
            Form {
                TextField("Full name", text: $name)
                    .accessibilityIdentifier("person-name-field")
                TextField("Short name (optional)", text: $short)
                    .accessibilityIdentifier("person-short-field")
                TextField("Aliases (comma-separated)", text: $aliasText)
                    .accessibilityIdentifier("person-aliases-field")
            }
            .navigationTitle("Add Person")
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
        let aliases = aliasText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        store.upsert(canonical: name, aliases: aliases, short: short.isEmpty ? nil : short)
        onSave()
        dismiss()
    }
}
