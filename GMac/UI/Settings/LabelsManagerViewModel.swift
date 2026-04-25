import Foundation
import Observation

@Observable
@MainActor
final class LabelsManagerViewModel {
    var labels: [GmailLabel] = []
    var newLabelName: String = ""
    var isLoading: Bool = false
    var isCreating: Bool = false
    var lastError: AppError? = nil

    private let gmailService: any GmailServiceProtocol
    private let settingsService: any GmailSettingsServiceProtocol

    init(gmailService: any GmailServiceProtocol, settingsService: any GmailSettingsServiceProtocol) {
        self.gmailService = gmailService
        self.settingsService = settingsService
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let result = await gmailService.fetchLabels()
        switch result {
        case .success(let all): labels = all.filter { $0.type == .user }
        case .failure(let e): lastError = e
        }
    }

    func createLabel() async {
        let name = newLabelName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !isCreating else { return }
        isCreating = true
        defer { isCreating = false }
        let result = await settingsService.createLabel(name: name)
        switch result {
        case .success(let label):
            labels.append(label)
            newLabelName = ""
        case .failure(let e):
            lastError = e
        }
    }

    func deleteLabel(id: String) async {
        let result = await settingsService.deleteLabel(id: id)
        switch result {
        case .success: labels.removeAll { $0.id == id }
        case .failure(let e): lastError = e
        }
    }
}
