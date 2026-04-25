import Foundation

enum MIMEBuilderError: Error {
    case encodingFailed
}

enum MIMEBuilder {
    static func buildRaw(message: OutgoingMessage, from senderEmail: String) throws -> String {
        var lines: [String] = []

        lines.append("From: \(senderEmail)")
        lines.append("To: \(message.to.joined(separator: ", "))")

        if !message.cc.isEmpty {
            lines.append("Cc: \(message.cc.joined(separator: ", "))")
        }

        lines.append("Subject: \(encodeSubject(message.subject))")
        lines.append("MIME-Version: 1.0")
        lines.append("Content-Type: text/plain; charset=utf-8")
        lines.append("Content-Transfer-Encoding: quoted-printable")

        if let replyToId = message.replyToMessageId {
            lines.append("In-Reply-To: \(replyToId)")
            lines.append("References: \(replyToId)")
        }

        lines.append("")  // ligne vide séparant headers et body (RFC 2822)
        lines.append(message.body)

        let mimeString = lines.joined(separator: "\r\n")
        guard let mimeData = mimeString.data(using: .utf8) else {
            throw MIMEBuilderError.encodingFailed
        }

        return mimeData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func encodeSubject(_ subject: String) -> String {
        let isAllAscii = subject.unicodeScalars.allSatisfy { $0.value < 128 }
        if isAllAscii { return subject }
        guard let data = subject.data(using: .utf8) else { return subject }
        return "=?utf-8?b?\(data.base64EncodedString())?="
    }
}
