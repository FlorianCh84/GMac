import Foundation

struct ScheduledSendEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let draftId: String
    let scheduledDate: Date
    let subject: String
    let to: [String]
    let threadId: String?
    let senderEmail: String

    init(draftId: String, scheduledDate: Date, subject: String, to: [String], threadId: String?, senderEmail: String) {
        self.id = UUID()
        self.draftId = draftId
        self.scheduledDate = scheduledDate
        self.subject = subject
        self.to = to
        self.threadId = threadId
        self.senderEmail = senderEmail
    }
}
