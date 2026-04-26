import SwiftUI
import SwiftData

@main
struct GMacApp: App {
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
            .onOpenURL { url in
                Task { await env.oauth.handleCallbackURL(url) }
            }
        }
        // Reroute les URLs OAuth vers la fenêtre existante au lieu d'en ouvrir une nouvelle
        .handlesExternalEvents(matching: ["*"])
        .modelContainer(for: VoiceProfile.self)
    }
}
