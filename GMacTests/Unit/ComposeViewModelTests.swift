import XCTest
@testable import GMac

@MainActor
final class ComposeViewModelTests: XCTestCase {
    var mockService: MockGmailService!
    var vm: ComposeViewModel!

    override func setUp() async throws {
        mockService = MockGmailService()
        vm = ComposeViewModel(gmailService: mockService)
    }

    func test_initialState_isIdle() {
        if case .idle = vm.sendState { } else {
            XCTFail("Initial state must be .idle, got \(vm.sendState)")
        }
    }

    func test_isValid_requiresAllFields() {
        XCTAssertFalse(vm.isValid)
        vm.to = "bob@example.com"
        XCTAssertFalse(vm.isValid)
        vm.subject = "Subject"
        XCTAssertFalse(vm.isValid)
        vm.body = "Hello"
        XCTAssertTrue(vm.isValid)
    }

    func test_send_withCountdownZero_callsAPI() async {
        vm.to = "bob@example.com"
        vm.subject = "Subject"
        vm.body = "Body"
        mockService.stubSend(.success(()))
        await vm.startSend(countdownDuration: 0)
        if case .idle = vm.sendState { } else {
            XCTFail("Expected .idle after success, got \(vm.sendState)")
        }
        XCTAssertEqual(mockService.sendCallCount, 1)
    }

    func test_send_success_clearsComposer() async {
        vm.to = "bob@example.com"
        vm.subject = "Subject"
        vm.body = "Body"
        mockService.stubSend(.success(()))
        await vm.startSend(countdownDuration: 0)
        XCTAssertTrue(vm.to.isEmpty)
        XCTAssertTrue(vm.subject.isEmpty)
        XCTAssertTrue(vm.body.isEmpty)
    }

    func test_send_failure_doesNotClearComposer() async {
        vm.to = "bob@example.com"
        vm.subject = "Subject"
        vm.body = "Body"
        mockService.stubSend(.failure(.offline))
        await vm.startSend(countdownDuration: 0)
        if case .failed(.offline) = vm.sendState { } else {
            XCTFail("Expected .failed(.offline), got \(vm.sendState)")
        }
        XCTAssertEqual(vm.to, "bob@example.com")
        XCTAssertEqual(vm.subject, "Subject")
    }

    func test_cancel_beforeCountdownExpires_preventsAPICall() async {
        vm.to = "bob@example.com"
        vm.subject = "Subject"
        vm.body = "Body"
        mockService.stubSend(.success(()))

        // startSend avec countdown court mais > 0
        let task = Task { await vm.startSend(countdownDuration: 10.0) }
        try? await Task.sleep(for: .milliseconds(50))
        // Verifier qu'on est en countdown
        if case .countdown = vm.sendState { } else {
            XCTFail("Expected .countdown state, got \(vm.sendState)")
        }
        // Annuler
        vm.cancelSend()
        try? await Task.sleep(for: .milliseconds(100))
        if case .idle = vm.sendState { } else {
            XCTFail("Expected .idle after cancel, got \(vm.sendState)")
        }
        XCTAssertEqual(mockService.sendCallCount, 0, "API ne doit pas etre appelee apres annulation")
        task.cancel()
    }

    func test_resetAfterFailure_returnsToIdle() async {
        vm.to = "bob@example.com"
        vm.subject = "Subject"
        vm.body = "Body"
        mockService.stubSend(.failure(.offline))
        await vm.startSend(countdownDuration: 0)
        vm.resetAfterFailure()
        if case .idle = vm.sendState { } else {
            XCTFail("Expected .idle after resetAfterFailure")
        }
    }

    func test_send_invalidMessage_doesNotCallAPI() async {
        // vm.to, subject, body sont tous vides
        await vm.startSend(countdownDuration: 0)
        XCTAssertEqual(mockService.sendCallCount, 0)
        if case .idle = vm.sendState { } else {
            XCTFail("Expected .idle when message invalid")
        }
    }
}
