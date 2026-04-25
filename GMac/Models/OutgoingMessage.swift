import Foundation

struct OutgoingMessage: Sendable {
    let to: [String]
    let subject: String
    let body: String
    let replyToThreadId: String?
    let idempotencyKey: UUID

    init(to: [String], subject: String, body: String, replyToThreadId: String? = nil) {
        self.to = to
        self.subject = subject
        self.body = body
        self.replyToThreadId = replyToThreadId
        self.idempotencyKey = UUID()
    }
}
