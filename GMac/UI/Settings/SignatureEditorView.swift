import SwiftUI
import WebKit

struct SignatureEditorView: View {
    @State var vm: SignatureEditorViewModel
    @State private var showSavedConfirmation = false
    @State private var confirmationTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if vm.isLoading {
                ProgressView("Chargement de la signature…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SignatureWebEditor(html: $vm.currentHTML)
                    .frame(minHeight: 300)
            }
        }
        .task { await vm.load() }
        .onChange(of: vm.saveSuccess) {
            if vm.saveSuccess {
                showSavedConfirmation = true
                vm.saveSuccess = false
                confirmationTask?.cancel()
                confirmationTask = Task {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    showSavedConfirmation = false
                }
            }
        }
        .onDisappear { confirmationTask?.cancel() }
        .alert("Erreur", isPresented: Binding(
            get: { vm.lastError != nil },
            set: { if !$0 { vm.lastError = nil } }
        )) {
            Button("OK") { vm.lastError = nil }
        } message: {
            Text("La signature n'a pas pu être sauvegardée.")
        }
    }

    private var toolbar: some View {
        HStack {
            if vm.aliases.count > 1 {
                Picker("Adresse", selection: Binding(
                    get: { vm.selectedAlias?.sendAsEmail ?? "" },
                    set: { email in
                        if let alias = vm.aliases.first(where: { $0.sendAsEmail == email }) {
                            vm.selectAlias(alias)
                        }
                    }
                )) {
                    ForEach(vm.aliases, id: \.sendAsEmail) { alias in
                        Text(alias.sendAsEmail).tag(alias.sendAsEmail)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 280)
            }
            Spacer()
            if showSavedConfirmation {
                Label("Sauvegardé", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
            Button(action: { Task { @MainActor in await vm.save() } }) {
                if vm.isSaving { ProgressView().controlSize(.small) }
                else { Text("Sauvegarder") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isSaving)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

struct SignatureWebEditor: NSViewRepresentable {
    @Binding var html: String

    func makeCoordinator() -> Coordinator { Coordinator(html: $html) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.add(context.coordinator, name: "signatureChanged")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        let editableHTML = """
        <!DOCTYPE html>
        <html><head>
        <meta charset="utf-8">
        <style>
          body { font-family: -apple-system, sans-serif; margin: 12px; outline: none; min-height: 200px; }
        </style>
        </head>
        <body contenteditable="true" id="sig">\(html)</body>
        <script>
        document.getElementById('sig').addEventListener('input', function() {
            window.webkit.messageHandlers.signatureChanged.postMessage(this.innerHTML);
        });
        </script>
        </html>
        """
        webView.loadHTMLString(editableHTML, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Le contenu est géré par JS et WKScriptMessageHandler — pas de rechargement
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var html: String
        init(html: Binding<String>) { _html = html }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "signatureChanged", let body = message.body as? String {
                DispatchQueue.main.async {
                    self.html = body
                }
            }
        }
    }
}
