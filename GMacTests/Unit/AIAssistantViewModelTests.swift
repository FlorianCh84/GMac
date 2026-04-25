import XCTest
@testable import GMac

@MainActor
final class AIAssistantViewModelTests: XCTestCase {
    var mock: MockLLMProvider!
    var vm: AIAssistantViewModel!

    override func setUp() async throws {
        mock = MockLLMProvider()
        vm = AIAssistantViewModel(provider: mock)
    }

    private func thread() -> EmailThread {
        let m = EmailMessage(id: "m", threadId: "t", snippet: "Hi", subject: "Test",
            from: "bob@example.com", to: ["me@example.com"], date: Date(),
            bodyHTML: nil, bodyPlain: "Please reply", labelIds: ["INBOX"], isUnread: true, attachmentRefs: [])
        return EmailThread(id: "t", snippet: "Hi", historyId: "1", messages: [m])
    }

    func test_initialState_isIdle() { if case .idle = vm.state { } else { XCTFail() } }

    func test_generate_success_movesDone() async {
        mock.stubbedReply = "AI reply"
        await vm.generate(thread: thread(), senderEmail: "me@example.com", sentMessages: [])
        if case .done(let t) = vm.state { XCTAssertEqual(t, "AI reply") }
        else { XCTFail("Expected .done, got \(vm.state)") }
    }

    func test_generate_noAPIKey_movesFailed() async {
        mock.shouldThrowNoAPIKey = true
        await vm.generate(thread: thread(), senderEmail: "me@example.com", sentMessages: [])
        if case .failed(let msg) = vm.state { XCTAssertTrue(msg.contains("Clé API")) }
        else { XCTFail("Expected .failed") }
    }

    func test_requestOpinion_success_movesOpinionDone() async {
        mock.stubbedOpinion = "Strategic analysis"
        await vm.requestOpinion(thread: thread())
        if case .opinionDone(let t) = vm.state { XCTAssertEqual(t, "Strategic analysis") }
        else { XCTFail("Expected .opinionDone") }
    }

    func test_reset_returnsToIdle() async {
        mock.stubbedReply = "Reply"
        await vm.generate(thread: thread(), senderEmail: "me@example.com", sentMessages: [])
        vm.reset()
        if case .idle = vm.state { } else { XCTFail("Expected .idle after reset") }
        XCTAssertTrue(vm.freeText.isEmpty)
    }

    func test_refine_appendsToConversation() async {
        mock.stubbedReply = "Initial"
        mock.stubbedRefinement = "Shorter"
        let t = thread()
        await vm.generate(thread: t, senderEmail: "me@example.com", sentMessages: [])
        vm.refinementText = "Make it shorter"
        await vm.refine(thread: t)
        if case .done(let text) = vm.state { XCTAssertEqual(text, "Shorter") }
        else { XCTFail("Expected .done after refine") }
        // Vérifier que le tour user du raffinement est dans la conversation
        XCTAssertTrue(vm.conversation.messages.contains { $0.role == .user && $0.content == "Make it shorter" },
            "L'instruction de raffinement doit être dans la conversation avant la réponse")
    }

    func test_isGenerating_trueWhileGenerating() { XCTAssertFalse(vm.isGenerating) }

    func test_generateStreaming_accumulatesChunks() async {
        mock.stubbedStreamChunks = ["Hello ", "world", "!"]
        await vm.generateStreaming(thread: thread(), senderEmail: "me@example.com", sentMessages: [])
        if case .done(let text) = vm.state {
            XCTAssertEqual(text, "Hello world!")
        } else { XCTFail("Expected .done with accumulated text, got \(vm.state)") }
    }

    func test_generateStreaming_noAPIKey_movesFailed() async {
        mock.shouldThrowNoAPIKey = true
        await vm.generateStreaming(thread: thread(), senderEmail: "me@example.com", sentMessages: [])
        if case .failed(let msg) = vm.state {
            XCTAssertTrue(msg.contains("Clé API"))
        } else { XCTFail("Expected .failed") }
    }
}
