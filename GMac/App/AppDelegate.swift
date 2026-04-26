import AppKit
import Foundation

// Intercepte les URLs au niveau AppKit avant que SwiftUI puisse créer une nouvelle fenêtre.
// NSApplicationDelegate.application(_:open:) est appelé par macOS quand une URL est reçue
// (redirect OAuth, etc.) — sans créer de fenêtre supplémentaire.
final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            // Dispatcher sur MainActor pour que GMacApp.onOpenURL le reçoive
            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .gmacDidReceiveURL,
                    object: url
                )
            }
        }
    }

    // Empêche la création d'une nouvelle fenêtre si des fenêtres sont déjà visibles
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag {
            sender.windows.first(where: { $0.isVisible })?.makeKeyAndOrderFront(nil)
            return false
        }
        return true
    }
}

extension Notification.Name {
    static let gmacDidReceiveURL = Notification.Name("GMacDidReceiveURL")
}
