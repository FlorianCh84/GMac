import XCTest
@testable import GMac

final class GmailSettingsServiceTests: XCTestCase {
    var mockClient: MockHTTPClient!
    var service: GmailSettingsService!

    override func setUp() {
        mockClient = MockHTTPClient()
        service = GmailSettingsService(httpClient: mockClient)
    }

    func test_fetchSendAsList_returnsMappedAliases() async {
        let response = SendAsListResponse(sendAs: [
            SendAsAlias(sendAsEmail: "alice@example.com", displayName: "Alice",
                        signature: "<p>Hello</p>", isDefault: true, isPrimary: true)
        ])
        mockClient.stub(response)
        let result = await service.fetchSendAsList()
        switch result {
        case .success(let aliases):
            XCTAssertEqual(aliases.count, 1)
            XCTAssertEqual(aliases[0].sendAsEmail, "alice@example.com")
            XCTAssertEqual(aliases[0].signature, "<p>Hello</p>")
        case .failure(let e): XCTFail("\(e)")
        }
    }

    func test_fetchSendAsList_propagatesOffline() async {
        mockClient.stubError(.offline)
        let result = await service.fetchSendAsList()
        if case .failure(.offline) = result { } else {
            XCTFail("Expected .failure(.offline)")
        }
    }

    func test_updateSignature_usesPATCH() async {
        mockClient.stub(EmptyResponse())
        let result = await service.updateSignature(sendAsEmail: "alice@example.com", html: "<b>Sig</b>")
        switch result {
        case .success: XCTAssertEqual(mockClient.lastRequest?.httpMethod, "PATCH")
        case .failure(let e): XCTFail("\(e)")
        }
    }

    func test_fetchVacationSettings_returnsSettings() async {
        let settings = VacationSettings(
            enableAutoReply: true, responseSubject: "Absent",
            responseBodyPlainText: "Je suis absent", responseBodyHtml: nil,
            startTime: nil, endTime: nil, restrictToContacts: false, restrictToDomain: false
        )
        mockClient.stub(settings)
        let result = await service.fetchVacationSettings()
        switch result {
        case .success(let s):
            XCTAssertTrue(s.enableAutoReply)
            XCTAssertEqual(s.responseSubject, "Absent")
        case .failure(let e): XCTFail("\(e)")
        }
    }

    func test_updateVacationSettings_usesPUT() async {
        mockClient.stub(EmptyResponse())
        let settings = VacationSettings(enableAutoReply: false, responseSubject: nil,
            responseBodyPlainText: nil, responseBodyHtml: nil,
            startTime: nil, endTime: nil, restrictToContacts: nil, restrictToDomain: nil)
        let result = await service.updateVacationSettings(settings)
        switch result {
        case .success: XCTAssertEqual(mockClient.lastRequest?.httpMethod, "PUT")
        case .failure(let e): XCTFail("\(e)")
        }
    }

    func test_createLabel_returnsLabel() async {
        let apiLabel = GmailAPILabel(id: "label1", name: "Clients", type: "user", messagesUnread: nil)
        mockClient.stub(apiLabel)
        let result = await service.createLabel(name: "Clients")
        switch result {
        case .success(let l): XCTAssertEqual(l.id, "label1")
        case .failure(let e): XCTFail("\(e)")
        }
    }

    func test_deleteLabel_propagatesServerError() async {
        mockClient.stubError(.serverError(statusCode: 500))
        let result = await service.deleteLabel(id: "label1")
        if case .failure(.serverError(500)) = result { } else {
            XCTFail("Expected .serverError(500)")
        }
    }
}
