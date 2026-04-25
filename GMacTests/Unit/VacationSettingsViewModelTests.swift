import XCTest
@testable import GMac

@MainActor
final class VacationSettingsViewModelTests: XCTestCase {
    var mockService: MockGmailSettingsService!
    var vm: VacationSettingsViewModel!

    override func setUp() async throws {
        mockService = MockGmailSettingsService()
        vm = VacationSettingsViewModel(settingsService: mockService)
    }

    func test_load_populatesFields() async {
        let settings = VacationSettings(
            enableAutoReply: true, responseSubject: "Absent",
            responseBodyPlainText: "Je suis absent", responseBodyHtml: nil,
            startTime: nil, endTime: nil,
            restrictToContacts: true, restrictToDomain: nil
        )
        mockService.stubVacation(.success(settings))
        await vm.load()
        XCTAssertTrue(vm.enableAutoReply)
        XCTAssertEqual(vm.subject, "Absent")
        XCTAssertEqual(vm.bodyText, "Je suis absent")
        XCTAssertTrue(vm.restrictToContacts)
    }

    func test_load_failure_setsError() async {
        mockService.stubVacation(.failure(.offline))
        await vm.load()
        XCTAssertEqual(vm.lastError, .offline)
    }

    func test_save_callsUpdateVacation() async {
        mockService.stubUpdateVacation(.success(()))
        vm.enableAutoReply = true
        vm.subject = "Absent"
        vm.bodyText = "Retour lundi"
        await vm.save()
        XCTAssertTrue(vm.saveSuccess)
        XCTAssertNil(vm.lastError)
    }

    func test_save_failure_setsError() async {
        mockService.stubUpdateVacation(.failure(.serverError(statusCode: 500)))
        await vm.save()
        XCTAssertNotNil(vm.lastError)
        XCTAssertFalse(vm.saveSuccess)
        XCTAssertFalse(vm.isSaving, "isSaving doit être false après echec (defer)")
    }

    func test_isLoading_falseAfterLoad() async {
        mockService.stubVacation(.success(VacationSettings(
            enableAutoReply: false, responseSubject: nil, responseBodyPlainText: nil,
            responseBodyHtml: nil, startTime: nil, endTime: nil,
            restrictToContacts: nil, restrictToDomain: nil
        )))
        await vm.load()
        XCTAssertFalse(vm.isLoading)
    }
}
