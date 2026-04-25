import SwiftUI

struct SidebarView: View {
    @Environment(SessionStore.self) var store

    private let systemLabelIds = ["INBOX", "SENT", "DRAFTS", "TRASH", "SPAM"]

    var systemLabels: [GmailLabel] {
        store.labels.filter { systemLabelIds.contains($0.id) }
    }

    var userLabels: [GmailLabel] {
        store.labels.filter { !systemLabelIds.contains($0.id) }
    }

    var body: some View {
        List(selection: Binding(
            get: { store.selectedLabelId as String? },
            set: { if let id = $0 { store.selectedLabelId = id } }
        )) {
            Section("Boites") {
                ForEach(systemLabels) { label in
                    LabelRow(label: label).tag(label.id)
                }
            }
            if !userLabels.isEmpty {
                Section("Labels") {
                    ForEach(userLabels) { label in
                        LabelRow(label: label).tag(label.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    }
}

private struct LabelRow: View {
    let label: GmailLabel

    var body: some View {
        HStack {
            Label(label.name, systemImage: iconName(for: label.id))
            Spacer()
            if let unread = label.messagesUnread, unread > 0 {
                Text("\(unread)")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
            }
        }
    }

    private func iconName(for id: String) -> String {
        switch id {
        case "INBOX": return "tray"
        case "SENT": return "paperplane"
        case "DRAFTS": return "doc"
        case "TRASH": return "trash"
        case "SPAM": return "exclamationmark.shield"
        default: return "tag"
        }
    }
}
