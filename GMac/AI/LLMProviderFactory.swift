import Foundation

enum LLMProviderFactory {
    static func provider(for type: LLMProviderType, keychain: any KeychainServiceProtocol = KeychainService()) -> any LLMProvider {
        switch type {
        case .claude: return ClaudeProvider(keychain: keychain)
        case .openai: return OpenAIProvider(keychain: keychain)
        case .gemini: return GeminiProvider(keychain: keychain)
        case .mistral: return MistralProvider(keychain: keychain)
        }
    }
}
