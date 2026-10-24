import Foundation

/// One model call: the prompt, the text, the token cap → the model's RAW output (untrimmed).
/// The live MLX engine (`EnhancementService.generate`) and the recorded-output replay
/// (`ModelOutputCache`) both have this shape, so every deterministic step around the model
/// runs MLX-free in the unit tests (Q423, C7/C286).
typealias ModelGenerate = @Sendable (_ prompt: String, _ text: String, _ maxTokens: Int) async throws -> String

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

/// An `Enhancing` around one `ModelGenerate`: copy-edit v2 and its title/summary turn, with the
/// model a closure (the corpus runs pass the recorded-output replay, the recorder the live model).
struct GenerateEnhancer: Enhancing {
    let generate: ModelGenerate

    func copyEdit(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
        try await copyEdit(transcript, spoken: true, prompts: prompts, modelRepo: modelRepo)
    }
    func copyEdit(_ transcript: String, spoken: Bool, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
        try await CopyEditV2.copyEdit(transcript, spoken: spoken, prompt: prompts.effectiveCopyEdit, generate: generate).text
    }
    func title(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
        try await CopyEditV2.turn(prompt: prompts.effectiveTitle, body: transcript, maxTokens: 64, generate: generate)
    }
    func summary(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
        try await CopyEditV2.turn(prompt: prompts.effectiveSummary, body: transcript, maxTokens: 256, generate: generate)
    }
}
