import SwiftUI

struct ComposeView: View {
    @State var vm: ComposeViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            fieldsSection
            Divider()
            bodySection
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private var headerBar: some View {
        HStack {
            Button("Annuler") { onDismiss() }
                .disabled(!isIdle)
            Spacer()
            Text(vm.replyToThreadId != nil ? "Répondre" : "Nouveau message")
                .font(.headline)
            Spacer()
            SendButton(
                sendState: vm.sendState,
                isValid: vm.isValid,
                onSend: { Task { await vm.startSend() } },
                onCancel: { vm.cancelSend() }
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var fieldsSection: some View {
        VStack(spacing: 0) {
            ComposeField(label: "À", text: $vm.to)
            Divider().padding(.leading, 56)
            ComposeField(label: "Cc", text: $vm.cc)
            Divider().padding(.leading, 56)
            ComposeField(label: "Objet", text: $vm.subject)
        }
    }

    private var bodySection: some View {
        TextEditor(text: $vm.body)
            .font(.body)
            .padding(12)
            .frame(minHeight: 240)
    }

    private var isIdle: Bool {
        guard case .idle = vm.sendState else { return false }
        return true
    }
}

private struct ComposeField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
            TextField("", text: $text)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
