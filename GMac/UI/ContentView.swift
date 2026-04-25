import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) var store
    @Environment(GoogleOAuthManager.self) var oauth
    @Environment(AppEnvironment.self) var appEnv
    @State private var isComposing = false
    @State private var isShowingSettings = false
    @State private var composeReplyToThreadId: String? = nil
    @State private var composeReplyToMessageId: String? = nil
    @State private var composePrefilledTo: String = ""
    @State private var composePrefilledSubject: String = ""

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            ThreadListView()
        } detail: {
            MessageDetailView(onReply: startReply)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nouveau", systemImage: "square.and.pencil") {
                    startNewMessage()
                }
            }
            ToolbarItem(placement: .navigation) {
                Button("Déconnexion", systemImage: "rectangle.portrait.and.arrow.right") {
                    oauth.logout()
                }
            }
            ToolbarItem(placement: .navigation) {
                Button("Paramètres", systemImage: "gear") {
                    isShowingSettings = true
                }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            settingsSheet
        }
        .sheet(isPresented: $isComposing, onDismiss: resetCompose) {
            ComposeViewShim(
                replyToThreadId: composeReplyToThreadId,
                replyToMessageId: composeReplyToMessageId,
                prefilledTo: composePrefilledTo,
                prefilledSubject: composePrefilledSubject,
                senderEmail: store.senderEmail,
                gmailService: store.gmailService,
                onDismiss: { isComposing = false }
            )
        }
        .task {
            await store.loadLabels()
            await store.loadThreadList()
        }
    }

    private func startNewMessage() {
        composeReplyToThreadId = nil
        composeReplyToMessageId = nil
        composePrefilledTo = ""
        composePrefilledSubject = ""
        isComposing = true
    }

    private func startReply(thread: EmailThread, message: EmailMessage) {
        composeReplyToThreadId = thread.id
        composeReplyToMessageId = message.id
        composePrefilledTo = message.from
        composePrefilledSubject = message.subject.hasPrefix("Re:") ? message.subject : "Re: \(message.subject)"
        isComposing = true
    }

    private func resetCompose() {
        composeReplyToThreadId = nil
        composeReplyToMessageId = nil
    }

    private var settingsSheet: some View {
        SettingsView(
            gmailService: store.gmailService,
            settingsService: appEnv.settingsService
        )
    }
}
