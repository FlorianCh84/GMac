import SwiftUI

struct ComposeViewShim: View {
    let replyToThreadId: String?
    let replyToMessageId: String?
    let prefilledTo: String
    let prefilledSubject: String
    let senderEmail: String
    let gmailService: any GmailServiceProtocol
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
        onDismiss: @escaping () -> Void
    ) {
        self.replyToThreadId = replyToThreadId
        self.replyToMessageId = replyToMessageId
        self.prefilledTo = prefilledTo
        self.prefilledSubject = prefilledSubject
        self.senderEmail = senderEmail
        self.gmailService = gmailService
        self.onDismiss = onDismiss

        let initialVM = ComposeViewModel(gmailService: gmailService)
        initialVM.replyToThreadId = replyToThreadId
        initialVM.replyToMessageId = replyToMessageId
        initialVM.to = prefilledTo
        initialVM.subject = prefilledSubject
        initialVM.senderEmail = senderEmail
        self._vm = State(initialValue: initialVM)
    }

    var body: some View {
        ComposeView(vm: vm, onDismiss: onDismiss)
    }
}
