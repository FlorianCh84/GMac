import SwiftUI

struct SettingsView: View {
    let gmailService: any GmailServiceProtocol
    let settingsService: any GmailSettingsServiceProtocol

    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink("Signature") {
                    SignatureEditorView(
                        vm: SignatureEditorViewModel(settingsService: settingsService)
                    )
                    .navigationTitle("Signature")
                }
                NavigationLink("Message d'absence") {
                    VacationSettingsView(
                        vm: VacationSettingsViewModel(settingsService: settingsService)
                    )
                    .navigationTitle("Message d'absence")
                }
                NavigationLink("Labels") {
                    LabelsManagerView(
                        vm: LabelsManagerViewModel(gmailService: gmailService, settingsService: settingsService)
                    )
                    .navigationTitle("Labels")
                }
                NavigationLink("Assistant IA") {
                    AISettingsView(vm: AISettingsViewModel())
                        .navigationTitle("Assistant IA")
                }
            }
            .navigationTitle("Paramètres")
            .listStyle(.sidebar)
        } detail: {
            ContentUnavailableView("Choisissez une section", systemImage: "gear")
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}
