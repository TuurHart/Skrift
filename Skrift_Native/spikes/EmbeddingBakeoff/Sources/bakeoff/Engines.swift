import Foundation
import NaturalLanguage
import CoreMLLLM

// ── Engine A: Apple NLContextualEmbedding (0 MB, OS assets) ──

final class AppleEmbedder: SpikeEmbedder {
    let name = "NLContextualEmbedding (latin)"
    private let embedding: NLContextualEmbedding

    init() throws {
        guard let e = NLContextualEmbedding(script: .latin) else {
            throw Bail("no latin NLContextualEmbedding model on this OS")
        }
        embedding = e
    }

    func prepare() async throws {
        if !embedding.hasAvailableAssets {
            print("downloading NLContextualEmbedding assets…")
            let ok = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
                embedding.requestAssets { result, error in
                    if let error { cont.resume(throwing: error) }
                    else { cont.resume(returning: result == .available) }
                }
            }
            guard ok else { throw Bail("NL assets not available") }
        }
        try embedding.load()
        print("NLContextualEmbedding loaded · dimension \(embedding.dimension)")
    }

    func embed(_ text: String, isQuery: Bool) throws -> [Float] {
        let result = try embedding.embeddingResult(for: text, language: nil)
        var sum = [Double](repeating: 0, count: embedding.dimension)
        var count = 0
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
            for (i, v) in vector.enumerated() { sum[i] += v }
            count += 1
            return true
        }
        guard count > 0 else { throw Bail("no token vectors for text") }
        return normalize(sum.map { Float($0 / Double(count)) })
    }
}

// ── Engine B: EmbeddingGemma-300M via CoreML-LLM (295 MB download, ANE) ──

final class GemmaEmbedder: SpikeEmbedder {
    let name: String
    private let model: EmbeddingGemma
    private let dim: Int

    init(model: EmbeddingGemma, dim: Int) {
        self.model = model
        self.dim = dim
        name = "EmbeddingGemma-300M (dim \(dim))"
    }

    static func load() async throws -> EmbeddingGemma {
        let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Models")
        print("loading EmbeddingGemma (downloads 295 MB on first run) → \(dir.path)")
        return try await EmbeddingGemma.downloadAndLoad(modelsDir: dir)
    }

    func embed(_ text: String, isQuery: Bool) throws -> [Float] {
        let v = try model.encode(text: text,
                                 task: isQuery ? .retrievalQuery : .retrievalDocument,
                                 dim: dim)
        return normalize(v)
    }
}
