import SwiftUI
import SwiftData
import AppKit

/// Sheet listing every saved run of a command. Select a run to see the exact
/// command that was executed and its full captured output.
struct RunHistoryView: View {
    let command: SavedCommand

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selection: CommandRun?
    @State private var confirmingClear = false

    init(command: SavedCommand, initialSelection: CommandRun? = nil) {
        self.command = command
        _selection = State(initialValue: initialSelection)
    }

    private var runs: [CommandRun] {
        command.runs.sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("History: \(command.name)")
                    .font(.title3.bold())
                Spacer()
                Button("Clear All…", role: .destructive) { confirmingClear = true }
                    .disabled(runs.filter(canDelete).isEmpty)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)

            Divider()

            if runs.isEmpty {
                ContentUnavailableView("No Runs Yet", systemImage: "clock.arrow.circlepath")
            } else {
                HSplitView {
                    List(selection: $selection) {
                        ForEach(runs) { run in
                            RunRow(run: run)
                                .tag(run)
                                .contextMenu {
                                    Button("Delete", role: .destructive) { delete(run) }
                                        .disabled(!canDelete(run))
                                }
                        }
                    }
                    .frame(minWidth: 220, idealWidth: 250, maxWidth: 320)

                    Group {
                        if let selection {
                            RunOutputView(run: selection)
                        } else {
                            ContentUnavailableView("Select a Run", systemImage: "text.alignleft")
                        }
                    }
                    .frame(minWidth: 380)
                }
            }
        }
        .frame(width: 780, height: 520)
        .confirmationDialog(
            "Delete all history for \"\(command.name)\"?",
            isPresented: $confirmingClear
        ) {
            Button("Delete All Runs", role: .destructive) { clearAll() }
        } message: {
            Text("This can't be undone.")
        }
    }

    /// Don't delete the run that's still being written to by a live process.
    private func canDelete(_ run: CommandRun) -> Bool {
        let isLive = !run.isFinished
            && run.persistentModelID == runs.first?.persistentModelID
            && RunnerStore.shared.runner(for: command).isRunning
        return !isLive
    }

    private func delete(_ run: CommandRun) {
        guard canDelete(run) else { return }
        if selection == run { selection = nil }
        modelContext.delete(run)
    }

    private func clearAll() {
        selection = nil
        for run in runs where canDelete(run) {
            modelContext.delete(run)
        }
    }
}

/// One line in a run list: status icon, start time, and duration.
struct RunRow: View {
    let run: CommandRun

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(run.startedAt.formatted(date: .abbreviated, time: .standard))
                    .font(.caption)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var icon: String {
        if !run.isFinished { return "circle.dotted" }
        return run.didSucceed ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var color: Color {
        if !run.isFinished { return .secondary }
        return run.didSucceed ? .green : .red
    }

    private var subtitle: String {
        guard run.isFinished else { return "Unfinished" }
        let seconds = String(format: "%.1fs", run.duration ?? 0)
        return run.didSucceed ? seconds : "exit \(run.exitCode ?? -1) · \(seconds)"
    }
}

/// Full detail for a single run: the command as executed, metadata, and output.
struct RunOutputView: View {
    let run: CommandRun

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(run.resolvedCommandText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

            HStack(spacing: 12) {
                Text(run.startedAt.formatted(date: .complete, time: .standard))
                if let duration = run.duration {
                    Text(String(format: "%.2fs", duration))
                }
                if let code = run.exitCode {
                    Text("exit \(code)")
                        .foregroundStyle(code == 0 ? .green : .red)
                } else {
                    Text("unfinished")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ScrollView {
                Text(run.output.isEmpty ? "No output." : run.output)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(run.output.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .background(Color.black.opacity(0.85))

            HStack {
                Button("Copy Command") { copy(run.resolvedCommandText) }
                Button("Copy Output") { copy(run.output) }
                    .disabled(run.output.isEmpty)
            }
        }
        .padding(12)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
