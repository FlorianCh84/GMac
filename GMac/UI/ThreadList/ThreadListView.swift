import SwiftUI

struct ThreadListView: View {
    @Environment(SessionStore.self) var store
    @State private var searchQuery: String = ""

    private var sortedThreads: [EmailThread] {
        store.threads
            .filter { thread in
                thread.messages.contains { $0.labelIds.contains(store.selectedLabelId) }
            }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if store.isLoading && store.threads.isEmpty && !store.isSearching {
                ProgressView("Chargement...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.lastSyncError, !store.isSearching {
                errorView(error)
            } else if store.isSearching {
                ProgressView("Recherche…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !searchQuery.isEmpty && store.searchResults.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            } else if !searchQuery.isEmpty {
                threadList(store.searchResults)
            } else if sortedThreads.isEmpty {
                ContentUnavailableView("Aucun message", systemImage: "tray")
            } else {
                threadList(sortedThreads)
            }
        }
        .searchable(text: $searchQuery, placement: .toolbar, prompt: "Rechercher…")
        .navigationSplitViewColumnWidth(min: 260, ideal: 340)
        .onChange(of: store.selectedLabelId) {
            store.selectedThreadId = nil
            searchQuery = ""
            store.searchResults = []
            Task { await store.loadThreadList() }
        }
        .task(id: searchQuery) {
            guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
                store.searchResults = []
                return
            }
            try? await Task.sleep(for: .milliseconds(400))
            await store.performSearch(query: searchQuery)
        }
    }

    @ViewBuilder
    private func threadList(_ threads: [EmailThread]) -> some View {
        List(threads, selection: Binding(
            get: { store.selectedThreadId },
            set: { store.selectedThreadId = $0 }
        )) { thread in
            ThreadRow(thread: thread).tag(thread.id)
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func errorView(_ error: AppError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("Impossible de charger les emails")
                .font(.headline)
            Text(errorMessage(error))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.08), in: .rect(cornerRadius: 8))
            Button("Réessayer") {
                store.lastSyncError = nil
                Task { await store.loadLabels(); await store.loadThreadList() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Text(formattedDate(thread.date))
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

    private func formattedDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().locale(Locale(identifier: "fr_FR")))
        }
        if cal.isDateInYesterday(date) {
            return "Hier"
        }
        let thisYear = cal.component(.year, from: Date()) == cal.component(.year, from: date)
        if thisYear {
            return date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).locale(Locale(identifier: "fr_FR")))
        }
        return date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits).locale(Locale(identifier: "fr_FR")))
    }
}
