import SwiftUI
import SwiftData

struct CommandDetailView: View {
    @Bindable var command: SavedCommand

    @State private var showingVariablesSheet = false
    @State private var showingEditSheet = false
    @State private var showingHistory = false
    @State private var historySelection: CommandRun?
    @State private var pendingInput: String = ""
    private var router = AppRouter.shared
    @Environment(\.modelContext) private var modelContext

    /// One runner per command, shared via the store, so output survives switching away.
    private var runner: ProcessRunner { RunnerStore.shared.runner(for: command) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            GroupBox("Command") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(command.command)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    if let dir = command.workingDirectory, !dir.isEmpty {
                        Text("cwd: \(dir)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !command.variableNames.isEmpty {
                        Text("Variables: \(command.variableNames.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            GroupBox("Output") {
                ScrollView {
                    Text(runner.output.isEmpty ? "No output yet." : runner.output)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(runner.output.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(6)
                }
                .frame(minHeight: 220)
                .background(Color.black.opacity(0.85))
            }

            if runner.isRunning {
                HStack {
                    TextField("Type a response and press Return…", text: $pendingInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit {
                            guard !pendingInput.isEmpty else { return }
                            runner.sendInput(pendingInput)
                            pendingInput = ""
                        }
                    Button("Send") {
                        guard !pendingInput.isEmpty else { return }
                        runner.sendInput(pendingInput)
                        pendingInput = ""
                    }
                }
                Text("Sends text to the running command's input, as if typed in a terminal.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let exitCode = runner.exitCode {
                HStack {
                    Image(systemName: exitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(exitCode == 0 ? .green : .red)
                    Text(exitCode == 0 ? "Succeeded" : "Exited with code \(exitCode)")
                        .font(.caption)
                }
            }

            historySection

            Spacer()
        }
        .padding()
        .toolbar {
            ToolbarItem {
                Button {
                    showingEditSheet = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
        }
        .onAppear { consumePendingRun() }
        .onChange(of: router.pendingRunID) { _, _ in consumePendingRun() }
        .sheet(isPresented: $showingEditSheet) {
            AddEditCommandView(existing: command) { _ in }
        }
        .sheet(isPresented: $showingHistory) {
            RunHistoryView(command: command, initialSelection: historySelection)
        }
        .sheet(isPresented: $showingVariablesSheet) {
            RunVariablesSheet(command: command) { resolvedCommand in
                startRun(resolvedText: resolvedCommand)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(command.name)
                .font(.title2.bold())
            Spacer()
            if runner.isRunning {
                Button(role: .destructive) {
                    runner.cancel()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
            } else {
                Button {
                    if command.variableNames.isEmpty {
                        startRun(resolvedText: command.command)
                    } else {
                        showingVariablesSheet = true
                    }
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private var historySection: some View {
        GroupBox {
            let recent = command.runs.sorted { $0.startedAt > $1.startedAt }.prefix(5)
            if recent.isEmpty {
                Text("No runs yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(4)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(recent), id: \.persistentModelID) { run in
                        Button {
                            historySelection = run
                            showingHistory = true
                        } label: {
                            RunRow(run: run)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
            }
        } label: {
            HStack {
                Text("Recent Runs")
                Spacer()
                Button("View All (\(command.runs.count))") {
                    historySelection = nil
                    showingHistory = true
                }
                .buttonStyle(.link)
                .font(.caption)
                .disabled(command.runs.isEmpty)
            }
        }
    }

    /// If a hotkey/menu bar item asked to run this command, open the variables sheet.
    private func consumePendingRun() {
        guard router.pendingRunID == command.persistentModelID else { return }
        router.pendingRunID = nil
        if !runner.isRunning { showingVariablesSheet = true }
    }

    private func startRun(resolvedText: String) {
        command.lastRunAt = Date()
        let run = CommandRun(resolvedCommandText: resolvedText, command: command)
        modelContext.insert(run)

        runner.onFinish = { code, output in
            run.finishedAt = Date()
            run.exitCode = code
            run.output = output
        }
        runner.run(command: resolvedText, workingDirectory: command.workingDirectory)
    }
}
