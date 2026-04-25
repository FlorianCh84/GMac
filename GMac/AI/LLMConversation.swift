import Foundation

struct LLMConversation: Sendable {
    enum Role: String, Sendable { case system, user, assistant }
    struct Message: Sendable { let role: Role; let content: String }

    var messages: [Message] = []

    mutating func append(role: Role, content: String) {
        messages.append(Message(role: role, content: content))
    }

    var lastAssistantMessage: String? {
        messages.last(where: { $0.role == .assistant })?.content
    }
}
