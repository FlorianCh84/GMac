import SwiftUI

struct AISettingsView: View {
    @State private var vm: AISettingsViewModel

    init(vm: AISettingsViewModel) { _vm = State(initialValue: vm) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Provider actif
                GroupBox("Provider actif") {
                    Picker("", selection: $vm.selectedProvider) {
                        ForEach(LLMProviderType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.vertical, 4)
                }

                // Clés API
                GroupBox("Clés API") {
                    VStack(spacing: 0) {
                        apiKeyRow("Claude (Anthropic)", placeholder: "sk-ant-api...", text: $vm.claudeKey)
                        Divider()
                        apiKeyRow("ChatGPT (OpenAI)", placeholder: "sk-proj-...", text: $vm.openaiKey)
                        Divider()
                        apiKeyRow("Gemini (Google)", placeholder: "AIzaSy...", text: $vm.geminiKey)
                        Divider()
                        apiKeyRow("Mistral", placeholder: "...", text: $vm.mistralKey)
                    }
                }

                // Info
                Text("Les clés sont stockées dans le Keychain macOS — jamais en clair, jamais envoyées à GMac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                // Bouton Sauvegarder
                HStack {
                    Spacer()
                    Button(action: { Task { @MainActor in await vm.save() } }) {
                        if vm.isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Sauvegarder les clés")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isSaving)
                }
            }
            .padding(20)
        }
        .overlay(alignment: .top) {
            if vm.saveSuccess {
                Label("Clés sauvegardées", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.green.opacity(0.9), in: .capsule)
                    .padding(.top, 8)
                    .task {
                        try? await Task.sleep(for: .seconds(2))
                        vm.saveSuccess = false
                    }
            }
        }
        .alert("Erreur", isPresented: Binding(
            get: { vm.saveError != nil },
            set: { if !$0 { vm.saveError = nil } }
        )) {
            Button("OK") { vm.saveError = nil }
        } message: {
            Text(vm.saveError ?? "")
        }
    }

    private func apiKeyRow(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.body)
                .frame(width: 160, alignment: .leading)
                .foregroundStyle(.primary)
            TextField(placeholder, text: text)
                .textFieldStyle(.squareBorder)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
}
