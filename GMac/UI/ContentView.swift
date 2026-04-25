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
                settingsService: appEnv.settingsService,
                aiProvider: appEnv.aiSettings.activeProvider(),
                contextThread: composeReplyToThreadId.flatMap { id in store.threads.first { $0.id == id } },
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
        .overlay(alignment: .top) {
            if let error = store.lastSyncError, !store.isLoading {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(apiErrorMessage(error))
                            .font(.caption)
                            .foregroundStyle(.primary)
                        Spacer()
                        Button("Réessayer") {
                            store.lastSyncError = nil
                            Task { await store.loadLabels(); await store.loadThreadList() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button("Copier") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(apiErrorMessage(error), forType: .string)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        Button("×") { store.lastSyncError = nil }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.orange.opacity(0.15))
                    Divider()
                }
            }
        }
        .onAppear { appEnv.syncEngine.start() }
        .onDisappear { appEnv.syncEngine.stop() }
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
            settingsService: appEnv.settingsService,
            aiSettings: appEnv.aiSettings,
            onDismiss: { isShowingSettings = false }
        )
    }

    private func apiErrorMessage(_ error: AppError) -> String {
        switch error {
        case .apiError(let code, let msg):
            if code == 403 { return "API non autorisée (403) — Activez Gmail API dans Google Cloud Console" }
            if code == 401 { return "Session expirée — Déconnectez-vous et reconnectez-vous" }
            if code == 400 { return "Requête invalide (\(code)): \(msg)" }
            return "Erreur API \(code): \(msg)"
        case .offline: return "Pas de connexion internet"
        case .tokenExpired: return "Token expiré — Déconnectez-vous et reconnectez-vous"
        case .dnsError: return "Erreur DNS — Vérifiez votre connexion internet"
        default: return "Erreur: \(error)"
        }
    }
}
