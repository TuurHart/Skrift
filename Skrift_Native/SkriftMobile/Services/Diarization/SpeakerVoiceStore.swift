import Foundation
import FluidAudio

/// Per-person voice samples for Sortformer enrollment (auto-match returning speakers).
/// When you name a speaker, the audio of that speaker's turns is extracted (16kHz mono
/// Float) and saved here keyed by the person; before a new recording is diarized, every
/// known sample is enrolled so Sortformer labels matching slots with the person's name.
struct SpeakerVoiceStore {
    var directory: URL = AppPaths.recordingsDirectory.appendingPathComponent("voices", isDirectory: true)

    private var manifestURL: URL { directory.appendingPathComponent("voices.json") }
    private func ensureDir() { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }

    /// person name → relative pcm filename
    private func manifest() -> [String: String] {
        guard let data = try? Data(contentsOf: manifestURL),
              let m = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return m
    }
    private func writeManifest(_ m: [String: String]) { ensureDir(); try? JSONEncoder().encode(m).write(to: manifestURL) }

    /// Extract the audio of `segments` (one speaker's turns) from `memoAudioURL`
    /// (resampled to 16kHz mono) and save it as `person`'s voice sample.
    func enroll(person: String, from memoAudioURL: URL, segments: [DiarizedSegment]) {
        guard !person.isEmpty, !segments.isEmpty,
              let all = try? AudioConverter(sampleRate: 16000).resampleAudioFile(memoAudioURL) else { return }
        var samples: [Float] = []
        for seg in segments.sorted(by: { $0.start < $1.start }) {
            let s = max(0, Int(seg.start * 16000)), e = min(all.count, Int(seg.end * 16000))
            if s < e { samples.append(contentsOf: all[s..<e]) }
        }
        guard samples.count >= 8000 else { return }   // need ≥~0.5s of voice to be useful
        save(samples, for: person)
    }

    func save(_ samples: [Float], for person: String) {
        ensureDir()
        let file = manifest()[person] ?? "voice_\(UUID().uuidString).pcm"
        samples.withUnsafeBytes { try? Data($0).write(to: directory.appendingPathComponent(file)) }
        var m = manifest(); m[person] = file; writeManifest(m)
    }

    func load(for person: String) -> [Float]? {
        guard let file = manifest()[person],
              let data = try? Data(contentsOf: directory.appendingPathComponent(file)) else { return nil }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    /// (name, samples) for every enrolled person — to enroll before diarization.
    func allKnown() -> [(name: String, samples: [Float])] {
        manifest().keys.compactMap { name in load(for: name).map { (name, $0) } }
    }

    func knownNames() -> [String] { Array(manifest().keys) }
}
