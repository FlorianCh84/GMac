# GMac Sprint 2 — Composeur

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Permettre d'écrire, répondre, transférer et envoyer des emails depuis GMac — avec countdown 3s annulable, idempotency garantie, et gestion des brouillons.

**Architecture:** `ComposeViewModel` (@Observable @MainActor) orchestre la machine d'états `SendState` (idle → countdown → sending → failed). L'API Gmail n'est jamais appelée avant la fin du countdown. `MIMEBuilder` construit les messages RFC 2822 base64url. Zéro retry automatique sur l'envoi (non-idempotent — l'utilisateur confirme manuellement).

**Tech Stack:** Swift 6, SwiftUI, Gmail REST API v1 (messages/send, drafts/\*), Foundation (Data, base64url)

---

## Prérequis

Fichiers existants importants :
- `GMac/Models/OutgoingMessage.swift` — déjà `idempotencyKey: UUID`, Sprint 2 tâche 0 = zéro modification
- `GMac/Services/GmailService.swift` — `send()` retourne `.failure(.unknown)` → à implémenter Task 3
- `GMac/Services/GmailServiceProtocol.swift` — ajouter `createDraft`, `updateDraft`, `deleteDraft`
- `GMac/Network/Endpoints.swift` — ajouter `draftCreate`, `draftUpdate`, `draftDelete`, `draftSend`

---

## Task 1 : SendState + ComposeViewModel

**Files:**
- Create: `GMac/UI/Compose/ComposeViewModel.swift`
- Create: `GMacTests/Unit/ComposeViewModelTests.swift`

### Étape 1 : Écrire les tests en premier

```swift
// GMacTests/Unit/ComposeViewModelTests.swift
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
            XCTFail("Initial state must be .idle")
        }
    }

    func test_send_transitionsToCountdown() async {
        vm.to = "bob@example.com"
        vm.subject = "Hello"
        vm.body = "Test"
        mockService.stubSend(.success(()))

        // startSend() démarre le countdown mais ne bloque pas
        let task = Task { await vm.startSend() }
        // Donner un tick pour que l'état transite
        try? await Task.sleep(for: .milliseconds(50))
        if case .countdown = vm.sendState { } else {
            XCTFail("Expected .countdown after startSend(), got \(vm.sendState)")
        }
        task.cancel()
    }

    func test_cancel_duringCountdown_returnsToIdle() async {
        vm.to = "bob@example.com"
        vm.subject = "Subject"
        vm.body = "Body"

        let task = Task { await vm.startSend() }
        try? await Task.sleep(for: .milliseconds(50))
        vm.cancelSend()
        try? await Task.sleep(for: .milliseconds(50))

        if case .idle = vm.sendState { } else {
            XCTFail("Expected .idle after cancel, got \(vm.sendState)")
        }
        task.cancel()
        // Vérifier que l'API n'a pas été appelée
        XCTAssertEqual(mockService.sendCallCount, 0)
    }

    func test_send_afterCountdown_callsAPI() async {
        vm.to = "bob@example.com"
        vm.subject = "Subject"
        vm.body = "Body"
        mockService.stubSend(.success(()))

        await vm.startSend(countdownDuration: 0)  // countdown = 0 pour les tests

        if case .idle = vm.sendState { } else {
            XCTFail("Expected .idle (reset) after success, got \(vm.sendState)")
        }
        XCTAssertEqual(mockService.sendCallCount, 1)
    }

    func test_send_failure_returnsFailedState() async {
        vm.to = "bob@example.com"
        vm.subject = "Subject"
        vm.body = "Body"
        mockService.stubSend(.failure(.offline))

        await vm.startSend(countdownDuration: 0)

        if case .failed(.offline) = vm.sendState { } else {
            XCTFail("Expected .failed(.offline), got \(vm.sendState)")
        }
        // Le brouillon doit être intact (to/subject/body non effacés)
        XCTAssertEqual(vm.to, "bob@example.com")
    }

    func test_resetAfterFailure_returnsToIdle() async {
        vm.to = "bob@example.com"
        mockService.stubSend(.failure(.offline))
        await vm.startSend(countdownDuration: 0)
        vm.resetAfterFailure()
        if case .idle = vm.sendState { } else {
            XCTFail("Expected .idle after reset")
        }
    }

    func test_isValid_requiresToAndSubjectAndBody() {
        XCTAssertFalse(vm.isValid)
        vm.to = "bob@example.com"
        XCTAssertFalse(vm.isValid)
        vm.subject = "Subject"
        XCTAssertFalse(vm.isValid)
        vm.body = "Hello"
        XCTAssertTrue(vm.isValid)
    }
}
```

### Étape 2 : Lancer les tests — vérifier l'échec

```bash
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "error:|TEST" | head -10
```
Attendu : `error: cannot find type 'ComposeViewModel'`

### Étape 3 : Implémenter `ComposeViewModel.swift`

```swift
// GMac/UI/Compose/ComposeViewModel.swift
import Foundation
import Observation

enum SendState: Sendable {
    case idle
    case countdown(progress: Double)   // 0.0 → 1.0 pendant countdownDuration secondes
    case sending
    case failed(AppError)
}

@Observable
@MainActor
final class ComposeViewModel {
    // Champs du composeur
    var to: String = ""
    var cc: String = ""
    var subject: String = ""
    var body: String = ""
    var replyToThreadId: String? = nil
    var replyToMessageId: String? = nil

    // Machine d'états
    var sendState: SendState = .idle

    var isValid: Bool {
        !to.trimmingCharacters(in: .whitespaces).isEmpty &&
        !subject.trimmingCharacters(in: .whitespaces).isEmpty &&
        !body.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private let gmailService: any GmailServiceProtocol
    private var countdownTask: Task<Void, Never>?

    init(gmailService: any GmailServiceProtocol) {
        self.gmailService = gmailService
    }

    func startSend(countdownDuration: TimeInterval = 3.0) async {
        guard isValid else { return }
        sendState = .countdown(progress: 0.0)

        let message = OutgoingMessage(
            to: to.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) },
            cc: cc.isEmpty ? [] : cc.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) },
            subject: subject,
            body: body,
            replyToThreadId: replyToThreadId,
            replyToMessageId: replyToMessageId
        )

        // Countdown — l'API n'est jamais appelée pendant cette phase
        if countdownDuration > 0 {
            let steps = 30
            let stepDuration = countdownDuration / Double(steps)
            for step in 1...steps {
                if case .idle = sendState { return }  // annulé
                sendState = .countdown(progress: Double(step) / Double(steps))
                try? await Task.sleep(for: .seconds(stepDuration))
            }
        }

        // Vérifier que l'envoi n'a pas été annulé pendant le countdown
        if case .idle = sendState { return }

        sendState = .sending
        let result = await gmailService.send(message: message)

        switch result {
        case .success:
            clearComposer()
            sendState = .idle
        case .failure(let error):
            sendState = .failed(error)
            // Ne pas effacer le brouillon — l'utilisateur peut réessayer
        }
    }

    func cancelSend() {
        sendState = .idle
    }

    func resetAfterFailure() {
        sendState = .idle
    }

    private func clearComposer() {
        to = ""
        cc = ""
        subject = ""
        body = ""
        replyToThreadId = nil
        replyToMessageId = nil
    }
}
```

**Note :** `OutgoingMessage` doit accepter `cc` et `replyToMessageId`. Mettre à jour `GMac/Models/OutgoingMessage.swift` :

```swift
struct OutgoingMessage: Sendable {
    let to: [String]
    let cc: [String]
    let subject: String
    let body: String
    let replyToThreadId: String?
    let replyToMessageId: String?
    let idempotencyKey: UUID

    init(to: [String], cc: [String] = [], subject: String, body: String,
         replyToThreadId: String? = nil, replyToMessageId: String? = nil) {
        self.to = to
        self.cc = cc
        self.subject = subject
        self.body = body
        self.replyToThreadId = replyToThreadId
        self.replyToMessageId = replyToMessageId
        self.idempotencyKey = UUID()
    }
}
```

Mettre à jour `MockGmailService` pour ajouter `sendCallCount` :

```swift
private var _sendCallCount = 0
var sendCallCount: Int { lock.withLock { _sendCallCount } }

func send(message: OutgoingMessage) async -> Result<Void, AppError> {
    lock.withLock { _sendCallCount += 1; return _sendResult }
}
```

### Étape 4 : xcodegen + tests

```bash
xcodegen generate
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | head -3
```
Attendu : TEST SUCCEEDED, ~78 tests.

### Étape 5 : Commit

```bash
git add GMac/UI/Compose/ComposeViewModel.swift GMac/Models/OutgoingMessage.swift GMacTests/Unit/ComposeViewModelTests.swift GMacTests/Mocks/MockGmailService.swift
git commit -m "feat: SendState enum, ComposeViewModel — countdown 3s annulable, machine d'états envoi"
```

---

## Task 2 : MIMEBuilder — construction messages RFC 2822

**Files:**
- Create: `GMac/Services/MIMEBuilder.swift`
- Create: `GMacTests/Unit/MIMEBuilderTests.swift`

### Étape 1 : Écrire les tests

```swift
// GMacTests/Unit/MIMEBuilderTests.swift
import XCTest
@testable import GMac

final class MIMEBuilderTests: XCTestCase {

    func test_build_simpleTextMessage() throws {
        let message = OutgoingMessage(
            to: ["bob@example.com"],
            subject: "Hello",
            body: "Test body"
        )
        let raw = try MIMEBuilder.buildRaw(message: message, from: "alice@example.com")
        let decoded = decodeBase64url(raw)

        XCTAssertTrue(decoded.contains("To: bob@example.com"))
        XCTAssertTrue(decoded.contains("Subject: Hello"))
        XCTAssertTrue(decoded.contains("From: alice@example.com"))
        XCTAssertTrue(decoded.contains("MIME-Version: 1.0"))
        XCTAssertTrue(decoded.contains("Test body"))
    }

    func test_build_withCC() throws {
        let message = OutgoingMessage(
            to: ["bob@example.com"],
            cc: ["carol@example.com"],
            subject: "CC Test",
            body: "Body"
        )
        let raw = try MIMEBuilder.buildRaw(message: message, from: "alice@example.com")
        let decoded = decodeBase64url(raw)
        XCTAssertTrue(decoded.contains("Cc: carol@example.com"))
    }

    func test_build_reply_includesInReplyToAndReferences() throws {
        let message = OutgoingMessage(
            to: ["bob@example.com"],
            subject: "Re: Hello",
            body: "Reply body",
            replyToThreadId: "thread1",
            replyToMessageId: "<original-message-id@gmail.com>"
        )
        let raw = try MIMEBuilder.buildRaw(message: message, from: "alice@example.com")
        let decoded = decodeBase64url(raw)
        XCTAssertTrue(decoded.contains("In-Reply-To: <original-message-id@gmail.com>"))
        XCTAssertTrue(decoded.contains("References: <original-message-id@gmail.com>"))
    }

    func test_build_multipleRecipients() throws {
        let message = OutgoingMessage(
            to: ["bob@example.com", "carol@example.com"],
            subject: "Multi",
            body: "Body"
        )
        let raw = try MIMEBuilder.buildRaw(message: message, from: "alice@example.com")
        let decoded = decodeBase64url(raw)
        XCTAssertTrue(decoded.contains("bob@example.com") && decoded.contains("carol@example.com"))
    }

    func test_build_subjectEncoding_specialChars() throws {
        let message = OutgoingMessage(
            to: ["bob@example.com"],
            subject: "Réunion équipe",
            body: "Body"
        )
        let raw = try MIMEBuilder.buildRaw(message: message, from: "alice@example.com")
        // RFC 2047 encoding ou UTF-8 direct — doit ne pas crasher et contenir le sujet
        XCTAssertFalse(raw.isEmpty)
    }

    func test_rawIsValidBase64url() throws {
        let message = OutgoingMessage(to: ["bob@example.com"], subject: "Test", body: "Body")
        let raw = try MIMEBuilder.buildRaw(message: message, from: "alice@example.com")
        // base64url ne contient pas + ou /
        XCTAssertFalse(raw.contains("+"))
        XCTAssertFalse(raw.contains("/"))
    }

    // Helper
    private func decodeBase64url(_ encoded: String) -> String {
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let string = String(data: data, encoding: .utf8) else { return "" }
        return string
    }
}
```

### Étape 2 : Phase rouge, puis implémenter `MIMEBuilder.swift`

```swift
// GMac/Services/MIMEBuilder.swift
import Foundation

enum MIMEBuilderError: Error {
    case encodingFailed
}

enum MIMEBuilder {
    static func buildRaw(message: OutgoingMessage, from senderEmail: String) throws -> String {
        var lines: [String] = []

        lines.append("From: \(senderEmail)")
        lines.append("To: \(message.to.joined(separator: ", "))")
        if !message.cc.isEmpty {
            lines.append("Cc: \(message.cc.joined(separator: ", "))")
        }
        lines.append("Subject: \(encodeSubject(message.subject))")
        lines.append("MIME-Version: 1.0")
        lines.append("Content-Type: text/plain; charset=utf-8")
        lines.append("Content-Transfer-Encoding: base64")

        if let replyToId = message.replyToMessageId {
            lines.append("In-Reply-To: \(replyToId)")
            lines.append("References: \(replyToId)")
        }

        lines.append("")  // ligne vide séparant headers et body

        // Body encodé en base64
        guard let bodyData = message.body.data(using: .utf8) else {
            throw MIMEBuilderError.encodingFailed
        }
        lines.append(bodyData.base64EncodedString(options: .lineLength76Characters))

        let mimeString = lines.joined(separator: "\r\n")
        guard let mimeData = mimeString.data(using: .utf8) else {
            throw MIMEBuilderError.encodingFailed
        }

        // Encoder en base64url (RFC 4648 §5 — URL safe, pas de padding)
        return mimeData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // RFC 2047 encoding pour les sujets avec caractères non-ASCII
    private static func encodeSubject(_ subject: String) -> String {
        let ascii = subject.unicodeScalars.allSatisfy { $0.isASCII }
        if ascii { return subject }
        guard let data = subject.data(using: .utf8) else { return subject }
        let b64 = data.base64EncodedString()
        return "=?utf-8?b?\(b64)?="
    }
}
```

### Étape 3 : Tests + commit

```bash
xcodegen generate
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | head -3
```

```bash
git add GMac/Services/MIMEBuilder.swift GMacTests/Unit/MIMEBuilderTests.swift
git commit -m "feat: MIMEBuilder — RFC 2822 → base64url, reply headers, RFC 2047 subject encoding"
```

---

## Task 3 : GmailService.send() — implémentation réelle

**Files:**
- Modify: `GMac/Services/GmailService.swift`
- Modify: `GMac/Services/GmailAPIModels.swift` (ajouter SendMessageRequest, SendMessageResponse)
- Modify: `GMacTests/Unit/GmailServiceTests.swift`

### Étape 1 : Ajouter les modèles dans `GmailAPIModels.swift`

```swift
struct SendMessageRequest: Encodable, Sendable {
    let raw: String
    let threadId: String?
}

struct SendMessageResponse: Decodable, Sendable {
    let id: String
    let threadId: String
    let labelIds: [String]?
}
```

Mettre à jour `Endpoints.swift` — vérifier que `messageSend()` est déjà présent (oui, depuis Sprint 1).

### Étape 2 : Écrire le test d'envoi

Dans `GMacTests/Unit/GmailServiceTests.swift`, ajouter :

```swift
func test_send_buildsCorrectRequest() async throws {
    let response = SendMessageResponse(id: "msg1", threadId: "thread1", labelIds: ["SENT"])
    mockClient.stub(response)

    let message = OutgoingMessage(
        to: ["bob@example.com"],
        subject: "Test",
        body: "Hello"
    )
    let result = await service.send(message: message, senderEmail: "alice@example.com")

    switch result {
    case .success:
        XCTAssertEqual(mockClient.callCount, 1)
        XCTAssertEqual(mockClient.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(mockClient.lastRequest?.url, Endpoints.messageSend())
    case .failure(let error):
        XCTFail("Expected success, got \(error)")
    }
}

func test_send_propagatesServerError() async throws {
    mockClient.stubError(.serverError(statusCode: 500))
    let message = OutgoingMessage(to: ["bob@example.com"], subject: "Test", body: "Hello")
    let result = await service.send(message: message, senderEmail: "alice@example.com")
    if case .failure(.serverError(500)) = result { } else {
        XCTFail("Expected .serverError(500)")
    }
}
```

Note : `GmailServiceProtocol.send()` doit accepter `senderEmail` — mettre à jour la signature :

```swift
// Dans GmailServiceProtocol.swift
func send(message: OutgoingMessage, senderEmail: String) async -> Result<Void, AppError>
```

Et `MockGmailService` en conséquence.

### Étape 3 : Implémenter `GmailService.send()`

```swift
func send(message: OutgoingMessage, senderEmail: String) async -> Result<Void, AppError> {
    do {
        let raw = try MIMEBuilder.buildRaw(message: message, from: senderEmail)
        let body = SendMessageRequest(raw: raw, threadId: message.replyToThreadId)

        var request = URLRequest(url: Endpoints.messageSend())
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let result: Result<SendMessageResponse, AppError> = await httpClient.send(request)
        return result.map { _ in () }
    } catch {
        return .failure(.unknown)
    }
}
```

Mettre à jour `ComposeViewModel` pour passer `senderEmail` — il faut que `SessionStore` expose l'email de l'utilisateur (à récupérer depuis les settings Gmail) ou le passer depuis `AppEnvironment`. Pour Sprint 2 : utiliser l'email stocké dans `ComposeViewModel.senderEmail` (injecté depuis l'extérieur).

### Étape 4 : Tests + commit

```bash
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | head -3
```

```bash
git add GMac/Services/GmailService.swift GMac/Services/GmailAPIModels.swift GMac/Services/GmailServiceProtocol.swift GMacTests/Unit/GmailServiceTests.swift GMacTests/Mocks/MockGmailService.swift
git commit -m "feat: GmailService.send() — MIME → base64url → Gmail API POST, reply threadId"
```

---

## Task 4 : Drafts — CRUD Gmail API

**Files:**
- Modify: `GMac/Services/GmailServiceProtocol.swift`
- Modify: `GMac/Services/GmailService.swift`
- Modify: `GMac/Services/GmailAPIModels.swift`
- Modify: `GMac/Network/Endpoints.swift`
- Modify: `GMacTests/Unit/GmailServiceTests.swift`

### Étape 1 : Ajouter les modèles draft dans `GmailAPIModels.swift`

```swift
struct DraftMessage: Decodable, Sendable {
    let id: String
    let message: GmailAPIMessage?
}

struct CreateDraftRequest: Encodable, Sendable {
    struct MessageRef: Encodable, Sendable { let raw: String; let threadId: String? }
    let message: MessageRef
}
```

### Étape 2 : Endpoints pour les drafts dans `Endpoints.swift`

```swift
static func draftCreate(userId: String = "me") -> URL {
    URL(string: "\(gmailBase)/users/\(userId)/drafts")!
    // → utiliser URLComponents pour être safe :
}

static func draftUpdate(userId: String = "me", id: String) -> URL { ... }

static func draftDelete(userId: String = "me", id: String) -> URL { ... }

static func draftSend(userId: String = "me") -> URL { ... }
```

Utiliser le même pattern `URLComponents + preconditionFailure` que les autres endpoints.

### Étape 3 : Protocole + implémentation

Ajouter à `GmailServiceProtocol` :
```swift
func createDraft(message: OutgoingMessage, senderEmail: String) async -> Result<DraftMessage, AppError>
func updateDraft(id: String, message: OutgoingMessage, senderEmail: String) async -> Result<DraftMessage, AppError>
func deleteDraft(id: String) async -> Result<Void, AppError>
```

Implémenter dans `GmailService` (même pattern que `send()`).

### Étape 4 : Écrire les tests

```swift
func test_createDraft_sendsCorrectRequest() async {
    let draft = DraftMessage(id: "draft1", message: nil)
    mockClient.stub(draft)
    let message = OutgoingMessage(to: ["bob@example.com"], subject: "Draft", body: "WIP")
    let result = await service.createDraft(message: message, senderEmail: "alice@example.com")
    switch result {
    case .success(let d): XCTAssertEqual(d.id, "draft1")
    case .failure(let e): XCTFail("\(e)")
    }
}

func test_deleteDraft_propagatesError() async {
    mockClient.stubError(.offline)
    let result = await service.deleteDraft(id: "draft1")
    if case .failure(.offline) = result { } else { XCTFail("Expected .offline") }
}
```

### Étape 5 : Commit

```bash
git add GMac/Services/ GMac/Network/Endpoints.swift GMacTests/Unit/GmailServiceTests.swift GMacTests/Mocks/MockGmailService.swift
git commit -m "feat: GmailService drafts — createDraft, updateDraft, deleteDraft via Gmail API"
```

---

## Task 5 : ComposeView — UI avec countdown button

**Files:**
- Create: `GMac/UI/Compose/ComposeView.swift`
- Create: `GMac/UI/Compose/SendButton.swift`

### `SendButton.swift` — bouton avec barre de progression countdown

```swift
// GMac/UI/Compose/SendButton.swift
import SwiftUI

struct SendButton: View {
    let sendState: SendState
    let isValid: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        switch sendState {
        case .idle:
            Button("Envoyer", action: onSend)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!isValid)
                .buttonStyle(.borderedProminent)

        case .countdown(let progress):
            HStack(spacing: 8) {
                Button("Annuler", action: onCancel)
                    .buttonStyle(.bordered)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.2))
                        .frame(height: 32)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor)
                        .frame(width: max(0, 120 * progress), height: 32)
                        .animation(.linear(duration: 0.1), value: progress)
                    Text("Envoi dans \(max(0, Int(3 * (1 - progress)) + 1))s")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 120)
                }
            }

        case .sending:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Envoi en cours…").font(.caption)
            }
            .padding(.horizontal)

        case .failed(let error):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Échec — \(errorMessage(error))")
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("Réessayer", action: onSend)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func errorMessage(_ error: AppError) -> String {
        switch error {
        case .offline: return "Hors ligne"
        case .rateLimited: return "Quota atteint"
        case .serverError: return "Erreur serveur"
        case .tokenExpired: return "Session expirée"
        default: return "Erreur réseau"
        }
    }
}
```

### `ComposeView.swift`

```swift
// GMac/UI/Compose/ComposeView.swift
import SwiftUI

struct ComposeView: View {
    @State var vm: ComposeViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Annuler") { onDismiss() }
                    .disabled(!isIdle)
                Spacer()
                Text(vm.replyToThreadId != nil ? "Répondre" : "Nouveau message")
                    .font(.headline)
                Spacer()
                SendButton(
                    sendState: vm.sendState,
                    isValid: vm.isValid,
                    onSend: { Task { await vm.startSend() } },
                    onCancel: { vm.cancelSend() }
                )
            }
            .padding()

            Divider()

            // Champs
            VStack(spacing: 0) {
                ComposeField(label: "À", text: $vm.to)
                Divider()
                ComposeField(label: "Cc", text: $vm.cc)
                Divider()
                ComposeField(label: "Objet", text: $vm.subject)
                Divider()
            }

            // Corps
            TextEditor(text: $vm.body)
                .font(.body)
                .padding(8)
                .frame(minHeight: 200)
        }
        .frame(minWidth: 550, minHeight: 400)
    }

    private var isIdle: Bool {
        if case .idle = vm.sendState { return true }
        return false
    }
}

private struct ComposeField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
            TextField("", text: $text)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
```

### Étape : xcodegen + build (pas de tests UI)

```bash
xcodegen generate
xcodebuild build -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | head -3
```

### Commit

```bash
git add GMac/UI/Compose/
git commit -m "feat: ComposeView + SendButton — countdown 3s visuel, annulation, états sending/failed"
```

---

## Task 6 : Intégration ComposeView dans ContentView + bouton Répondre

**Files:**
- Modify: `GMac/UI/ContentView.swift`
- Modify: `GMac/UI/MessageView/MessageDetailView.swift`
- Modify: `GMac/App/AppEnvironment.swift`

### Étape 1 : Exposer l'email expéditeur depuis SessionStore ou AppEnvironment

Ajouter dans `GMac/Store/SessionStore.swift` :
```swift
var senderEmail: String = ""  // chargé depuis les settings Gmail au démarrage
```

### Étape 2 : Modifier `ContentView.swift`

Ajouter le bouton "Nouveau message" dans la toolbar et la sheet :

```swift
@State private var isComposing = false
@State private var composeReplyToThread: String? = nil
@State private var composeReplyToMessage: String? = nil

// Dans body, après NavigationSplitView :
.sheet(isPresented: $isComposing) {
    ComposeView(
        vm: ComposeViewModel(gmailService: ...), // injecté
        onDismiss: { isComposing = false }
    )
}
.toolbar {
    ToolbarItem {
        Button("Nouveau", systemImage: "square.and.pencil") {
            composeReplyToThread = nil
            composeReplyToMessage = nil
            isComposing = true
        }
    }
}
```

### Étape 3 : Bouton Répondre dans `MessageDetailView.swift`

Dans `MessageBubble`, ajouter un bouton Répondre qui déclenche l'ouverture du composeur avec le thread et message pré-remplis.

### Commit

```bash
git add GMac/UI/ GMac/Store/SessionStore.swift
git commit -m "feat: intégration composeur — bouton Nouveau message, bouton Répondre depuis MessageDetailView"
```

---

## Task 7 : Pièces jointes (drag & drop)

**Files:**
- Create: `GMac/Models/Attachment.swift`
- Modify: `GMac/Models/OutgoingMessage.swift`
- Modify: `GMac/Services/MIMEBuilder.swift`
- Modify: `GMac/UI/Compose/ComposeView.swift`
- Create: `GMacTests/Unit/MIMEBuilderAttachmentTests.swift`

### `Attachment.swift`

```swift
import Foundation

struct Attachment: Identifiable, Sendable {
    let id: UUID
    let filename: String
    let mimeType: String
    let data: Data

    var sizeDescription: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(data.count))
    }
}
```

Ajouter `attachments: [Attachment]` à `OutgoingMessage`.

### Tests MIMEBuilder avec pièce jointe

```swift
func test_build_withAttachment_createsMultipart() throws {
    let attachment = Attachment(
        id: UUID(),
        filename: "test.txt",
        mimeType: "text/plain",
        data: Data("Hello PJ".utf8)
    )
    let message = OutgoingMessage(
        to: ["bob@example.com"],
        subject: "PJ Test",
        body: "Voir PJ",
        attachments: [attachment]
    )
    let raw = try MIMEBuilder.buildRaw(message: message, from: "alice@example.com")
    let decoded = decodeBase64url(raw)
    XCTAssertTrue(decoded.contains("multipart/mixed"))
    XCTAssertTrue(decoded.contains("test.txt"))
}
```

### MIMEBuilder avec multipart/mixed pour les PJ

Mettre à jour `MIMEBuilder.buildRaw` : si `message.attachments` est non-vide, utiliser `multipart/mixed` avec boundary.

### Drag & drop dans ComposeView

```swift
.dropDestination(for: URL.self) { urls, _ in
    for url in urls {
        if let data = try? Data(contentsOf: url) {
            let filename = url.lastPathComponent
            let mimeType = mimeType(for: url)
            let attachment = Attachment(id: UUID(), filename: filename, mimeType: mimeType, data: data)
            vm.attachments.append(attachment)
        }
    }
    return true
}
```

### Commit

```bash
git add GMac/Models/Attachment.swift GMac/Models/OutgoingMessage.swift GMac/Services/MIMEBuilder.swift GMac/UI/Compose/ComposeView.swift GMacTests/Unit/MIMEBuilderAttachmentTests.swift
git commit -m "feat: pièces jointes — Attachment model, multipart/mixed MIME, drag & drop dans ComposeView"
```

---

## Task 8 : Envoi différé (date picker + scheduleTime)

**Files:**
- Modify: `GMac/Models/OutgoingMessage.swift`
- Modify: `GMac/Services/GmailAPIModels.swift`
- Modify: `GMac/Services/GmailService.swift`
- Modify: `GMac/UI/Compose/ComposeView.swift`

### Ajouter `scheduledDate` à `OutgoingMessage`

```swift
let scheduledDate: Date?  // nil = envoi immédiat
```

### Mettre à jour `SendMessageRequest`

```swift
struct SendMessageRequest: Encodable, Sendable {
    let raw: String
    let threadId: String?
    let scheduleTime: String?  // ISO 8601, nil si envoi immédiat

    init(raw: String, threadId: String?, scheduledDate: Date?) {
        self.raw = raw
        self.threadId = threadId
        if let date = scheduledDate {
            let formatter = ISO8601DateFormatter()
            self.scheduleTime = formatter.string(from: date)
        } else {
            self.scheduleTime = nil
        }
    }
}
```

### Date picker dans ComposeView

```swift
@State private var isScheduled = false
@State private var scheduledDate = Date().addingTimeInterval(3600)

// Dans ComposeView body :
Toggle("Envoi différé", isOn: $isScheduled)
if isScheduled {
    DatePicker("Date d'envoi", selection: $scheduledDate, in: Date()...)
        .labelsHidden()
}
```

### Test

```swift
func test_send_withScheduledDate_includesScheduleTime() async throws {
    let response = SendMessageResponse(id: "msg1", threadId: "t1", labelIds: nil)
    mockClient.stub(response)
    let futureDate = Date().addingTimeInterval(3600)
    let message = OutgoingMessage(
        to: ["bob@example.com"],
        subject: "Later",
        body: "Scheduled",
        scheduledDate: futureDate
    )
    _ = await service.send(message: message, senderEmail: "alice@example.com")
    let body = mockClient.lastRequest?.httpBody
    let json = try JSONDecoder().decode([String: String].self, from: body!)
    XCTAssertNotNil(json["scheduleTime"])
}
```

### Commit

```bash
git add GMac/Models/OutgoingMessage.swift GMac/Services/ GMac/UI/Compose/ComposeView.swift
git commit -m "feat: envoi différé — scheduledDate → scheduleTime ISO 8601, date picker dans ComposeView"
```

---

## Résumé Sprint 2

À la fin de ce sprint, GMac permet :
- Écrire un nouveau message ou répondre depuis le thread
- Envoi avec countdown 3s annulable visuellement (barre de progression sur le bouton)
- L'API Gmail n'est jamais appelée pendant le countdown — annulation = rien n'est parti
- En cas d'échec, le composeur reste ouvert avec le brouillon intact
- Pièces jointes par drag & drop
- Envoi différé avec date picker
- Brouillons sauvegardés sur Gmail

**Sprint 3 :** Settings Gmail (signature HTML, message d'absence, labels).

---

*Plan Sprint 2 — GMac — 25 avril 2026*
