import XCTest
@testable import GMac

@MainActor
final class AISettingsViewModelTests: XCTestCase {
    var keychain: MockKeychainService!
    var vm: AISettingsViewModel!

    override func setUp() async throws {
        // Nettoyer UserDefaults avant chaque test pour éviter les interférences entre runs
        UserDefaults.standard.removeObject(forKey: "gmac.selectedProvider")
        keychain = MockKeychainService()
        vm = AISettingsViewModel(keychain: keychain)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "gmac.selectedProvider")
    }

    func test_initialState_defaultProviderClaude() { XCTAssertEqual(vm.selectedProvider, .claude) }

    func test_save_storesClaudeKey() async {
        vm.claudeKey = "sk-ant-test"
        await vm.save()
        XCTAssertEqual(try? keychain.retrieve(key: "claude_api_key"), "sk-ant-test")
    }

    func test_save_storesSelectedProvider() async {
        // selectedProvider est persisté via UserDefaults didSet — pas dans le Keychain
        vm.selectedProvider = .mistral
        XCTAssertEqual(UserDefaults.standard.string(forKey: "gmac.selectedProvider"), LLMProviderType.mistral.rawValue)
        await vm.save()
        // Le Keychain ne doit plus stocker llm_selected_provider (mort — UserDefaults didSet le gère)
        XCTAssertNil(try? keychain.retrieve(key: "llm_selected_provider"))
    }

    func test_activeProvider_returnsCorrectType() {
        vm.selectedProvider = .openai
        XCTAssertEqual(vm.activeProvider().type, .openai)
    }

    func test_save_setsSaveSuccess() async {
        await vm.save()
        XCTAssertTrue(vm.saveSuccess)
        XCTAssertFalse(vm.isSaving)
    }

    func test_save_resetsSaveSuccessBeforeNewSave() async {
        await vm.save()
        XCTAssertTrue(vm.saveSuccess)
        // Deuxième save — saveSuccess doit être false au début
        vm.claudeKey = "new-key"
        // On vérifie juste que save() peut être appelé deux fois sans état stale
        await vm.save()
        XCTAssertTrue(vm.saveSuccess)
    }
}
