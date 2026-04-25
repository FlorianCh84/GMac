import SwiftUI

struct LabelsManagerView: View {
    @State var vm: LabelsManagerViewModel

    var body: some View {
        List {
            Section("Labels personnalisés") {
                if vm.labels.isEmpty && !vm.isLoading {
                    Text("Aucun label personnalisé")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vm.labels) { label in
                        HStack {
                            Image(systemName: "tag").foregroundStyle(.blue)
                            Text(label.name)
                            Spacer()
                            Button(role: .destructive) {
                                Task { @MainActor in await vm.deleteLabel(id: label.id) }
                            } label: {
                                Image(systemName: "trash").foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Section("Nouveau label") {
                HStack {
                    TextField("Nom du label", text: $vm.newLabelName)
                        .onSubmit { Task { @MainActor in await vm.createLabel() } }
                    Button("Créer") {
                        Task { @MainActor in await vm.createLabel() }
                    }
                    .disabled(vm.newLabelName.trimmingCharacters(in: .whitespaces).isEmpty || vm.isCreating)
                }
            }
        }
        .overlay {
            if vm.isLoading { ProgressView("Chargement…") }
        }
        .task { await vm.load() }
        .alert("Erreur", isPresented: Binding(
            get: { vm.lastError != nil },
            set: { if !$0 { vm.lastError = nil } }
        )) {
            Button("OK") { vm.lastError = nil }
        } message: {
            Text("Opération échouée. Réessayez.")
        }
    }
}
