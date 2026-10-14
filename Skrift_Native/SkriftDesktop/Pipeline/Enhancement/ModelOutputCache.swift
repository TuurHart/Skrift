import CryptoKit
import Foundation

/// Recorded model outputs (C7, C286): one file per model call,
/// `<dir>/<sha256(prompt + input)>.txt`, holding the model's raw output. Recorded once over
/// the synthetic corpus by the DEBUG `-recordcopyedit` harness (MLX app); replayed MLX-free
/// by `CopyEditDiffHarnessTests`. The key is the exact prompt text followed by the exact
/// input text the model was given (UTF-8, no separator), hex-encoded.
struct ModelOutputCache: Sendable {
    let directory: URL

    /// A replay asked for a call nobody recorded. Never silent: the error names the key.
    struct Miss: LocalizedError {
        let key: String
        var errorDescription: String? { "model-output cache miss: \(key).txt (re-record with -recordcopyedit)" }
    }

    static func key(prompt: String, input: String) -> String {
        SHA256.hash(data: Data((prompt + input).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func url(forKey key: String) -> URL { directory.appendingPathComponent("\(key).txt") }

    func lookup(prompt: String, input: String) -> String? {
        try? String(contentsOf: url(forKey: Self.key(prompt: prompt, input: input)), encoding: .utf8)
    }

    /// Replay only: a hit returns the recorded output, a miss throws `Miss` (the MLX-free
    /// harness cannot run the model live).
    var replay: ModelGenerate {
        let cache = self
        return { prompt, text, _ in
            guard let out = cache.lookup(prompt: prompt, input: text) else {
                throw Miss(key: Self.key(prompt: prompt, input: text))
            }
            return out
        }
    }

    /// Record: run `live`, write its raw output under the key, return it.
    func recording(_ live: @escaping ModelGenerate) -> ModelGenerate {
        let cache = self
        return { prompt, text, maxTokens in
            let out = try await live(prompt, text, maxTokens)
            try FileManager.default.createDirectory(at: cache.directory, withIntermediateDirectories: true)
            try Data(out.utf8).write(to: cache.url(forKey: Self.key(prompt: prompt, input: text)))
            return out
        }
    }
}
