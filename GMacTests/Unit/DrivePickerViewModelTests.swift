import XCTest
@testable import GMac

@MainActor
final class DrivePickerViewModelTests: XCTestCase {
    var mockService: MockDriveService!
    var vm: DrivePickerViewModel!

    override func setUp() async throws {
        mockService = MockDriveService()
        vm = DrivePickerViewModel(driveService: mockService)
    }

    func test_load_populatesFiles() async {
        mockService.stubList(.success([
            DriveFile(id: "f1", name: "Report.pdf", mimeType: "application/pdf", size: "102400", modifiedTime: nil)
        ]))
        await vm.load()
        XCTAssertEqual(vm.files.count, 1)
        XCTAssertEqual(vm.files[0].name, "Report.pdf")
        XCTAssertFalse(vm.isLoading)
    }

    func test_load_failure_setsError() async {
        mockService.stubList(.failure(.offline))
        await vm.load()
        XCTAssertEqual(vm.lastError, .offline)
        XCTAssertTrue(vm.files.isEmpty)
    }

    func test_isLoading_falseAfterLoad() async {
        mockService.stubList(.success([]))
        await vm.load()
        XCTAssertFalse(vm.isLoading)
    }
}
