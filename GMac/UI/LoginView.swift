import SwiftUI

struct LoginView: View {
    @Environment(GoogleOAuthManager.self) var oauth
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "envelope.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("GMac")
                .font(.largeTitle.bold())

            Text("Client Gmail natif macOS")
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }

            Button(action: signIn) {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Se connecter avec Google", systemImage: "person.badge.key.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
        }
        .frame(width: 420, height: 320)
        .padding()
    }

    private func signIn() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await oauth.startOAuthFlow()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
