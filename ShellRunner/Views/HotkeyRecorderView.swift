import SwiftUI
import AppKit
import SwiftData

/// A small control that, when clicked, listens for the next keystroke and
/// stores it as a global hotkey binding on the given command.
struct HotkeyRecorderView: View {
    @Bindable var command: SavedCommand

    @State private var isRecording = false
    @State private var localMonitor: Any?

    var body: some View {
        HStack {
            Text(label)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(isRecording ? .orange : .primary)

            Button(isRecording ? "Press keys…" : "Set Hotkey") {
                startRecording()
            }
            .disabled(isRecording)

            if command.hotkeyKeyCode != nil {
                Button("Clear") { clear() }
                    .foregroundStyle(.red)
            }
        }
        .onDisappear { stopRecording() }
    }

    private var label: String {
        guard let keyCode = command.hotkeyKeyCode else { return "No hotkey set" }
        let mods = NSEvent.ModifierFlags(rawValue: UInt(command.hotkeyModifiers ?? 0))
        return "\(modifierSymbols(mods))\(keyName(for: keyCode))"
    }

    private func startRecording() {
        isRecording = true
        HotkeyManager.shared.isSuspended = true
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])

            // Escape cancels without changing anything.
            if event.keyCode == 53 && mods.isEmpty {
                stopRecording()
                return nil
            }
            // Require ⌘, ⌥ or ⌃ so a hotkey can't swallow ordinary typing.
            guard !mods.intersection([.command, .option, .control]).isEmpty else {
                NSSound.beep()
                return nil
            }

            command.hotkeyKeyCode = Int(event.keyCode)
            command.hotkeyModifiers = Int(mods.rawValue)
            stopRecording()
            HotkeyBindingCoordinator.shared.reregister(command)
            return nil // swallow the event so it doesn't propagate elsewhere
        }
    }

    private func stopRecording() {
        isRecording = false
        HotkeyManager.shared.isSuspended = false
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func clear() {
        HotkeyBindingCoordinator.shared.unregister(command)
        command.hotkeyKeyCode = nil
        command.hotkeyModifiers = nil
    }

    private func modifierSymbols(_ mods: NSEvent.ModifierFlags) -> String {
        var s = ""
        if mods.contains(.control) { s += "⌃" }
        if mods.contains(.option) { s += "⌥" }
        if mods.contains(.shift) { s += "⇧" }
        if mods.contains(.command) { s += "⌘" }
        return s
    }

    private func keyName(for keyCode: Int) -> String {
        // Minimal mapping for common keys; extend as needed.
        let map: [Int: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 5: "G", 4: "H", 38: "J", 40: "K", 37: "L",
            15: "R", 17: "T", 16: "Y", 32: "U", 34: "I", 31: "O", 35: "P",
            12: "Q", 13: "W", 14: "E", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 45: "N", 46: "M",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            36: "Return", 49: "Space", 48: "Tab", 51: "Delete", 53: "Escape"
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }
}
