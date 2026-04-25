import SwiftUI

struct SendButton: View {
    let sendState: SendState
    let isValid: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        switch sendState {
        case .idle:
            Button("Envoyer", action: onSend)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!isValid)
                .buttonStyle(.borderedProminent)

        case .countdown(let progress):
            HStack(spacing: 8) {
                Button("Annuler", action: onCancel)
                    .buttonStyle(.bordered)
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .frame(width: 140, height: 32)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.gradient)
                            .frame(width: max(0, geo.size.width * progress), height: 32)
                            .animation(.linear(duration: 0.1), value: progress)
                    }
                    .frame(width: 140, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("Envoi dans \(max(0, Int(ceil(3 * (1 - progress)))))s")
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                }
            }

        case .sending:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Envoi…").font(.caption).foregroundStyle(.secondary)
            }

        case .failed(let error):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(errorLabel(error))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                Button("Réessayer", action: onSend)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    private func errorLabel(_ error: AppError) -> String {
        switch error {
        case .offline: return "Hors ligne"
        case .rateLimited: return "Quota atteint"
        case .serverError: return "Erreur serveur"
        case .gatewayError: return "Service indisponible"
        case .tokenExpired: return "Session expirée"
        default: return "Erreur réseau"
        }
    }
}
