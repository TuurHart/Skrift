import Foundation

/// Enhancement seam: the real mlx-swift engine (`EnhancementService`) conforms;
/// the BatchRunner tests use a stub. All steps take the RAW transcript.
protocol Enhancing: Sendable {
    func copyEdit(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String
    func title(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String
    func summary(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String
}
