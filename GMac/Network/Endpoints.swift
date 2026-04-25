import Foundation

enum Endpoints {
    static let gmailBase = "https://gmail.googleapis.com/gmail/v1"
    static let tokenURL = "https://oauth2.googleapis.com/token"

    static func threadsList(
        userId: String = "me",
        labelIds: [String] = ["INBOX"],
        maxResults: Int = 50,
        pageToken: String? = nil
    ) -> URL {
        var components = URLComponents(string: "\(gmailBase)/users/\(userId)/threads")!
        var items: [URLQueryItem] = [URLQueryItem(name: "maxResults", value: "\(maxResults)")]
        items += labelIds.map { URLQueryItem(name: "labelIds", value: $0) }
        if let token = pageToken {
            items.append(URLQueryItem(name: "pageToken", value: token))
        }
        components.queryItems = items
        return components.url!
    }

    static func threadGet(userId: String = "me", id: String) -> URL {
        URL(string: "\(gmailBase)/users/\(userId)/threads/\(id)?format=FULL")!
    }

    static func messageGet(userId: String = "me", id: String) -> URL {
        URL(string: "\(gmailBase)/users/\(userId)/messages/\(id)?format=FULL")!
    }

    static func labelsList(userId: String = "me", pageToken: String? = nil) -> URL {
        var components = URLComponents(string: "\(gmailBase)/users/\(userId)/labels")!
        if let token = pageToken {
            components.queryItems = [URLQueryItem(name: "pageToken", value: token)]
        }
        return components.url!
    }

    static func historyList(userId: String = "me", startHistoryId: String) -> URL {
        URL(string: "\(gmailBase)/users/\(userId)/history?startHistoryId=\(startHistoryId)&historyTypes=messageAdded&historyTypes=messageDeleted&historyTypes=labelAdded&historyTypes=labelRemoved")!
    }

    static func messageSend(userId: String = "me") -> URL {
        URL(string: "\(gmailBase)/users/\(userId)/messages/send")!
    }

    static func threadModify(userId: String = "me", id: String) -> URL {
        URL(string: "\(gmailBase)/users/\(userId)/threads/\(id)/modify")!
    }
}
