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

    private static let lastSenderKey = "gmac.lastSelectedSender"

    var selectedSenderEmail: String = UserDefaults.standard.string(forKey: ComposeViewModel.lastSenderKey) ?? "" {
        didSet {
            UserDefaults.standard.set(selectedSenderEmail, forKey: ComposeViewModel.lastSenderKey)
        }
    }

    var aiSettings: AISettingsViewModel? = nil
    var contextThread: EmailThread? = nil
    var scheduledSendManager: ScheduledSendManager? = nil

    var sendState: SendState = .idle

    var isValid: Bool {
        let hasRecipient = !to.trimmingCharacters(in: .whitespaces).isEmpty
        let hasSubject = !subject.trimmingCharacters(in: .whitespaces).isEmpty
        let hasBody = !body.trimmingCharacters(in: .whitespaces).isEmpty || !bodyHTML.trimmingCharacters(in: .whitespaces).isEmpty
        let hasValidSchedule = !isScheduled || scheduledDate >= Date().addingTimeInterval(300)
        return hasRecipient && hasSubject && hasBody && hasValidSchedule
    }

    private let gmailService: any GmailServiceProtocol

    init(gmailService: any GmailServiceProtocol) {
        self.gmailService = gmailService
    }

    func startSend(countdownDuration: TimeInterval = 3.0) async {
        guard isValid else { return }
        if isScheduled, scheduledDate < Date().addingTimeInterval(300) {
            sendState = .failed(.apiError(statusCode: 400, message: "L'heure d'envoi doit être au moins 5 minutes dans le futur"))
            return
        }

        let toList = to.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let ccList = cc.isEmpty ? [] : cc.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let sender = selectedSenderEmail.isEmpty ? senderEmail : selectedSenderEmail

        let message = OutgoingMessage(
            to: toList, cc: ccList,
            subject: subject,
            body: bodyHTML.isEmpty ? body : bodyHTML,
            isHTML: !bodyHTML.isEmpty,
            replyToThreadId: replyToThreadId,
            replyToMessageId: replyToMessageId,
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

        if isScheduled {
            let result = await gmailService.createDraft(message: message, senderEmail: sender)
            switch result {
            case .success(let draft):
                let entry = ScheduledSendEntry(
                    draftId: draft.id,
                    scheduledDate: scheduledDate,
                    subject: subject,
                    to: toList,
                    threadId: replyToThreadId,
                    senderEmail: sender
                )
                scheduledSendManager?.schedule(entry: entry)
                clearComposer()
                sendState = .idle
            case .failure(let error):
                sendState = .failed(error)
            }
        } else {
            let result = await gmailService.send(message: message, senderEmail: sender)
            switch result {
            case .success:
                clearComposer()
                sendState = .idle
            case .failure(let error):
                sendState = .failed(error)
            }
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

        var signature: String? = nil
        if case .success(let aliases) = result, !aliases.isEmpty {
            availableSenders = aliases
            let primary = aliases.first(where: { $0.isPrimary == true }) ?? aliases[0]
            let savedEmail = UserDefaults.standard.string(forKey: ComposeViewModel.lastSenderKey) ?? ""
            let resolvedSender = aliases.first(where: { $0.sendAsEmail == savedEmail }) ?? primary
            selectedSenderEmail = resolvedSender.sendAsEmail
            signature = resolvedSender.signature
        }

        guard bodyHTML.isEmpty else { return }
        bodyHTML = buildInitialBody(signature: signature)
        body = bodyHTML
    }

    private func buildInitialBody(signature: String?) -> String {
        var html = "<br>"

        if let sig = signature, !sig.isEmpty {
            html += "<br><hr><div style='color:#666;font-size:13px;'>\(sig)</div>"
        }

        if let thread = contextThread {
            html += quotedThreadHTML(thread: thread)
        }

        return html
    }

    private func quotedThreadHTML(thread: EmailThread) -> String {
        let msg: EmailMessage?
        if let msgId = replyToMessageId {
            msg = thread.messages.first(where: { $0.id == msgId }) ?? thread.messages.last
        } else {
            msg = thread.messages.last
        }
        guard let message = msg else { return "" }

        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "fr_FR")
        let dateStr = formatter.string(from: message.date)

        let originalBody: String
        if let html = message.bodyHTML, html.contains("<") {
            originalBody = html
        } else {
            let plain = (message.bodyPlain ?? message.snippet)
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            originalBody = "<div style='white-space:pre-wrap'>\(plain)</div>"
        }

        let from = message.from
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return """
        <br><br>
        <div style="margin-top:8px;padding-left:12px;border-left:3px solid #ccc;color:#555">
          <p style="margin:0 0 6px 0;font-size:12px"><b>\(from)</b> a écrit le \(dateStr) :</p>
          \(originalBody)
        </div>
        """
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
