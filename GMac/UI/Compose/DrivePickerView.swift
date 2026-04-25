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
            } else if let error = vm.lastError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle).foregroundStyle(.orange)
                    Text("Erreur Drive").font(.headline)
                    Text(driveErrorMessage(error))
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal)
                    Button("Réessayer") { Task { await vm.load() } }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.files.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive")
                        .font(.largeTitle).foregroundStyle(.secondary)
                    Text("Aucun fichier Drive").font(.headline)
                    Text("Drive API activée mais aucun fichier trouvé dans votre Drive.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal)
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

    private func driveErrorMessage(_ error: AppError) -> String {
        switch error {
        case .apiError(let code, let msg):
            if code == 403 { return "Accès refusé (403). Vérifiez que l'API Google Drive est activée dans Google Cloud Console :\nconsole.cloud.google.com/apis/library/drive.googleapis.com" }
            if code == 401 { return "Session expirée. Déconnectez-vous et reconnectez-vous." }
            return "Erreur API \(code): \(msg)"
        case .offline: return "Pas de connexion internet."
        default: return "Erreur: \(error)"
        }
    }

    private func driveIcon(for mimeType: String) -> String {
        if mimeType.contains("pdf") { return "doc.fill" }
        if mimeType.contains("image") { return "photo" }
        if mimeType.contains("spreadsheet") || mimeType.contains("excel") { return "tablecells" }
        if mimeType.contains("presentation") { return "play.rectangle" }
        return "doc"
    }
}
