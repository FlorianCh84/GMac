import SwiftUI

struct AISettingsView: View {
    @State private var vm: AISettingsViewModel

    init(vm: AISettingsViewModel) { _vm = State(initialValue: vm) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Provider actif avec indicateur visuel
                GroupBox {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Provider actif")
                                .font(.headline)
                            Spacer()
                            // Badge indiquant si la clé du provider actif est configurée
                            if keyForCurrentProvider.isEmpty {
                                Label("Clé manquante", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else {
                                Label("Clé configurée", systemImage: "checkmark.seal.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        Picker("", selection: $vm.selectedProvider) {
                            ForEach(LLMProviderType.allCases) { type in
                                HStack {
                                    Text(type.rawValue)
                                    if !keyFor(type).isEmpty {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                                .tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)
                }

                // Clés API
                GroupBox("Clés API") {
                    VStack(spacing: 0) {
                        apiKeyRow("Claude (Anthropic)",
                                  placeholder: "sk-ant-api...",
                                  text: $vm.claudeKey,
                                  isActive: vm.selectedProvider == .claude)
                        Divider()
                        apiKeyRow("ChatGPT (OpenAI)",
                                  placeholder: "sk-proj-...",
                                  text: $vm.openaiKey,
                                  isActive: vm.selectedProvider == .openai)
                        Divider()
                        apiKeyRow("Gemini (Google)",
                                  placeholder: "AIzaSy...",
                                  text: $vm.geminiKey,
                                  isActive: vm.selectedProvider == .gemini)
                        Divider()
                        apiKeyRow("Mistral",
                                  placeholder: "...",
                                  text: $vm.mistralKey,
                                  isActive: vm.selectedProvider == .mistral)
                    }
                }

                // Info
                Text("Les clés sont stockées dans le Keychain macOS. Entrez la clé du provider sélectionné, puis cliquez Sauvegarder.")
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
                            Label("Sauvegarder", systemImage: "square.and.arrow.down")
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
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.white)
                    Text("\(vm.selectedProvider.rawValue) sélectionné et clé sauvegardée")
                        .font(.caption.bold()).foregroundStyle(.white)
                }
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

    // MARK: - Helpers

    private var keyForCurrentProvider: String {
        keyFor(vm.selectedProvider)
    }

    private func keyFor(_ type: LLMProviderType) -> String {
        switch type {
        case .claude:  return vm.claudeKey
        case .openai:  return vm.openaiKey
        case .gemini:  return vm.geminiKey
        case .mistral: return vm.mistralKey
        }
    }

    private func apiKeyRow(_ label: String, placeholder: String, text: Binding<String>, isActive: Bool) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                if isActive {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                }
                Text(label)
                    .font(isActive ? .body.bold() : .body)
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .frame(width: 168, alignment: .leading)
            }
            TextField(placeholder, text: text)
                .textFieldStyle(.squareBorder)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
            // Indicateur clé présente
            if !text.wrappedValue.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isActive ? Color.blue.opacity(0.04) : Color.clear)
    }
}
