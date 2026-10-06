import AppKit

/// Registers keyboard shortcuts that fire both when ShellRunner is in the background
/// (global monitor) and when it's focused (local monitor). The global monitor
/// requires the user to grant "Input Monitoring" in System Settings > Privacy &
/// Security the first time it's installed.
final class HotkeyManager {
    static let shared = HotkeyManager()

    /// Set to true while the hotkey recorder is capturing a keystroke, so that
    /// pressing an existing combo while recording doesn't trigger its command.
    var isSuspended = false

    private var globalMonitor: Any?
    private var localMonitor: Any?
    /// Maps "keyCode-modifierFlags" -> handler
    private var handlers: [String: @MainActor () -> Void] = [:]

    private init() {
        // Fires when another app is frontmost. Cannot swallow the event.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handle(event)
        }
        // Fires when ShellRunner is frontmost. Returning nil swallows a matched
        // hotkey so it doesn't also type into a text field.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            (self?.handle(event) ?? false) ? nil : event
        }
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    func register(keyCode: Int, modifiers: NSEvent.ModifierFlags, action: @escaping @MainActor () -> Void) {
        handlers[key(keyCode: keyCode, modifiers: modifiers)] = action
    }

    func unregister(keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        handlers.removeValue(forKey: key(keyCode: keyCode, modifiers: modifiers))
    }

    /// Returns true if the event matched a registered hotkey.
    private func handle(_ event: NSEvent) -> Bool {
        guard !isSuspended else { return false }
        let relevantFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let mods = event.modifierFlags.intersection(relevantFlags)
        guard let action = handlers[key(keyCode: Int(event.keyCode), modifiers: mods)] else { return false }
        // Holding the keys down shouldn't launch the command repeatedly.
        if !event.isARepeat {
            Task { @MainActor in action() }
        }
        return true
    }

    private func key(keyCode: Int, modifiers: NSEvent.ModifierFlags) -> String {
        "\(keyCode)-\(modifiers.rawValue)"
    }
}
