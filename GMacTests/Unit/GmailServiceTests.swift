import XCTest
@testable import GMac

final class GmailServiceTests: XCTestCase {
    var mockClient: MockHTTPClient!
    var service: GmailService!

    override func setUp() {
        mockClient = MockHTTPClient()
        service = GmailService(httpClient: mockClient)
    }

    func test_fetchLabels_returnsMappedLabels() async {
        let response = GmailLabelListResponse(
            labels: [
                GmailAPILabel(id: "INBOX", name: "INBOX", type: "system", messagesUnread: 3),
                GmailAPILabel(id: "tag1", name: "Clients", type: "user", messagesUnread: nil)
            ]
        )
        mockClient.stub(response)
        let result = await service.fetchLabels()
        switch result {
        case .success(let labels):
            XCTAssertEqual(labels.count, 2)
            XCTAssertEqual(labels[0].id, "INBOX")
            XCTAssertEqual(labels[0].type, .system)
            XCTAssertEqual(labels[1].type, .user)
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func test_fetchLabels_propagatesError() async {
        mockClient.stubError(.offline)
        let result = await service.fetchLabels()
        XCTAssertEqual(result, .failure(.offline))
    }

    func test_fetchThreadList_returnsRefs() async {
        let response = GmailThreadListResponse(
            threads: [GmailThreadRef(id: "t1", snippet: "Hello", historyId: "100")],
            nextPageToken: nil,
            resultSizeEstimate: 1
        )
        mockClient.stub(response)
        let result = await service.fetchThreadList(labelId: "INBOX", pageToken: nil)
        switch result {
        case .success(let refs):
            XCTAssertEqual(refs.count, 1)
            XCTAssertEqual(refs[0].id, "t1")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func test_fetchThreadList_emptyThreads_returnsEmptyArray() async {
        let response = GmailThreadListResponse(threads: nil, nextPageToken: nil, resultSizeEstimate: 0)
        mockClient.stub(response)
        let result = await service.fetchThreadList(labelId: "INBOX", pageToken: nil)
        XCTAssertEqual(result, .success([]))
    }

    func test_fetchThread_propagatesRateLimited() async {
        mockClient.stubError(.rateLimited(retryAfter: 30))
        let result = await service.fetchThread(id: "t1")
        if case .failure(.rateLimited(let d)) = result {
            XCTAssertEqual(d, 30, accuracy: 0.001)
        } else {
            XCTFail("Expected .rateLimited")
        }
    }

    func test_archiveThread_propagatesGatewayError() async {
        mockClient.stubError(.gatewayError(statusCode: 503))
        let result = await service.archiveThread(id: "t1")
        if case .failure(.gatewayError(503)) = result {
            // OK
        } else {
            XCTFail("Expected .gatewayError(503), got \(result)")
        }
    }

    // MARK: - Task 3: send()

    func test_send_postsToCorrectEndpoint() async throws {
        let response = SendMessageResponse(id: "msg1", threadId: "t1", labelIds: ["SENT"])
        mockClient.stub(response)
        let message = OutgoingMessage(to: ["bob@example.com"], subject: "Test", body: "Hello")
        let result = await service.send(message: message, senderEmail: "alice@example.com")
        switch result {
        case .success:
            XCTAssertEqual(mockClient.callCount, 1)
            XCTAssertEqual(mockClient.lastRequest?.httpMethod, "POST")
            XCTAssertEqual(mockClient.lastRequest?.url, Endpoints.messageSend())
        case .failure(let e):
            XCTFail("Expected success, got \(e)")
        }
    }

    func test_send_serverError_propagates() async {
        mockClient.stubError(.serverError(statusCode: 500))
        let message = OutgoingMessage(to: ["bob@example.com"], subject: "Test", body: "Hello")
        let result = await service.send(message: message, senderEmail: "alice@example.com")
        if case .failure(.serverError(500)) = result { } else {
            XCTFail("Expected .serverError(500)")
        }
    }

    func test_send_withReplyThreadId_includesThreadId() async throws {
        let response = SendMessageResponse(id: "msg1", threadId: "t1", labelIds: nil)
        mockClient.stub(response)
        let message = OutgoingMessage(
            to: ["bob@example.com"],
            subject: "Re: Hello",
            body: "Reply",
            replyToThreadId: "original-thread-id"
        )
        _ = await service.send(message: message, senderEmail: "alice@example.com")
        let body = mockClient.lastRequest?.httpBody ?? Data()
        struct SendBody: Decodable { let threadId: String? }
        let decoded = try JSONDecoder().decode(SendBody.self, from: body)
        XCTAssertEqual(decoded.threadId, "original-thread-id")
    }

    // MARK: - Task 8: envoi différé

    func test_send_withScheduledDate_includesScheduleTimeInBody() async throws {
        let response = SendMessageResponse(id: "msg1", threadId: "t1", labelIds: nil)
        mockClient.stub(response)
        let futureDate = Date(timeIntervalSince1970: 1800000000)
        let message = OutgoingMessage(
            to: ["bob@example.com"],
            subject: "Later",
            body: "Scheduled",
            scheduledDate: futureDate
        )
        _ = await service.send(message: message, senderEmail: "alice@example.com")
        let bodyData = mockClient.lastRequest?.httpBody ?? Data()
        struct SendBody: Decodable { let raw: String; let scheduleTime: String? }
        let decoded = try JSONDecoder().decode(SendBody.self, from: bodyData)
        XCTAssertNotNil(decoded.scheduleTime, "scheduleTime doit être présent pour envoi différé")
    }

    func test_send_withoutScheduledDate_noScheduleTime() async throws {
        let response = SendMessageResponse(id: "msg1", threadId: "t1", labelIds: nil)
        mockClient.stub(response)
        let message = OutgoingMessage(to: ["bob@example.com"], subject: "Now", body: "Immediate")
        _ = await service.send(message: message, senderEmail: "alice@example.com")
        let bodyData = mockClient.lastRequest?.httpBody ?? Data()
        struct SendBody: Decodable { let raw: String; let scheduleTime: String? }
        let decoded = try JSONDecoder().decode(SendBody.self, from: bodyData)
        XCTAssertNil(decoded.scheduleTime, "scheduleTime doit être nil pour envoi immédiat")
    }

    // MARK: - Task 4: drafts

    func test_createDraft_returnsId() async {
        let draft = DraftMessage(id: "draft1", message: nil)
        mockClient.stub(draft)
        let message = OutgoingMessage(to: ["bob@example.com"], subject: "Draft", body: "WIP")
        let result = await service.createDraft(message: message, senderEmail: "alice@example.com")
        switch result {
        case .success(let d): XCTAssertEqual(d.id, "draft1")
        case .failure(let e): XCTFail("\(e)")
        }
    }

    func test_deleteDraft_propagatesOffline() async {
        mockClient.stubError(.offline)
        let result = await service.deleteDraft(id: "draft1")
        if case .failure(.offline) = result { } else {
            XCTFail("Expected .offline")
        }
    }
}
