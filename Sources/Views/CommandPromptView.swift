import SwiftUI

/// Quick popup that collects a command's parameters (reason, mask, duration,
/// level, …) before sending.
struct CommandPromptView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let prompt: CommandPrompt
    @State private var fields: [CommandField]

    init(prompt: CommandPrompt) {
        self.prompt = prompt
        _fields = State(initialValue: prompt.fields)
    }

    private var valid: Bool {
        fields.allSatisfy { !$0.required || !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(prompt.title).font(.headline)
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, prompt.note.isEmpty ? 12 : 4)
            if !prompt.note.isEmpty {
                Text(prompt.note).font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.bottom, 10)
            }
            Divider()

            Form {
                ForEach($fields) { $field in
                    switch field.kind {
                    case .choice(let options):
                        Picker(field.label, selection: $field.value) {
                            ForEach(options, id: \.self) { Text($0).tag($0) }
                        }
                    default:
                        LabeledContent(field.label) {
                            TextField(field.label, text: $field.value, prompt: Text(field.prompt))
                                .labelsHidden().textFieldStyle(.roundedBorder)
                                .frame(minWidth: 220)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Send") {
                    model.sendCommandPrompt(prompt, fields: fields)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!valid)
            }
            .padding(12)
        }
        .frame(width: 420)
    }
}
