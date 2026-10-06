import AppKit
import SwiftData
import Observation

/// Cross-window requests. When a hotkey (or menu bar item) needs the main window,
/// for example to ask for `{variable}` values, it leaves a request here.
@Observable
final class AppRouter {
    static let shared = AppRouter()
    private init() {}

    /// A command the main window should select and show the variables sheet for.
    var pendingRunID: PersistentIdentifier?
}

enum MainWindow {
    /// Brings the existing main window forward. Returns false if there isn't one.
    static func bringToFront() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else { return false }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        return true
    }
}

/// Keeps the shared HotkeyManager in sync with each command's saved hotkey, and
/// runs the command when its hotkey fires.
final class HotkeyBindingCoordinator {
    static let shared = HotkeyBindingCoordinator()
    private init() {}

    private var container: ModelContainer?
    /// The combo currently registered for each command, so changing or clearing a
    /// hotkey removes the old one.
    private var bindings: [PersistentIdentifier: (keyCode: Int, modifiers: NSEvent.ModifierFlags)] = [:]

    /// Call once at app launch so hotkeys work even if the main window is never opened.
    @MainActor
    func start(container: ModelContainer) {
        self.container = container
        let commands = (try? container.mainContext.fetch(FetchDescriptor<SavedCommand>())) ?? []
        registerAll(commands)
    }

    func registerAll(_ commands: [SavedCommand]) {
        for command in commands { reregister(command) }
    }

    /// (Re)binds a command's current hotkey, removing any previous binding first.
    func reregister(_ command: SavedCommand) {
        // Make sure the command has a permanent ID before we capture it.
        try? command.modelContext?.save()
        let id = command.persistentModelID
        removeBinding(for: id)

        guard let keyCode = command.hotkeyKeyCode else { return }
        let mods = NSEvent.ModifierFlags(rawValue: UInt(command.hotkeyModifiers ?? 0))
        bindings[id] = (keyCode, mods)
        HotkeyManager.shared.register(keyCode: keyCode, modifiers: mods) { [weak self] in
            self?.trigger(id)
        }
    }

    /// Removes a command's hotkey (call when clearing it or deleting the command).
    func unregister(_ command: SavedCommand) {
        removeBinding(for: command.persistentModelID)
    }

    private func removeBinding(for id: PersistentIdentifier) {
        if let old = bindings.removeValue(forKey: id) {
            HotkeyManager.shared.unregister(keyCode: old.keyCode, modifiers: old.modifiers)
        }
    }

    @MainActor
    private func trigger(_ id: PersistentIdentifier) {
        guard let container else { return }
        let context = container.mainContext

        // Look the command up fresh each time rather than holding a model object,
        // so a deleted command can't be touched.
        var descriptor = FetchDescriptor<SavedCommand>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        guard let command = try? context.fetch(descriptor).first else {
            removeBinding(for: id)
            return
        }

        // Commands with {variables} need input, so hand off to the main window.
        if !command.variableNames.isEmpty {
            AppRouter.shared.pendingRunID = id
            if !MainWindow.bringToFront() {
                // No window exists (e.g. it was closed); relaunching reopens it.
                NSWorkspace.shared.open(Bundle.main.bundleURL)
            }
            return
        }

        let runner = RunnerStore.shared.runner(for: command)
        guard !runner.isRunning else {
            NSSound.beep()
            return
        }

        command.lastRunAt = Date()
        let run = CommandRun(resolvedCommandText: command.command, command: command)
        context.insert(run)

        runner.onFinish = { code, output in
            run.finishedAt = Date()
            run.exitCode = code
            run.output = output
            // No window to show the result in, so give audible feedback.
            NSSound(named: code == 0 ? "Glass" : "Basso")?.play()
        }
        runner.run(command: command.command, workingDirectory: command.workingDirectory)
    }
}
