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
            // Header avec breadcrumb
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(vm.breadcrumbs.enumerated()), id: \.offset) { idx, crumb in
                            if idx > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Button(crumb.name) {
                                Task { @MainActor in await vm.navigateTo(breadcrumb: crumb) }
                            }
                            .buttonStyle(.plain)
                            .font(idx == vm.breadcrumbs.count - 1 ? .headline : .body)
                            .foregroundStyle(idx == vm.breadcrumbs.count - 1 ? .primary : .secondary)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                Spacer()
                Button("Annuler", action: onDismiss)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.regularMaterial)

            Divider()

            // Contenu
            if vm.isLoading {
                ProgressView("Chargement…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.lastError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.orange)
                    Text("Erreur Drive").font(.headline)
                    Text(driveErrorMessage(error)).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal)
                    Button("Réessayer") { Task { await vm.load() } }.buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.files.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Dossier vide").font(.headline)
                    Text("Ce dossier ne contient aucun fichier.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(vm.files) { file in
                    Button(action: {
                        if file.isFolder {
                            Task { @MainActor in await vm.navigateInto(folder: file) }
                        } else {
                            onSelect(file)
                        }
                    }) {
                        HStack {
                            Image(systemName: file.isFolder ? "folder.fill" : driveIcon(for: file.mimeType))
                                .foregroundStyle(file.isFolder ? .blue : .secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name).font(.body).lineLimit(1)
                                if !file.isFolder {
                                    Text(ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if file.isFolder {
                                Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(minWidth: 570, minHeight: 450)
        .task { await vm.load() }
    }

    private func driveErrorMessage(_ error: AppError) -> String {
        switch error {
        case .apiError(let code, let msg):
            if code == 403 { return "Accès refusé (403). Vérifiez que l'API Google Drive est activée." }
            return "Erreur \(code): \(msg)"
        case .offline: return "Pas de connexion internet."
        default: return "Erreur: \(error)"
        }
    }

    private func driveIcon(for mimeType: String) -> String {
        if mimeType.contains("pdf") { return "doc.fill" }
        if mimeType.contains("image") { return "photo" }
        if mimeType.contains("spreadsheet") || mimeType.contains("excel") { return "tablecells" }
        if mimeType.contains("presentation") { return "play.rectangle" }
        if mimeType.contains("google-apps.document") { return "doc.text.fill" }
        return "doc"
    }
}
