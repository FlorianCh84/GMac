import SwiftUI
import WebKit

struct MessageDetailView: View {
    @Environment(SessionStore.self) var store

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
                        MessageBubble(message: message)
                        Divider()
                    }
                }
            }
            .navigationTitle(thread.subject)
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

            if let html = message.bodyHTML {
                EmailWebView(html: html)
                    .frame(minHeight: 200)
                    .padding(.horizontal, 4)
            } else if let plain = message.bodyPlain {
                Text(plain)
                    .font(.body)
                    .padding(.horizontal)
                    .padding(.bottom, 12)
            } else {
                Text(message.snippet)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 12)
            }
        }
    }
}

private struct EmailWebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType != .other {
                return .cancel
            }
            return .allow
        }
    }
}
