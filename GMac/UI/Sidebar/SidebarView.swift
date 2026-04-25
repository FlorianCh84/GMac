import SwiftUI

struct SidebarView: View {
    @Environment(SessionStore.self) var store

    // Ordre exact Gmail + noms français
    private static let gmailOrder: [(id: String, name: String, icon: String)] = [
        ("INBOX",               "Boîte de réception", "tray"),
        ("STARRED",             "Suivis",              "star"),
        ("SNOOZED",             "Snoozés",             "clock"),
        ("IMPORTANT",           "Important",           "exclamationmark"),
        ("SENT",                "Envoyés",             "paperplane"),
        ("SCHEDULED",           "Planifiés",           "calendar.badge.clock"),
        ("DRAFTS",              "Brouillons",          "doc"),
        ("ALL",                 "Tous les messages",   "tray.full"),
        ("SPAM",                "Spam",                "exclamationmark.shield"),
        ("TRASH",               "Corbeille",           "trash"),
    ]

    private static let orderedIds = Set(gmailOrder.map { $0.id })

    // Labels système présents dans le compte, dans l'ordre Gmail
    var systemLabels: [(label: GmailLabel?, meta: (id: String, name: String, icon: String))] {
        Self.gmailOrder.compactMap { meta in
            let found = store.labels.first { $0.id == meta.id }
            // Inclure seulement si le label existe dans le compte (ou si c'est INBOX toujours)
            if found != nil || meta.id == "INBOX" {
                return (label: found, meta: meta)
            }
            return nil
        }
    }

    // Labels catégories Gmail (CATEGORY_*)
    var categoryLabels: [GmailLabel] {
        store.labels.filter { $0.id.hasPrefix("CATEGORY_") }
            .sorted { $0.name < $1.name }
    }

    // Labels personnalisés (type .user)
    var userLabels: [GmailLabel] {
        store.labels
            .filter { $0.type == .user && !$0.id.hasPrefix("CATEGORY_") }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List(selection: Binding(
            get: { store.selectedLabelId as String? },
            set: { if let id = $0 { store.selectedLabelId = id } }
        )) {
            // Labels système dans l'ordre Gmail
            Section {
                ForEach(systemLabels, id: \.meta.id) { entry in
                    LabelRow(
                        id: entry.meta.id,
                        name: entry.meta.name,
                        icon: entry.meta.icon,
                        unread: entry.label?.messagesUnread
                    )
                    .tag(entry.meta.id)
                }
            }

            // Catégories Gmail (si présentes)
            if !categoryLabels.isEmpty {
                Section("Catégories") {
                    ForEach(categoryLabels) { label in
                        LabelRow(
                            id: label.id,
                            name: categoryName(label.id),
                            icon: "folder",
                            unread: label.messagesUnread
                        )
                        .tag(label.id)
                    }
                }
            }

            // Labels personnalisés
            if !userLabels.isEmpty {
                Section("Labels") {
                    ForEach(userLabels) { label in
                        LabelRow(
                            id: label.id,
                            name: label.name,
                            icon: "tag",
                            unread: label.messagesUnread
                        )
                        .tag(label.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    }

    private func categoryName(_ id: String) -> String {
        switch id {
        case "CATEGORY_PERSONAL":    return "Personnel"
        case "CATEGORY_SOCIAL":      return "Réseaux sociaux"
        case "CATEGORY_PROMOTIONS":  return "Promotions"
        case "CATEGORY_UPDATES":     return "Notifications"
        case "CATEGORY_FORUMS":      return "Forums"
        default: return id.replacingOccurrences(of: "CATEGORY_", with: "").capitalized
        }
    }
}

private struct LabelRow: View {
    let id: String
    let name: String
    let icon: String
    let unread: Int?

    var body: some View {
        HStack {
            Label(name, systemImage: icon)
            Spacer()
            if let unread, unread > 0 {
                Text("\(unread)")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
            }
        }
    }
}
