import XCTest
@testable import GMac

final class MIMEBuilderTests: XCTestCase {

    private func decodeBase64url(_ encoded: String) -> String {
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let string = String(data: data, encoding: .utf8) else { return "" }
        return string
    }

    func test_build_containsRequiredHeaders() throws {
        let message = OutgoingMessage(to: ["bob@example.com"], subject: "Hello", body: "Test body")
        let raw = try MIMEBuilder.buildRaw(message: message, from: "alice@example.com")
        let decoded = decodeBase64url(raw)
        XCTAssertTrue(decoded.contains("To: bob@example.com"))
        XCTAssertTrue(decoded.contains("Subject: Hello"))
        XCTAssertTrue(decoded.contains("From: alice@example.com"))
        XCTAssertTrue(decoded.contains("MIME-Version: 1.0"))
    }

    func test_build_containsBody() throws {
        let message = OutgoingMessage(to: ["bob@example.com"], subject: "Hello", body: "Test body")
        let raw = try MIMEBuilder.buildRaw(message: message, from: "alice@example.com")
        let decoded = decodeBase64url(raw)
        XCTAssertTrue(decoded.contains("Test body"))
    }

    func test_build_withCC_includesCcHeader() throws {
        let message = OutgoingMessage(
            to: ["bob@example.com"],
            cc: ["carol@example.com"],
            subject: "CC Test",
            body: "Body"
        )
        let raw = try MIMEBuilder.buildRaw(message: message, from: "alice@example.com")
        let decoded = decodeBase64url(raw)
        XCTAssertTrue(decoded.contains("Cc: carol@example.com"))
    }

    func test_build_withoutCC_noCcHeader() throws {
        let message = OutgoingMessage(to: ["bob@example.com"], subject: "No CC", body: "Body")
        let raw = try MIMEBuilder.buildRaw(message: message, from: "alice@example.com")
        let decoded = decodeBase64url(raw)
        XCTAssertFalse(decoded.contains("Cc:"))
    }

    func test_build_reply_includesInReplyToAndReferences() throws {
        let message = OutgoingMessage(
            to: ["bob@example.com"],
            subject: "Re: Hello",
            body: "Reply body",
            replyToThreadId: "thread1",
            replyToMessageId: "<original@gmail.com>"
        )
        let raw = try MIMEBuilder.buildRaw(message: message, from: "alice@example.com")
        let decoded = decodeBase64url(raw)
        XCTAssertTrue(decoded.contains("In-Reply-To: <original@gmail.com>"))
        XCTAssertTrue(decoded.contains("References: <original@gmail.com>"))
    }

    func test_build_noReply_noInReplyToHeader() throws {
        let message = OutgoingMessage(to: ["bob@example.com"], subject: "Subject", body: "Body")
        let raw = try MIMEBuilder.buildRaw(message: message, from: "alice@example.com")
        let decoded = decodeBase64url(raw)
        XCTAssertFalse(decoded.contains("In-Reply-To:"))
        XCTAssertFalse(decoded.contains("References:"))
    }

    func test_build_multipleRecipients() throws {
        let message = OutgoingMessage(
            to: ["bob@example.com", "carol@example.com"],
            subject: "Multi",
            body: "Body"
        )
        let raw = try MIMEBuilder.buildRaw(message: message, from: "alice@example.com")
        let decoded = decodeBase64url(raw)
        XCTAssertTrue(decoded.contains("bob@example.com"))
        XCTAssertTrue(decoded.contains("carol@example.com"))
    }

    func test_build_nonAsciiSubject_encodedAsRFC2047() throws {
        let message = OutgoingMessage(
            to: ["bob@example.com"],
            subject: "Réunion équipe",
            body: "Body"
        )
        let raw = try MIMEBuilder.buildRaw(message: message, from: "alice@example.com")
        XCTAssertFalse(raw.isEmpty)
        let decoded = decodeBase64url(raw)
        XCTAssertTrue(decoded.contains("=?utf-8?b?"), "Le sujet non-ASCII doit être encodé RFC 2047")
    }

    func test_build_outputIsValidBase64url() throws {
        let message = OutgoingMessage(to: ["bob@example.com"], subject: "Test", body: "Body")
        let raw = try MIMEBuilder.buildRaw(message: message, from: "alice@example.com")
        XCTAssertFalse(raw.contains("+"), "base64url ne doit pas contenir +")
        XCTAssertFalse(raw.contains("/"), "base64url ne doit pas contenir /")
        XCTAssertFalse(raw.contains("="), "base64url sans padding")
    }
}
