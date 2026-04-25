import SwiftUI

struct DrivePickerView: View {
    @State var vm: DrivePickerViewModel
    let onSelect: (DriveFile) -> Void
    let onDismiss: () -> Void

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
                ContentUnavailableView(
                    "Aucun fichier Drive",
                    systemImage: "externaldrive",
                    description: Text("Uploader des fichiers vers Drive pour les retrouver ici")
                )
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
