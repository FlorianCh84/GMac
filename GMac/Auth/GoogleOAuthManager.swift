import AuthenticationServices
import Foundation

@Observable
@MainActor
final class GoogleOAuthManager: NSObject {
    private let clientId: String
    private let clientSecret: String
    let keychain: any KeychainServiceProtocol
    private let redirectURI = "com.googleusercontent.apps.1003757919116-ieidrg2o2cm450t06aeds8vebrm027f1:/oauth2callback"
    private let scopes = [
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/gmail.send",
        "https://www.googleapis.com/auth/gmail.settings.basic",
        "https://www.googleapis.com/auth/gmail.settings.sharing",
        "https://www.googleapis.com/auth/drive.file"
    ]

    // Single-flight refresh : évite la race condition où deux 401 simultanés
    // déclenchent deux refreshes concurrents qui s'écrasent mutuellement
    private actor RefreshCoordinator {
        private var task: Task<Void, Error>?

        func refresh(work: @escaping @Sendable () async throws -> Void) async throws {
            if let existing = task { return try await existing.value }
            let t = Task { try await work() }
            task = t
            defer { task = nil }
            try await t.value
        }
    }

    private let refreshCoordinator = RefreshCoordinator()

    var isAuthenticated: Bool {
        guard let expiry = storedExpiry else { return false }
        let hasAccess = (try? keychain.retrieve(key: "google_access_token")) != nil
        let hasRefresh = (try? keychain.retrieve(key: "google_refresh_token")) != nil
        return hasAccess && hasRefresh && Date() < expiry
    }

    private var storedExpiry: Date? {
        guard let raw = try? keychain.retrieve(key: "google_token_expiry"),
              let ts = Double(raw) else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    init(clientId: String, clientSecret: String, keychain: any KeychainServiceProtocol = KeychainService()) {
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

    func refresh() async throws {
        try await refreshCoordinator.refresh { [weak self] in
            guard let self else { return }
            try await self._doRefresh()
        }
    }

    private func _doRefresh() async throws {
        guard let refreshToken = try? keychain.retrieve(key: "google_refresh_token") else {
            throw AppError.tokenExpired
        }
        guard let url = URL(string: Endpoints.tokenURL) else { throw AppError.unknown }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = "grant_type=refresh_token&refresh_token=\(refreshToken)&client_id=\(clientId)"
        if !clientSecret.isEmpty { params += "&client_secret=\(clientSecret)" }
        let body = params
        request.httpBody = Data(body.utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        try storeTokens(token, refreshToken: refreshToken)
    }

    func startOAuthFlow() async throws {
        let expectedState = UUID().uuidString
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: expectedState),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let authURL = components.url else { throw AppError.unknown }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "com.googleusercontent.apps.1003757919116-ieidrg2o2cm450t06aeds8vebrm027f1"
            ) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: AppError.unknown)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        let queryItems = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems
        guard let returnedState = queryItems?.first(where: { $0.name == "state" })?.value,
              returnedState == expectedState else {
            throw AppError.unknown
        }
        guard let code = queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AppError.unknown
        }
        try await exchangeCode(code)
    }

    private func exchangeCode(_ code: String) async throws {
        guard let url = URL(string: Endpoints.tokenURL) else { throw AppError.unknown }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = "grant_type=authorization_code&code=\(code)&redirect_uri=\(redirectURI)&client_id=\(clientId)"
        if !clientSecret.isEmpty { params += "&client_secret=\(clientSecret)" }
        let body = params
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
