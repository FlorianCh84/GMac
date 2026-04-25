import Foundation

struct EmailThread: Identifiable {
    let id: String
    let snippet: String
    let historyId: String
    let messages: [EmailMessage]

    var subject: String { messages.first?.subject ?? "(Sans sujet)" }
    var from: String { messages.first?.from ?? "" }
    var date: Date { messages.last?.date ?? Date() }
    var isUnread: Bool { messages.contains { $0.isUnread } }
}
