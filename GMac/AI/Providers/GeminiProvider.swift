import Foundation

final class GeminiProvider: LLMProvider, Sendable {
    let type: LLMProviderType = .gemini
    private let keychain: any KeychainServiceProtocol
    private let model: String

    init(keychain: any KeychainServiceProtocol = KeychainService(), model: String = LLMProviderType.gemini.defaultModel) {
        self.keychain = keychain; self.model = model
    }

    func generateReply(thread: EmailThread, instruction: UserInstruction) async throws -> String {
        let toneSource = ToneContextResolver.resolve(thread: thread, sentMessages: instruction.toneExamples)
        return try await complete(conversation: PromptBuilder.buildReplyPrompt(thread: thread, instruction: instruction, toneSource: toneSource))
    }
    func requestOpinion(thread: EmailThread) async throws -> String { try await complete(conversation: PromptBuilder.buildOpinionPrompt(thread: thread)) }
    func refine(conversation: LLMConversation, instruction: String) async throws -> String { try await complete(conversation: PromptBuilder.buildRefinementPrompt(existing: conversation, instruction: instruction)) }

    func generateReplyStream(thread: EmailThread, instruction: UserInstruction) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let text = try await generateReply(thread: thread, instruction: instruction)
                    continuation.yield(text)
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
    }

    private func complete(conversation: LLMConversation) async throws -> String {
        guard let apiKey = try? keychain.retrieve(key: "gemini_api_key"), !apiKey.isEmpty else { throw LLMError.noAPIKey }
        struct Part: Encodable { let text: String }
        struct Content: Encodable { let role: String; let parts: [Part] }
        struct Req: Encodable { let contents: [Content] }
        struct RespPart: Decodable { let text: String? }
        struct RespContent: Decodable { let parts: [RespPart] }
        struct Candidate: Decodable { let content: RespContent }
        struct Resp: Decodable { let candidates: [Candidate] }
        let sys = conversation.messages.first(where: { $0.role == .system })?.content ?? ""
        var contents: [Content] = []
        var injected = false
        for msg in conversation.messages where msg.role != .system {
            let prefix = (!injected && !sys.isEmpty) ? "\(sys)\n\n" : ""
            contents.append(Content(role: msg.role == .user ? "user" : "model", parts: [Part(text: prefix + msg.content)]))
            injected = true
        }
        var req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(Req(contents: contents))
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let text = try JSONDecoder().decode(Resp.self, from: data).candidates.first?.content.parts.first?.text else { throw LLMError.emptyResponse }
        return text
    }
}
