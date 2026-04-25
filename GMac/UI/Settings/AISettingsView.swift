import SwiftUI

struct AISettingsView: View {
    @State private var vm: AISettingsViewModel

    init(vm: AISettingsViewModel) { _vm = State(initialValue: vm) }

    var body: some View {
        Form {
            Section("Provider actif") {
                Picker("LLM", selection: $vm.selectedProvider) {
                    ForEach(LLMProviderType.allCases) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented)
            }
            Section("Clés API") {
                keyField("Claude (Anthropic)", key: $vm.claudeKey, hint: "sk-ant-...")
                keyField("ChatGPT (OpenAI)", key: $vm.openaiKey, hint: "sk-...")
                keyField("Gemini (Google)", key: $vm.geminiKey, hint: "AIza...")
                keyField("Mistral", key: $vm.mistralKey, hint: "...")
            }
            Section {
                Text("Clés stockées dans le Keychain macOS — jamais en clair, jamais envoyées à GMac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { Task { @MainActor in await vm.save() } }) {
                    if vm.isSaving { ProgressView().controlSize(.small) } else { Text("Sauvegarder") }
                }
                .buttonStyle(.borderedProminent).disabled(vm.isSaving)
            }
        }
        .overlay(alignment: .top) {
            if vm.saveSuccess {
                Label("Clés sauvegardées", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold()).foregroundStyle(.white)
                    .padding(8).background(.green.opacity(0.9), in: .capsule).padding(.top, 8)
                    .task { try? await Task.sleep(for: .seconds(2)); vm.saveSuccess = false }
            }
        }
    }

    private func keyField(_ label: String, key: Binding<String>, hint: String) -> some View {
        HStack {
            Text(label).frame(width: 160, alignment: .leading)
            SecureField(hint, text: key).textFieldStyle(.plain)
        }
    }
}
