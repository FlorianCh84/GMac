import SwiftUI

// AIAssistantPanel complet — implémenté après les tests passent
struct AIAssistantPanel: View {
    @State private var vm: AIAssistantViewModel
    let thread: EmailThread
    let senderEmail: String
    let sentMessages: [EmailMessage]
    let onInject: (String) -> Void

    init(vm: AIAssistantViewModel, thread: EmailThread, senderEmail: String, sentMessages: [EmailMessage], onInject: @escaping (String) -> Void) {
        _vm = State(initialValue: vm)
        self.thread = thread; self.senderEmail = senderEmail
        self.sentMessages = sentMessages; self.onInject = onInject
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Assistant IA").font(.headline).padding()
            Divider()
            Text("En construction — Sprint 5").foregroundStyle(.secondary).padding()
        }
        .frame(minWidth: 300)
    }
}
