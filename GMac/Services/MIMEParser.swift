import Foundation

enum MIMEParser {
    static func header(_ name: String, from headers: [GmailAPIMessage.Header]?) -> String? {
        headers?.first { $0.name.lowercased() == name.lowercased() }?.value
    }

    static func decodeBase64(_ encoded: String) -> String? {
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }

    static func decodeQuotedPrintable(_ input: String) -> String {
        var result = input
        result = result.replacingOccurrences(of: "=\r\n", with: "")
        result = result.replacingOccurrences(of: "=\n", with: "")

        let pattern = "=[0-9A-Fa-f]{2}"
        var output = ""
        var remaining = result[...]
        while let range = remaining.range(of: pattern, options: .regularExpression) {
            output += remaining[..<range.lowerBound]
            let hex = String(remaining[range].dropFirst())
            if let byte = UInt8(hex, radix: 16) {
                output += String(bytes: [byte], encoding: .isoLatin1) ?? ""
            }
            remaining = remaining[range.upperBound...]
        }
        output += remaining
        return output
    }

    static func extractBody(from part: GmailAPIMessage.MessagePart?) -> (html: String?, plain: String?) {
        guard let part else { return (nil, nil) }
        return extractBodyRecursive(from: part)
    }

    static func parseDate(_ internalDate: String?) -> Date {
        guard let raw = internalDate, let ms = Double(raw) else { return Date() }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    // MARK: - Private

    private static func extractBodyRecursive(
        from part: GmailAPIMessage.MessagePart
    ) -> (html: String?, plain: String?) {
        var html: String?
        var plain: String?

        let transferEncoding = part.headers?
            .first { $0.name.lowercased() == "content-transfer-encoding" }?
            .value.lowercased()

        func decodeBody(_ data: String?) -> String? {
            guard let data else { return nil }
            switch transferEncoding {
            case "quoted-printable": return decodeQuotedPrintable(data)
            default: return decodeBase64(data)
            }
        }

        switch part.mimeType {
        case "text/html":
            html = decodeBody(part.body?.data)
        case "text/plain":
            plain = decodeBody(part.body?.data)
        default:
            for subpart in part.parts ?? [] {
                let (h, p) = extractBodyRecursive(from: subpart)
                if html == nil { html = h }
                if plain == nil { plain = p }
            }
        }
        return (html, plain)
    }
}
