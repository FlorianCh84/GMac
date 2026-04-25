import XCTest
@testable import GMac

final class MIMEParserTests: XCTestCase {

    func test_header_extractsByName() {
        let headers = [
            GmailAPIMessage.Header(name: "Subject", value: "Test"),
            GmailAPIMessage.Header(name: "From", value: "alice@example.com")
        ]
        XCTAssertEqual(MIMEParser.header("Subject", from: headers), "Test")
        XCTAssertEqual(MIMEParser.header("subject", from: headers), "Test") // case insensitive
        XCTAssertNil(MIMEParser.header("CC", from: headers))
        XCTAssertNil(MIMEParser.header("Subject", from: nil))
    }

    func test_decodeBase64_urlSafe() {
        let urlSafe = Data("Hello, world!".utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        XCTAssertEqual(MIMEParser.decodeBase64(urlSafe), "Hello, world!")
    }

    func test_decodeBase64_standard() {
        let standard = Data("Hello, world!".utf8).base64EncodedString()
        XCTAssertEqual(MIMEParser.decodeBase64(standard), "Hello, world!")
    }

    func test_decodeBase64_nilOnInvalidInput() {
        XCTAssertNil(MIMEParser.decodeBase64("not-valid-base64!!!"))
    }

    func test_decodeQuotedPrintable_hexSequences() {
        // "ete" en latin-1 QP
        let qp = "=C3=A9t=C3=A9"  // UTF-8 bytes pour "e"
        let result = MIMEParser.decodeQuotedPrintable(qp)
        XCTAssertFalse(result.isEmpty)
    }

    func test_decodeQuotedPrintable_softLineBreaks() {
        XCTAssertEqual(MIMEParser.decodeQuotedPrintable("Hello =\r\nworld"), "Hello world")
        XCTAssertEqual(MIMEParser.decodeQuotedPrintable("Hello =\nworld"), "Hello world")
    }

    func test_extractBody_nilPayload_returnsNil() {
        let (html, plain) = MIMEParser.extractBody(from: nil)
        XCTAssertNil(html)
        XCTAssertNil(plain)
    }

    func test_extractBody_textHtml() {
        let htmlEncoded = Data("<p>Hello</p>".utf8).base64EncodedString()
        let part = GmailAPIMessage.MessagePart(
            partId: "0",
            mimeType: "text/html",
            headers: nil,
            body: GmailAPIMessage.MessageBody(attachmentId: nil, size: 12, data: htmlEncoded),
            parts: nil
        )
        let (html, plain) = MIMEParser.extractBody(from: part)
        XCTAssertEqual(html, "<p>Hello</p>")
        XCTAssertNil(plain)
    }

    func test_extractBody_quotedPrintable() {
        let part = GmailAPIMessage.MessagePart(
            partId: "0",
            mimeType: "text/plain",
            headers: [GmailAPIMessage.Header(name: "Content-Transfer-Encoding", value: "quoted-printable")],
            body: GmailAPIMessage.MessageBody(attachmentId: nil, size: 10, data: "Hello =\r\nworld"),
            parts: nil
        )
        let (_, plain) = MIMEParser.extractBody(from: part)
        XCTAssertEqual(plain, "Hello world")
    }

    func test_parseDate_validMilliseconds() {
        let date = MIMEParser.parseDate("1745000000000")
        XCTAssertEqual(date.timeIntervalSince1970, 1745000000, accuracy: 1)
    }

    func test_parseDate_invalidInput_returnsNow() {
        let before = Date()
        let date = MIMEParser.parseDate("not-a-number")
        let after = Date()
        XCTAssertTrue(date >= before && date <= after)
    }
}
