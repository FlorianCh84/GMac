# GMac Sprint 5 — Assistant IA

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Intégrer un assistant IA multi-LLM dans le composeur de GMac qui génère des réponses dans le ton de l'utilisateur, avec affinage conversationnel et injection directe ⌘+Return.

**Architecture:** `LLMProvider` (protocole Sendable) implémenté par 4 providers (Claude, OpenAI, Gemini, Mistral). `ToneContextResolver` détermine la source de ton en 5 niveaux de priorité (thread courant > expéditeur connu > domaine > sujet similaire > profil global). `PromptBuilder` construit les prompts avec few-shot (vrais emails). `VoiceProfile` persisté en SwiftData. Tout sans streaming pour Sprint 5 — ajout streaming Sprint 6.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, URLSession (Anthropic API, OpenAI API, Gemini API, Mistral API), Keychain

---

## Contexte — APIs LLM

| Provider | Endpoint | Auth |
|---|---|---|
| Claude | `https://api.anthropic.com/v1/messages` | `x-api-key: {key}`, `anthropic-version: 2023-06-01` |
| OpenAI | `https://api.openai.com/v1/chat/completions` | `Authorization: Bearer {key}` |
| Gemini | `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}` | Query param |
| Mistral | `https://api.mistral.ai/v1/chat/completions` | `Authorization: Bearer {key}` (format OpenAI) |

---

## Task 1 : Modèles IA + LLMProvider protocole

**Files:**
- Create: `GMac/AI/LLMProvider.swift`
- Create: `GMac/AI/LLMConversation.swift`
- Create: `GMac/AI/UserInstruction.swift`
- Create: `GMac/Models/VoiceProfile.swift`
- Create: `GMacTests/Unit/LLMConversationTests.swift`

### `GMac/AI/UserInstruction.swift`

```swift
import Foundation

enum ReplyObjective: String, CaseIterable, Sendable, Identifiable {
    var id: String { rawValue }
    case conclude = "Conclure"
    case negotiate = "Négocier"
    case inform = "Informer"
    case refusePolitely = "Refuser poliment"
    case followUp = "Relancer"
    case clarify = "Clarifier"
    case thank = "Remercier"
}

enum ReplyTone: String, CaseIterable, Sendable, Identifiable {
    var id: String { rawValue }
    case formal = "Formel"
    case warm = "Chaleureux"
    case direct = "Direct"
    case firm = "Ferme"
    case diplomatic = "Diplomate"
    case conciliatory = "Conciliant"
}

enum ReplyLength: String, CaseIterable, Sendable, Identifiable {
    var id: String { rawValue }
    case concise = "Concis"
    case balanced = "Équilibré"
    case detailed = "Détaillé"
}

struct UserInstruction: Sendable {
    let freeText: String
    let objective: ReplyObjective?
    let tone: ReplyTone?
    let length: ReplyLength
    let senderEmail: String
    let toneExamples: [EmailMessage]

    init(
        freeText: String,
        objective: ReplyObjective? = nil,
        tone: ReplyTone? = nil,
        length: ReplyLength = .balanced,
        senderEmail: String = "",
        toneExamples: [EmailMessage] = []
    ) {
        self.freeText = freeText
        self.objective = objective
        self.tone = tone
        self.length = length
        self.senderEmail = senderEmail
        self.toneExamples = toneExamples
    }
}
```

### `GMac/AI/LLMConversation.swift`

```swift
import Foundation

struct LLMConversation: Sendable {
    enum Role: String, Sendable { case system, user, assistant }

    struct Message: Sendable {
        let role: Role
        let content: String
    }

    var messages: [Message] = []

    mutating func append(role: Role, content: String) {
        messages.append(Message(role: role, content: content))
    }

    var lastAssistantMessage: String? {
        messages.last(where: { $0.role == .assistant })?.content
    }
}
```

### `GMac/AI/LLMProvider.swift`

```swift
import Foundation

enum LLMProviderType: String, CaseIterable, Sendable, Identifiable {
    var id: String { rawValue }
    case claude = "Claude"
    case openai = "ChatGPT"
    case gemini = "Gemini"
    case mistral = "Mistral"

    var defaultModel: String {
        switch self {
        case .claude: return "claude-sonnet-4-6"
        case .openai: return "gpt-4o"
        case .gemini: return "gemini-1.5-pro"
        case .mistral: return "mistral-large-latest"
        }
    }
}

enum LLMError: Error, Sendable {
    case noAPIKey
    case requestFailed(String)
    case decodingFailed(String)
    case emptyResponse
}

protocol LLMProvider: Sendable {
    var type: LLMProviderType { get }

    func generateReply(
        thread: EmailThread,
        instruction: UserInstruction
    ) async throws -> String

    func requestOpinion(thread: EmailThread) async throws -> String

    func refine(
        conversation: LLMConversation,
        instruction: String
    ) async throws -> String
}
```

### `GMac/Models/VoiceProfile.swift`

```swift
import Foundation
import SwiftData

@Model
final class VoiceProfile {
    var formalityLevel: String = ""
    var sentenceStructure: String = ""
    var greetingPatterns: [String] = []
    var closingPatterns: [String] = []
    var specificExpressions: [String] = []
    var thingsToAvoid: [String] = []
    var userDescription: String = ""
    var rawEmailSamples: [String] = []  // vrais emails envoyés pour few-shot
    var lastUpdated: Date = Date()

    init() {}
}
```

### Tests `LLMConversationTests.swift`

```swift
// GMacTests/Unit/LLMConversationTests.swift
import XCTest
@testable import GMac

final class LLMConversationTests: XCTestCase {

    func test_append_addsMessage() {
        var conversation = LLMConversation()
        conversation.append(role: .user, content: "Hello")
        XCTAssertEqual(conversation.messages.count, 1)
        XCTAssertEqual(conversation.messages[0].content, "Hello")
        XCTAssertEqual(conversation.messages[0].role, .user)
    }

    func test_lastAssistantMessage_returnsLastAssistant() {
        var conversation = LLMConversation()
        conversation.append(role: .system, content: "System")
        conversation.append(role: .user, content: "User msg")
        conversation.append(role: .assistant, content: "First response")
        conversation.append(role: .user, content: "Refine this")
        conversation.append(role: .assistant, content: "Second response")
        XCTAssertEqual(conversation.lastAssistantMessage, "Second response")
    }

    func test_lastAssistantMessage_nilWhenNoAssistant() {
        var conversation = LLMConversation()
        conversation.append(role: .user, content: "Question")
        XCTAssertNil(conversation.lastAssistantMessage)
    }

    func test_userInstruction_defaults() {
        let instruction = UserInstruction(freeText: "Say hello")
        XCTAssertNil(instruction.objective)
        XCTAssertNil(instruction.tone)
        XCTAssertEqual(instruction.length, .balanced)
        XCTAssertTrue(instruction.toneExamples.isEmpty)
    }

    func test_llmProviderType_defaultModels() {
        XCTAssertEqual(LLMProviderType.claude.defaultModel, "claude-sonnet-4-6")
        XCTAssertEqual(LLMProviderType.openai.defaultModel, "gpt-4o")
        XCTAssertEqual(LLMProviderType.gemini.defaultModel, "gemini-1.5-pro")
        XCTAssertEqual(LLMProviderType.mistral.defaultModel, "mistral-large-latest")
    }

    func test_replyObjective_allCasesHaveRawValues() {
        for objective in ReplyObjective.allCases {
            XCTAssertFalse(objective.rawValue.isEmpty)
        }
        XCTAssertEqual(ReplyObjective.allCases.count, 7)
    }
}
```

### Commit Task 1

```bash
xcodegen generate
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | head -3
git add GMac/AI/ GMac/Models/VoiceProfile.swift GMacTests/Unit/LLMConversationTests.swift
git commit -m "feat: LLMProvider protocole, LLMConversation, UserInstruction, VoiceProfile SwiftData, enums IA"
```

---

## Task 2 : PromptBuilder + ToneContextResolver

**Files:**
- Create: `GMac/AI/PromptBuilder.swift`
- Create: `GMac/AI/ToneContextResolver.swift`
- Create: `GMacTests/Unit/PromptBuilderTests.swift`
- Create: `GMacTests/Unit/ToneContextResolverTests.swift`

### `GMac/AI/ToneContextResolver.swift`

```swift
import Foundation

enum ToneSource: Sendable {
    case currentThread([EmailMessage])
    case knownSender(email: String, [EmailMessage])
    case sameDomain(domain: String, [EmailMessage])
    case similarSubject([EmailMessage])
    case globalProfile

    var label: String {
        switch self {
        case .currentThread: return "Ton de cet échange"
        case .knownSender(let email, _): return "Ton avec \(email)"
        case .sameDomain(let domain, _): return "Ton avec \(domain)"
        case .similarSubject: return "Ton de tes échanges similaires"
        case .globalProfile: return "Ton général"
        }
    }

    var examples: [EmailMessage] {
        switch self {
        case .currentThread(let msgs): return msgs
        case .knownSender(_, let msgs): return msgs
        case .sameDomain(_, let msgs): return msgs
        case .similarSubject(let msgs): return msgs
        case .globalProfile: return []
        }
    }
}

enum ToneContextResolver {
    static func resolve(
        thread: EmailThread,
        sentMessages: [EmailMessage]
    ) -> ToneSource {
        let senderEmail = thread.messages.first?.from ?? ""
        let senderDomain = senderEmail.components(separatedBy: "@").last ?? ""

        // Priority 1 : messages envoyés dans ce thread
        let threadReplies = thread.messages.filter { !$0.labelIds.contains("INBOX") }
        if !threadReplies.isEmpty {
            return .currentThread(threadReplies)
        }

        // Priority 2 : emails envoyés à cet expéditeur
        let toSender = sentMessages.filter { $0.to.contains(senderEmail) }
        if !toSender.isEmpty {
            return .knownSender(email: senderEmail, toSender)
        }

        // Priority 3 : emails au même domaine
        let toDomain = sentMessages.filter {
            $0.to.contains(where: { $0.hasSuffix("@\(senderDomain)") })
        }
        if !toDomain.isEmpty && !senderDomain.isEmpty {
            return .sameDomain(domain: senderDomain, toDomain)
        }

        // Priority 4 : emails avec sujet similaire (mots communs)
        let subjectWords = Set(
            thread.subject
                .lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { $0.count > 3 }
        )
        let similar = sentMessages.filter { msg in
            let msgWords = Set(msg.subject.lowercased().components(separatedBy: .whitespacesAndNewlines))
            return !subjectWords.intersection(msgWords).isEmpty
        }
        if !similar.isEmpty {
            return .similarSubject(Array(similar.prefix(5)))
        }

        // Priority 5 : profil global
        return .globalProfile
    }
}
```

### `GMac/AI/PromptBuilder.swift`

```swift
import Foundation

enum PromptBuilder {

    static func buildReplyPrompt(
        thread: EmailThread,
        instruction: UserInstruction,
        toneSource: ToneSource
    ) -> LLMConversation {
        var conversation = LLMConversation()

        // System prompt
        var system = "Tu es un assistant qui rédige des réponses d'email au nom de l'utilisateur."
        system += " Écris uniquement le corps du message, sans salutation ni signature."
        system += " Longueur : \(instruction.length.rawValue)."
        if let objective = instruction.objective {
            system += " Objectif : \(objective.rawValue)."
        }
        if let tone = instruction.tone {
            system += " Ton : \(tone.rawValue)."
        }
        conversation.append(role: .system, content: system)

        // Few-shot : exemples de vrais emails de l'utilisateur
        let examples = toneSource.examples.prefix(3)
        if !examples.isEmpty {
            let examplesText = examples.map { "---\n\($0.bodyPlain ?? $0.snippet)" }.joined(separator: "\n")
            conversation.append(role: .user, content: "Voici des exemples de ma façon d'écrire :\n\(examplesText)\n\nÉcris dans ce même style.")
            conversation.append(role: .assistant, content: "Compris, je vais écrire dans ce style.")
        }

        // Thread context
        let threadContext = buildThreadContext(thread)
        let userPrompt = """
        Échange email :
        \(threadContext)

        Instruction : \(instruction.freeText.isEmpty ? "Réponds de façon appropriée" : instruction.freeText)
        """
        conversation.append(role: .user, content: userPrompt)

        return conversation
    }

    static func buildOpinionPrompt(thread: EmailThread) -> LLMConversation {
        var conversation = LLMConversation()
        let system = """
        Tu analyses des échanges email de façon objective et stratégique.
        Identifie : le ton et l'intention de l'interlocuteur, les points de tension ou ambiguïtés,
        les enjeux sous-jacents, ce que l'interlocuteur attend réellement,
        et des recommandations stratégiques pour la suite.
        Sois direct et concis.
        """
        conversation.append(role: .system, content: system)
        conversation.append(role: .user, content: "Analyse cet échange :\n\n\(buildThreadContext(thread))")
        return conversation
    }

    static func buildRefinementPrompt(
        existing: LLMConversation,
        instruction: String
    ) -> LLMConversation {
        var conversation = existing
        conversation.append(role: .user, content: instruction)
        return conversation
    }

    private static func buildThreadContext(_ thread: EmailThread) -> String {
        thread.messages.suffix(5).map { msg in
            "De : \(msg.from)\n\(msg.bodyPlain ?? msg.snippet)"
        }.joined(separator: "\n---\n")
    }
}
```

### Tests PromptBuilder

```swift
// GMacTests/Unit/PromptBuilderTests.swift
import XCTest
@testable import GMac

final class PromptBuilderTests: XCTestCase {

    private func makeThread(subject: String, fromEmail: String = "bob@example.com") -> EmailThread {
        let msg = EmailMessage(
            id: "m1", threadId: "t1", snippet: "Hello",
            subject: subject, from: fromEmail, to: ["alice@example.com"],
            date: Date(), bodyHTML: nil, bodyPlain: "Hello, please respond.",
            labelIds: ["INBOX"], isUnread: true, attachmentRefs: []
        )
        return EmailThread(id: "t1", snippet: "Hello", historyId: "100", messages: [msg])
    }

    func test_buildReplyPrompt_containsSystemMessage() {
        let thread = makeThread(subject: "Test")
        let instruction = UserInstruction(freeText: "Reply politely")
        let conversation = PromptBuilder.buildReplyPrompt(thread: thread, instruction: instruction, toneSource: .globalProfile)
        XCTAssertTrue(conversation.messages.first?.role == .system)
        XCTAssertTrue(conversation.messages.first?.content.contains("réponses d'email") ?? false)
    }

    func test_buildReplyPrompt_withObjective_mentionsObjective() {
        let thread = makeThread(subject: "Test")
        let instruction = UserInstruction(freeText: "", objective: .negotiate)
        let conversation = PromptBuilder.buildReplyPrompt(thread: thread, instruction: instruction, toneSource: .globalProfile)
        let systemContent = conversation.messages.first?.content ?? ""
        XCTAssertTrue(systemContent.contains("Négocier"))
    }

    func test_buildReplyPrompt_withToneExamples_addsFewShot() {
        let thread = makeThread(subject: "Test")
        let example = EmailMessage(
            id: "ex1", threadId: "t0", snippet: "Example",
            subject: "Old email", from: "alice@example.com", to: ["bob@example.com"],
            date: Date(), bodyHTML: nil, bodyPlain: "Bonjour, suite à notre entretien…",
            labelIds: ["SENT"], isUnread: false, attachmentRefs: []
        )
        let instruction = UserInstruction(freeText: "Reply", toneExamples: [example])
        let conversation = PromptBuilder.buildReplyPrompt(thread: thread, instruction: instruction, toneSource: .knownSender(email: "bob@example.com", [example]))
        // Doit contenir un message avec les exemples
        let hasExamples = conversation.messages.contains { $0.content.contains("façon d'écrire") }
        XCTAssertTrue(hasExamples)
    }

    func test_buildOpinionPrompt_containsAnalysisKeywords() {
        let thread = makeThread(subject: "Test")
        let conversation = PromptBuilder.buildOpinionPrompt(thread: thread)
        let systemContent = conversation.messages.first?.content ?? ""
        XCTAssertTrue(systemContent.contains("enjeux"))
        XCTAssertTrue(systemContent.contains("stratégiques"))
    }

    func test_buildRefinementPrompt_appendsInstruction() {
        var existing = LLMConversation()
        existing.append(role: .system, content: "System")
        existing.append(role: .user, content: "Original")
        existing.append(role: .assistant, content: "Response")
        let refined = PromptBuilder.buildRefinementPrompt(existing: existing, instruction: "Make it shorter")
        XCTAssertEqual(refined.messages.count, 4)
        XCTAssertEqual(refined.messages.last?.content, "Make it shorter")
    }
}
```

### Tests ToneContextResolver

```swift
// GMacTests/Unit/ToneContextResolverTests.swift
import XCTest
@testable import GMac

final class ToneContextResolverTests: XCTestCase {

    private func makeMessage(from: String, to: [String], subject: String, labelIds: [String] = ["INBOX"]) -> EmailMessage {
        EmailMessage(id: UUID().uuidString, threadId: "t1", snippet: "", subject: subject,
                     from: from, to: to, date: Date(), bodyHTML: nil, bodyPlain: nil,
                     labelIds: labelIds, isUnread: false, attachmentRefs: [])
    }

    private func makeThread(from: String, subject: String, hasReply: Bool = false) -> EmailThread {
        var messages = [makeMessage(from: from, to: ["me@example.com"], subject: subject)]
        if hasReply {
            messages.append(makeMessage(from: "me@example.com", to: [from], subject: "Re: \(subject)", labelIds: ["SENT"]))
        }
        return EmailThread(id: "t1", snippet: "", historyId: "1", messages: messages)
    }

    func test_resolve_priority1_currentThread() {
        let thread = makeThread(from: "bob@acme.com", subject: "Project", hasReply: true)
        let source = ToneContextResolver.resolve(thread: thread, sentMessages: [])
        if case .currentThread = source { } else {
            XCTFail("Expected .currentThread, got \(source.label)")
        }
    }

    func test_resolve_priority2_knownSender() {
        let thread = makeThread(from: "bob@acme.com", subject: "New topic")
        let sent = makeMessage(from: "me@example.com", to: ["bob@acme.com"], subject: "Old topic", labelIds: ["SENT"])
        let source = ToneContextResolver.resolve(thread: thread, sentMessages: [sent])
        if case .knownSender(let email, _) = source {
            XCTAssertEqual(email, "bob@acme.com")
        } else {
            XCTFail("Expected .knownSender, got \(source.label)")
        }
    }

    func test_resolve_priority3_sameDomain() {
        let thread = makeThread(from: "carol@acme.com", subject: "New topic")
        let sent = makeMessage(from: "me@example.com", to: ["dave@acme.com"], subject: "Old topic", labelIds: ["SENT"])
        let source = ToneContextResolver.resolve(thread: thread, sentMessages: [sent])
        if case .sameDomain(let domain, _) = source {
            XCTAssertEqual(domain, "acme.com")
        } else {
            XCTFail("Expected .sameDomain, got \(source.label)")
        }
    }

    func test_resolve_priority5_globalProfile_whenNoMatch() {
        let thread = makeThread(from: "unknown@random.xyz", subject: "Xyzzy unique")
        let source = ToneContextResolver.resolve(thread: thread, sentMessages: [])
        if case .globalProfile = source { } else {
            XCTFail("Expected .globalProfile, got \(source.label)")
        }
    }

    func test_toneSource_labels() {
        XCTAssertEqual(ToneSource.globalProfile.label, "Ton général")
        XCTAssertEqual(ToneSource.currentThread([]).label, "Ton de cet échange")
    }
}
```

### Commit Task 2

```bash
xcodegen generate
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | head -3
git add GMac/AI/ GMacTests/Unit/PromptBuilderTests.swift GMacTests/Unit/ToneContextResolverTests.swift
git commit -m "feat: PromptBuilder (few-shot), ToneContextResolver (5 niveaux priorité)"
```

---

## Task 3 : LLM Providers — Claude + OpenAI + Gemini + Mistral

**Files:**
- Create: `GMac/AI/Providers/ClaudeProvider.swift`
- Create: `GMac/AI/Providers/OpenAIProvider.swift`
- Create: `GMac/AI/Providers/GeminiProvider.swift`
- Create: `GMac/AI/Providers/MistralProvider.swift`
- Create: `GMac/AI/LLMProviderFactory.swift`
- Create: `GMacTests/Unit/LLMProviderTests.swift`

### Pattern commun aux providers

Tous les providers :
1. Récupèrent leur API key depuis `KeychainService`
2. Construisent la requête HTTP avec `URLSession.shared` (pas `AuthenticatedHTTPClient` — les LLMs ont leurs propres auth)
3. Retournent `throw LLMError.noAPIKey` si key absente
4. Convertissent `LLMConversation` → format API specifique

### `GMac/AI/Providers/ClaudeProvider.swift`

```swift
import Foundation

final class ClaudeProvider: LLMProvider, Sendable {
    let type: LLMProviderType = .claude
    private let keychain: KeychainService
    private let model: String

    init(keychain: KeychainService = KeychainService(), model: String = LLMProviderType.claude.defaultModel) {
        self.keychain = keychain
        self.model = model
    }

    func generateReply(thread: EmailThread, instruction: UserInstruction) async throws -> String {
        let toneSource = ToneContextResolver.resolve(thread: thread, sentMessages: instruction.toneExamples)
        let conversation = PromptBuilder.buildReplyPrompt(thread: thread, instruction: instruction, toneSource: toneSource)
        return try await complete(conversation: conversation)
    }

    func requestOpinion(thread: EmailThread) async throws -> String {
        let conversation = PromptBuilder.buildOpinionPrompt(thread: thread)
        return try await complete(conversation: conversation)
    }

    func refine(conversation: LLMConversation, instruction: String) async throws -> String {
        let updated = PromptBuilder.buildRefinementPrompt(existing: conversation, instruction: instruction)
        return try await complete(conversation: updated)
    }

    private func complete(conversation: LLMConversation) async throws -> String {
        guard let apiKey = try? keychain.retrieve(key: "claude_api_key"), !apiKey.isEmpty else {
            throw LLMError.noAPIKey
        }

        struct Message: Encodable { let role: String; let content: String }
        struct Request: Encodable {
            let model: String
            let maxTokens: Int
            let system: String
            let messages: [Message]
            enum CodingKeys: String, CodingKey {
                case model, system, messages
                case maxTokens = "max_tokens"
            }
        }
        struct Response: Decodable {
            struct Content: Decodable { let text: String }
            let content: [Content]
        }

        let systemContent = conversation.messages.first(where: { $0.role == .system })?.content ?? ""
        let chatMessages = conversation.messages
            .filter { $0.role != .system }
            .map { Message(role: $0.role.rawValue, content: $0.content) }

        let body = Request(model: model, maxTokens: 1024, system: systemContent, messages: chatMessages)
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let text = response.content.first?.text else { throw LLMError.emptyResponse }
        return text
    }
}
```

### `GMac/AI/Providers/OpenAIProvider.swift`

```swift
import Foundation

final class OpenAIProvider: LLMProvider, Sendable {
    let type: LLMProviderType = .openai
    private let keychain: KeychainService
    private let model: String

    init(keychain: KeychainService = KeychainService(), model: String = LLMProviderType.openai.defaultModel) {
        self.keychain = keychain
        self.model = model
    }

    func generateReply(thread: EmailThread, instruction: UserInstruction) async throws -> String {
        let toneSource = ToneContextResolver.resolve(thread: thread, sentMessages: instruction.toneExamples)
        let conversation = PromptBuilder.buildReplyPrompt(thread: thread, instruction: instruction, toneSource: toneSource)
        return try await complete(conversation: conversation)
    }

    func requestOpinion(thread: EmailThread) async throws -> String {
        let conversation = PromptBuilder.buildOpinionPrompt(thread: thread)
        return try await complete(conversation: conversation)
    }

    func refine(conversation: LLMConversation, instruction: String) async throws -> String {
        let updated = PromptBuilder.buildRefinementPrompt(existing: conversation, instruction: instruction)
        return try await complete(conversation: updated)
    }

    private func complete(conversation: LLMConversation) async throws -> String {
        guard let apiKey = try? keychain.retrieve(key: "openai_api_key"), !apiKey.isEmpty else {
            throw LLMError.noAPIKey
        }

        struct Message: Encodable { let role: String; let content: String }
        struct Request: Encodable { let model: String; let messages: [Message] }
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Msg: Decodable { let content: String? }
                let message: Msg
            }
            let choices: [Choice]
        }

        let messages = conversation.messages.map { Message(role: $0.role.rawValue, content: $0.content) }
        let body = Request(model: model, messages: messages)
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let text = response.choices.first?.message.content else { throw LLMError.emptyResponse }
        return text
    }
}
```

### `GMac/AI/Providers/MistralProvider.swift`

```swift
import Foundation

// Mistral utilise le format OpenAI — délègue la logique commune
final class MistralProvider: LLMProvider, Sendable {
    let type: LLMProviderType = .mistral
    private let keychain: KeychainService
    private let model: String

    init(keychain: KeychainService = KeychainService(), model: String = LLMProviderType.mistral.defaultModel) {
        self.keychain = keychain
        self.model = model
    }

    func generateReply(thread: EmailThread, instruction: UserInstruction) async throws -> String {
        let toneSource = ToneContextResolver.resolve(thread: thread, sentMessages: instruction.toneExamples)
        let conversation = PromptBuilder.buildReplyPrompt(thread: thread, instruction: instruction, toneSource: toneSource)
        return try await complete(conversation: conversation)
    }

    func requestOpinion(thread: EmailThread) async throws -> String {
        return try await complete(conversation: PromptBuilder.buildOpinionPrompt(thread: thread))
    }

    func refine(conversation: LLMConversation, instruction: String) async throws -> String {
        return try await complete(conversation: PromptBuilder.buildRefinementPrompt(existing: conversation, instruction: instruction))
    }

    private func complete(conversation: LLMConversation) async throws -> String {
        guard let apiKey = try? keychain.retrieve(key: "mistral_api_key"), !apiKey.isEmpty else {
            throw LLMError.noAPIKey
        }
        struct Message: Encodable { let role: String; let content: String }
        struct Request: Encodable { let model: String; let messages: [Message] }
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Msg: Decodable { let content: String? }
                let message: Msg
            }
            let choices: [Choice]
        }
        let messages = conversation.messages.map { Message(role: $0.role.rawValue, content: $0.content) }
        let body = Request(model: model, messages: messages)
        var request = URLRequest(url: URL(string: "https://api.mistral.ai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let text = response.choices.first?.message.content else { throw LLMError.emptyResponse }
        return text
    }
}
```

### `GMac/AI/Providers/GeminiProvider.swift`

```swift
import Foundation

final class GeminiProvider: LLMProvider, Sendable {
    let type: LLMProviderType = .gemini
    private let keychain: KeychainService
    private let model: String

    init(keychain: KeychainService = KeychainService(), model: String = LLMProviderType.gemini.defaultModel) {
        self.keychain = keychain
        self.model = model
    }

    func generateReply(thread: EmailThread, instruction: UserInstruction) async throws -> String {
        let toneSource = ToneContextResolver.resolve(thread: thread, sentMessages: instruction.toneExamples)
        let conversation = PromptBuilder.buildReplyPrompt(thread: thread, instruction: instruction, toneSource: toneSource)
        return try await complete(conversation: conversation)
    }

    func requestOpinion(thread: EmailThread) async throws -> String {
        return try await complete(conversation: PromptBuilder.buildOpinionPrompt(thread: thread))
    }

    func refine(conversation: LLMConversation, instruction: String) async throws -> String {
        return try await complete(conversation: PromptBuilder.buildRefinementPrompt(existing: conversation, instruction: instruction))
    }

    private func complete(conversation: LLMConversation) async throws -> String {
        guard let apiKey = try? keychain.retrieve(key: "gemini_api_key"), !apiKey.isEmpty else {
            throw LLMError.noAPIKey
        }

        struct Part: Encodable { let text: String }
        struct Content: Encodable { let role: String; let parts: [Part] }
        struct Request: Encodable { let contents: [Content] }
        struct Response: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String? }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]
        }

        // Gemini ne supporte pas 'system' comme role — injecter le system dans le premier user message
        var contents: [Content] = []
        var systemInjected = false
        let systemText = conversation.messages.first(where: { $0.role == .system })?.content ?? ""
        for msg in conversation.messages where msg.role != .system {
            let prefix = (!systemInjected && !systemText.isEmpty) ? "\(systemText)\n\n" : ""
            contents.append(Content(role: msg.role == .user ? "user" : "model", parts: [Part(text: prefix + msg.content)]))
            systemInjected = true
        }

        let body = Request(contents: contents)
        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        var request = URLRequest(url: URL(string: urlStr)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let text = response.candidates.first?.content.parts.first?.text else { throw LLMError.emptyResponse }
        return text
    }
}
```

### `GMac/AI/LLMProviderFactory.swift`

```swift
import Foundation

enum LLMProviderFactory {
    static func provider(for type: LLMProviderType, keychain: KeychainService = KeychainService()) -> any LLMProvider {
        switch type {
        case .claude: return ClaudeProvider(keychain: keychain)
        case .openai: return OpenAIProvider(keychain: keychain)
        case .gemini: return GeminiProvider(keychain: keychain)
        case .mistral: return MistralProvider(keychain: keychain)
        }
    }
}
```

### Tests

```swift
// GMacTests/Unit/LLMProviderTests.swift
import XCTest
@testable import GMac

final class LLMProviderTests: XCTestCase {

    func test_claudeProvider_noAPIKey_throwsNoAPIKey() async {
        let keychain = MockKeychainService()
        let provider = ClaudeProvider(keychain: keychain)
        let thread = makeEmptyThread()
        do {
            _ = try await provider.requestOpinion(thread: thread)
            XCTFail("Should throw")
        } catch LLMError.noAPIKey {
            // Expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_openAIProvider_noAPIKey_throwsNoAPIKey() async {
        let keychain = MockKeychainService()
        let provider = OpenAIProvider(keychain: keychain)
        do {
            _ = try await provider.requestOpinion(thread: makeEmptyThread())
            XCTFail("Should throw")
        } catch LLMError.noAPIKey { }
        catch { XCTFail("Wrong error: \(error)") }
    }

    func test_mistralProvider_noAPIKey_throwsNoAPIKey() async {
        let keychain = MockKeychainService()
        let provider = MistralProvider(keychain: keychain)
        do {
            _ = try await provider.requestOpinion(thread: makeEmptyThread())
            XCTFail("Should throw")
        } catch LLMError.noAPIKey { }
        catch { XCTFail("Wrong error: \(error)") }
    }

    func test_geminiProvider_noAPIKey_throwsNoAPIKey() async {
        let keychain = MockKeychainService()
        let provider = GeminiProvider(keychain: keychain)
        do {
            _ = try await provider.requestOpinion(thread: makeEmptyThread())
            XCTFail("Should throw")
        } catch LLMError.noAPIKey { }
        catch { XCTFail("Wrong error: \(error)") }
    }

    func test_llmProviderFactory_createsCorrectType() {
        let keychain = MockKeychainService()
        XCTAssertEqual(LLMProviderFactory.provider(for: .claude, keychain: keychain).type, .claude)
        XCTAssertEqual(LLMProviderFactory.provider(for: .openai, keychain: keychain).type, .openai)
        XCTAssertEqual(LLMProviderFactory.provider(for: .gemini, keychain: keychain).type, .gemini)
        XCTAssertEqual(LLMProviderFactory.provider(for: .mistral, keychain: keychain).type, .mistral)
    }

    private func makeEmptyThread() -> EmailThread {
        EmailThread(id: "t1", snippet: "", historyId: "1", messages: [])
    }
}
```

### Commit Task 3

```bash
xcodegen generate
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | head -3
git add GMac/AI/Providers/ GMac/AI/LLMProviderFactory.swift GMacTests/Unit/LLMProviderTests.swift
git commit -m "feat: ClaudeProvider, OpenAIProvider, GeminiProvider, MistralProvider, LLMProviderFactory"
```

---

## Task 4 : AISettings — gestion des clés API + provider sélectionné

**Files:**
- Create: `GMac/AI/AISettingsViewModel.swift`
- Create: `GMac/UI/Settings/AISettingsView.swift`
- Create: `GMacTests/Unit/AISettingsViewModelTests.swift`

### `GMac/AI/AISettingsViewModel.swift`

```swift
import Foundation
import Observation

@Observable
@MainActor
final class AISettingsViewModel {
    var selectedProvider: LLMProviderType = .claude
    var claudeKey: String = ""
    var openaiKey: String = ""
    var geminiKey: String = ""
    var mistralKey: String = ""
    var isSaving: Bool = false
    var saveSuccess: Bool = false

    private let keychain: KeychainService

    init(keychain: KeychainService = KeychainService()) {
        self.keychain = keychain
        loadKeys()
        loadSelectedProvider()
    }

    private func loadKeys() {
        claudeKey = (try? keychain.retrieve(key: "claude_api_key")) ?? ""
        openaiKey = (try? keychain.retrieve(key: "openai_api_key")) ?? ""
        geminiKey = (try? keychain.retrieve(key: "gemini_api_key")) ?? ""
        mistralKey = (try? keychain.retrieve(key: "mistral_api_key")) ?? ""
    }

    private func loadSelectedProvider() {
        if let raw = try? keychain.retrieve(key: "llm_selected_provider"),
           let type = LLMProviderType(rawValue: raw) {
            selectedProvider = type
        }
    }

    func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try keychain.save(claudeKey, key: "claude_api_key")
            try keychain.save(openaiKey, key: "openai_api_key")
            try keychain.save(geminiKey, key: "gemini_api_key")
            try keychain.save(mistralKey, key: "mistral_api_key")
            try keychain.save(selectedProvider.rawValue, key: "llm_selected_provider")
            saveSuccess = true
        } catch {
            // Keychain errors sont rares — ignorer silencieusement
        }
    }

    func activeProvider() -> any LLMProvider {
        LLMProviderFactory.provider(for: selectedProvider, keychain: keychain)
    }
}
```

### `GMac/UI/Settings/AISettingsView.swift`

```swift
import SwiftUI

struct AISettingsView: View {
    @State var vm: AISettingsViewModel

    var body: some View {
        Form {
            Section("Provider actif") {
                Picker("LLM", selection: $vm.selectedProvider) {
                    ForEach(LLMProviderType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Clés API") {
                SecureKeyField(label: "Claude (Anthropic)", key: $vm.claudeKey, hint: "sk-ant-...")
                SecureKeyField(label: "ChatGPT (OpenAI)", key: $vm.openaiKey, hint: "sk-...")
                SecureKeyField(label: "Gemini (Google)", key: $vm.geminiKey, hint: "AIza...")
                SecureKeyField(label: "Mistral", key: $vm.mistralKey, hint: "...")
            }

            Section {
                Text("Les clés sont stockées dans le Keychain macOS — jamais en clair, jamais envoyées à GMac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { Task { @MainActor in await vm.save() } }) {
                    if vm.isSaving { ProgressView().controlSize(.small) }
                    else { Text("Sauvegarder") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isSaving)
            }
        }
        .overlay(alignment: .top) {
            if vm.saveSuccess {
                Label("Clés sauvegardées", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold()).foregroundStyle(.white)
                    .padding(8).background(.green.opacity(0.9), in: .capsule)
                    .padding(.top, 8)
                    .task { try? await Task.sleep(for: .seconds(2)); vm.saveSuccess = false }
            }
        }
    }
}

private struct SecureKeyField: View {
    let label: String
    @Binding var key: String
    let hint: String

    var body: some View {
        HStack {
            Text(label).frame(width: 160, alignment: .leading)
            SecureField(hint, text: $key)
                .textFieldStyle(.plain)
        }
    }
}
```

### Tests

```swift
// GMacTests/Unit/AISettingsViewModelTests.swift
import XCTest
@testable import GMac

@MainActor
final class AISettingsViewModelTests: XCTestCase {
    var keychain: MockKeychainService!
    var vm: AISettingsViewModel!

    override func setUp() async throws {
        keychain = MockKeychainService()
        vm = AISettingsViewModel(keychain: keychain)
    }

    func test_initialState_defaultProviderIsClaude() {
        XCTAssertEqual(vm.selectedProvider, .claude)
    }

    func test_save_storesKeysInKeychain() async {
        vm.claudeKey = "sk-ant-test"
        vm.selectedProvider = .claude
        await vm.save()
        let stored = try? keychain.retrieve(key: "claude_api_key")
        XCTAssertEqual(stored, "sk-ant-test")
    }

    func test_save_storesSelectedProvider() async {
        vm.selectedProvider = .mistral
        await vm.save()
        let stored = try? keychain.retrieve(key: "llm_selected_provider")
        XCTAssertEqual(stored, LLMProviderType.mistral.rawValue)
    }

    func test_activeProvider_returnsCorrectType() {
        vm.selectedProvider = .openai
        let provider = vm.activeProvider()
        XCTAssertEqual(provider.type, .openai)
    }
}
```

### Ajouter AISettingsView dans SettingsView

Lire `SettingsView.swift`. Ajouter un lien "Assistant IA" :

```swift
NavigationLink("Assistant IA") {
    AISettingsView(vm: AISettingsViewModel())
        .navigationTitle("Assistant IA")
}
```

### Commit Task 4

```bash
xcodegen generate
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | head -3
git add GMac/AI/AISettingsViewModel.swift GMac/UI/Settings/AISettingsView.swift GMac/UI/Settings/SettingsView.swift GMacTests/Unit/AISettingsViewModelTests.swift
git commit -m "feat: AISettingsView — clés API par provider, Keychain, provider sélectionné"
```

---

## Task 5 : AIAssistantViewModel + AIAssistantPanel

**Files:**
- Create: `GMac/AI/AIAssistantViewModel.swift`
- Create: `GMac/UI/AIPanel/AIAssistantPanel.swift`
- Create: `GMacTests/Unit/AIAssistantViewModelTests.swift`

### `GMac/AI/AIAssistantViewModel.swift`

```swift
import Foundation
import Observation

enum AIAssistantState: Sendable {
    case idle
    case generating
    case done(String)          // réponse générée
    case opinionDone(String)   // analyse de l'échange
    case failed(String)
}

@Observable
@MainActor
final class AIAssistantViewModel {
    var state: AIAssistantState = .idle
    var freeText: String = ""
    var selectedObjective: ReplyObjective? = nil
    var selectedTone: ReplyTone? = nil
    var selectedLength: ReplyLength = .balanced
    var refinementText: String = ""
    var toneSource: ToneSource = .globalProfile

    private var conversation: LLMConversation = LLMConversation()
    private let provider: any LLMProvider

    init(provider: any LLMProvider) {
        self.provider = provider
    }

    func generate(thread: EmailThread, senderEmail: String, sentMessages: [EmailMessage]) async {
        state = .generating
        toneSource = ToneContextResolver.resolve(thread: thread, sentMessages: sentMessages)
        let instruction = UserInstruction(
            freeText: freeText,
            objective: selectedObjective,
            tone: selectedTone,
            length: selectedLength,
            senderEmail: senderEmail,
            toneExamples: toneSource.examples
        )
        do {
            conversation = PromptBuilder.buildReplyPrompt(thread: thread, instruction: instruction, toneSource: toneSource)
            let response = try await provider.generateReply(thread: thread, instruction: instruction)
            conversation.append(role: .assistant, content: response)
            state = .done(response)
        } catch LLMError.noAPIKey {
            state = .failed("Clé API manquante. Configurez-la dans Paramètres → Assistant IA.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func requestOpinion(thread: EmailThread) async {
        state = .generating
        do {
            let opinion = try await provider.requestOpinion(thread: thread)
            state = .opinionDone(opinion)
        } catch LLMError.noAPIKey {
            state = .failed("Clé API manquante.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func refine(thread: EmailThread) async {
        guard case .done = state, !refinementText.isEmpty else { return }
        state = .generating
        do {
            let refined = try await provider.refine(conversation: conversation, instruction: refinementText)
            conversation.append(role: .user, content: refinementText)
            conversation.append(role: .assistant, content: refined)
            refinementText = ""
            state = .done(refined)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func reset() {
        state = .idle
        freeText = ""
        selectedObjective = nil
        selectedTone = nil
        selectedLength = .balanced
        refinementText = ""
        conversation = LLMConversation()
    }

    var generatedText: String? {
        if case .done(let text) = state { return text }
        return nil
    }
}
```

### `GMac/UI/AIPanel/AIAssistantPanel.swift`

```swift
import SwiftUI

struct AIAssistantPanel: View {
    @State var vm: AIAssistantViewModel
    let thread: EmailThread
    let senderEmail: String
    let sentMessages: [EmailMessage]
    let onInject: (String) -> Void   // ⌘+Return → injecte dans le composeur

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    instructionSection
                    chipsSection
                    lengthSection
                    actionButtons
                    responseSection
                }
                .padding()
            }
        }
        .frame(minWidth: 300, maxWidth: 380)
    }

    // MARK: - Sections

    private var panelHeader: some View {
        HStack {
            Image(systemName: "sparkles").foregroundStyle(.blue)
            Text("Assistant IA").font(.headline)
            Spacer()
            Text(vm.toneSource.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }

    private var instructionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Intention").font(.caption.bold()).foregroundStyle(.secondary)
            TextEditor(text: $vm.freeText)
                .frame(minHeight: 60, maxHeight: 80)
                .font(.body)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        }
    }

    private var chipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChipGroup(title: "Objectif", items: ReplyObjective.allCases, selected: $vm.selectedObjective)
            ChipGroup(title: "Ton", items: ReplyTone.allCases, selected: $vm.selectedTone)
        }
    }

    private var lengthSection: some View {
        HStack(spacing: 6) {
            Text("Longueur").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: $vm.selectedLength) {
                ForEach(ReplyLength.allCases) { l in Text(l.rawValue).tag(l) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var actionButtons: some View {
        HStack {
            Button(action: { Task { @MainActor in await vm.generate(thread: thread, senderEmail: senderEmail, sentMessages: sentMessages) } }) {
                if case .generating = vm.state {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Générer", systemImage: "arrow.trianglehead.2.clockwise")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.state == .generating as? Bool ?? isGenerating)

            Button(action: { Task { @MainActor in await vm.requestOpinion(thread: thread) } }) {
                Label("Analyser", systemImage: "eye")
            }
            .buttonStyle(.bordered)
            .disabled(isGenerating)
        }
    }

    private var isGenerating: Bool {
        if case .generating = vm.state { return true }
        return false
    }

    @ViewBuilder
    private var responseSection: some View {
        switch vm.state {
        case .idle:
            EmptyView()

        case .generating:
            HStack { ProgressView(); Text("Génération…").font(.caption).foregroundStyle(.secondary) }

        case .done(let text):
            VStack(alignment: .leading, spacing: 8) {
                Text("Réponse générée").font(.caption.bold()).foregroundStyle(.secondary)
                Text(text).font(.body).textSelection(.enabled)
                    .padding(8).background(.quaternary, in: .rect(cornerRadius: 6))

                // Affinage
                HStack {
                    TextField("Affiner…", text: $vm.refinementText)
                        .textFieldStyle(.plain)
                        .onSubmit { Task { @MainActor in await vm.refine(thread: thread) } }
                    Button("OK") { Task { @MainActor in await vm.refine(thread: thread) } }
                        .disabled(vm.refinementText.isEmpty)
                }
                .padding(6).background(.quaternary, in: .capsule)

                // Injection ⌘+Return
                Button(action: { onInject(text) }) {
                    Label("Insérer dans le composeur", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.return, modifiers: .command)
            }

        case .opinionDone(let opinion):
            VStack(alignment: .leading, spacing: 8) {
                Text("Analyse de l'échange").font(.caption.bold()).foregroundStyle(.secondary)
                Text(opinion).font(.body).textSelection(.enabled)
                    .padding(8).background(.blue.opacity(0.08), in: .rect(cornerRadius: 6))
                Button("Réinitialiser") { vm.reset() }
                    .buttonStyle(.bordered).controlSize(.small)
            }

        case .failed(let message):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

// MARK: - ChipGroup

private struct ChipGroup<T: RawRepresentable & CaseIterable & Identifiable & Hashable>: View where T.RawValue == String {
    let title: String
    let items: [T]
    @Binding var selected: T?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            FlowLayout(spacing: 4) {
                ForEach(items) { item in
                    Button(item.rawValue) {
                        selected = selected == item ? nil : item
                    }
                    .buttonStyle(ChipButtonStyle(isSelected: selected == item))
                }
            }
        }
    }
}

private struct ChipButtonStyle: ButtonStyle {
    let isSelected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15), in: .capsule)
            .foregroundStyle(isSelected ? .white : .primary)
    }
}

// FlowLayout simple pour les chips
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0; var y: CGFloat = 0; var rowH: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing; rowH = max(rowH, size.height)
        }
        return CGSize(width: width, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX; var y = bounds.minY; var rowH: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; rowH = max(rowH, size.height)
        }
    }
}
```

Note : `AIAssistantState` n'est pas `Equatable` directement (les enums avec associated values nécessitent une implémentation custom). Utiliser le computed property `isGenerating` au lieu de `==`.

### Tests AIAssistantViewModel

```swift
// GMacTests/Unit/AIAssistantViewModelTests.swift
import XCTest
@testable import GMac

@MainActor
final class AIAssistantViewModelTests: XCTestCase {
    var mockProvider: MockLLMProvider!
    var vm: AIAssistantViewModel!

    override func setUp() async throws {
        mockProvider = MockLLMProvider()
        vm = AIAssistantViewModel(provider: mockProvider)
    }

    func test_initialState_isIdle() {
        if case .idle = vm.state { } else { XCTFail("Expected .idle") }
    }

    func test_generate_success_movesToDone() async {
        mockProvider.stubbedReply = "Hello from AI"
        let thread = makeThread()
        await vm.generate(thread: thread, senderEmail: "me@example.com", sentMessages: [])
        if case .done(let text) = vm.state {
            XCTAssertEqual(text, "Hello from AI")
        } else { XCTFail("Expected .done, got \(vm.state)") }
    }

    func test_generate_noAPIKey_movesToFailed() async {
        mockProvider.shouldThrowNoAPIKey = true
        await vm.generate(thread: makeThread(), senderEmail: "me@example.com", sentMessages: [])
        if case .failed(let msg) = vm.state {
            XCTAssertTrue(msg.contains("Clé API"))
        } else { XCTFail("Expected .failed") }
    }

    func test_requestOpinion_success_movesToOpinionDone() async {
        mockProvider.stubbedOpinion = "Strategic analysis"
        await vm.requestOpinion(thread: makeThread())
        if case .opinionDone(let text) = vm.state {
            XCTAssertEqual(text, "Strategic analysis")
        } else { XCTFail("Expected .opinionDone") }
    }

    func test_reset_returnsToIdle() async {
        mockProvider.stubbedReply = "Reply"
        await vm.generate(thread: makeThread(), senderEmail: "me@example.com", sentMessages: [])
        vm.reset()
        if case .idle = vm.state { } else { XCTFail("Expected .idle after reset") }
        XCTAssertTrue(vm.freeText.isEmpty)
    }

    func test_refine_appendsToConversation() async {
        mockProvider.stubbedReply = "Initial reply"
        mockProvider.stubbedRefinement = "Shorter reply"
        let thread = makeThread()
        await vm.generate(thread: thread, senderEmail: "me@example.com", sentMessages: [])
        vm.refinementText = "Make it shorter"
        await vm.refine(thread: thread)
        if case .done(let text) = vm.state {
            XCTAssertEqual(text, "Shorter reply")
        } else { XCTFail("Expected .done after refine") }
    }

    private func makeThread() -> EmailThread {
        let msg = EmailMessage(id: "m1", threadId: "t1", snippet: "Hi", subject: "Test",
                               from: "bob@example.com", to: ["me@example.com"],
                               date: Date(), bodyHTML: nil, bodyPlain: "Please reply",
                               labelIds: ["INBOX"], isUnread: true, attachmentRefs: [])
        return EmailThread(id: "t1", snippet: "Hi", historyId: "1", messages: [msg])
    }
}

// MockLLMProvider
final class MockLLMProvider: LLMProvider, @unchecked Sendable {
    let type: LLMProviderType = .claude
    var stubbedReply: String = ""
    var stubbedOpinion: String = ""
    var stubbedRefinement: String = ""
    var shouldThrowNoAPIKey: Bool = false

    func generateReply(thread: EmailThread, instruction: UserInstruction) async throws -> String {
        if shouldThrowNoAPIKey { throw LLMError.noAPIKey }
        return stubbedReply
    }
    func requestOpinion(thread: EmailThread) async throws -> String {
        if shouldThrowNoAPIKey { throw LLMError.noAPIKey }
        return stubbedOpinion
    }
    func refine(conversation: LLMConversation, instruction: String) async throws -> String {
        if shouldThrowNoAPIKey { throw LLMError.noAPIKey }
        return stubbedRefinement
    }
}
```

### Commit Task 5

```bash
xcodegen generate
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | head -3
git add GMac/AI/ GMac/UI/AIPanel/ GMacTests/Unit/AIAssistantViewModelTests.swift
git commit -m "feat: AIAssistantViewModel (generate/opinion/refine), AIAssistantPanel (chips, injection ⌘+Return)"
```

---

## Task 6 : Intégration dans MessageDetailView + ComposeView

**Files:**
- Modify: `GMac/UI/MessageView/MessageDetailView.swift`
- Modify: `GMac/UI/Compose/ComposeView.swift`
- Modify: `GMac/App/AppEnvironment.swift`

### AppEnvironment : exposer aiSettingsViewModel

Lire `AppEnvironment.swift`. Ajouter :
```swift
let aiSettings: AISettingsViewModel

// Dans init() :
self.aiSettings = AISettingsViewModel(keychain: keychain)
```

### MessageDetailView : bouton IA

Dans `ThreadDetailView` ou `MessageDetailView`, ajouter un bouton "✶ IA" qui ouvre l'AIAssistantPanel en split view côté composeur.

La logique : le panneau IA s'ouvre depuis le thread, et `onInject` injecte le texte dans un composeur existant ou en ouvre un nouveau.

```swift
// Dans MessageDetailView, ajouter :
@State private var isAIPanelOpen = false
@State private var aiGeneratedText: String = ""

// Bouton dans la toolbar du détail :
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button("✶ IA", systemImage: "sparkles") {
            isAIPanelOpen.toggle()
        }
    }
}
// Panel en overlay ou sheet :
.sheet(isPresented: $isAIPanelOpen) {
    if let thread = selectedThread {
        AIAssistantPanel(
            vm: AIAssistantViewModel(provider: appEnv.aiSettings.activeProvider()),
            thread: thread,
            senderEmail: store.senderEmail,
            sentMessages: [],  // TODO Sprint 5+: charger les emails envoyés depuis SessionStore
            onInject: { text in
                aiGeneratedText = text
                isAIPanelOpen = false
                // Déclencher l'ouverture du composeur avec le texte pré-rempli
                onReplyWithBody?(thread, thread.messages.last!, text)
            }
        )
    }
}
```

### Build + tests

```bash
xcodegen generate
xcodebuild build -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | tail -5
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | head -3
git add GMac/UI/ GMac/App/AppEnvironment.swift
git commit -m "feat: bouton IA dans MessageDetailView, injection ⌘+Return → composeur"
```

---

## Résumé Sprint 5

À la fin de ce sprint, GMac dispose d'un assistant IA complet :
- 4 providers LLM (Claude, OpenAI, Gemini, Mistral) avec clés API dans le Keychain
- ToneContextResolver qui détecte automatiquement le ton adapté (5 niveaux de priorité)
- PromptBuilder avec few-shot sur les vrais emails de l'utilisateur
- AIAssistantPanel avec chips Objectif/Ton/Longueur, génération, affinage conversationnel
- Injection directe ⌘+Return dans le composeur (zéro copier-coller)
- Feature "Analyser cet échange" (opinion stratégique du LLM)
- Clés API sécurisées dans le Keychain macOS

**Sprint 6 :** Streaming SSE (affichage en temps réel de la réponse IA), VoiceProfileAnalyzer (analyse automatique des 30 derniers emails envoyés), polish UI Liquid Glass.

---

*Plan Sprint 5 — GMac — 25 avril 2026*
