import SwiftUI

/// Settings → Capture → Custom words: the vocabulary-boost list. Words added
/// here are CTC-spotted + rescored into every finished transcription
/// (`VocabularyBooster`), fixing names Parakeet mis-hears ("Skrift", products,
/// people). First use downloads a ~100 MB spotter model.
struct CustomWordsView: View {
    @State private var words: [String] = CustomVocabularyStore.words()
    @State private var newWord: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField(SettingsCopy.customWordPlaceholder, text: $newWord)
                        .autocorrectionDisabled()
                        .focused($fieldFocused)
                        .onSubmit(addWord)
                        .accessibilityIdentifier("custom-word-field")
                    Button {
                        addWord()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.skAccent)
                    }
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("custom-word-add")
                }
            } footer: {
                Text(SettingsCopy.customWordsHelp)
            }

            if !words.isEmpty {
                Section("Words") {
                    ForEach(words, id: \.self) { word in
                        Text(word)
                    }
                    .onDelete { offsets in
                        words.remove(atOffsets: offsets)
                        CustomVocabularyStore.save(words)
                        VocabularyCloudSync.run(NotesRepository.shared)   // push to CloudKit now
                    }
                }
            }
        }
        .navigationTitle("Custom words")
        .navigationBarTitleDisplayMode(.inline)
        // Re-read from the store on every appearance — the `@State` initial value is only
        // evaluated once, so if this view is kept alive and revisited it would otherwise
        // show stale state. (The store itself uses UserDefaults.standard and persists.)
        .onAppear { words = CustomVocabularyStore.words() }
    }

    private func addWord() {
        // The shared add rule (Q172). Empty input keeps the field as typed (whitespace);
        // a duplicate clears it — the phone's behaviour before the fold.
        guard !newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let updated = VocabularySyncCore.adding(newWord, to: words) else {
            newWord = ""
            return
        }
        words = updated
        CustomVocabularyStore.save(words)
        VocabularyCloudSync.run(NotesRepository.shared)   // push to CloudKit so other devices get it now
        newWord = ""
        fieldFocused = true   // keep the keyboard for rapid entry
    }
}
