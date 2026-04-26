import Foundation

@Observable
@MainActor
final class AppEnvironment {
    let oauth: GoogleOAuthManager
    let httpClient: AuthenticatedHTTPClient
    let gmailService: GmailService
    let settingsService: GmailSettingsService
    let sessionStore: SessionStore
    let driveService: DriveService
    let aiSettings: AISettingsViewModel
    let voiceProfileAnalyzer: VoiceProfileAnalyzer
    let syncEngine: SyncEngine

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
        self.settingsService = GmailSettingsService(httpClient: client)
        self.sessionStore = SessionStore(gmailService: service)
        self.driveService = DriveService(httpClient: client)
        self.aiSettings = AISettingsViewModel(keychain: keychain)
        print("[GMac] AppEnvironment: provider actif = \(aiSettings.selectedProvider.rawValue)")
        print("[GMac] AppEnvironment: gemini key = \(((try? keychain.retrieve(key: "gemini_api_key")) ?? "").prefix(5))...")
        self.voiceProfileAnalyzer = VoiceProfileAnalyzer(provider: aiSettings.activeProvider())
        self.syncEngine = SyncEngine(store: sessionStore)
    }
}
