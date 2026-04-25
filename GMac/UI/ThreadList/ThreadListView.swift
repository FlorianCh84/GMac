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
