import Foundation

/// Enhancement seam: the real mlx-swift engine (`EnhancementService`) conforms;
/// the BatchRunner tests use a stub. All steps take the RAW transcript.
protocol Enhancing: Sendable {
    func copyEdit(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String
    func title(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String
    func summary(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String
    /// Q426: the copy-edit of a body whose words were spoken or typed — copy-edit v2 never
    /// re-paragraphs a typed note (C34). An engine that does not tell them apart answers with
    /// `copyEdit(_:prompts:modelRepo:)` (the default below).
    func copyEdit(_ transcript: String, spoken: Bool, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String
}

extension Enhancing {
    func copyEdit(_ transcript: String, spoken: Bool, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
        try await copyEdit(transcript, prompts: prompts, modelRepo: modelRepo)
    }
}
