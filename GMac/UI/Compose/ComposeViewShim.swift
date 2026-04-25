import SwiftUI

struct ComposeViewShim: View {
    let replyToThreadId: String?
    let replyToMessageId: String?
    let prefilledTo: String
    let prefilledSubject: String
    let senderEmail: String
    let gmailService: any GmailServiceProtocol
    let driveService: any DriveServiceProtocol
    let settingsService: any GmailSettingsServiceProtocol
    let aiProvider: (any LLMProvider)?
    let contextThread: EmailThread?
    let onDismiss: () -> Void

    @State private var vm: ComposeViewModel

    @MainActor
    init(
        replyToThreadId: String?,
        replyToMessageId: String?,
        prefilledTo: String,
        prefilledSubject: String,
        senderEmail: String,
        gmailService: any GmailServiceProtocol,
        driveService: any DriveServiceProtocol,
        settingsService: any GmailSettingsServiceProtocol,
        aiProvider: (any LLMProvider)? = nil,
        contextThread: EmailThread? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.replyToThreadId = replyToThreadId
        self.replyToMessageId = replyToMessageId
        self.prefilledTo = prefilledTo
        self.prefilledSubject = prefilledSubject
        self.senderEmail = senderEmail
        self.gmailService = gmailService
        self.driveService = driveService
        self.settingsService = settingsService
        self.aiProvider = aiProvider
        self.contextThread = contextThread
        self.onDismiss = onDismiss

        let initialVM = ComposeViewModel(gmailService: gmailService)
        initialVM.replyToThreadId = replyToThreadId
        initialVM.replyToMessageId = replyToMessageId
        initialVM.to = prefilledTo
        initialVM.subject = prefilledSubject
        initialVM.senderEmail = senderEmail
        initialVM.aiProvider = aiProvider
        initialVM.contextThread = contextThread
        self._vm = State(initialValue: initialVM)
    }

    var body: some View {
        ComposeView(vm: vm, driveService: driveService, onDismiss: onDismiss)
            .task {
                await vm.loadSenders(settingsService: settingsService)
            }
    }
}
