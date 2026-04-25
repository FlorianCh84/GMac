import Foundation

struct GmailThreadListResponse: Decodable, Sendable {
    let threads: [GmailThreadRef]?
    let nextPageToken: String?
    let resultSizeEstimate: Int?
}

struct GmailThreadRef: Decodable, Sendable, Equatable {
    let id: String
    let snippet: String
    let historyId: String
}

struct GmailAPIThread: Decodable, Sendable {
    let id: String
    let snippet: String
    let historyId: String
    let messages: [GmailAPIMessage]?
}

struct GmailAPIMessage: Decodable, Sendable {
    let id: String
    let threadId: String
    let labelIds: [String]?
    let snippet: String?
    let payload: MessagePart?
    let internalDate: String?

    struct MessagePart: Decodable, Sendable {
        let partId: String?
        let mimeType: String?
        let headers: [Header]?
        let body: MessageBody?
        let parts: [MessagePart]?
    }

    struct Header: Decodable, Sendable {
        let name: String
        let value: String
    }

    struct MessageBody: Decodable, Sendable {
        let attachmentId: String?
        let size: Int
        let data: String?
    }
}

struct GmailLabelListResponse: Decodable, Sendable {
    let labels: [GmailAPILabel]
}

struct GmailAPILabel: Decodable, Sendable {
    let id: String
    let name: String
    let type: String?
    let messagesUnread: Int?
}

struct GmailHistoryListResponse: Decodable, Sendable {
    let history: [HistoryRecord]?
    let historyId: String
    let nextPageToken: String?

    struct HistoryRecord: Decodable, Sendable {
        let id: String
        let messages: [GmailAPIMessage]?
        let messagesAdded: [MessageAdded]?
        let messagesDeleted: [MessageDeleted]?
        let labelsAdded: [LabelChange]?
        let labelsRemoved: [LabelChange]?
    }

    struct MessageAdded: Decodable, Sendable { let message: GmailAPIMessage }
    struct MessageDeleted: Decodable, Sendable { let message: GmailAPIMessage }
    struct LabelChange: Decodable, Sendable {
        let message: GmailAPIMessage
        let labelIds: [String]
    }
}
