import Foundation

enum LLMProviderType: String, CaseIterable, Sendable, Identifiable, Equatable {
    var id: String { rawValue }
    case claude = "Claude"
    case openai = "ChatGPT"
    case gemini = "Gemini"
    case mistral = "Mistral"

    var defaultModel: String {
        switch self {
        case .claude: return "claude-sonnet-4-6"
        case .openai: return "gpt-4o"
        case .gemini: return "gemini-1.5-pro"
        case .mistral: return "mistral-large-latest"
        }
    }
}

enum LLMError: Error, Sendable, Equatable {
    case noAPIKey
    case requestFailed(String)
    case decodingFailed(String)
    case emptyResponse
}

protocol LLMProvider: Sendable {
    var type: LLMProviderType { get }
    func generateReply(thread: EmailThread, instruction: UserInstruction) async throws -> String
    func requestOpinion(thread: EmailThread) async throws -> String
    func refine(conversation: LLMConversation, instruction: String) async throws -> String
    func generateReplyStream(
        thread: EmailThread,
        instruction: UserInstruction
    ) -> AsyncThrowingStream<String, Error>
    // Complétion générique sans sémantique particulière (utilisé par VoiceProfileAnalyzer etc.)
    func complete(conversation: LLMConversation) async throws -> String
}
