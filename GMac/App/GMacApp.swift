import SwiftUI
import SwiftData

@main
struct GMacApp: App {
    // AppDelegate intercepte les URLs au niveau AppKit — empêche la création d'une 2e fenêtre
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            Group {
                if env.oauth.isLoggedIn {
                    ContentView()
                        .environment(env.sessionStore)
                        .environment(env.oauth)
                        .environment(env)
                } else {
                    LoginView()
                        .environment(env.oauth)
                }
            }
            // Observer les URLs reçues par AppDelegate (sans nouvelle fenêtre)
            .onReceive(NotificationCenter.default.publisher(for: .gmacDidReceiveURL)) { notification in
                if let url = notification.object as? URL {
                    Task { await env.oauth.handleCallbackURL(url) }
                }
            }
        }
        .handlesExternalEvents(matching: ["*"])
        .modelContainer(for: VoiceProfile.self)
    }
}
