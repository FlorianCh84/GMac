import SwiftUI

struct DriveFolderPickerView: View {
    @State private var vm: DrivePickerViewModel
    let onSelect: (DriveFile?) -> Void  // nil = racine "Mon Drive"
    let onDismiss: () -> Void

    init(driveService: any DriveServiceProtocol, onSelect: @escaping (DriveFile?) -> Void, onDismiss: @escaping () -> Void) {
        _vm = State(initialValue: DrivePickerViewModel(driveService: driveService))
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    var folderFiles: [DriveFile] {
        vm.files.filter { $0.isFolder }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(vm.breadcrumbs.enumerated()), id: \.offset) { idx, crumb in
                            if idx > 0 {
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
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

            // Bouton "Enregistrer ici" pour le dossier courant
            Button(action: {
                let currentFolderFile = vm.breadcrumbs.count > 1 ?
                    DriveFile(id: vm.currentFolderId ?? "root", name: vm.breadcrumbs.last?.name ?? "Mon Drive",
                              mimeType: "application/vnd.google-apps.folder", size: nil, modifiedTime: nil) :
                    nil
                onSelect(currentFolderFile)
            }) {
                HStack {
                    Image(systemName: "folder.badge.plus").foregroundStyle(.blue)
                    Text("Enregistrer dans « \(vm.breadcrumbs.last?.name ?? "Mon Drive") »")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(.blue.opacity(0.08), in: .rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(12)

            Divider()

            if vm.isLoading {
                ProgressView("Chargement…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if folderFiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Aucun sous-dossier").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(folderFiles) { folder in
                    Button(action: {
                        Task { @MainActor in await vm.navigateInto(folder: folder) }
                    }) {
                        HStack {
                            Image(systemName: "folder.fill").foregroundStyle(.blue)
                            Text(folder.name)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 360)
        .task { await vm.load() }
    }
}
