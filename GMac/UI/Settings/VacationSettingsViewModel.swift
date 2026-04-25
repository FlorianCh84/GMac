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
            startTime: nil, endTime: nil,
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
