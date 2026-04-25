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
        // Ne pas recharger si en cours d'édition
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
          <button class="btn" onclick="fmt('bold')" title="Gras (cmdb)"><b>B</b></button>
          <button class="btn" onclick="fmt('italic')" title="Italique (cmdi)"><i>I</i></button>
          <button class="btn" onclick="fmt('underline')" title="Souligne (cmdu)"><u>U</u></button>
          <button class="btn" onclick="fmt('strikeThrough')" title="Barre"><s>S</s></button>
          <div class="sep"></div>
          <select class="font-size" onchange="setFontSize(this.value)" title="Taille">
            <option value="">Taille</option>
            <option value="1">Petit</option>
            <option value="3" selected>Normal</option>
            <option value="5">Grand</option>
            <option value="7">Tres grand</option>
          </select>
          <div class="sep"></div>
          <button class="btn" onclick="fmt('insertUnorderedList')" title="Liste a puces">list</button>
          <button class="btn" onclick="fmt('insertOrderedList')" title="Liste numerotee">1.</button>
          <div class="sep"></div>
          <button class="btn" onclick="fmt('justifyLeft')" title="Gauche">L</button>
          <button class="btn" onclick="fmt('justifyCenter')" title="Centre">C</button>
          <button class="btn" onclick="fmt('justifyRight')" title="Droite">R</button>
          <div class="sep"></div>
          <input type="color" onchange="setColor(this.value)" title="Couleur du texte" value="#000000">
          <div class="sep"></div>
          <button class="btn" onclick="fmt('removeFormat')" title="Effacer le formatage">X</button>
        </div>
        <div id="editor" contenteditable="true" data-placeholder="Redigez votre message"></div>

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

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var html: String

        init(html: Binding<String>) { _html = html }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "contentChanged", let body = message.body as? String {
                DispatchQueue.main.async {
                    self.html = body
                }
            }
        }
    }
}
