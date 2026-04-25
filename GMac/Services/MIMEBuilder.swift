import Foundation

enum MIMEBuilderError: Error {
    case encodingFailed
}

enum MIMEBuilder {
    static func buildRaw(message: OutgoingMessage, from senderEmail: String) throws -> String {
        let mimeString: String

        if message.attachments.isEmpty {
            mimeString = try buildSimpleMIME(message: message, from: senderEmail)
        } else {
            mimeString = try buildMultipartMIME(message: message, from: senderEmail)
        }

        guard let mimeData = mimeString.data(using: .utf8) else {
            throw MIMEBuilderError.encodingFailed
        }
        return mimeData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func buildCommonHeaders(message: OutgoingMessage, from senderEmail: String) throws -> [String] {
        var lines: [String] = []
        lines.append("From: \(senderEmail)")
        lines.append("To: \(message.to.joined(separator: ", "))")
        if !message.cc.isEmpty { lines.append("Cc: \(message.cc.joined(separator: ", "))") }
        lines.append("Subject: \(try encodeSubject(message.subject))")
        if let replyToId = message.replyToMessageId {
            lines.append("In-Reply-To: \(replyToId)")
            lines.append("References: \(replyToId)")
        }
        return lines
    }

    private static func buildSimpleMIME(message: OutgoingMessage, from senderEmail: String) throws -> String {
        var lines = try buildCommonHeaders(message: message, from: senderEmail)
        lines.append("MIME-Version: 1.0")
        let contentType = message.isHTML ? "text/html; charset=utf-8" : "text/plain; charset=utf-8"
        lines.append("Content-Type: \(contentType)")
        lines.append("Content-Transfer-Encoding: 8bit")

        lines.append("")  // ligne vide séparant headers et body (RFC 2822)
        lines.append(message.body)

        return lines.joined(separator: "\r\n")
    }

    private static func buildMultipartMIME(message: OutgoingMessage, from senderEmail: String) throws -> String {
        let boundary = "GMac_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var lines = try buildCommonHeaders(message: message, from: senderEmail)
        lines.append("MIME-Version: 1.0")
        lines.append("Content-Type: multipart/mixed; boundary=\"\(boundary)\"")
        lines.append("")

        // Body part
        lines.append("--\(boundary)")
        let bodyContentType = message.isHTML ? "text/html; charset=utf-8" : "text/plain; charset=utf-8"
        lines.append("Content-Type: \(bodyContentType)")
        lines.append("Content-Transfer-Encoding: 8bit")
        lines.append("")
        lines.append(message.body)

        // Attachment parts
        for attachment in message.attachments {
            lines.append("--\(boundary)")
            lines.append("Content-Type: \(attachment.mimeType); name=\"\(attachment.filename)\"")
            lines.append("Content-Transfer-Encoding: base64")
            lines.append("Content-Disposition: attachment; filename=\"\(attachment.filename)\"")
            lines.append("")
            lines.append(attachment.data.base64EncodedString(options: .lineLength76Characters))
        }

        lines.append("--\(boundary)--")
        return lines.joined(separator: "\r\n")
    }

    private static func encodeSubject(_ subject: String) throws -> String {
        let isAllAscii = subject.unicodeScalars.allSatisfy { $0.value < 128 }
        if isAllAscii { return subject }
        guard let data = subject.data(using: .utf8) else {
            throw MIMEBuilderError.encodingFailed
        }
        return "=?utf-8?b?\(data.base64EncodedString())?="
    }
}
