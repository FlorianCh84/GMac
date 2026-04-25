import SwiftUI

struct ComposeView: View {
    @State private var vm: ComposeViewModel
    @State private var isShowingDrivePicker = false
    @State private var isAIOpen = false
    @State private var driveDownloadError: String? = nil
    let driveService: any DriveServiceProtocol
    let onDismiss: () -> Void

    init(vm: ComposeViewModel, driveService: any DriveServiceProtocol, onDismiss: @escaping () -> Void) {
        self._vm = State(initialValue: vm)
        self.driveService = driveService
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(spacing: 0) {
            // --- Colonne principale : formulaire de composition ---
            VStack(spacing: 0) {
                headerBar
                Divider()
                fieldsSection
                Divider()
                bodySection
            }
            .frame(minWidth: 420, maxWidth: .infinity)

            // --- Panneau IA : slide depuis la droite ---
            if isAIOpen, let provider = vm.aiProvider {
                Divider()
                aiPanel(provider: provider)
                    .frame(width: 380)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal:   .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isAIOpen)
        .frame(minHeight: 620)
        .sheet(isPresented: $isShowingDrivePicker) {
            DrivePickerView(
                vm: DrivePickerViewModel(driveService: driveService),
                onSelect: { file in
                    isShowingDrivePicker = false
                    Task { @MainActor in
                        let result = await downloadDriveFile(file: file)
                        switch result {
                        case .success(let data):
                            vm.attachments.append(Attachment(id: UUID(), filename: file.name, mimeType: file.mimeType, data: data))
                        case .failure(let error):
                            driveDownloadError = "Impossible de télécharger \(file.name) : \(driveErrorDesc(error))"
                        }
                    }
                },
                onDismiss: { isShowingDrivePicker = false }
            )
        }
        .alert("Erreur Drive", isPresented: Binding(
            get: { driveDownloadError != nil },
            set: { if !$0 { driveDownloadError = nil } }
        )) {
            Button("OK") { driveDownloadError = nil }
        } message: {
            Text(driveDownloadError ?? "")
        }
    }

    @ViewBuilder
    private func aiPanel(provider: any LLMProvider) -> some View {
        let thread = vm.contextThread ?? makeContextThread()
        VStack(spacing: 0) {
            // Header du panneau IA
            HStack {
                Label("Assistant IA", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Button(action: { withAnimation(.easeInOut(duration: 0.25)) { isAIOpen = false } }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.regularMaterial)
            Divider()

            // Panneau IA sans son propre header (on a le nôtre)
            AIAssistantPanel(
                vm: AIAssistantViewModel(provider: provider),
                thread: thread,
                senderEmail: vm.selectedSenderEmail.isEmpty ? vm.senderEmail : vm.selectedSenderEmail,
                sentMessages: [],
                onInject: { text in
                    let signature = extractSignature(from: vm.bodyHTML)
                    vm.bodyHTML = text + (signature.isEmpty ? "" : "<br><br>\(signature)")
                    vm.body = vm.bodyHTML
                    // Panneau reste ouvert pour affinage
                }
            )
        }
        .background(.regularMaterial)
    }

    private func downloadDriveFile(file: DriveFile) async -> Result<Data, AppError> {
        // Les fichiers Google Workspace (Docs, Sheets, Slides) nécessitent un export
        let googleMimeTypes: [String: String] = [
            "application/vnd.google-apps.document": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "application/vnd.google-apps.spreadsheet": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "application/vnd.google-apps.presentation": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
            "application/vnd.google-apps.drawing": "image/png"
        ]
        if let exportMime = googleMimeTypes[file.mimeType] {
            return await driveService.exportGoogleFile(id: file.id, mimeType: exportMime)
        }
        return await driveService.downloadFile(id: file.id)
    }

    private func driveErrorDesc(_ error: AppError) -> String {
        switch error {
        case .apiError(let code, let msg): return "Erreur \(code): \(msg)"
        case .offline: return "Pas de connexion"
        case .tokenExpired: return "Session expirée"
        default: return "\(error)"
        }
    }

    private func makeContextThread() -> EmailThread {
        // Crée un thread minimal depuis le contenu du composeur (pour nouveau message)
        let msg = EmailMessage(
            id: "draft", threadId: "draft",
            snippet: vm.body.isEmpty ? vm.subject : String(vm.body.prefix(100)),
            subject: vm.subject,
            from: vm.selectedSenderEmail.isEmpty ? vm.senderEmail : vm.selectedSenderEmail,
            to: [vm.to],
            date: Date(),
            bodyHTML: vm.bodyHTML.isEmpty ? nil : vm.bodyHTML,
            bodyPlain: vm.body.isEmpty ? nil : vm.body,
            labelIds: [],
            isUnread: false,
            attachmentRefs: []
        )
        return EmailThread(id: "draft", snippet: vm.subject, historyId: "", messages: [msg])
    }

    private func extractSignature(from html: String) -> String {
        // Extrait la signature après <hr> si elle existe
        if let hrRange = html.range(of: "<hr>") {
            return String(html[hrRange.lowerBound...])
        }
        return ""
    }

    private var headerBar: some View {
        HStack {
            Button("Annuler") { onDismiss() }
                .disabled(!isIdle)
            Spacer()
            Text(vm.replyToThreadId != nil ? "Répondre" : "Nouveau message")
                .font(.headline)
            Spacer()
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) { isAIOpen.toggle() }
            }) {
                Label("IA", systemImage: "sparkles")
            }
            .buttonStyle(.bordered)
            .tint(isAIOpen ? .blue : nil)
            .disabled(vm.aiProvider == nil)
            SendButton(
                sendState: vm.sendState,
                isValid: vm.isValid,
                onSend: { Task { @MainActor in await vm.startSend() } },
                onCancel: { vm.cancelSend() }
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var fieldsSection: some View {
        VStack(spacing: 0) {
            // Sélecteur expéditeur (si plusieurs comptes)
            if vm.availableSenders.count > 1 {
                HStack(spacing: 8) {
                    Text("De")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                    Picker("", selection: $vm.selectedSenderEmail) {
                        ForEach(vm.availableSenders, id: \.sendAsEmail) { alias in
                            Text(alias.displayName.map { "\($0) <\(alias.sendAsEmail)>" } ?? alias.sendAsEmail)
                                .tag(alias.sendAsEmail)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .onChange(of: vm.selectedSenderEmail) {
                        if let alias = vm.availableSenders.first(where: { $0.sendAsEmail == vm.selectedSenderEmail }) {
                            vm.selectSender(alias)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                Divider().padding(.leading, 56)
            }

            ComposeField(label: "À", text: $vm.to)
            Divider().padding(.leading, 56)
            ComposeField(label: "Cc", text: $vm.cc)
            Divider().padding(.leading, 56)
            ComposeField(label: "Objet", text: $vm.subject)

            // Toggle différé
            Divider().padding(.leading, 56)
            HStack(spacing: 8) {
                Text("Différé")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
                Toggle("", isOn: $vm.isScheduled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                if vm.isScheduled {
                    DatePicker("", selection: $vm.scheduledDate, in: Date()...)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
    }

    private var bodySection: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Drive", systemImage: "externaldrive") {
                    isShowingDrivePicker = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            RichTextEditor(html: $vm.bodyHTML, placeholder: "Rédigez votre message…")
                .frame(minHeight: 240)
                .onChange(of: vm.bodyHTML) {
                    // Synchroniser bodyHTML → body (texte brut pour les previews)
                    vm.body = vm.bodyHTML
                }
                .dropDestination(for: URL.self) { urls, _ in
                    for url in urls {
                        guard url.isFileURL,
                              let data = try? Data(contentsOf: url) else { continue }
                        let filename = url.lastPathComponent
                        let mimeType = Self.mimeType(for: url)
                        vm.attachments.append(Attachment(id: UUID(), filename: filename, mimeType: mimeType, data: data))
                    }
                    return !urls.isEmpty
                }

            if !vm.attachments.isEmpty {
                attachmentsList
            }
        }
    }

    private var attachmentsList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.attachments) { attachment in
                    AttachmentChip(attachment: attachment) {
                        vm.attachments.removeAll { $0.id == attachment.id }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "txt": return "text/plain"
        case "doc", "docx": return "application/msword"
        case "xls", "xlsx": return "application/vnd.ms-excel"
        case "zip": return "application/zip"
        default: return "application/octet-stream"
        }
    }

    private var isIdle: Bool {
        guard case .idle = vm.sendState else { return false }
        return true
    }
}

private struct AttachmentChip: View {
    let attachment: Attachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "paperclip")
                .font(.caption)
            Text(attachment.filename)
                .font(.caption)
                .lineLimit(1)
            Text(attachment.sizeDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: .capsule)
    }
}

private struct ComposeField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
            TextField("", text: $text)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
