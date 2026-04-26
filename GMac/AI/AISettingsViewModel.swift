import Foundation
import Observation

@Observable
@MainActor
final class AISettingsViewModel {
    private static let providerKey = "gmac.selectedProvider"

    var selectedProvider: LLMProviderType = {
        if let raw = UserDefaults.standard.string(forKey: "gmac.selectedProvider"),
           let type = LLMProviderType(rawValue: raw) {
            return type
        }
        return .claude
    }() {
        didSet {
            UserDefaults.standard.set(selectedProvider.rawValue, forKey: "gmac.selectedProvider")
        }
    }
    var claudeKey: String = ""
    var openaiKey: String = ""
    var geminiKey: String = ""
    var mistralKey: String = ""
    var isSaving: Bool = false
    var saveSuccess: Bool = false
    var saveError: String? = nil

    private let keychain: any KeychainServiceProtocol

    init(keychain: any KeychainServiceProtocol = KeychainService()) {
        self.keychain = keychain
        claudeKey = (try? keychain.retrieve(key: "claude_api_key")) ?? ""
        openaiKey = (try? keychain.retrieve(key: "openai_api_key")) ?? ""
        geminiKey = (try? keychain.retrieve(key: "gemini_api_key")) ?? ""
        mistralKey = (try? keychain.retrieve(key: "mistral_api_key")) ?? ""
        // selectedProvider est chargé depuis UserDefaults via la propriété calculée — plus fiable que le Keychain
    }

    func save() async {
        isSaving = true
        saveSuccess = false
        saveError = nil
        defer { isSaving = false }
        do {
            try keychain.save(claudeKey, key: "claude_api_key")
            try keychain.save(openaiKey, key: "openai_api_key")
            try keychain.save(geminiKey, key: "gemini_api_key")
            try keychain.save(mistralKey, key: "mistral_api_key")
            // Double persistance : UserDefaults (didSet) + Keychain pour fiabilité maximale
            UserDefaults.standard.set(selectedProvider.rawValue, forKey: "gmac.selectedProvider")
            UserDefaults.standard.synchronize()
            saveSuccess = true
        } catch {
            saveError = error.localizedDescription
        }
    }

    func activeProvider() -> any LLMProvider {
        LLMProviderFactory.provider(for: selectedProvider, keychain: keychain)
    }
}
