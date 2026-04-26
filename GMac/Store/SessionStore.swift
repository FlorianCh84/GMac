import Foundation

@Observable
@MainActor
final class SessionStore {
    var threads: [EmailThread] = []
    var openMessages: [String: EmailMessage] = [:]
    var labels: [GmailLabel] = []
    var currentHistoryId: String = ""

    var selectedLabelId: String = "INBOX"
    var selectedThreadId: String? = nil

    var searchQuery: String = ""
    var searchResults: [EmailThread] = []
    var isSearching: Bool = false

    var pendingOperations: Set<String> = []
    var isLoading: Bool = false
    var lastSyncError: AppError? = nil

    var senderEmail: String = ""

    let gmailService: any GmailServiceProtocol

    init(gmailService: any GmailServiceProtocol) {
        self.gmailService = gmailService
    }

    func loadLabels() async {
        let result = await gmailService.fetchLabels()
        switch result {
        case .success(let labels):
            self.labels = labels
        case .failure(let error):
            lastSyncError = error
            print("[GMac] loadLabels error: \(error)")
        }
    }

    func loadThreadList() async {
        isLoading = true
        defer { isLoading = false }
        let result = await gmailService.fetchThreadList(labelId: selectedLabelId, pageToken: nil)
        switch result {
        case .success(let refs):
            await withTaskGroup(of: Void.self) { group in
                for ref in refs.prefix(20) {
                    group.addTask { await self.loadThread(id: ref.id) }
                }
            }
        case .failure(let error):
            lastSyncError = error
        }
    }

    func loadThread(id: String) async {
        guard !Task.isCancelled else { return }
        let result = await gmailService.fetchThread(id: id)
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let thread):
            if let index = threads.firstIndex(where: { $0.id == id }) {
                threads[index] = thread
            } else {
                threads.append(thread)
            }
        case .failure(let error):
            lastSyncError = error
            print("[GMac] loadThreadList error: \(error)")
        }
    }

    func archiveThread(id: String) async {
        pendingOperations.insert(id)
        defer { pendingOperations.remove(id) }

        let result = await gmailService.archiveThread(id: id)
        switch result {
        case .success:
            threads.removeAll { $0.id == id }
            if selectedThreadId == id { selectedThreadId = nil }
        case .failure(let error):
            lastSyncError = error
        }
    }

    func performSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        defer { isSearching = false }

        let result = await gmailService.searchThreads(query: trimmed)
        switch result {
        case .success(let refs):
            var found: [EmailThread] = []
            await withTaskGroup(of: EmailThread?.self) { group in
                for ref in refs.prefix(30) {
                    group.addTask {
                        guard case .success(let t) = await self.gmailService.fetchThread(id: ref.id) else { return nil }
                        return t
                    }
                }
                for await thread in group {
                    if let t = thread { found.append(t) }
                }
            }
            searchResults = found.sorted { $0.date > $1.date }
        case .failure(let error):
            if case .network(let urlError) = error, urlError.code == .cancelled { return }
            lastSyncError = error
        }
    }

    func refreshIfNeeded() async {
        if labels.isEmpty {
            await loadLabels()
        }
        if threads.isEmpty {
            await loadThreadList()
        }
    }

    func reconcile() async {
        guard !currentHistoryId.isEmpty else { return }
        let result = await withRetry(maxRetries: 2) {
            await self.gmailService.fetchHistory(startHistoryId: self.currentHistoryId)
        }
        switch result {
        case .success(let history):
            currentHistoryId = history.historyId
            let changedIds = Set(
                (history.history ?? []).flatMap { record in
                    ((record.messagesAdded?.map { $0.message.threadId }) ?? []) +
                    ((record.messagesDeleted?.map { $0.message.threadId }) ?? [])
                }
            )
            await withTaskGroup(of: Void.self) { group in
                for threadId in changedIds {
                    group.addTask { await self.loadThread(id: threadId) }
                }
            }
        case .failure(.apiError(400, _)):
            currentHistoryId = ""
            await loadThreadList()
        case .failure(let error):
            lastSyncError = error
        }
    }
}
