// swiftlint:disable line_length
import SwiftUI
import WebKit

struct RichTextEditor: NSViewRepresentable {
    @Binding var html: String
    var placeholder: String = "Rédigez votre message…"

    func makeCoordinator() -> Coordinator { Coordinator(html: $html) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.add(context.coordinator, name: "contentChanged")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(editorHTML, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        if context.coordinator.isPageLoaded {
            // Page chargée → injecter immédiatement
            context.coordinator.inject(html, into: webView)
        } else {
            // Page pas encore prête → mettre en attente pour didFinish
            // Ne pas mettre loadedHTML ici — seulement quand l'injection est réelle
            context.coordinator.pendingHTML = html
        }
    }

    private var editorHTML: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body { font-family: -apple-system, sans-serif; font-size: 14px; background: transparent; }

          #toolbar {
            display: flex; flex-wrap: wrap; gap: 2px; padding: 6px 8px;
            background: rgba(0,0,0,0.04); border-bottom: 1px solid rgba(0,0,0,0.1);
            position: sticky; top: 0; z-index: 10;
          }

          .btn {
            display: inline-flex; align-items: center; justify-content: center;
            width: 26px; height: 26px; border: none; border-radius: 4px;
            background: transparent; cursor: pointer; font-size: 13px;
            color: #333; transition: background 0.1s;
          }
          .btn:hover { background: rgba(0,0,0,0.1); }
          .btn:active { background: rgba(0,0,0,0.2); }
          .sep { width: 1px; height: 20px; background: rgba(0,0,0,0.15); margin: 3px 2px; }

          #editor {
            min-height: 200px; padding: 12px; outline: none;
            font-family: -apple-system, sans-serif; font-size: 14px; line-height: 1.5;
          }
          #editor:empty:before {
            content: attr(data-placeholder); color: #999; pointer-events: none;
          }

          select.font-size {
            height: 26px; border: none; border-radius: 4px; font-size: 12px;
            background: transparent; cursor: pointer; padding: 0 4px;
          }
          select.font-size:hover { background: rgba(0,0,0,0.1); }

          input[type=color] {
            width: 26px; height: 26px; border: none; border-radius: 4px;
            padding: 2px; cursor: pointer; background: transparent;
          }
        </style>
        </head>
        <body>
        <div id="toolbar">
          <!-- Lucide-style SVG icons -->
          <button class="btn" onclick="fmt('bold')" title="Gras (⌘B)">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M6 4h8a4 4 0 0 1 4 4 4 4 0 0 1-4 4H6z"/><path d="M6 12h9a4 4 0 0 1 4 4 4 4 0 0 1-4 4H6z"/></svg>
          </button>
          <button class="btn" onclick="fmt('italic')" title="Italique (⌘I)">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="19" y1="4" x2="10" y2="4"/><line x1="14" y1="20" x2="5" y2="20"/><line x1="15" y1="4" x2="9" y2="20"/></svg>
          </button>
          <button class="btn" onclick="fmt('underline')" title="Souligne (⌘U)">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 3v7a6 6 0 0 0 6 6 6 6 0 0 0 6-6V3"/><line x1="4" y1="21" x2="20" y2="21"/></svg>
          </button>
          <button class="btn" onclick="fmt('strikeThrough')" title="Barré">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="5" y1="12" x2="19" y2="12"/><path d="M16 6c0 0-1.5-2-4-2s-5 1.5-5 4c0 2 1.5 3 5 4"/><path d="M8 18c0 0 1.5 2 4 2s5-1.5 5-4c0-2-1.5-3-5-4"/></svg>
          </button>
          <div class="sep"></div>
          <select class="font-size" onchange="setFontSize(this.value)" title="Taille de police">
            <option value="">Taille</option>
            <option value="1">Petit</option>
            <option value="3" selected>Normal</option>
            <option value="5">Grand</option>
            <option value="7">Très grand</option>
          </select>
          <div class="sep"></div>
          <button class="btn" onclick="fmt('insertUnorderedList')" title="Liste à puces">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="9" y1="6" x2="20" y2="6"/><line x1="9" y1="12" x2="20" y2="12"/><line x1="9" y1="18" x2="20" y2="18"/><circle cx="4" cy="6" r="1.5" fill="currentColor" stroke="none"/><circle cx="4" cy="12" r="1.5" fill="currentColor" stroke="none"/><circle cx="4" cy="18" r="1.5" fill="currentColor" stroke="none"/></svg>
          </button>
          <button class="btn" onclick="fmt('insertOrderedList')" title="Liste numérotée">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="10" y1="6" x2="21" y2="6"/><line x1="10" y1="12" x2="21" y2="12"/><line x1="10" y1="18" x2="21" y2="18"/><path d="M4 6h1v4"/><path d="M4 10h2"/><path d="M3 14h2a1 1 0 0 1 1 1v1a1 1 0 0 1-1 1H3"/><path d="M3 18h2"/></svg>
          </button>
          <div class="sep"></div>
          <button class="btn" onclick="fmt('justifyLeft')" title="Aligner à gauche">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="3" y1="6" x2="21" y2="6"/><line x1="3" y1="12" x2="15" y2="12"/><line x1="3" y1="18" x2="18" y2="18"/></svg>
          </button>
          <button class="btn" onclick="fmt('justifyCenter')" title="Centrer">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="3" y1="6" x2="21" y2="6"/><line x1="6" y1="12" x2="18" y2="12"/><line x1="4" y1="18" x2="20" y2="18"/></svg>
          </button>
          <button class="btn" onclick="fmt('justifyRight')" title="Aligner à droite">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="3" y1="6" x2="21" y2="6"/><line x1="9" y1="12" x2="21" y2="12"/><line x1="6" y1="18" x2="21" y2="18"/></svg>
          </button>
          <div class="sep"></div>
          <input type="color" onchange="setColor(this.value)" title="Couleur du texte" value="#000000">
          <div class="sep"></div>
          <button class="btn" onclick="fmt('removeFormat')" title="Effacer le formatage">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m7 21-4.3-4.3c-1-1-1-2.5 0-3.4l9.6-9.6c1-1 2.5-1 3.4 0l5.6 5.6c1 1 1 2.5 0 3.4L13 21"/><path d="M22 21H7"/><path d="m5 11 9 9"/></svg>
          </button>
        </div>
        <div id="editor" contenteditable="true" data-placeholder="Rédigez votre message…"></div>

        <script>
        const editor = document.getElementById('editor');

        function fmt(cmd, val) {
          editor.focus();
          document.execCommand(cmd, false, val || null);
          notify();
        }

        function setFontSize(val) {
          if (val) fmt('fontSize', val);
        }

        function setColor(val) {
          fmt('foreColor', val);
        }

        function notify() {
          window.webkit.messageHandlers.contentChanged.postMessage(editor.innerHTML);
        }

        editor.addEventListener('input', notify);
        editor.addEventListener('paste', function(e) {
          e.preventDefault();
          var text = e.clipboardData.getData('text/plain');
          document.execCommand('insertText', false, text);
        });

        editor.addEventListener('keydown', function(e) {
          if (e.metaKey || e.ctrlKey) {
            if (e.key === 'b') { e.preventDefault(); fmt('bold'); }
            if (e.key === 'i') { e.preventDefault(); fmt('italic'); }
            if (e.key === 'u') { e.preventDefault(); fmt('underline'); }
          }
        });

        function setContent(safeHtml) {
          editor.innerHTML = safeHtml || '';
        }
        </script>
        </body>
        </html>
        """
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var html: String
        var loadedHTML: String? = nil  // nil = WKWebView pas encore chargé
        var isPageLoaded = false       // true après webView(_:didFinish:)
        var pendingHTML: String? = nil // HTML à injecter dès que la page est prête

        nonisolated init(html: Binding<String>) { _html = html }

        // Appelé quand la page HTML est entièrement chargée — inject le HTML en attente
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isPageLoaded = true
            if let pending = pendingHTML, !pending.isEmpty {
                inject(pending, into: webView)
                pendingHTML = nil
            }
        }

        nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "contentChanged", let body = message.body as? String {
                Task { @MainActor in
                    self.html = body
                    self.loadedHTML = body  // sync — évite la re-injection pendant la frappe
                }
            }
        }

        func inject(_ content: String, into webView: WKWebView) {
            loadedHTML = content
            if let jsonData = try? JSONEncoder().encode(content),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                webView.evaluateJavaScript("setContent(\(jsonString));") { _, _ in }
            }
        }
    }
}
