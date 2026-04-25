// swiftlint:disable force_unwrapping
import Foundation

enum Endpoints {
    private static let driveBase = "https://www.googleapis.com/drive/v3"
    private static let driveUploadBase = "https://www.googleapis.com/upload/drive/v3"

    static func driveFilesList() -> URL {
        var c = URLComponents(string: "\(driveBase)/files")!
        c.queryItems = [
            URLQueryItem(name: "orderBy", value: "modifiedTime desc"),
            URLQueryItem(name: "pageSize", value: "30"),
            URLQueryItem(name: "fields", value: "files(id,name,mimeType,size,modifiedTime),nextPageToken")
        ]
        guard let url = c.url else { preconditionFailure("driveFilesList URL invalide") }
        return url
    }

    static func driveFilesUpload() -> URL {
        var c = URLComponents(string: "\(driveUploadBase)/files")!
        c.queryItems = [URLQueryItem(name: "uploadType", value: "multipart")]
        guard let url = c.url else { preconditionFailure("driveFilesUpload URL invalide") }
        return url
    }

    static func driveFileDownload(id: String) -> URL {
        var c = URLComponents()
        c.scheme = "https"; c.host = "www.googleapis.com"
        c.path = "/drive/v3/files/\(id)"
        c.queryItems = [URLQueryItem(name: "alt", value: "media")]
        guard let url = c.url else { preconditionFailure("driveFileDownload URL invalide") }
        return url
    }

    static func gmailAttachment(userId: String = "me", messageId: String, attachmentId: String) -> URL {
        var c = URLComponents()
        c.scheme = "https"; c.host = "gmail.googleapis.com"
        c.path = "/gmail/v1/users/\(userId)/messages/\(messageId)/attachments/\(attachmentId)"
        guard let url = c.url else { preconditionFailure("gmailAttachment URL invalide") }
        return url
    }

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

    static func draftCreate(userId: String = "me") -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "gmail.googleapis.com"
        components.path = "/gmail/v1/users/\(userId)/drafts"
        guard let url = components.url else {
            preconditionFailure("draftCreate URL invalide")
        }
        return url
    }

    private static func draftResourceURL(userId: String, id: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "gmail.googleapis.com"
        components.path = "/gmail/v1/users/\(userId)/drafts/\(id)"
        guard let url = components.url else {
            preconditionFailure("draftResourceURL invalide — erreur de programmation")
        }
        return url
    }

    static func draftUpdate(userId: String = "me", id: String) -> URL {
        draftResourceURL(userId: userId, id: id)
    }

    static func draftDelete(userId: String = "me", id: String) -> URL {
        draftResourceURL(userId: userId, id: id)
    }

    static func threadModify(userId: String = "me", id: String) -> URL {
        let components = URLComponents(url: gmailBaseURL.appendingPathComponent("users/\(userId)/threads/\(id)/modify"), resolvingAgainstBaseURL: false)!
        return components.url!
    }

    static func sendAsList(userId: String = "me") -> URL {
        var c = URLComponents()
        c.scheme = "https"; c.host = "gmail.googleapis.com"
        c.path = "/gmail/v1/users/\(userId)/settings/sendAs"
        guard let url = c.url else { preconditionFailure("sendAsList URL invalide") }
        return url
    }

    static func sendAsUpdate(userId: String = "me", sendAsEmail: String) -> URL {
        let encoded = sendAsEmail.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sendAsEmail
        var c = URLComponents()
        c.scheme = "https"; c.host = "gmail.googleapis.com"
        c.path = "/gmail/v1/users/\(userId)/settings/sendAs/\(encoded)"
        guard let url = c.url else { preconditionFailure("sendAsUpdate URL invalide") }
        return url
    }

    static func vacationSettings(userId: String = "me") -> URL {
        var c = URLComponents()
        c.scheme = "https"; c.host = "gmail.googleapis.com"
        c.path = "/gmail/v1/users/\(userId)/settings/vacation"
        guard let url = c.url else { preconditionFailure("vacationSettings URL invalide") }
        return url
    }

    static func labelCreate(userId: String = "me") -> URL {
        var c = URLComponents()
        c.scheme = "https"; c.host = "gmail.googleapis.com"
        c.path = "/gmail/v1/users/\(userId)/labels"
        guard let url = c.url else { preconditionFailure("labelCreate URL invalide") }
        return url
    }

    private static func labelResourceURL(userId: String, id: String) -> URL {
        var c = URLComponents()
        c.scheme = "https"; c.host = "gmail.googleapis.com"
        c.path = "/gmail/v1/users/\(userId)/labels/\(id)"
        guard let url = c.url else { preconditionFailure("labelResourceURL invalide") }
        return url
    }

    static func labelUpdate(userId: String = "me", id: String) -> URL {
        labelResourceURL(userId: userId, id: id)
    }

    static func labelDelete(userId: String = "me", id: String) -> URL {
        labelResourceURL(userId: userId, id: id)
    }
}
