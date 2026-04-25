import SwiftUI

@main
struct GMacApp: App {
    @State private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            if env.oauth.isAuthenticated {
                ContentView()
                    .environment(env.sessionStore)
                    .environment(env.oauth)
                    .environment(env)
            } else {
                LoginView()
                    .environment(env.oauth)
            }
        }
    }
}
