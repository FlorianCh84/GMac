import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) var store
    @Environment(GoogleOAuthManager.self) var oauth

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            ThreadListView()
        } detail: {
            MessageDetailView()
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Deconnexion", systemImage: "rectangle.portrait.and.arrow.right") {
                    oauth.logout()
                }
            }
        }
        .task { await store.loadLabels() }
        .task { await store.loadThreadList() }
    }
}
