import XCTest
@testable import GMac

final class VoiceProfileAnalyzerTests: XCTestCase {
    var mockProvider: MockLLMProvider!
    var analyzer: VoiceProfileAnalyzer!

    override func setUp() {
        mockProvider = MockLLMProvider()
        analyzer = VoiceProfileAnalyzer(provider: mockProvider)
    }

    func test_analyze_emptyMessages_returnsDefaults() async throws {
        let result = try await analyzer.analyze(sentMessages: [])
        XCTAssertEqual(result.formalityLevel, "semi-formel")
        XCTAssertTrue(result.greetingPatterns.isEmpty)
    }

    func test_analyze_validJSONResponse_parsesCorrectly() async throws {
        mockProvider.stubbedCompletion = """
        {
          "formalityLevel": "formel",
          "sentenceStructure": "courtes",
          "greetingPatterns": ["Bonjour,", "Madame, Monsieur,"],
          "closingPatterns": ["Cordialement,"],
          "vocabulary": "soutenu",
          "paragraphStyle": "court",
          "specificExpressions": ["en effet"],
          "thingsToAvoid": ["familiarités"]
        }
        """
        let msg = makeMessage(body: "Bonjour, Suite à notre échange...")
        let result = try await analyzer.analyze(sentMessages: [msg])
        XCTAssertEqual(result.formalityLevel, "formel")
        XCTAssertEqual(result.greetingPatterns, ["Bonjour,", "Madame, Monsieur,"])
        XCTAssertEqual(result.closingPatterns, ["Cordialement,"])
    }

    func test_analyze_jsonWithMarkdownFences_parsesCorrectly() async throws {
        mockProvider.stubbedCompletion = """
        ```json
        {"formalityLevel":"informel","sentenceStructure":"courtes","greetingPatterns":["Salut"],"closingPatterns":["Bye"],"vocabulary":"courant","paragraphStyle":"court","specificExpressions":[],"thingsToAvoid":[]}
        ```
        """
        let msg = makeMessage(body: "Salut, comment ça va ?")
        let result = try await analyzer.analyze(sentMessages: [msg])
        XCTAssertEqual(result.formalityLevel, "informel")
        XCTAssertEqual(result.greetingPatterns, ["Salut"])
    }

    func test_analyze_noAPIKey_throws() async {
        mockProvider.shouldThrowNoAPIKey = true
        let msg = makeMessage(body: "Test")
        do {
            _ = try await analyzer.analyze(sentMessages: [msg])
            XCTFail("Should throw")
        } catch LLMError.noAPIKey { }
        catch { XCTFail("Wrong error: \(error)") }
    }

    private func makeMessage(body: String) -> EmailMessage {
        EmailMessage(id: UUID().uuidString, threadId: "t", snippet: body,
                     subject: "Test", from: "me@example.com", to: ["you@example.com"],
                     date: Date(), bodyHTML: nil, bodyPlain: body,
                     labelIds: ["SENT"], isUnread: false, attachmentRefs: [])
    }
}
