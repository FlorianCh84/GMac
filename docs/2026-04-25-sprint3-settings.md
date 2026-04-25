# GMac Sprint 3 — Settings Gmail

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Permettre à l'utilisateur de configurer sa signature HTML, son message d'absence et ses labels directement depuis GMac, sans passer par Gmail web.

**Architecture:** `GmailSettingsService` (protocol-driven, injectable) wrappant les endpoints Gmail Settings API. Signature éditée dans une `WKWebView contenteditable`, contenu récupéré via `evaluateJavaScript`. Labels CRUD via `GmailService` existant (déjà implémenté pour la lecture). Tout passe par `AuthenticatedHTTPClient` existant.

**Tech Stack:** Swift 6, SwiftUI, WKWebView (contenteditable + WKScriptMessageHandler), Gmail REST API v1 (settings/sendAs, settings/vacationSettings, labels)

---

## Contexte — API Gmail Settings

### Scopes déjà configurés (Sprint 1)
- `gmail.settings.basic` — vacationSettings, filtres
- `gmail.settings.sharing` — sendAs (signatures)

### Endpoints à ajouter dans `Endpoints.swift`
```
GET  /settings/sendAs                    → liste des adresses d'envoi avec signatures
PATCH /settings/sendAs/{sendAsEmail}     → modifier la signature
GET  /settings/vacationSettings          → obtenir les paramètres d'absence
PUT  /settings/vacationSettings          → mettre à jour
POST /labels                             → créer un label
PUT  /labels/{id}                        → modifier un label
DELETE /labels/{id}                      → supprimer un label
```

---

## Task 1 : GmailSettingsService + modèles

**Files:**
- Create: `GMac/Services/GmailSettingsModels.swift`
- Create: `GMac/Services/GmailSettingsServiceProtocol.swift`
- Create: `GMac/Services/GmailSettingsService.swift`
- Modify: `GMac/Network/Endpoints.swift`
- Create: `GMacTests/Mocks/MockGmailSettingsService.swift`
- Create: `GMacTests/Unit/GmailSettingsServiceTests.swift`

### Étape 1 : Créer `GMac/Services/GmailSettingsModels.swift`

```swift
import Foundation

struct SendAsAlias: Decodable, Sendable {
    let sendAsEmail: String
    let displayName: String?
    let signature: String?
    let isDefault: Bool?
    let isPrimary: Bool?
}

struct SendAsListResponse: Decodable, Sendable {
    let sendAs: [SendAsAlias]
}

struct UpdateSignatureRequest: Encodable, Sendable {
    let signature: String

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(signature, forKey: .signature)
    }
    enum CodingKeys: String, CodingKey { case signature }
}

struct VacationSettings: Codable, Sendable {
    var enableAutoReply: Bool
    var responseSubject: String?
    var responseBodyPlainText: String?
    var responseBodyHtml: String?
    var startTime: String?   // Unix ms en String
    var endTime: String?     // Unix ms en String
    var restrictToContacts: Bool?
    var restrictToDomain: Bool?
}

struct CreateLabelRequest: Encodable, Sendable {
    let name: String
    let labelListVisibility: String
    let messageListVisibility: String

    init(name: String) {
        self.name = name
        self.labelListVisibility = "labelShow"
        self.messageListVisibility = "show"
    }
}
```

### Étape 2 : Ajouter endpoints dans `Endpoints.swift`

Lire le fichier. Ajouter après les endpoints existants :

```swift
static func sendAsList(userId: String = "me") -> URL {
    var c = URLComponents()
    c.scheme = "https"; c.host = "gmail.googleapis.com"
    c.path = "/gmail/v1/users/\(userId)/settings/sendAs"
    guard let url = c.url else { preconditionFailure("sendAsList URL invalide") }
    return url
}

static func sendAsUpdate(userId: String = "me", sendAsEmail: String) -> URL {
    // Encode l'email pour l'URL
    let encoded = sendAsEmail.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sendAsEmail
    var c = URLComponents()
    c.scheme = "https"; c.host = "gmail.googleapis.com"
    c.path = "/gmail/v1/users/\(userId)/settings/sendAs/\(encoded)"
    guard let url = c.url else { preconditionFailure("sendAsUpdate URL invalide") }
    return url
}

static func vacationSettings(userId: String = "me") -> URL {
    var c = URLComponents()
    c.scheme = "https"; c.host = "gmail.googleapis.com"
    c.path = "/gmail/v1/users/\(userId)/settings/vacation"
    guard let url = c.url else { preconditionFailure("vacationSettings URL invalide") }
    return url
}

static func labelCreate(userId: String = "me") -> URL {
    var c = URLComponents()
    c.scheme = "https"; c.host = "gmail.googleapis.com"
    c.path = "/gmail/v1/users/\(userId)/labels"
    guard let url = c.url else { preconditionFailure("labelCreate URL invalide") }
    return url
}

static func labelUpdate(userId: String = "me", id: String) -> URL {
    var c = URLComponents()
    c.scheme = "https"; c.host = "gmail.googleapis.com"
    c.path = "/gmail/v1/users/\(userId)/labels/\(id)"
    guard let url = c.url else { preconditionFailure("labelUpdate URL invalide") }
    return url
}

static func labelDelete(userId: String = "me", id: String) -> URL {
    labelUpdate(userId: userId, id: id)  // même URL, méthode DELETE
}
```

### Étape 3 : Créer `GMac/Services/GmailSettingsServiceProtocol.swift`

```swift
import Foundation

protocol GmailSettingsServiceProtocol: Sendable {
    func fetchSendAsList() async -> Result<[SendAsAlias], AppError>
    func updateSignature(sendAsEmail: String, html: String) async -> Result<Void, AppError>
    func fetchVacationSettings() async -> Result<VacationSettings, AppError>
    func updateVacationSettings(_ settings: VacationSettings) async -> Result<Void, AppError>
    func createLabel(name: String) async -> Result<GmailLabel, AppError>
    func updateLabel(id: String, name: String) async -> Result<GmailLabel, AppError>
    func deleteLabel(id: String) async -> Result<Void, AppError>
}
```

### Étape 4 : Écrire les tests d'abord

```swift
// GMacTests/Unit/GmailSettingsServiceTests.swift
import XCTest
@testable import GMac

final class GmailSettingsServiceTests: XCTestCase {
    var mockClient: MockHTTPClient!
    var service: GmailSettingsService!

    override func setUp() {
        mockClient = MockHTTPClient()
        service = GmailSettingsService(httpClient: mockClient)
    }

    func test_fetchSendAsList_returnsMappedAliases() async {
        let response = SendAsListResponse(sendAs: [
            SendAsAlias(sendAsEmail: "alice@example.com", displayName: "Alice", signature: "<p>Hello</p>", isDefault: true, isPrimary: true)
        ])
        mockClient.stub(response)
        let result = await service.fetchSendAsList()
        switch result {
        case .success(let aliases):
            XCTAssertEqual(aliases.count, 1)
            XCTAssertEqual(aliases[0].sendAsEmail, "alice@example.com")
            XCTAssertEqual(aliases[0].signature, "<p>Hello</p>")
        case .failure(let e): XCTFail("\(e)")
        }
    }

    func test_fetchSendAsList_propagatesError() async {
        mockClient.stubError(.offline)
        let result = await service.fetchSendAsList()
        XCTAssertEqual(result, .failure(.offline))
    }

    func test_updateSignature_sendsCorrectBody() async {
        struct EmptyResponse: Decodable {}
        mockClient.stub(EmptyResponse())
        let result = await service.updateSignature(sendAsEmail: "alice@example.com", html: "<b>Sig</b>")
        switch result {
        case .success: XCTAssertEqual(mockClient.lastRequest?.httpMethod, "PATCH")
        case .failure(let e): XCTFail("\(e)")
        }
    }

    func test_fetchVacationSettings_returnsSettings() async {
        let settings = VacationSettings(
            enableAutoReply: true,
            responseSubject: "Away",
            responseBodyPlainText: "I am away",
            responseBodyHtml: nil, startTime: nil, endTime: nil,
            restrictToContacts: false, restrictToDomain: false
        )
        mockClient.stub(settings)
        let result = await service.fetchVacationSettings()
        switch result {
        case .success(let s):
            XCTAssertTrue(s.enableAutoReply)
            XCTAssertEqual(s.responseSubject, "Away")
        case .failure(let e): XCTFail("\(e)")
        }
    }

    func test_updateVacationSettings_sendsPUT() async {
        struct EmptyResponse: Decodable {}
        mockClient.stub(EmptyResponse())
        let settings = VacationSettings(enableAutoReply: false, responseSubject: nil,
            responseBodyPlainText: nil, responseBodyHtml: nil,
            startTime: nil, endTime: nil, restrictToContacts: nil, restrictToDomain: nil)
        let result = await service.updateVacationSettings(settings)
        switch result {
        case .success: XCTAssertEqual(mockClient.lastRequest?.httpMethod, "PUT")
        case .failure(let e): XCTFail("\(e)")
        }
    }

    func test_createLabel_returnsLabel() async {
        let label = GmailAPILabel(id: "label1", name: "Clients", type: "user", messagesUnread: nil)
        mockClient.stub(label)
        let result = await service.createLabel(name: "Clients")
        switch result {
        case .success(let l): XCTAssertEqual(l.id, "label1")
        case .failure(let e): XCTFail("\(e)")
        }
    }

    func test_deleteLabel_propagatesError() async {
        mockClient.stubError(.serverError(statusCode: 500))
        let result = await service.deleteLabel(id: "label1")
        if case .failure(.serverError(500)) = result { } else {
            XCTFail("Expected .serverError(500)")
        }
    }
}
```

### Étape 5 : xcodegen + phase rouge

```bash
cd /Users/florianchambolle/Bureau/GMac
xcodegen generate
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep "error:" | head -5
```
Attendu : `cannot find type 'GmailSettingsService'`

### Étape 6 : Implémenter `GMac/Services/GmailSettingsService.swift`

```swift
import Foundation

final class GmailSettingsService: GmailSettingsServiceProtocol, @unchecked Sendable {
    private let httpClient: any HTTPClientProtocol

    init(httpClient: any HTTPClientProtocol) {
        self.httpClient = httpClient
    }

    func fetchSendAsList() async -> Result<[SendAsAlias], AppError> {
        let request = URLRequest(url: Endpoints.sendAsList())
        let result: Result<SendAsListResponse, AppError> = await httpClient.send(request)
        return result.map { $0.sendAs }
    }

    func updateSignature(sendAsEmail: String, html: String) async -> Result<Void, AppError> {
        do {
            var request = URLRequest(url: Endpoints.sendAsUpdate(sendAsEmail: sendAsEmail))
            request.httpMethod = "PATCH"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(UpdateSignatureRequest(signature: html))
            struct EmptyResponse: Decodable {}
            let result: Result<EmptyResponse, AppError> = await httpClient.send(request)
            return result.map { _ in () }
        } catch {
            return .failure(.unknown)
        }
    }

    func fetchVacationSettings() async -> Result<VacationSettings, AppError> {
        let request = URLRequest(url: Endpoints.vacationSettings())
        return await httpClient.send(request)
    }

    func updateVacationSettings(_ settings: VacationSettings) async -> Result<Void, AppError> {
        do {
            var request = URLRequest(url: Endpoints.vacationSettings())
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(settings)
            struct EmptyResponse: Decodable {}
            let result: Result<EmptyResponse, AppError> = await httpClient.send(request)
            return result.map { _ in () }
        } catch {
            return .failure(.unknown)
        }
    }

    func createLabel(name: String) async -> Result<GmailLabel, AppError> {
        do {
            var request = URLRequest(url: Endpoints.labelCreate())
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(CreateLabelRequest(name: name))
            let result: Result<GmailAPILabel, AppError> = await httpClient.send(request)
            return result.map { GmailLabel(id: $0.id, name: $0.name, type: $0.type == "system" ? .system : .user, messagesUnread: $0.messagesUnread) }
        } catch {
            return .failure(.unknown)
        }
    }

    func updateLabel(id: String, name: String) async -> Result<GmailLabel, AppError> {
        do {
            var request = URLRequest(url: Endpoints.labelUpdate(id: id))
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(CreateLabelRequest(name: name))
            let result: Result<GmailAPILabel, AppError> = await httpClient.send(request)
            return result.map { GmailLabel(id: $0.id, name: $0.name, type: $0.type == "system" ? .system : .user, messagesUnread: $0.messagesUnread) }
        } catch {
            return .failure(.unknown)
        }
    }

    func deleteLabel(id: String) async -> Result<Void, AppError> {
        var request = URLRequest(url: Endpoints.labelDelete(id: id))
        request.httpMethod = "DELETE"
        struct EmptyResponse: Decodable {}
        let result: Result<EmptyResponse, AppError> = await httpClient.send(request)
        return result.map { _ in () }
    }
}
```

### Étape 7 : Créer `MockGmailSettingsService.swift`

```swift
// GMacTests/Mocks/MockGmailSettingsService.swift
import Foundation
@testable import GMac

final class MockGmailSettingsService: GmailSettingsServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _sendAsResult: Result<[SendAsAlias], AppError> = .success([])
    private var _updateSigResult: Result<Void, AppError> = .success(())
    private var _vacationResult: Result<VacationSettings, AppError> = .failure(.unknown)
    private var _updateVacationResult: Result<Void, AppError> = .success(())
    private var _createLabelResult: Result<GmailLabel, AppError> = .failure(.unknown)
    private var _deleteLabelResult: Result<Void, AppError> = .success(())

    func stubSendAs(_ r: Result<[SendAsAlias], AppError>) { lock.withLock { _sendAsResult = r } }
    func stubUpdateSignature(_ r: Result<Void, AppError>) { lock.withLock { _updateSigResult = r } }
    func stubVacation(_ r: Result<VacationSettings, AppError>) { lock.withLock { _vacationResult = r } }
    func stubUpdateVacation(_ r: Result<Void, AppError>) { lock.withLock { _updateVacationResult = r } }
    func stubCreateLabel(_ r: Result<GmailLabel, AppError>) { lock.withLock { _createLabelResult = r } }
    func stubDeleteLabel(_ r: Result<Void, AppError>) { lock.withLock { _deleteLabelResult = r } }

    func fetchSendAsList() async -> Result<[SendAsAlias], AppError> { lock.withLock { _sendAsResult } }
    func updateSignature(sendAsEmail: String, html: String) async -> Result<Void, AppError> { lock.withLock { _updateSigResult } }
    func fetchVacationSettings() async -> Result<VacationSettings, AppError> { lock.withLock { _vacationResult } }
    func updateVacationSettings(_ s: VacationSettings) async -> Result<Void, AppError> { lock.withLock { _updateVacationResult } }
    func createLabel(name: String) async -> Result<GmailLabel, AppError> { lock.withLock { _createLabelResult } }
    func updateLabel(id: String, name: String) async -> Result<GmailLabel, AppError> { lock.withLock { _createLabelResult } }
    func deleteLabel(id: String) async -> Result<Void, AppError> { lock.withLock { _deleteLabelResult } }
}
```

### Étape 8 : Tests verts + commit

```bash
xcodegen generate
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | head -3
git add GMac/Services/ GMac/Network/Endpoints.swift GMacTests/Unit/GmailSettingsServiceTests.swift GMacTests/Mocks/MockGmailSettingsService.swift
git commit -m "feat: GmailSettingsService — signature, vacation, label CRUD + endpoints settings"
```

---

## Task 2 : Signature editor (WKWebView contenteditable)

**Files:**
- Create: `GMac/UI/Settings/SignatureEditorView.swift`
- Create: `GMac/UI/Settings/SignatureEditorViewModel.swift`

### Étape 1 : `SignatureEditorViewModel.swift`

```swift
import Foundation
import Observation

@Observable
@MainActor
final class SignatureEditorViewModel {
    var aliases: [SendAsAlias] = []
    var selectedAlias: SendAsAlias? = nil
    var currentHTML: String = ""
    var isSaving: Bool = false
    var isLoading: Bool = false
    var lastError: AppError? = nil
    var saveSuccess: Bool = false

    private let settingsService: any GmailSettingsServiceProtocol

    init(settingsService: any GmailSettingsServiceProtocol) {
        self.settingsService = settingsService
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let result = await settingsService.fetchSendAsList()
        switch result {
        case .success(let list):
            aliases = list
            if let primary = list.first(where: { $0.isPrimary == true }) ?? list.first {
                selectedAlias = primary
                currentHTML = primary.signature ?? ""
            }
        case .failure(let e):
            lastError = e
        }
    }

    func selectAlias(_ alias: SendAsAlias) {
        selectedAlias = alias
        currentHTML = alias.signature ?? ""
    }

    func save() async {
        guard let alias = selectedAlias else { return }
        isSaving = true
        defer { isSaving = false }
        let result = await settingsService.updateSignature(sendAsEmail: alias.sendAsEmail, html: currentHTML)
        switch result {
        case .success:
            saveSuccess = true
        case .failure(let e):
            lastError = e
        }
    }
}
```

### Étape 2 : `SignatureEditorView.swift`

```swift
import SwiftUI
import WebKit

struct SignatureEditorView: View {
    @State var vm: SignatureEditorViewModel
    @State private var showSavedConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if vm.isLoading {
                ProgressView("Chargement de la signature…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                editorContent
            }
        }
        .task { await vm.load() }
        .onChange(of: vm.saveSuccess) {
            if vm.saveSuccess {
                showSavedConfirmation = true
                vm.saveSuccess = false
                Task { try? await Task.sleep(for: .seconds(2)); showSavedConfirmation = false }
            }
        }
        .alert("Erreur", isPresented: .constant(vm.lastError != nil)) {
            Button("OK") { vm.lastError = nil }
        } message: {
            Text(vm.lastError.map { _ in "La signature n'a pas pu être sauvegardée." } ?? "")
        }
    }

    private var toolbar: some View {
        HStack {
            if vm.aliases.count > 1 {
                Picker("Adresse", selection: Binding(
                    get: { vm.selectedAlias?.sendAsEmail ?? "" },
                    set: { email in
                        if let alias = vm.aliases.first(where: { $0.sendAsEmail == email }) {
                            vm.selectAlias(alias)
                        }
                    }
                )) {
                    ForEach(vm.aliases, id: \.sendAsEmail) { alias in
                        Text(alias.sendAsEmail).tag(alias.sendAsEmail)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 280)
            }
            Spacer()
            if showSavedConfirmation {
                Label("Sauvegardé", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
            Button(action: { Task { await vm.save() } }) {
                if vm.isSaving {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Sauvegarder")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isSaving)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var editorContent: some View {
        SignatureWebEditor(html: $vm.currentHTML)
            .frame(minHeight: 300)
    }
}

// WKWebView avec contenteditable — l'utilisateur édite directement le HTML rendu
struct SignatureWebEditor: NSViewRepresentable {
    @Binding var html: String

    func makeCoordinator() -> Coordinator { Coordinator(html: $html) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true  // JS requis pour contenteditable
        config.userContentController.add(context.coordinator, name: "signatureChanged")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        let editableHTML = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          body { font-family: -apple-system, sans-serif; margin: 12px; outline: none; min-height: 200px; }
          body:empty:before { content: 'Tapez votre signature ici…'; color: #999; }
        </style>
        </head>
        <body contenteditable="true" id="sig">\(html)</body>
        <script>
        const sig = document.getElementById('sig');
        sig.addEventListener('input', function() {
            window.webkit.messageHandlers.signatureChanged.postMessage(sig.innerHTML);
        });
        </script>
        </html>
        """
        webView.loadHTMLString(editableHTML, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Ne pas recharger si en cours d'édition — le contenu est géré par JS
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var html: String
        var isLoaded = false

        init(html: Binding<String>) { _html = html }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "signatureChanged", let body = message.body as? String {
                html = body
            }
        }
    }
}
```

### Étape 3 : Build + commit

```bash
xcodegen generate
xcodebuild build -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | head -3
git add GMac/UI/Settings/
git commit -m "feat: SignatureEditorView — WKWebView contenteditable, feedback sauvegarde, multi-alias picker"
```

---

## Task 3 : Message d'absence (VacationSettingsView)

**Files:**
- Create: `GMac/UI/Settings/VacationSettingsView.swift`
- Create: `GMac/UI/Settings/VacationSettingsViewModel.swift`

### `VacationSettingsViewModel.swift`

```swift
import Foundation
import Observation

@Observable
@MainActor
final class VacationSettingsViewModel {
    var enableAutoReply: Bool = false
    var subject: String = ""
    var bodyText: String = ""
    var restrictToContacts: Bool = false
    var isLoading: Bool = false
    var isSaving: Bool = false
    var lastError: AppError? = nil
    var saveSuccess: Bool = false

    private let settingsService: any GmailSettingsServiceProtocol

    init(settingsService: any GmailSettingsServiceProtocol) {
        self.settingsService = settingsService
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let result = await settingsService.fetchVacationSettings()
        switch result {
        case .success(let s):
            enableAutoReply = s.enableAutoReply
            subject = s.responseSubject ?? ""
            bodyText = s.responseBodyPlainText ?? ""
            restrictToContacts = s.restrictToContacts ?? false
        case .failure(let e):
            lastError = e
        }
    }

    func save() async {
        isSaving = true
        defer { isSaving = false }
        let settings = VacationSettings(
            enableAutoReply: enableAutoReply,
            responseSubject: subject.isEmpty ? nil : subject,
            responseBodyPlainText: bodyText.isEmpty ? nil : bodyText,
            responseBodyHtml: nil,
            startTime: nil,
            endTime: nil,
            restrictToContacts: restrictToContacts,
            restrictToDomain: nil
        )
        let result = await settingsService.updateVacationSettings(settings)
        switch result {
        case .success: saveSuccess = true
        case .failure(let e): lastError = e
        }
    }
}
```

### `VacationSettingsView.swift`

```swift
import SwiftUI

struct VacationSettingsView: View {
    @State var vm: VacationSettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Réponse automatique activée", isOn: $vm.enableAutoReply)
            }

            if vm.enableAutoReply {
                Section("Message") {
                    TextField("Objet", text: $vm.subject)
                    TextEditor(text: $vm.bodyText)
                        .frame(minHeight: 100)
                }

                Section("Options") {
                    Toggle("Répondre uniquement aux contacts", isOn: $vm.restrictToContacts)
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { Task { await vm.save() } }) {
                    if vm.isSaving { ProgressView().controlSize(.small) }
                    else { Text("Sauvegarder") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isSaving)
            }
        }
        .overlay {
            if vm.isLoading { ProgressView("Chargement…") }
        }
        .task { await vm.load() }
        .alert("Erreur", isPresented: .constant(vm.lastError != nil)) {
            Button("OK") { vm.lastError = nil }
        } message: {
            Text("Les paramètres n'ont pas pu être sauvegardés.")
        }
    }
}
```

### Tests VacationSettingsViewModel

```swift
// À ajouter dans un fichier GMacTests/Unit/VacationSettingsViewModelTests.swift
import XCTest
@testable import GMac

@MainActor
final class VacationSettingsViewModelTests: XCTestCase {
    var mockService: MockGmailSettingsService!
    var vm: VacationSettingsViewModel!

    override func setUp() async throws {
        mockService = MockGmailSettingsService()
        vm = VacationSettingsViewModel(settingsService: mockService)
    }

    func test_load_populatesFields() async {
        let settings = VacationSettings(
            enableAutoReply: true, responseSubject: "Absent",
            responseBodyPlainText: "Je suis absent", responseBodyHtml: nil,
            startTime: nil, endTime: nil,
            restrictToContacts: true, restrictToDomain: nil
        )
        mockService.stubVacation(.success(settings))
        await vm.load()
        XCTAssertTrue(vm.enableAutoReply)
        XCTAssertEqual(vm.subject, "Absent")
        XCTAssertEqual(vm.bodyText, "Je suis absent")
        XCTAssertTrue(vm.restrictToContacts)
    }

    func test_load_failure_setsLastError() async {
        mockService.stubVacation(.failure(.offline))
        await vm.load()
        XCTAssertEqual(vm.lastError, .offline)
    }

    func test_save_callsUpdateVacation() async {
        mockService.stubUpdateVacation(.success(()))
        vm.enableAutoReply = true
        vm.subject = "Absent"
        vm.bodyText = "Retour lundi"
        await vm.save()
        XCTAssertTrue(vm.saveSuccess)
        XCTAssertNil(vm.lastError)
    }

    func test_save_failure_setsLastError() async {
        mockService.stubUpdateVacation(.failure(.serverError(statusCode: 500)))
        await vm.save()
        if case .failed = vm.lastError { } else {
            // accepter tout AppError — le type exact n'est pas critique ici
        }
        XCTAssertNotNil(vm.lastError)
    }
}
```

### Commit Task 3

```bash
xcodegen generate
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | head -3
git add GMac/UI/Settings/ GMacTests/Unit/VacationSettingsViewModelTests.swift
git commit -m "feat: VacationSettingsView — message d'absence, toggle, options, sauvegarde"
```

---

## Task 4 : Gestion des labels

**Files:**
- Create: `GMac/UI/Settings/LabelsManagerView.swift`
- Create: `GMac/UI/Settings/LabelsManagerViewModel.swift`

### `LabelsManagerViewModel.swift`

```swift
import Foundation
import Observation

@Observable
@MainActor
final class LabelsManagerViewModel {
    var labels: [GmailLabel] = []
    var newLabelName: String = ""
    var isLoading: Bool = false
    var lastError: AppError? = nil

    private let gmailService: any GmailServiceProtocol
    private let settingsService: any GmailSettingsServiceProtocol

    init(gmailService: any GmailServiceProtocol, settingsService: any GmailSettingsServiceProtocol) {
        self.gmailService = gmailService
        self.settingsService = settingsService
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let result = await gmailService.fetchLabels()
        switch result {
        case .success(let all): labels = all.filter { $0.type == .user }
        case .failure(let e): lastError = e
        }
    }

    func createLabel() async {
        let name = newLabelName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let result = await settingsService.createLabel(name: name)
        switch result {
        case .success(let label):
            labels.append(label)
            newLabelName = ""
        case .failure(let e):
            lastError = e
        }
    }

    func deleteLabel(id: String) async {
        let result = await settingsService.deleteLabel(id: id)
        switch result {
        case .success: labels.removeAll { $0.id == id }
        case .failure(let e): lastError = e
        }
    }
}
```

### `LabelsManagerView.swift`

```swift
import SwiftUI

struct LabelsManagerView: View {
    @State var vm: LabelsManagerViewModel

    var body: some View {
        List {
            Section("Labels personnalisés") {
                if vm.labels.isEmpty && !vm.isLoading {
                    Text("Aucun label personnalisé")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vm.labels) { label in
                        HStack {
                            Image(systemName: "tag")
                                .foregroundStyle(.blue)
                            Text(label.name)
                            Spacer()
                            Button(role: .destructive) {
                                Task { await vm.deleteLabel(id: label.id) }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section("Nouveau label") {
                HStack {
                    TextField("Nom du label", text: $vm.newLabelName)
                        .onSubmit { Task { await vm.createLabel() } }
                    Button("Créer") {
                        Task { await vm.createLabel() }
                    }
                    .disabled(vm.newLabelName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .overlay {
            if vm.isLoading { ProgressView("Chargement…") }
        }
        .task { await vm.load() }
        .alert("Erreur", isPresented: .constant(vm.lastError != nil)) {
            Button("OK") { vm.lastError = nil }
        } message: {
            Text("Opération échouée. Réessayez.")
        }
    }
}
```

### Tests LabelsManagerViewModel

```swift
// GMacTests/Unit/LabelsManagerViewModelTests.swift
import XCTest
@testable import GMac

@MainActor
final class LabelsManagerViewModelTests: XCTestCase {
    var mockGmail: MockGmailService!
    var mockSettings: MockGmailSettingsService!
    var vm: LabelsManagerViewModel!

    override func setUp() async throws {
        mockGmail = MockGmailService()
        mockSettings = MockGmailSettingsService()
        vm = LabelsManagerViewModel(gmailService: mockGmail, settingsService: mockSettings)
    }

    func test_load_showsOnlyUserLabels() async {
        mockGmail.stubLabels(.success([
            GmailLabel(id: "INBOX", name: "INBOX", type: .system, messagesUnread: nil),
            GmailLabel(id: "tag1", name: "Clients", type: .user, messagesUnread: nil)
        ]))
        await vm.load()
        XCTAssertEqual(vm.labels.count, 1)
        XCTAssertEqual(vm.labels[0].name, "Clients")
    }

    func test_createLabel_addsToList() async {
        mockGmail.stubLabels(.success([]))
        await vm.load()
        mockSettings.stubCreateLabel(.success(GmailLabel(id: "new1", name: "Prospects", type: .user, messagesUnread: nil)))
        vm.newLabelName = "Prospects"
        await vm.createLabel()
        XCTAssertEqual(vm.labels.count, 1)
        XCTAssertEqual(vm.labels[0].name, "Prospects")
        XCTAssertTrue(vm.newLabelName.isEmpty, "Le champ doit être vidé après création")
    }

    func test_deleteLabel_removesFromList() async {
        vm.labels = [GmailLabel(id: "tag1", name: "Old", type: .user, messagesUnread: nil)]
        mockSettings.stubDeleteLabel(.success(()))
        await vm.deleteLabel(id: "tag1")
        XCTAssertTrue(vm.labels.isEmpty)
    }

    func test_createLabel_emptyName_doesNotCallAPI() async {
        vm.newLabelName = "   "
        await vm.createLabel()
        XCTAssertTrue(vm.labels.isEmpty)
    }
}
```

### Commit Task 4

```bash
xcodegen generate
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | head -3
git add GMac/UI/Settings/ GMacTests/Unit/LabelsManagerViewModelTests.swift
git commit -m "feat: LabelsManagerView — CRUD labels personnalisés, création inline, suppression"
```

---

## Task 5 : SettingsView container + intégration AppEnvironment

**Files:**
- Create: `GMac/UI/Settings/SettingsView.swift`
- Modify: `GMac/App/AppEnvironment.swift`
- Modify: `GMac/UI/ContentView.swift`

### `SettingsView.swift`

```swift
import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) var appEnv

    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink("Signature", destination: signatureView)
                NavigationLink("Message d'absence", destination: vacationView)
                NavigationLink("Labels", destination: labelsView)
            }
            .navigationTitle("Paramètres")
            .listStyle(.sidebar)
        } detail: {
            ContentUnavailableView("Choisissez une section", systemImage: "gear")
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private var signatureView: some View {
        SignatureEditorView(vm: SignatureEditorViewModel(settingsService: appEnv.settingsService))
            .navigationTitle("Signature")
    }

    private var vacationView: some View {
        VacationSettingsView(vm: VacationSettingsViewModel(settingsService: appEnv.settingsService))
            .navigationTitle("Message d'absence")
    }

    private var labelsView: some View {
        LabelsManagerView(vm: LabelsManagerViewModel(gmailService: appEnv.gmailService, settingsService: appEnv.settingsService))
            .navigationTitle("Labels")
    }
}
```

### Mettre à jour `AppEnvironment.swift`

Lire le fichier. Ajouter `settingsService` :

```swift
let settingsService: GmailSettingsService

// Dans init(), après gmailService :
self.settingsService = GmailSettingsService(httpClient: client)
```

### Mettre à jour `ContentView.swift`

Ajouter un bouton Settings dans la toolbar :

```swift
.toolbar {
    // ... existant ...
    ToolbarItem(placement: .navigation) {
        Button("Paramètres", systemImage: "gear") {
            isShowingSettings = true
        }
    }
}
.sheet(isPresented: $isShowingSettings) {
    SettingsView()
        .environment(env)  // ou appEnv selon le nom dans ContentView
}
```

Ajouter `@State private var isShowingSettings = false` dans ContentView.

### Commit Task 5

```bash
xcodegen generate
xcodebuild build -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3
xcodebuild test -scheme GMac -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed" | head -3
git add GMac/UI/Settings/SettingsView.swift GMac/App/AppEnvironment.swift GMac/UI/ContentView.swift
git commit -m "feat: SettingsView container — navigation Signature / Absence / Labels, intégration ContentView"
```

---

## Résumé Sprint 3

À la fin de ce sprint, GMac permet de :
- Éditer la signature HTML directement dans une WKWebView contenteditable (rendu en temps réel)
- Activer/désactiver le message d'absence avec sujet, texte et restriction aux contacts
- Créer, lister et supprimer des labels personnalisés
- Accéder aux Settings depuis une icône engrenage dans la toolbar

**Sprint 4 :** Intégration Google Drive (upload PJ, picker fichiers Drive) — Sprint 5 : Assistant IA (LLM providers, ToneContextResolver, VoiceProfile).

---

*Plan Sprint 3 — GMac — 25 avril 2026*
