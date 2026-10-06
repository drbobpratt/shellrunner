import Foundation
import SwiftData

@Model
final class SavedCommand {
    var name: String
    var command: String
    var workingDirectory: String?
    var folder: String?
    var isFavorite: Bool
    var createdAt: Date
    var lastRunAt: Date?
    var hotkeyKeyCode: Int?      // raw virtual key code, optional global hotkey
    var hotkeyModifiers: Int?    // raw NSEvent.ModifierFlags

    @Relationship(deleteRule: .cascade, inverse: \CommandRun.command)
    var runs: [CommandRun] = []

    init(
        name: String,
        command: String,
        workingDirectory: String? = nil,
        folder: String? = nil,
        isFavorite: Bool = false
    ) {
        self.name = name
        self.command = command
        self.workingDirectory = workingDirectory
        self.folder = folder
        self.isFavorite = isFavorite
        self.createdAt = Date()
    }

    static let placeholderPattern = #"\{([a-zA-Z0-9_]+)\}"#

    /// Finds `{placeholder}` tokens in a command string, in order, without duplicates,
    /// e.g. "git checkout {branch}" -> ["branch"]
    static func variableNames(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: placeholderPattern) else { return [] }
        let ns = text as NSString
        var names: [String] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: match.range(at: 1))
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    var variableNames: [String] { Self.variableNames(in: command) }

    /// Quotes a value so the shell treats it as one literal word. Plain values
    /// (letters, digits, and `_-./:@%+=,`) are left bare so previews stay readable
    /// and `"{branch}"` still works when the user already wrapped it in quotes.
    static func shellQuote(_ value: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./:@%+=,")
        if !value.isEmpty, value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Substitutes `{placeholder}` tokens with shell-quoted values in a single pass
    /// (so a value containing "{other}" is never re-expanded). Placeholders with no
    /// supplied value are left as-is.
    ///
    /// Note: don't wrap a placeholder in your own quotes if the value may contain
    /// spaces or special characters; the value is quoted for you.
    func resolvedCommand(with values: [String: String]) -> String {
        guard let regex = try? NSRegularExpression(pattern: Self.placeholderPattern) else { return command }
        let ns = command as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: command, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let name = ns.substring(with: match.range(at: 1))
            if let value = values[name] {
                result += Self.shellQuote(value)
            } else {
                result += ns.substring(with: match.range)
            }
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }
}
