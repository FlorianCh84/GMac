import Foundation

final class GmailSettingsService: GmailSettingsServiceProtocol, @unchecked Sendable {
    private let httpClient: any HTTPClientProtocol

    init(httpClient: any HTTPClientProtocol) {
        self.httpClient = httpClient
    }

    func fetchSendAsList() async -> Result<[SendAsAlias], AppError> {
        let result: Result<SendAsListResponse, AppError> = await httpClient.send(URLRequest(url: Endpoints.sendAsList()))
        return result.map { $0.sendAs }
    }

    func updateSignature(sendAsEmail: String, html: String) async -> Result<Void, AppError> {
        do {
            var request = URLRequest(url: Endpoints.sendAsUpdate(sendAsEmail: sendAsEmail))
            request.httpMethod = "PATCH"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(UpdateSignatureRequest(signature: html))
            let result: Result<EmptyResponse, AppError> = await httpClient.send(request)
            return result.map { _ in () }
        } catch { return .failure(.unknown) }
    }

    func fetchVacationSettings() async -> Result<VacationSettings, AppError> {
        await httpClient.send(URLRequest(url: Endpoints.vacationSettings()))
    }

    func updateVacationSettings(_ settings: VacationSettings) async -> Result<Void, AppError> {
        do {
            var request = URLRequest(url: Endpoints.vacationSettings())
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(settings)
            let result: Result<EmptyResponse, AppError> = await httpClient.send(request)
            return result.map { _ in () }
        } catch { return .failure(.unknown) }
    }

    func createLabel(name: String) async -> Result<GmailLabel, AppError> {
        do {
            var request = URLRequest(url: Endpoints.labelCreate())
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(CreateLabelRequest(name: name))
            let result: Result<GmailAPILabel, AppError> = await httpClient.send(request)
            return result.map { mapLabel($0) }
        } catch { return .failure(.unknown) }
    }

    func updateLabel(id: String, name: String) async -> Result<GmailLabel, AppError> {
        do {
            var request = URLRequest(url: Endpoints.labelUpdate(id: id))
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(UpdateLabelRequest(name: name))
            let result: Result<GmailAPILabel, AppError> = await httpClient.send(request)
            return result.map { mapLabel($0) }
        } catch { return .failure(.unknown) }
    }

    func deleteLabel(id: String) async -> Result<Void, AppError> {
        var request = URLRequest(url: Endpoints.labelDelete(id: id))
        request.httpMethod = "DELETE"
        let result: Result<EmptyResponse, AppError> = await httpClient.send(request)
        return result.map { _ in () }
    }

    private func mapLabel(_ api: GmailAPILabel) -> GmailLabel {
        GmailLabel(id: api.id, name: api.name, type: api.type == "system" ? .system : .user, messagesUnread: api.messagesUnread)
    }
}
