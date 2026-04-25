import XCTest
@testable import GMac

final class LLMConversationTests: XCTestCase {

    func test_append_addsMessage() {
        var c = LLMConversation()
        c.append(role: .user, content: "Hello")
        XCTAssertEqual(c.messages.count, 1)
        XCTAssertEqual(c.messages[0].content, "Hello")
        XCTAssertEqual(c.messages[0].role, .user)
    }

    func test_lastAssistantMessage_returnsLast() {
        var c = LLMConversation()
        c.append(role: .user, content: "Q")
        c.append(role: .assistant, content: "A1")
        c.append(role: .user, content: "Q2")
        c.append(role: .assistant, content: "A2")
        XCTAssertEqual(c.lastAssistantMessage, "A2")
    }

    func test_lastAssistantMessage_nilWhenNoAssistant() {
        var c = LLMConversation()
        c.append(role: .user, content: "Q")
        XCTAssertNil(c.lastAssistantMessage)
    }

    func test_userInstruction_defaults() {
        let i = UserInstruction(freeText: "Say hello")
        XCTAssertNil(i.objective)
        XCTAssertNil(i.tone)
        XCTAssertEqual(i.length, .balanced)
        XCTAssertTrue(i.toneExamples.isEmpty)
    }

    func test_llmProviderType_defaultModels() {
        XCTAssertEqual(LLMProviderType.claude.defaultModel, "claude-sonnet-4-6")
        XCTAssertEqual(LLMProviderType.openai.defaultModel, "gpt-4o")
        XCTAssertEqual(LLMProviderType.gemini.defaultModel, "gemini-1.5-pro")
        XCTAssertEqual(LLMProviderType.mistral.defaultModel, "mistral-large-latest")
    }

    func test_replyObjective_sevenCases() {
        XCTAssertEqual(ReplyObjective.allCases.count, 7)
    }

    func test_replyTone_sixCases() {
        XCTAssertEqual(ReplyTone.allCases.count, 6)
    }
}
