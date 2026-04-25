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
            ],
            nextPageToken: nil
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
}
