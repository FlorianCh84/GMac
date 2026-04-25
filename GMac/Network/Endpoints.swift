import Foundation

enum Endpoints {
    private static let gmailBaseURL: URL = {
        guard let url = URL(string: "https://gmail.googleapis.com/gmail/v1") else {
            preconditionFailure("gmailBaseURL invalide — erreur de programmation")
        }
        return url
    }()

    static let tokenURL: String = "https://oauth2.googleapis.com/token"

    static func threadsList(
        userId: String = "me",
        labelIds: [String] = ["INBOX"],
        maxResults: Int = 50,
        pageToken: String? = nil
    ) -> URL {
        var components = URLComponents(url: gmailBaseURL.appendingPathComponent("users/\(userId)/threads"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [URLQueryItem(name: "maxResults", value: "\(maxResults)")]
        items += labelIds.map { URLQueryItem(name: "labelIds", value: $0) }
        if let token = pageToken {
            items.append(URLQueryItem(name: "pageToken", value: token))
        }
        components.queryItems = items
        return components.url!
    }

    static func threadGet(userId: String = "me", id: String) -> URL {
        var components = URLComponents(url: gmailBaseURL.appendingPathComponent("users/\(userId)/threads/\(id)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "format", value: "FULL")]
        return components.url!
    }

    static func messageGet(userId: String = "me", id: String) -> URL {
        var components = URLComponents(url: gmailBaseURL.appendingPathComponent("users/\(userId)/messages/\(id)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "format", value: "FULL")]
        return components.url!
    }

    static func labelsList(userId: String = "me", pageToken: String? = nil) -> URL {
        var components = URLComponents(url: gmailBaseURL.appendingPathComponent("users/\(userId)/labels"), resolvingAgainstBaseURL: false)!
        if let token = pageToken {
            components.queryItems = [URLQueryItem(name: "pageToken", value: token)]
        }
        return components.url!
    }

    static func historyList(userId: String = "me", startHistoryId: String) -> URL {
        var components = URLComponents(url: gmailBaseURL.appendingPathComponent("users/\(userId)/history"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "startHistoryId", value: startHistoryId),
            URLQueryItem(name: "historyTypes", value: "messageAdded"),
            URLQueryItem(name: "historyTypes", value: "messageDeleted"),
            URLQueryItem(name: "historyTypes", value: "labelAdded"),
            URLQueryItem(name: "historyTypes", value: "labelRemoved")
        ]
        return components.url!
    }

    static func messageSend(userId: String = "me") -> URL {
        gmailBaseURL.appendingPathComponent("users/\(userId)/messages/send")
    }

    static func threadModify(userId: String = "me", id: String) -> URL {
        let components = URLComponents(url: gmailBaseURL.appendingPathComponent("users/\(userId)/threads/\(id)/modify"), resolvingAgainstBaseURL: false)!
        return components.url!
    }
}
