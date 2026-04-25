import Foundation

protocol GmailServiceProtocol: Sendable {
    func fetchLabels() async -> Result<[GmailLabel], AppError>
    func fetchThreadList(labelId: String, pageToken: String?) async -> Result<[GmailThreadRef], AppError>
    func fetchThread(id: String) async -> Result<EmailThread, AppError>
    func archiveThread(id: String) async -> Result<Void, AppError>
    func send(message: OutgoingMessage) async -> Result<Void, AppError>
    func fetchHistory(startHistoryId: String) async -> Result<GmailHistoryListResponse, AppError>
}
