import XCTest
@testable import GMac

final class PromptBuilderTests: XCTestCase {

    private func makeThread(subject: String, from: String = "bob@example.com", hasReply: Bool = false) -> EmailThread {
        var messages = [EmailMessage(id: "m1", threadId: "t1", snippet: "Hi", subject: subject,
            from: from, to: ["me@example.com"], date: Date(), bodyHTML: nil,
            bodyPlain: "Hello, please respond.", labelIds: ["INBOX"], isUnread: true, attachmentRefs: [])]
        if hasReply {
            messages.append(EmailMessage(id: "m2", threadId: "t1", snippet: "Reply", subject: "Re: \(subject)",
                from: "me@example.com", to: [from], date: Date(), bodyHTML: nil,
                bodyPlain: "Thanks for reaching out.", labelIds: ["SENT"], isUnread: false, attachmentRefs: []))
        }
        return EmailThread(id: "t1", snippet: "Hi", historyId: "1", messages: messages)
    }

    func test_buildReplyPrompt_firstMessageIsSystem() {
        let thread = makeThread(subject: "Test")
        let c = PromptBuilder.buildReplyPrompt(thread: thread, instruction: UserInstruction(freeText: "Reply"), toneSource: .globalProfile)
        XCTAssertEqual(c.messages.first?.role, .system)
        XCTAssertTrue(c.messages.first?.content.contains("réponses d'email") ?? false)
    }

    func test_buildReplyPrompt_withObjective_mentionedInSystem() {
        let thread = makeThread(subject: "Test")
        let instruction = UserInstruction(freeText: "", objective: .negotiate)
        let c = PromptBuilder.buildReplyPrompt(thread: thread, instruction: instruction, toneSource: .globalProfile)
        XCTAssertTrue(c.messages.first?.content.contains("Négocier") ?? false)
    }

    func test_buildReplyPrompt_withToneExamples_addsFewShot() {
        let thread = makeThread(subject: "Test")
        let example = EmailMessage(id: "ex1", threadId: "t0", snippet: "Eg",
            subject: "Old", from: "me@example.com", to: ["bob@example.com"],
            date: Date(), bodyHTML: nil, bodyPlain: "Example body",
            labelIds: ["SENT"], isUnread: false, attachmentRefs: [])
        let toneSource = ToneSource.knownSender(email: "bob@example.com", [example])
        let c = PromptBuilder.buildReplyPrompt(thread: thread, instruction: UserInstruction(freeText: "Reply"), toneSource: toneSource)
        XCTAssertTrue(c.messages.contains { $0.content.contains("façon d'écrire") })
    }

    func test_buildOpinionPrompt_systemContainsStructure() {
        let thread = makeThread(subject: "Test")
        let c = PromptBuilder.buildOpinionPrompt(thread: thread)
        let content = c.messages.first?.content ?? ""
        XCTAssertTrue(content.contains("Recommandations"), "Le prompt doit contenir la section Recommandations")
        XCTAssertTrue(content.contains("Ton & intention"), "Le prompt doit contenir la section Ton & intention")
    }

    func test_buildRefinementPrompt_appendsInstruction() {
        var existing = LLMConversation()
        existing.append(role: .assistant, content: "Response")
        let refined = PromptBuilder.buildRefinementPrompt(existing: existing, instruction: "Make it shorter")
        XCTAssertEqual(refined.messages.last?.content, "Make it shorter")
        XCTAssertEqual(refined.messages.count, 2)
    }
}
