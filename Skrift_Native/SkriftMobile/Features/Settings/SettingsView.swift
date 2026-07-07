import SwiftUI

/// Settings (mockup2): iCloud sync status, capture toggles, library
/// (Names & voices, weather key), theme, version. A root tab (AppTabView);
/// Names pushes within its own stack.
struct SettingsView: View {
    @AppStorage("liveTranscription") private var liveTranscription = true
    // Auto-stop live captions after N seconds of recording (0 = never) — long
    // battery-saving recordings drop live captioning and transcribe once at stop.
    @AppStorage("liveCaptionAutoOffSeconds") private var liveCaptionAutoOffSeconds = 60
    @AppStorage("appTheme") private var appTheme = "dark"
    @AppStorage("weatherAPIKey") private var weatherKey = ""
    @AppStorage("karaokeTapToSeek") private var karaokeTapToSeek = true
    // Key mirrored by MemoSaver.autoCopySettingKey (default OFF — user-locked).
    @AppStorage("autoCopyTranscript") private var autoCopyTranscript = false
    // Key = TranscriptionService.multilingualKey. false = English (v3 default, cleanest
    // English); true = Multilingual (mel-off, fixes non-English drift). TranscriptionService
    // rebuilds the model when this flips.
    @AppStorage("transcriptionMultilingual") private var transcriptionMultilingual = false
    @State private var showFeedback = false
    /// Global CloudKit (device↔device) sync activity → the honest "iCloud" status row.
    @ObservedObject private var cloudSync = CloudSyncMonitor.shared

    private var customWordsCount: String {
        let n = CustomVocabularyStore.words().count
        return n == 0 ? "None" : "\(n)"
    }

    var body: some View {
        NavigationStack {
            Form {
                // The honest GLOBAL sync state (no per-note badge — CloudKit doesn't
                // expose reliable per-row status). "Syncing…" while in flight, else
                // "Up to date".
                Section {
                    HStack {
                        Label("iCloud sync", systemImage: "icloud")
                        Spacer()
                        if cloudSync.isSyncing {
                            ProgressView().controlSize(.mini)
                            Text("Syncing…").foregroundStyle(Color.skTextDim)
                        } else {
                            Text("Up to date").foregroundStyle(Color.skTextDim)
                        }
                    }
                    .accessibilityIdentifier("icloud-status")

                    NavigationLink {
                        SyncedAudiobooksView()
                    } label: {
                        Label("Synced audiobooks", systemImage: "books.vertical")
                    }
                } footer: {
                    Text("Your memos, names, and custom words sync across your devices via iCloud. Audiobooks sync per-book — turn one on from its long-press menu.")
                }

                Section {
                    Toggle("Live transcription", isOn: $liveTranscription)
                        .accessibilityIdentifier("setting-live-transcription")
                    if liveTranscription {
                        Picker("Stop live captions after", selection: $liveCaptionAutoOffSeconds) {
                            Text("Never").tag(0)
                            Text("30 seconds").tag(30)
                            Text("1 minute").tag(60)
                            Text("2 minutes").tag(120)
                        }
                        .accessibilityIdentifier("setting-live-caption-auto-off")
                    }
                    Toggle("Copy transcript to clipboard", isOn: $autoCopyTranscript)
                        .accessibilityIdentifier("setting-auto-copy-transcript")
                    Picker("Language", selection: $transcriptionMultilingual) {
                        Text("English").tag(false)
                        Text("Multilingual").tag(true)
                    }
                    .accessibilityIdentifier("setting-transcription-language")
                    NavigationLink {
                        CustomWordsView()
                    } label: {
                        HStack {
                            Text("Custom words")
                            Spacer()
                            Text(customWordsCount).foregroundStyle(Color.skTextDim)
                        }
                    }
                    .accessibilityIdentifier("custom-words-link")
                } header: {
                    Text("Capture")
                } footer: {
                    Text("Language: keep English for the cleanest English; switch to Multilingual when recording Dutch or other languages (it stops the model drifting to English on non-English speech). When a transcription finishes, the final transcript is copied to the clipboard automatically. Custom words teach the transcriber names it mis-hears (like “Skrift”).")
                }

                Section {
                    Toggle("Tap words to seek", isOn: $karaokeTapToSeek)
                        .accessibilityIdentifier("setting-tap-to-seek")
                } header: {
                    Text("Playback")
                } footer: {
                    Text("While audio plays, tap a word in the transcript to jump there.")
                }

                Section("Library") {
                    NavigationLink {
                        NamesListView()
                    } label: {
                        Text("Names & voices")
                    }
                    .accessibilityIdentifier("names-link")
                    NavigationLink {
                        ModelsView()
                    } label: {
                        Text("Models")
                    }
                    .accessibilityIdentifier("models-link")
                    NavigationLink {
                        WeatherKeyView(key: $weatherKey)
                    } label: {
                        HStack {
                            Text("Weather API key")
                            Spacer()
                            Text(maskedKey).foregroundStyle(Color.skTextDim)
                        }
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appTheme) {
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                        Text("Auto").tag("auto")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Feedback") {
                    Button { showFeedback = true } label: {
                        Label("Send feedback", systemImage: "paperplane")
                    }
                    .accessibilityIdentifier("send-feedback-button")
                }

                Section("About") {
                    // Read from the bundle (was hardcoded "0.1.0" → never reflected the
                    // actual build). Shows "0.1.0 (5)" so you can confirm which build a
                    // device is running — bump CFBundleVersion per install to tell them apart.
                    HStack {
                        Text("Version"); Spacer()
                        Text({
                            let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                            let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
                            return "\(v) (\(b))"
                        }()).foregroundStyle(Color.skTextDim)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.skBg.ignoresSafeArea())
            .navigationTitle("Settings")
            // No "Done": Settings is a root tab now (AppTabView), not a presented
            // sheet — there's nothing to dismiss.
            .sheet(isPresented: $showFeedback) { FeedbackCaptureView() }
        }
    }

    private var maskedKey: String {
        guard !weatherKey.isEmpty else { return "Not set" }
        return "••••••" + String(weatherKey.suffix(2))
    }
}

private struct WeatherKeyView: View {
    @Binding var key: String

    var body: some View {
        Form {
            Section {
                TextField("OpenWeatherMap key", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("weather-key-field")
            } footer: {
                Text("Used to tag memos with weather + pressure. Get a free key at openweathermap.org.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.skBg.ignoresSafeArea())
        .navigationTitle("Weather API key")
        .navigationBarTitleDisplayMode(.inline)
    }
}
