import XCTest
@testable import GMac

@MainActor
final class SignatureEditorViewModelTests: XCTestCase {
    var mockService: MockGmailSettingsService!
    var vm: SignatureEditorViewModel!

    override func setUp() async throws {
        mockService = MockGmailSettingsService()
        vm = SignatureEditorViewModel(settingsService: mockService)
    }

    func test_load_selectsPrimaryAlias() async {
        mockService.stubSendAs(.success([
            SendAsAlias(sendAsEmail: "alice@example.com", displayName: nil, signature: "<p>Hi</p>", isDefault: true, isPrimary: true)
        ]))
        await vm.load()
        XCTAssertEqual(vm.selectedAlias?.sendAsEmail, "alice@example.com")
        XCTAssertEqual(vm.currentHTML, "<p>Hi</p>")
        XCTAssertFalse(vm.isLoading)
    }

    func test_load_failure_setsError() async {
        mockService.stubSendAs(.failure(.offline))
        await vm.load()
        XCTAssertEqual(vm.lastError, .offline)
        XCTAssertTrue(vm.aliases.isEmpty)
    }

    func test_save_success_setsSaveSuccess() async {
        mockService.stubSendAs(.success([
            SendAsAlias(sendAsEmail: "alice@example.com", displayName: nil, signature: nil, isDefault: true, isPrimary: true)
        ]))
        await vm.load()
        mockService.stubUpdateSignature(.success(()))
        await vm.save()
        XCTAssertTrue(vm.saveSuccess)
        XCTAssertNil(vm.lastError)
    }

    func test_save_noAlias_doesNotCallAPI() async {
        mockService.stubUpdateSignature(.success(()))
        await vm.save()  // selectedAlias est nil
        XCTAssertFalse(vm.saveSuccess)
    }

    func test_save_failure_setsError() async {
        mockService.stubSendAs(.success([
            SendAsAlias(sendAsEmail: "alice@example.com", displayName: nil, signature: nil, isDefault: true, isPrimary: true)
        ]))
        await vm.load()
        mockService.stubUpdateSignature(.failure(.serverError(statusCode: 500)))
        await vm.save()
        XCTAssertNotNil(vm.lastError)
        XCTAssertFalse(vm.saveSuccess)
        XCTAssertFalse(vm.isSaving, "isSaving doit être false après echec (defer)")
    }
}
