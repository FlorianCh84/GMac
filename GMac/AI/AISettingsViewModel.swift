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
    var saveError: String? = nil

    private let keychain: any KeychainServiceProtocol

    init(keychain: any KeychainServiceProtocol = KeychainService()) {
        self.keychain = keychain
        claudeKey = (try? keychain.retrieve(key: "claude_api_key")) ?? ""
        openaiKey = (try? keychain.retrieve(key: "openai_api_key")) ?? ""
        geminiKey = (try? keychain.retrieve(key: "gemini_api_key")) ?? ""
        mistralKey = (try? keychain.retrieve(key: "mistral_api_key")) ?? ""
        if let raw = try? keychain.retrieve(key: "llm_selected_provider"), let t = LLMProviderType(rawValue: raw) {
            selectedProvider = t
        }
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
            try keychain.save(selectedProvider.rawValue, key: "llm_selected_provider")
            saveSuccess = true
        } catch {
            saveError = error.localizedDescription
        }
    }

    func activeProvider() -> any LLMProvider {
        LLMProviderFactory.provider(for: selectedProvider, keychain: keychain)
    }
}
