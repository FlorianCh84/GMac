import Foundation
@testable import GMac

final class MockGmailSettingsService: GmailSettingsServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _sendAsResult: Result<[SendAsAlias], AppError> = .success([])
    private var _updateSigResult: Result<Void, AppError> = .success(())
    private var _vacationResult: Result<VacationSettings, AppError> = .failure(.unknown)
    private var _updateVacationResult: Result<Void, AppError> = .success(())
    private var _createLabelResult: Result<GmailLabel, AppError> = .failure(.unknown)
    private var _deleteLabelResult: Result<Void, AppError> = .success(())

    func stubSendAs(_ r: Result<[SendAsAlias], AppError>) { lock.withLock { _sendAsResult = r } }
    func stubUpdateSignature(_ r: Result<Void, AppError>) { lock.withLock { _updateSigResult = r } }
    func stubVacation(_ r: Result<VacationSettings, AppError>) { lock.withLock { _vacationResult = r } }
    func stubUpdateVacation(_ r: Result<Void, AppError>) { lock.withLock { _updateVacationResult = r } }
    func stubCreateLabel(_ r: Result<GmailLabel, AppError>) { lock.withLock { _createLabelResult = r } }
    func stubDeleteLabel(_ r: Result<Void, AppError>) { lock.withLock { _deleteLabelResult = r } }

    func fetchSendAsList() async -> Result<[SendAsAlias], AppError> { lock.withLock { _sendAsResult } }
    func updateSignature(sendAsEmail: String, html: String) async -> Result<Void, AppError> { lock.withLock { _updateSigResult } }
    func fetchVacationSettings() async -> Result<VacationSettings, AppError> { lock.withLock { _vacationResult } }
    func updateVacationSettings(_ s: VacationSettings) async -> Result<Void, AppError> { lock.withLock { _updateVacationResult } }
    func createLabel(name: String) async -> Result<GmailLabel, AppError> { lock.withLock { _createLabelResult } }
    func updateLabel(id: String, name: String) async -> Result<GmailLabel, AppError> { lock.withLock { _createLabelResult } }
    func deleteLabel(id: String) async -> Result<Void, AppError> { lock.withLock { _deleteLabelResult } }
}
