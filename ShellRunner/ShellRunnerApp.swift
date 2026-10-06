import SwiftUI
import SwiftData

@main
struct ShellRunnerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([SavedCommand.self, CommandRun.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        // Register saved hotkeys at launch so they work even if the main window
        // is never opened (menu bar only).
        let container = sharedModelContainer
        Task { @MainActor in
            HotkeyBindingCoordinator.shared.start(container: container)
        }
    }

    var body: some Scene {
        // Main management window: browse/edit/run saved commands, view history.
        WindowGroup(id: "main") {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .windowResizability(.contentSize)

        // Menu bar quick-launcher: click the terminal icon to run favorites
        // without opening the main window.
        MenuBarExtra("ShellRunner", image: "MenuBarIcon") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
        .modelContainer(sharedModelContainer)
    }
}
