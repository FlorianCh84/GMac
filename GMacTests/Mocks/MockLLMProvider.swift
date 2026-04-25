import Foundation
@testable import GMac

final class MockLLMProvider: LLMProvider, @unchecked Sendable {
    let type: LLMProviderType = .claude
    var stubbedReply: String = ""
    var stubbedOpinion: String = ""
    var stubbedRefinement: String = ""
    var shouldThrowNoAPIKey: Bool = false

    func generateReply(thread: EmailThread, instruction: UserInstruction) async throws -> String {
        if shouldThrowNoAPIKey { throw LLMError.noAPIKey }; return stubbedReply
    }
    func requestOpinion(thread: EmailThread) async throws -> String {
        if shouldThrowNoAPIKey { throw LLMError.noAPIKey }; return stubbedOpinion
    }
    func refine(conversation: LLMConversation, instruction: String) async throws -> String {
        if shouldThrowNoAPIKey { throw LLMError.noAPIKey }; return stubbedRefinement
    }
}
