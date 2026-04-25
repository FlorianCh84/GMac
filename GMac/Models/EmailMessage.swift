import Foundation

struct EmailMessage: Identifiable {
    let id: String
    let threadId: String
    let snippet: String
    let subject: String
    let from: String
    let to: [String]
    let date: Date
    let bodyHTML: String?
    let bodyPlain: String?
    let labelIds: [String]
    let isUnread: Bool
}
