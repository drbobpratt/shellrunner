import SwiftUI

struct RunVariablesSheet: View {
    let command: SavedCommand
    var onRun: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Fill in variables for \"\(command.name)\"")
                .font(.title3.bold())

            Form {
                ForEach(command.variableNames, id: \.self) { variable in
                    TextField(variable, text: binding(for: variable))
                }
            }

            Text(previewCommand)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Run") {
                    onRun(command.resolvedCommand(with: values))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(command.variableNames.contains { (values[$0] ?? "").isEmpty })
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var previewCommand: String {
        command.resolvedCommand(with: values)
    }

    private func binding(for variable: String) -> Binding<String> {
        Binding(
            get: { values[variable] ?? "" },
            set: { values[variable] = $0 }
        )
    }
}
