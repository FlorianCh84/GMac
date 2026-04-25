import Foundation
@testable import GMac

final class MockGmailService: GmailServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _labelsResult: Result<[GmailLabel], AppError> = .success([])
    private var _threadListResult: Result<[GmailThreadRef], AppError> = .success([])
    private var _threadResult: Result<EmailThread, AppError> = .failure(.unknown)
    private var _archiveResult: Result<Void, AppError> = .success(())
    private var _sendResult: Result<Void, AppError> = .success(())
    private var _historyResult: Result<GmailHistoryListResponse, AppError> = .success(
        GmailHistoryListResponse(history: nil, historyId: "0", nextPageToken: nil)
    )
    private var _createDraftResult: Result<DraftMessage, AppError> = .failure(.unknown)
    private var _deleteDraftResult: Result<Void, AppError> = .success(())
    private var _threadListCallCount = 0
    private var _sendCallCount = 0

    var threadListCallCount: Int { lock.withLock { _threadListCallCount } }
    var sendCallCount: Int { lock.withLock { _sendCallCount } }

    func stubLabels(_ result: Result<[GmailLabel], AppError>) { lock.withLock { _labelsResult = result } }
    func stubThreadList(_ result: Result<[GmailThreadRef], AppError>) { lock.withLock { _threadListResult = result } }
    func stubThread(_ result: Result<EmailThread, AppError>) { lock.withLock { _threadResult = result } }
    func stubArchive(_ result: Result<Void, AppError>) { lock.withLock { _archiveResult = result } }

    func stubSend(_ result: Result<Void, AppError>) { lock.withLock { _sendResult = result } }
    func stubHistory(_ result: Result<GmailHistoryListResponse, AppError>) { lock.withLock { _historyResult = result } }
    func stubCreateDraft(_ result: Result<DraftMessage, AppError>) { lock.withLock { _createDraftResult = result } }
    func stubDeleteDraft(_ result: Result<Void, AppError>) { lock.withLock { _deleteDraftResult = result } }

    func fetchLabels() async -> Result<[GmailLabel], AppError> { lock.withLock { _labelsResult } }
    func fetchThreadList(labelId: String, pageToken: String?) async -> Result<[GmailThreadRef], AppError> { lock.withLock { _threadListCallCount += 1; return _threadListResult } }
    func fetchThread(id: String) async -> Result<EmailThread, AppError> { lock.withLock { _threadResult } }
    func archiveThread(id: String) async -> Result<Void, AppError> { lock.withLock { _archiveResult } }
    func send(message: OutgoingMessage, senderEmail: String) async -> Result<Void, AppError> { lock.withLock { _sendCallCount += 1; return _sendResult } }
    func fetchHistory(startHistoryId: String) async -> Result<GmailHistoryListResponse, AppError> { lock.withLock { _historyResult } }
    func createDraft(message: OutgoingMessage, senderEmail: String) async -> Result<DraftMessage, AppError> { lock.withLock { _createDraftResult } }
    func updateDraft(id: String, message: OutgoingMessage, senderEmail: String) async -> Result<DraftMessage, AppError> { lock.withLock { _createDraftResult } }
    func deleteDraft(id: String) async -> Result<Void, AppError> { lock.withLock { _deleteDraftResult } }
}
