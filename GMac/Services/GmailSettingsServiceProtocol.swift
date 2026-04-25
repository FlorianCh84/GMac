import Foundation

protocol GmailSettingsServiceProtocol: Sendable {
    func fetchSendAsList() async -> Result<[SendAsAlias], AppError>
    func updateSignature(sendAsEmail: String, html: String) async -> Result<Void, AppError>
    func fetchVacationSettings() async -> Result<VacationSettings, AppError>
    func updateVacationSettings(_ settings: VacationSettings) async -> Result<Void, AppError>
    func createLabel(name: String) async -> Result<GmailLabel, AppError>
    func updateLabel(id: String, name: String) async -> Result<GmailLabel, AppError>
    func deleteLabel(id: String) async -> Result<Void, AppError>
}
