import Foundation

final class ClaudeProvider: LLMProvider, Sendable {
    let type: LLMProviderType = .claude
    private let keychain: any KeychainServiceProtocol
    private let model: String

    init(keychain: any KeychainServiceProtocol = KeychainService(), model: String = LLMProviderType.claude.defaultModel) {
        self.keychain = keychain; self.model = model
    }

    func generateReply(thread: EmailThread, instruction: UserInstruction) async throws -> String {
        let toneSource = ToneContextResolver.resolve(thread: thread, sentMessages: instruction.toneExamples)
        let conversation = PromptBuilder.buildReplyPrompt(thread: thread, instruction: instruction, toneSource: toneSource)
        return try await complete(conversation: conversation)
    }

    func requestOpinion(thread: EmailThread) async throws -> String {
        try await complete(conversation: PromptBuilder.buildOpinionPrompt(thread: thread))
    }

    func refine(conversation: LLMConversation, instruction: String) async throws -> String {
        try await complete(conversation: PromptBuilder.buildRefinementPrompt(existing: conversation, instruction: instruction))
    }

    func generateReplyStream(thread: EmailThread, instruction: UserInstruction) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let apiKey = try? keychain.retrieve(key: "claude_api_key"), !apiKey.isEmpty else {
                        continuation.finish(throwing: LLMError.noAPIKey); return
                    }
                    let toneSource = ToneContextResolver.resolve(thread: thread, sentMessages: instruction.toneExamples)
                    let conversation = PromptBuilder.buildReplyPrompt(thread: thread, instruction: instruction, toneSource: toneSource)
                    struct Msg: Encodable { let role: String; let content: String }
                    struct Req: Encodable {
                        let model: String; let maxTokens: Int; let stream: Bool
                        let system: String; let messages: [Msg]
                        enum CodingKeys: String, CodingKey { case model, stream, system, messages; case maxTokens = "max_tokens" }
                    }
                    let sys = conversation.messages.first(where: { $0.role == .system })?.content ?? ""
                    let msgs = conversation.messages.filter { $0.role != .system }.map { Msg(role: $0.role.rawValue, content: $0.content) }
                    let body = Req(model: model, maxTokens: 1024, stream: true, system: sys, messages: msgs)
                    var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(body)
                    let (bytes, _) = try await URLSession.shared.bytes(for: request)
                    for try await line in bytes.lines {
                        if let chunk = SSEParser.parseClaudeDelta(line) { continuation.yield(chunk) }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
    }

    private func complete(conversation: LLMConversation) async throws -> String {
        guard let apiKey = try? keychain.retrieve(key: "claude_api_key"), !apiKey.isEmpty else { throw LLMError.noAPIKey }
        struct Msg: Encodable { let role: String; let content: String }
        struct Req: Encodable {
            let model: String; let maxTokens: Int; let system: String; let messages: [Msg]
            enum CodingKeys: String, CodingKey { case model, system, messages; case maxTokens = "max_tokens" }
        }
        struct Resp: Decodable { struct C: Decodable { let text: String }; let content: [C] }
        let sys = conversation.messages.first(where: { $0.role == .system })?.content ?? ""
        let msgs = conversation.messages.filter { $0.role != .system }.map { Msg(role: $0.role.rawValue, content: $0.content) }
        let body = Req(model: model, maxTokens: 1024, system: sys, messages: msgs)
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await URLSession.shared.data(for: req)
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        guard let text = resp.content.first?.text else { throw LLMError.emptyResponse }
        return text
    }
}
