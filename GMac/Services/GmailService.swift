import Foundation

final class GmailService: GmailServiceProtocol, @unchecked Sendable {
    private let httpClient: any HTTPClientProtocol

    init(httpClient: any HTTPClientProtocol) {
        self.httpClient = httpClient
    }

    func fetchLabels() async -> Result<[GmailLabel], AppError> {
        var allLabels: [GmailLabel] = []
        var pageToken: String? = nil
        repeat {
            let request = URLRequest(url: Endpoints.labelsList(pageToken: pageToken))
            let result: Result<GmailLabelListResponse, AppError> = await httpClient.send(request)
            switch result {
            case .success(let response):
                allLabels += response.labels.map { mapLabel($0) }
                pageToken = response.nextPageToken
            case .failure(let error):
                return .failure(error)
            }
        } while pageToken != nil
        return .success(allLabels)
    }

    func fetchThreadList(labelId: String, pageToken: String? = nil) async -> Result<[GmailThreadRef], AppError> {
        let request = URLRequest(url: Endpoints.threadsList(labelIds: [labelId], pageToken: pageToken))
        let result: Result<GmailThreadListResponse, AppError> = await httpClient.send(request)
        return result.map { $0.threads ?? [] }
    }

    func fetchThread(id: String) async -> Result<EmailThread, AppError> {
        let request = URLRequest(url: Endpoints.threadGet(id: id))
        let result: Result<GmailAPIThread, AppError> = await httpClient.send(request)
        return result.map { mapThread($0) }
    }

    func archiveThread(id: String) async -> Result<Void, AppError> {
        var request = URLRequest(url: Endpoints.threadModify(id: id))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["removeLabelIds": ["INBOX"]])

        struct EmptyResponse: Decodable {}
        let result: Result<EmptyResponse, AppError> = await httpClient.send(request)
        return result.map { _ in () }
    }

    func send(message: OutgoingMessage) async -> Result<Void, AppError> {
        return .failure(.unknown)
    }

    func fetchHistory(startHistoryId: String) async -> Result<GmailHistoryListResponse, AppError> {
        let request = URLRequest(url: Endpoints.historyList(startHistoryId: startHistoryId))
        return await httpClient.send(request)
    }

    // MARK: - Private mapping

    private func mapLabel(_ api: GmailAPILabel) -> GmailLabel {
        GmailLabel(
            id: api.id,
            name: api.name,
            type: api.type == "system" ? .system : .user,
            messagesUnread: api.messagesUnread
        )
    }

    private func mapThread(_ api: GmailAPIThread) -> EmailThread {
        EmailThread(
            id: api.id,
            snippet: api.snippet,
            historyId: api.historyId,
            messages: (api.messages ?? []).map { mapMessage($0) }
        )
    }

    private func mapMessage(_ api: GmailAPIMessage) -> EmailMessage {
        let headers = api.payload?.headers
        let (html, plain) = MIMEParser.extractBody(from: api.payload)
        return EmailMessage(
            id: api.id,
            threadId: api.threadId,
            snippet: api.snippet ?? "",
            subject: MIMEParser.header("Subject", from: headers) ?? "(Sans sujet)",
            from: MIMEParser.header("From", from: headers) ?? "",
            to: (MIMEParser.header("To", from: headers) ?? "")
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty },
            date: MIMEParser.parseDate(api.internalDate),
            bodyHTML: html,
            bodyPlain: plain,
            labelIds: api.labelIds ?? [],
            isUnread: api.labelIds?.contains("UNREAD") ?? false
        )
    }
}
