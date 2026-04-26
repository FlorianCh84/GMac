import Foundation

enum MIMEParser {
    static func header(_ name: String, from headers: [GmailAPIMessage.Header]?) -> String? {
        headers?.first { $0.name.lowercased() == name.lowercased() }?.value
    }

    static func decodeBase64(_ encoded: String) -> String? {
        guard !encoded.isEmpty else { return nil }
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        // .ignoreUnknownCharacters tolère les sauts de ligne (\n) fréquents dans les corps MIME
        // Retourne nil pour entrée vide ou base64 décodant vers 0 octets (corps d'email vide, rare).
        // L'appelant utilise alors le snippet comme fallback — dégradation gracieuse, pas de crash.
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
              !data.isEmpty else { return nil }
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

        // Comparaison insensible à la casse ET aux paramètres ("text/html; charset=utf-8" → match)
        let baseMime = part.mimeType?.lowercased()
            .components(separatedBy: ";").first?
            .trimmingCharacters(in: .whitespaces)

        if baseMime == "text/html" {
            html = decodeBody(part.body?.data)
        } else if baseMime == "text/plain" {
            plain = decodeBody(part.body?.data)
        } else {
            // Multipart ou autre → descendre dans les sous-parties
            for subpart in part.parts ?? [] {
                let (h, p) = extractBodyRecursive(from: subpart)
                if html == nil { html = h }
                if plain == nil { plain = p }
            }
            // Si aucune sous-partie, essayer le body directement comme fallback
            if html == nil && plain == nil, let data = part.body?.data, !data.isEmpty {
                plain = decodeBase64(data)
            }
        }
        return (html, plain)
    }
}
