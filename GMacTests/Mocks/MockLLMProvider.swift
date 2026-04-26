import Foundation
@testable import GMac

final class MockLLMProvider: LLMProvider, @unchecked Sendable {
    let type: LLMProviderType = .claude
    var stubbedReply: String = ""
    var stubbedOpinion: String = ""
    var stubbedRefinement: String = ""
    var stubbedCompletion: String = ""
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
    func complete(conversation: LLMConversation) async throws -> String {
        if shouldThrowNoAPIKey { throw LLMError.noAPIKey }; return stubbedCompletion
    }

    var stubbedStreamChunks: [String] = ["Hello ", "world", "!"]

    func generateReplyStream(thread: EmailThread, instruction: UserInstruction) -> AsyncThrowingStream<String, Error> {
        let chunks = stubbedStreamChunks
        let shouldThrow = shouldThrowNoAPIKey
        return AsyncThrowingStream { continuation in
            Task {
                if shouldThrow { continuation.finish(throwing: LLMError.noAPIKey); return }
                for chunk in chunks { continuation.yield(chunk) }
                continuation.finish()
            }
        }
    }
}
