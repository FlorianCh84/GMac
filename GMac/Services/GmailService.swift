import Foundation

final class GmailService: GmailServiceProtocol, @unchecked Sendable {
    private let httpClient: any HTTPClientProtocol

    init(httpClient: any HTTPClientProtocol) {
        self.httpClient = httpClient
    }

    func fetchLabels() async -> Result<[GmailLabel], AppError> {
        let request = URLRequest(url: Endpoints.labelsList())
        let result: Result<GmailLabelListResponse, AppError> = await httpClient.send(request)
        return result.map { $0.labels.map { mapLabel($0) } }
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

    func send(message: OutgoingMessage, senderEmail: String) async -> Result<Void, AppError> {
        let raw: String
        do {
            raw = try MIMEBuilder.buildRaw(message: message, from: senderEmail)
        } catch {
            return .failure(.unknown)
        }

        let bodyData: Data
        do {
            let body = SendMessageRequest(raw: raw, threadId: message.replyToThreadId)
            bodyData = try JSONEncoder().encode(body)
        } catch {
            // JSONEncoder ne devrait jamais échouer sur des types Encodable bien formés
            return .failure(.decodingError("JSONEncoder failed: \(error)"))
        }

        var request = URLRequest(url: Endpoints.messageSend())
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        let result: Result<SendMessageResponse, AppError> = await httpClient.send(request)
        return result.map { _ in () }
    }

    func createDraft(message: OutgoingMessage, senderEmail: String) async -> Result<DraftMessage, AppError> {
        do {
            let raw = try MIMEBuilder.buildRaw(message: message, from: senderEmail)
            let body = CreateDraftRequest(message: .init(raw: raw, threadId: message.replyToThreadId))
            var request = URLRequest(url: Endpoints.draftCreate())
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
            return await httpClient.send(request)
        } catch {
            return .failure(.unknown)
        }
    }

    func updateDraft(id: String, message: OutgoingMessage, senderEmail: String) async -> Result<DraftMessage, AppError> {
        do {
            let raw = try MIMEBuilder.buildRaw(message: message, from: senderEmail)
            let body = CreateDraftRequest(message: .init(raw: raw, threadId: message.replyToThreadId))
            var request = URLRequest(url: Endpoints.draftUpdate(id: id))
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
            return await httpClient.send(request)
        } catch {
            return .failure(.unknown)
        }
    }

    func deleteDraft(id: String) async -> Result<Void, AppError> {
        var request = URLRequest(url: Endpoints.draftDelete(id: id))
        request.httpMethod = "DELETE"
        struct EmptyResponse: Decodable {}
        let result: Result<EmptyResponse, AppError> = await httpClient.send(request)
        return result.map { _ in () }
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
