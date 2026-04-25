import Foundation
import Observation

enum SendState: Sendable {
    case idle
    case countdown(progress: Double)
    case sending
    case failed(AppError)
}

@Observable
@MainActor
final class ComposeViewModel {
    var to: String = ""
    var cc: String = ""
    var subject: String = ""
    var body: String = ""
    var bodyHTML: String = ""
    var replyToThreadId: String? = nil
    var replyToMessageId: String? = nil
    var senderEmail: String = ""
    var attachments: [Attachment] = []
    var isScheduled: Bool = false
    var scheduledDate: Date = Date().addingTimeInterval(3600)

    var availableSenders: [SendAsAlias] = []
    var selectedSenderEmail: String = ""

    var aiProvider: (any LLMProvider)? = nil
    var contextThread: EmailThread? = nil  // thread original si réponse

    var sendState: SendState = .idle

    var isValid: Bool {
        !to.trimmingCharacters(in: .whitespaces).isEmpty &&
        !subject.trimmingCharacters(in: .whitespaces).isEmpty &&
        (!body.trimmingCharacters(in: .whitespaces).isEmpty || !bodyHTML.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private let gmailService: any GmailServiceProtocol

    init(gmailService: any GmailServiceProtocol) {
        self.gmailService = gmailService
    }

    func startSend(countdownDuration: TimeInterval = 3.0) async {
        guard isValid else { return }

        // Snapshot avant le countdown — garantit que le mail envoyé correspond exactement
        // à ce que l'utilisateur a confirmé en cliquant Envoyer, même s'il modifie le texte pendant les 3s.
        let message = OutgoingMessage(
            to: to.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            cc: cc.isEmpty ? [] : cc.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            subject: subject,
            body: bodyHTML.isEmpty ? body : bodyHTML,
            isHTML: !bodyHTML.isEmpty,
            replyToThreadId: replyToThreadId,
            replyToMessageId: replyToMessageId,
            scheduledDate: isScheduled ? scheduledDate : nil,
            attachments: attachments
        )

        sendState = .countdown(progress: 0.0)

        if countdownDuration > 0 {
            let steps = 30
            let stepDuration = countdownDuration / Double(steps)
            do {
                for step in 1...steps {
                    guard case .countdown = sendState else { return }
                    sendState = .countdown(progress: Double(step) / Double(steps))
                    try await Task.sleep(for: .seconds(stepDuration))
                }
            } catch {
                sendState = .idle
                return
            }
        }

        guard case .countdown = sendState else { return }

        sendState = .sending
        let result = await gmailService.send(message: message, senderEmail: selectedSenderEmail.isEmpty ? senderEmail : selectedSenderEmail)

        switch result {
        case .success:
            clearComposer()
            sendState = .idle
        case .failure(let error):
            sendState = .failed(error)
        }
    }

    func cancelSend() {
        sendState = .idle
    }

    func resetAfterFailure() {
        sendState = .idle
    }

    func loadSenders(settingsService: any GmailSettingsServiceProtocol) async {
        let result = await settingsService.fetchSendAsList()
        guard case .success(let aliases) = result, !aliases.isEmpty else { return }
        availableSenders = aliases
        // Sélectionner l'alias primaire par défaut
        let primary = aliases.first(where: { $0.isPrimary == true }) ?? aliases[0]
        selectedSenderEmail = primary.sendAsEmail
        // Injecter la signature comme contenu initial si le body est vide
        if bodyHTML.isEmpty, let sig = primary.signature, !sig.isEmpty {
            bodyHTML = "<br><br><hr><div style='color:#666;font-size:13px;'>\(sig)</div>"
            body = bodyHTML
        }
    }

    func selectSender(_ alias: SendAsAlias) {
        selectedSenderEmail = alias.sendAsEmail
        // Mettre à jour la signature si le body ne contient pas encore de contenu utilisateur
        if let sig = alias.signature, !sig.isEmpty {
            let sigHTML = "<br><br><hr><div style='color:#666;font-size:13px;'>\(sig)</div>"
            if bodyHTML.isEmpty || bodyHTML == sigHTML {
                bodyHTML = sigHTML
                body = bodyHTML
            }
        }
    }

    private func clearComposer() {
        to = ""
        cc = ""
        subject = ""
        body = ""
        bodyHTML = ""
        attachments = []
        replyToThreadId = nil
        replyToMessageId = nil
        isScheduled = false
        scheduledDate = Date().addingTimeInterval(3600)
    }
}
