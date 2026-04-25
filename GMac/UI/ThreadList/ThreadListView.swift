import SwiftUI

struct ThreadListView: View {
    @Environment(SessionStore.self) var store

    var filteredThreads: [EmailThread] {
        store.threads.filter { thread in
            thread.messages.contains { $0.labelIds.contains(store.selectedLabelId) }
        }
    }

    var body: some View {
        Group {
            if store.isLoading && store.threads.isEmpty {
                ProgressView("Chargement...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.lastSyncError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text("Impossible de charger les emails")
                        .font(.headline)
                    Text(errorMessage(error))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Réessayer") {
                        store.lastSyncError = nil
                        Task { await store.loadLabels(); await store.loadThreadList() }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredThreads.isEmpty {
                ContentUnavailableView("Aucun message", systemImage: "tray")
            } else {
                List(filteredThreads, selection: Binding(
                    get: { store.selectedThreadId },
                    set: { store.selectedThreadId = $0 }
                )) { thread in
                    ThreadRow(thread: thread).tag(thread.id)
                }
                .listStyle(.plain)
            }
        }
        .navigationSplitViewColumnWidth(min: 260, ideal: 340)
        .onChange(of: store.selectedLabelId) {
            store.selectedThreadId = nil
            Task { await store.loadThreadList() }
        }
    }

    private func errorMessage(_ error: AppError) -> String {
        switch error {
        case .apiError(let code, let msg):
            if code == 403 { return "Accès refusé (403). Vérifiez que l'API Gmail est activée dans Google Cloud Console." }
            if code == 401 { return "Session expirée. Reconnectez-vous." }
            return "Erreur API \(code) : \(msg)"
        case .offline: return "Pas de connexion internet."
        case .tokenExpired: return "Session expirée. Déconnectez-vous et reconnectez-vous."
        default: return "Erreur inattendue. Réessayez."
        }
    }
}

private struct ThreadRow: View {
    let thread: EmailThread

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(thread.from)
                    .font(thread.isUnread ? .headline : .body)
                    .lineLimit(1)
                Spacer()
                Text(thread.date, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(thread.subject)
                .font(.subheadline)
                .lineLimit(1)
            Text(thread.snippet)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}
