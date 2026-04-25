import Foundation

@Observable
@MainActor
final class AppEnvironment {
    let oauth: GoogleOAuthManager
    let httpClient: AuthenticatedHTTPClient
    let gmailService: GmailService
    let sessionStore: SessionStore

    init() {
        let keychain = KeychainService()
        let clientId = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String ?? ""
        let clientSecret = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_SECRET") as? String ?? ""

        let oauthInstance = GoogleOAuthManager(clientId: clientId, clientSecret: clientSecret, keychain: keychain)
        let client = AuthenticatedHTTPClient(oauth: oauthInstance)
        let service = GmailService(httpClient: client)

        self.oauth = oauthInstance
        self.httpClient = client
        self.gmailService = service
        self.sessionStore = SessionStore(gmailService: service)
    }
}
