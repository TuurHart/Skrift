import ExpoModulesCore
import Foundation
import FluidAudio
import AVFoundation
import UIKit

// On-device ASR via FluidAudio (Parakeet TDT v3 0.6B, multilingual —
// supports Dutch / English and 23 other European languages).
//
// `AsrManager.transcribe(url:source:)` accepts a file URL and internally
// normalises audio to 16 kHz mono Float32 via AudioConverter, so we don't
// have to decode m4a / opus / etc. ourselves.
//
// When `imageManifestJson` is supplied, we merge BPE sub-word tokens into
// whole words, then insert `[[img_NNN]]` markers at the word whose start
// timestamp is closest to each photo's offsetSeconds. Mirrors the desktop
// `_insert_image_markers` logic in backend/services/transcription.py so
// the output is bit-for-bit compatible.

private struct Word {
  let text: String
  let start: TimeInterval
  let end: TimeInterval
  var charStart: Int = 0
  var charEnd: Int = 0
}

private struct ManifestEntry: Codable {
  let filename: String
  let offsetSeconds: Double
}

public class ParakeetModule: Module {
  private var asr: AsrManager?
  private var models: AsrModels?
  private var loadTask: Task<Void, Error>?
  private var isTranscribing = false
  private var memoryWarningObserver: NSObjectProtocol?

  public func definition() -> ModuleDefinition {
    Name("ParakeetModule")

    Events("downloadProgress")

    // Free the ~600 MB ASR model under memory pressure so iOS doesn't jetsam
    // the app. It reloads from the on-disk cache on the next transcribe.
    OnCreate {
      self.memoryWarningObserver = NotificationCenter.default.addObserver(
        forName: UIApplication.didReceiveMemoryWarningNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.teardown()
      }
    }

    OnDestroy {
      if let obs = self.memoryWarningObserver {
        NotificationCenter.default.removeObserver(obs)
        self.memoryWarningObserver = nil
      }
    }

    AsyncFunction("isModelReady") { () -> Bool in
      return self.asr != nil
    }

    // Explicit unload from JS (e.g. when the model won't be needed for a while).
    // No-op while a transcription is in flight.
    AsyncFunction("unloadModel") { () -> Void in
      self.teardown()
    }

    AsyncFunction("downloadModel") { (promise: Promise) in
      Task {
        do {
          try await self.ensureLoaded()
          promise.resolve(nil)
        } catch {
          promise.reject("E_PARAKEET_DOWNLOAD", "\(error)")
        }
      }
    }

    AsyncFunction("transcribe") { (audioUri: String, imageManifestJson: String?, promise: Promise) in
      Task {
        do {
          self.isTranscribing = true
          defer { self.isTranscribing = false }
          try await self.ensureLoaded()
          guard let asr = self.asr else {
            throw NSError(domain: "Parakeet", code: 1, userInfo: [NSLocalizedDescriptionKey: "ASR not loaded"])
          }

          // Accept file:// URIs from React Native as well as raw paths.
          let url: URL
          if let parsed = URL(string: audioUri), parsed.scheme != nil {
            url = parsed
          } else {
            url = URL(fileURLWithPath: audioUri)
          }

          // Mean audio energy, used by the silence/phantom guard below.
          let rms = Self.averageRMS(url: url)

          let started = Date()
          let result = try await asr.transcribe(url, source: .system)
          let ms = Int(Date().timeIntervalSince(started) * 1000)

          // Silence/phantom guard: Parakeet TDT can hallucinate a short phantom
          // transcript on (near-)silent audio. Return nothing when the transcript
          // is empty, or when it's tiny AND audio energy is low. Conservative +
          // gated on a tiny word count so real speech is never dropped — tune the
          // threshold on device.
          let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
          let wordCount = trimmed.isEmpty ? 0 : trimmed.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
          let lowEnergy = rms.map { $0 < 0.0075 } ?? false
          if trimmed.isEmpty || (lowEnergy && wordCount <= 3) {
            promise.resolve([
              "text": "",
              "confidence": Double(result.confidence),
              "durationMs": ms,
              "wordTimings": [[String: Any]](),
              "markersInjected": false,
            ])
            return
          }

          // Merge BPE sub-word tokens → whole words.
          let words = Self.mergeBPETokens(result.tokenTimings ?? [])

          // Build wordTimings array we hand back to JS for storage.
          let wordTimings: [[String: Any]] = words.map { w in
            [
              "word": w.text,
              "start": w.start,
              "end": w.end,
            ]
          }

          // Optionally inject image markers.
          var text = result.text
          var markersInjected = false
          if let json = imageManifestJson, !json.isEmpty {
            if let manifest = Self.decodeManifest(json), !manifest.isEmpty, !words.isEmpty {
              text = Self.insertImageMarkers(transcript: text, words: words, manifest: manifest)
              markersInjected = true
            }
          }

          promise.resolve([
            "text": text,
            "confidence": Double(result.confidence),
            "durationMs": ms,
            "wordTimings": wordTimings,
            "markersInjected": markersInjected,
          ])
        } catch {
          promise.reject("E_PARAKEET_TRANSCRIBE", "\(error)")
        }
      }
    }
  }

  // MARK: - Model loading

  private func ensureLoaded() async throws {
    if asr != nil { return }
    if let loadTask = loadTask {
      try await loadTask.value
      return
    }
    // Capture self weakly so the Swift compiler is happy with @Sendable.
    let emit: @Sendable (Double, String, Int, Int) -> Void = { [weak self] frac, phase, completedFiles, totalFiles in
      self?.sendEvent("downloadProgress", [
        "fractionCompleted": frac,
        "phase": phase,
        "completedFiles": completedFiles,
        "totalFiles": totalFiles,
      ])
    }

    let task = Task<Void, Error> {
      // v3 = multilingual (25 European languages + ja/zh). Downloads from
      // HuggingFace on first call, cached locally thereafter.
      let models = try await AsrModels.downloadAndLoad(version: .v3, progressHandler: { progress in
        let phaseStr: String
        var done = 0
        var total = 0
        switch progress.phase {
        case .listing:
          phaseStr = "listing"
        case .downloading(let c, let t):
          phaseStr = "downloading"
          done = c
          total = t
        case .compiling(_):
          phaseStr = "compiling"
        }
        emit(progress.fractionCompleted, phaseStr, done, total)
      })
      let manager = AsrManager(config: .default)
      try await manager.initialize(models: models)
      self.models = models
      self.asr = manager
      // Final 1.0 / loaded event so JS can drop the download UI.
      emit(1.0, "ready", 0, 0)
    }
    self.loadTask = task
    do {
      try await task.value
      self.loadTask = nil
    } catch {
      self.loadTask = nil
      throw error
    }
  }

  // MARK: - Memory management

  /// Release the loaded ASR model + CoreML weights. No-op while transcribing or
  /// while a load is in flight (the in-flight call holds its own reference, so
  /// tearing down would only force a redundant reload).
  private func teardown() {
    guard !isTranscribing, loadTask == nil else { return }
    asr = nil
    models = nil
  }

  // MARK: - Silence detection

  /// Mean RMS amplitude across the whole file (chunked so a long recording is
  /// never fully loaded into memory). Returns nil if the file can't be read.
  private static func averageRMS(url: URL) -> Float? {
    guard let file = try? AVAudioFile(forReading: url) else { return nil }
    let format = file.processingFormat
    let frameCapacity: AVAudioFrameCount = 16384
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }
    var sumSquares: Double = 0
    var totalFrames: Double = 0
    while true {
      do {
        try file.read(into: buffer, frameCount: frameCapacity)
      } catch {
        break
      }
      let n = Int(buffer.frameLength)
      if n == 0 { break }
      guard let channels = buffer.floatChannelData else { break }
      let samples = channels[0]
      var i = 0
      while i < n {
        let s = Double(samples[i])
        sumSquares += s * s
        i += 1
      }
      totalFrames += Double(n)
    }
    if totalFrames == 0 { return nil }
    return Float((sumSquares / totalFrames).squareRoot())
  }

  // MARK: - Token merging (mirrors backend transcription.py:240-285)

  /// Merge BPE sub-word tokens into whole words. A token whose raw text
  /// starts with a space begins a new word; others are continuations.
  private static func mergeBPETokens(_ tokens: [TokenTiming]) -> [Word] {
    var words: [Word] = []
    var pending: (text: String, start: TimeInterval, end: TimeInterval)? = nil

    for token in tokens {
      let raw = token.token
      if raw.isEmpty { continue }
      let isNewWord = raw.hasPrefix(" ") || pending == nil
      let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      if clean.isEmpty { continue }
      let s = max(0.0, token.startTime)
      let e = max(s, token.endTime)

      if isNewWord {
        if let p = pending, !p.text.trimmingCharacters(in: .whitespaces).isEmpty {
          words.append(Word(
            text: p.text.trimmingCharacters(in: .whitespaces),
            start: p.start,
            end: p.end
          ))
        }
        pending = (text: clean, start: s, end: e)
      } else {
        pending?.text.append(clean)
        pending?.end = e
      }
    }
    if let p = pending, !p.text.trimmingCharacters(in: .whitespaces).isEmpty {
      words.append(Word(
        text: p.text.trimmingCharacters(in: .whitespaces),
        start: p.start,
        end: p.end
      ))
    }
    return words
  }

  // MARK: - Image marker insertion (mirrors backend transcription.py:_insert_image_markers)

  private static func decodeManifest(_ json: String) -> [ManifestEntry]? {
    guard let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode([ManifestEntry].self, from: data)
  }

  /// Insert `[[img_NNN]]` markers into the transcript at character positions
  /// matching the closest word per photo offset. Numbering ascends by offset.
  private static func insertImageMarkers(transcript: String, words: [Word], manifest: [ManifestEntry]) -> String {
    guard !words.isEmpty, !manifest.isEmpty else { return transcript }

    // Pre-compute character positions for each word by scanning sequentially.
    // Uses NSString char counts (UTF-16 code units) since that's what
    // Foundation's String.range(of:) returns. We work in UTF-16 indices the
    // whole way through and convert to String.Index at the very end.
    var indexedWords = words
    let nsTranscript = transcript as NSString
    var scanPos = 0
    let totalLen = nsTranscript.length

    let totalDuration = max(1.0, words.last?.end ?? 1.0)

    for i in indexedWords.indices {
      let needle = indexedWords[i].text as NSString
      var found = -1
      if scanPos < totalLen {
        let searchRange = NSRange(location: scanPos, length: totalLen - scanPos)
        let r = nsTranscript.range(of: needle as String, options: [], range: searchRange)
        if r.location != NSNotFound {
          found = r.location
          indexedWords[i].charStart = found
          indexedWords[i].charEnd = found + needle.length
          scanPos = found + needle.length
        }
      }
      if found == -1 {
        // Word not found (punctuation mismatch etc.). Estimate by timing.
        let estimated = Int(Double(totalLen) * indexedWords[i].start / totalDuration)
        let clamped = min(max(0, estimated), totalLen)
        indexedWords[i].charStart = clamped
        indexedWords[i].charEnd = clamped
      }
    }

    // Sort manifest ascending by offset for consistent numbering.
    let sortedManifest = manifest.sorted { $0.offsetSeconds < $1.offsetSeconds }

    // For each photo, find the word whose start time is closest to the offset.
    var insertions: [(pos: Int, marker: String)] = []
    for (i, entry) in sortedManifest.enumerated() {
      let offset = entry.offsetSeconds
      var bestIdx = 0
      var bestDiff = abs(indexedWords[0].start - offset)
      for (wi, w) in indexedWords.enumerated() {
        let diff = abs(w.start - offset)
        if diff < bestDiff {
          bestDiff = diff
          bestIdx = wi
        }
      }
      let pos = indexedWords[bestIdx].charEnd
      let marker = "\n\n[[img_\(String(format: "%03d", i + 1))]]\n\n"
      insertions.append((pos, marker))
    }

    // Apply back-to-front to preserve offsets.
    var result = transcript
    for (pos, marker) in insertions.sorted(by: { $0.pos > $1.pos }) {
      let nsResult = result as NSString
      let safePos = min(max(0, pos), nsResult.length)
      let prefix = nsResult.substring(to: safePos)
      let suffix = nsResult.substring(from: safePos)
      result = prefix + marker + suffix
    }
    return result
  }
}
