import SwiftUI

struct DrivePickerView: View {
    @State private var vm: DrivePickerViewModel
    let onSelect: (DriveFile) -> Void
    let onDismiss: () -> Void

    init(vm: DrivePickerViewModel, onSelect: @escaping (DriveFile) -> Void, onDismiss: @escaping () -> Void) {
        _vm = State(initialValue: vm)
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Fichiers Google Drive").font(.headline)
                Spacer()
                Button("Annuler", action: onDismiss)
            }
            .padding()
            Divider()
            if vm.isLoading {
                ProgressView("Chargement…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.files.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive.badge.questionmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Aucun fichier Drive")
                        .font(.headline)
                    Text("Aucun fichier Drive trouvé. Si vous venez de mettre à jour l'app, déconnectez-vous et reconnectez-vous pour accorder les nouveaux droits d'accès Drive.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(vm.files) { file in
                    Button(action: { onSelect(file) }) {
                        HStack {
                            Image(systemName: driveIcon(for: file.mimeType)).foregroundStyle(.blue)
                            VStack(alignment: .leading) {
                                Text(file.name).font(.body)
                                Text(ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 300)
        .task { await vm.load() }
    }

    private func driveIcon(for mimeType: String) -> String {
        if mimeType.contains("pdf") { return "doc.fill" }
        if mimeType.contains("image") { return "photo" }
        if mimeType.contains("spreadsheet") || mimeType.contains("excel") { return "tablecells" }
        if mimeType.contains("presentation") { return "play.rectangle" }
        return "doc"
    }
}
