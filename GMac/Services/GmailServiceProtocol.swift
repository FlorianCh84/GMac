import Foundation

protocol GmailServiceProtocol: Sendable {
    func fetchLabels() async -> Result<[GmailLabel], AppError>
    func fetchThreadList(labelId: String, pageToken: String?) async -> Result<[GmailThreadRef], AppError>
    func fetchThread(id: String) async -> Result<EmailThread, AppError>
    func archiveThread(id: String) async -> Result<Void, AppError>
    func send(message: OutgoingMessage, senderEmail: String) async -> Result<Void, AppError>
    func createDraft(message: OutgoingMessage, senderEmail: String) async -> Result<DraftMessage, AppError>
    func updateDraft(id: String, message: OutgoingMessage, senderEmail: String) async -> Result<DraftMessage, AppError>
    func deleteDraft(id: String) async -> Result<Void, AppError>
    func fetchHistory(startHistoryId: String) async -> Result<GmailHistoryListResponse, AppError>
    func fetchAttachment(messageId: String, attachmentId: String) async -> Result<Data, AppError>
}
