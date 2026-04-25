import XCTest
@testable import GMac

final class ToneContextResolverTests: XCTestCase {

    private func msg(id: String = UUID().uuidString, from: String, to: [String], subject: String, labels: [String] = ["INBOX"]) -> EmailMessage {
        EmailMessage(id: id, threadId: "t", snippet: "", subject: subject, from: from, to: to, date: Date(),
                     bodyHTML: nil, bodyPlain: nil, labelIds: labels, isUnread: false, attachmentRefs: [])
    }

    func test_priority1_currentThreadReply() {
        let thread = EmailThread(id: "t1", snippet: "", historyId: "1", messages: [
            msg(from: "bob@acme.com", to: ["me@example.com"], subject: "Project"),
            msg(from: "me@example.com", to: ["bob@acme.com"], subject: "Re: Project", labels: ["SENT"])
        ])
        let source = ToneContextResolver.resolve(thread: thread, sentMessages: [])
        if case .currentThread = source { } else { XCTFail("Expected .currentThread, got \(source.label)") }
    }

    func test_priority2_knownSender() {
        let thread = EmailThread(id: "t1", snippet: "", historyId: "1", messages: [
            msg(from: "bob@acme.com", to: ["me@example.com"], subject: "New topic")
        ])
        let sent = msg(from: "me@example.com", to: ["bob@acme.com"], subject: "Old", labels: ["SENT"])
        let source = ToneContextResolver.resolve(thread: thread, sentMessages: [sent])
        if case .knownSender(let email, _) = source {
            XCTAssertEqual(email, "bob@acme.com")
        } else { XCTFail("Expected .knownSender, got \(source.label)") }
    }

    func test_priority3_sameDomain() {
        let thread = EmailThread(id: "t1", snippet: "", historyId: "1", messages: [
            msg(from: "carol@acme.com", to: ["me@example.com"], subject: "New")
        ])
        let sent = msg(from: "me@example.com", to: ["dave@acme.com"], subject: "Old", labels: ["SENT"])
        let source = ToneContextResolver.resolve(thread: thread, sentMessages: [sent])
        if case .sameDomain(let domain, _) = source {
            XCTAssertEqual(domain, "acme.com")
        } else { XCTFail("Expected .sameDomain, got \(source.label)") }
    }

    func test_priority5_globalProfile_noMatch() {
        let thread = EmailThread(id: "t1", snippet: "", historyId: "1", messages: [
            msg(from: "unknown@xyz999.io", to: ["me@example.com"], subject: "Zxqwerty unique")
        ])
        let source = ToneContextResolver.resolve(thread: thread, sentMessages: [])
        if case .globalProfile = source { } else { XCTFail("Expected .globalProfile, got \(source.label)") }
    }

    func test_toneSource_labels() {
        XCTAssertEqual(ToneSource.globalProfile.label, "Ton général")
        XCTAssertEqual(ToneSource.currentThread([]).label, "Ton de cet échange")
    }
}
