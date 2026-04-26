import SwiftUI
import WebKit

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
                VStack(alignment: .leading, spacing: 0) {
                    Text(thread.subject)
                        .font(.title2.bold())
                        .padding()

                    Divider()

                    ForEach(thread.messages) { message in
                        MessageBubble(message: message, thread: thread, onReply: onReply, onSaveToDrive: onSaveToDrive)
                        Divider()
                    }
                }
            }
            .navigationTitle(thread.subject)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("IA", systemImage: "sparkles") {
                        isAIPanelOpen = true
                    }
                    .disabled(store.selectedThreadId == nil)
                }
            }
            .sheet(isPresented: $isAIPanelOpen) {
                AIAssistantPanel(
                    vm: AIAssistantViewModel(provider: appEnv.aiSettings.activeProvider()),
                    thread: thread,
                    senderEmail: store.senderEmail,
                    sentMessages: [],
                    onInject: { text in
                        isAIPanelOpen = false
                        onReply(thread, thread.messages.last ?? thread.messages[0])
                    }
                )
            }
        } else {
            ContentUnavailableView(
                "Selectionnez un message",
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
                    // Rendu HTML via WebKit
                    EmailWebView(html: html)
                        .frame(minHeight: 200)
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
                            Button("Drive") {
                                onSaveToDrive?(message.id, ref)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
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
}

private struct EmailWebView: NSViewRepresentable {
    let html: String

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

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType != .other {
                return .cancel
            }
            return .allow
        }
    }
}
