import SwiftUI
import SwiftData
import AppKit

struct AddEditCommandView: View {
    let existing: SavedCommand?
    var onSave: (SavedCommand) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var command: String = ""
    @State private var workingDirectory: String = ""
    @State private var folder: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(existing == nil ? "New Command" : "Edit Command")
                .font(.title3.bold())

            Form {
                TextField("Name", text: $name)
                TextField("Command", text: $command)
                    .font(.system(.body, design: .monospaced))
                TextField("Working Directory (optional)", text: $workingDirectory)
                TextField("Folder (optional, for grouping)", text: $folder)

                if !parsedVariables.isEmpty {
                    Text("Detected variables: \(parsedVariables.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("Use {placeholder} syntax in the command, e.g. git checkout {branch}")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let existing {
                    HotkeyRecorderView(command: existing)
                }
            }

            HStack {
                Button("Choose Directory…") { pickDirectory() }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty ||
                              command.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear(perform: populateIfEditing)
    }

    private var parsedVariables: [String] {
        SavedCommand.variableNames(in: command)
    }

    private func populateIfEditing() {
        guard let existing else { return }
        name = existing.name
        command = existing.command
        workingDirectory = existing.workingDirectory ?? ""
        folder = existing.folder ?? ""
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory = url.path
        }
    }

    private func save() {
        if let existing {
            existing.name = name
            existing.command = command
            existing.workingDirectory = workingDirectory.isEmpty ? nil : workingDirectory
            existing.folder = folder.isEmpty ? nil : folder
            onSave(existing)
        } else {
            let newCommand = SavedCommand(
                name: name,
                command: command,
                workingDirectory: workingDirectory.isEmpty ? nil : workingDirectory,
                folder: folder.isEmpty ? nil : folder
            )
            modelContext.insert(newCommand)
            onSave(newCommand)
        }
        dismiss()
    }
}
