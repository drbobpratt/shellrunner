import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedCommand: SavedCommand?
    @State private var showingAddSheet = false
    @Query private var allCommands: [SavedCommand]
    private var router = AppRouter.shared

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedCommand, showingAddSheet: $showingAddSheet)
        } detail: {
            if let selectedCommand {
                CommandDetailView(command: selectedCommand)
            } else {
                ContentUnavailableView(
                    "No Command Selected",
                    systemImage: "terminal",
                    description: Text("Select a saved command, or add a new one with the + button.")
                )
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .sheet(isPresented: $showingAddSheet) {
            AddEditCommandView(existing: nil) { newCommand in
                selectedCommand = newCommand
            }
        }
        .onAppear { selectPendingCommand() }
        .onChange(of: router.pendingRunID) { _, _ in selectPendingCommand() }
    }

    /// A hotkey or menu bar item asked to run a command that needs variable values:
    /// select it so its detail view can show the variables sheet.
    private func selectPendingCommand() {
        guard let id = router.pendingRunID,
              let command = allCommands.first(where: { $0.persistentModelID == id }) else { return }
        selectedCommand = command
    }
}
