# GMac Sprint 6 — Polish & Open Source

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Finaliser GMac pour une publication GitHub open source : streaming IA en temps réel, VoiceProfileAnalyzer, Liquid Glass UI, performances et documentation.

**Architecture:** Streaming via `AsyncThrowingStream<String, Error>` + `URLSession.bytes(for:)` pour tous les providers LLM. `VoiceProfileAnalyzer` utilise le provider actif pour analyser les 30 derniers emails envoyés et persiste en SwiftData. UI polie avec Liquid Glass macOS 26. README + CONTRIBUTING pour les contributeurs open source.

**Tech Stack:** Swift 6, SwiftUI (Liquid Glass macOS 26), URLSession AsyncBytes, SwiftData, XCTest, GitHub MIT

---

## Task 1 : Infrastructure streaming SSE

**Files:**
- Create: `GMac/AI/SSEParser.swift`
- Create: `GMacTests/Unit/SSEParserTests.swift`
- Modify: `GMac/AI/LLMProvider.swift`

### Étape 1 : Ajouter `generateReplyStream` au protocole

Lire `GMac/AI/LLMProvider.swift`. Ajouter la méthode streaming :

```swift
// Dans le protocole LLMProvider, ajouter après refine() :
func generateReplyStream(
    thread: EmailThread,
    instruction: UserInstruction
) -> AsyncThrowingStream<String, Error>
```

### Étape 2 : Créer `GMac/AI/SSEParser.swift`

```swift
import Foundation

enum SSEParser {

    // Extrait le texte d'une ligne SSE Claude : data: {"delta":{"type":"text_delta","text":"..."}}
    static func parseClaudeDelta(_ line: String) -> String? {
        guard line.hasPrefix("data: ") else { return nil }
        let json = String(line.dropFirst(6))
        guard let data = json.data(using: .utf8),
              let obj = try? JSONDecoder().decode(ClaudeDelta.self, from: data),
              obj.type == "content_block_delta",
              obj.delta.type == "text_delta" else { return nil }
        return obj.delta.text
    }

    // Extrait le texte d'une ligne SSE OpenAI/Mistral : data: {"choices":[{"delta":{"content":"..."}}]}
    static func parseOpenAIDelta(_ line: String) -> String? {
        guard line.hasPrefix("data: ") else { return nil }
        let json = String(line.dropFirst(6))
        if json.trimmingCharacters(in: .whitespaces) == "[DONE]" { return nil }
        guard let data = json.data(using: .utf8),
              let obj = try? JSONDecoder().decode(OpenAIDelta.self, from: data) else { return nil }
        return obj.choices.first?.delta.content
    }

    // Structures de décodage
    struct ClaudeDelta: Decodable {
        let type: String
        let delta: ClaudeDeltaContent
        struct ClaudeDeltaContent: Decodable {
            let type: String
            let text: String?
        }
    }

    struct OpenAIDelta: Decodable {
        let choices: [Choice]
        struct Choice: Decodable {
            let delta: Delta
            struct Delta: Decodable {
                let content: String?
            }
        }
    }
}

extension SSEParser.ClaudeDelta.ClaudeDeltaContent {
    var text: String { (self as? SSEParser.ClaudeDelta.ClaudeDeltaContent)?.text ?? "" }
}
```

Corriger l'extension — remplacer par implémentation sans extension circulaire :

```swift
import Foundation

enum SSEParser {

    static func parseClaudeDelta(_ line: String) -> String? {
        guard line.hasPrefix("data: ") else { return nil }
        let json = String(line.dropFirst(6))
        guard let data = json.data(using: .utf8) else { return nil }
        struct Root: Decodable { let type: String?; let delta: Delta? }
        struct Delta: Decodable { let type: String?; let text: String? }
        guard let root = try? JSONDecoder().decode(Root.self, from: data),
              root.type == "content_block_delta",
              root.delta?.type == "text_delta" else { return nil }
        return root.delta?.text
    }

    static func parseOpenAIDelta(_ line: String) -> String? {
        guard line.hasPrefix("data: ") else { return nil }
        let json = String(line.dropFirst(6))
        if json.trimmingCharacters(in: .whitespaces) == "[DONE]" { return nil }
        guard let data = json.data(using: .utf8) else { return nil }
        struct Root: Decodable { let choices: [Choice]? }
        struct Choice: Decodable { let delta: Delta }
        struct Delta: Decodable { let content: String? }
        guard let root = try? JSONDecoder().decode(Root.self, from: data) else { return nil }
        return root.choices?.first?.delta.content
    }
}
```

### Étape 3 : Tests SSEParser

```swift
// GMacTests/Unit/SSEParserTests.swift
import XCTest
@testable import GMac

final class SSEParserTests: XCTestCase {

    func test_parseClaudeDelta_validLine_returnsText() {
        let line = """
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}
        """
        XCTAssertEqual(SSEParser.parseClaudeDelta(line), "Hello")
    }

    func test_parseClaudeDelta_wrongType_returnsNil() {
        let line = """
        data: {"type":"message_stop","delta":{"type":"text_delta","text":"ignored"}}
        """
        XCTAssertNil(SSEParser.parseClaudeDelta(line))
    }

    func test_parseClaudeDelta_nonDataLine_returnsNil() {
        XCTAssertNil(SSEParser.parseClaudeDelta("event: content_block_start"))
        XCTAssertNil(SSEParser.parseClaudeDelta(""))
    }

    func test_parseOpenAIDelta_validLine_returnsText() {
        let line = """
        data: {"choices":[{"delta":{"content":"World"},"finish_reason":null}]}
        """
        XCTAssertEqual(SSEParser.parseOpenAIDelta(line), "World")
    }

    func test_parseOpenAIDelta_doneMarker_returnsNil() {
        XCTAssertNil(SSEParser.parseOpenAIDelta("data: [DONE]"))
    }

    func test_parseOpenAIDelta_emptyContent_returnsNil() {
        let line = """
        data: {"choices":[{"delta":{"content":null},"finish_reason":"stop"}]}
        """
        XCTAssertNil(SSEParser.parseOpenAIDelta(line))
    }
}
```

### Commit Task 1

```bash
xcodegen generate
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | head -3
git add GMac/AI/SSEParser.swift GMac/AI/LLMProvider.swift GMacTests/Unit/SSEParserTests.swift
git commit -m "feat: SSEParser (Claude + OpenAI/Mistral delta), generateReplyStream dans protocole LLMProvider"
```

---

## Task 2 : Streaming dans les providers + AIAssistantViewModel

**Files:**
- Modify: `GMac/AI/Providers/ClaudeProvider.swift`
- Modify: `GMac/AI/Providers/OpenAIProvider.swift`
- Modify: `GMac/AI/Providers/MistralProvider.swift`
- Modify: `GMac/AI/Providers/GeminiProvider.swift`
- Modify: `GMac/AI/AIAssistantViewModel.swift`
- Modify: `GMacTests/Mocks/MockLLMProvider.swift`

### Implémenter `generateReplyStream` dans ClaudeProvider

```swift
func generateReplyStream(thread: EmailThread, instruction: UserInstruction) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        Task {
            do {
                guard let apiKey = try? keychain.retrieve(key: "claude_api_key"), !apiKey.isEmpty else {
                    continuation.finish(throwing: LLMError.noAPIKey)
                    return
                }
                let toneSource = ToneContextResolver.resolve(thread: thread, sentMessages: instruction.toneExamples)
                let conversation = PromptBuilder.buildReplyPrompt(thread: thread, instruction: instruction, toneSource: toneSource)

                struct Msg: Encodable { let role: String; let content: String }
                struct Req: Encodable {
                    let model: String; let maxTokens: Int; let stream: Bool
                    let system: String; let messages: [Msg]
                    enum CodingKeys: String, CodingKey { case model, stream, system, messages; case maxTokens = "max_tokens" }
                }
                let sys = conversation.messages.first(where: { $0.role == .system })?.content ?? ""
                let msgs = conversation.messages.filter { $0.role != .system }.map { Msg(role: $0.role.rawValue, content: $0.content) }
                let body = Req(model: model, maxTokens: 1024, stream: true, system: sys, messages: msgs)

                var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                request.httpMethod = "POST"
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(body)

                let (bytes, _) = try await URLSession.shared.bytes(for: request)
                for try await line in bytes.lines {
                    if let chunk = SSEParser.parseClaudeDelta(line) {
                        continuation.yield(chunk)
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
```

### Implémenter `generateReplyStream` dans OpenAIProvider et MistralProvider

Même pattern avec `"stream": true` et `SSEParser.parseOpenAIDelta` :

```swift
func generateReplyStream(thread: EmailThread, instruction: UserInstruction) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        Task {
            do {
                guard let apiKey = try? keychain.retrieve(key: "openai_api_key"), !apiKey.isEmpty else {
                    continuation.finish(throwing: LLMError.noAPIKey); return
                }
                let toneSource = ToneContextResolver.resolve(thread: thread, sentMessages: instruction.toneExamples)
                let conversation = PromptBuilder.buildReplyPrompt(thread: thread, instruction: instruction, toneSource: toneSource)

                struct Msg: Encodable { let role: String; let content: String }
                struct Req: Encodable { let model: String; let stream: Bool; let messages: [Msg] }
                let body = Req(model: model, stream: true, messages: conversation.messages.map { Msg(role: $0.role.rawValue, content: $0.content) })

                var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(body)

                let (bytes, _) = try await URLSession.shared.bytes(for: request)
                for try await line in bytes.lines {
                    if let chunk = SSEParser.parseOpenAIDelta(line) {
                        continuation.yield(chunk)
                    }
                }
                continuation.finish()
            } catch { continuation.finish(throwing: error) }
        }
    }
}
```

Mistral : même code, URL `https://api.mistral.ai/v1/chat/completions`, clé `mistral_api_key`.

Gemini streaming : endpoint `streamGenerateContent`, réponse NDJSON (pas SSE) — implémenter en non-streaming pour l'instant (déléguer à `generateReply` non-streaming) :

```swift
func generateReplyStream(thread: EmailThread, instruction: UserInstruction) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        Task {
            do {
                let text = try await generateReply(thread: thread, instruction: instruction)
                continuation.yield(text)
                continuation.finish()
            } catch { continuation.finish(throwing: error) }
        }
    }
}
```

### Mettre à jour AIAssistantViewModel pour streaming

Lire `GMac/AI/AIAssistantViewModel.swift`. Ajouter `streamingText` et `generateStreaming` :

```swift
var streamingText: String = ""

func generateStreaming(thread: EmailThread, senderEmail: String, sentMessages: [EmailMessage]) async {
    state = .generating
    streamingText = ""
    toneSource = ToneContextResolver.resolve(thread: thread, sentMessages: sentMessages)
    let instruction = UserInstruction(freeText: freeText, objective: selectedObjective, tone: selectedTone,
                                      length: selectedLength, senderEmail: senderEmail, toneExamples: toneSource.examples)
    do {
        var accumulated = ""
        conversation = PromptBuilder.buildReplyPrompt(thread: thread, instruction: instruction, toneSource: toneSource)
        for try await chunk in provider.generateReplyStream(thread: thread, instruction: instruction) {
            accumulated += chunk
            streamingText = accumulated
            state = .done(accumulated)  // mise à jour en temps réel
        }
        conversation.append(role: .assistant, content: accumulated)
        state = .done(accumulated)
    } catch LLMError.noAPIKey {
        state = .failed("Clé API manquante. Configurez-la dans Paramètres → Assistant IA.")
    } catch {
        state = .failed(error.localizedDescription)
    }
}
```

Mettre à jour `AIAssistantPanel.actionRow` pour utiliser `generateStreaming` :
```swift
// Remplacer l'appel generate par generateStreaming dans le bouton Générer
await vm.generateStreaming(thread: thread, senderEmail: senderEmail, sentMessages: sentMessages)
```

Mettre à jour `MockLLMProvider` pour implémenter la nouvelle méthode :
```swift
var stubbedStreamChunks: [String] = ["Hello ", "from ", "AI"]

func generateReplyStream(thread: EmailThread, instruction: UserInstruction) -> AsyncThrowingStream<String, Error> {
    let chunks = stubbedStreamChunks
    let shouldThrow = shouldThrowNoAPIKey
    return AsyncThrowingStream { continuation in
        Task {
            if shouldThrow { continuation.finish(throwing: LLMError.noAPIKey); return }
            for chunk in chunks { continuation.yield(chunk) }
            continuation.finish()
        }
    }
}
```

### Tests streaming

```swift
// Ajouter dans AIAssistantViewModelTests.swift
func test_generateStreaming_accumulatesChunks() async {
    mock.stubbedStreamChunks = ["Hello ", "world", "!"]
    let t = thread()
    await vm.generateStreaming(thread: t, senderEmail: "me@example.com", sentMessages: [])
    if case .done(let text) = vm.state {
        XCTAssertEqual(text, "Hello world!")
    } else { XCTFail("Expected .done") }
}

func test_generateStreaming_noAPIKey_movesFailed() async {
    mock.shouldThrowNoAPIKey = true
    await vm.generateStreaming(thread: thread(), senderEmail: "me@example.com", sentMessages: [])
    if case .failed(let msg) = vm.state {
        XCTAssertTrue(msg.contains("Clé API"))
    } else { XCTFail("Expected .failed") }
}
```

### Commit Task 2

```bash
xcodegen generate
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | head -3
git add GMac/AI/ GMacTests/Unit/AIAssistantViewModelTests.swift GMacTests/Mocks/MockLLMProvider.swift
git commit -m "feat: streaming SSE Claude/OpenAI/Mistral via AsyncThrowingStream, AIAssistantViewModel.generateStreaming"
```

---

## Task 3 : VoiceProfileAnalyzer

**Files:**
- Create: `GMac/AI/VoiceProfileAnalyzer.swift`
- Create: `GMacTests/Unit/VoiceProfileAnalyzerTests.swift`

### `GMac/AI/VoiceProfileAnalyzer.swift`

```swift
import Foundation
import SwiftData

final class VoiceProfileAnalyzer: Sendable {
    private let provider: any LLMProvider

    init(provider: any LLMProvider) {
        self.provider = provider
    }

    func analyze(sentMessages: [EmailMessage], existing: VoiceProfile?) async throws -> VoiceProfileData {
        guard !sentMessages.isEmpty else {
            return VoiceProfileData(
                formalityLevel: "semi-formel", sentenceStructure: "mixte",
                greetingPatterns: [], closingPatterns: [], vocabulary: "standard",
                paragraphStyle: "court", specificExpressions: [], thingsToAvoid: []
            )
        }

        let samples = sentMessages.prefix(30).compactMap { $0.bodyPlain ?? $0.snippet }.filter { !$0.isEmpty }
        let emailsText = samples.prefix(15).enumerated().map { "---Email \($0.offset + 1)---\n\($0.element)" }.joined(separator: "\n")

        let systemPrompt = """
        Tu analyses des emails et extrais le style d'écriture de leur auteur.
        Réponds UNIQUEMENT avec un JSON valide, sans markdown ni texte supplémentaire.
        """
        let userPrompt = """
        Analyse ces emails envoyés et décris le style d'écriture de leur auteur en JSON :
        {
          "formalityLevel": "formel|semi-formel|informel",
          "sentenceStructure": "courtes|longues|mixtes",
          "greetingPatterns": ["formule1", "formule2"],
          "closingPatterns": ["formule1", "formule2"],
          "vocabulary": "soutenu|courant|familier",
          "paragraphStyle": "court|développé|mixte",
          "specificExpressions": ["expression1"],
          "thingsToAvoid": ["chose à éviter"]
        }

        Emails à analyser :
        \(emailsText)
        """

        var conversation = LLMConversation()
        conversation.append(role: .system, content: systemPrompt)
        conversation.append(role: .user, content: userPrompt)

        let response = try await provider.refine(conversation: LLMConversation(), instruction: userPrompt)
        return try parseVoiceProfileJSON(response)
    }

    private func parseVoiceProfileJSON(_ json: String) throws -> VoiceProfileData {
        let cleaned = json.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw LLMError.decodingFailed("Cannot encode JSON string")
        }
        return try JSONDecoder().decode(VoiceProfileData.self, from: data)
    }
}

struct VoiceProfileData: Decodable, Sendable {
    let formalityLevel: String
    let sentenceStructure: String
    let greetingPatterns: [String]
    let closingPatterns: [String]
    let vocabulary: String
    let paragraphStyle: String
    let specificExpressions: [String]
    let thingsToAvoid: [String]

    func applyTo(_ profile: VoiceProfile) {
        profile.formalityLevel = formalityLevel
        profile.sentenceStructure = sentenceStructure
        profile.greetingPatterns = greetingPatterns
        profile.closingPatterns = closingPatterns
        profile.vocabulary = vocabulary
        profile.paragraphStyle = paragraphStyle
        profile.specificExpressions = specificExpressions
        profile.thingsToAvoid = thingsToAvoid
        profile.lastUpdated = Date()
    }
}
```

### Tests VoiceProfileAnalyzer

```swift
// GMacTests/Unit/VoiceProfileAnalyzerTests.swift
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
        let result = try await analyzer.analyze(sentMessages: [], existing: nil)
        XCTAssertEqual(result.formalityLevel, "semi-formel")
    }

    func test_analyze_validLLMResponse_parsesJSON() async throws {
        mockProvider.stubbedRefinement = """
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
        let msg = EmailMessage(id: "1", threadId: "t", snippet: "Test", subject: "S",
            from: "me@ex.com", to: ["you@ex.com"], date: Date(),
            bodyHTML: nil, bodyPlain: "Bonjour, Suite à notre échange...", labelIds: ["SENT"], isUnread: false, attachmentRefs: [])
        let result = try await analyzer.analyze(sentMessages: [msg], existing: nil)
        XCTAssertEqual(result.formalityLevel, "formel")
        XCTAssertEqual(result.greetingPatterns, ["Bonjour,", "Madame, Monsieur,"])
        XCTAssertEqual(result.closingPatterns, ["Cordialement,"])
    }

    func test_analyze_jsonWithMarkdown_parsesCorrectly() async throws {
        mockProvider.stubbedRefinement = """
        ```json
        {"formalityLevel":"informel","sentenceStructure":"courtes","greetingPatterns":["Salut"],"closingPatterns":["Bonne journée"],"vocabulary":"courant","paragraphStyle":"court","specificExpressions":[],"thingsToAvoid":[]}
        ```
        """
        let msg = EmailMessage(id: "1", threadId: "t", snippet: "Hi", subject: "S",
            from: "me@ex.com", to: ["y@ex.com"], date: Date(),
            bodyHTML: nil, bodyPlain: "Salut, comment ça va ?", labelIds: ["SENT"], isUnread: false, attachmentRefs: [])
        let result = try await analyzer.analyze(sentMessages: [msg], existing: nil)
        XCTAssertEqual(result.formalityLevel, "informel")
    }
}
```

### Intégrer VoiceProfileAnalyzer dans AppEnvironment

Lire `AppEnvironment.swift`. Ajouter :
```swift
let voiceProfileAnalyzer: VoiceProfileAnalyzer

// Dans init() :
self.voiceProfileAnalyzer = VoiceProfileAnalyzer(provider: aiSettings.activeProvider())
```

### Commit Task 3

```bash
xcodegen generate
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | head -3
git add GMac/AI/VoiceProfileAnalyzer.swift GMac/App/AppEnvironment.swift GMacTests/Unit/VoiceProfileAnalyzerTests.swift
git commit -m "feat: VoiceProfileAnalyzer — analyse 30 derniers emails, JSON parsing avec cleanup markdown"
```

---

## Task 4 : Liquid Glass UI polish

> **Note :** Utiliser le skill `frontend-design` pour chaque composant. Cette task couvre les 5 composants prioritaires.

**Files:**
- Modify: `GMac/UI/Compose/SendButton.swift`
- Modify: `GMac/UI/Compose/ComposeView.swift`
- Modify: `GMac/UI/ThreadList/ThreadListView.swift`
- Modify: `GMac/UI/LoginView.swift`
- Modify: `GMac/UI/AIPanel/AIAssistantPanel.swift`

### Principes Liquid Glass macOS 26

- **Matériau** : `.ultraThinMaterial` ou `.regularMaterial` pour les panels
- **Formes** : `RoundedRectangle(cornerRadius: 12-16)` avec ombres légères
- **Couleurs** : systémiques, jamais hardcodées — `.accentColor`, `.primary`, `.secondary`
- **Animations** : `.spring(response: 0.3, dampingFraction: 0.7)` pour les transitions
- **Boutons** : `.bordered` ou `.borderedProminent` natifs macOS 26 (Liquid Glass automatique)

### SendButton — countdown Liquid Glass

Remplacer la barre de progression custom par une animation fluide :

```swift
case .countdown(let progress):
    HStack(spacing: 8) {
        Button("Annuler", action: onCancel)
            .buttonStyle(.bordered)
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .frame(width: 140, height: 32)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.gradient)
                    .frame(width: geo.size.width * progress)
                    .animation(.linear(duration: 0.1), value: progress)
            }
            .frame(width: 140, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("Envoi dans \(max(0, Int(ceil(3 * (1 - progress)))))s")
                .font(.caption.bold())
                .foregroundStyle(.primary)
        }
    }
```

### ComposeView — header Liquid Glass

```swift
private var headerBar: some View {
    HStack { ... }
    .padding(.horizontal)
    .padding(.vertical, 10)
    .background(.regularMaterial)
}
```

### ThreadListView — sélection avec animation

```swift
private struct ThreadRow: View {
    let thread: EmailThread
    var body: some View {
        VStack(...) { ... }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
}
// Les listes macOS 26 appliquent automatiquement Liquid Glass sur la sélection
```

### LoginView — card glass

```swift
var body: some View {
    ZStack {
        // Gradient de fond
        LinearGradient(colors: [.blue.opacity(0.2), .purple.opacity(0.1)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
        // Card glass
        VStack(spacing: 24) { ... }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
    }
}
```

### AIAssistantPanel — sidebar glass

Envelopper dans un `ZStack` avec `.regularMaterial` en fond et une séparation visuelle :

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 0) { ... }
    .background(.regularMaterial)
    .frame(minWidth: 300, maxWidth: 400)
}
```

### Commit Task 4

```bash
xcodegen generate
xcodebuild build -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | head -3
git add GMac/UI/
git commit -m "feat: Liquid Glass UI — SendButton countdown, ComposeView header, LoginView card, AIPanel sidebar"
```

---

## Task 5 : SyncEngine — polling historyId automatique

**Files:**
- Create: `GMac/Services/SyncEngine.swift`
- Modify: `GMac/UI/ContentView.swift`

### `GMac/Services/SyncEngine.swift`

```swift
import Foundation

@Observable
@MainActor
final class SyncEngine {
    private(set) var isRunning = false
    private var pollTask: Task<Void, Never>?
    private let store: SessionStore
    private let intervalSeconds: TimeInterval

    init(store: SessionStore, intervalSeconds: TimeInterval = 60) {
        self.store = store
        self.intervalSeconds = intervalSeconds
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.store.reconcile()
                try? await Task.sleep(for: .seconds(self.intervalSeconds))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        isRunning = false
    }
}
```

### Intégrer SyncEngine dans AppEnvironment et ContentView

Dans `AppEnvironment.swift`, ajouter :
```swift
let syncEngine: SyncEngine
// Dans init() : self.syncEngine = SyncEngine(store: sessionStore)
```

Dans `ContentView.swift`, démarrer/arrêter le sync engine :
```swift
.onAppear { appEnv.syncEngine.start() }
.onDisappear { appEnv.syncEngine.stop() }
```

### Tests SyncEngine

```swift
// GMacTests/Unit/SyncEngineTests.swift
import XCTest
@testable import GMac

@MainActor
final class SyncEngineTests: XCTestCase {
    func test_start_setsIsRunning() {
        let mockService = MockGmailService()
        let store = SessionStore(gmailService: mockService)
        let engine = SyncEngine(store: store, intervalSeconds: 3600)
        engine.start()
        XCTAssertTrue(engine.isRunning)
        engine.stop()
    }

    func test_stop_clearsIsRunning() {
        let mockService = MockGmailService()
        let store = SessionStore(gmailService: mockService)
        let engine = SyncEngine(store: store, intervalSeconds: 3600)
        engine.start()
        engine.stop()
        XCTAssertFalse(engine.isRunning)
    }

    func test_start_idempotent() {
        let mockService = MockGmailService()
        let store = SessionStore(gmailService: mockService)
        let engine = SyncEngine(store: store, intervalSeconds: 3600)
        engine.start()
        engine.start()  // deuxième appel — ne doit pas créer une deuxième task
        XCTAssertTrue(engine.isRunning)
        engine.stop()
    }
}
```

### Commit Task 5

```bash
xcodegen generate
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | head -3
git add GMac/Services/SyncEngine.swift GMac/App/AppEnvironment.swift GMac/UI/ContentView.swift GMacTests/Unit/SyncEngineTests.swift
git commit -m "feat: SyncEngine — polling historyId automatique toutes les 60s, start/stop depuis ContentView"
```

---

## Task 6 : README + CONTRIBUTING + GitHub prep

**Files:**
- Create: `README.md`
- Modify: `CONTRIBUTING.md` (déjà créé au Sprint 1)

### README.md

```markdown
# GMac

**Client Gmail natif macOS avec assistant IA intégré**

GMac est un client mail open source pour macOS, construit avec SwiftUI natif. Il utilise directement l'API Gmail (pas IMAP) et intègre un assistant IA multi-LLM qui génère des réponses dans votre ton, avec injection directe dans le composeur.

## Pourquoi GMac ?

| App | Natif macOS | Gmail API | IA intégrée | Prix | Open source |
|---|---|---|---|---|---|
| Mimestream | ✅ | ✅ | ❌ | 120$/an | ❌ |
| Superhuman | ❌ Electron | ✅ | Partiel | 360$/an | ❌ |
| **GMac** | **✅ SwiftUI** | **✅** | **✅ Multi-LLM** | **Gratuit** | **✅ MIT** |

## Fonctionnalités

- **Client Gmail complet** — threads, labels natifs, recherche, envoi différé, pièces jointes
- **Countdown 3s annulable** — le mail ne part que 3s après clic, annulation en un clic
- **Assistant IA multi-LLM** — Claude, GPT-4o, Gemini, Mistral avec vos propres clés API
- **ToneContextResolver** — l'IA écrit dans votre ton (analyse vos vrais emails)
- **Google Drive intégré** — upload/download de PJ directement depuis GMac
- **Settings Gmail** — signature HTML, message d'absence, labels depuis l'app
- **Privacy first** — IA opt-in, clés API dans le Keychain macOS, données Gmail jamais persistées sur disque

## Prérequis

- macOS 26.0+ (Tahoe)
- Xcode 26+
- Compte Google Cloud avec Gmail API + Drive API activés

## Installation

```bash
git clone https://github.com/florianchambolle/gmac
cd gmac
xcodegen generate
open GMac.xcodeproj
```

Créer les credentials OAuth dans [Google Cloud Console](https://console.cloud.google.com), puis remplir dans `GMac/Resources/Info.plist` :
- `GOOGLE_CLIENT_ID`
- `GOOGLE_CLIENT_SECRET`

Optionnel : configurer vos clés API LLM dans GMac → Paramètres → Assistant IA.

## Architecture

Voir `docs/2026-04-25-architecture-fiabilite-design.md` pour le design complet.

**Principe fondamental** : Gmail est la source de vérité. Aucune donnée Gmail n'est persistée sur disque. Toutes les mutations bloquent l'UI jusqu'à confirmation API — zéro mail perdu par design.

```
UI (SwiftUI)
    ↓
ViewModels (@Observable @MainActor)
    ↓
SessionStore (in-memory)
    ↓
Services (GmailService, DriveService, GmailSettingsService)
    ↓
AuthenticatedHTTPClient (token refresh auto, retry isRetryable)
    ↓
SwiftData (VoiceProfile, préférences uniquement — jamais données Gmail)
```

## Tests

```bash
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64'
```

168+ tests unitaires couvrant : réseau, auth, MIME, SessionStore (pendingOperations), LLM providers.

## Licence

MIT — voir [LICENSE](LICENSE).
```

### Créer `LICENSE`

```
MIT License

Copyright (c) 2026 Florian Chambolle

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Commit Task 6

```bash
git add README.md LICENSE CONTRIBUTING.md
git commit -m "docs: README complet, LICENSE MIT, CONTRIBUTING — GMac prêt pour GitHub"
```

---

## Résumé Sprint 6 (dernier sprint)

À la fin de ce sprint, GMac est :
- **Complet fonctionnellement** — tous les sprints 1-6 livrés
- **Streaming IA** — réponses apparaissent en temps réel (Claude, OpenAI, Mistral)
- **VoiceProfileAnalyzer** — analyse automatique du style d'écriture
- **Sync automatique** — historyId polling toutes les 60s
- **UI Liquid Glass** — interface macOS 26 Tahoe native
- **Open source** — README, LICENSE MIT, CONTRIBUTING

**Nombre total de tests cible : 180+**

---

*Plan Sprint 6 — GMac — 25 avril 2026 — Dernier sprint*
