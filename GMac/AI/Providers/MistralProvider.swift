import Foundation

final class MistralProvider: LLMProvider, Sendable {
    let type: LLMProviderType = .mistral
    private let keychain: any KeychainServiceProtocol
    private let model: String

    init(keychain: any KeychainServiceProtocol = KeychainService(), model: String = LLMProviderType.mistral.defaultModel) {
        self.keychain = keychain; self.model = model
    }

    func generateReply(thread: EmailThread, instruction: UserInstruction) async throws -> String {
        let toneSource = ToneContextResolver.resolve(thread: thread, sentMessages: instruction.toneExamples)
        return try await complete(conversation: PromptBuilder.buildReplyPrompt(thread: thread, instruction: instruction, toneSource: toneSource))
    }
    func requestOpinion(thread: EmailThread) async throws -> String { try await complete(conversation: PromptBuilder.buildOpinionPrompt(thread: thread)) }
    func refine(conversation: LLMConversation, instruction: String) async throws -> String { try await complete(conversation: PromptBuilder.buildRefinementPrompt(existing: conversation, instruction: instruction)) }

    private func complete(conversation: LLMConversation) async throws -> String {
        guard let apiKey = try? keychain.retrieve(key: "mistral_api_key"), !apiKey.isEmpty else { throw LLMError.noAPIKey }
        struct Msg: Encodable { let role: String; let content: String }
        struct Req: Encodable { let model: String; let messages: [Msg] }
        struct Resp: Decodable { struct Choice: Decodable { struct M: Decodable { let content: String? }; let message: M }; let choices: [Choice] }
        let body = Req(model: model, messages: conversation.messages.map { Msg(role: $0.role.rawValue, content: $0.content) })
        var req = URLRequest(url: URL(string: "https://api.mistral.ai/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let text = try JSONDecoder().decode(Resp.self, from: data).choices.first?.message.content else { throw LLMError.emptyResponse }
        return text
    }
}
