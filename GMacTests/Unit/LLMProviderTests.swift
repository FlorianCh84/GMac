import XCTest
@testable import GMac

final class LLMProviderTests: XCTestCase {
    private func emptyThread() -> EmailThread { EmailThread(id: "t", snippet: "", historyId: "1", messages: []) }

    func test_claudeProvider_noAPIKey_throwsNoAPIKey() async {
        let p = ClaudeProvider(keychain: MockKeychainService())
        do { _ = try await p.requestOpinion(thread: emptyThread()); XCTFail() }
        catch LLMError.noAPIKey { }
        catch { XCTFail("Wrong error: \(error)") }
    }

    func test_openaiProvider_noAPIKey_throwsNoAPIKey() async {
        let p = OpenAIProvider(keychain: MockKeychainService())
        do { _ = try await p.requestOpinion(thread: emptyThread()); XCTFail() }
        catch LLMError.noAPIKey { }
        catch { XCTFail("\(error)") }
    }

    func test_mistralProvider_noAPIKey_throwsNoAPIKey() async {
        let p = MistralProvider(keychain: MockKeychainService())
        do { _ = try await p.requestOpinion(thread: emptyThread()); XCTFail() }
        catch LLMError.noAPIKey { }
        catch { XCTFail("\(error)") }
    }

    func test_geminiProvider_noAPIKey_throwsNoAPIKey() async {
        let p = GeminiProvider(keychain: MockKeychainService())
        do { _ = try await p.requestOpinion(thread: emptyThread()); XCTFail() }
        catch LLMError.noAPIKey { }
        catch { XCTFail("\(error)") }
    }

    func test_factory_createsCorrectType() {
        XCTAssertEqual(LLMProviderFactory.provider(for: .claude, keychain: MockKeychainService()).type, .claude)
        XCTAssertEqual(LLMProviderFactory.provider(for: .openai, keychain: MockKeychainService()).type, .openai)
        XCTAssertEqual(LLMProviderFactory.provider(for: .gemini, keychain: MockKeychainService()).type, .gemini)
        XCTAssertEqual(LLMProviderFactory.provider(for: .mistral, keychain: MockKeychainService()).type, .mistral)
    }
}
