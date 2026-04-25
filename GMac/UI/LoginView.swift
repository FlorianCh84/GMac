import SwiftUI

struct LoginView: View {
    @Environment(GoogleOAuthManager.self) var oauth
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.blue.opacity(0.15), .indigo.opacity(0.08)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

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
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
            .frame(width: 420)
        }
        .frame(width: 520, height: 380)
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
