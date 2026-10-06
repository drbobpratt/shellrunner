import SwiftUI
import SwiftData

struct MenuBarView: View {
    @Query(filter: #Predicate<SavedCommand> { $0.isFavorite == true })
    private var favorites: [SavedCommand]

    @Query private var allCommands: [SavedCommand]
    @Environment(\.openWindow) private var openWindow

    @Environment(\.modelContext) private var modelContext

    @State private var runningCommandID: PersistentIdentifier?
    @State private var runner = ProcessRunner()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ShellRunner")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 10)

            Divider().padding(.top, 6)

            if favorites.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No favorites yet")
                        .foregroundStyle(.secondary)
                    Text("Star a command in the main window to pin it here.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(favorites) { cmd in
                            quickRunRow(cmd)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 240)
            }

            if !runner.output.isEmpty {
                Divider()
                ScrollView {
                    Text(runner.output)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 120)
                .background(Color.black.opacity(0.85))
            }

            Divider()

            HStack {
                Button("Open ShellRunner") { showMainWindow() }
                .buttonStyle(.plain)
                .font(.caption)

                Spacer()

                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 280)
    }

    @ViewBuilder
    private func quickRunRow(_ cmd: SavedCommand) -> some View {
        Button {
            if cmd.variableNames.isEmpty {
                execute(cmd)
            } else {
                // Variables need the main window's prompt UI.
                AppRouter.shared.pendingRunID = cmd.persistentModelID
                showMainWindow()
            }
        } label: {
            HStack {
                Image(systemName: runningCommandID == cmd.id ? "circle.dotted" : "play.fill")
                    .foregroundStyle(runningCommandID == cmd.id ? .orange : .accentColor)
                Text(cmd.name)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(cmd.variableNames.isEmpty ? cmd.command : "Opens the main window to fill in variables")
    }

    /// Reuses the existing main window instead of opening a duplicate each time.
    private func showMainWindow() {
        if !MainWindow.bringToFront() {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func execute(_ cmd: SavedCommand) {
        guard !runner.isRunning else { return }
        runningCommandID = cmd.id
        cmd.lastRunAt = Date()

        // Record the run in history, same as the main window does.
        let run = CommandRun(resolvedCommandText: cmd.command, command: cmd)
        modelContext.insert(run)

        runner.onFinish = { code, output in
            run.finishedAt = Date()
            run.exitCode = code
            run.output = output
            runningCommandID = nil
        }
        runner.run(command: cmd.command, workingDirectory: cmd.workingDirectory)
    }
}
