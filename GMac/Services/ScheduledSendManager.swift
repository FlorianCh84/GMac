import Foundation
import UserNotifications

@Observable
@MainActor
final class ScheduledSendManager {
    private var timer: Timer?
    private let gmailService: any GmailServiceProtocol

    var pendingEntries: [ScheduledSendEntry] {
        ScheduledSendStore.load().sorted { $0.scheduledDate < $1.scheduledDate }
    }

    init(gmailService: any GmailServiceProtocol) {
        self.gmailService = gmailService
    }

    func start() {
        requestNotificationPermission()
        Task { await checkAndSendDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { await self?.checkAndSendDue() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func schedule(entry: ScheduledSendEntry) {
        ScheduledSendStore.add(entry)
    }

    func cancel(id: UUID) async {
        guard let entry = ScheduledSendStore.load().first(where: { $0.id == id }) else { return }
        _ = await gmailService.deleteDraft(id: entry.draftId)
        ScheduledSendStore.remove(id: id)
    }

    private func checkAndSendDue() async {
        let due = ScheduledSendStore.load().filter { $0.scheduledDate <= Date() }
        for entry in due {
            let result = await gmailService.sendDraft(id: entry.draftId)
            switch result {
            case .success:
                ScheduledSendStore.remove(id: entry.id)
                notify(subject: entry.subject, to: entry.to.first ?? "")
            case .failure:
                break
            }
        }
    }

    private func notify(subject: String, to: String) {
        let content = UNMutableNotificationContent()
        content.title = "Mail envoyé"
        content.body = "« \(subject) » envoyé à \(to)"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
