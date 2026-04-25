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
        case .success: saveSuccess = true
        case .failure(let e): lastError = e
        }
    }
}
