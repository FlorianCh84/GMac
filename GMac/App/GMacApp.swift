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
                // Garanti @MainActor par SwiftUI — aucun problème d'isolation
                Task { await env.oauth.handleCallbackURL(url) }
            }
        }
        .modelContainer(for: VoiceProfile.self)
    }
}
