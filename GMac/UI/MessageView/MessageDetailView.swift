import SwiftUI
import WebKit
import AppKit

struct MessageDetailView: View {
    @Environment(SessionStore.self) var store
    @Environment(AppEnvironment.self) var appEnv
    let onReply: (EmailThread, EmailMessage) -> Void
    let onSaveToDrive: ((String, MessageAttachmentRef) -> Void)?

    @State private var isAIPanelOpen = false

    init(onReply: @escaping (EmailThread, EmailMessage) -> Void, onSaveToDrive: ((String, MessageAttachmentRef) -> Void)? = nil) {
        self.onReply = onReply
        self.onSaveToDrive = onSaveToDrive
    }

    var selectedThread: EmailThread? {
        store.threads.first { $0.id == store.selectedThreadId }
    }

    var body: some View {
        if let thread = selectedThread {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text(thread.subject)
                        .font(.title2.bold())
                        .padding()
                    Divider()
                    ForEach(thread.messages) { message in
                        MessageBubble(message: message, thread: thread, onReply: onReply, onSaveToDrive: onSaveToDrive)
                        Divider()
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(thread.subject)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("IA", systemImage: "sparkles") { isAIPanelOpen = true }
                }
            }
            .sheet(isPresented: $isAIPanelOpen) {
                AIAssistantPanel(
                    vm: AIAssistantViewModel(provider: appEnv.aiSettings.activeProvider()),
                    thread: thread,
                    senderEmail: store.senderEmail,
                    sentMessages: [],
                    onInject: { _ in
                        isAIPanelOpen = false
                        onReply(thread, thread.messages.last ?? thread.messages[0])
                    }
                )
            }
        } else {
            ContentUnavailableView(
                "Sélectionnez un message",
                systemImage: "envelope",
                description: Text("Choisissez un thread dans la liste")
            )
        }
    }
}

private struct MessageBubble: View {
    let message: EmailMessage
    let thread: EmailThread
    let onReply: (EmailThread, EmailMessage) -> Void
    let onSaveToDrive: ((String, MessageAttachmentRef) -> Void)?
    @Environment(SessionStore.self) var store
    @State private var webViewHeight: CGFloat = 200  // hauteur mesurée après chargement HTML

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(message.from)
                    .font(.headline)
                Spacer()
                Text(message.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            if let rawHTML = message.bodyHTML {
                // Si le "HTML" ne contient pas de balises, tenter un second décodage base64
                let html: String = rawHTML.contains("<") ? rawHTML :
                    (MIMEParser.decodeBase64(rawHTML) ?? rawHTML)
                if html.contains("<") {
                    // WKWebView mesure sa hauteur réelle via JS après chargement
                    EmailWebView(html: html, height: $webViewHeight)
                        .frame(height: max(200, webViewHeight))
                        .padding(.horizontal, 4)
                } else {
                    Text(html)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                }
            } else if let content = message.bodyPlain {
                // Texte brut (ou HTML mal parsé sans balises)
                Text(content)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.horizontal)
                    .padding(.bottom, 12)
            } else {
                Text(message.snippet)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 12)
            }

            if !message.attachmentRefs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(message.attachmentRefs, id: \.attachmentId) { ref in
                        HStack {
                            Image(systemName: "paperclip").foregroundStyle(.secondary)
                            Text(ref.filename).font(.caption)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(ref.size), countStyle: .file))
                                .font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Button(action: {
                                Task { @MainActor in
                                    await saveAttachmentToMac(messageId: message.id, ref: ref)
                                }
                            }) {
                                Image(systemName: "arrow.down.to.line")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .help("Enregistrer sur Mac")
                            Button("Drive") {
                                onSaveToDrive?(message.id, ref)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .help("Enregistrer dans Google Drive")
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            HStack {
                Spacer()
                Button("Répondre") {
                    onReply(thread, message)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }

    private func saveAttachmentToMac(messageId: String, ref: MessageAttachmentRef) async {
        let fetchResult = await store.gmailService.fetchAttachment(messageId: messageId, attachmentId: ref.attachmentId)
        guard case .success(let data) = fetchResult else { return }
        await MainActor.run {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = ref.filename
            panel.canCreateDirectories = true
            panel.title = "Enregistrer la pièce jointe"
            if panel.runModal() == .OK, let url = panel.url {
                do {
                    try data.write(to: url)
                } catch {
                    // Silencieux — les erreurs d'écriture sont rares
                }
            }
        }
    }
}

private struct EmailWebView: NSViewRepresentable {
    let html: String
    @Binding var height: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.preferences.isElementFullscreenEnabled = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?
        @Binding var height: CGFloat

        init(height: Binding<CGFloat>) { _height = height }

        // Après chargement, mesurer la hauteur réelle du contenu HTML
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                if let h = result as? Double, h > 0 {
                    DispatchQueue.main.async { self.height = CGFloat(h) }
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType != .other {
                return .cancel
            }
            return .allow
        }
    }
}
