import SwiftUI

struct AIAssistantPanel: View {
    @State private var vm: AIAssistantViewModel
    let thread: EmailThread
    let senderEmail: String
    let sentMessages: [EmailMessage]
    let onInject: (String) -> Void

    init(vm: AIAssistantViewModel, thread: EmailThread, senderEmail: String,
         sentMessages: [EmailMessage], onInject: @escaping (String) -> Void) {
        _vm = State(initialValue: vm)
        self.thread = thread; self.senderEmail = senderEmail
        self.sentMessages = sentMessages; self.onInject = onInject
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    instructionField
                    objectiveChips
                    toneChips
                    lengthPicker
                    actionRow
                    responseArea
                }
                .padding()
            }
        }
        .background(.regularMaterial)
        .frame(minWidth: 300, maxWidth: 400)
    }

    // MARK: - Subviews

    private var panelHeader: some View {
        HStack {
            Label("Assistant IA", systemImage: "sparkles").font(.headline)
            Spacer()
            Text(vm.toneSource.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal).padding(.vertical, 10)
    }

    private var instructionField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Intention").font(.caption.bold()).foregroundStyle(.secondary)
            TextEditor(text: $vm.freeText)
                .frame(minHeight: 60, maxHeight: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        }
    }

    private var objectiveChips: some View {
        chipRow(title: "Objectif", items: ReplyObjective.allCases, selected: $vm.selectedObjective)
    }

    private var toneChips: some View {
        chipRow(title: "Ton", items: ReplyTone.allCases, selected: $vm.selectedTone)
    }

    private var lengthPicker: some View {
        HStack(spacing: 6) {
            Text("Longueur").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: $vm.selectedLength) {
                ForEach(ReplyLength.allCases) { l in Text(l.rawValue).tag(l) }
            }
            .pickerStyle(.segmented).labelsHidden()
        }
    }

    private var actionRow: some View {
        HStack {
            Button(action: { Task { @MainActor in await vm.generateStreaming(thread: thread, senderEmail: senderEmail, sentMessages: sentMessages) } }) {
                if vm.isGenerating { ProgressView().controlSize(.small) }
                else { Label("Générer", systemImage: "arrow.trianglehead.2.clockwise") }
            }
            .buttonStyle(.borderedProminent).disabled(vm.isGenerating)

            Button(action: { Task { @MainActor in await vm.requestOpinion(thread: thread) } }) {
                Label("Analyser", systemImage: "eye")
            }
            .buttonStyle(.bordered).disabled(vm.isGenerating)
        }
    }

    @ViewBuilder
    private var responseArea: some View {
        switch vm.state {
        case .idle: EmptyView()
        case .generating:
            HStack { ProgressView(); Text("Génération…").font(.caption).foregroundStyle(.secondary) }
        case .done(let text):
            VStack(alignment: .leading, spacing: 8) {
                Text("Réponse générée").font(.caption.bold()).foregroundStyle(.secondary)
                Text(text).font(.body).textSelection(.enabled)
                    .padding(8).background(.quaternary, in: .rect(cornerRadius: 6))
                HStack {
                    TextField("Affiner…", text: $vm.refinementText)
                        .textFieldStyle(.plain)
                        .onSubmit { Task { @MainActor in await vm.refine(thread: thread) } }
                    Button("OK") { Task { @MainActor in await vm.refine(thread: thread) } }
                        .disabled(vm.refinementText.isEmpty)
                }
                .padding(6).background(.quaternary, in: .capsule)
                Button(action: { onInject(text) }) {
                    Label("Insérer dans le composeur", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.return, modifiers: .command)
            }
        case .opinionDone(let opinion):
            VStack(alignment: .leading, spacing: 8) {
                Text("Analyse de l'échange").font(.caption.bold()).foregroundStyle(.secondary)
                Text(opinion).font(.body).textSelection(.enabled)
                    .padding(8).background(.blue.opacity(0.08), in: .rect(cornerRadius: 6))
                Button("Réinitialiser") { vm.reset() }.buttonStyle(.bordered).controlSize(.small)
            }
        case .failed(let msg):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
                VStack(alignment: .leading) {
                    Text(msg).font(.caption).foregroundStyle(.red)
                    Button("Réinitialiser") { vm.reset() }.buttonStyle(.plain).font(.caption)
                }
            }
        }
    }

    // MARK: - Chip helpers

    private func chipRow<T: RawRepresentable & CaseIterable & Identifiable & Hashable>(
        title: String, items: [T], selected: Binding<T?>
    ) -> some View where T.RawValue == String {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], alignment: .leading, spacing: 4) {
                ForEach(items) { item in
                    Button(item.rawValue) {
                        selected.wrappedValue = selected.wrappedValue == item ? nil : item
                    }
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(selected.wrappedValue == item ? Color.accentColor : Color.secondary.opacity(0.15), in: .capsule)
                    .foregroundStyle(selected.wrappedValue == item ? .white : .primary)
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
