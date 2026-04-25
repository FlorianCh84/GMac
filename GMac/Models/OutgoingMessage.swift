import Foundation

struct OutgoingMessage: Sendable {
    let to: [String]
    let cc: [String]
    let subject: String
    let body: String
    let isHTML: Bool            // true si le body est du HTML (RichTextEditor)
    let replyToThreadId: String?
    let replyToMessageId: String?
    let scheduledDate: Date?
    let attachments: [Attachment]
    let idempotencyKey: UUID

    init(
        to: [String], cc: [String] = [], subject: String, body: String,
        isHTML: Bool = false,
        replyToThreadId: String? = nil, replyToMessageId: String? = nil,
        scheduledDate: Date? = nil, attachments: [Attachment] = []
    ) {
        self.to = to; self.cc = cc; self.subject = subject; self.body = body
        self.isHTML = isHTML
        self.replyToThreadId = replyToThreadId; self.replyToMessageId = replyToMessageId
        self.scheduledDate = scheduledDate; self.attachments = attachments
        self.idempotencyKey = UUID()
    }
}
