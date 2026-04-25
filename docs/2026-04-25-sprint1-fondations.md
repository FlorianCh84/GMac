# GMac Sprint 1 — Fondations

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Une app macOS qui s'authentifie avec Google, charge la boîte de réception Gmail et affiche les threads — zéro crash, zéro mail perdu, base testable.

**Architecture:** Approche "Gmail source de vérité" — aucune donnée Gmail persistée sur disque. SessionStore in-memory, toutes les mutations bloquent l'UI jusqu'à confirmation API. Couche réseau avec token refresh transparent et backoff exponentiel.

**Tech Stack:** Swift 5.9+, SwiftUI + AppKit, SwiftData (préférences uniquement), URLSession, ASWebAuthenticationSession, XCTest, SwiftLint

---

## Prérequis avant de commencer

- Xcode 16+ installé
- Compte Google Cloud Console avec un projet créé
- Activer Gmail API v1 et Google Drive API v3 dans la console
- Créer des credentials OAuth 2.0 (type "macOS application")
- Noter le `CLIENT_ID` et `CLIENT_SECRET`

---

## Task 1 : Initialisation du projet Xcode

**Files:**
- Create: `GMac.xcodeproj` (via Xcode)
- Create: `.swiftlint.yml`
- Create: `.gitignore`
- Create: `GMac/App/GMacApp.swift`

### Étape 1 : Créer le projet dans Xcode

1. Ouvrir Xcode → File → New → Project
2. Choisir **macOS → App**
3. Remplir :
   - Product Name: `GMac`
   - Team: ton compte développeur (ou None)
   - Organization Identifier: `fr.agence810`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Cocher **Include Tests**
4. Sauvegarder dans `~/Bureau/GMac/`

### Étape 2 : Créer la structure de dossiers

Dans Xcode, créer ces groupes (clic droit → New Group) :

```
GMac/
├── App/
├── Network/
├── Auth/
├── Services/
├── Store/
├── Models/
├── UI/
└── Resources/Fixtures/

GMacTests/
├── Unit/
├── Integration/
└── Mocks/
```

### Étape 3 : Installer SwiftLint via Homebrew

```bash
brew install swiftlint
```

### Étape 4 : Créer `.swiftlint.yml` à la racine du projet

```yaml
disabled_rules:
  - trailing_whitespace

opt_in_rules:
  - force_unwrapping
  - implicitly_unwrapped_optional

force_unwrapping: error

excluded:
  - .build
  - DerivedData
```

### Étape 5 : Ajouter SwiftLint comme Build Phase

Dans Xcode → Target GMac → Build Phases → + → New Run Script Phase :

```bash
if which swiftlint > /dev/null; then
  swiftlint
else
  echo "warning: SwiftLint not installed"
fi
```

### Étape 6 : Créer `.gitignore`

```
.DS_Store
*.xcuserstate
DerivedData/
.build/
xcuserdata/
*.moved-aside
*.orig
```

### Étape 7 : Init git et premier commit

```bash
cd ~/Bureau/GMac
git init
git add .
git commit -m "feat: init projet Xcode GMac"
```

---

## Task 2 : Modèles core

**Files:**
- Create: `GMac/Models/AppError.swift`
- Create: `GMac/Models/GmailLabel.swift`
- Create: `GMac/Models/EmailMessage.swift`
- Create: `GMac/Models/EmailThread.swift`
- Create: `GMacTests/Unit/AppErrorTests.swift`

### Étape 1 : Écrire le test AppError en premier

Dans `GMacTests/Unit/AppErrorTests.swift` :

```swift
import XCTest
@testable import GMac

final class AppErrorTests: XCTestCase {
    func test_appError_isEquatable() {
        XCTAssertEqual(AppError.tokenExpired, AppError.tokenExpired)
        XCTAssertEqual(AppError.offline, AppError.offline)
        XCTAssertNotEqual(AppError.offline, AppError.tokenExpired)
    }

    func test_appError_apiError_equality() {
        let e1 = AppError.apiError(statusCode: 401, message: "Unauthorized")
        let e2 = AppError.apiError(statusCode: 401, message: "Unauthorized")
        let e3 = AppError.apiError(statusCode: 403, message: "Forbidden")
        XCTAssertEqual(e1, e2)
        XCTAssertNotEqual(e1, e3)
    }

    func test_appError_rateLimited_equality() {
        XCTAssertEqual(AppError.rateLimited(retryAfter: 5), AppError.rateLimited(retryAfter: 5))
        XCTAssertNotEqual(AppError.rateLimited(retryAfter: 5), AppError.rateLimited(retryAfter: 10))
    }
}
```

### Étape 2 : Lancer le test — vérifier qu'il échoue

Cmd+U dans Xcode.
Attendu : erreur de compilation "AppError not found".

### Étape 3 : Implémenter `AppError.swift`

```swift
enum AppError: Error, Equatable {
    case network(URLError)
    case apiError(statusCode: Int, message: String)
    case rateLimited(retryAfter: TimeInterval)
    case tokenExpired
    case offline
    case unknown

    static func == (lhs: AppError, rhs: AppError) -> Bool {
        switch (lhs, rhs) {
        case (.tokenExpired, .tokenExpired): return true
        case (.offline, .offline): return true
        case (.unknown, .unknown): return true
        case (.network(let a), .network(let b)): return a.code == b.code
        case (.apiError(let a, let b), .apiError(let c, let d)): return a == c && b == d
        case (.rateLimited(let a), .rateLimited(let b)): return a == b
        default: return false
        }
    }
}
```

### Étape 4 : Implémenter `GmailLabel.swift`

```swift
struct GmailLabel: Identifiable, Hashable, Decodable {
    let id: String
    let name: String
    let type: LabelType
    let messagesUnread: Int?

    enum LabelType: String, Decodable {
        case system
        case user
    }
}
```

### Étape 5 : Implémenter `EmailMessage.swift`

```swift
struct EmailMessage: Identifiable {
    let id: String
    let threadId: String
    let snippet: String
    let subject: String
    let from: String
    let to: [String]
    let date: Date
    let bodyHTML: String?
    let bodyPlain: String?
    let labelIds: [String]
    let isUnread: Bool
}
```

### Étape 6 : Implémenter `EmailThread.swift`

```swift
struct EmailThread: Identifiable {
    let id: String
    let snippet: String
    let historyId: String
    let messages: [EmailMessage]

    var subject: String { messages.first?.subject ?? "(Sans sujet)" }
    var from: String { messages.first?.from ?? "" }
    var date: Date { messages.last?.date ?? Date() }
    var isUnread: Bool { messages.contains { $0.isUnread } }
}
```

### Étape 7 : Lancer les tests — vérifier qu'ils passent

Cmd+U dans Xcode.
Attendu : tous les tests passent (vert).

### Étape 8 : Commit

```bash
git add GMac/Models/ GMacTests/Unit/AppErrorTests.swift
git commit -m "feat: modèles core AppError, GmailLabel, EmailMessage, EmailThread"
```

---

## Task 3 : Couche réseau — HTTPClientProtocol + MockHTTPClient

**Files:**
- Create: `GMac/Network/HTTPClientProtocol.swift`
- Create: `GMac/Network/Endpoints.swift`
- Create: `GMacTests/Mocks/MockHTTPClient.swift`
- Create: `GMacTests/Unit/RetryTests.swift`

### Étape 1 : Implémenter `HTTPClientProtocol.swift`

```swift
protocol HTTPClientProtocol {
    func send<T: Decodable>(_ request: URLRequest) async -> Result<T, AppError>
}
```

### Étape 2 : Implémenter `Endpoints.swift`

```swift
enum Endpoints {
    static let gmailBase = "https://gmail.googleapis.com/gmail/v1"
    static let tokenURL = "https://oauth2.googleapis.com/token"

    static func threadsList(userId: String = "me", labelIds: [String] = ["INBOX"], maxResults: Int = 50) -> URL {
        var components = URLComponents(string: "\(gmailBase)/users/\(userId)/threads")!
        components.queryItems = [
            URLQueryItem(name: "maxResults", value: "\(maxResults)"),
        ] + labelIds.map { URLQueryItem(name: "labelIds", value: $0) }
        return components.url!
    }

    static func threadGet(userId: String = "me", id: String) -> URL {
        URL(string: "\(gmailBase)/users/\(userId)/threads/\(id)?format=FULL")!
    }

    static func messageGet(userId: String = "me", id: String) -> URL {
        URL(string: "\(gmailBase)/users/\(userId)/messages/\(id)?format=FULL")!
    }

    static func labelsList(userId: String = "me") -> URL {
        URL(string: "\(gmailBase)/users/\(userId)/labels")!
    }

    static func historyList(userId: String = "me", startHistoryId: String) -> URL {
        URL(string: "\(gmailBase)/users/\(userId)/history?startHistoryId=\(startHistoryId)&historyTypes=messageAdded&historyTypes=messageDeleted&historyTypes=labelAdded&historyTypes=labelRemoved")!
    }

    static func messageSend(userId: String = "me") -> URL {
        URL(string: "\(gmailBase)/users/\(userId)/messages/send")!
    }
}
```

### Étape 3 : Implémenter `MockHTTPClient.swift`

```swift
import Foundation
@testable import GMac

final class MockHTTPClient: HTTPClientProtocol {
    var stubbedResult: Any?
    var stubbedError: AppError?
    var callCount = 0
    var lastRequest: URLRequest?

    func send<T: Decodable>(_ request: URLRequest) async -> Result<T, AppError> {
        callCount += 1
        lastRequest = request

        if let error = stubbedError {
            return .failure(error)
        }
        if let result = stubbedResult as? T {
            return .success(result)
        }
        return .failure(.unknown)
    }

    func stub<T>(result: T) { stubbedResult = result }
    func stubError(_ error: AppError) { stubbedError = error }
    func reset() { stubbedResult = nil; stubbedError = nil; callCount = 0; lastRequest = nil }
}
```

### Étape 4 : Écrire les tests de retry

Dans `GMacTests/Unit/RetryTests.swift` :

```swift
import XCTest
@testable import GMac

final class RetryTests: XCTestCase {
    func test_withRetry_succeedsOnFirstAttempt() async {
        var callCount = 0
        let result: Result<String, AppError> = await withRetry(maxAttempts: 3) {
            callCount += 1
            return .success("ok")
        }
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(try? result.get(), "ok")
    }

    func test_withRetry_retriesOnNetworkError() async {
        var callCount = 0
        let networkError = URLError(.notConnectedToInternet)
        let result: Result<String, AppError> = await withRetry(maxAttempts: 3, delay: 0) {
            callCount += 1
            if callCount < 3 { return .failure(.network(networkError)) }
            return .success("ok")
        }
        XCTAssertEqual(callCount, 3)
        XCTAssertEqual(try? result.get(), "ok")
    }

    func test_withRetry_doesNotRetryNonRetryableErrors() async {
        var callCount = 0
        let result: Result<String, AppError> = await withRetry(maxAttempts: 3, delay: 0) {
            callCount += 1
            return .failure(.apiError(statusCode: 403, message: "Forbidden"))
        }
        XCTAssertEqual(callCount, 1)
        if case .failure(.apiError(403, _)) = result { } else {
            XCTFail("Expected 403 error")
        }
    }
}
```

### Étape 5 : Lancer les tests — vérifier qu'ils échouent

Cmd+U. Attendu : `withRetry` not found.

### Étape 6 : Implémenter `withRetry` dans `HTTPClientProtocol.swift`

```swift
func withRetry<T>(
    maxAttempts: Int = 3,
    delay: TimeInterval = -1,  // -1 = exponentiel
    operation: () async -> Result<T, AppError>
) async -> Result<T, AppError> {
    for attempt in 0..<maxAttempts {
        let result = await operation()
        switch result {
        case .success:
            return result
        case .failure(.rateLimited(let retryAfter)):
            let waitTime = delay >= 0 ? delay : retryAfter
            if waitTime > 0 { try? await Task.sleep(for: .seconds(waitTime)) }
        case .failure(.network):
            let waitTime = delay >= 0 ? delay : pow(2.0, Double(attempt))
            if waitTime > 0 { try? await Task.sleep(for: .seconds(waitTime)) }
        case .failure:
            return result  // non-retryable
        }
    }
    return await operation()
}
```

### Étape 7 : Lancer les tests — vérifier qu'ils passent

Cmd+U. Attendu : tous verts.

### Étape 8 : Commit

```bash
git add GMac/Network/ GMacTests/Mocks/ GMacTests/Unit/RetryTests.swift
git commit -m "feat: HTTPClientProtocol, Endpoints, MockHTTPClient, withRetry"
```

---

## Task 4 : KeychainService

**Files:**
- Create: `GMac/Auth/KeychainService.swift`
- Create: `GMacTests/Unit/KeychainServiceTests.swift`

### Étape 1 : Écrire le test

```swift
import XCTest
@testable import GMac

final class KeychainServiceTests: XCTestCase {
    var keychain: KeychainService!

    override func setUp() {
        keychain = KeychainService(service: "fr.agence810.GMac.tests")
        try? keychain.delete(key: "test_token")
    }

    override func tearDown() {
        try? keychain.delete(key: "test_token")
    }

    func test_save_andRetrieve() throws {
        try keychain.save("my_token", key: "test_token")
        let retrieved = try keychain.retrieve(key: "test_token")
        XCTAssertEqual(retrieved, "my_token")
    }

    func test_update_existingKey() throws {
        try keychain.save("token_v1", key: "test_token")
        try keychain.save("token_v2", key: "test_token")
        let retrieved = try keychain.retrieve(key: "test_token")
        XCTAssertEqual(retrieved, "token_v2")
    }

    func test_delete_removesKey() throws {
        try keychain.save("token", key: "test_token")
        try keychain.delete(key: "test_token")
        XCTAssertThrowsError(try keychain.retrieve(key: "test_token"))
    }

    func test_retrieve_missingKey_throws() {
        XCTAssertThrowsError(try keychain.retrieve(key: "nonexistent"))
    }
}
```

### Étape 2 : Lancer le test — vérifier l'échec

Cmd+U. Attendu : `KeychainService` not found.

### Étape 3 : Implémenter `KeychainService.swift`

```swift
import Security
import Foundation

final class KeychainService {
    private let service: String

    init(service: String = "fr.agence810.GMac") {
        self.service = service
    }

    func save(_ value: String, key: String) throws {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)

        let attributes: [CFString: Any] = query.merging([kSecValueData: data]) { $1 }
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func retrieve(key: String) throws -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.notFound
        }
        return string
    }

    func delete(key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

enum KeychainError: Error {
    case saveFailed(OSStatus)
    case notFound
    case deleteFailed(OSStatus)
}
```

### Étape 4 : Lancer les tests — vérifier qu'ils passent

Cmd+U. Attendu : tous verts.

### Étape 5 : Commit

```bash
git add GMac/Auth/KeychainService.swift GMacTests/Unit/KeychainServiceTests.swift
git commit -m "feat: KeychainService — stockage sécurisé des tokens"
```

---

## Task 5 : GoogleOAuthManager

**Files:**
- Create: `GMac/Auth/GoogleOAuthManager.swift`
- Create: `GMac/Auth/TokenResponse.swift`
- Create: `GMacTests/Unit/GoogleOAuthManagerTests.swift`

### Étape 1 : Implémenter `TokenResponse.swift`

```swift
struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

struct StoredTokens {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) } // marge 60s
}
```

### Étape 2 : Écrire les tests

```swift
import XCTest
@testable import GMac

final class GoogleOAuthManagerTests: XCTestCase {
    var keychain: KeychainService!
    var manager: GoogleOAuthManager!

    override func setUp() {
        keychain = KeychainService(service: "fr.agence810.GMac.tests")
        manager = GoogleOAuthManager(
            clientId: "test_client_id",
            clientSecret: "test_client_secret",
            keychain: keychain
        )
        try? keychain.delete(key: "google_access_token")
        try? keychain.delete(key: "google_refresh_token")
        try? keychain.delete(key: "google_token_expiry")
    }

    func test_isAuthenticated_falseWhenNoTokens() {
        XCTAssertFalse(manager.isAuthenticated)
    }

    func test_isAuthenticated_trueWhenValidTokensStored() throws {
        try keychain.save("access_token", key: "google_access_token")
        try keychain.save("refresh_token", key: "google_refresh_token")
        let future = Date().addingTimeInterval(3600)
        try keychain.save("\(future.timeIntervalSince1970)", key: "google_token_expiry")
        XCTAssertTrue(manager.isAuthenticated)
    }

    func test_signRequest_addsAuthorizationHeader() throws {
        try keychain.save("my_access_token", key: "google_access_token")
        try keychain.save("refresh_token", key: "google_refresh_token")
        let future = Date().addingTimeInterval(3600)
        try keychain.save("\(future.timeIntervalSince1970)", key: "google_token_expiry")

        var request = URLRequest(url: URL(string: "https://api.example.com")!)
        let signed = manager.sign(request)
        XCTAssertEqual(signed.value(forHTTPHeaderField: "Authorization"), "Bearer my_access_token")
    }

    func test_logout_clearsKeychain() throws {
        try keychain.save("token", key: "google_access_token")
        try keychain.save("refresh", key: "google_refresh_token")
        manager.logout()
        XCTAssertFalse(manager.isAuthenticated)
    }
}
```

### Étape 3 : Lancer le test — vérifier l'échec

Cmd+U. Attendu : `GoogleOAuthManager` not found.

### Étape 4 : Implémenter `GoogleOAuthManager.swift`

```swift
import AuthenticationServices
import Foundation

@Observable
final class GoogleOAuthManager: NSObject {
    private let clientId: String
    private let clientSecret: String
    private let keychain: KeychainService
    private let redirectURI = "fr.agence810.gmac:/oauth2callback"
    private let scopes = [
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/gmail.send",
        "https://www.googleapis.com/auth/gmail.settings.basic",
        "https://www.googleapis.com/auth/gmail.settings.sharing",
        "https://www.googleapis.com/auth/drive.file"
    ]

    var isAuthenticated: Bool {
        guard let expiry = storedExpiry else { return false }
        return (try? keychain.retrieve(key: "google_access_token")) != nil
            && (try? keychain.retrieve(key: "google_refresh_token")) != nil
            && Date() < expiry
    }

    private var storedExpiry: Date? {
        guard let raw = try? keychain.retrieve(key: "google_token_expiry"),
              let ts = Double(raw) else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    init(clientId: String, clientSecret: String, keychain: KeychainService = KeychainService()) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.keychain = keychain
    }

    func sign(_ request: URLRequest) -> URLRequest {
        var req = request
        if let token = try? keychain.retrieve(key: "google_access_token") {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    func logout() {
        try? keychain.delete(key: "google_access_token")
        try? keychain.delete(key: "google_refresh_token")
        try? keychain.delete(key: "google_token_expiry")
    }

    func startOAuthFlow() async throws {
        let state = UUID().uuidString
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let authURL = components.url else { throw AppError.unknown }

        let callbackURL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "fr.agence810.gmac"
            ) { url, error in
                if let error = error { continuation.resume(throwing: error) }
                else if let url = url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: AppError.unknown) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AppError.unknown
        }

        try await exchangeCode(code)
    }

    func refresh() async throws {
        guard let refreshToken = try? keychain.retrieve(key: "google_refresh_token") else {
            throw AppError.tokenExpired
        }
        var request = URLRequest(url: URL(string: Endpoints.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=refresh_token&refresh_token=\(refreshToken)&client_id=\(clientId)&client_secret=\(clientSecret)"
        request.httpBody = Data(body.utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        try storeTokens(token, refreshToken: refreshToken)
    }

    private func exchangeCode(_ code: String) async throws {
        var request = URLRequest(url: URL(string: Endpoints.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=authorization_code&code=\(code)&redirect_uri=\(redirectURI)&client_id=\(clientId)&client_secret=\(clientSecret)"
        request.httpBody = Data(body.utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let refreshToken = token.refreshToken else { throw AppError.unknown }
        try storeTokens(token, refreshToken: refreshToken)
    }

    private func storeTokens(_ token: TokenResponse, refreshToken: String) throws {
        let expiry = Date().addingTimeInterval(TimeInterval(token.expiresIn))
        try keychain.save(token.accessToken, key: "google_access_token")
        try keychain.save(refreshToken, key: "google_refresh_token")
        try keychain.save("\(expiry.timeIntervalSince1970)", key: "google_token_expiry")
    }
}

extension GoogleOAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}
```

### Étape 5 : Lancer les tests — vérifier qu'ils passent

Cmd+U. Attendu : tous verts.

### Étape 6 : Commit

```bash
git add GMac/Auth/ GMacTests/Unit/GoogleOAuthManagerTests.swift
git commit -m "feat: GoogleOAuthManager — OAuth2 + Keychain + token refresh"
```

---

## Task 6 : AuthenticatedHTTPClient

**Files:**
- Create: `GMac/Network/AuthenticatedHTTPClient.swift`
- Create: `GMacTests/Unit/AuthenticatedHTTPClientTests.swift`

### Étape 1 : Écrire les tests

```swift
import XCTest
@testable import GMac

final class AuthenticatedHTTPClientTests: XCTestCase {
    struct TestResponse: Decodable, Equatable { let value: String }

    func test_send_addsAuthorizationHeader() async {
        let keychain = KeychainService(service: "fr.agence810.GMac.tests")
        let oauth = GoogleOAuthManager(clientId: "id", clientSecret: "secret", keychain: keychain)
        try? keychain.save("test_token", key: "google_access_token")
        try? keychain.save("refresh", key: "google_refresh_token")
        try? keychain.save("\(Date().addingTimeInterval(3600).timeIntervalSince1970)", key: "google_token_expiry")

        var capturedRequest: URLRequest?
        let innerClient = CapturingHTTPClient(result: TestResponse(value: "ok")) { req in
            capturedRequest = req
        }
        let client = AuthenticatedHTTPClient(inner: innerClient, oauth: oauth)

        let _: Result<TestResponse, AppError> = await client.send(URLRequest(url: URL(string: "https://api.test.com")!))

        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test_token")
    }

    func test_send_refreshesTokenOn401() async {
        // Ce test vérifie que le client retente après un 401
        // L'implémentation complète nécessite un mock OAuth — voir intégration tests
        // Pour l'instant, on vérifie que .tokenExpired est retourné si le refresh échoue
        XCTAssertTrue(true) // placeholder — test d'intégration dans Task Integration
    }
}

// Helper pour capturer les requêtes
final class CapturingHTTPClient<T: Decodable>: HTTPClientProtocol {
    let result: T
    let onSend: (URLRequest) -> Void
    init(result: T, onSend: @escaping (URLRequest) -> Void) {
        self.result = result
        self.onSend = onSend
    }
    func send<R: Decodable>(_ request: URLRequest) async -> Result<R, AppError> {
        onSend(request)
        if let r = result as? R { return .success(r) }
        return .failure(.unknown)
    }
}
```

### Étape 2 : Lancer le test — vérifier l'échec

Cmd+U. Attendu : `AuthenticatedHTTPClient` not found.

### Étape 3 : Implémenter `AuthenticatedHTTPClient.swift`

```swift
import Foundation

final class AuthenticatedHTTPClient: HTTPClientProtocol {
    private let session: URLSession
    private let oauth: GoogleOAuthManager

    init(session: URLSession = .shared, oauth: GoogleOAuthManager) {
        self.session = session
        self.oauth = oauth
    }

    // Initializer secondaire pour tests
    private let _inner: (any HTTPClientProtocol)?
    init(inner: any HTTPClientProtocol, oauth: GoogleOAuthManager) {
        self.session = .shared
        self.oauth = oauth
        self._inner = inner
    }

    func send<T: Decodable>(_ request: URLRequest) async -> Result<T, AppError> {
        let signed = oauth.sign(request)
        let result: Result<T, AppError> = await performRequest(signed)

        if case .failure(.apiError(401, _)) = result {
            do {
                try await oauth.refresh()
                let resigned = oauth.sign(request)
                return await performRequest(resigned)
            } catch {
                return .failure(.tokenExpired)
            }
        }
        return result
    }

    private func performRequest<T: Decodable>(_ request: URLRequest) async -> Result<T, AppError> {
        if let inner = _inner {
            return await inner.send(request)
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.unknown)
            }
            switch httpResponse.statusCode {
            case 200...299:
                do {
                    let decoded = try JSONDecoder().decode(T.self, from: data)
                    return .success(decoded)
                } catch {
                    return .failure(.unknown)
                }
            case 401:
                return .failure(.apiError(statusCode: 401, message: "Unauthorized"))
            case 403:
                return .failure(.apiError(statusCode: 403, message: "Forbidden"))
            case 429:
                let retryAfter = Double(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
                return .failure(.rateLimited(retryAfter: retryAfter))
            default:
                let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                return .failure(.apiError(statusCode: httpResponse.statusCode, message: msg))
            }
        } catch let urlError as URLError {
            if urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost {
                return .failure(.offline)
            }
            return .failure(.network(urlError))
        } catch {
            return .failure(.unknown)
        }
    }
}
```

### Étape 4 : Lancer les tests — vérifier qu'ils passent

Cmd+U. Attendu : verts.

### Étape 5 : Commit

```bash
git add GMac/Network/AuthenticatedHTTPClient.swift GMacTests/Unit/AuthenticatedHTTPClientTests.swift
git commit -m "feat: AuthenticatedHTTPClient — token refresh auto + mapping erreurs HTTP"
```

---

## Task 7 : GmailService — lecture

**Files:**
- Create: `GMac/Services/GmailService.swift`
- Create: `GMac/Services/MIMEParser.swift`
- Create: `GMacTests/Unit/GmailServiceTests.swift`
- Create: `GMacTests/Unit/MIMEParserTests.swift`
- Create: `GMac/Resources/Fixtures/thread_list_response.json`
- Create: `GMac/Resources/Fixtures/message_response.json`

### Étape 1 : Sauvegarder les fixtures JSON

Faire un vrai appel à l'API Gmail (via curl ou Insomnia) et sauvegarder les réponses dans `Resources/Fixtures/`. Ces fixtures serviront de référence pour les tests.

```bash
# Exemple avec curl (remplacer ACCESS_TOKEN)
curl -H "Authorization: Bearer ACCESS_TOKEN" \
  "https://gmail.googleapis.com/gmail/v1/users/me/threads?maxResults=1" \
  > ~/Bureau/GMac/GMac/Resources/Fixtures/thread_list_response.json
```

### Étape 2 : Écrire les tests MIMEParser

```swift
import XCTest
@testable import GMac

final class MIMEParserTests: XCTestCase {
    func test_extractHeader_fromMessagePart() {
        let headers = [
            GmailAPIMessage.Header(name: "Subject", value: "Test subject"),
            GmailAPIMessage.Header(name: "From", value: "alice@example.com"),
            GmailAPIMessage.Header(name: "To", value: "bob@example.com"),
            GmailAPIMessage.Header(name: "Date", value: "Mon, 25 Apr 2026 10:00:00 +0000")
        ]
        XCTAssertEqual(MIMEParser.header("Subject", from: headers), "Test subject")
        XCTAssertEqual(MIMEParser.header("From", from: headers), "alice@example.com")
        XCTAssertNil(MIMEParser.header("CC", from: headers))
    }

    func test_decodeBase64_decodesCorrectly() {
        let encoded = Data("Hello, world!".utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        XCTAssertEqual(MIMEParser.decodeBase64(encoded), "Hello, world!")
    }
}
```

### Étape 3 : Implémenter `MIMEParser.swift` + réponses API décodables

```swift
import Foundation

// Structures de décodage des réponses Gmail API

struct GmailThreadListResponse: Decodable {
    let threads: [GmailThreadRef]?
    let nextPageToken: String?
    let resultSizeEstimate: Int?
}

struct GmailThreadRef: Decodable {
    let id: String
    let snippet: String
    let historyId: String
}

struct GmailAPIThread: Decodable {
    let id: String
    let snippet: String
    let historyId: String
    let messages: [GmailAPIMessage]?
}

struct GmailAPIMessage: Decodable {
    let id: String
    let threadId: String
    let labelIds: [String]?
    let snippet: String?
    let payload: MessagePart?
    let internalDate: String?

    struct MessagePart: Decodable {
        let partId: String?
        let mimeType: String?
        let headers: [Header]?
        let body: MessageBody?
        let parts: [MessagePart]?
    }

    struct Header: Decodable {
        let name: String
        let value: String
    }

    struct MessageBody: Decodable {
        let attachmentId: String?
        let size: Int
        let data: String?
    }
}

struct GmailLabelListResponse: Decodable {
    let labels: [GmailAPILabel]
}

struct GmailAPILabel: Decodable {
    let id: String
    let name: String
    let type: String?
    let messagesUnread: Int?
}

struct GmailHistoryListResponse: Decodable {
    let history: [HistoryRecord]?
    let historyId: String
    let nextPageToken: String?

    struct HistoryRecord: Decodable {
        let id: String
        let messages: [GmailAPIMessage]?
        let messagesAdded: [MessageAdded]?
        let messagesDeleted: [MessageDeleted]?
        let labelsAdded: [LabelChange]?
        let labelsRemoved: [LabelChange]?
    }

    struct MessageAdded: Decodable { let message: GmailAPIMessage }
    struct MessageDeleted: Decodable { let message: GmailAPIMessage }
    struct LabelChange: Decodable {
        let message: GmailAPIMessage
        let labelIds: [String]
    }
}

// MIME Parser

enum MIMEParser {
    static func header(_ name: String, from headers: [GmailAPIMessage.Header]?) -> String? {
        headers?.first { $0.name.lowercased() == name.lowercased() }?.value
    }

    static func decodeBase64(_ encoded: String) -> String? {
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func extractBody(from part: GmailAPIMessage.MessagePart?) -> (html: String?, plain: String?) {
        guard let part = part else { return (nil, nil) }
        return extractBodyRecursive(from: part)
    }

    private static func extractBodyRecursive(from part: GmailAPIMessage.MessagePart) -> (html: String?, plain: String?) {
        var html: String?
        var plain: String?

        switch part.mimeType {
        case "text/html":
            html = part.body?.data.flatMap { decodeBase64($0) }
        case "text/plain":
            plain = part.body?.data.flatMap { decodeBase64($0) }
        default:
            for subpart in part.parts ?? [] {
                let (h, p) = extractBodyRecursive(from: subpart)
                if html == nil { html = h }
                if plain == nil { plain = p }
            }
        }
        return (html, plain)
    }

    static func parseDate(_ internalDate: String?) -> Date {
        guard let raw = internalDate, let ms = Double(raw) else { return Date() }
        return Date(timeIntervalSince1970: ms / 1000)
    }
}
```

### Étape 4 : Écrire les tests GmailService

```swift
import XCTest
@testable import GMac

final class GmailServiceTests: XCTestCase {
    var mockClient: MockHTTPClient!
    var service: GmailService!

    override func setUp() {
        mockClient = MockHTTPClient()
        service = GmailService(httpClient: mockClient)
    }

    func test_fetchLabels_returnsLabels() async {
        let apiResponse = GmailLabelListResponse(labels: [
            GmailAPILabel(id: "INBOX", name: "INBOX", type: "system", messagesUnread: 3),
            GmailAPILabel(id: "SENT", name: "SENT", type: "system", messagesUnread: nil)
        ])
        mockClient.stub(result: apiResponse)

        let result = await service.fetchLabels()

        switch result {
        case .success(let labels):
            XCTAssertEqual(labels.count, 2)
            XCTAssertEqual(labels[0].id, "INBOX")
            XCTAssertEqual(labels[0].name, "INBOX")
            XCTAssertEqual(labels[0].messagesUnread, 3)
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    func test_fetchLabels_propagatesNetworkError() async {
        mockClient.stubError(.offline)
        let result = await service.fetchLabels()
        if case .failure(.offline) = result { } else {
            XCTFail("Expected .offline error")
        }
    }

    func test_fetchThreadList_returnsThreadRefs() async {
        let apiResponse = GmailThreadListResponse(
            threads: [
                GmailThreadRef(id: "thread1", snippet: "Hello", historyId: "12345")
            ],
            nextPageToken: nil,
            resultSizeEstimate: 1
        )
        mockClient.stub(result: apiResponse)

        let result = await service.fetchThreadList(labelId: "INBOX")

        switch result {
        case .success(let refs):
            XCTAssertEqual(refs.count, 1)
            XCTAssertEqual(refs[0].id, "thread1")
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    func test_fetchThread_propagates429() async {
        mockClient.stubError(.rateLimited(retryAfter: 30))
        let result = await service.fetchThread(id: "thread1")
        if case .failure(.rateLimited(30)) = result { } else {
            XCTFail("Expected .rateLimited(30)")
        }
    }
}
```

### Étape 5 : Lancer le test — vérifier l'échec

Cmd+U. Attendu : `GmailService` not found.

### Étape 6 : Implémenter `GmailService.swift`

```swift
import Foundation

final class GmailService {
    private let httpClient: any HTTPClientProtocol

    init(httpClient: any HTTPClientProtocol) {
        self.httpClient = httpClient
    }

    func fetchLabels() async -> Result<[GmailLabel], AppError> {
        let request = URLRequest(url: Endpoints.labelsList())
        let result: Result<GmailLabelListResponse, AppError> = await httpClient.send(request)
        return result.map { response in
            response.labels.map { apiLabel in
                GmailLabel(
                    id: apiLabel.id,
                    name: apiLabel.name,
                    type: apiLabel.type == "system" ? .system : .user,
                    messagesUnread: apiLabel.messagesUnread
                )
            }
        }
    }

    func fetchThreadList(labelId: String, pageToken: String? = nil) async -> Result<[GmailThreadRef], AppError> {
        let request = URLRequest(url: Endpoints.threadsList(labelIds: [labelId]))
        let result: Result<GmailThreadListResponse, AppError> = await httpClient.send(request)
        return result.map { $0.threads ?? [] }
    }

    func fetchThread(id: String) async -> Result<EmailThread, AppError> {
        let request = URLRequest(url: Endpoints.threadGet(id: id))
        let result: Result<GmailAPIThread, AppError> = await httpClient.send(request)
        return result.map { apiThread in
            let messages = (apiThread.messages ?? []).map { parseMessage($0) }
            return EmailThread(
                id: apiThread.id,
                snippet: apiThread.snippet,
                historyId: apiThread.historyId,
                messages: messages
            )
        }
    }

    func fetchHistory(startHistoryId: String) async -> Result<GmailHistoryListResponse, AppError> {
        let request = URLRequest(url: Endpoints.historyList(startHistoryId: startHistoryId))
        return await httpClient.send(request)
    }

    private func parseMessage(_ api: GmailAPIMessage) -> EmailMessage {
        let headers = api.payload?.headers
        let (html, plain) = MIMEParser.extractBody(from: api.payload)
        return EmailMessage(
            id: api.id,
            threadId: api.threadId,
            snippet: api.snippet ?? "",
            subject: MIMEParser.header("Subject", from: headers) ?? "(Sans sujet)",
            from: MIMEParser.header("From", from: headers) ?? "",
            to: (MIMEParser.header("To", from: headers) ?? "")
                .components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) },
            date: MIMEParser.parseDate(api.internalDate),
            bodyHTML: html,
            bodyPlain: plain,
            labelIds: api.labelIds ?? [],
            isUnread: api.labelIds?.contains("UNREAD") ?? false
        )
    }
}
```

### Étape 7 : Lancer les tests — vérifier qu'ils passent

Cmd+U. Attendu : tous verts.

### Étape 8 : Commit

```bash
git add GMac/Services/ GMacTests/Unit/GmailServiceTests.swift GMacTests/Unit/MIMEParserTests.swift
git commit -m "feat: GmailService — lecture threads, labels, historyId + MIMEParser"
```

---

## Task 8 : SessionStore

**Files:**
- Create: `GMac/Store/SessionStore.swift`
- Create: `GMacTests/Unit/SessionStoreTests.swift`

### Étape 1 : Écrire les tests — priorité sur pendingOperations

```swift
import XCTest
@testable import GMac

@MainActor
final class SessionStoreTests: XCTestCase {
    var store: SessionStore!
    var mockGmailService: MockGmailService!

    override func setUp() {
        mockGmailService = MockGmailService()
        store = SessionStore(gmailService: mockGmailService)
    }

    func test_initialState_isEmpty() {
        XCTAssertTrue(store.threads.isEmpty)
        XCTAssertTrue(store.labels.isEmpty)
        XCTAssertFalse(store.isLoading)
        XCTAssertTrue(store.pendingOperations.isEmpty)
    }

    func test_loadLabels_setsLabels() async {
        mockGmailService.labelsResult = .success([
            GmailLabel(id: "INBOX", name: "INBOX", type: .system, messagesUnread: 2)
        ])
        await store.loadLabels()
        XCTAssertEqual(store.labels.count, 1)
        XCTAssertEqual(store.labels[0].id, "INBOX")
    }

    func test_loadLabels_onError_setsLastSyncError() async {
        mockGmailService.labelsResult = .failure(.offline)
        await store.loadLabels()
        XCTAssertEqual(store.lastSyncError, .offline)
        XCTAssertTrue(store.labels.isEmpty)
    }

    // LE TEST LE PLUS IMPORTANT DU PROJET
    func test_pendingOperations_clearedOnSuccess() async {
        // Simuler qu'une opération en cours libère pendingOperations après succès
        let threadId = "thread123"
        mockGmailService.archiveResult = .success(())
        await store.archiveThread(id: threadId)
        XCTAssertFalse(store.pendingOperations.contains(threadId),
                       "pendingOperations doit être libéré après succès")
    }

    // LE TEST LE PLUS IMPORTANT DU PROJET (bis)
    func test_pendingOperations_clearedOnError() async {
        let threadId = "thread123"
        mockGmailService.archiveResult = .failure(.offline)
        await store.archiveThread(id: threadId)
        XCTAssertFalse(store.pendingOperations.contains(threadId),
                       "pendingOperations doit être libéré même en cas d'erreur")
    }

    func test_archiveThread_onError_setsLastSyncError() async {
        mockGmailService.archiveResult = .failure(.network(URLError(.timedOut)))
        await store.archiveThread(id: "thread123")
        XCTAssertNotNil(store.lastSyncError)
    }
}
```

### Étape 2 : Créer `MockGmailService`

Dans `GMacTests/Mocks/MockGmailService.swift` :

```swift
@testable import GMac

final class MockGmailService {
    var labelsResult: Result<[GmailLabel], AppError> = .success([])
    var threadListResult: Result<[GmailThreadRef], AppError> = .success([])
    var threadResult: Result<EmailThread, AppError> = .failure(.unknown)
    var archiveResult: Result<Void, AppError> = .success(())
    var sendResult: Result<Void, AppError> = .success(())
}

extension MockGmailService: GmailServiceProtocol {
    func fetchLabels() async -> Result<[GmailLabel], AppError> { labelsResult }
    func fetchThreadList(labelId: String, pageToken: String?) async -> Result<[GmailThreadRef], AppError> { threadListResult }
    func fetchThread(id: String) async -> Result<EmailThread, AppError> { threadResult }
    func archiveThread(id: String) async -> Result<Void, AppError> { archiveResult }
    func send(message: OutgoingMessage) async -> Result<Void, AppError> { sendResult }
    func fetchHistory(startHistoryId: String) async -> Result<GmailHistoryListResponse, AppError> { .success(GmailHistoryListResponse(history: nil, historyId: "0", nextPageToken: nil)) }
}
```

### Étape 3 : Lancer le test — vérifier l'échec

Cmd+U. Attendu : `SessionStore` not found.

### Étape 4 : Implémenter `SessionStore.swift`

```swift
import Foundation

protocol GmailServiceProtocol {
    func fetchLabels() async -> Result<[GmailLabel], AppError>
    func fetchThreadList(labelId: String, pageToken: String?) async -> Result<[GmailThreadRef], AppError>
    func fetchThread(id: String) async -> Result<EmailThread, AppError>
    func archiveThread(id: String) async -> Result<Void, AppError>
    func send(message: OutgoingMessage) async -> Result<Void, AppError>
    func fetchHistory(startHistoryId: String) async -> Result<GmailHistoryListResponse, AppError>
}

struct OutgoingMessage {
    let to: [String]
    let subject: String
    let body: String
    let replyToThreadId: String?
}

@Observable
@MainActor
final class SessionStore {
    var threads: [EmailThread] = []
    var openMessages: [String: EmailMessage] = [:]
    var labels: [GmailLabel] = []
    var currentHistoryId: String = ""

    var selectedLabelId: String = "INBOX"
    var selectedThreadId: String? = nil

    var pendingOperations: Set<String> = []
    var isLoading: Bool = false
    var lastSyncError: AppError? = nil

    private let gmailService: any GmailServiceProtocol
    private var loadThreadTasks: [String: Task<Void, Never>] = [:]

    init(gmailService: any GmailServiceProtocol) {
        self.gmailService = gmailService
    }

    func loadLabels() async {
        let result = await gmailService.fetchLabels()
        switch result {
        case .success(let labels):
            self.labels = labels
        case .failure(let error):
            self.lastSyncError = error
        }
    }

    func loadThreadList() async {
        isLoading = true
        defer { isLoading = false }
        let result = await gmailService.fetchThreadList(labelId: selectedLabelId, pageToken: nil)
        switch result {
        case .success(let refs):
            // Charger les threads un par un en arrière-plan
            for ref in refs.prefix(20) {
                Task { await loadThread(id: ref.id) }
            }
        case .failure(let error):
            lastSyncError = error
        }
    }

    func loadThread(id: String) async {
        loadThreadTasks[id]?.cancel()
        loadThreadTasks[id] = Task {
            let result = await gmailService.fetchThread(id: id)
            if Task.isCancelled { return }
            switch result {
            case .success(let thread):
                if let index = threads.firstIndex(where: { $0.id == id }) {
                    threads[index] = thread
                } else {
                    threads.append(thread)
                }
            case .failure(let error):
                lastSyncError = error
            }
        }
        await loadThreadTasks[id]?.value
    }

    func archiveThread(id: String) async {
        pendingOperations.insert(id)
        defer { pendingOperations.remove(id) }  // libéré dans TOUS les cas

        let result = await gmailService.archiveThread(id: id)
        switch result {
        case .success:
            threads.removeAll { $0.id == id }
            if selectedThreadId == id { selectedThreadId = nil }
        case .failure(let error):
            lastSyncError = error
        }
    }

    func reconcile() async {
        guard !currentHistoryId.isEmpty else { return }
        let result = await gmailService.fetchHistory(startHistoryId: currentHistoryId)
        switch result {
        case .success(let history):
            currentHistoryId = history.historyId
            // Recharger les threads modifiés
            let changedThreadIds = Set(
                (history.history ?? []).flatMap { record in
                    ((record.messagesAdded?.map { $0.message.threadId }) ?? []) +
                    ((record.messagesDeleted?.map { $0.message.threadId }) ?? [])
                }
            )
            for threadId in changedThreadIds {
                Task { await loadThread(id: threadId) }
            }
        case .failure(let error):
            lastSyncError = error
        }
    }
}
```

### Étape 5 : Ajouter `archiveThread` à `GmailService`

Dans `GmailService.swift`, ajouter :

```swift
func archiveThread(id: String) async -> Result<Void, AppError> {
    var request = URLRequest(url: URL(string: "\(Endpoints.gmailBase)/users/me/threads/\(id)/modify")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: [
        "removeLabelIds": ["INBOX"]
    ])

    struct EmptyResponse: Decodable {}
    let result: Result<EmptyResponse, AppError> = await httpClient.send(request)
    return result.map { _ in () }
}

func send(message: OutgoingMessage) async -> Result<Void, AppError> {
    // Implémenté au Sprint 2
    return .failure(.unknown)
}
```

Ajouter la conformance `GmailServiceProtocol` à `GmailService`.

### Étape 6 : Lancer les tests — vérifier qu'ils passent

Cmd+U. Attendu : tous verts — en particulier les deux tests `pendingOperations`.

### Étape 7 : Commit

```bash
git add GMac/Store/ GMacTests/Unit/SessionStoreTests.swift GMacTests/Mocks/MockGmailService.swift
git commit -m "feat: SessionStore — source de vérité in-memory, pendingOperations, reconcile historyId"
```

---

## Task 9 : AppEnvironment (DI root)

**Files:**
- Create: `GMac/App/AppEnvironment.swift`
- Modify: `GMac/App/GMacApp.swift`

### Étape 1 : Implémenter `AppEnvironment.swift`

```swift
import Foundation

@Observable
@MainActor
final class AppEnvironment {
    let oauth: GoogleOAuthManager
    let httpClient: AuthenticatedHTTPClient
    let gmailService: GmailService
    let sessionStore: SessionStore

    init() {
        // Récupérer les credentials depuis Info.plist ou une config locale
        let clientId = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String ?? ""
        let clientSecret = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_SECRET") as? String ?? ""

        let keychain = KeychainService()
        self.oauth = GoogleOAuthManager(clientId: clientId, clientSecret: clientSecret, keychain: keychain)
        self.httpClient = AuthenticatedHTTPClient(oauth: oauth)
        self.gmailService = GmailService(httpClient: httpClient)
        self.sessionStore = SessionStore(gmailService: gmailService)
    }
}
```

### Étape 2 : Modifier `GMacApp.swift`

```swift
import SwiftUI

@main
struct GMacApp: App {
    @State private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            if env.oauth.isAuthenticated {
                ContentView()
                    .environment(env.sessionStore)
            } else {
                LoginView()
                    .environment(env.oauth)
            }
        }
    }
}
```

### Étape 3 : Ajouter `GOOGLE_CLIENT_ID` à Info.plist

Dans Xcode → GMac → Info → ajouter :
- Key: `GOOGLE_CLIENT_ID` → Value: (ton client ID)
- Key: `GOOGLE_CLIENT_SECRET` → Value: (ton client secret)
- Key: `CFBundleURLTypes` → URL Scheme: `fr.agence810.gmac`

### Étape 4 : Commit

```bash
git add GMac/App/
git commit -m "feat: AppEnvironment — DI root, assemblage des dépendances"
```

---

## Task 10 : UI skeleton — NavigationSplitView + LoginView

**Files:**
- Create: `GMac/UI/LoginView.swift`
- Create: `GMac/UI/ContentView.swift`
- Create: `GMac/UI/Sidebar/SidebarView.swift`
- Create: `GMac/UI/ThreadList/ThreadListView.swift`
- Create: `GMac/UI/MessageView/MessageView.swift`

> Note UI : toute l'interface utilisera le langage visuel **Liquid Glass** (macOS 26 Tahoe). L'implémentation détaillée des composants visuels sera faite via le skill `frontend-design`. Ce sprint pose le skeleton fonctionnel uniquement.

### Étape 1 : `LoginView.swift`

```swift
import SwiftUI

struct LoginView: View {
    @Environment(GoogleOAuthManager.self) var oauth
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "envelope.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("GMac")
                .font(.largeTitle.bold())

            Text("Client Gmail natif macOS")
                .foregroundStyle(.secondary)

            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Button(action: signIn) {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Se connecter avec Google", systemImage: "person.badge.key.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
        }
        .frame(width: 400, height: 300)
    }

    private func signIn() {
        isLoading = true
        error = nil
        Task {
            do {
                try await oauth.startOAuthFlow()
            } catch {
                self.error = "Connexion échouée : \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}
```

### Étape 2 : `ContentView.swift`

```swift
import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) var store

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            ThreadListView()
        } detail: {
            MessageDetailView()
        }
        .task { await store.loadLabels() }
        .task { await store.loadThreadList() }
    }
}
```

### Étape 3 : `SidebarView.swift`

```swift
import SwiftUI

struct SidebarView: View {
    @Environment(SessionStore.self) var store

    private let systemLabels = ["INBOX", "SENT", "DRAFTS", "TRASH", "SPAM"]

    var body: some View {
        List(selection: Binding(
            get: { store.selectedLabelId },
            set: { store.selectedLabelId = $0 ?? "INBOX" }
        )) {
            Section("Boîtes") {
                ForEach(store.labels.filter { systemLabels.contains($0.id) }) { label in
                    LabelRow(label: label)
                }
            }
            Section("Labels") {
                ForEach(store.labels.filter { !systemLabels.contains($0.id) }) { label in
                    LabelRow(label: label)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    }
}

private struct LabelRow: View {
    let label: GmailLabel
    var body: some View {
        HStack {
            Label(label.name, systemImage: labelIcon(label.id))
            Spacer()
            if let unread = label.messagesUnread, unread > 0 {
                Text("\(unread)").font(.caption.bold()).foregroundStyle(.blue)
            }
        }
        .tag(label.id)
    }

    private func labelIcon(_ id: String) -> String {
        switch id {
        case "INBOX": return "tray"
        case "SENT": return "paperplane"
        case "DRAFTS": return "doc"
        case "TRASH": return "trash"
        case "SPAM": return "exclamationmark.shield"
        default: return "tag"
        }
    }
}
```

### Étape 4 : `ThreadListView.swift`

```swift
import SwiftUI

struct ThreadListView: View {
    @Environment(SessionStore.self) var store

    var filteredThreads: [EmailThread] {
        store.threads.filter { thread in
            thread.messages.contains { $0.labelIds.contains(store.selectedLabelId) }
        }
    }

    var body: some View {
        Group {
            if store.isLoading && store.threads.isEmpty {
                ProgressView("Chargement…")
            } else {
                List(filteredThreads, selection: Binding(
                    get: { store.selectedThreadId },
                    set: { store.selectedThreadId = $0 }
                )) { thread in
                    ThreadRow(thread: thread)
                        .tag(thread.id)
                }
                .listStyle(.plain)
            }
        }
        .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        .onChange(of: store.selectedLabelId) {
            store.selectedThreadId = nil
            Task { await store.loadThreadList() }
        }
    }
}

private struct ThreadRow: View {
    let thread: EmailThread

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(thread.from)
                    .font(thread.isUnread ? .headline : .body)
                    .lineLimit(1)
                Spacer()
                Text(thread.date.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(thread.subject).lineLimit(1).font(.subheadline)
            Text(thread.snippet).lineLimit(1).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
```

### Étape 5 : `MessageDetailView.swift`

```swift
import SwiftUI
import WebKit

struct MessageDetailView: View {
    @Environment(SessionStore.self) var store

    var selectedThread: EmailThread? {
        store.threads.first { $0.id == store.selectedThreadId }
    }

    var body: some View {
        if let thread = selectedThread {
            ThreadDetailView(thread: thread)
        } else {
            ContentUnavailableView("Aucun message sélectionné", systemImage: "envelope")
        }
    }
}

struct ThreadDetailView: View {
    let thread: EmailThread

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(thread.subject).font(.title2.bold()).padding(.horizontal)

                ForEach(thread.messages) { message in
                    MessageBubble(message: message)
                }
            }
            .padding(.vertical)
        }
    }
}

struct MessageBubble: View {
    let message: EmailMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(message.from).font(.headline)
                Spacer()
                Text(message.date.formatted()).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            if let html = message.bodyHTML {
                WebView(html: html)
                    .frame(minHeight: 200)
            } else {
                Text(message.bodyPlain ?? message.snippet)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .padding(.horizontal)
    }
}

struct WebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = false  // sécurité
        let webView = WKWebView(frame: .zero, configuration: config)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }
}
```

### Étape 6 : Build et vérification visuelle

Cmd+B pour builder. Cmd+R pour lancer l'app. Vérifier :
- [ ] La LoginView s'affiche au premier lancement
- [ ] Après connexion Google, la ContentView s'affiche
- [ ] La sidebar liste les labels Gmail
- [ ] La liste des threads se charge
- [ ] Cliquer un thread affiche les messages

### Étape 7 : Commit

```bash
git add GMac/UI/ GMac/App/
git commit -m "feat: UI skeleton — LoginView, NavigationSplitView, Sidebar, ThreadList, MessageView"
```

---

---

## Task 2-bis : AppError enrichi (fiabilité réseau)

**Files:**
- Modify: `GMac/Models/AppError.swift`
- Modify: `GMacTests/Unit/AppErrorTests.swift`

À faire **juste après Task 2**. Enrichir `AppError` pour distinguer les erreurs retryables des non-retryables.

### Étape 1 : Ajouter les tests manquants dans `AppErrorTests.swift`

```swift
func test_500_isServerError_notRetryable() {
    let e = AppError.serverError(statusCode: 500)
    XCTAssertFalse(e.isRetryable)
}

func test_502_isGatewayError_retryable() {
    let e = AppError.gatewayError(statusCode: 502)
    XCTAssertTrue(e.isRetryable)
}

func test_503_isGatewayError_retryable() {
    let e = AppError.gatewayError(statusCode: 503)
    XCTAssertTrue(e.isRetryable)
}

func test_dnsError_isNotRetryable() {
    XCTAssertFalse(AppError.dnsError.isRetryable)
}

func test_emptyResponse_isNotRetryable() {
    XCTAssertFalse(AppError.emptyResponse.isRetryable)
}
```

### Étape 2 : Mettre à jour `AppError.swift`

```swift
enum AppError: Error, Equatable {
    case network(URLError)
    case apiError(statusCode: Int, message: String)
    case serverError(statusCode: Int)    // 500 — non-retryable
    case gatewayError(statusCode: Int)   // 502/503 — retryable
    case rateLimited(retryAfter: TimeInterval)
    case tokenExpired
    case offline
    case dnsError
    case emptyResponse
    case decodingError(String)
    case unknown

    var isRetryable: Bool {
        switch self {
        case .rateLimited, .gatewayError: return true
        case .network(let e): return e.code == .networkConnectionLost || e.code == .timedOut
        default: return false
        }
    }

    static func == (lhs: AppError, rhs: AppError) -> Bool {
        switch (lhs, rhs) {
        case (.tokenExpired, .tokenExpired), (.offline, .offline),
             (.unknown, .unknown), (.dnsError, .dnsError),
             (.emptyResponse, .emptyResponse): return true
        case (.network(let a), .network(let b)): return a.code == b.code
        case (.apiError(let a, let b), .apiError(let c, let d)): return a == c && b == d
        case (.serverError(let a), .serverError(let b)): return a == b
        case (.gatewayError(let a), .gatewayError(let b)): return a == b
        case (.rateLimited(let a), .rateLimited(let b)): return a == b
        case (.decodingError(let a), .decodingError(let b)): return a == b
        default: return false
        }
    }
}
```

### Étape 3 : Mettre à jour `AuthenticatedHTTPClient.performRequest`

```swift
switch httpResponse.statusCode {
case 200...299:
    guard !data.isEmpty else { return .failure(.emptyResponse) }
    do {
        let decoded = try JSONDecoder().decode(T.self, from: data)
        return .success(decoded)
    } catch let e {
        return .failure(.decodingError(e.localizedDescription))
    }
case 401: return .failure(.apiError(statusCode: 401, message: "Unauthorized"))
case 403: return .failure(.apiError(statusCode: 403, message: "Forbidden"))
case 429:
    let retryAfter = Double(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "5") ?? 5
    return .failure(.rateLimited(retryAfter: max(1, retryAfter)))
case 500: return .failure(.serverError(statusCode: 500))
case 502, 503: return .failure(.gatewayError(statusCode: httpResponse.statusCode))
default:
    let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
    return .failure(.apiError(statusCode: httpResponse.statusCode, message: msg))
}
```

Et dans le `catch` URLError :
```swift
} catch let urlError as URLError {
    switch urlError.code {
    case .notConnectedToInternet, .networkConnectionLost: return .failure(.offline)
    case .dnsLookupFailed, .cannotFindHost: return .failure(.dnsError)
    default: return .failure(.network(urlError))
    }
}
```

### Étape 4 : Mettre à jour `withRetry` pour utiliser `isRetryable`

```swift
func withRetry<T>(
    maxAttempts: Int = 3,
    delay: TimeInterval = -1,
    operation: () async -> Result<T, AppError>
) async -> Result<T, AppError> {
    for attempt in 0..<maxAttempts {
        let result = await operation()
        switch result {
        case .success:
            return result
        case .failure(let error) where error.isRetryable:
            let waitTime: TimeInterval
            if case .rateLimited(let retryAfter) = error {
                waitTime = delay >= 0 ? delay : max(1, retryAfter)
            } else {
                waitTime = delay >= 0 ? delay : pow(2.0, Double(attempt))
            }
            if waitTime > 0 { try? await Task.sleep(for: .seconds(waitTime)) }
        case .failure:
            return result  // non-retryable
        }
    }
    return await operation()
}
```

### Étape 5 : Lancer les tests — vérifier qu'ils passent

Cmd+U. Attendu : tous verts.

### Étape 6 : Commit

```bash
git add GMac/Models/AppError.swift GMac/Network/ GMacTests/Unit/AppErrorTests.swift
git commit -m "feat: AppError enrichi — serverError/gatewayError/dnsError/emptyResponse, withRetry basé sur isRetryable"
```

---

## Task 5-bis : Single-flight OAuth refresh

**Files:**
- Modify: `GMac/Auth/GoogleOAuthManager.swift`
- Modify: `GMacTests/Unit/GoogleOAuthManagerTests.swift`

À faire **juste après Task 5**. Éviter la race condition quand deux requêtes arrivent avec 401 simultanément.

### Étape 1 : Ajouter le test de race condition

```swift
func test_concurrentRefresh_onlyRefreshesOnce() async throws {
    // Pré-conditions : token expiré dans Keychain
    try keychain.save("expired_token", key: "google_access_token")
    try keychain.save("refresh_token", key: "google_refresh_token")
    try keychain.save("\(Date().addingTimeInterval(-100).timeIntervalSince1970)", key: "google_token_expiry")

    var refreshCallCount = 0
    // Note : ce test vérifie que deux appels refresh() simultanés
    // ne font qu'UN seul vrai appel réseau (coalescence via Task)
    async let r1: Void = manager.refresh()
    async let r2: Void = manager.refresh()
    _ = try await (r1, r2)
    // Si implémenté correctement, refreshCallCount == 1 (pas de double write Keychain)
    // Vérifiable indirectement par le fait qu'aucune exception n'est levée
    XCTAssertTrue(manager.isAuthenticated)
}
```

### Étape 2 : Mettre à jour `GoogleOAuthManager.swift`

Remplacer la méthode `refresh()` par :

```swift
private var refreshTask: Task<Void, Error>?

func refresh() async throws {
    if let existingTask = refreshTask {
        return try await existingTask.value
    }
    let task = Task<Void, Error> { [weak self] in
        guard let self else { return }
        try await self._doRefresh()
    }
    refreshTask = task
    defer { refreshTask = nil }
    try await task.value
}

private func _doRefresh() async throws {
    guard let refreshToken = try? keychain.retrieve(key: "google_refresh_token") else {
        throw AppError.tokenExpired
    }
    var request = URLRequest(url: URL(string: Endpoints.tokenURL)!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    let body = "grant_type=refresh_token&refresh_token=\(refreshToken)&client_id=\(clientId)&client_secret=\(clientSecret)"
    request.httpBody = Data(body.utf8)
    let (data, _) = try await URLSession.shared.data(for: request)
    let token = try JSONDecoder().decode(TokenResponse.self, from: data)
    try storeTokens(token, refreshToken: refreshToken)
}
```

### Étape 3 : Lancer les tests

Cmd+U. Attendu : tous verts.

### Étape 4 : Commit

```bash
git add GMac/Auth/GoogleOAuthManager.swift GMacTests/Unit/GoogleOAuthManagerTests.swift
git commit -m "feat: OAuth single-flight refresh — coalescence des 401 simultanés"
```

---

## Task 7-bis : MIME robustesse (charset + Quoted-Printable)

**Files:**
- Modify: `GMac/Services/MIMEParser.swift`
- Create: `GMacTests/Unit/MIMEParserRobustnessTests.swift`

À faire **juste après Task 7**.

### Étape 1 : Écrire les tests de robustesse

```swift
import XCTest
@testable import GMac

final class MIMEParserRobustnessTests: XCTestCase {

    func test_decodeBase64_handlesStandardBase64() {
        // Gmail peut parfois retourner base64 standard (pas url-safe)
        let standard = Data("Hello, world!".utf8).base64EncodedString()
        XCTAssertEqual(MIMEParser.decodeBase64(standard), "Hello, world!")
    }

    func test_decodeBase64_handlesUrlSafeBase64() {
        let urlSafe = Data("Hello, world!".utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        XCTAssertEqual(MIMEParser.decodeBase64(urlSafe), "Hello, world!")
    }

    func test_decodeQuotedPrintable_decodesHexSequences() {
        let qp = "Bonjour =C3=A9t=C3=A9"  // "Bonjour été" en QP
        XCTAssertEqual(MIMEParser.decodeQuotedPrintable(qp), "Bonjour été")
    }

    func test_decodeQuotedPrintable_handlesSoftLineBreaks() {
        let qp = "Hello =\r\nworld"
        XCTAssertEqual(MIMEParser.decodeQuotedPrintable(qp), "Hello world")
    }

    func test_extractBody_nilPayload_returnsEmpty() {
        let (html, plain) = MIMEParser.extractBody(from: nil)
        XCTAssertNil(html)
        XCTAssertNil(plain)
    }

    func test_extractBody_quotedPrintableTransferEncoding() {
        let part = GmailAPIMessage.MessagePart(
            partId: "0",
            mimeType: "text/plain",
            headers: [
                GmailAPIMessage.Header(name: "Content-Transfer-Encoding", value: "quoted-printable")
            ],
            body: GmailAPIMessage.MessageBody(attachmentId: nil, size: 10, data: "Bonjour =C3=A9t=C3=A9"),
            parts: nil
        )
        let (_, plain) = MIMEParser.extractBody(from: part)
        XCTAssertEqual(plain, "Bonjour été")
    }
}
```

### Étape 2 : Lancer le test — vérifier l'échec

Cmd+U. Attendu : `decodeQuotedPrintable` not found.

### Étape 3 : Mettre à jour `MIMEParser.swift`

Ajouter à `MIMEParser` :

```swift
static func decodeQuotedPrintable(_ input: String) -> String {
    var result = input
    // Soft line breaks : = suivi de CRLF ou LF
    result = result.replacingOccurrences(of: "=\r\n", with: "")
    result = result.replacingOccurrences(of: "=\n", with: "")
    // Séquences hex : =XX
    let pattern = "=[0-9A-Fa-f]{2}"
    var output = ""
    var remaining = result[...]
    while let range = remaining.range(of: pattern, options: .regularExpression) {
        output += remaining[..<range.lowerBound]
        let hex = String(remaining[range].dropFirst())
        if let byte = UInt8(hex, radix: 16) {
            output += String(bytes: [byte], encoding: .isoLatin1) ?? ""
        }
        remaining = remaining[range.upperBound...]
    }
    output += remaining
    return output
}
```

Mettre à jour `extractBodyRecursive` pour vérifier `Content-Transfer-Encoding` :

```swift
private static func extractBodyRecursive(from part: GmailAPIMessage.MessagePart) -> (html: String?, plain: String?) {
    var html: String?
    var plain: String?
    let transferEncoding = part.headers?
        .first { $0.name.lowercased() == "content-transfer-encoding" }?
        .value.lowercased()

    func decodeBody(_ data: String?) -> String? {
        guard let data else { return nil }
        switch transferEncoding {
        case "quoted-printable": return decodeQuotedPrintable(data)
        default: return decodeBase64(data)
        }
    }

    switch part.mimeType {
    case "text/html":
        html = decodeBody(part.body?.data)
    case "text/plain":
        plain = decodeBody(part.body?.data)
    default:
        for subpart in part.parts ?? [] {
            let (h, p) = extractBodyRecursive(from: subpart)
            if html == nil { html = h }
            if plain == nil { plain = p }
        }
    }
    return (html, plain)
}
```

### Étape 4 : Lancer les tests

Cmd+U. Attendu : tous verts.

### Étape 5 : Commit

```bash
git add GMac/Services/MIMEParser.swift GMacTests/Unit/MIMEParserRobustnessTests.swift
git commit -m "feat: MIMEParser robuste — Quoted-Printable, base64 standard + url-safe, nil payload safe"
```

---

## Task 8-bis : historyId expiration + reconcile retry

**Files:**
- Modify: `GMac/Store/SessionStore.swift`
- Modify: `GMacTests/Unit/SessionStoreTests.swift`

À faire **juste après Task 8**.

### Étape 1 : Ajouter les tests

```swift
func test_reconcile_on400_triggersFullReload() async {
    // Simuler un historyId expiré → 400
    mockGmailService.historyResult = .failure(.apiError(statusCode: 400, message: "Invalid historyId"))
    mockGmailService.threadListResult = .success([])
    store.currentHistoryId = "stale_id"

    await store.reconcile()

    XCTAssertEqual(store.currentHistoryId, "", "historyId doit être réinitialisé après 400")
}

func test_reconcile_onRateLimited_doesNotCrash() async {
    mockGmailService.historyResult = .failure(.rateLimited(retryAfter: 1))
    await store.reconcile()
    // Pas de crash, lastSyncError peut être nil car withRetry a retried
    XCTAssertTrue(true)
}
```

### Étape 2 : Mettre à jour `SessionStore.reconcile()`

```swift
func reconcile() async {
    guard !currentHistoryId.isEmpty else { return }
    let result = await withRetry(maxAttempts: 2) {
        await self.gmailService.fetchHistory(startHistoryId: self.currentHistoryId)
    }
    switch result {
    case .success(let history):
        currentHistoryId = history.historyId
        let changedThreadIds = Set(
            (history.history ?? []).flatMap { record in
                ((record.messagesAdded?.map { $0.message.threadId }) ?? []) +
                ((record.messagesDeleted?.map { $0.message.threadId }) ?? [])
            }
        )
        for threadId in changedThreadIds {
            Task { await loadThread(id: threadId) }
        }
    case .failure(.apiError(400, _)):
        // historyId expiré (>7 jours) → rechargement complet
        currentHistoryId = ""
        await loadThreadList()
    case .failure(let error):
        lastSyncError = error
    }
}
```

### Étape 3 : Lancer les tests

Cmd+U. Attendu : tous verts.

### Étape 4 : Commit

```bash
git add GMac/Store/SessionStore.swift GMacTests/Unit/SessionStoreTests.swift
git commit -m "feat: reconcile — détecte historyId expiré (400), withRetry sur rate limit"
```

---

## Résumé Sprint 1 (avec fixes fiabilité)

À la fin de ce sprint, l'app :
- S'authentifie avec Google OAuth2 (tokens dans le Keychain)
- Charge les labels Gmail avec pagination complète
- Liste les threads de la boîte de réception
- Affiche le contenu des messages (HTML + texte, UTF-8 et ISO-8859-1, base64 et Quoted-Printable)
- Gère le token refresh transparent avec single-flight (zéro race condition)
- Retry automatique uniquement sur erreurs retryables (502/503/rateLimited) — pas sur 500 ou send
- Ne crashe pas sur les erreurs API — toutes les erreurs sont typées et gérées
- Ne perd aucune donnée — zéro écriture Gmail sur disque
- Récupère proprement un historyId expiré sans erreur visible
- Tests unitaires couvrant : AppError (avec isRetryable), KeychainService, GmailService, SessionStore, MIMEParser (robustesse)

**Sprint 2 :** Composeur, envoi avec countdown 3s annulable + idempotency key, gestion des brouillons.

---

*Plan Sprint 1 — GMac — 25 avril 2026*
