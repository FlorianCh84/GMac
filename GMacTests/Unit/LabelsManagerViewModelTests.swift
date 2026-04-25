import XCTest
@testable import GMac

@MainActor
final class LabelsManagerViewModelTests: XCTestCase {
    var mockGmail: MockGmailService!
    var mockSettings: MockGmailSettingsService!
    var vm: LabelsManagerViewModel!

    override func setUp() async throws {
        mockGmail = MockGmailService()
        mockSettings = MockGmailSettingsService()
        vm = LabelsManagerViewModel(gmailService: mockGmail, settingsService: mockSettings)
    }

    func test_load_showsOnlyUserLabels() async {
        mockGmail.stubLabels(.success([
            GmailLabel(id: "INBOX", name: "INBOX", type: .system, messagesUnread: nil),
            GmailLabel(id: "tag1", name: "Clients", type: .user, messagesUnread: nil)
        ]))
        await vm.load()
        XCTAssertEqual(vm.labels.count, 1)
        XCTAssertEqual(vm.labels[0].name, "Clients")
    }

    func test_createLabel_addsToList() async {
        mockGmail.stubLabels(.success([]))
        await vm.load()
        mockSettings.stubCreateLabel(.success(GmailLabel(id: "new1", name: "Prospects", type: .user, messagesUnread: nil)))
        vm.newLabelName = "Prospects"
        await vm.createLabel()
        XCTAssertEqual(vm.labels.count, 1)
        XCTAssertEqual(vm.labels[0].name, "Prospects")
        XCTAssertTrue(vm.newLabelName.isEmpty)
    }

    func test_createLabel_emptyName_doesNotCallAPI() async {
        mockGmail.stubLabels(.success([]))
        await vm.load()
        vm.newLabelName = "   "
        await vm.createLabel()
        XCTAssertTrue(vm.labels.isEmpty)
    }

    func test_deleteLabel_removesFromList() async {
        vm.labels = [GmailLabel(id: "tag1", name: "Old", type: .user, messagesUnread: nil)]
        mockSettings.stubDeleteLabel(.success(()))
        await vm.deleteLabel(id: "tag1")
        XCTAssertTrue(vm.labels.isEmpty)
    }

    func test_load_failure_setsError() async {
        mockGmail.stubLabels(.failure(.offline))
        await vm.load()
        XCTAssertEqual(vm.lastError, .offline)
    }
}
