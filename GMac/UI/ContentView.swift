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
    @State private var driveUploadSuccess = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            ThreadListView()
        } detail: {
            MessageDetailView(onReply: startReply, onSaveToDrive: saveToDrive)
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
                driveService: appEnv.driveService,
                onDismiss: { isComposing = false }
            )
        }
        .overlay(alignment: .top) {
            if driveUploadSuccess {
                Label("Sauvegardé dans Drive", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.green.opacity(0.9), in: .capsule)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(2))
                        driveUploadSuccess = false
                    }
            }
        }
        .animation(.easeInOut, value: driveUploadSuccess)
        .task {
            await store.loadLabels()
            await store.loadThreadList()
        }
    }

    private func saveToDrive(messageId: String, ref: MessageAttachmentRef) {
        Task { @MainActor in
            let fetch = await store.gmailService.fetchAttachment(messageId: messageId, attachmentId: ref.attachmentId)
            guard case .success(let data) = fetch else { return }
            let upload = await appEnv.driveService.uploadFile(data: data, filename: ref.filename, mimeType: ref.mimeType)
            if case .success = upload { driveUploadSuccess = true }
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
