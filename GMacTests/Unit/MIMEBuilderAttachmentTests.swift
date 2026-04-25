import XCTest
@testable import GMac

final class MIMEBuilderAttachmentTests: XCTestCase {

    private func decodeBase64url(_ encoded: String) -> String {
        var base64 = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64), let str = String(data: data, encoding: .utf8) else { return "" }
        return str
    }

    func test_build_withAttachment_createsMultipartMixed() throws {
        let attachment = Attachment(
            id: UUID(),
            filename: "test.txt",
            mimeType: "text/plain",
            data: Data("Hello attachment".utf8)
        )
        let message = OutgoingMessage(
            to: ["bob@example.com"],
            subject: "PJ Test",
            body: "Voir PJ",
            attachments: [attachment]
        )
        let raw = try MIMEBuilder.buildRaw(message: message, from: "alice@example.com")
        let decoded = decodeBase64url(raw)
        XCTAssertTrue(decoded.contains("multipart/mixed"), "Doit utiliser multipart/mixed si PJ")
        XCTAssertTrue(decoded.contains("test.txt"), "Doit inclure le nom de fichier")
    }

    func test_build_withoutAttachment_isNotMultipart() throws {
        let message = OutgoingMessage(to: ["bob@example.com"], subject: "Simple", body: "Body")
        let raw = try MIMEBuilder.buildRaw(message: message, from: "alice@example.com")
        let decoded = decodeBase64url(raw)
        XCTAssertFalse(decoded.contains("multipart/mixed"), "Sans PJ, pas de multipart")
    }

    func test_build_attachmentData_base64Encoded() throws {
        let data = Data("file content".utf8)
        let attachment = Attachment(id: UUID(), filename: "file.txt", mimeType: "text/plain", data: data)
        let message = OutgoingMessage(
            to: ["bob@example.com"],
            subject: "Test",
            body: "Body",
            attachments: [attachment]
        )
        let raw = try MIMEBuilder.buildRaw(message: message, from: "alice@example.com")
        let decoded = decodeBase64url(raw)
        // Le contenu de la PJ doit être encodé en base64 dans le MIME
        let expectedBase64 = data.base64EncodedString(options: .lineLength76Characters)
        XCTAssertTrue(decoded.contains(expectedBase64), "Les données de la PJ doivent être encodées en base64 avec sauts de ligne à 76 chars")
    }
}
