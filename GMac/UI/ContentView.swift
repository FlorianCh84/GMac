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
    @State private var cachedAIProvider: (any LLMProvider)? = nil
    @State private var isDriveFolderPickerOpen = false
    @State private var pendingDriveUpload: (messageId: String, ref: MessageAttachmentRef)? = nil

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            ThreadListView()
        } detail: {
            if isComposing {
                // Composition directement dans le panneau de détail
                ComposeViewShim(
                    replyToThreadId: composeReplyToThreadId,
                    replyToMessageId: composeReplyToMessageId,
                    prefilledTo: composePrefilledTo,
                    prefilledSubject: composePrefilledSubject,
                    senderEmail: store.senderEmail,
                    gmailService: store.gmailService,
                    driveService: appEnv.driveService,
                    settingsService: appEnv.settingsService,
                    aiSettings: appEnv.aiSettings,
                    contextThread: composeReplyToThreadId.flatMap { id in store.threads.first { $0.id == id } },
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            resetCompose()
                            isComposing = false
                        }
                    }
                )
                .transition(.opacity)
            } else {
                MessageDetailView(onReply: startReply, onSaveToDrive: saveToDrive)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isComposing)
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
        .sheet(isPresented: $isDriveFolderPickerOpen) {
            if let pending = pendingDriveUpload {
                DriveFolderPickerView(
                    driveService: appEnv.driveService,
                    onSelect: { folder in
                        isDriveFolderPickerOpen = false
                        Task { @MainActor in
                            let fetch = await store.gmailService.fetchAttachment(
                                messageId: pending.messageId,
                                attachmentId: pending.ref.attachmentId
                            )
                            guard case .success(let data) = fetch else { return }
                            let upload = await appEnv.driveService.uploadFile(
                                data: data,
                                filename: pending.ref.filename,
                                mimeType: pending.ref.mimeType,
                                parentId: folder?.id
                            )
                            if case .success = upload { driveUploadSuccess = true }
                        }
                    },
                    onDismiss: {
                        isDriveFolderPickerOpen = false
                        pendingDriveUpload = nil
                    }
                )
            }
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
                        Button(action: { store.lastSyncError = nil }) {
                            Image(systemName: "xmark")
                                .font(.caption)
                        }
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
        pendingDriveUpload = (messageId: messageId, ref: ref)
        isDriveFolderPickerOpen = true
    }

    private func startNewMessage() {
        cachedAIProvider = appEnv.aiSettings.activeProvider()  // snapshot au moment d'ouvrir
        composeReplyToThreadId = nil
        composeReplyToMessageId = nil
        composePrefilledTo = ""
        composePrefilledSubject = ""
        store.selectedThreadId = nil  // désélectionne le thread courant
        withAnimation(.easeInOut(duration: 0.2)) { isComposing = true }
    }

    private func startReply(thread: EmailThread, message: EmailMessage) {
        cachedAIProvider = appEnv.aiSettings.activeProvider()  // snapshot au moment d'ouvrir
        composeReplyToThreadId = thread.id
        composeReplyToMessageId = message.id
        composePrefilledTo = message.from
        composePrefilledSubject = message.subject.hasPrefix("Re:") ? message.subject : "Re: \(message.subject)"
        withAnimation(.easeInOut(duration: 0.2)) { isComposing = true }
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
