import SwiftUI

struct VacationSettingsView: View {
    @State var vm: VacationSettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Réponse automatique activée", isOn: $vm.enableAutoReply)
            }
            if vm.enableAutoReply {
                Section("Message") {
                    TextField("Objet", text: $vm.subject)
                    TextEditor(text: $vm.bodyText)
                        .frame(minHeight: 80)
                }
                Section("Options") {
                    Toggle("Répondre uniquement aux contacts", isOn: $vm.restrictToContacts)
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { Task { @MainActor in await vm.save() } }) {
                    if vm.isSaving { ProgressView().controlSize(.small) }
                    else { Text("Sauvegarder") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isSaving)
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
            Text("Les paramètres n'ont pas pu être sauvegardés.")
        }
    }
}
